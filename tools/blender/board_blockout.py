"""3D blockout of an arena board for a studio-style paintover (run headless in Blender 5.x).

  blender.exe -b -P tools/blender/board_blockout.py -- <out_dir> [width height] [--arena=<id>]

<id> is one of acheron (default), limbo, lust, dis, cocytus (data/arenas.json). Every arena shares the camera and
the sockets (hero plinths, power sockets, end-turn recess, deck niches, mana trays, with the same ID colours); only
the terrain, the scenery on the frame and the props change. The two minion zones stay flat in every arena: the detail
goes to the frame.

A tilted ORTHOGRAPHIC camera looks at the board like a table (55 degrees elevation, no perspective), so a piece
has the same on-screen size and shape wherever it sits: the enemy's sockets render exactly like the player's. Every
socket is placed by casting a (parallel) ray from the camera plane through its on-screen layout position (1920x1080
units across the full render, the same numbers the game uses in battle_view.gd), then nudged so the centre of its
on-screen bounding box lands exactly on that point. The paired sockets (hero plinths, power sockets, deck niches) are
mirrored about the divider (y = 472) and built from the identical mesh; the mana trays share one mesh too but stay
at the top and bottom edges (the player's hand sits at the bottom). The minion zones are perfectly flat in every
arena; the terrain, the scenery and the props only live on the outer frame, and props never show in the board passes.

Writes into <out_dir>:
  board_clay.png    grey clay render with shadows and cavity (base for img2img / canny)
  board_depth.png   depth, near = white (Depth-Anything convention, for depth ControlNet and in-game fog)
  board_normal.png  camera-space normals (for Godot 2D lights through CanvasTexture normal maps)
  board_id.png      flat colour per element (to cut the painting into layers)
  props_clay.png / props_id.png   the props alone on transparent background
  ids.json          element name -> ID colour
Then run tools/arena/passes.py on <out_dir> for the line art, the layout check and the linear normal map.
"""
import json
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector, noise
from bpy_extras.object_utils import world_to_camera_view

argv = sys.argv[sys.argv.index("--") + 1:]
OPTS = dict(a[2:].split("=", 1) for a in argv if a.startswith("--") and "=" in a)
argv = [a for a in argv if not a.startswith("--")]
ARENA = OPTS.get("arena", "acheron")
OUT = os.path.abspath(argv[0])
RES = (int(argv[1]), int(argv[2])) if len(argv) > 2 else (2560, 1440)
os.makedirs(OUT, exist_ok=True)

LAYOUT = (1920.0, 1080.0)
RIVER = (420.0, 524.0)          # screen y band of the Acheron
PLAY_X = (300.0, 1620.0)        # the calm play area between the side cliffs
MID = 472.0                     # screen y of the middle divider (every arena)

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.resolution_x, scene.render.resolution_y = RES
scene.render.resolution_percentage = 100

