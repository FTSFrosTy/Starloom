"""Film finishing for rendered sets: bloom + red halation around lights,
split-tone grade, gentle chromatic fringe at the edges, vignette and grain.
Turns a clean CG render into something that reads as a photographed
stop-motion miniature."""
import sys
import numpy as np
from PIL import Image, ImageFilter


def finish(src, dst, grade=(0.0, 0.03, 0.06), warm=(0.06, 0.03, -0.02), bloom=0.55, grain=0.035, vignette=0.55, size=None, seed=1):
    im = Image.open(src).convert('RGB')
    if size:
        im = im.resize((size, size), Image.LANCZOS)
    a = np.asarray(im).astype(np.float32) / 255.0
    h, w, _ = a.shape

    # Bloom from the bright bits (windows, lamps, moon, sun).
    lum = a @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
    bright = np.clip((lum - 0.62) / 0.38, 0, 1)[..., None] * a
    bimg = Image.fromarray((np.clip(bright, 0, 1) * 255).astype(np.uint8))
    b1 = np.asarray(bimg.filter(ImageFilter.GaussianBlur(w * 0.006))).astype(np.float32) / 255
    b2 = np.asarray(bimg.filter(ImageFilter.GaussianBlur(w * 0.03))).astype(np.float32) / 255
    halation = b2 * np.array([1.0, 0.45, 0.25], dtype=np.float32)
    a = a + bloom * (0.6 * b1 + 0.8 * halation)

    # Split-tone: cool shadows, warm highlights, slightly lifted blacks.
    l = (a @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32))[..., None]
    a = a + (1 - l) ** 2 * np.array(grade, dtype=np.float32) + l ** 2 * np.array(warm, dtype=np.float32)
    a = 0.018 + a * 0.985
    # gentle S-curve
    a = np.clip(a, 0, 1)
    a = a * a * (3 - 2 * a) * 0.35 + a * 0.65

    # Chromatic fringe toward the corners (old lens).
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    cx, cy = (w - 1) / 2, (h - 1) / 2
    r = np.sqrt(((xx - cx) / cx) ** 2 + ((yy - cy) / cy) ** 2)
    shift = int(max(1, w * 0.0015))
    red = np.roll(a[..., 0], shift, axis=1)
    blue = np.roll(a[..., 2], -shift, axis=1)
    edge = np.clip(r - 0.6, 0, 1)
    a[..., 0] = a[..., 0] * (1 - edge) + red * edge
    a[..., 2] = a[..., 2] * (1 - edge) + blue * edge

    # Vignette.
    v = 1 - vignette * np.clip(r / 1.414, 0, 1) ** 2.2
    a = a * v[..., None]

    # Film grain (luma-weighted, stronger in the mids).
    rng = np.random.default_rng(seed)
    g = rng.normal(0, 1, (h, w)).astype(np.float32)
    g = np.asarray(Image.fromarray(((g * 0.25 + 0.5).clip(0, 1) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.6))).astype(np.float32) / 255 - 0.5
    mid = 4 * l[..., 0] * (1 - l[..., 0])
    a = a + (grain * (0.5 + mid))[..., None] * g[..., None] * 2

    out = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8))
    out.save(dst, quality=86, optimize=True, progressive=True) if dst.endswith('.jpg') else out.save(dst)


if __name__ == '__main__':
    finish(sys.argv[1], sys.argv[2])
