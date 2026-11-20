import sys, math, random, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
import kit

res = int(sys.argv[-3]); samples = int(sys.argv[-2]); out = sys.argv[-1]
rnd = random.Random(13)
kit.reset(res, res, samples)
kit.world((0.006, 0.01, 0.025), 1.0)
kit.set_fog((0.04, 0.07, 0.14), 6.0, 60.0)

W = [kit.clay2('wA', (0.26, 0.12, 0.32), (0.16, 0.07, 0.22)),
     kit.clay2('wB', (0.06, 0.24, 0.26), (0.03, 0.14, 0.17)),
     kit.clay2('wC', (0.38, 0.22, 0.07), (0.24, 0.12, 0.04)),
     kit.clay2('wD', (0.14, 0.16, 0.30), (0.08, 0.09, 0.19)),
     kit.clay2('wE', (0.30, 0.10, 0.10), (0.18, 0.05, 0.06))]
roof = kit.clay2('roof', (0.05, 0.05, 0.08), (0.03, 0.03, 0.05), bump=1.2)
trim = kit.clay2('trim', (0.05, 0.04, 0.05), rough=0.35)
stone = kit.clay2('cobble', (0.12, 0.12, 0.15), (0.07, 0.07, 0.09), bump=1.0, scale=0.4)
mortar = kit.clay2('mortar', (0.03, 0.03, 0.04), bump=0.4, smear=False)
iron = kit.clay2('iron', (0.025, 0.025, 0.03), rough=0.3, smear=False)
bark = kit.clay2('bark', (0.05, 0.04, 0.05), bump=1.4, scale=0.3)
lit = kit.glow('lit', (1.0, 0.52, 0.16), 12)
dimlit = kit.glow('dim', (0.9, 0.35, 0.10), 4)
dark = kit.clay2('pane', (0.01, 0.012, 0.02), rough=0.15, smear=False, bump=0.2)
lampg = kit.glow('lamp', (1.0, 0.68, 0.3), 25)

# Ground: dark mortar with hundreds of hand-rolled cobbles.
kit.ground(mortar, size=140, amt=0.12, scale=2.0, loc=(0, 30, 0))
bpy.ops.mesh.primitive_uv_sphere_add(radius=0.15, segments=10, ring_count=6, location=(0, -50, 0))
pebble = bpy.context.object
pebble.data.materials.append(stone)
bpy.ops.object.shade_smooth()
def street_x(y):
    return math.sin(y * 0.11) * 1.3
for row in range(110):
    y = -1.0 + row * 0.26
    for k in range(-9, 10):
        x = street_x(y) + k * 0.27 + (row % 2) * 0.135 + rnd.uniform(-0.03, 0.03)
        kit.instance(pebble, (x, y + rnd.uniform(-0.04, 0.04), 0.02),
                     rot=(rnd.uniform(-0.2, 0.2), rnd.uniform(-0.2, 0.2), rnd.uniform(0, 3)),
                     scale=(rnd.uniform(0.8, 1.1), rnd.uniform(0.7, 1.0), rnd.uniform(0.28, 0.42)))

# Painted sky + moon.
sky = kit.painted_sky('sky', top=(0.006, 0.012, 0.045), bottom=(0.06, 0.12, 0.24), horizon=0.3, strength=1.0,
                      clouds=((0.12, 0.18, 0.32), 0.65))
kit.backdrop(sky, dist=95, width=280, height=140, z0=-8)
moonm = kit.glow('moon', (0.95, 0.93, 0.82), 7, haze=0)
moon = kit.sphere((0.8, 86, 13), 13, moonm, scale=(1, 0.12, 1), amt=0.35)
crater = kit.glow('crater', (0.62, 0.66, 0.70), 4, haze=0)
for (cx, cz, cr) in [(-4, 34, 2.2), (2.5, 27, 1.6), (-0.5, 23.5, 1.0), (4, 33, 0.9)]:
    kit.sphere((cx + 2.3, 84.5, cz - 15), cr, crater, scale=(1, 0.2, 1), amt=0.1)
star = kit.glow('star', (0.9, 0.92, 1.0), 9, haze=0)
for k in range(110):
    kit.sphere((rnd.uniform(-60, 60), 93, rnd.uniform(10, 70)), rnd.uniform(0.07, 0.2), star, amt=0, seg=6)


parent_all = kit.parent_all