# Orthographic camera, tilted 35 degrees from straight down (55 degrees elevation), looking at the world origin.
# ORTHO_SCALE world units span the render's width, so 1920 layout units = 24 world units (80 per unit).
CAM_TILT = math.radians(35.0)
ORTHO_SCALE = 24.0
cam_data = bpy.data.cameras.new("cam")
cam_data.type = "ORTHO"
cam_data.ortho_scale = ORTHO_SCALE
cam_data.clip_start = 0.1
cam_data.clip_end = 300.0
cam = bpy.data.objects.new("cam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam
cam.location = (0.0, -80.0 * math.sin(CAM_TILT), 80.0 * math.cos(CAM_TILT))
cam.rotation_euler = (CAM_TILT, 0.0, 0.0)
bpy.context.view_layer.update()

IDS = {}
PALETTE = [(0.9, 0.1, 0.1), (0.1, 0.9, 0.1), (0.1, 0.1, 0.9), (0.9, 0.9, 0.1), (0.9, 0.1, 0.9), (0.1, 0.9, 0.9),
           (0.9, 0.5, 0.1), (0.5, 0.1, 0.9), (0.1, 0.5, 0.2), (0.6, 0.6, 0.6), (0.5, 0.3, 0.1), (0.2, 0.2, 0.5),
           (0.9, 0.6, 0.7), (0.4, 0.8, 0.4), (0.3, 0.6, 0.9), (0.8, 0.8, 0.5)]
# The sockets keep the Acheron's ID colours in every arena (art_src/arena/blockout/ids.json).
SOCKET_IDS = {name: PALETTE[5 + k] for k, name in enumerate((
    "hero_plinth_enemy", "hero_plinth_player", "power_socket_enemy", "power_socket_player", "end_turn_socket",
    "deck_niche_enemy", "deck_niche_player", "mana_tray_enemy", "mana_tray_player"))}
# Terrain and scenery take the remaining colours (the Acheron's order), then these extra ones.
BOARD_IDS = [c for c in PALETTE if c not in SOCKET_IDS.values()] + [
    (0.9, 0.3, 0.5), (0.5, 0.9, 0.9), (0.6, 0.9, 0.1), (0.2, 0.9, 0.5), (0.95, 0.95, 0.95), (0.3, 0.3, 0.3),
    (0.6, 0.3, 0.6)]
_count = {"board": 0, "prop": 0}
PROPS = []


def tag(o, name, prop=False):
    if name not in IDS:
        if name in SOCKET_IDS:
            IDS[name] = SOCKET_IDS[name]
        elif prop:  # props render on their own, so they may reuse board colours
            IDS[name] = PALETTE[_count["prop"] % len(PALETTE)]
            _count["prop"] += 1
        else:
            IDS[name] = BOARD_IDS[_count["board"] % len(BOARD_IDS)]
            _count["board"] += 1
    o.color = (*IDS[name], 1.0)
    o["element"] = name
    if prop:
        PROPS.append(o)
    return o


def screen_ray(gx, gy):
    """World-space ray through the layout point (gx, gy) in 1920x1080 units. The camera is orthographic: every ray
    is parallel to the view axis and starts on the camera plane, at the layout point's place in the view frame."""
    frame = cam_data.view_frame(scene=scene)  # top-right, bottom-right, bottom-left, top-left (camera space)
    u, v = gx / LAYOUT[0], 1.0 - gy / LAYOUT[1]
    left = frame[2].lerp(frame[3], v)
    right = frame[1].lerp(frame[0], v)
    p = left.lerp(right, u)
    origin = cam.matrix_world @ Vector((p.x, p.y, 0.0))
    return origin, (cam.matrix_world.to_3x3() @ Vector((0.0, 0.0, -1.0))).normalized()


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


def band(y, y0, y1, soft):
    """1 inside [y0, y1], fading to 0 over `soft` layout units on each side."""
    return smooth(y0 - soft, y0, y) * (1.0 - smooth(y1, y1 + soft, y))


def n2(wx, wy, f, seed):
    return noise.noise(Vector((wx * f, wy * f, seed)))


def ridged(wx, wy, f, seed):
    return 1.0 - abs(n2(wx, wy, f, seed))


def frame_masks(gx, gy, top_px=70.0):
    """side: 0 inside the play columns, 1 at the screen edge; top: 0 below top_px, 1 at the top edge.
    The side frames dip towards the middle band, where the divider runs out of the board."""
    side = max(PLAY_X[0] - gx, gx - PLAY_X[1], 0.0) / 300.0 * (1.0 - 0.55 * band(gy, MID - 50, MID + 50, 90))
    top = max(top_px - gy, 0.0) / top_px
    return side, top


# ----------------------------------------------------------------------------------------------------------------
# Acheron (the original board)

def height_acheron(gx, gy, wx, wy):
    """Terrain height from the on-screen position: calm banks, a sunk river, cliffs at the frame."""
    river = smooth(RIVER[0] - 18, RIVER[0] + 6, gy) * (1.0 - smooth(RIVER[1] - 6, RIVER[1] + 18, gy))
    h = -0.45 * river
    side = max(PLAY_X[0] - gx, gx - PLAY_X[1], 0.0) / 300.0
    top = max(70.0 - gy, 0.0) / 70.0
    cliff = smooth(0.0, 1.0, side) * 2.4 + top * 1.2
    rough = noise.noise(Vector((wx * 0.6, wy * 0.6, 0.0)))
    fine = noise.noise(Vector((wx * 2.5, wy * 2.5, 3.0)))
    play = 1.0 - min(1.0, side * 1.5 + top)
    # The banks stay perfectly flat: only the frame gets the noise.
    h += cliff * (1.0 + 0.5 * rough) + (0.35 * rough + 0.12 * fine) * (1.0 - play)
    # The river cuts a gorge through the side cliffs too.
    return h * (1.0 - river) - 0.45 * river


def region_acheron(gx, gy):
    if gx < PLAY_X[0] - 40 or gx > PLAY_X[1] + 40 or gy < 40:
        return "cliffs"
    if RIVER[0] - 6 < gy < RIVER[1] + 6:
        return "riverbed"
    return "far_bank" if gy < RIVER[0] else "near_bank"


def extras_acheron():
    # A flat water sheet in the river bed.
    a, b = ground_at(960, RIVER[0] + 4, -0.38), ground_at(960, RIVER[1] - 4, -0.38)
    l, r = ground_at(-400, 472, -0.38), ground_at(2320, 472, -0.38)
    bpy.ops.mesh.primitive_plane_add(location=(0.0, (a.y + b.y) / 2, -0.38))
    w = bpy.context.object
    w.scale = (abs(r.x - l.x) / 2, abs(b.y - a.y) / 2, 1)
    tag(w, "river")


def scenery_acheron():
    """Shapes for the painter to follow: the crowd of souls on the far edge and Charon's landing stage."""
    rnd = random.Random(7)
    for k in range(70):
        gx = rnd.uniform(380, 1540)
        gy = rnd.uniform(18, 70)
        hgt = rnd.uniform(0.55, 0.75)
        if not clear_of_sockets(gx, gy):
            continue
        z = height_at(gx, gy)
        p = ground_at(gx, gy, z)
        bpy.ops.mesh.primitive_cylinder_add(radius=0.09, depth=hgt, vertices=8, location=(p.x, p.y, z + hgt / 2))
        tag(bpy.context.object, "souls")
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.08, segments=10, ring_count=6, location=(p.x, p.y, z + hgt + 0.06))
        tag(bpy.context.object, "souls")
    # Landing stage: planks from the far bank into the river, on the left frame (clear of the minion zones).
    for k in range(6):
        gy = 380 + k * 18
        p = ground_at(270, gy, -0.05)
        bpy.ops.mesh.primitive_cube_add(location=(p.x, p.y, -0.05))
        o = bpy.context.object
        o.scale = (0.7, 0.12, 0.05)
        tag(o, "landing_stage")
    for gx in (232, 308):
        p = ground_at(gx, 470, -0.4)
        bpy.ops.mesh.primitive_cylinder_add(radius=0.07, depth=0.9, vertices=8, location=(p.x, p.y, 0.0))
        tag(bpy.context.object, "landing_stage")


def props_acheron():
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


# ----------------------------------------------------------------------------------------------------------------
# Shared tools for the other arenas: one mesh object per element, built from boxes, cylinders and spheres.

