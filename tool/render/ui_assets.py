"""Renders the clay UI pieces: round button, pill button and panel, each in
three slightly different sculpts (for stop-motion "boil"), in neutral grey
plasticine on a transparent background. The app tints them per theme."""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
import kit

OUT = sys.argv[-1]
os.makedirs(OUT, exist_ok=True)


def setup(w, h):
    sc = kit.reset(w, h, 48)
    sc.render.film_transparent = True
    sc.render.image_settings.color_mode = 'RGBA'
    sc.view_settings.look = 'AgX - Base Contrast'
    kit.world((0.5, 0.5, 0.55), 0.6)
    kit.set_fog((0, 0, 0), 1000, 2000)  # no haze on UI pieces
    return sc


def lights():
    kit.light('AREA', (-3, 3, 6), 260, (1.0, 0.97, 0.92), rot_deg=(-25, -30, 0), size=4)
    kit.light('AREA', (4, -2, 3), 40, (0.85, 0.9, 1.0), rot_deg=(30, 45, 0), size=6)


def cam(ortho):
    bpy.ops.object.camera_add(location=(0, 0, 10), rotation=(0, 0, 0))
    c = bpy.context.object
    c.data.type = 'ORTHO'
    c.data.ortho_scale = ortho
    bpy.context.scene.camera = c


def render(name):
    bpy.context.scene.render.filepath = os.path.join(OUT, name)
    bpy.ops.render.render(write_still=True)


grey = None
for frame in range(3):
    # ---- round button ------------------------------------------------------
    setup(256, 256)
    grey = kit.clay2('grey', (0.62, 0.62, 0.62), (0.52, 0.52, 0.52), rough=0.45, bump=0.8, scale=0.6, sss=0.2, sheen=0.1)
    lights()
    cam(2.5)
    b = kit.sphere((0, 0, 0), 1.0, grey, scale=(1.0, 1.0, 0.42), amt=0, seg=48)
    kit.lumpy(b, 0.06 + frame * 0.005, scale=0.8 + frame * 0.15, bevel=0, levels=2)
    render(f'round_{frame}.png')

    # ---- pill button (3:1) -------------------------------------------------
    setup(384, 128)
    grey = kit.clay2('grey', (0.62, 0.62, 0.62), (0.52, 0.52, 0.52), rough=0.45, bump=0.8, scale=0.6, sss=0.2, sheen=0.1)
    lights()
    cam(3.0)
    p = kit.cube((0, 0, 0), (2.85, 0.88, 0.5), grey, amt=0, bevel=0, levels=0)
    p.modifiers.clear()
    bv = p.modifiers.new('bev', 'BEVEL'); bv.width = 0.42; bv.segments = 6; bv.affect = 'EDGES'
    kit.lumpy(p, 0.035 + frame * 0.004, scale=0.7 + frame * 0.1, bevel=0, levels=2)
    render(f'pill_{frame}.png')

# ---- panel slab (nine-slice) ------------------------------------------------
setup(384, 384)
grey = kit.clay2('grey', (0.62, 0.62, 0.62), (0.52, 0.52, 0.52), rough=0.5, bump=0.9, scale=0.5, sss=0.2, sheen=0.08)
lights()
cam(3.0)
s = kit.cube((0, 0, 0), (2.8, 2.8, 0.4), grey, amt=0, bevel=0, levels=0)
s.modifiers.clear()
bv = s.modifiers.new('bev', 'BEVEL'); bv.width = 0.28; bv.segments = 6
kit.lumpy(s, 0.03, scale=0.6, bevel=0, levels=2)
render('panel.png')
