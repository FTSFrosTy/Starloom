"""Stop-motion set kit for Blender (bpy). Clay materials, hand-made lumpy
shapes, a painted sky backdrop and cheap distance haze."""
import bpy, math, random

FOG = [(0.3, 0.35, 0.5), 10.0, 40.0]  # color, start, end (set per scene)


def reset(res_x, res_y, samples):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'
    sc.cycles.samples = samples
    sc.cycles.use_denoising = True
    sc.cycles.max_bounces = 6
    sc.cycles.diffuse_bounces = 3
    sc.cycles.glossy_bounces = 2
    sc.cycles.transmission_bounces = 2
    sc.cycles.transparent_max_bounces = 4
    sc.cycles.caustics_reflective = False
    sc.cycles.caustics_refractive = False
    sc.render.resolution_x = res_x
    sc.render.resolution_y = res_y
    sc.render.resolution_percentage = 100
    sc.view_settings.view_transform = 'AgX'
    sc.view_settings.look = 'AgX - Base Contrast'
    sc.render.image_settings.file_format = 'PNG'
    w = bpy.data.worlds.new('w')
    sc.world = w
    w.use_nodes = True
    return sc


def world(color, strength=1.0):
    bg = bpy.context.scene.world.node_tree.nodes['Background']
    bg.inputs['Color'].default_value = (*color, 1)
    bg.inputs['Strength'].default_value = strength


def set_fog(color, start, end):
    FOG[0], FOG[1], FOG[2] = color, start, end


def _haze(nt, shader_out, out_node, haze=1.0):
    """Mix toward the fog color with distance from the camera."""
    cam = nt.nodes.new('ShaderNodeCameraData')
    mr = nt.nodes.new('ShaderNodeMapRange')
    mr.inputs['From Min'].default_value = FOG[1]
    mr.inputs['From Max'].default_value = FOG[2]
    mr.inputs['To Max'].default_value = 0.6 * haze
    mr.clamp = True
    nt.links.new(cam.outputs['View Distance'], mr.inputs['Value'])
    em = nt.nodes.new('ShaderNodeEmission')
    em.inputs['Color'].default_value = (*FOG[0], 1)
    em.inputs['Strength'].default_value = 1.0
    mix = nt.nodes.new('ShaderNodeMixShader')
    nt.links.new(mr.outputs['Result'], mix.inputs['Fac'])
    nt.links.new(shader_out, mix.inputs[1])
    nt.links.new(em.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out_node.inputs['Surface'])


