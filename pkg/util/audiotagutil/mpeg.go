package audiotagutil

import (
	"encoding/binary"
	"io"
	"time"

	"github.com/dhowden/tag"
)

// maxSyncScan is how far past the ID3v2 tag the first frame is looked for.
const maxSyncScan = 64 << 10

// maxADTSFrames is how many ADTS frames are averaged for the estimate.
const maxADTSFrames = 64

var (
	mpeg1Bitrates = [3][16]int{ // layer I, II, III; kbit/s
		{0, 32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448, 0},
		{0, 32, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384, 0},
		{0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0},
	}
	mpeg2Bitrates = [3][16]int{ // MPEG-2 and 2.5
		{0, 32, 48, 56, 64, 80, 96, 112, 128, 144, 160, 176, 192, 224, 256, 0},
		{0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0},
		{0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0},
	}
	adtsSampleRates = [16]int{96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050, 16000, 12000, 11025, 8000, 7350}
)

// readMPEG reads an MP3 or a raw ADTS AAC file: the ID3v2 tag at the front,
// or failing that the ID3v1 tag at the end, and the duration from the first
// frame.
func readMPEG(src io.ReaderAt, size int64) (parsed, error) {
	var found parsed
	audioStart := int64(0)
	head := make([]byte, 10)
	if err := readFull(src, 0, head); err == nil && string(head[0:3]) == "ID3" {
		n := id3v2Len(head)
		if n > MaxTagBytes || n > size {
			return parsed{}, ErrTagTooLarge
		}
		var err error
		if found, err = libraryTags(src, 0, n, tag.ReadID3v2Tags); err != nil {
			return parsed{}, err
		}
		audioStart = n
	}
	audioEnd := size
	if size-audioStart >= 128 {
		trailer := make([]byte, 3)
		if err := readFull(src, size-128, trailer); err == nil && string(trailer) == "TAG" {
			audioEnd = size - 128
			if audioStart == 0 {
				var err error
				if found, err = libraryTags(src, size-128, 128, tag.ReadID3v1Tags); err != nil {
					return parsed{}, err
				}
			}
		}
	}
	found.tags.Duration, found.tags.DurationExact = mpegDuration(src, audioStart, audioEnd)
	return found, nil
}

// id3v2Len is the whole length of the ID3v2 tag whose 10-byte header is h,
// header and footer included.
func id3v2Len(h []byte) int64 {
	n := int64(h[6]&0x7F)<<21 | int64(h[7]&0x7F)<<14 | int64(h[8]&0x7F)<<7 | int64(h[9]&0x7F)
	n += 10
	if h[5]&0x10 != 0 {
		n += 10
	}
	return n
}

// mpegDuration finds the first frame after start and reads the duration from
// it: exact from a Xing, Info or VBRI header, estimated from the bitrate
// otherwise, and estimated from the average frame for ADTS.
func mpegDuration(src io.ReaderAt, start, end int64) (dur time.Duration, exact bool) {
	window := min(end-start, maxSyncScan+2048)
	if window < 4 {
		return 0, false
	}
	buf := make([]byte, window)
	n, _ := src.ReadAt(buf, start)
	buf = buf[:n]
	for i := 0; i+4 <= len(buf) && i < maxSyncScan; i++ {
		if buf[i] != 0xFF || buf[i+1]&0xE0 != 0xE0 {
			continue
		}
		if buf[i+1]&0xF6 == 0xF0 {
			if d, ok := adtsDuration(src, start+int64(i), end); ok {
				return d, false
			}
			continue
		}
		h, ok := parseMPEGHeader(buf[i:])
		if !ok {
			continue
		}
		// A lone 0xFFE is common inside an ID3 picture or junk; insist the
		// next frame starts where this one says it ends, when it is in view.
		if next := i + h.frameLen; next+4 <= len(buf) {
			if _, ok := parseMPEGHeader(buf[next:]); !ok {
				continue
			}
		}
		if d, ok := vbrDuration(buf[i:], h); ok {
			return d, true
		}
		d, _ := estimateDuration(end-start-int64(i), float64(h.bitrate)/8)
		return d, false
	}
	return 0, false
}