def window(fx, wy, z, side, w, h, r, parts, round_top=False):
    on = r.random() < 0.6
    mat = lit if on else (dimlit if r.random() < 0.25 else dark)
    tilt = (0, 0, 0)
    tilt = (r.uniform(-0.12, 0.12), 0, 0)
    parts.append(kit.cube((fx, wy, z), (0.08, w, h), mat, rot=tilt, amt=0, bevel=0.02, levels=1))
    parts.append(kit.cube((fx - side * 0.04, wy, z + h / 2 + 0.06), (0.14, w + 0.2, 0.12), trim, rot=tilt, amt=0.01, levels=1))
    parts.append(kit.cube((fx - side * 0.04, wy, z - h / 2 - 0.06), (0.16, w + 0.25, 0.1), trim, rot=tilt, amt=0.01, levels=1))
    if r.random() < 0.5:  # cross bars on some windows
        parts.append(kit.cube((fx - side * 0.03, wy, z), (0.05, 0.05, h), trim, rot=tilt, amt=0, bevel=0, levels=0))
    if round_top:
        kit.cyl((fx, wy, z + h / 2), w / 2, 0.08, mat, rot=(0, math.radians(90), 0), verts=16, amt=0, levels=1)
    if r.random() < 0.18:  # one shutter hanging crooked
        parts.append(kit.cube((fx - side * 0.06, wy + w * 0.75, z - 0.08), (0.06, w * 0.55, h * 1.05), r.choice(W), rot=(r.uniform(0.15, 0.4), 0, 0), amt=0.01, levels=1))
    if on:
        kit.anchor('window', (fx - side * 0.05, wy, z))
        if r.random() < 0.6:
            kit.light('POINT', (fx - side * 0.6, wy, z), 22, (1.0, 0.55, 0.22), size=0.25)


def house(side, y, depth, height, seed):
    r = random.Random(seed)
    sx = street_x(y)
    inner = sx + side * 2.7
    w = 2.4
    x0 = inner + side * w / 2
    parts = []
    mat = r.choice(W)
    floors = max(3, int(height / 1.55))
    fh = height / floors
    for f in range(floors):
        jut = 0.16 * f
        cx = x0 - side * jut / 2
        b = kit.cube((cx, y + r.uniform(-0.15, 0.15), f * fh + fh / 2),
                     (w + jut + r.uniform(-0.15, 0.15), depth * (1 - 0.03 * f) + r.uniform(-0.1, 0.1), fh * 1.05), mat,
                     rot=(r.uniform(-0.07, 0.07), r.uniform(-0.07, 0.07), r.uniform(-0.1, 0.1)), amt=0.16, bevel=0.18)
        parts.append(b)
        parts.append(kit.cube((cx - side * 0.06, y, f * fh + 0.03), (w + jut + 0.3, depth * 1.06, 0.13), trim, amt=0.03, levels=1))
        fx = cx - side * (w + jut) / 2 - side * 0.04
        n = 1 if depth < 1.9 else 2
        for k in range(n):
            wy = y + (k - (n - 1) / 2) * depth * 0.42
            window(fx, wy, f * fh + fh * 0.55, side, r.uniform(0.38, 0.55), r.uniform(0.6, 0.85), r, parts, round_top=(f == floors - 1 and r.random() < 0.5))
    top = floors * fh
    jt = 0.16 * floors
    # witch-hat roof: tall cone, bent so the tip curls over the street
    rf = kit.cone((x0 - side * jt / 2, y, top + height * 0.36), (w + jt) * 0.78, height * 0.75, roof, verts=8,
                  rot=(0, 0, r.uniform(0, 1)), amt=0.06, levels=2)
    kit.deform(rf, 'BEND', side * r.uniform(0.5, 1.1), axis='Y', origin=(x0 - side * jt / 2, y, top))
    parts.append(rf)
    # crooked chimney
    if r.random() < 0.75:
        chx, chy, chz = x0 + side * 0.55, y + depth * 0.25, top + 1.4
        ch = kit.cube((chx, chy, chz), (0.38, 0.38, 2.6), W[3], rot=(0, side * r.uniform(0.05, 0.25), 0), amt=0.05)
        parts.append(ch)
        kit.anchor('chimney', (chx + side * 0.2, chy, chz + 1.4))
    lean = side * -r.uniform(0.03, 0.08)
    e = parent_all(parts, (x0, y, 0), (r.uniform(-0.04, 0.04), lean, 0))
    # bend the whole stack a bit (tops lean further than the bottoms)
    return e


y = -3.5
i = 0
while y < 30:
    depth = rnd.uniform(1.5, 2.3)
    for side in (-1, 1):
        house(side, y + rnd.uniform(-0.2, 0.2) + (0.7 if side > 0 else 0), depth, rnd.uniform(5.5, 9.5) * (1 - y / 70), 200 + i)
        i += 1
    y += depth + rnd.uniform(0.05, 0.3)