def clay(name, color, color2=None, rough=0.58, bump=0.3, scale=1.0, sss=0.1, haze=1.0, prints=True):
    """Plasticine: soft sheen, subtle subsurface, thumb dents and fingerprint
    ridges, with a gentle color wobble between two tints."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes['Principled BSDF']
    out = nt.nodes['Material Output']
    b.inputs['Roughness'].default_value = rough
    b.inputs['Subsurface Weight'].default_value = sss
    b.inputs['Subsurface Radius'].default_value = (0.5, 0.25, 0.15)
    b.inputs['Subsurface Scale'].default_value = 0.05
    b.inputs['Specular IOR Level'].default_value = 0.35
    tc = nt.nodes.new('ShaderNodeTexCoord')
    # color wobble
    n1 = nt.nodes.new('ShaderNodeTexNoise')
    n1.inputs['Scale'].default_value = 1.6 / scale
    n1.inputs['Detail'].default_value = 3
    nt.links.new(tc.outputs['Object'], n1.inputs['Vector'])
    ramp = nt.nodes.new('ShaderNodeValToRGB')
    ramp.color_ramp.elements[0].color = (*color, 1)
    ramp.color_ramp.elements[1].color = (*(color2 or [c * 0.8 for c in color]), 1)
    nt.links.new(n1.outputs['Fac'], ramp.inputs['Fac'])
    nt.links.new(ramp.outputs['Color'], b.inputs['Base Color'])
    # surface: fine grain + thumb dents (+ fingerprint ridges)
    n2 = nt.nodes.new('ShaderNodeTexNoise')
    n2.inputs['Scale'].default_value = 40 / scale
    n2.inputs['Detail'].default_value = 8
    nt.links.new(tc.outputs['Object'], n2.inputs['Vector'])
    vor = nt.nodes.new('ShaderNodeTexVoronoi')
    vor.feature = 'SMOOTH_F1'
    vor.inputs['Scale'].default_value = 6 / scale
    nt.links.new(tc.outputs['Object'], vor.inputs['Vector'])
    add = nt.nodes.new('ShaderNodeMath')
    add.operation = 'MULTIPLY_ADD'
    add.inputs[1].default_value = 0.25
    nt.links.new(n2.outputs['Fac'], add.inputs[0])
    nt.links.new(vor.outputs['Distance'], add.inputs[2])
    height = add.outputs[0]
    if prints:
        wave = nt.nodes.new('ShaderNodeTexWave')
        wave.wave_type = 'RINGS'
        wave.inputs['Scale'].default_value = 9 / scale
        wave.inputs['Distortion'].default_value = 6
        wave.inputs['Detail'].default_value = 2
        nt.links.new(tc.outputs['Object'], wave.inputs['Vector'])
        wmask = nt.nodes.new('ShaderNodeTexNoise')
        wmask.inputs['Scale'].default_value = 3 / scale
        nt.links.new(tc.outputs['Object'], wmask.inputs['Vector'])
        gate = nt.nodes.new('ShaderNodeMapRange')
        gate.inputs['From Min'].default_value = 0.55
        gate.inputs['From Max'].default_value = 0.7
        nt.links.new(wmask.outputs['Fac'], gate.inputs['Value'])
        ridge = nt.nodes.new('ShaderNodeMath')
        ridge.operation = 'MULTIPLY'
        nt.links.new(wave.outputs['Fac'], ridge.inputs[0])
        nt.links.new(gate.outputs['Result'], ridge.inputs[1])
        ridge2 = nt.nodes.new('ShaderNodeMath')
        ridge2.operation = 'MULTIPLY_ADD'
        ridge2.inputs[1].default_value = 0.08
        nt.links.new(ridge.outputs[0], ridge2.inputs[0])
        nt.links.new(height, ridge2.inputs[2])
        height = ridge2.outputs[0]
    bp = nt.nodes.new('ShaderNodeBump')
    bp.inputs['Strength'].default_value = bump
    bp.inputs['Distance'].default_value = 0.03 * scale
    nt.links.new(height, bp.inputs['Height'])
    nt.links.new(bp.outputs['Normal'], b.inputs['Normal'])
    _haze(nt, b.outputs[0], out, haze)
    return m


def glow(name, color, strength=6.0, haze=0.5):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes['Principled BSDF']
    b.inputs['Base Color'].default_value = (*color, 1)
    b.inputs['Emission Color'].default_value = (*color, 1)
    b.inputs['Emission Strength'].default_value = strength
    _haze(nt, b.outputs[0], nt.nodes['Material Output'], haze)
    return m


def painted_sky(name, top, bottom, horizon=0.45, strength=1.0, clouds=None):
    """Emissive painted backdrop, like the hand-painted skies on real sets.
    clouds: (color, amount) soft brushy cloud bands."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new('ShaderNodeOutputMaterial')
    em = nt.nodes.new('ShaderNodeEmission')
    em.inputs['Strength'].default_value = strength
    tc = nt.nodes.new('ShaderNodeTexCoord')
    sep = nt.nodes.new('ShaderNodeSeparateXYZ')
    nt.links.new(tc.outputs['Generated'], sep.inputs[0])
    ramp = nt.nodes.new('ShaderNodeValToRGB')
    ramp.color_ramp.elements[0].position = 0.0
    ramp.color_ramp.elements[0].color = (*bottom, 1)
    ramp.color_ramp.elements[1].position = 1.0
    ramp.color_ramp.elements[1].color = (*top, 1)
    e = ramp.color_ramp.elements.new(horizon)
    e.color = (*[(a + b) / 2 for a, b in zip(top, bottom)], 1)
    nt.links.new(sep.outputs['Z'], ramp.inputs['Fac'])
    col = ramp.outputs['Color']
    if clouds:
        ccol, amt = clouds
        noise = nt.nodes.new('ShaderNodeTexNoise')
        noise.inputs['Scale'].default_value = 3.0
        noise.inputs['Detail'].default_value = 4
        noise.inputs['Roughness'].default_value = 0.6
        mapping = nt.nodes.new('ShaderNodeMapping')
        mapping.inputs['Scale'].default_value = (1.0, 1.0, 3.5)
        nt.links.new(tc.outputs['Generated'], mapping.inputs['Vector'])
        nt.links.new(mapping.outputs['Vector'], noise.inputs['Vector'])
        mr = nt.nodes.new('ShaderNodeMapRange')
        mr.inputs['From Min'].default_value = 0.52
        mr.inputs['From Max'].default_value = 0.72
        mr.inputs['To Max'].default_value = amt
        nt.links.new(noise.outputs['Fac'], mr.inputs['Value'])
        mix = nt.nodes.new('ShaderNodeMix')
        mix.data_type = 'RGBA'
        mix.inputs['B'].default_value = (*ccol, 1)
        nt.links.new(mr.outputs['Result'], mix.inputs['Factor'])
        nt.links.new(col, mix.inputs['A'])
        col = mix.outputs['Result']
    nt.links.new(col, em.inputs['Color'])
    nt.links.new(em.outputs[0], out.inputs['Surface'])
    return m