// parseMPEGHeader decodes the four-byte frame header at the front of b.
func parseMPEGHeader(b []byte) (mpegHeader, bool) {
	if len(b) < 4 || b[0] != 0xFF || b[1]&0xE0 != 0xE0 {
		return mpegHeader{}, false
	}
	version := (b[1] >> 3) & 3 // 0: 2.5, 1: reserved, 2: 2, 3: 1
	layerBits := (b[1] >> 1) & 3
	bitrateIdx := b[2] >> 4
	rateIdx := (b[2] >> 2) & 3
	if version == 1 || layerBits == 0 || bitrateIdx == 0 || bitrateIdx == 15 || rateIdx == 3 {
		return mpegHeader{}, false
	}
	h := mpegHeader{mpeg1: version == 3, layer: 4 - int(layerBits), mono: b[3]>>6 == 3}
	rate := [3]int{44100, 48000, 32000}[rateIdx]
	table := &mpeg1Bitrates
	switch version {
	case 2:
		rate /= 2
		table = &mpeg2Bitrates
	case 0:
		rate /= 4
		table = &mpeg2Bitrates
	}
	h.sampleRate = rate
	h.bitrate = table[h.layer-1][bitrateIdx] * 1000
	pad := int(b[2]>>1) & 1
	switch {
	case h.layer == 1:
		h.samplesPerFrame = 384
		h.frameLen = (12*h.bitrate/rate + pad) * 4
	case h.layer == 3 && !h.mpeg1:
		h.samplesPerFrame = 576
		h.frameLen = 72*h.bitrate/rate + pad
	default:
		h.samplesPerFrame = 1152
		h.frameLen = 144*h.bitrate/rate + pad
	}
	return h, h.frameLen > 4
}

// vbrDuration reads the frame count from a Xing or Info header (layer III,
// after the side information) or a VBRI header (32 bytes in) in the frame at
// the front of b.
func vbrDuration(b []byte, h mpegHeader) (time.Duration, bool) {
	frames := uint32(0)
	if h.layer == 3 {
		side := 32
		switch {
		case h.mpeg1 && h.mono:
			side = 17
		case !h.mpeg1 && h.mono:
			side = 9
		case !h.mpeg1:
			side = 17
		}
		if x := b[min(4+side, len(b)):]; len(x) >= 12 && (string(x[:4]) == "Xing" || string(x[:4]) == "Info") {
			if binary.BigEndian.Uint32(x[4:8])&1 != 0 {
				frames = binary.BigEndian.Uint32(x[8:12])
			}
		}
	}
	if v := b[min(36, len(b)):]; frames == 0 && len(v) >= 18 && string(v[:4]) == "VBRI" {
		frames = binary.BigEndian.Uint32(v[14:18])
	}
	return samplesDuration(uint64(frames)*uint64(h.samplesPerFrame), uint64(h.sampleRate))
}

// adtsDuration estimates a raw AAC stream's length from the average size of
// its first frames. ADTS carries no total, so the result is approximate.
func adtsDuration(src io.ReaderAt, start, end int64) (time.Duration, bool) {
	var hdr [7]byte
	var bytes, samples int64
	rate := 0
	off := start
	for range maxADTSFrames {
		if off+7 > end || readFull(src, off, hdr[:]) != nil {
			break
		}
		if hdr[0] != 0xFF || hdr[1]&0xF6 != 0xF0 {
			break
		}
		r := adtsSampleRates[(hdr[2]>>2)&0x0F]
		frameLen := int64(hdr[3]&3)<<11 | int64(hdr[4])<<3 | int64(hdr[5]>>5)
		if r == 0 || frameLen < 7 || (rate != 0 && r != rate) {
			break
		}
		rate = r
		bytes += frameLen
		samples += 1024 * int64(hdr[6]&3+1)
		off += frameLen
	}
	if bytes == 0 {
		return 0, false
	}
	return estimateDuration(end-start, float64(bytes)/float64(samples)*float64(rate))
}
