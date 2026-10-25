"""Image -> 3D mesh on the owner's ComfyUI (native nodes).

  hunyuan  Hunyuan3D 2.1: geometry only (no texture module in native ComfyUI). Licence excludes the EU:
           prototypes only, never ship without re-checking the licence.
  trellis  TRELLIS.2 (MIT): geometry + baked PBR texture (base colour, metallic, roughness), decimated, UV-unwrapped.

    python tools/comfy/mesh3d.py trellis --out art_src/mesh --name charon --faces 60000 path/to/input.png

The input is cut out with BiRefNet and cropped to the subject inside the graph. Each run saves <name>.glb and a
preview render <name>_render.png. Run all jobs of one model family, then `comfy.py free` before switching.
"""
import argparse
import json
import os
import sys
import time
import urllib.parse

sys.path.insert(0, os.path.dirname(__file__))
import comfy  # noqa: E402

TRELLIS_UNET = "hy3d\\trellis_2_int8_convrot.safetensors"
TRELLIS_SHAPE_VAE = "hy3d\\trellis_2_shape_vae_bf16.safetensors"
TRELLIS_TEX_VAE = "hy3d\\trellis_2_texture_vae_bf16.safetensors"
DINO = "hy3d\\dino_v3_L_naf_fp32.safetensors"
BIREFNET = "hy3d\\birefnet.safetensors"
HUNYUAN = "hunyuan3d\\hunyuan_3d_v2.1.safetensors"


def _prep(wf: dict, image: str, bg: str) -> list:
    """LoadImage -> BiRefNet mask -> crop to subject (1024^2, 10% margin). Returns the image ref."""
    wf["p1"] = {"class_type": "LoadImage", "inputs": {"image": image}}
    wf["p2"] = {"class_type": "LoadBackgroundRemovalModel", "inputs": {"bg_removal_name": BIREFNET}}
    wf["p3"] = {"class_type": "RemoveBackground", "inputs": {"bg_removal_model": ["p2", 0], "image": ["p1", 0]}}
    wf["p4"] = {"class_type": "ImageCropToMask", "inputs": {"images": ["p1", 0], "masks": ["p3", 0], "width": 1024,
                                                             "height": 1024, "pad_factor": 1.1, "grow_mask": 0,
                                                             "background": bg}}
    wf["p5"] = {"class_type": "SaveImage", "inputs": {"images": ["p4", 0], "filename_prefix": "dantes3d_in"}}
    return ["p4", 0]


def _finish(wf: dict, mesh: list, name: str, mode: str) -> None:
    wf["s1"] = {"class_type": "SaveGLB", "inputs": {"mesh": mesh, "filename_prefix": "dantes3d/" + name}}
    wf["s2"] = {"class_type": "RenderMesh", "inputs": {"mesh": mesh, "mode": mode, "width": 1024, "height": 1024,
                                                        "background": "#2a2a2a"}}
    wf["s3"] = {"class_type": "SaveImage", "inputs": {"images": ["s2", 0], "filename_prefix": "dantes3d_render"}}


def workflow_hunyuan(image: str, name: str, seed: int, faces: int, octree: int = 256) -> dict:
    wf = {}
    img = _prep(wf, image, "#FFFFFF")
    wf.update({
        "1": {"class_type": "ImageOnlyCheckpointLoader", "inputs": {"ckpt_name": HUNYUAN}},
        "3": {"class_type": "ModelSamplingAuraFlow", "inputs": {"model": ["1", 0], "shift": 1.0}},
        "13": {"class_type": "CLIPVisionEncode", "inputs": {"clip_vision": ["1", 1], "image": img, "crop": "center"}},
        "6": {"class_type": "Hunyuan3Dv2Conditioning", "inputs": {"clip_vision_output": ["13", 0]}},
        "4": {"class_type": "EmptyLatentHunyuan3Dv2", "inputs": {"resolution": 4096, "batch_size": 1}},
        "7": {"class_type": "KSampler", "inputs": {"model": ["3", 0], "positive": ["6", 0], "negative": ["6", 1],
                                                    "latent_image": ["4", 0], "seed": seed, "steps": 30, "cfg": 5.0,
                                                    "sampler_name": "euler", "scheduler": "normal", "denoise": 1.0}},
        "8": {"class_type": "VAEDecodeHunyuan3D", "inputs": {"samples": ["7", 0], "vae": ["1", 2], "num_chunks": 8000,
                                                              "octree_resolution": octree}},
        "9": {"class_type": "VoxelToMesh", "inputs": {"voxel": ["8", 0], "algorithm": "surface net", "threshold": 0.6}},
        "10": {"class_type": "DecimateMesh", "inputs": {"mesh": ["9", 0], "target_face_count": faces,
                                                         "placement_mode": "midpoint"}},
        "11": {"class_type": "MeshSmoothNormals", "inputs": {"mesh": ["10", 0], "crease_angle": 180.0}},
    })
    _finish(wf, ["11", 0], name, "solid")
    return wf