def backdrop(mat, dist=60, width=200, height=90, z0=-5):
    bpy.ops.mesh.primitive_plane_add(size=1, location=(0, dist, z0 + height / 2), rotation=(math.radians(90), 0, 0))
    o = bpy.context.object
    o.scale = (width, height, 1)
    bpy.ops.object.transform_apply(scale=True)
    o.data.materials.append(mat)
    o.visible_shadow = False
    return o


def lumpy(o, amt=0.05, scale=1.0, bevel=0.06, levels=2, seed=0):
    if bevel:
        bv = o.modifiers.new('bev', 'BEVEL')
        bv.width = bevel
        bv.segments = 2
    s = o.modifiers.new('sub', 'SUBSURF')
    s.levels = levels
    s.render_levels = levels
    if amt:
        t = bpy.data.textures.new(o.name + 't', 'CLOUDS')
        t.noise_scale = scale
        t.noise_basis = 'ORIGINAL_PERLIN'
        d = o.modifiers.new('disp', 'DISPLACE')
        d.texture = t
        d.strength = amt
        d.texture_coords = 'GLOBAL'
    return o


def cube(loc, size, mat, rot=(0, 0, 0), amt=0.04, bevel=0.05, levels=2):
    bpy.ops.mesh.primitive_cube_add(location=loc, rotation=rot)
    o = bpy.context.object
    o.scale = (size[0] / 2, size[1] / 2, size[2] / 2)
    bpy.ops.object.transform_apply(scale=True)
    o.data.materials.append(mat)
    lumpy(o, amt, bevel=bevel, levels=levels)
    return o


def cone(loc, r, depth, mat, verts=4, rot=(0, 0, 0), amt=0.03, levels=1):
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r, radius2=0, depth=depth, location=loc, rotation=rot)
    o = bpy.context.object
    o.data.materials.append(mat)
    lumpy(o, amt, bevel=0.03, levels=levels)
    return o


def sphere(loc, r, mat, scale=(1, 1, 1), amt=0.03, seg=24):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=loc, segments=seg, ring_count=seg // 2)
    o = bpy.context.object
    o.scale = scale
    o.data.materials.append(mat)
    bpy.ops.object.shade_smooth()
    if amt:
        lumpy(o, amt, bevel=0, levels=1)
    return o


