import sys, math, random
sys.path.insert(0, __import__('os').path.dirname(__file__))
import bpy
import kit

res = int(sys.argv[-3]); samples = int(sys.argv[-2]); out = sys.argv[-1]
rnd = random.Random(5)
kit.reset(res, res, samples)
kit.world((0.6, 0.7, 0.85), 0.8)
kit.set_fog((0.72, 0.80, 0.93), 22.0, 110.0)

walls = [
    kit.clay('wA', (0.55, 0.20, 0.16), (0.42, 0.14, 0.11)),
    kit.clay('wB', (0.20, 0.36, 0.48), (0.14, 0.26, 0.36)),
    kit.clay('wC', (0.72, 0.55, 0.30), (0.58, 0.42, 0.22)),
    kit.clay('wD', (0.40, 0.48, 0.30), (0.30, 0.37, 0.22)),
]
snow = kit.clay('snow', (0.86, 0.89, 0.95), (0.70, 0.77, 0.90), rough=0.75, bump=0.35, sss=0.3, prints=False)
trim = kit.clay('trim', (0.25, 0.15, 0.10), bump=0.4)
pine = kit.clay('pine', (0.10, 0.25, 0.20), (0.06, 0.17, 0.14), bump=0.6)
lit = kit.glow('lit', (1.0, 0.72, 0.38), 4)
dark = kit.clay('glass', (0.10, 0.12, 0.18), rough=0.2, prints=False)

kit.ground(snow, size=160, amt=0.4, scale=4.0, loc=(0, 40, 0))
path = kit.clay('path', (0.62, 0.66, 0.78), (0.50, 0.55, 0.70), bump=0.7, scale=0.4, prints=False)
for k in range(26):
    yy = k * 1.9
    kit.sphere((math.sin(yy * 0.09) * 1.6, yy, -0.02), 1.7, path, scale=(1.0, 1.4, 0.06), amt=0.03, seg=12)

sky = kit.painted_sky('sky', top=(0.22, 0.40, 0.72), bottom=(0.88, 0.80, 0.82), horizon=0.35, strength=1.1,
                      clouds=((0.98, 0.97, 1.0), 0.6))
kit.backdrop(sky, dist=110, width=300, height=120, z0=-6)

# Distant snowy hills.
for (hx, hy, r) in [(-30, 80, 22), (0, 92, 26), (34, 84, 24), (60, 76, 18)]:
    kit.sphere((hx, hy, -r * 0.55), r, snow, scale=(1.4, 0.6, 1), amt=0.4, seg=20)


def parent_all(objs, pivot, rot):
    bpy.ops.object.empty_add(location=pivot)
    e = bpy.context.object
    for ob in objs:
        ob.parent = e
        ob.matrix_parent_inverse = e.matrix_world.inverted()
    e.rotation_euler = rot
    return e


def cottage(x, y, seed, facing):
    """Squat rounded cottage with a fat snow cap and glowing windows."""
    r = random.Random(seed)
    w, d, h = r.uniform(2.6, 3.4), r.uniform(2.6, 3.2), r.uniform(2.0, 3.0)
    mat = r.choice(walls)
    parts = [kit.cube((x, y, h / 2), (w, d, h), mat, amt=0.1, bevel=0.3)]
    # gable roof: a squashed 4-sided cone, then a thick pillowy snow layer
    roof_h = r.uniform(1.6, 2.4)
    parts.append(kit.cone((x, y, h + roof_h / 2 - 0.05), max(w, d) * 0.8, roof_h, trim, verts=4, rot=(0, 0, math.radians(45)), amt=0.05))
    cap = kit.cone((x, y, h + roof_h / 2 + 0.12), max(w, d) * 0.84, roof_h + 0.15, snow, verts=4, rot=(0, 0, math.radians(45)), amt=0.12, levels=2)
    parts.append(cap)
    # chimney with snow
    cx = x + r.uniform(-0.6, 0.6)
    parts.append(kit.cube((cx, y + 0.4, h + roof_h * 0.7), (0.45, 0.45, 1.2), trim, amt=0.03))
    parts.append(kit.sphere((cx, y + 0.4, h + roof_h * 0.7 + 0.65), 0.32, snow, scale=(1, 1, 0.5), amt=0.05))
    # windows on the side facing the lane
    fx = x - facing * w / 2 - facing * 0.03
    for k in (-1, 1):
        on = r.random() < 0.75
        parts.append(kit.cube((fx, y + k * d * 0.24, h * 0.5), (0.08, 0.55, 0.7), lit if on else dark, amt=0, bevel=0.05, levels=1))
        parts.append(kit.cube((fx, y + k * d * 0.24, h * 0.5 - 0.42), (0.2, 0.7, 0.14), snow, amt=0.02, bevel=0.05, levels=1))
        if on:
            kit.light('POINT', (fx - facing * 0.6, y + k * d * 0.24, h * 0.5), 18, (1.0, 0.7, 0.4), size=0.3)
    # snow drift around the base
    parts.append(kit.sphere((x, y, 0.0), max(w, d) * 0.75, snow, scale=(1.1, 1.1, 0.22), amt=0.1, seg=16))
    parent_all(parts, (x, y, 0), (0, 0, r.uniform(-0.12, 0.12) + facing * 0.05))


