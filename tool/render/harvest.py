import sys, math, random
sys.path.insert(0, __import__('os').path.dirname(__file__))
import bpy
import kit

res = int(sys.argv[-3]); samples = int(sys.argv[-2]); out = sys.argv[-1]
rnd = random.Random(11)
kit.reset(res, res, samples)
kit.world((0.55, 0.62, 0.8), 0.7)
kit.set_fog((0.95, 0.80, 0.60), 25.0, 120.0)

grass = kit.clay('grass', (0.55, 0.45, 0.16), (0.42, 0.36, 0.12), bump=0.8, scale=0.6)
dirt = kit.clay('dirt', (0.40, 0.24, 0.12), (0.30, 0.17, 0.08), bump=0.8, scale=0.5, prints=False)
pump = [kit.clay('pA', (0.95, 0.38, 0.06), (0.80, 0.28, 0.04), bump=0.5), kit.clay('pB', (0.90, 0.48, 0.10), (0.75, 0.36, 0.06), bump=0.5)]
stem = kit.clay('stem', (0.22, 0.30, 0.10), bump=0.5)
wood = kit.clay('wood', (0.38, 0.24, 0.14), (0.26, 0.15, 0.08), bump=0.7)
barn = kit.clay('barn', (0.62, 0.12, 0.08), (0.46, 0.08, 0.05), bump=0.6)
white = kit.clay('white', (0.90, 0.86, 0.78), bump=0.4)
roofm = kit.clay('roof', (0.25, 0.20, 0.20), bump=0.6)
leaves = [kit.clay('lA', (0.92, 0.42, 0.08), (0.75, 0.28, 0.05), bump=0.6, scale=0.8),
          kit.clay('lB', (0.80, 0.18, 0.08), (0.62, 0.12, 0.05), bump=0.6, scale=0.8),
          kit.clay('lC', (0.95, 0.70, 0.15), (0.80, 0.55, 0.10), bump=0.6, scale=0.8)]
straw = kit.clay('straw', (0.85, 0.68, 0.30), bump=0.8)
cloth = kit.clay('cloth', (0.30, 0.38, 0.60), bump=0.6)
hat = kit.clay('hat', (0.35, 0.25, 0.12), bump=0.5)

kit.ground(grass, size=180, amt=0.3, scale=7.0, loc=(0, 50, 0))
for k in range(44):
    yy = -2 + k * 1.2
    kit.sphere((math.sin(yy * 0.07) * 2.0 + 0.3, yy, 0.12), 1.15, dirt, scale=(1.0, 1.6, 0.06), amt=0.02, seg=12)

sky = kit.painted_sky('sky', top=(0.20, 0.42, 0.78), bottom=(0.98, 0.82, 0.58), horizon=0.38, strength=1.2,
                      clouds=((1.0, 0.97, 0.92), 0.85))
kit.backdrop(sky, dist=120, width=320, height=130, z0=-6)

# Rolling hills.
for (hx, hy, r, c) in [(-40, 90, 30, (0.45, 0.42, 0.18)), (0, 100, 34, (0.55, 0.45, 0.20)), (40, 92, 30, (0.50, 0.38, 0.16)), (-15, 70, 20, (0.60, 0.50, 0.20))]:
    kit.sphere((hx, hy, -r * 0.62), r, kit.clay('h%d' % hx, c, bump=0.6, scale=3.0), scale=(1.6, 0.7, 1), amt=0.5, seg=24)


def pumpkin(x, y, s, seed):
    r = random.Random(seed)
    body = kit.sphere((x, y, s * 0.42), s * 0.55, r.choice(pump), scale=(1.15, 1.15, 0.78), amt=0.03, seg=20)
    # ribs
    sw = body.modifiers.new('ribs', 'SIMPLE_DEFORM')
    sw.deform_method = 'TWIST'
    sw.angle = 0.2
    kit.cyl((x, y, s * 0.88), s * 0.07, s * 0.3, stem, rot=(r.uniform(-0.3, 0.3), r.uniform(-0.3, 0.3), 0), verts=6)