def workflow_trellis(image: str, name: str, seed: int, faces: int, tex: int, upsample: int = 1536) -> dict:
    """Mirror of the official 3d_pixal3d_trellis2_image_to_model template (TRELLIS.2 branch)."""
    wf = {}
    img = _prep(wf, image, "#000000")
    wf.update({
        "40": {"class_type": "UNETLoader", "inputs": {"unet_name": TRELLIS_UNET, "weight_dtype": "default"}},
        "117": {"class_type": "VAELoader", "inputs": {"vae_name": TRELLIS_SHAPE_VAE}},
        "118": {"class_type": "VAELoader", "inputs": {"vae_name": TRELLIS_TEX_VAE}},
        "15": {"class_type": "CLIPVisionLoader", "inputs": {"clip_name": DINO}},
        "299": {"class_type": "Trellis2Conditioning", "inputs": {"clip_vision_model": ["15", 0], "image": img}},
        # CFG override + rescale match the original pipeline defaults.
        "279": {"class_type": "CFGOverride", "inputs": {"model": ["40", 0], "cfg": 1.0, "start_percent": 0.769, "end_percent": 1.0}},
        "126": {"class_type": "RescaleCFG", "inputs": {"model": ["279", 0], "multiplier": 0.5}},
        "199": {"class_type": "CFGOverride", "inputs": {"model": ["40", 0], "cfg": 1.0, "start_percent": 0.667, "end_percent": 1.0}},
        "125": {"class_type": "RescaleCFG", "inputs": {"model": ["199", 0], "multiplier": 0.7}},
        "108": {"class_type": "ModelSamplingSD3", "inputs": {"model": ["125", 0], "shift": 5.0}},
        "87": {"class_type": "EmptyTrellis2LatentStructure", "inputs": {"batch_size": 1}},
        "3": {"class_type": "KSampler", "inputs": {"model": ["108", 0], "positive": ["299", 0], "negative": ["299", 1],
                                                    "latent_image": ["87", 0], "seed": seed, "steps": 12, "cfg": 7.5,
                                                    "sampler_name": "euler", "scheduler": "normal", "denoise": 1.0}},
        "119": {"class_type": "VaeDecodeStructureTrellis2", "inputs": {"samples": ["3", 0], "vae": ["117", 0], "resolution": "32"}},
        "91": {"class_type": "Trellis2ShapeStage", "inputs": {"positive": ["299", 0], "negative": ["299", 1], "voxel": ["119", 0]}},
        "18": {"class_type": "KSampler", "inputs": {"model": ["126", 0], "positive": ["91", 0], "negative": ["91", 1],
                                                     "latent_image": ["91", 2], "seed": seed + 1, "steps": 20, "cfg": 7.5,
                                                     "sampler_name": "euler", "scheduler": "normal", "denoise": 1.0}},
        "94": {"class_type": "Trellis2UpsampleStage", "inputs": {"positive": ["91", 0], "negative": ["91", 1],
                                                                  "shape_latent": ["18", 0], "vae": ["117", 0],
                                                                  "target_resolution": upsample}},
        "23": {"class_type": "KSampler", "inputs": {"model": ["126", 0], "positive": ["94", 0], "negative": ["94", 1],
                                                     "latent_image": ["94", 2], "seed": seed + 2, "steps": 12, "cfg": 7.5,
                                                     "sampler_name": "euler", "scheduler": "simple", "denoise": 1.0}},
        "92": {"class_type": "VaeDecodeShapeTrellis", "inputs": {"samples": ["23", 0], "vae": ["117", 0]}},
        "98": {"class_type": "Trellis2TextureStage", "inputs": {"positive": ["94", 0], "negative": ["94", 1], "shape_latent": ["23", 0]}},
        "12": {"class_type": "KSampler", "inputs": {"model": ["40", 0], "positive": ["98", 0], "negative": ["98", 1],
                                                     "latent_image": ["98", 2], "seed": seed + 3, "steps": 12, "cfg": 1.0,
                                                     "sampler_name": "euler", "scheduler": "normal", "denoise": 1.0}},
        "93": {"class_type": "VaeDecodeTextureTrellis", "inputs": {"samples": ["12", 0], "vae": ["118", 0], "shape_subdivides": ["92", 1]}},
        # Raw TRELLIS surfaces are a non-manifold double shell: re-extract one clean surface first (as the template).
        "241": {"class_type": "RemeshMesh", "inputs": {"mesh": ["92", 0], "resolution": 768, "sign_mode": "udf",
                                                        "sign_mode.qef": False, "sign_mode.drop_inverted_components": False,
                                                        "sign_mode.drop_enclosed_components": False, "band": 1.0,
                                                        "project_back": 0.0, "fix_poles": False, "smooth_iters": 20,
                                                        "drop_small_components": 0.01, "precluster_max_verts": 20000000}},
        "186": {"class_type": "DecimateMesh", "inputs": {"mesh": ["241", 0], "target_face_count": faces, "placement_mode": "midpoint"}},
        "238": {"class_type": "MeshSmoothNormals", "inputs": {"mesh": ["186", 0], "crease_angle": 180.0}},
        "196": {"class_type": "UnwrapMesh", "inputs": {"mesh": ["238", 0], "segmenter": "pec", "resolution": tex, "padding": 2,
                                                        "weld_distance": 0.0002}},
        "147": {"class_type": "BakeTextureFromVoxel", "inputs": {"mesh": ["196", 0], "voxel_colors": ["93", 0],
                                                                  "texture_size": tex, "reference_mesh": ["92", 0]}},
        "210": {"class_type": "ApplyTextureToMesh", "inputs": {"mesh": ["196", 0], "base_color": ["147", 0],
                                                                "metallic": ["147", 1], "roughness": ["147", 2]}},
    })
    _finish(wf, ["210", 0], name, "texture")
    return wf


