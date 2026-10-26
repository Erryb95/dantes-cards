"""Uploads an arena's blockout passes to the ComfyUI PC as paintover inputs (POST /upload/image only).

  python tools/arena/upload_blockout.py <arena> [<arena> ...]      # e.g. limbo lust dis cocytus
  python tools/arena/upload_blockout.py --dry-run limbo

Reads art_src/arena/blockout_<arena>/board_<pass>.png (made by tools/blender/board_blockout.py --arena=<arena> and
tools/arena/passes.py) and uploads each as input/<arena>_bo_board_<pass>.png, overwriting the previous upload.
Passes: id, clay, depth, lineart, normal (2560x1440). It never queues a job or touches the queue / GPU.
The server URL is read from C:\\Servers\\comfy_url.txt (never written into the repo).
"""
import json
import os
import sys
import urllib.request
import uuid

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
URL_FILE = r"C:\Servers\comfy_url.txt"
PASSES = ("id", "clay", "depth", "lineart", "normal")
SIZE = (2560, 1440)


def png_size(data: bytes) -> tuple:
    return int.from_bytes(data[16:20], "big"), int.from_bytes(data[20:24], "big")


def upload(base: str, name: str, data: bytes) -> dict:
    boundary = uuid.uuid4().hex
    parts = []
    for field, value in (("type", "input"), ("overwrite", "true")):
        parts.append(('--%s\r\nContent-Disposition: form-data; name="%s"\r\n\r\n%s\r\n'
                      % (boundary, field, value)).encode())
    parts.append(('--%s\r\nContent-Disposition: form-data; name="image"; filename="%s"\r\n'
                  'Content-Type: image/png\r\n\r\n' % (boundary, name)).encode() + data + b"\r\n")
    body = b"".join(parts) + ("--%s--\r\n" % boundary).encode()
    req = urllib.request.Request(base + "/upload/image", data=body, method="POST",
                                 headers={"Content-Type": "multipart/form-data; boundary=" + boundary})
    with urllib.request.urlopen(req, timeout=120) as r:
        return json.loads(r.read().decode() or "{}")


def main(args: list) -> int:
    dry = "--dry-run" in args
    arenas = [a for a in args if not a.startswith("--")]
    if not arenas:
        print(__doc__)
        return 2
    base = open(URL_FILE, encoding="utf-8").readline().strip().rstrip("/")
    failed = 0
    for arena in arenas:
        d = os.path.join(ROOT, "art_src", "arena", "blockout_" + arena)
        for p in PASSES:
            src = os.path.join(d, "board_%s.png" % p)
            name = "%s_bo_board_%s.png" % (arena, p)
            if not os.path.exists(src):
                print("MISSING", src)
                failed += 1
                continue
            data = open(src, "rb").read()
            if png_size(data) != SIZE:
                print("WRONG SIZE", src, png_size(data))
                failed += 1
                continue
            if dry:
                print("would upload", name, len(data), "bytes")
                continue
            try:
                res = upload(base, name, data)
                print("uploaded", name, "->", res.get("subfolder", ""), res.get("name", ""), res.get("type", ""))
            except Exception as e:  # noqa: BLE001 - report and go on with the others
                print("FAILED", name, type(e).__name__, str(e).replace(base, "<comfy>"))
                failed += 1
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