# Clock-tower spire at the end of the street, bent like everything else.
tw = kit.cube((3.6, 44, 8), (3.0, 3.0, 16), W[0], rot=(0, 0.04, 0.25), amt=0.12, bevel=0.3)
kit.deform(tw, 'TAPER', -0.35, axis='Z', origin=(3.6, 44, 0))
sp = kit.cone((3.6, 44, 21), 2.6, 11, roof, verts=8, amt=0.06, levels=2)
kit.deform(sp, 'BEND', 0.9, axis='Y', origin=(3.6, 44, 16))
face = kit.glow('clock', (1.0, 0.85, 0.45), 6)
kit.cyl((3.6 - 1.55, 44, 12.5), 0.9, 0.1, face, rot=(0, math.radians(90), 0), verts=24, amt=0, levels=1)
kit.anchor('lamp', (3.6 - 1.6, 44, 12.5))
kit.anchor('moon', (0.8, 85, 13))

# Gas lamps (one right up close and out of focus, like a real miniature shot).
for (lx, ly, near) in [(-1.25, 1.2, True), (1.9 + street_x(9), 9.0, False), (-1.6 + street_x(17), 17.0, False), (1.5 + street_x(25), 25, False)]:
    post = kit.cyl((lx, ly, 1.4), 0.07, 2.8, iron, verts=8)
    kit.deform(post, 'BEND', 0.25, axis='Y', origin=(lx, ly, 0))
    kit.cube((lx + 0.12, ly, 2.95), (0.36, 0.36, 0.5), lampg, amt=0, bevel=0.05, levels=1)
    c = kit.cone((lx + 0.12, ly, 3.35), 0.34, 0.45, iron, verts=4, rot=(0, 0, math.radians(45)), amt=0)
    kit.light('POINT', (lx + 0.12, ly, 2.8), 85, (1.0, 0.62, 0.28), size=0.2)
    kit.anchor('lamp', (lx + 0.12, ly, 2.95))

# Curly dead tree, branches bent into hooks.
def curly_tree(x, y, h):
    trunk = kit.cone((x, y, h * 0.3), 0.32, h * 0.6, bark, verts=10, amt=0.05, levels=2)
    trunk.data.vertices  # noqa
    kit.deform(trunk, 'TWIST', 1.2, axis='Z', origin=(x, y, 0))
    kit.deform(trunk, 'BEND', 0.6, axis='Y', origin=(x, y, 0))
    for k in range(6):
        a = k / 6 * math.pi * 2 + rnd.uniform(-0.3, 0.3)
        z = h * rnd.uniform(0.35, 0.6)
        L = h * rnd.uniform(0.35, 0.55)
        br = kit.cone((x + math.cos(a) * L * 0.45, y + math.sin(a) * L * 0.45, z + L * 0.25), 0.1, L, bark, verts=8,
                      rot=(math.sin(a) * -1.0, math.cos(a) * 1.0, 0), amt=0.02, levels=2)
        kit.deform(br, 'BEND', rnd.choice((-1, 1)) * rnd.uniform(2.0, 3.6), axis='X', origin=(x + math.cos(a) * L * 0.45, y + math.sin(a) * L * 0.45, z))

curly_tree(-1.95 + street_x(6), 6.0, 5.5)

# Wonky iron fence close to camera (blurred foreground).
for k in range(9):
    fy = 0.2 + k * 0.32
    kit.cyl((1.55, fy, 0.55), 0.035, 1.1, iron, rot=(rnd.uniform(-0.1, 0.1), rnd.uniform(-0.15, 0.15), 0), verts=6, amt=0)
    kit.cone((1.55, fy, 1.18), 0.07, 0.18, iron, verts=4, amt=0)
kit.cube((1.55, 1.5, 0.95), (0.05, 3.0, 0.05), iron, rot=(0.04, 0, 0), amt=0, levels=1)

# Haze so the lamp and moon light shows up as beams.
# kit.volume_box((0, 16, 7), (24, 44, 16), density=0.035, color=(0.55, 0.65, 1.0))

# Lighting: hard cold moon rim from behind, warm practicals, very little fill.
kit.light('SPOT', (-1.5, 60, 26), 60000, (0.55, 0.72, 1.0), rot_deg=(-110, 0, 0), size=1.5, spot=40)
kit.light('SUN', (0, 0, 20), 1.1, (0.40, 0.62, 1.0), rot_deg=(-35, 0, 190), size=1)
kit.light('AREA', (0, -6, 4), 40, (0.45, 0.55, 1.0), rot_deg=(60, 0, 0), size=5)

kit.camera((0.15, -2.4, 0.75), (93.5, 0, 0.6), lens=19, focus=8.0, fstop=0.8)
bpy.context.scene.view_settings.look = 'AgX - Punchy'
bpy.context.scene.view_settings.exposure = 0.25
import time as _t; print('BUILD', _t.process_time(), flush=True)
kit.export_anchors(out.rsplit('.', 1)[0] + '.json')
kit.render(out)
