package audiotagutil

// Builders for small, valid files of every format, so the tests and the fuzz
// corpus need no binary fixtures. Each takes the fields a test varies.

import (
	"bytes"
	"encoding/base64"
	"encoding/binary"
	"unicode/utf16"
)

func be16(n uint16) []byte { return binary.BigEndian.AppendUint16(nil, n) }
func be32(n uint32) []byte { return binary.BigEndian.AppendUint32(nil, n) }
func le16(n uint16) []byte { return binary.LittleEndian.AppendUint16(nil, n) }
func le32(n uint32) []byte { return binary.LittleEndian.AppendUint32(nil, n) }
func le64(n uint64) []byte { return binary.LittleEndian.AppendUint64(nil, n) }

func cat(parts ...[]byte) []byte { return bytes.Join(parts, nil) }

// fakeJPEG is enough of a JPEG for content sniffing.
func fakeJPEG(seed byte) []byte {
	return cat([]byte{0xFF, 0xD8, 0xFF, 0xE0, 0, 16, 'J', 'F', 'I', 'F', 0}, bytes.Repeat([]byte{seed}, 64), []byte{0xFF, 0xD9})
}

// ---- ID3v2.3 and MP3 ----

type id3Frame struct {
	id   string
	data []byte
}

func id3Text(id, text string) id3Frame { return id3Frame{id, cat([]byte{0}, []byte(text))} }

func id3APIC(picType byte, mime string, data []byte) id3Frame {
	return id3Frame{"APIC", cat([]byte{0}, []byte(mime), []byte{0, picType, 0}, data)}
}

func syncsafe(n int) []byte {
	return []byte{byte(n>>21) & 0x7F, byte(n>>14) & 0x7F, byte(n>>7) & 0x7F, byte(n) & 0x7F}
}

func id3v23(frames ...id3Frame) []byte {
	var body []byte
	for _, f := range frames {
		body = cat(body, []byte(f.id), be32(uint32(len(f.data))), []byte{0, 0}, f.data)
	}
	return cat([]byte("ID3\x03\x00\x00"), syncsafe(len(body)), body)
}

// mp3Header is MPEG-1 layer III, 128 kbit/s, 44.1 kHz, joint stereo: 417-byte frames.
var mp3Header = []byte{0xFF, 0xFB, 0x90, 0x40}

const mp3FrameLen = 417

// mp3Frames is count frames; with xing > 0 the first one is an Info frame
// declaring that many frames.
func mp3Frames(count int, xing uint32) []byte {
	var out []byte
	for i := range count {
		frame := make([]byte, mp3FrameLen)
		copy(frame, mp3Header)
		if i == 0 && xing > 0 {
			copy(frame[36:], cat([]byte("Xing"), be32(1), be32(xing)))
		}
		out = append(out, frame...)
	}
	return out
}

func id3v1(title string) []byte {
	t := make([]byte, 128)
	copy(t, "TAG")
	copy(t[3:33], title)
	t[127] = 255
	return t
}

// ---- FLAC ----

func flacBlock(typ byte, last bool, body []byte) []byte {
	if last {
		typ |= 0x80
	}
	return cat([]byte{typ, byte(len(body) >> 16), byte(len(body) >> 8), byte(len(body))}, body)
}

func streamInfo(samples uint64, rate uint32) []byte {
	b := make([]byte, 34)
	copy(b, cat(be16(4096), be16(4096)))
	packed := uint64(rate)<<44 | uint64(1)<<41 | uint64(15)<<36 | samples
	binary.BigEndian.PutUint64(b[10:18], packed)
	return b
}

func vorbisComment(comments ...string) []byte {
	out := cat(le32(4), []byte("test"), le32(uint32(len(comments))))
	for _, c := range comments {
		out = cat(out, le32(uint32(len(c))), []byte(c))
	}
	return out
}

// pictureBlock is a FLAC picture block whose data length field says
// declared, followed by data.
func pictureBlock(picType uint32, mime string, declared uint32, data []byte) []byte {
	return cat(be32(picType), be32(uint32(len(mime))), []byte(mime), be32(0), make([]byte, 16), be32(declared), data)
}