class Mesh:
    def __init__(self):
        self.v, self.f, self.sm = [], [], []

    def _add(self, verts, faces, smooth_faces=False):
        base = len(self.v)
        self.v += [tuple(v) for v in verts]
        self.f += [tuple(base + i for i in f) for f in faces]
        self.sm += [smooth_faces] * len(faces)

    def box(self, c, half, rot=(0.0, 0.0, 0.0)):
        m = Matrix.LocRotScale(Vector(c), Euler(rot), None)
        verts = [m @ Vector((dx * half[0], dy * half[1], dz * half[2]))
                 for dz in (-1, 1) for dy in (-1, 1) for dx in (-1, 1)]
        self._add(verts, [(0, 2, 3, 1), (4, 5, 7, 6), (0, 1, 5, 4), (2, 6, 7, 3), (0, 4, 6, 2), (1, 3, 7, 5)])

    def cyl(self, c, r0, r1, h, n=12, rot=(0.0, 0.0, 0.0), smooth_faces=False):
        """Cylinder or cone standing on its base centre c (r1 = 0 makes a cone)."""
        m = Matrix.LocRotScale(Vector(c), Euler(rot), None)
        r1 = max(r1, 0.002)
        verts = [m @ Vector((math.cos(2 * math.pi * k / n) * r, math.sin(2 * math.pi * k / n) * r, z))
                 for r, z in ((r0, 0.0), (r1, h)) for k in range(n)]
        faces = [(k, (k + 1) % n, n + (k + 1) % n, n + k) for k in range(n)]
        faces += [tuple(range(n - 1, -1, -1)), tuple(range(n, 2 * n))]
        self._add(verts, faces, smooth_faces)

    def sphere(self, c, r, sq=(1.0, 1.0, 1.0), seg=12, rings=8):
        verts = [Vector(c) + Vector((0, 0, -r * sq[2]))]
        for j in range(1, rings):
            a = math.pi * j / rings - math.pi / 2
            for k in range(seg):
                b = 2 * math.pi * k / seg
                verts.append(Vector(c) + Vector((math.cos(a) * math.cos(b) * r * sq[0],
                                                 math.cos(a) * math.sin(b) * r * sq[1], math.sin(a) * r * sq[2])))
        verts.append(Vector(c) + Vector((0, 0, r * sq[2])))
        top = len(verts) - 1
        faces = [(0, 1 + (k + 1) % seg, 1 + k) for k in range(seg)]
        for j in range(rings - 2):
            a, b = 1 + j * seg, 1 + (j + 1) * seg
            faces += [(a + k, a + (k + 1) % seg, b + (k + 1) % seg, b + k) for k in range(seg)]
        last = 1 + (rings - 2) * seg
        faces += [(last + k, last + (k + 1) % seg, top) for k in range(seg)]
        self._add(verts, faces, True)

    def poly(self, verts, faces):
        self._add(verts, faces)

    def build(self, name, prop=False):
        me = bpy.data.meshes.new(name)
        me.from_pydata(self.v, [], self.f)
        for p, s in zip(me.polygons, self.sm):
            p.use_smooth = s
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(me)
        bm.free()
        me.update()
        o = bpy.data.objects.new(name, me)
        scene.collection.objects.link(o)
        return tag(o, name, prop)


def spot(gx, gy, dz=0.0):
    """World point on the terrain under the layout point (gx, gy), raised by dz."""
    z = height_at(gx, gy)
    p = ground_at(gx, gy, z)
    return Vector((p.x, p.y, z + dz))


def px(gx, gy, n_px):
    """World length of n_px layout units at (gx, gy) on the ground."""
    return radius_at(gx, gy, n_px)


# Socket layout points (1920x1080 units). The pairs mirror about the divider MID; the mana trays cannot (the hand
# covers the bottom edge) but share one mesh. Keep in step with the game's battle_view.gd.
HERO_PLINTHS = {"hero_plinth_enemy": (960, 143), "hero_plinth_player": (960, 801)}
POWER_SOCKETS = {"power_socket_enemy": (1140, 129), "power_socket_player": (1140, 815)}
DECK_NICHES = {"deck_niche_enemy": (1800, 312), "deck_niche_player": (1800, 632)}
MANA_TRAYS = {"mana_tray_enemy": (1640, 55), "mana_tray_player": (1640, 1025)}
END_TURN = (1745, 472)
# Ground level of each socket (world z) and the upward screen shift of one world unit of height (orthographic).
Z_PLINTH, Z_DECK, Z_TRAY, Z_END_TURN = 0.0, 0.35, 0.15, -0.3
Z_SCREEN = math.sin(CAM_TILT) * LAYOUT[0] / ORTHO_SCALE

# Pads flatten the ground under every socket to the socket's level: (cx, cy, rx, ry, z, ellipse), with (cx, cy)
# the pad centre as seen at its height z. Mirrored sockets get mirrored pads at the same z. The end-turn recess is
# sunk like the Acheron's.
SOCKET_PADS = ([(gx, gy, 150, 135, Z_PLINTH, True) for gx, gy in HERO_PLINTHS.values()]
               + [(gx, gy, 66, 60, Z_PLINTH, True) for gx, gy in POWER_SOCKETS.values()]
               + [(gx, gy, 82, 74, Z_DECK, False) for gx, gy in DECK_NICHES.values()]
               + [(gx, gy, 275, 48, Z_TRAY, False) for gx, gy in MANA_TRAYS.values()]
               + [(END_TURN[0], END_TURN[1], 135, 78, Z_END_TURN, True)])


def pad_distance(gx, gy, pad):
    """Below 1 inside the pad, growing outwards; (gx, gy) is the layout point of the ground at z = 0."""
    cx, cy, rx, ry, z, ellipse = pad
    dx, dy = abs(gx - cx) / rx, abs(gy - z * Z_SCREEN - cy) / ry
    return math.hypot(dx, dy) if ellipse else max(dx, dy)


def clear_of_sockets(gx, gy, margin=0.2):
    """True when the layout point is off every socket pad (with a margin): scenery must keep off them."""
    return all(pad_distance(gx, gy, pad) > 1.0 + margin for pad in SOCKET_PADS)