def _fetch_outputs(pid: str, out_dir: str, name: str) -> None:
    hist = json.loads(comfy._req("/history/" + pid))[pid]
    for nid, o in hist.get("outputs", {}).items():
        for key, items in o.items():
            if not isinstance(items, list):
                continue
            for it in items:
                if not isinstance(it, dict) or "filename" not in it:
                    continue
                data = comfy._req("/view?" + urllib.parse.urlencode(
                    {"filename": it["filename"], "subfolder": it.get("subfolder", ""), "type": it.get("type", "output")}))
                ext = os.path.splitext(it["filename"])[1]
                suffix = {"s3": "_render", "p5": "_input"}.get(nid, "")
                p = os.path.join(out_dir, f"{name}{suffix}{ext}")
                with open(p, "wb") as f:
                    f.write(data)
                print("saved", p, len(data), "bytes", flush=True)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("model", choices=["hunyuan", "trellis"])
    ap.add_argument("image")
    ap.add_argument("--out", default="art_src/mesh")
    ap.add_argument("--name", default="mesh")
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--faces", type=int, default=60000)
    ap.add_argument("--tex", type=int, default=2048)
    ap.add_argument("--octree", type=int, default=256, help="Hunyuan surface resolution (256-512)")
    ap.add_argument("--upsample", type=int, default=1536, help="TRELLIS.2 shape resolution (1024-2048)")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    server_name = comfy.upload(a.image)
    wf = workflow_hunyuan(server_name, a.name, a.seed, a.faces, a.octree) if a.model == "hunyuan" else \
        workflow_trellis(server_name, a.name, a.seed, a.faces, a.tex, a.upsample)
    t0 = time.time()
    pid = comfy.submit(wf)
    comfy.wait(pid, timeout=3600)
    _fetch_outputs(pid, a.out, a.name)
    print(f"done {a.model} {a.name} in {time.time() - t0:.0f}s", flush=True)


if __name__ == "__main__":
    main()