// picture3 is a well-formed front-cover picture block.
func picture3(mime string, data []byte) []byte {
	return pictureBlock(3, mime, uint32(len(data)), data)
}

func flacFile(samples uint64, rate uint32, blocks ...[]byte) []byte {
	out := cat([]byte("fLaC"), flacBlock(0, len(blocks) == 0, streamInfo(samples, rate)))
	for i, b := range blocks {
		b = append([]byte(nil), b...)
		if i == len(blocks)-1 {
			b[0] |= 0x80
		}
		out = append(out, b...)
	}
	return append(out, make([]byte, 64)...)
}

func pictureComment(block []byte) string {
	return "METADATA_BLOCK_PICTURE=" + base64.StdEncoding.EncodeToString(block)
}

// ---- Ogg ----

var oggTable = func() (t [256]uint32) {
	for i := range t {
		crc := uint32(i) << 24
		for range 8 {
			if crc&0x80000000 != 0 {
				crc = crc<<1 ^ 0x04C11DB7
			} else {
				crc <<= 1
			}
		}
		t[i] = crc
	}
	return t
}()

// oggPage wraps one whole packet (under 64 KiB) in a page.
func oggPage(serial, seq uint32, flags byte, granule uint64, packet []byte) []byte {
	var sizes []byte
	n := len(packet)
	for ; n >= 255; n -= 255 {
		sizes = append(sizes, 255)
	}
	sizes = append(sizes, byte(n))
	page := cat([]byte("OggS"), []byte{0, flags}, le64(granule), le32(serial), le32(seq), le32(0), []byte{byte(len(sizes))}, sizes, packet)
	var crc uint32
	for _, b := range page {
		crc = crc<<8 ^ oggTable[byte(crc>>24)^b]
	}
	binary.LittleEndian.PutUint32(page[22:26], crc)
	return page
}

func vorbisID(rate uint32) []byte {
	return cat([]byte("\x01vorbis"), le32(0), []byte{2}, le32(rate), le32(0), le32(128000), le32(0), []byte{0xB8, 1})
}

func oggVorbisFile(rate uint32, samples uint64, comments ...string) []byte {
	return cat(
		oggPage(7, 0, 2, 0, vorbisID(rate)),
		oggPage(7, 1, 0, 0, cat([]byte("\x03vorbis"), vorbisComment(comments...), []byte{1})),
		oggPage(7, 2, 4, samples, make([]byte, 200)),
	)
}

func opusFile(preSkip uint16, samples uint64, comments ...string) []byte {
	head := cat([]byte("OpusHead"), []byte{1, 2}, le16(preSkip), le32(48000), le16(0), []byte{0})
	return cat(
		oggPage(9, 0, 2, 0, head),
		oggPage(9, 1, 0, 0, cat([]byte("OpusTags"), vorbisComment(comments...))),
		oggPage(9, 2, 4, samples+uint64(preSkip), make([]byte, 200)),
	)
}

// ---- MP4 ----

func atom(name string, body ...[]byte) []byte {
	b := cat(body...)
	return cat(be32(uint32(8+len(b))), []byte(name), b)
}

func dataAtom(class uint32, payload []byte) []byte {
	return atom("data", be32(class), be32(0), payload)
}

func textItem(name, text string) []byte { return atom(name, dataAtom(1, []byte(text))) }

func mvhd(scale, units uint32) []byte {
	return atom("mvhd", make([]byte, 12), be32(scale), be32(units), make([]byte, 80))
}

func m4aFile(scale, units uint32, items ...[]byte) []byte {
	meta := atom("meta", be32(0), atom("hdlr", make([]byte, 25)), atom("ilst", items...))
	return cat(
		atom("ftyp", []byte("M4A "), be32(0), []byte("M4A isom")),
		atom("moov", mvhd(scale, units), atom("udta", meta)),
		atom("mdat", make([]byte, 128)),
	)
}

// ---- WAV ----

func riffChunk(id string, body []byte) []byte {
	out := cat([]byte(id), le32(uint32(len(body))), body)
	if len(body)%2 == 1 {
		out = append(out, 0)
	}
	return out
}

func wavFmt(byteRate uint32) []byte {
	return riffChunk("fmt ", cat(le16(1), le16(1), le32(byteRate), le32(byteRate), le16(1), le16(8)))
}