def hides_socket(gx, gy, h, rx=40.0, ry=40.0):
    """True when a piece of scenery standing at the layout point (footprint half-size rx, ry layout units; h world
    units tall) would cover part of a socket on screen: it stands in front of the socket and reaches into it."""
    for cx, cy, prx, pry, z, ellipse in SOCKET_PADS:
        # The pads are a little larger than their sockets: test against the socket's own extent.
        if (abs(gx - cx) < 0.9 * prx + rx and gy + ry > cy - 0.75 * pry + z * Z_SCREEN
                and gy - h * Z_SCREEN - ry < cy + pry):
            return True
    return False


def scenery_ok(gx, gy, h, r=40.0):
    """A free-standing piece of scenery keeps off the socket pads and out of the view of every socket."""
    return clear_of_sockets(gx, gy, r / 100.0) and not hides_socket(gx, gy, h, r, r)


def with_pads(raw):
    def h(gx, gy, wx, wy):
        v = raw(gx, gy, wx, wy)
        # A low ledge on the right frame for the decks and the end-turn recess, with the frame rising behind it
        # (mirrored about the divider, like the decks).
        ledge = band(gy, MID - 240, MID + 240, 70) * smooth(1590.0, 1680.0, gx) * (1.0 - smooth(1880.0, 1960.0, gx))
        v *= 1.0 - 0.75 * ledge
        for pad in SOCKET_PADS:
            d = pad_distance(gx, gy, pad)
            # Soft round pads; the sunk end-turn recess fades out quicker, before it reaches the minion zones.
            w = 1.0 - smooth(1.0, (1.2 if pad[4] < 0.0 else 1.5) if pad[5] else 1.6, d)
            if w > 0.0:
                v = v * (1.0 - w) + pad[4] * w
        # Nothing in front of a socket may rise into the view of it: below each pad (on screen) the frame stays
        # under the sight line that grazes the pad's front edge, so no socket is cut by the terrain. (The sunk
        # recess is exempt: its socket's top is flush with the ground around it.)
        for cx, cy, rx, ry, z, ellipse in SOCKET_PADS:
            cover = 1.0 - smooth(rx, rx + 40.0, abs(gx - cx))
            if z >= 0.0 and cover > 0.0 and gy > cy + ry + z * Z_SCREEN:
                cap = (gy - cy - ry) / Z_SCREEN    # a point this high is seen exactly on the pad's front edge
                if v > cap:
                    v = v * (1.0 - cover) + cap * cover
        return v
    return h


def region_generic(frame, far, near, bed, bed_band, span=(-1e9, 1e9)):
    def r(gx, gy):
        if gx < PLAY_X[0] - 40 or gx > PLAY_X[1] + 40 or gy < 40:
            if bed_band[0] < gy < bed_band[1] and span[0] < gx < span[1]:
                return bed
            return frame
        if bed_band[0] < gy < bed_band[1] and span[0] < gx < span[1]:
            return bed
        return far if gy < MID else near
    return r


def sheet(name, gy0, gy1, z, gx0=-400.0, gx1=2320.0):
    """A flat sheet (water, embers) under the divider, hidden below ground outside its bed."""
    a, b = ground_at(960, gy0, z), ground_at(960, gy1, z)
    l, r = ground_at(gx0, MID, z), ground_at(gx1, MID, z)
    bpy.ops.mesh.primitive_plane_add(location=((l.x + r.x) / 2, (a.y + b.y) / 2, z))
    w = bpy.context.object
    w.scale = (abs(r.x - l.x) / 2, abs(b.y - a.y) / 2, 1)
    tag(w, name)


def wall(m, pts, h, thick, merlon=0.16, gap=0.14, spikes=None, step=50.0):
    """A wall through the layout points pts, following the terrain in short segments, with merlons or spikes."""
    sub = []
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        n = max(1, int(math.ceil(math.hypot(x1 - x0, y1 - y0) / step)))
        sub += [(x0 + (x1 - x0) * k / n, y0 + (y1 - y0) * k / n) for k in range(n)]
    sub.append(pts[-1])
    for (ax, ay), (bx, by) in zip(sub, sub[1:]):
        # Leave a gap where the wall would stand in front of a socket.
        if hides_socket((ax + bx) / 2, (ay + by) / 2, h + (spikes or merlon),
                        abs(bx - ax) / 2 + 10, abs(by - ay) / 2 + 5):
            continue
        a, b = spot(ax, ay), spot(bx, by)
        base, top = min(a.z, b.z) - 0.25, max(a.z, b.z) + h
        d = b - a
        length = math.hypot(d.x, d.y)
        yaw = math.atan2(d.y, d.x)
        c = (a + b) / 2
        m.box((c.x, c.y, (base + top) / 2), (length / 2 + thick / 2, thick / 2, (top - base) / 2), (0, 0, yaw))
        k = max(1, int(length / (merlon + gap)))
        for i in range(k):
            t = (i + 0.5) / k
            q = a + d * t
            if spikes:
                m.cyl((q.x, q.y, top), thick * 0.4, 0.0, spikes, n=4, rot=(0, 0, yaw))
            else:
                m.box((q.x, q.y, top + merlon / 2), (merlon / 2, thick / 2 + 0.01, merlon / 2), (0, 0, yaw))


# ----------------------------------------------------------------------------------------------------------------
# Limbo: the Noble Castle meadow. Flat meadow, a thin stream sunk along the middle, the walls only at the top edge.

def stream_y(gx):
    return MID + 5.0 * math.sin(gx / 170.0)


def height_limbo(gx, gy, wx, wy):
    side, top = frame_masks(gx, gy, 90.0)
    s, t = smooth(0.0, 1.0, side), smooth(0.0, 1.0, top)
    rough = n2(wx, wy, 0.3, 11.0)
    fine = n2(wx, wy, 1.1, 5.0)
    h = s * (1.1 + 0.8 * rough) + t * 0.3 + max(s, t) * 0.25 * fine     # soft grassy hillocks on the frame only
    c = stream_y(gx)
    st = band(gy, c - 12, c + 12, 7)    # inside the gap between the minion zones
    return h * (1.0 - st) - 0.16 * st


