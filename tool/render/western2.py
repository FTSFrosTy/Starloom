import sys, math, random
sys.path.insert(0, __import__('os').path.dirname(__import__('os').path.abspath(__file__)))
import bpy
import kit
kit.BEVEL_REL = 'max'

res = int(sys.argv[-3]); samples = int(sys.argv[-2]); out = sys.argv[-1]
rnd = random.Random(21)
kit.reset(res, res, samples)
kit.world((0.25, 0.12, 0.07), 0.6)
kit.set_fog((0.62, 0.36, 0.22), 14.0, 80.0)

planks = [
    kit.clay2('plankA', (0.36, 0.20, 0.10), (0.25, 0.13, 0.06), bump=0.7),
    kit.clay2('plankB', (0.30, 0.22, 0.15), (0.20, 0.14, 0.09), bump=0.7),
    kit.clay2('plankC', (0.42, 0.16, 0.09), (0.28, 0.10, 0.05), bump=0.7),
    kit.clay2('plankD', (0.26, 0.24, 0.20), (0.17, 0.15, 0.12), bump=0.7),
]
trim = kit.clay2('trim', (0.12, 0.07, 0.04), bump=0.5)
dirt = kit.clay2('dirt', (0.55, 0.33, 0.18), (0.42, 0.24, 0.12), bump=0.8, scale=0.5, smear=False)
rock = kit.clay2('rock', (0.55, 0.24, 0.13), (0.40, 0.16, 0.09), bump=0.8, scale=2.0, haze=1.2)
cactus = kit.clay2('cactus', (0.16, 0.30, 0.14), (0.10, 0.20, 0.09), bump=0.5)
dark = kit.clay2('darkwin', (0.03, 0.02, 0.02), rough=0.25, smear=False)
lit = kit.glow('lit', (1.0, 0.62, 0.25), 5)
sunm = kit.glow('sun', (1.0, 0.78, 0.42), 8, haze=0)

kit.ground(dirt, size=160, amt=0.22, scale=3.0, loc=(0, 40, 0))

sky = kit.painted_sky('sky', top=(0.10, 0.10, 0.32), bottom=(1.0, 0.45, 0.15), horizon=0.25, strength=1.25,
                      clouds=((1.0, 0.35, 0.38), 0.8))
kit.backdrop(sky, dist=110, width=300, height=120, z0=-6)
kit.sphere((-3, 104, 9), 7.5, sunm, scale=(1, 0.1, 1), amt=0.15)
kit.anchor('sun', (-3, 103, 9))

# Mesas / buttes on the horizon.
for (mx, my, w, h) in [(-38, 85, 30, 14), (-12, 92, 16, 9), (24, 88, 34, 17), (52, 80, 20, 11)]:
    kit.cube((mx, my, h / 2 - 0.5), (w, 10, h), rock, rot=(0, 0, rnd.uniform(-0.1, 0.1)), amt=0.9, bevel=0.6)
    kit.cube((mx, my - 2, 1.2), (w * 1.3, 14, 3), rock, amt=0.7, bevel=0.6)


parent_all = kit.parent_all


def storefront(side, y, depth, seed, sign=None):
    """Wooden false-front building with a porch."""
    r = random.Random(seed)
    inner = 4.0 * side
    w = 3.4
    x0 = inner + side * w / 2
    mat = r.choice(planks)
    h = r.uniform(3.2, 4.4)
    parts = []
    parts.append(kit.cube((x0, y, h / 2), (w, depth, h), mat, amt=0.16, bevel=0.2))
    # tall false front (taller than the building, flat top or stepped)
    fh = h + r.uniform(1.0, 2.0)
    parts.append(kit.cube((inner + side * 0.08, y, fh / 2), (0.16, depth * 1.04, fh), mat, amt=0.05, bevel=0.06))
    if r.random() < 0.5:
        parts.append(kit.cube((inner + side * 0.08, y, fh + 0.35), (0.16, depth * 0.5, 0.7), mat, amt=0.04, bevel=0.06))
    # porch roof on posts
    parts.append(kit.cube((inner - side * 0.9, y, 2.45), (1.9, depth * 1.02, 0.12), trim, rot=(0, side * 0.12, 0), amt=0.03, bevel=0.03))
    for k in (-1, 1):
        parts.append(kit.cyl((inner - side * 1.75, y + k * depth * 0.42, 1.2), 0.07, 2.4, trim, verts=8))
    parts.append(kit.cube((inner - side * 0.9, y, 0.12), (1.9, depth * 1.02, 0.18), trim, amt=0.02, bevel=0.03))
    # windows + door
    for k in (-1, 1):
        on = r.random() < 0.45
        parts.append(kit.cube((inner - side * 0.02, y + k * depth * 0.28, 1.5), (0.06, depth * 0.22, 0.8), lit if on else dark, amt=0, bevel=0.02, levels=1))
        if on:
            kit.anchor('window', (inner - side * 0.05, y + k * depth * 0.28, 1.5))
    parts.append(kit.cube((inner - side * 0.02, y, 1.0), (0.06, depth * 0.2, 1.8), dark, amt=0, bevel=0.02, levels=1))
    # sign board
    if sign:
        parts.append(kit.cube((inner - side * 0.02, y, h + 0.5), (0.1, depth * 0.8, 0.7), kit.clay2('sign' + str(seed), sign, bump=0.4), amt=0.02, bevel=0.04))
    parent_all(parts, (x0, y, 0), (0, side * -r.uniform(0.02, 0.09), r.uniform(-0.06, 0.06)))