def cyl(loc, r, depth, mat, rot=(0, 0, 0), verts=12, amt=0.02, levels=1):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=depth, location=loc, rotation=rot)
    o = bpy.context.object
    o.data.materials.append(mat)
    lumpy(o, amt, bevel=0.02, levels=levels)
    return o


def ground(mat, size=120, amt=0.25, scale=3.0, loc=(0, 20, 0)):
    bpy.ops.mesh.primitive_grid_add(x_subdivisions=80, y_subdivisions=80, size=size, location=loc)
    g = bpy.context.object
    g.data.materials.append(mat)
    t = bpy.data.textures.new('gt', 'CLOUDS')
    t.noise_scale = scale
    d = g.modifiers.new('disp', 'DISPLACE')
    d.texture = t
    d.strength = amt
    s = g.modifiers.new('sub', 'SUBSURF')
    s.levels = 1
    s.render_levels = 1
    bpy.ops.object.shade_smooth()
    return g


def bent_tree(root, height, mat, seed=1, depth=4, spread=0.6, thick=0.12):
    """Twisted bare tree from tapered cylinders."""
    rnd = random.Random(seed)

    def branch(p, ang, length, r, d):
        if d == 0 or length < 0.15:
            return
        dx = math.sin(ang[1]) * math.cos(ang[0])
        dy = math.sin(ang[1]) * math.sin(ang[0])
        dz = math.cos(ang[1])
        end = (p[0] + dx * length, p[1] + dy * length, p[2] + dz * length)
        mid = ((p[0] + end[0]) / 2, (p[1] + end[1]) / 2, (p[2] + end[2]) / 2)
        bpy.ops.mesh.primitive_cone_add(vertices=8, radius1=r, radius2=r * 0.62, depth=length, location=mid)
        o = bpy.context.object
        o.rotation_mode = 'XYZ'
        o.rotation_euler = (0, ang[1], ang[0])
        # cones point along local Z; rotate so Z follows (dx,dy,dz)
        o.rotation_mode = 'QUATERNION'
        from mathutils import Vector
        o.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(Vector((dx, dy, dz)))
        o.data.materials.append(mat)
        bpy.ops.object.shade_smooth()
        for _ in range(2 if d > 1 else rnd.choice([1, 2])):
            na = (ang[0] + rnd.uniform(-1.6, 1.6), min(1.35, ang[1] + rnd.uniform(-spread, spread) + 0.15))
            branch(end, na, length * rnd.uniform(0.6, 0.78), r * 0.62, d - 1)

    branch(root, (rnd.uniform(0, 6.28), rnd.uniform(0.05, 0.25)), height * 0.42, thick, depth)


def camera(loc, rot_deg, lens=35, focus=12, fstop=2.0, sensor=36):
    bpy.ops.object.camera_add(location=loc, rotation=[math.radians(a) for a in rot_deg])
    cam = bpy.context.object
    bpy.context.scene.camera = cam
    cam.data.lens = lens
    cam.data.sensor_width = sensor
    cam.data.dof.use_dof = True
    cam.data.dof.focus_distance = focus
    cam.data.dof.aperture_fstop = fstop
    cam.data.dof.aperture_blades = 6
    return cam


def light(kind, loc, energy, color, rot_deg=(0, 0, 0), size=1.0, spot=None):
    bpy.ops.object.light_add(type=kind, location=loc, rotation=[math.radians(a) for a in rot_deg])
    l = bpy.context.object
    l.data.energy = energy
    l.data.color = color
    if kind == 'AREA':
        l.data.size = size
    elif kind in ('POINT', 'SPOT'):
        l.data.shadow_soft_size = size
    if kind == 'SPOT' and spot:
        l.data.spot_size = math.radians(spot)
        l.data.spot_blend = 0.6
    if kind == 'SUN':
        l.data.angle = math.radians(size)
    return l


def render(path):
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