def scenery_limbo():
    walls, towers, shrubs = Mesh(), Mesh(), Mesh()
    # The seven walls, stepped up towards the castle beyond the top edge; the gate gap holds the enemy hero.
    for gx0, gx1 in ((-60, 812), (1108, 1372)):
        for k in range(4):
            wall(walls, [(gx0, 64 - 15 * k), (gx1, 64 - 15 * k)], 0.32 + 0.24 * k, 0.16)
    for gx, gy, r, h in ((40, 46, 0.42, 1.5), (250, 52, 0.36, 1.2), (470, 52, 0.36, 1.25), (690, 50, 0.4, 1.4),
                         (790, 42, 0.55, 1.9), (1130, 42, 0.55, 1.9), (1345, 50, 0.4, 1.4)):
        if hides_socket(gx, gy, h + r * 1.6, r * 80.0, r * 65.0):
            continue
        p = spot(gx, gy, -0.2)
        towers.cyl(p, r, r * 0.95, h, n=16)
        towers.cyl(p + Vector((0, 0, h)), r * 1.12, 0.0, r * 1.6, n=16)
    rnd = random.Random(3)
    for gx, gy in ((70, 540), (240, 610), (90, 815), (270, 1030), (1690, 205), (1690, 765), (1885, 990), (45, 390)):
        if not scenery_ok(gx, gy, 0.6):
            continue
        p = spot(gx, gy)
        for k in range(3):
            r = rnd.uniform(0.18, 0.3)
            shrubs.sphere(p + Vector((rnd.uniform(-0.3, 0.3), rnd.uniform(-0.2, 0.2), r * 0.5)), r, (1.0, 1.0, 0.75))
    walls.build("castle_walls")
    towers.build("castle_towers")
    shrubs.build("shrubs")


def props_limbo():
    lantern = Mesh()  # a lantern hanging from a post
    p = spot(165, 300)
    lantern.cyl(p, 0.07, 0.06, 2.1, n=8)
    lantern.box(p + Vector((0.3, 0, 2.05)), (0.36, 0.04, 0.04))
    lantern.box(p + Vector((0.55, 0, 1.55)), (0.14, 0.14, 0.2))
    lantern.cyl(p + Vector((0.55, 0, 1.75)), 0.17, 0.0, 0.18, n=4, rot=(0, 0, math.pi / 4))
    lantern.build("prop_limbo_lantern", True)
    column = Mesh()  # a broken classical column and a fallen drum
    p = spot(150, 945)
    column.box(p + Vector((0, 0, 0.08)), (0.42, 0.42, 0.08))
    column.cyl(p + Vector((0, 0, 0.16)), 0.28, 0.26, 1.0, n=20, smooth_faces=True)
    column.cyl(p + Vector((0.75, -0.1, 0.24)), 0.24, 0.24, 0.6, n=20, rot=(0, math.pi / 2, 0.4), smooth_faces=True)
    column.build("prop_limbo_column", True)
    laurel = Mesh()  # a laurel bush
    p = spot(1830, 860)
    laurel.cyl(p, 0.08, 0.06, 0.8, n=8)
    for dx, dy, dz, r in ((0, 0, 1.05, 0.45), (-0.3, 0.05, 0.85, 0.32), (0.3, -0.05, 0.9, 0.34)):
        laurel.sphere(p + Vector((dx, dy, dz)), r, (1.0, 1.0, 0.9))
    laurel.build("prop_limbo_laurel", True)


# ----------------------------------------------------------------------------------------------------------------
# Lust: a windswept rock plateau; jagged cliffs only at the frame; a slightly lower, smooth wind channel.

def height_lust(gx, gy, wx, wy):
    side, top = frame_masks(gx, gy, 80.0)
    s, t = smooth(0.0, 0.85, side), smooth(0.0, 1.0, top)
    if gx > PLAY_X[1]:
        # The right frame holds the decks, the trays and the end turn: a low rocky shelf, the cliff only at the edge.
        s = 0.3 * smooth(PLAY_X[1], PLAY_X[1] + 120, gx) + 0.7 * smooth(1880.0, 1990.0, gx)
    r1 = ridged(wx, wy, 0.45, 21.0) ** 3
    r2 = ridged(wx, wy, 1.4, 8.0) ** 2
    r3 = ridged(wx, wy, 3.2, 2.0)
    cliff = s * (2.9 * (0.45 + 0.9 * r1) + 0.6 * r2 + 0.15 * r3) + t * (1.2 * (0.5 + 0.9 * r1) + 0.4 * r2)
    h = cliff
    # The wind channel stays in the gap between the minion zones, which are perfectly flat.
    ch = band(gy, MID - 10, MID + 10, 10)
    return h * (1.0 - 0.6 * ch) - 0.1 * ch


def scenery_lust():
    spires = Mesh()
    rnd = random.Random(12)
    spots = [(60, 120), (215, 70), (110, 600), (250, 760), (45, 1020), (1700, 150), (1880, 160), (1700, 860),
             (1880, 1060), (420, 22), (640, 30), (1260, 26), (1330, 40)]
    for gx, gy in [s for s in spots if scenery_ok(*s, 2.0)]:
        p = spot(gx, gy, -0.2)
        for k in range(rnd.randint(1, 3)):
            off = Vector((rnd.uniform(-0.35, 0.35), rnd.uniform(-0.25, 0.25), 0))
            h = rnd.uniform(1.0, 2.0) * (0.6 if gy < 60 else 1.0)
            spires.cyl(p + off, rnd.uniform(0.2, 0.35), 0.0, h, n=5,
                       rot=(rnd.uniform(-0.15, 0.15), rnd.uniform(0.15, 0.35), rnd.uniform(0, 3)))
    spires.build("rock_spires")


