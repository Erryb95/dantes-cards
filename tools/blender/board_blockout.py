"""3D blockout of the Acheron board for a studio-style paintover (run headless in Blender 5.x).

  blender.exe -b -P tools/blender/board_blockout.py -- <out_dir> [width height]

A tilted perspective camera looks at the board like a table (about 55 degrees elevation). Every socket is placed by
casting a ray from the camera through its on-screen layout position (1920x1080 units, the same numbers the game
uses in battle_view.gd), so the painted sockets land exactly under the heroes, decks and buttons.

Writes into <out_dir>:
  board_clay.png    grey clay render with shadows and cavity (base for img2img / canny)
  board_depth.png   depth, near = white (Depth-Anything convention, for depth ControlNet and in-game fog)
  board_normal.png  camera-space normals (for Godot 2D lights through CanvasTexture normal maps)
  board_id.png      flat colour per element (to cut the painting into layers)
  props_clay.png / props_id.png   the props alone on transparent background
  ids.json          element name -> ID colour
"""
import json
import math
import os
import sys

import bpy
from mathutils import Vector, noise
from bpy_extras.object_utils import world_to_camera_view

argv = sys.argv[sys.argv.index("--") + 1:]
OUT = os.path.abspath(argv[0])
RES = (int(argv[1]), int(argv[2])) if len(argv) > 2 else (2560, 1440)
os.makedirs(OUT, exist_ok=True)

LAYOUT = (1920.0, 1080.0)
RIVER = (420.0, 524.0)          # screen y band of the Acheron
PLAY_X = (300.0, 1620.0)        # the calm play area between the side cliffs

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.resolution_x, scene.render.resolution_y = RES
scene.render.resolution_percentage = 100