def pine_tree(x, y, h, seed):
    r = random.Random(seed)
    kit.cyl((x, y, h * 0.1), 0.18, h * 0.2, trim, verts=8)
    tiers = 3
    for t in range(tiers):
        z = h * (0.22 + t * 0.24)
        rad = h * (0.36 - t * 0.09)
        kit.cone((x, y, z + h * 0.16), rad, h * 0.38, pine, verts=10, rot=(0, 0, r.uniform(0, 1)), amt=0.08)
        kit.cone((x, y, z + h * 0.25), rad * 0.72, h * 0.22, snow, verts=10, rot=(0, 0, r.uniform(0, 1)), amt=0.06)


# Cottages along a gently curving lane.
y = 0.0
i = 0
while y < 40:
    curve = math.sin(y * 0.09) * 1.6
    for side in (-1, 1):
        if rnd.random() < 0.85:
            cottage(curve + side * rnd.uniform(3.8, 4.6), y + rnd.uniform(-0.5, 0.5) + (1.6 if side > 0 else 0), 500 + i, side)
        i += 1
    y += rnd.uniform(3.6, 4.6)

for k in range(18):
    side = rnd.choice((-1, 1))
    pine_tree(side * rnd.uniform(6.5, 11), rnd.uniform(4, 50), rnd.uniform(3.5, 6.5), 900 + k)
pine_tree(-2.6, 1.6, 2.6, 77)

# A church steeple at the end of the lane.
kit.cube((1.5, 48, 4), (3.5, 4, 8), walls[2], amt=0.08, bevel=0.2)
kit.cone((1.5, 48, 10), 2.4, 5.5, snow, verts=4, rot=(0, 0, math.radians(45)), amt=0.06)
kit.cube((1.5 - 1.8, 48, 5), (0.1, 0.9, 1.4), lit, amt=0, levels=1)

# Lamp posts and a little fence.
lampm = kit.glow('lamp', (1.0, 0.78, 0.45), 10)
for (lx, ly) in [(-2.2, 6), (2.6, 14), (-1.0, 24)]:
    kit.cyl((lx, ly, 1.2), 0.07, 2.4, trim, verts=8)
    kit.sphere((lx, ly, 2.55), 0.22, lampm, amt=0)
    kit.sphere((lx, ly, 2.8), 0.22, snow, scale=(1.2, 1.2, 0.5), amt=0.03)
for k in range(8):
    kit.cube((2.3, 1.5 + k * 0.7, 0.4), (0.12, 0.12, 0.8), trim, rot=(0, 0, rnd.uniform(-0.1, 0.1)), amt=0.02, levels=1)
    kit.sphere((2.3, 1.5 + k * 0.7, 0.85), 0.11, snow, scale=(1, 1, 0.6), amt=0)

# Soft winter daylight.
kit.light('SUN', (0, 0, 20), 3.8, (1.0, 0.86, 0.70), rot_deg=(-62, 0, 125), size=3)
kit.light('AREA', (0, -8, 8), 50, (0.6, 0.72, 1.0), rot_deg=(50, 0, 0), size=10)

kit.camera((0.0, -1.5, 1.2), (85.0, 0, 0.0), lens=22, focus=9.0, fstop=1.3)
bpy.context.scene.view_settings.exposure = -0.38
bpy.context.scene.view_settings.look = 'AgX - Punchy'
kit.render(out)
