"""Batch helper for art assets: holds the shared GPU lock ("art", one family) while it runs a list of jobs.

  python tools/comfy/art.py t2i jobs.json      # [{"name","prompt","seed","w","h","depth","depth_strength","lora","lora_strength","rmbg"}]
  python tools/comfy/art.py trellis in.png --name x --out dir --faces 80000 --tex 4096 --upsample 2048 [--seed N]

Qwen jobs use family "qwen", TRELLIS jobs family "trellis" (comfy.acquire frees the models on a family switch).
"""
import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(__file__))
import comfy  # noqa: E402
import mesh3d  # noqa: E402

OWNER = "dantescards-art"


def run_t2i(jobs: list, out_dir: str) -> None:
    comfy.acquire(OWNER, "qwen")
    try:
        os.makedirs(out_dir, exist_ok=True)
        for j in jobs:
            t0 = time.time()
            depth = comfy.upload(j["depth"]) if j.get("depth") else ""
            wf = comfy.workflow_t2i(j["prompt"], j.get("seed", 1), j.get("w", 928), j.get("h", 1664), depth,
                                    j.get("depth_strength", 1.0), j.get("rmbg", False), j.get("lora", ""),
                                    j.get("lora_strength", 0.7))
            out = comfy.wait(comfy.submit(wf))
            for nid, suffix in (("11", ""), ("10", "_rgba")):
                for data in out.get(nid, []):
                    p = os.path.join(out_dir, j["name"] + suffix + ".png")
                    with open(p, "wb") as f:
                        f.write(data)
                    print("saved", p, f"{time.time() - t0:.0f}s", flush=True)
            comfy.touch(OWNER)
    finally:
        comfy.release(OWNER)


def run_trellis(image: str, out: str, name: str, faces: int, tex: int, upsample: int, seed: int) -> None:
    comfy.acquire(OWNER, "trellis")
    try:
        os.makedirs(out, exist_ok=True)
        server_name = comfy.upload(image)
        wf = mesh3d.workflow_trellis(server_name, name, seed, faces, tex, upsample)
        t0 = time.time()
        pid = comfy.submit(wf)
        comfy.wait(pid, timeout=3600)
        mesh3d._fetch_outputs(pid, out, name)
        print(f"done trellis {name} in {time.time() - t0:.0f}s", flush=True)
    finally:
        comfy.release(OWNER)


if __name__ == "__main__":
    mode = sys.argv[1]
    if mode == "t2i":
        jobs = json.load(open(sys.argv[2], encoding="utf-8"))
        run_t2i(jobs, os.path.dirname(os.path.abspath(sys.argv[2])))
    elif mode == "trellis":
        import argparse
        ap = argparse.ArgumentParser()
        ap.add_argument("mode")
        ap.add_argument("image")
        ap.add_argument("--out", default="art_src/mesh")
        ap.add_argument("--name", default="mesh")
        ap.add_argument("--faces", type=int, default=80000)
        ap.add_argument("--tex", type=int, default=4096)
        ap.add_argument("--upsample", type=int, default=2048)
        ap.add_argument("--seed", type=int, default=42)
        a = ap.parse_args()
        run_trellis(a.image, a.out, a.name, a.faces, a.tex, a.upsample, a.seed)
