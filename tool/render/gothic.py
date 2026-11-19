import sys, math, random
sys.path.insert(0, __import__('os').path.dirname(__file__))
import bpy
import kit

res = int(sys.argv[-3]); samples = int(sys.argv[-2]); out = sys.argv[-1]
rnd = random.Random(7)
kit.reset(res, res, samples)
kit.world((0.01, 0.012, 0.03), 1.0)
kit.set_fog((0.05, 0.07, 0.15), 12.0, 70.0)

walls = [
    kit.clay('wallA', (0.20, 0.13, 0.24), (0.13, 0.08, 0.17)),
    kit.clay('wallB', (0.10, 0.18, 0.20), (0.06, 0.11, 0.13)),
    kit.clay('wallC', (0.26, 0.17, 0.10), (0.16, 0.10, 0.06)),
    kit.clay('wallD', (0.14, 0.14, 0.20), (0.09, 0.09, 0.14)),
]
trim = kit.clay('trim', (0.08, 0.07, 0.1), rough=0.5)
roof = kit.clay('roof', (0.07, 0.065, 0.1), (0.05, 0.05, 0.08), bump=0.5)
street = kit.clay('street', (0.06, 0.06, 0.08), (0.035, 0.035, 0.05), bump=0.9, scale=0.35, prints=False)
lit = kit.glow('lit', (1.0, 0.56, 0.2), 9)
dim = kit.glow('dim', (0.85, 0.42, 0.16), 3)
dark = kit.clay('dark', (0.02, 0.02, 0.03), rough=0.3, prints=False)
lamp = kit.glow('lamp', (1.0, 0.7, 0.35), 18)
bark = kit.clay('bark', (0.05, 0.045, 0.06), bump=0.8, scale=0.3)

kit.ground(street, size=140, amt=0.18, scale=2.0, loc=(0, 30, 0))

sky = kit.painted_sky('sky', top=(0.012, 0.02, 0.06), bottom=(0.10, 0.16, 0.30), horizon=0.32, strength=1.0,
                      clouds=((0.16, 0.2, 0.34), 0.55))
kit.backdrop(sky, dist=95, width=260, height=130, z0=-8)

# Big moon on the backdrop, with a soft halo.
moonm = kit.glow('moon', (0.93, 0.92, 0.84), 5.5, haze=0)
kit.sphere((1.5, 88, 34), 9.5, moonm, scale=(1, 0.15, 1), amt=0.25)
halo = bpy.data.materials.new('halo'); halo.use_nodes = True
nt = halo.node_tree
for n in list(nt.nodes): nt.nodes.remove(n)
o = nt.nodes.new('ShaderNodeOutputMaterial'); em = nt.nodes.new('ShaderNodeEmission'); tr = nt.nodes.new('ShaderNodeBsdfTransparent')
mx = nt.nodes.new('ShaderNodeMixShader'); grad = nt.nodes.new('ShaderNodeTexGradient'); grad.gradient_type = 'SPHERICAL'
tc = nt.nodes.new('ShaderNodeTexCoord'); nt.links.new(tc.outputs['Object'], grad.inputs['Vector'])
pw = nt.nodes.new('ShaderNodeMath'); pw.operation = 'POWER'; pw.inputs[1].default_value = 2.2
nt.links.new(grad.outputs['Fac'], pw.inputs[0])
em.inputs['Color'].default_value = (0.55, 0.65, 0.9, 1); em.inputs['Strength'].default_value = 1.6
nt.links.new(pw.outputs[0], mx.inputs['Fac']); nt.links.new(tr.outputs[0], mx.inputs[1]); nt.links.new(em.outputs[0], mx.inputs[2])
nt.links.new(mx.outputs[0], o.inputs['Surface'])
bpy.ops.mesh.primitive_plane_add(size=1, location=(1.5, 90, 34), rotation=(math.radians(90), 0, 0))
h = bpy.context.object; h.scale = (40, 40, 1); h.data.materials.append(halo); h.visible_shadow = False


def parent_all(objs, pivot, rot):
    bpy.ops.object.empty_add(location=pivot)
    e = bpy.context.object
    for ob in objs:
        ob.parent = e
        ob.matrix_parent_inverse = e.matrix_world.inverted()
    e.rotation_euler = rot
    return e