for k in range(90):
    side = rnd.choice((-1, 1))
    x = side * rnd.uniform(2.4, 12)
    y = rnd.uniform(-1, 30) if k > 20 else rnd.uniform(-1, 6)
    pumpkin(x, y, rnd.uniform(0.45, 0.95), 50 + k)
pumpkin(1.9, 1.0, 0.8, 1)
pumpkin(-2.2, 2.2, 0.7, 2)
pumpkin(2.8, 3.6, 0.6, 3)
pumpkin(-1.6, 0.4, 0.5, 4)

# Fence along the path.
for k in range(14):
    yy = 3 + k * 1.6
    for side in (-1, 1):
        kit.cube((side * 2.1 + math.sin(yy * 0.07) * 2.0, yy, 0.5), (0.14, 0.14, 1.0), wood, rot=(0, rnd.uniform(-0.1, 0.1), 0), amt=0.02, levels=1)
    if k < 13:
        for side in (-1, 1):
            kit.cube((side * 2.1 + math.sin((yy + 0.8) * 0.07) * 2.0, yy + 0.8, 0.75), (0.08, 1.7, 0.12), wood, rot=(rnd.uniform(-0.05, 0.05), 0, 0), amt=0.02, levels=1)

# Red barn.
bx, by = 7.5, 34
kit.cube((bx, by, 3), (8, 7, 6), barn, rot=(0, 0, 0.35), amt=0.12, bevel=0.3)
kit.cone((bx, by, 7.3), 6.2, 3.5, roofm, verts=4, rot=(0, 0, math.radians(45) + 0.35), amt=0.08)
kit.cube((bx - 3.7, by - 1.5, 2.2), (0.15, 3.2, 4.0), white, rot=(0, 0, 0.35), amt=0.04)

# Scarecrow on the left.
sx, sy = -4.2, 9
kit.cyl((sx, sy, 1.6), 0.08, 3.2, wood, verts=8)
kit.cyl((sx, sy, 2.4), 0.06, 2.4, wood, rot=(0, math.radians(90), 0), verts=8)
kit.cube((sx, sy, 2.1), (1.0, 0.5, 1.1), cloth, amt=0.08, bevel=0.15)
kit.sphere((sx, sy, 2.95), 0.36, straw, amt=0.05)
kit.cyl((sx, sy, 3.3), 0.62, 0.06, hat, verts=16)
kit.cyl((sx, sy, 3.45), 0.32, 0.35, hat, verts=16)
for side in (-1, 1):
    kit.sphere((sx + side * 1.25, sy, 2.4), 0.16, straw, scale=(1.4, 1, 1), amt=0.05)

# Autumn trees with big puffy clay canopies.
def tree(x, y, h, seed):
    r = random.Random(seed)
    kit.cyl((x, y, h * 0.35), h * 0.06, h * 0.7, wood, verts=10)
    for k in range(5):
        kit.sphere((x + r.uniform(-h * 0.25, h * 0.25), y + r.uniform(-h * 0.2, h * 0.2), h * (0.75 + r.uniform(-0.1, 0.25))),
                   h * r.uniform(0.25, 0.38), r.choice(leaves), amt=0.12, seg=16)

for k, (tx, ty, th) in enumerate([(-9, 18, 6.5), (11, 14, 7.5), (-14, 30, 8), (16, 40, 8), (-6, 44, 6), (3, 58, 7)]):
    tree(tx, ty, th, 700 + k)

# Hay bales.
for (hx, hy) in [(3.6, 6.5), (-3.8, 15)]:
    kit.cyl((hx, hy, 0.55), 0.6, 1.2, straw, rot=(math.radians(90), 0, rnd.uniform(0, 3)), verts=18, amt=0.06)

kit.light('SUN', (0, 0, 20), 4.5, (1.0, 0.80, 0.55), rot_deg=(-58, 0, 205), size=2.5)
kit.light('AREA', (0, -8, 8), 60, (0.6, 0.72, 1.0), rot_deg=(50, 0, 0), size=10)

kit.camera((0.3, -2.0, 0.75), (87.5, 0, 0.0), lens=24, focus=7.0, fstop=1.2)
bpy.context.scene.view_settings.exposure = -0.35
bpy.context.scene.view_settings.look = 'AgX - Punchy'
kit.render(out)