func wavFile(chunks ...[]byte) []byte {
	body := cat(chunks...)
	return cat([]byte("RIFF"), le32(uint32(4+len(body))), []byte("WAVE"), body)
}

// ---- ASF ----

func utf16z(s string) []byte {
	var out []byte
	for _, u := range utf16.Encode([]rune(s)) {
		out = append(out, le16(u)...)
	}
	return append(out, 0, 0)
}

func asfObject(guid []byte, body ...[]byte) []byte {
	b := cat(body...)
	return cat(guid, le64(uint64(24+len(b))), b)
}

func asfFileProps(play100ns, prerollMS uint64) []byte {
	return asfObject(asfFileProperties, make([]byte, 40), le64(play100ns), le64(0), le64(prerollMS), le32(2), make([]byte, 12))
}

func asfContent(title, author string) []byte {
	t, a := utf16z(title), utf16z(author)
	return asfObject(asfContentDescription, le16(uint16(len(t))), le16(uint16(len(a))), le16(0), le16(0), le16(0), t, a)
}

type asfDescriptor struct {
	name  string
	kind  uint16
	value []byte
}

func asfExtended(ds ...asfDescriptor) []byte {
	out := le16(uint16(len(ds)))
	for _, d := range ds {
		n := utf16z(d.name)
		out = cat(out, le16(uint16(len(n))), n, le16(d.kind), le16(uint16(len(d.value))), d.value)
	}
	return asfObject(asfExtendedDescription, out)
}

func asfPictureValue(picType byte, mime string, data []byte) []byte {
	return cat([]byte{picType}, le32(uint32(len(data))), utf16z(mime), utf16z(""), data)
}

func asfFile(objects ...[]byte) []byte {
	body := cat(objects...)
	header := cat(asfHeaderGUID, le64(uint64(30+len(body))), le32(uint32(len(objects))), []byte{1, 2}, body)
	data := cat([]byte{0x36, 0x26, 0xB2, 0x75, 0x8E, 0x66, 0xCF, 0x11, 0xA6, 0xD9, 0x00, 0xAA, 0x00, 0x62, 0xCE, 0x6C}, le64(50), make([]byte, 26))
	return cat(header, data)
}

// ---- ADTS ----

// adtsFrames is count AAC-LC frames at 44.1 kHz, each frameLen bytes.
func adtsFrames(count, frameLen int) []byte {
	var out []byte
	for range count {
		f := make([]byte, frameLen)
		copy(f, []byte{0xFF, 0xF1, 0x50, 0x80 | byte(frameLen>>11)&3, byte(frameLen >> 3), byte(frameLen&7)<<5 | 0x1F, 0xFC})
		out = append(out, f...)
	}
	return out
}

// corpus is one valid file of every format, the fuzz seeds.
func corpus() map[string][]byte {
	return map[string][]byte{
		"mp3":   cat(id3v23(id3Text("TIT2", "Song"), id3APIC(3, "image/jpeg", fakeJPEG(1))), mp3Frames(4, 100)),
		"mp3v1": cat(mp3Frames(4, 0), id3v1("Old")),
		"flac":  flacFile(44100, 44100, flacBlock(4, false, vorbisComment("TITLE=Song")), flacBlock(6, false, picture3("image/jpeg", fakeJPEG(2)))),
		"ogg":   oggVorbisFile(44100, 441000, "TITLE=Song", pictureComment(picture3("image/png", []byte("\x89PNG")))),
		"opus":  opusFile(312, 48000, "TITLE=Song"),
		"m4a":   m4aFile(1000, 5000, textItem("\xa9nam", "Song"), atom("covr", dataAtom(13, fakeJPEG(3)))),
		"wav":   wavFile(wavFmt(1000), riffChunk("LIST", cat([]byte("INFO"), riffChunk("INAM", []byte("Song\x00")))), riffChunk("data", make([]byte, 100))),
		"wma":   asfFile(asfFileProps(60_000_000, 3000), asfContent("Song", "Band"), asfExtended(asfDescriptor{"WM/Picture", asfBytes, asfPictureValue(3, "image/jpeg", fakeJPEG(4))})),
		"aac":   adtsFrames(8, 200),
	}
}