signs = [(0.85, 0.75, 0.55), (0.55, 0.15, 0.12), (0.2, 0.3, 0.45), (0.75, 0.6, 0.25)]
y = -3.0
i = 0
while y < 26:
    depth = rnd.uniform(3.0, 4.2)
    for side in (-1, 1):
        if rnd.random() < 0.88:
            storefront(side, y + (1.0 if side > 0 else 0), depth, 300 + i, signs[i % len(signs)] if rnd.random() < 0.7 else None)
        i += 1
    y += depth + rnd.uniform(0.4, 1.6)

# Water tower behind the right side.
for k in range(4):
    a = k * math.pi / 2 + math.pi / 4
    kit.cyl((6.5 + math.cos(a) * 1.4, 38 + math.sin(a) * 1.4, 4), 0.12, 8, trim, verts=8)
kit.cyl((6.5, 38, 9.2), 2.2, 3.0, planks[1], verts=20, amt=0.08)
kit.cone((6.5, 38, 11.4), 2.5, 1.6, trim, verts=20, amt=0.04)

# Saguaro cacti.
def saguaro(x, y, h, seed):
    r = random.Random(seed)
    kit.cyl((x, y, h / 2), 0.32, h, cactus, verts=12, amt=0.04, levels=2)
    kit.sphere((x, y, h), 0.32, cactus, amt=0.02)
    for side in (-1, 1):
        if r.random() < 0.85:
            ah = r.uniform(h * 0.35, h * 0.6)
            kit.cyl((x + side * 0.55, y, ah), 0.22, 0.9, cactus, rot=(0, math.radians(90), 0), verts=10, amt=0.03)
            kit.cyl((x + side * 0.95, y, ah + 0.7), 0.22, 1.4, cactus, verts=10, amt=0.03)
            kit.sphere((x + side * 0.95, y, ah + 1.4), 0.22, cactus, amt=0.02)

saguaro(3.1, 6.0, 1.9, 1)
saguaro(-5.0, 40, 5.0, 2)
saguaro(4.5, 48, 5.5, 3)
saguaro(-1.5, 60, 4.5, 4)

# Barrels, a hitching rail and a tumbleweed.
for (bx, by) in [(-2.7, 3.5), (2.8, 9.5), (-2.8, 16.0)]:
    kit.cyl((bx, by, 0.4), 0.33, 0.8, planks[0], verts=14, amt=0.03)
kit.cube((2.2, 4.5, 0.9), (0.1, 2.4, 0.1), trim, amt=0, levels=1)
for k in (-1, 1):
    kit.cyl((2.2, 4.5 + k * 1.1, 0.45), 0.06, 0.9, trim, verts=6)
tw = kit.sphere((0.9, 6.5, 0.45), 0.45, kit.clay2('weed', (0.45, 0.32, 0.17), bump=0.4), amt=0.1, seg=12)
wf = tw.modifiers.new('wire', 'WIREFRAME'); wf.thickness = 0.04

# Low sun behind the street, warm bounce, cool sky fill.
kit.light('SUN', (0, 0, 10), 3.2, (1.0, 0.62, 0.32), rot_deg=(-80, 0, 182), size=2)
kit.light('AREA', (0, -7, 5), 260, (1.0, 0.62, 0.55), rot_deg=(62, 0, 0), size=7)
kit.light('AREA', (0, 14, 0.6), 60, (1.0, 0.55, 0.3), size=8)

kit.camera((0.3, -1.6, 0.8), (88.0, 0, 0.5), lens=19, focus=8.0, fstop=0.8)
bpy.context.scene.view_settings.exposure = 0.1
kit.export_anchors(out.rsplit('.', 1)[0] + '.json')
kit.render(out)
