"""Minimal ComfyUI client for Dante's Vengeance (owner's PC, RTX 5070, via Tailscale).

Rules (see CLAUDE.md): read the gate file before every submit (first line must be "open"),
one model family at a time (Qwen t2i / Qwen edit / 3D), POST /free when switching family,
<= 4 queued jobs per agent.

    python tools/comfy/comfy.py t2i --out art_src/tests --name gate --seed 1 --w 1664 --h 928 "prompt..."
"""
import argparse
import json
import os
import sys
import time
import urllib.parse
import urllib.request
import uuid

def _server() -> str:
	r"""The owner's ComfyUI URL: env COMFY_URL, else the first line of C:\Servers\comfy_url.txt (kept out of the repo)."""
	if os.environ.get("COMFY_URL"):
		return os.environ["COMFY_URL"]
	with open(r"C:\Servers\comfy_url.txt", encoding="utf-8") as f:
		return f.readline().strip()


SERVER = _server()
GATE = os.environ.get("COMFY_GATE", r"C:\Servers\comfy_gate.txt")
CLIENT_ID = os.environ.get("COMFY_CLIENT", "dantes-" + uuid.uuid4().hex[:6])
MAX_QUEUED = 4

QWEN_UNET = "qwen-image-2512-Q4_K_M.gguf"
QWEN_LORA = "Qwen-Image-2512-Lightning-4steps-V1.0-bf16.safetensors"
QWEN_CLIP = "qwen_2.5_vl_7b_fp8_scaled.safetensors"
QWEN_VAE = "qwen_image_vae.safetensors"
QWEN_DEPTH = "qwen_image_depth_diffsynth_controlnet.safetensors"

# House style: Gustave Doré wood engravings (public domain) as the reference look.
DORE = ("in the style of a 19th century Gustave Dore wood engraving, dense black ink cross-hatching, "
        "dramatic chiaroscuro, sublime romantic composition, monochrome sepia and black ink on aged paper, "
        "extremely detailed linework")
NEGATIVE = "text, letters, watermark, signature, logo, frame, border, blurry, lowres, jpeg artifacts, deformed, cartoon, anime"


LOCK = os.environ.get("COMFY_LOCK", r"C:\Servers\comfy_lock.json")


def acquire(owner: str, family: str, poll: float = 20.0, stale_s: float = 2400.0) -> None:
    """GPU family lock shared by every agent: blocks until the GPU is free or already running `family`.
    Families: "qwen", "qwen-edit", "trellis", "hunyuan", "wan", "audio". Switching family frees the models first.
    Release with release(owner) when your batch is done. A lock untouched for `stale_s` seconds is considered dead."""
    said = False
    while True:
        cur = {}
        try:
            with open(LOCK, encoding="utf-8") as f:
                cur = json.load(f)
        except (OSError, ValueError):
            cur = {}
        mine = cur.get("owner") == owner
        stale = cur and time.time() - float(cur.get("t", 0)) > stale_s
        if not cur or mine or stale:
            if (cur.get("family") != family) and not mine:
                try:
                    if not json.loads(_req("/queue")).get("queue_running"):
                        free()
                except Exception:
                    pass
            elif mine and cur.get("family") != family:
                free()
            with open(LOCK, "w", encoding="utf-8") as f:
                json.dump({"owner": owner, "family": family, "t": time.time()}, f)
            return
        if not said:
            print(f"GPU busy ({cur.get('owner')} / {cur.get('family')}): waiting...", flush=True)
            said = True
        time.sleep(poll)


def touch(owner: str) -> None:
    """Refreshes the lock timestamp during long batches."""
    try:
        with open(LOCK, encoding="utf-8") as f:
            cur = json.load(f)
        if cur.get("owner") == owner:
            cur["t"] = time.time()
            with open(LOCK, "w", encoding="utf-8") as f:
                json.dump(cur, f)
    except (OSError, ValueError):
        pass


def release(owner: str) -> None:
    try:
        with open(LOCK, encoding="utf-8") as f:
            cur = json.load(f)
        if cur.get("owner") == owner:
            os.remove(LOCK)
    except (OSError, ValueError):
        pass


def gate_open() -> bool:
    try:
        with open(GATE, encoding="utf-8") as f:
            return f.readline().strip().lower().startswith("open")
    except OSError:
        return False


def wait_gate(poll: float = 30.0) -> None:
    said = False
    while not gate_open():
        if not said:
            print(f"comfy gate closed ({GATE}): waiting...", flush=True)
            said = True
        time.sleep(poll)


def _req(path: str, data: dict | None = None, timeout: float = 300):
    if path == "/prompt":
        wait_gate()
    body = json.dumps(data).encode() if data is not None else None
    r = urllib.request.Request(SERVER + path, data=body, headers={"Content-Type": "application/json"} if body else {})
    with urllib.request.urlopen(r, timeout=timeout) as f:
        return f.read()


def free() -> None:
    """Unloads models (call with an empty queue before switching model family)."""
    _req("/free", {"unload_models": True, "free_memory": True})