cam_data = bpy.data.cameras.new("cam")
cam_data.lens = 42.0
cam = bpy.data.objects.new("cam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam
cam.location = (0.0, -21.0, 19.0)
cam.rotation_euler = (math.radians(47.0), 0.0, 0.0)
bpy.context.view_layer.update()

IDS = {}
PALETTE = [(0.9, 0.1, 0.1), (0.1, 0.9, 0.1), (0.1, 0.1, 0.9), (0.9, 0.9, 0.1), (0.9, 0.1, 0.9), (0.1, 0.9, 0.9),
           (0.9, 0.5, 0.1), (0.5, 0.1, 0.9), (0.1, 0.5, 0.2), (0.6, 0.6, 0.6), (0.5, 0.3, 0.1), (0.2, 0.2, 0.5),
           (0.9, 0.6, 0.7), (0.4, 0.8, 0.4), (0.3, 0.6, 0.9), (0.8, 0.8, 0.5)]
PROPS = []


def tag(o, name, prop=False):
    if name not in IDS:
        IDS[name] = PALETTE[len(IDS) % len(PALETTE)]
    o.color = (*IDS[name], 1.0)
    o["element"] = name
    if prop:
        PROPS.append(o)
    return o


def screen_ray(gx, gy):
    """World-space ray through the layout point (gx, gy) in 1920x1080 units."""
    frame = cam_data.view_frame(scene=scene)  # top-right, bottom-right, bottom-left, top-left (camera space)
    u, v = gx / LAYOUT[0], 1.0 - gy / LAYOUT[1]
    left = frame[2].lerp(frame[3], v)
    right = frame[1].lerp(frame[0], v)
    p = left.lerp(right, u)
    origin = cam.matrix_world.translation
    return origin, (cam.matrix_world @ p - origin).normalized()


def ground_at(gx, gy, z=0.0):
    o, d = screen_ray(gx, gy)
    t = (z - o.z) / d.z
    return o + d * t


def to_layout(p):
    c = world_to_camera_view(scene, cam, Vector(p))
    return c.x * LAYOUT[0], (1.0 - c.y) * LAYOUT[1]


def smooth(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def height(gx, gy, wx, wy):
    """Terrain height from the on-screen position: calm banks, a sunk river, cliffs at the frame."""
    river = smooth(RIVER[0] - 18, RIVER[0] + 6, gy) * (1.0 - smooth(RIVER[1] - 6, RIVER[1] + 18, gy))
    h = -0.45 * river
    side = max(PLAY_X[0] - gx, gx - PLAY_X[1], 0.0) / 300.0
    top = max(70.0 - gy, 0.0) / 70.0
    cliff = smooth(0.0, 1.0, side) * 2.4 + top * 1.2
    rough = noise.noise(Vector((wx * 0.6, wy * 0.6, 0.0)))
    fine = noise.noise(Vector((wx * 2.5, wy * 2.5, 3.0)))
    play = 1.0 - min(1.0, side * 1.5 + top)
    h += cliff * (1.0 + 0.5 * rough) + (0.03 * rough + 0.015 * fine) * play + (0.35 * rough + 0.12 * fine) * (1.0 - play)
    # The river cuts a gorge through the side cliffs too.
    return h * (1.0 - river) - 0.45 * river


def region(gx, gy):
    if gx < PLAY_X[0] - 40 or gx > PLAY_X[1] + 40 or gy < 40:
        return "cliffs"
    if RIVER[0] - 6 < gy < RIVER[1] + 6:
        return "riverbed"
    return "far_bank" if gy < RIVER[0] else "near_bank"


def build_terrain():
    corners = [ground_at(x, y) for x, y in ((-400, -200), (2320, -200), (2320, 1400), (-400, 1400))]
    xs = [c.x for c in corners]
    ys = [c.y for c in corners]
    nx, ny = 320, 200
    verts, faces = [], []
    for j in range(ny + 1):
        for i in range(nx + 1):
            wx = min(xs) + (max(xs) - min(xs)) * i / nx
            wy = min(ys) + (max(ys) - min(ys)) * j / ny
            gx, gy = to_layout((wx, wy, 0.0))
            verts.append((wx, wy, height(gx, gy, wx, wy)))
    parts = {}
    for j in range(ny):
        for i in range(nx):
            a = j * (nx + 1) + i
            f = (a, a + 1, a + nx + 2, a + nx + 1)
            c = sum((Vector(verts[k]) for k in f), Vector()) / 4
            parts.setdefault(region(*to_layout(c)), []).append(f)
    # One object per region, so the ID pass separates banks, riverbed and cliffs.
    for name, faces in parts.items():
        me = bpy.data.meshes.new(name)
        me.from_pydata(verts, [], faces)
        me.update()
        o = bpy.data.objects.new(name, me)
        scene.collection.objects.link(o)
        for p in me.polygons:
            p.use_smooth = True
        tag(o, name)
    # A flat water sheet in the river bed.
    a, b = ground_at(960, RIVER[0] + 4, -0.38), ground_at(960, RIVER[1] - 4, -0.38)
    l, r = ground_at(-400, 472, -0.38), ground_at(2320, 472, -0.38)
    bpy.ops.mesh.primitive_plane_add(location=(0.0, (a.y + b.y) / 2, -0.38))
    w = bpy.context.object
    w.scale = (abs(r.x - l.x) / 2, abs(b.y - a.y) / 2, 1)
    tag(w, "river")


def radius_at(gx, gy, r_px, z=0.0):
    return (ground_at(gx + r_px, gy, z) - ground_at(gx, gy, z)).length


def disc(name, gx, gy, r_px, h, z=0.0, verts=48, prop=False, sy=1.0):
    p = ground_at(gx, gy, z)
    r = radius_at(gx, gy, r_px, z)
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=h, location=(p.x, p.y, z + h / 2))
    o = bpy.context.object
    o.scale.y = sy
    mod = o.modifiers.new("bevel", "BEVEL")
    mod.width = min(r, h) * 0.25
    mod.segments = 3
    mod.harden_normals = True
    bpy.ops.object.shade_auto_smooth()
    return tag(o, name, prop)


def box(name, gx, gy, w_px, d_px, h, z=0.0, prop=False):
    p = ground_at(gx, gy, z)
    w = radius_at(gx, gy, w_px / 2, z)
    d = (ground_at(gx, gy + d_px / 2, z) - p).length
    bpy.ops.mesh.primitive_cube_add(location=(p.x, p.y, z + h / 2))
    o = bpy.context.object
    o.scale = (w, d, h / 2)
    mod = o.modifiers.new("bevel", "BEVEL")
    mod.width = min(w, d) * 0.15
    mod.segments = 3
    return tag(o, name, prop)


def sockets():
    for name, (gx, gy) in {"hero_plinth_enemy": (960, 150), "hero_plinth_player": (960, 808)}.items():
        disc(name, gx, gy, 132, 0.28)
        disc(name, gx, gy, 118, 0.36)       # raised inner ring
    for name, (gx, gy) in {"power_socket_enemy": (1140, 164), "power_socket_player": (1140, 822)}.items():
        disc(name, gx, gy, 58, 0.18)
    disc("end_turn_socket", 1745, 472, 125, 0.3, z=-0.3, sy=0.55)
    for name, (gx, gy) in {"deck_niche_enemy": (1800, 312), "deck_niche_player": (1800, 632)}.items():
        box(name, gx, gy, 130, 120, 0.25, z=height_at(gx, gy))
    for name, (gx, gy) in {"mana_tray_enemy": (1640, 55), "mana_tray_player": (1640, 1025)}.items():
        box(name, gx, gy, 520, 70, 0.15, z=height_at(gx, gy))


def height_at(gx, gy):
    p = ground_at(gx, gy)
    return height(gx, gy, p.x, p.y)


def scenery():
    """Shapes for the painter to follow: the crowd of souls on the far edge and Charon's landing stage."""
    import random
    rnd = random.Random(7)
    for k in range(70):
        gx = rnd.uniform(380, 1540)
        gy = rnd.uniform(18, 70)
        z = height_at(gx, gy)
        p = ground_at(gx, gy, z)
        hgt = rnd.uniform(0.55, 0.75)
        bpy.ops.mesh.primitive_cylinder_add(radius=0.09, depth=hgt, vertices=8, location=(p.x, p.y, z + hgt / 2))
        tag(bpy.context.object, "souls")
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.08, segments=10, ring_count=6, location=(p.x, p.y, z + hgt + 0.06))
        tag(bpy.context.object, "souls")
    # Landing stage: planks from the far bank into the river, left of the play area.
    for k in range(6):
        gy = 380 + k * 18
        p = ground_at(300, gy, -0.05)
        bpy.ops.mesh.primitive_cube_add(location=(p.x, p.y, -0.05))
        o = bpy.context.object
        o.scale = (0.7, 0.12, 0.05)
        tag(o, "landing_stage")
    for gx in (262, 338):
        p = ground_at(gx, 470, -0.4)
        bpy.ops.mesh.primitive_cylinder_add(radius=0.07, depth=0.9, vertices=8, location=(p.x, p.y, 0.0))
        tag(bpy.context.object, "landing_stage")


