# Video trim and remux playback checklist

<!-- cspell:words aevalsrc demuxers drawbox drawtext fontcolor fontsize keyint libfreetype -->

Clips from `POST /api/v0/videos/trim` and files from a remux (`POST /api/v0/videos/transcode`, the viewer's
Convert action) are cut without re-encoding, by [sprocket](https://github.com/autobutler-org/sprocket). A cut
between two keyframes keeps the frames back to the earlier keyframe, the lead-in, and hides them: an MP4-family
output behind an edit list, Matroska and WebM behind a `CodecDelay`. A TS output cannot hide them and shows
them. Whether a player honors the hiding decides where the clip appears to start, and only playback shows
that. This checklist covers the playback side (#3418); the probe-level end-to-end journey is #3413.

Each clip must:

1. **Start at the requested frame**, or, where the player ignores the hiding, at the keyframe before it. Either
   way the "Clip saved" message, built from the job's `actualStartMs`, must name the time the clip actually
   starts from. A player that shows the lead-in while the message names the requested start is a bug.
2. **Stay in A/V sync** within one AAC frame, about 21 ms at 48 kHz. That is sprocket's documented bound. A
   larger offset is flagged as its own issue, never fixed by re-encoding, which is out of scope by design
   (#2378).
3. **Show the right duration**: the requested end less the start it is shown from, give or take one frame.
   sprocket keeps the last sample at or before the end, so an end that falls exactly on a frame keeps that
   frame and the clip runs one frame long. That is documented behavior, not a failure.

## What is automated

`pkg/util/trimutil/playback_test.go` plays every case below through ffmpeg, as one more player. It generates
its fixture at test time, so nothing binary is committed: four seconds of 24 fps H.264 with a keyframe every
second, where frame `n` is a flat gray of luma `16+2n`, and audio that is silent but for a beep at 2.5 s. It
trims 1.5 s to 3.5 s and reads, from the clip, which source frame is shown first, where the beep lands, and
the container's duration.

| Test                                         | Case                                         | Checks                                                              |
| -------------------------------------------- | -------------------------------------------- | ------------------------------------------------------------------- |
| `TestTrimJobClipsPlayFromTheirReportedStart` | MP4 (AAC), MKV (Opus), MKV (AAC) trim jobs   | `actualStartMs` is the request; first frame, sync, duration         |
| `TestTrimIntoTSPlaysItsLeadIn`               | MP4 trimmed into TS                          | Start is the keyframe (1 s); the clip shows it; sync, duration      |
| `TestRemuxMKVToMP4PlaysInSync`               | MKV (AAC) remuxed to fragmented MP4          | First frame at zero, sync, full duration                            |

Run them with `go test ./pkg/util/trimutil -run Play -v`; the log line of each case prints where its video is
shown from, where its audio is heard from, and how long it lasts. They skip when `ffmpeg` or `ffprobe` is not
on the `PATH`. CI installs no ffmpeg today, so there they skip: run them locally after touching trim, remux, or
the sprocket version.

What the tests found in ffmpeg 9.0 with sprocket v0.2.1. ffmpeg stands in only for players built on it, such
as libmpv on Linux:

- MP4: ffmpeg applies the edit list, so the first frame has timestamp zero and is the requested one.
- MKV: ffmpeg reports the lead-in at negative timestamps (stream start time −0.5 s for this cut). A player that
  starts its clock at zero and drops what comes before shows the requested frame first; one that plays from the
  first timestamp shows the lead-in.
- TS: the clip keeps its source's timestamps (start time 1 s), so a player starts its clock there. The audio
  sits about 19 ms off the video, inside the bound.
- Fragmented MP4 from a remux reads from zero in ffmpeg, in sync, with the audio track about 30 ms longer
  than the video.

ffmpeg passing is not evidence for AVPlayer, ExoPlayer, or a browser. The rest of this checklist is manual.

## Players

| Surface         | Player Quark uses                                          |
| --------------- | ---------------------------------------------------------- |
| iOS             | `video_player`, AVPlayer                                   |
| Android         | `video_player`, ExoPlayer (Media3)                         |
| Web             | `video_player`, the browser's `<video>` element            |
| Desktop (Linux) | `video_player_media_kit`, libmpv (#3151)                   |

On web, run Chrome, Safari, and Firefox: each has its own demuxers. Quark ships no macOS or Windows desktop
build today; add a row when it does.

## Fixture

Generate a ten-second clip whose picture prints its own time and frame number, with a white flash and a beep
for the first 100 ms of every second, and keyframes every two seconds. Any ffmpeg built with `libx264`,
`libfreetype` (for `drawtext`), and `libopus` will do:

```sh
ffmpeg -f lavfi -i "color=c=gray:s=640x360:r=24:d=10,drawtext=text='%{pts\:hms}  frame %{n}':fontsize=40:fontcolor=white:x=20:y=20,drawbox=t=fill:c=white:enable='lt(mod(t\,1)\,0.1)'" \
  -f lavfi -i "aevalsrc='if(lt(mod(t\,1)\,0.1)\,0.5*sin(2*PI*1000*t)\,0)':s=48000:d=10" \
  -c:v libx264 -pix_fmt yuv420p -g 48 -keyint_min 48 -sc_threshold 0 -c:a aac -b:a 128k sync.mp4
ffmpeg -i sync.mp4 -c copy sync.mkv
ffmpeg -i sync.mp4 -c:v copy -c:a libopus sync-opus.mkv
```

Upload all three to a Quark. Keyframes fall at 0, 2, 4, 6, and 8 seconds.

## Cases

Set the range with the viewer's trim bar, or, for exact times, call `POST /api/v0/videos/trim` with
`relPath`, `serial`, `startMs`, and `endMs`. For each case, open the result in Quark's video viewer on every surface and record what the first frame reads
(pause on it, or scrub to zero), whether every flash lands with its beep, and the duration the player shows.

| Case | Source          | Action                                  | Expected first frame       | Expected `actualStartMs` | Expected duration |
| ---- | --------------- | --------------------------------------- | -------------------------- | ------------------------ | ----------------- |
| T1   | `sync.mp4`      | Trim 3.5 s to 7.5 s                     | `00:00:03.500 frame 84`    | 3500                     | 4.0 s             |
| T2   | `sync-opus.mkv` | Trim 3.5 s to 7.5 s                     | `00:00:03.500 frame 84`    | 3500                     | 4.0 s             |
| T3   | `sync.mkv`      | Trim 3.5 s to 7.5 s                     | `00:00:03.500 frame 84`    | 3500                     | 4.0 s             |
| T4   | `sync.mp4`      | Trim 4 s to 7.5 s (on a keyframe)       | `00:00:04.000 frame 96`    | 4000                     | 3.5 s             |
| R1   | `sync.mkv`      | Convert to MP4                          | `00:00:00.000 frame 0`     | n/a                      | 10 s              |
| R2   | `sync-opus.mkv` | Convert to MP4, if offered              | `00:00:00.000 frame 0`     | n/a                      | 10 s              |

A player that ignores the hiding in T1 to T3 shows `00:00:02.000 frame 48` first and lasts 5.5 s; record it
as "keyframe" rather than "fail". The "Clip saved" message names no other start there, since `actualStartMs`
is the request, so that player contradicts it: note it in the cell. Flashes in a trimmed clip fall at the source's whole seconds, 4, 5, 6, and 7, so the first one
comes half a second in when the hiding works and two seconds in when it does not.

The trim-into-TS case is automated only. The trim endpoint writes a clip in its source's own format and cannot
cut a TS source, so the app cannot produce a TS clip today; when it can, add a row whose expected first frame
is the keyframe and whose `actualStartMs` is that keyframe.

T4 starts on a keyframe, has no lead-in, and is the control: a player that fails it has a problem unrelated to
hiding.

## Results

Fill in a cell with **pass**, **keyframe** (shows the lead-in; label and duration then disagree with the
picture), **out of sync** (with the offset you saw), **wrong duration** (with what it showed), or **n/a** (the
player cannot open the container). Record the device, OS, browser, and Quark versions above the table. File
each failure as its own issue that links #3418; do not add a transcoding fallback.

| Case | iOS | Android | Chrome | Safari | Firefox | Linux desktop |
| ---- | --- | ------- | ------ | ------ | ------- | ------------- |
| T1   |     |         |        |        |         |               |
| T2   |     |         |        |        |         |               |
| T3   |     |         |        |        |         |               |
| T4   |     |         |        |        |         |               |
| R1   |     |         |        |        |         |               |
| R2   |     |         |        |        |         |               |

No manual run has been recorded yet.