def queued_mine() -> int:
    q = json.loads(_req("/queue"))
    return sum(1 for e in q.get("queue_running", []) + q.get("queue_pending", [])
               if len(e) > 3 and isinstance(e[3], dict) and e[3].get("client_id") == CLIENT_ID)


def upload(path: str) -> str:
    boundary = uuid.uuid4().hex
    with open(path, "rb") as f:
        data = f.read()
    body = (f"--{boundary}\r\nContent-Disposition: form-data; name=\"image\"; filename=\"{os.path.basename(path)}\"\r\n"
            f"Content-Type: image/png\r\n\r\n").encode() + data + \
        f"\r\n--{boundary}\r\nContent-Disposition: form-data; name=\"overwrite\"\r\n\r\ntrue\r\n--{boundary}--\r\n".encode()
    r = urllib.request.Request(SERVER + "/upload/image", data=body,
                               headers={"Content-Type": f"multipart/form-data; boundary={boundary}"})
    with urllib.request.urlopen(r, timeout=120) as f:
        res = json.loads(f.read())
    return (res["subfolder"] + "/" if res.get("subfolder") else "") + res["name"]


def workflow_t2i(prompt: str, seed: int, w: int, h: int, depth_image: str = "", depth_strength: float = 1.0,
                 rmbg: bool = False, lora: str = "", lora_strength: float = 0.8) -> dict:
    """Qwen-Image 2512 + Lightning 4-step; optional DiffSynth depth ControlNet (block-out depth render)."""
    wf = {
        "1": {"class_type": "UnetLoaderGGUF", "inputs": {"unet_name": QWEN_UNET}},
        "2": {"class_type": "LoraLoaderModelOnly", "inputs": {"model": ["1", 0], "lora_name": QWEN_LORA, "strength_model": 1.0}},
        "3": {"class_type": "ModelSamplingAuraFlow", "inputs": {"model": ["2", 0], "shift": 3.1}},
        "4": {"class_type": "CLIPLoader", "inputs": {"clip_name": QWEN_CLIP, "type": "qwen_image"}},
        "5": {"class_type": "VAELoader", "inputs": {"vae_name": QWEN_VAE}},
        "6": {"class_type": "CLIPTextEncode", "inputs": {"text": prompt, "clip": ["4", 0]}},
        "7": {"class_type": "CLIPTextEncode", "inputs": {"text": NEGATIVE, "clip": ["4", 0]}},
        "12": {"class_type": "EmptySD3LatentImage", "inputs": {"width": w, "height": h, "batch_size": 1}},
        "13": {"class_type": "KSampler", "inputs": {"model": ["3", 0], "positive": ["6", 0], "negative": ["7", 0],
                                                     "latent_image": ["12", 0], "seed": seed, "steps": 4, "cfg": 1.0,
                                                     "sampler_name": "euler", "scheduler": "simple", "denoise": 1.0}},
        "8": {"class_type": "VAEDecode", "inputs": {"samples": ["13", 0], "vae": ["5", 0]}},
        "11": {"class_type": "SaveImage", "inputs": {"images": ["8", 0], "filename_prefix": "dantes"}},
    }
    if lora:
        wf["30"] = {"class_type": "LoraLoaderModelOnly", "inputs": {"model": ["2", 0], "lora_name": lora,
                                                                    "strength_model": lora_strength}}
        wf["3"]["inputs"]["model"] = ["30", 0]
    if depth_image:
        wf["20"] = {"class_type": "ModelPatchLoader", "inputs": {"name": QWEN_DEPTH}}
        wf["21"] = {"class_type": "LoadImage", "inputs": {"image": depth_image}}
        wf["22"] = {"class_type": "QwenImageDiffsynthControlnet",
                    "inputs": {"model": ["3", 0], "model_patch": ["20", 0], "vae": ["5", 0], "image": ["21", 0],
                               "strength": depth_strength}}
        wf["13"]["inputs"]["model"] = ["22", 0]
    if rmbg:
        wf["9"] = {"class_type": "BiRefNetRMBG", "inputs": {"image": ["8", 0], "model": "BiRefNet-general",
                                                            "sensitivity": 1.0, "process_res": 1024, "mask_blur": 0,
                                                            "mask_offset": 0, "invert_output": False,
                                                            "refine_foreground": True, "background": "Alpha"}}
        wf["10"] = {"class_type": "SaveImage", "inputs": {"images": ["9", 0], "filename_prefix": "dantes_rgba"}}
    return wf