def props_lust():
    banner = Mesh()  # a torn banner on a pole, blown sideways
    p = spot(165, 300)
    banner.cyl(p, 0.06, 0.05, 2.2, n=8)
    banner.box(p + Vector((0.45, 0, 1.75)), (0.42, 0.02, 0.35), (0, 0.12, 0))
    banner.build("prop_lust_banner", True)
    rock = Mesh()  # a wind-carved boulder
    p = spot(150, 950)
    rock.sphere(p + Vector((0, 0, 0.35)), 0.7, (1.2, 0.8, 0.6), seg=9, rings=6)
    rock.sphere(p + Vector((0.6, 0.2, 0.2)), 0.35, (1.0, 0.8, 0.7), seg=7, rings=5)
    rock.build("prop_lust_rock", True)
    torch = Mesh()  # an iron torch stand
    p = spot(1830, 860)
    torch.cyl(p, 0.07, 0.05, 1.5, n=8)
    torch.cyl(p + Vector((0, 0, 1.45)), 0.08, 0.24, 0.3, n=10)
    torch.build("prop_lust_torch", True)


# ----------------------------------------------------------------------------------------------------------------
# Dis: flat cracked paving; one straight ember crack; open tombs and iron walls only on the frame.

DIS_SPAN = (150.0, 1650.0)    # the divider VFX span in data/arenas.json
CRACK_SPAN = (250.0, 1650.0)  # the carved crack stops short of the left frame


def crack_band(gx, gy, halfw, span, soft):
    taper = smooth(span[0], span[0] + 130, gx) * (1.0 - smooth(span[1] - 130, span[1], gx))
    w = halfw * taper
    if w < 0.5:
        return 0.0
    return band(gy, MID - w, MID + w, soft)


def height_dis(gx, gy, wx, wy):
    side, top = frame_masks(gx, gy, 80.0)
    s, t = smooth(0.0, 1.0, side), smooth(0.0, 1.0, top)
    rough = n2(wx, wy, 0.5, 31.0)
    fine = n2(wx, wy, 2.2, 7.0)
    # A low kerb, then rubble rising towards the city walls.
    kerb = 0.22 * smooth(0.0, 0.3, side)
    h = kerb + s * (0.9 + 0.4 * rough) + t * 0.5 + max(s, t) * 0.1 * fine   # the paving itself is flat
    cr = crack_band(gx, gy, 15.0, CRACK_SPAN, 4.0)
    return h * (1.0 - cr) - 0.2 * cr


def open_tomb(m, lid, gx, gy, yaw, size=1.0):
    p = spot(gx, gy, -0.1)
    L, W, H, T = 0.85 * size, 0.42 * size, 0.5 * size, 0.07 * size
    rot = Euler((0, 0, yaw))
    for c, half in (((0, 0, T / 2), (L, W, T / 2)), ((0, W - T / 2, H / 2), (L, T / 2, H / 2)),
                    ((0, -W + T / 2, H / 2), (L, T / 2, H / 2)), ((L - T / 2, 0, H / 2), (T / 2, W, H / 2)),
                    ((-L + T / 2, 0, H / 2), (T / 2, W, H / 2))):
        v = Vector(c)
        v.rotate(rot)
        m.box(p + v, half, (0, 0, yaw))
    v = Vector((0.35 * size, -0.55 * size, H + 0.02))
    v.rotate(rot)
    lid.box(p + v, (L * 1.02, W * 1.05, T * 0.8), (0.0, 0.18, yaw + 0.35))


def scenery_dis():
    walls, towers, tombs, lids = Mesh(), Mesh(), Mesh(), Mesh()
    # Red-hot iron walls along the top edge, with towers, and down both sides of the frame.
    wall(walls, [(-80, 14), (2000, 14)], 1.0, 0.22, spikes=0.32)  # just behind the enemy mana tray
    for gx in (60, 330, 600, 1330, 1600, 1860):
        if hides_socket(gx, 22, 2.8, 34.0, 28.0):
            continue
        p = spot(gx, 22, -0.3)
        towers.box(p + Vector((0, 0, 0.9)), (0.42, 0.42, 1.2))
        towers.cyl(p + Vector((0, 0, 2.1)), 0.5, 0.0, 0.7, n=4, rot=(0, 0, math.pi / 4))
    for gx in (14, 1906):
        wall(walls, [(gx, 40), (gx, 1100)], 0.8, 0.2, spikes=0.28, step=80.0)
    for gx, gy, yaw, sz in ((215, 150, 0.15, 1.0), (85, 420, -0.4, 1.0), (240, 560, 0.3, 0.9), (70, 760, 0.1, 1.0),
                            (1710, 175, -0.2, 0.9), (1690, 780, 0.25, 0.9), (1885, 1000, -0.1, 0.9)):
        if scenery_ok(gx, gy, 0.6, 50.0):
            open_tomb(tombs, lids, gx, gy, yaw, sz)
    walls.build("iron_walls")
    towers.build("iron_towers")
    tombs.build("tombs")
    lids.build("tomb_lids")


def props_dis():
    chains = Mesh()  # a gibbet with hanging chains
    p = spot(165, 300)
    for dx in (-0.5, 0.5):
        chains.cyl(p + Vector((dx, 0, 0)), 0.07, 0.07, 2.0, n=8)
    chains.box(p + Vector((0, 0, 2.0)), (0.62, 0.06, 0.06))
    for dx in (-0.2, 0.2):
        for k in range(6):
            chains.box(p + Vector((dx, 0, 1.9 - k * 0.14)), (0.03, 0.05, 0.07), (0, 0, (k % 2) * math.pi / 2))
    chains.build("prop_dis_chains", True)
    tomb, lid = Mesh(), Mesh()  # a burning open tomb (the flame is code VFX)
    open_tomb(tomb, lid, 150, 950, 0.1, 1.3)
    tomb.build("prop_dis_tomb", True)
    lid.build("prop_dis_tomb", True)
    fury = Mesh()  # a Fury on a pedestal, wings half open
    p = spot(1830, 860)
    fury.box(p + Vector((0, 0, 0.2)), (0.32, 0.32, 0.2))
    fury.cyl(p + Vector((0, 0, 0.4)), 0.2, 0.12, 0.9, n=10)
    fury.sphere(p + Vector((0, 0, 1.45)), 0.15)
    for sgn in (-1, 1):
        fury.box(p + Vector((sgn * 0.4, 0.05, 1.15)), (0.32, 0.02, 0.28), (0, sgn * 0.5, 0))
    fury.build("prop_dis_fury", True)


