"""Keeps only the Vorbis audio of an Ogg file, dropping any other logical stream (a Theora picture track, say).

    python tools/audio/ogg_audio_only.py <in.ogg> <out.ogg>

Some public-domain recordings come as Ogg files that also carry a Theora video stream (the archive's still image).
Godot's Ogg Vorbis importer is fed every page of the file, so the video pages reach the audio decoder and play as
static. This copies the Vorbis stream's pages as they are (no re-encoding, no quality loss).
"""
import sys


def pages(data: bytes):
    i = 0
    while i < len(data):
        if data[i:i + 4] != b"OggS":
            i = data.find(b"OggS", i + 1)
            if i < 0:
                return
            continue
        nseg = data[i + 26]
        body = sum(data[i + 27:i + 27 + nseg])
        end = i + 27 + nseg + body
        yield data[i:end], int.from_bytes(data[i + 14:i + 18], "little"), data[i + 27 + nseg:end]
        i = end


def main() -> None:
    src, dst = sys.argv[1], sys.argv[2]
    data = open(src, "rb").read()
    vorbis = None
    out = bytearray()
    kept = dropped = 0
    for page, serial, body in pages(data):
        if vorbis is None and body.startswith(b"\x01vorbis"):
            vorbis = serial
        if serial == vorbis:
            out += page
            kept += 1
        else:
            dropped += 1
    if vorbis is None:
        sys.exit("no Vorbis stream in " + src)
    open(dst, "wb").write(bytes(out))
    print(f"{src}: kept {kept} Vorbis pages, dropped {dropped} other pages, {len(data)//1024} -> {len(out)//1024} KB")


if __name__ == "__main__":
    main()