def house(side, y, depth, height, seed):
    """Tall narrow townhouse leaning over the street, upper floors jutting out."""
    r = random.Random(seed)
    inner = 2.5 * side  # facade line
    x0 = inner + side * 1.3
    parts = []
    floors = max(3, int(height / 1.7))
    fh = height / floors
    wall = r.choice(walls)
    w = 2.6
    for f in range(floors):
        jut = 0.12 * f
        cx = x0 - side * jut / 2
        b = kit.cube((cx, y + r.uniform(-0.12, 0.12), f * fh + fh / 2), (w + jut + r.uniform(-0.2, 0.2), depth * (1 + 0.05 * f) + r.uniform(-0.15, 0.1), fh * 1.04), wall,
                     rot=(r.uniform(-0.06, 0.06), r.uniform(-0.06, 0.06), r.uniform(-0.08, 0.08)), amt=0.13, bevel=0.14)
        parts.append(b)
        # floor ledge
        parts.append(kit.cube((cx - side * 0.05, y, f * fh + 0.04), (w + jut + 0.25, depth * 1.08, 0.12), trim, amt=0.02, levels=1))
        # windows facing the street
        nwin = 1 if depth < 1.8 else 2
        for k in range(nwin):
            wy = y + (k - (nwin - 1) / 2) * depth * 0.42
            fx = cx - side * (w + jut) / 2 - side * 0.03
            on = r.random() < 0.55
            pane = kit.cube((fx, wy, f * fh + fh * 0.55), (0.08, 0.42, 0.7), lit if on else (dim if r.random() < 0.3 else dark),
                            amt=0, bevel=0.02, levels=1)
            frame = kit.cube((fx - side * 0.02, wy, f * fh + fh * 0.55), (0.06, 0.56, 0.84), trim, amt=0.01, bevel=0.02, levels=1)
            parts += [pane, frame]
            if on and r.random() < 0.5:
                kit.light('POINT', (fx - side * 0.5, wy, f * fh + fh * 0.55), 28, (1.0, 0.6, 0.3), size=0.3)
    top = floors * fh
    jt = 0.12 * floors
    rf = kit.cone((x0 - side * jt / 2, y, top + height * 0.28), (w + jt) * 0.82, height * 0.58, roof, verts=4,
                  rot=(0, 0, math.radians(45 + r.uniform(-8, 8))), amt=0.04)
    parts.append(rf)
    if r.random() < 0.7:
        parts.append(kit.cube((x0 + side * 0.5, y + depth * 0.25, top + 1.2), (0.35, 0.35, 2.4), trim, rot=(0, r.uniform(-0.15, 0.15), 0), amt=0.03))
    lean = side * -r.uniform(0.05, 0.11)
    parent_all(parts, (x0, y, 0), (r.uniform(-0.03, 0.03), lean, 0))


y = -4.0
i = 0
while y < 34:
    depth = rnd.uniform(1.5, 2.4)
    for side in (-1, 1):
        house(side, y + rnd.uniform(-0.3, 0.3) + (0.6 if side > 0 else 0), depth, rnd.uniform(6, 11.5) * (1 - y / 70), 100 + i)
        i += 1
    y += depth + rnd.uniform(0.05, 0.35)

# Spire at the end of the street.
kit.cube((0.8, 40, 7), (3.2, 3.2, 14), walls[0], rot=(0, 0.03, 0.2), amt=0.06)
kit.cone((0.8, 40, 19), 2.8, 10, roof, verts=4, rot=(0, 0.03, math.radians(30)), amt=0.05)
kit.cube((0.8 - 1.65, 40, 11), (0.1, 0.9, 1.3), lit, amt=0, levels=1)

# Street lamps.
for (lx, ly) in [(-1.8, 5.0), (1.85, 11.5), (-1.7, 19.0)]:
    kit.cyl((lx, ly, 1.3), 0.07, 2.6, trim, verts=8)
    kit.cube((lx, ly, 2.75), (0.38, 0.38, 0.5), lamp, amt=0, bevel=0.04, levels=1)
    kit.cone((lx, ly, 3.15), 0.32, 0.4, trim, verts=4, rot=(0, 0, math.radians(45)), amt=0)
    kit.light('POINT', (lx, ly, 2.6), 70, (1.0, 0.68, 0.35), size=0.25)

# A crooked bare tree on the left.
kit.bent_tree((-2.1, 7.0, 0), 5.0, bark, seed=3, depth=5, thick=0.14)
# Stars on the painted sky.
star = kit.glow('star', (0.9, 0.92, 1.0), 6, haze=0)
for k in range(70):
    kit.sphere((rnd.uniform(-40, 40), 93, rnd.uniform(14, 60)), rnd.uniform(0.08, 0.22), star, amt=0, seg=8)
# Barrels and crates by the walls, and a hanging shop sign.
wood = kit.clay('wood', (0.18, 0.10, 0.05), (0.11, 0.06, 0.03), bump=0.6)
for (bx, by) in [(-1.95, 2.6), (2.05, 8.6), (-1.9, 14.8)]:
    kit.cyl((bx, by, 0.32), 0.3, 0.64, wood, verts=14, amt=0.03)
    kit.cube((bx + (0.5 if bx < 0 else -0.5), by + 0.4, 0.22), (0.45, 0.45, 0.45), wood, rot=(0, 0, 0.3), amt=0.03)
kit.cube((1.95, 4.2, 3.1), (0.9, 0.06, 0.06), trim, amt=0, levels=1)
kit.cube((1.6, 4.2, 2.65), (0.08, 0.7, 0.55), kit.clay('sign', (0.42, 0.12, 0.10), (0.3, 0.08, 0.06)), rot=(0, 0, 0.05), amt=0.02)

# Lighting: cold moonlight from behind/above, warm bounce from the street.
kit.light('SUN', (0, 0, 20), 1.3, (0.45, 0.65, 1.0), rot_deg=(-38, 0, 195), size=2)
kit.light('AREA', (0, -2, 8), 30, (0.45, 0.55, 0.9), rot_deg=(40, 0, 0), size=4)
kit.light('AREA', (0, 10, 0.5), 45, (1.0, 0.55, 0.25), rot_deg=(0, 0, 0), size=6)

kit.camera((0.25, 0.5, 1.35), (84.0, 0, 0.6), lens=21, focus=9.0, fstop=1.4)
bpy.context.scene.view_settings.exposure = -0.25
kit.render(out)