# ----------------------------------------------------------------------------------------------------------------
# Cocytus: a perfectly flat ice sheet; a thin straight crack; sinners in ice blocks and Lucifer's wings at the frame.

def height_cocytus(gx, gy, wx, wy):
    side, top = frame_masks(gx, gy, 80.0)
    s, t = smooth(0.0, 0.9, side), smooth(0.0, 1.0, top)
    r1 = ridged(wx, wy, 0.55, 41.0) ** 2
    r2 = ridged(wx, wy, 1.6, 9.0)
    h = s * (0.8 + 0.7 * r1 + 0.15 * r2) + t * (0.15 + 0.2 * r1)   # heaped ice at the frame
    cr = crack_band(gx, gy, 5.0, CRACK_SPAN, 2.5)
    return h * (1.0 - cr) - 0.12 * cr


def scenery_cocytus():
    blocks, sinners, wings = Mesh(), Mesh(), Mesh()
    rnd = random.Random(9)
    for gx, gy in ((60, 130), (230, 140), (80, 440), (250, 560), (60, 690), (240, 880), (1700, 180),
                   (1690, 800), (1880, 1010), (430, 40), (1290, 45)):
        if not scenery_ok(gx, gy, 1.3):
            continue
        p = spot(gx, gy, -0.15)
        yaw = rnd.uniform(-0.5, 0.5)
        h = rnd.uniform(0.45, 0.7)
        blocks.box(p + Vector((0, 0, h / 2)), (rnd.uniform(0.35, 0.5), rnd.uniform(0.3, 0.42), h / 2),
                   (rnd.uniform(-0.08, 0.08), rnd.uniform(-0.08, 0.08), yaw))
        top = p + Vector((0, 0, h))
        kind = rnd.choice(("head", "head", "legs", "arms"))
        if kind == "head":  # locked in up to the neck, face turned down
            sinners.sphere(top + Vector((0, 0, 0.12)), 0.16, (0.9, 1.0, 1.1))
            sinners.cyl(top - Vector((0, 0, 0.05)), 0.1, 0.08, 0.1, n=8)
        elif kind == "legs":  # upside down, only the legs out of the ice (Judecca)
            for dx in (-0.08, 0.08):
                sinners.cyl(top - Vector((0, 0, 0.05)), 0.07, 0.05, 0.6, n=8, rot=(0, dx * 2.5, 0))
        else:  # reaching arms
            sinners.sphere(top + Vector((0, 0, 0.06)), 0.14, (0.9, 1.0, 0.8))
            for sgn in (-1, 1):
                sinners.cyl(top + Vector((sgn * 0.15, 0, 0)), 0.05, 0.04, 0.45, n=6, rot=(0, sgn * 0.5, 0))
    # Lucifer's wings: two ribbed bat-wing silhouettes rising behind the top edge, leaning back.
    for root_gx, sgn, span in ((830, -1, 7.5), (1090, 1, 4.0)):
        root = spot(root_gx, 66, 0.05)
        lean = Vector((0, 0.73, 0.68))  # facing the camera
        ribs = [(0.12, 1.0), (0.4, 0.7), (0.65, 0.42), (0.85, 0.22), (1.0, 0.08)]
        tip = [root + Vector((sgn * span * u, 0, 0)) + lean * (span * 0.55 * v) for u, v in ribs]
        for t in tip:
            d = t - root
            yaw = math.atan2(d.y, d.x)
            # a thin rib from the root to the tip
            mid = (root + t) / 2
            rib_len = d.length
            rib = Matrix.LocRotScale(mid, d.to_track_quat("X", "Z"), None)
            wings._add([rib @ Vector((x * rib_len / 2, y, z)) for z in (-0.05, 0.05) for y in (-0.05, 0.05)
                        for x in (-1, 1)], [(0, 2, 3, 1), (4, 5, 7, 6), (0, 1, 5, 4), (2, 6, 7, 3), (0, 4, 6, 2),
                                            (1, 3, 7, 5)])
        # membrane between the ribs, scalloped in towards the root
        verts = [root]
        for k, t in enumerate(tip):
            verts.append(t)
            if k + 1 < len(tip):
                verts.append(root + (t + tip[k + 1] - 2 * root) * 0.38)
        faces = [(0, i, i + 1) for i in range(1, len(verts) - 1)]
        wings._add(verts, faces)
        wings._add([v - Vector((0, 0, 0.03)) for v in verts], [tuple(reversed(f)) for f in faces])
    blocks.build("ice_blocks")
    sinners.build("sinners")
    wings.build("lucifer_wings")