def props():
    # Charon's boat on the river.
    p = ground_at(1300, 470, -0.38)
    bpy.ops.mesh.primitive_cube_add(location=(p.x, p.y, -0.2))
    hull = bpy.context.object
    hull.scale = (1.4, 0.45, 0.22)
    tag(hull, "prop_boat", True)
    bpy.ops.mesh.primitive_cone_add(radius1=0.22, radius2=0.08, depth=1.3, location=(p.x - 0.4, p.y, 0.6))
    tag(bpy.context.object, "prop_boat", True)
    # Bell on its gallows.
    z = height_at(165, 290)
    p = ground_at(165, 290, z)
    for dx in (-0.55, 0.55):
        bpy.ops.mesh.primitive_cylinder_add(radius=0.07, depth=2.0, location=(p.x + dx, p.y, z + 1.0))
        tag(bpy.context.object, "prop_bell", True)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.07, depth=1.3, location=(p.x, p.y, z + 2.0), rotation=(0, math.pi / 2, 0))
    tag(bpy.context.object, "prop_bell", True)
    bpy.ops.mesh.primitive_cone_add(radius1=0.38, radius2=0.14, depth=0.6, location=(p.x, p.y, z + 1.55))
    tag(bpy.context.object, "prop_bell", True)
    # The gate inscription tablet.
    z = height_at(170, 682)
    p = ground_at(170, 682, z)
    bpy.ops.mesh.primitive_cube_add(location=(p.x, p.y, z + 0.8), rotation=(math.radians(-20), 0, 0))
    o = bpy.context.object
    o.scale = (0.9, 0.12, 0.75)
    tag(o, "prop_tablet", True)
    # Brazier and skull pile.
    z = height_at(1830, 860)
    p = ground_at(1830, 860, z)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.08, depth=0.9, location=(p.x, p.y, z + 0.45))
    tag(bpy.context.object, "prop_brazier", True)
    bpy.ops.mesh.primitive_cone_add(radius1=0.15, radius2=0.45, depth=0.35, location=(p.x, p.y, z + 1.0))
    tag(bpy.context.object, "prop_brazier", True)
    z = height_at(140, 960)
    p = ground_at(140, 960, z)
    for k in range(9):
        a = k * 2.4
        r = 0.18 + 0.12 * (k % 3)
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.2, location=(p.x + math.cos(a) * r, p.y + math.sin(a) * r * 0.7,
                                                                    z + 0.2 + 0.18 * (k // 3)))
        tag(bpy.context.object, "prop_skulls", True)


def emission_override(kind, zr=(0, 1)):
    mat = bpy.data.materials.new(kind)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(em.outputs[0], out.inputs[0])
    if kind == "depth":
        cd = nt.nodes.new("ShaderNodeCameraData")
        mr = nt.nodes.new("ShaderNodeMapRange")
        mr.inputs["From Min"].default_value = zr[0]
        mr.inputs["From Max"].default_value = zr[1]
        mr.inputs["To Min"].default_value = 1.0
        mr.inputs["To Max"].default_value = 0.0
        nt.links.new(cd.outputs["View Z Depth"], mr.inputs["Value"])
        nt.links.new(mr.outputs["Result"], em.inputs["Color"])
    else:
        geo = nt.nodes.new("ShaderNodeNewGeometry")
        vt = nt.nodes.new("ShaderNodeVectorTransform")
        vt.vector_type = "NORMAL"
        vt.convert_from = "WORLD"
        vt.convert_to = "CAMERA"
        vm = nt.nodes.new("ShaderNodeVectorMath")
        vm.operation = "MULTIPLY_ADD"
        vm.inputs[1].default_value = (0.5, 0.5, -0.5)
        vm.inputs[2].default_value = (0.5, 0.5, 0.5)
        nt.links.new(geo.outputs["Normal"], vt.inputs[0])
        nt.links.new(vt.outputs[0], vm.inputs[0])
        nt.links.new(vm.outputs[0], em.inputs["Color"])
    return mat


def render(path, engine, transparent=False):
    scene.render.engine = engine
    scene.render.film_transparent = transparent
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA" if transparent else "RGB"
    scene.render.filepath = os.path.join(OUT, path)
    bpy.ops.render.render(write_still=True)


def workbench(color_type, flat=False):
    sh = scene.display.shading
    sh.light = "FLAT" if flat else "STUDIO"
    sh.color_type = color_type
    sh.single_color = (0.62, 0.6, 0.57)
    sh.show_cavity = not flat
    sh.show_shadows = False
    sh.shadow_intensity = 0.6
    scene.display.render_aa = "OFF" if flat else "8"


build_terrain()
sockets()
scenery()
props()
scene.view_settings.view_transform = "Standard"

# Board passes (props hidden).
for o in PROPS:
    o.hide_render = True
workbench("SINGLE")
render("board_clay.png", "BLENDER_WORKBENCH")
workbench("OBJECT", flat=True)
render("board_id.png", "BLENDER_WORKBENCH")
scene.cycles.samples = 4
scene.cycles.device = "CPU"
inv = cam.matrix_world.inverted()
dists = [-(inv @ (o.matrix_world @ v.co)).z for o in scene.objects if o.type == "MESH" and not o.hide_render
         for v in list(o.data.vertices)[::7]]
vl = bpy.context.view_layer
vl.material_override = emission_override("depth", (min(dists), max(dists)))
render("board_depth.png", "CYCLES")
vl.material_override = emission_override("normal")
render("board_normal.png", "CYCLES")
vl.material_override = None

# Props alone, on transparent background.
for o in scene.objects:
    if o.type == "MESH":
        o.hide_render = o not in PROPS
workbench("SINGLE")
render("props_clay.png", "BLENDER_WORKBENCH", True)
workbench("OBJECT", flat=True)
render("props_id.png", "BLENDER_WORKBENCH", True)

json.dump({k: [round(c * 255) for c in v] for k, v in IDS.items()}, open(os.path.join(OUT, "ids.json"), "w"), indent=1)
print("BLOCKOUT DONE", OUT)