def workflow_seamfix(prompt: str, seed: int, image: str, mask: str, denoise: float = 0.75) -> dict:
    """Repaints only the masked band of an (already half-shifted) image: makes a texture tile seamlessly."""
    wf = workflow_t2i(prompt, seed, 64, 64)
    del wf["12"]
    wf["40"] = {"class_type": "LoadImage", "inputs": {"image": image}}
    wf["41"] = {"class_type": "LoadImageMask", "inputs": {"image": mask, "channel": "red"}}
    wf["42"] = {"class_type": "VAEEncode", "inputs": {"pixels": ["40", 0], "vae": ["5", 0]}}
    wf["43"] = {"class_type": "SetLatentNoiseMask", "inputs": {"samples": ["42", 0], "mask": ["41", 0]}}
    wf["13"]["inputs"].update({"latent_image": ["43", 0], "denoise": denoise})
    return wf


def seamfix(src: str, out: str, prompt: str, seed: int, band: float = 0.16, denoise: float = 0.75) -> None:
    import numpy as np
    from PIL import Image, ImageFilter
    im = Image.open(src).convert("RGB")
    w, h = im.size
    arr = np.roll(np.roll(np.asarray(im), h // 2, axis=0), w // 2, axis=1)
    tmp = os.path.splitext(out)[0]
    Image.fromarray(arr).save(tmp + "_shift.png")
    m = np.zeros((h, w), np.uint8)
    bw, bh = int(w * band / 2), int(h * band / 2)
    m[:, w // 2 - bw:w // 2 + bw] = 255
    m[h // 2 - bh:h // 2 + bh, :] = 255
    Image.fromarray(m).filter(ImageFilter.GaussianBlur(6)).save(tmp + "_mask.png")
    wf = workflow_seamfix(prompt, seed, upload(tmp + "_shift.png"), upload(tmp + "_mask.png"), denoise)
    data = wait(submit(wf))["11"][0]
    with open(out, "wb") as f:
        f.write(data)
    # The model may drift slightly outside the mask: paste the result only inside the (feathered) mask.
    res = np.asarray(Image.open(out).convert("RGB").resize((w, h))).astype(np.float32)
    k = np.asarray(Image.open(tmp + "_mask.png")).astype(np.float32)[..., None] / 255.0
    Image.fromarray((res * k + arr * (1 - k)).astype(np.uint8)).save(out)
    print("seamless", out, flush=True)


def submit(wf: dict) -> str:
    wait_gate()
    while queued_mine() >= MAX_QUEUED:
        time.sleep(5)
    return json.loads(_req("/prompt", {"prompt": wf, "client_id": CLIENT_ID}))["prompt_id"]


def wait(pid: str, timeout: float = 1800.0) -> dict:
    """Returns {node_id: [bytes, ...]} for every image output of the prompt."""
    t0 = time.time()
    while True:
        hist = json.loads(_req("/history/" + pid)).get(pid)
        if hist:
            st = hist.get("status", {})
            if st.get("status_str") == "error":
                raise RuntimeError(json.dumps(st.get("messages", []))[-1500:])
            if st.get("completed"):
                out = {}
                for nid, o in hist.get("outputs", {}).items():
                    out[nid] = [_req("/view?" + urllib.parse.urlencode(
                        {"filename": i["filename"], "subfolder": i["subfolder"], "type": i["type"]}))
                        for i in o.get("images", [])]
                return out
        if time.time() - t0 > timeout:
            raise TimeoutError(pid)
        time.sleep(1.0)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["t2i", "free", "seamfix"])
    ap.add_argument("--src", default="", help="seamfix: source texture")
    ap.add_argument("prompt", nargs="?", default="")
    ap.add_argument("--out", default="art_src/tests")
    ap.add_argument("--name", default="img")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--w", type=int, default=1328)
    ap.add_argument("--h", type=int, default=1328)
    ap.add_argument("--depth", default="", help="local depth png (ControlNet)")
    ap.add_argument("--depth-strength", type=float, default=1.0)
    ap.add_argument("--rmbg", action="store_true")
    ap.add_argument("--dore", action="store_true", help="append the Dore engraving house style")
    ap.add_argument("--lora", default="", help="extra Qwen LoRA, e.g. qwen-image_3drenderstyle_redmond.safetensors")
    ap.add_argument("--lora-strength", type=float, default=0.8)
    a = ap.parse_args()
    if a.mode == "free":
        free()
        return
    if a.mode == "seamfix":
        os.makedirs(a.out, exist_ok=True)
        seamfix(a.src, os.path.join(a.out, a.name + ".png"), a.prompt, a.seed)
        return
    prompt = a.prompt + (", " + DORE if a.dore else "")
    depth = upload(a.depth) if a.depth else ""
    t0 = time.time()
    pid = submit(workflow_t2i(prompt, a.seed, a.w, a.h, depth, a.depth_strength, a.rmbg,
                                  a.lora, a.lora_strength))
    out = wait(pid)
    os.makedirs(a.out, exist_ok=True)
    for nid, suffix in (("11", ""), ("10", "_rgba")):
        for i, data in enumerate(out.get(nid, [])):
            p = os.path.join(a.out, f"{a.name}{suffix}.png")
            with open(p, "wb") as f:
                f.write(data)
            print("saved", p, f"{time.time() - t0:.0f}s", flush=True)


if __name__ == "__main__":
    sys.exit(main())