def props_cocytus():
    wing = Mesh()  # a small frozen wing (the toy flaps it)
    p = spot(175, 290)
    verts = [p + Vector((0, 0, 0.2))]
    for k in range(6):
        a = math.radians(15 + k * 25)
        r = 1.3 if k % 2 == 0 else 0.8
        verts.append(p + Vector((math.cos(a) * r * 0.9, 0.1, 0.2 + math.sin(a) * r)))
    wing.poly(verts + [v + Vector((0, 0.06, 0)) for v in verts],
              [(0, i, i + 1) for i in range(1, 6)] + [(7, 7 + i + 1, 7 + i) for i in range(1, 6)])
    wing.build("prop_cocytus_wing", True)
    head = Mesh()  # a head locked in an ice block
    p = spot(150, 955)
    head.box(p + Vector((0, 0, 0.3)), (0.5, 0.45, 0.3), (0, 0, 0.2))
    head.sphere(p + Vector((0, 0, 0.75)), 0.22, (0.9, 1.0, 1.1))
    head.build("prop_cocytus_head", True)
    stal = Mesh()  # an ice stalagmite
    p = spot(1830, 860)
    stal.cyl(p, 0.32, 0.0, 1.9, n=7)
    stal.cyl(p + Vector((0.3, 0.1, 0)), 0.16, 0.0, 0.9, n=6, rot=(0, 0.25, 0))
    stal.build("prop_cocytus_stalagmite", True)


# ----------------------------------------------------------------------------------------------------------------

ARENAS = {
    "acheron": dict(height=with_pads(height_acheron), region=region_acheron, extras=extras_acheron,
                    scenery=scenery_acheron, props=props_acheron, grid=(720, 400)),
    "limbo": dict(height=with_pads(height_limbo),
                  region=region_generic("grass_frame", "far_meadow", "near_meadow", "streambed",
                                        (MID - 22, MID + 22)),
                  extras=lambda: sheet("stream", MID - 18, MID + 18, -0.1), scenery=scenery_limbo,
                  props=props_limbo, grid=(720, 400)),
    "lust": dict(height=with_pads(height_lust),
                 # No region for the wind channel: its border would be a hard line in the line art.
                 region=region_generic("cliffs", "far_plateau", "near_plateau", "wind_channel", (0, 0)),
                 extras=lambda: None, scenery=scenery_lust, props=props_lust, grid=(720, 400)),
    "dis": dict(height=with_pads(height_dis),
                region=region_generic("frame_rubble", "far_paving", "near_paving", "crack", (MID - 20, MID + 20),
                                      CRACK_SPAN),
                extras=lambda: sheet("embers", MID - 16, MID + 16, -0.13, *CRACK_SPAN), scenery=scenery_dis,
                props=props_dis, grid=(720, 400)),
    "cocytus": dict(height=with_pads(height_cocytus),
                    region=region_generic("ice_frame", "far_ice", "near_ice", "crack", (MID - 8, MID + 8),
                                           CRACK_SPAN),
                    extras=lambda: None, scenery=scenery_cocytus, props=props_cocytus, grid=(720, 400)),
}
if ARENA not in ARENAS:
    sys.exit("unknown arena %r (choose from %s)" % (ARENA, ", ".join(ARENAS)))
A = ARENAS[ARENA]
height = A["height"]
region = A["region"]


def build_terrain():
    corners = [ground_at(x, y) for x, y in ((-400, -200), (2320, -200), (2320, 1400), (-400, 1400))]
    xs = [c.x for c in corners]
    ys = [c.y for c in corners]
    nx, ny = A["grid"]
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
    A["extras"]()


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


def screen_bbox(objs):
    """On-screen bounding box (layout units) of the objects' evaluated meshes (bevels included)."""
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    pts = []
    for o in objs:
        ev = o.evaluated_get(dg)
        me = ev.to_mesh()
        pts += [to_layout(ev.matrix_world @ v.co) for v in me.vertices]
        ev.to_mesh_clear()
    xs, ys = zip(*pts)
    return min(xs), min(ys), max(xs), max(ys)


def place(objs, gx, gy):
    """Slides a socket over the ground so the centre of its on-screen bounding box lands exactly on (gx, gy).
    (With the tilted camera the visible rim makes a socket taller on screen than its top face; centring the whole
    silhouette keeps mirrored sockets mirrored.)"""
    x0, y0, x1, y1 = screen_bbox(objs)
    shift = ground_at(gx, gy) - ground_at((x0 + x1) / 2, (y0 + y1) / 2)
    for o in objs:
        o.location += shift
    x0, y0, x1, y1 = screen_bbox(objs)
    print("socket %-20s centre (%.1f, %.1f) size %.1f x %.1f" % (objs[0]["element"], (x0 + x1) / 2, (y0 + y1) / 2,
                                                                 x1 - x0, y1 - y0))


def socket_pair(points, make):
    """Builds the first socket of a pair with make(name, gx, gy) -> objects, and the second as linked copies of the
    same meshes and modifiers. Every socket shape is symmetric front to back, so mirroring it about the divider is
    the same as copying it: both sockets have the identical size and shape on screen."""
    (n0, p0), (n1, p1) = points.items()
    objs = make(n0, *p0)
    place(objs, *p0)
    copies = []
    for o in objs:
        c = o.copy()
        scene.collection.objects.link(c)
        copies.append(tag(c, n1))
    place(copies, *p1)


def sockets():
    """The same in every arena, each on its flat pad (SOCKET_PADS) and centred on its layout point."""
    socket_pair(HERO_PLINTHS, lambda n, gx, gy: [disc(n, gx, gy, 128, 0.28, z=Z_PLINTH),
                                                 disc(n, gx, gy, 114, 0.36, z=Z_PLINTH)])  # raised inner ring
    socket_pair(POWER_SOCKETS, lambda n, gx, gy: [disc(n, gx, gy, 52, 0.18, z=Z_PLINTH)])
    socket_pair(DECK_NICHES, lambda n, gx, gy: [box(n, gx, gy, 130, 120, 0.25, z=Z_DECK)])
    socket_pair(MANA_TRAYS, lambda n, gx, gy: [box(n, gx, gy, 520, 70, 0.15, z=Z_TRAY)])
    place([disc("end_turn_socket", *END_TURN, 125, 0.3, z=Z_END_TURN, sy=0.55)], *END_TURN)


def height_at(gx, gy):
    p = ground_at(gx, gy)
    return height(gx, gy, p.x, p.y)


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
A["scenery"]()
A["props"]()
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
print("BLOCKOUT DONE", ARENA, OUT)
