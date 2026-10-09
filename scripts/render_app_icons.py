#!/usr/bin/env python3
"""Renders the KlimaBilanz app icons ("Alpine Glass") – reproducibly, on Linux, with Pillow + numpy only.

    python3 scripts/render_app_icons.py               # writes the asset catalog (masters + in-app previews)
    python3 scripts/render_app_icons.py --check DIR   # additionally writes home-screen check sheets to DIR
    python3 scripts/render_app_icons.py --only alpine --check DIR   # iterate on one icon

Motif: a glass summit on a living Alpine sky. The route (glacier → dusk → dawn, Theme.routeGradient) climbs the
lit face like the amortisation line in the app and ends in the break-even marker on the summit.
No text, no ÖBB / KlimaTicket marks.

Output (App/Resources/Assets.xcassets):
  AppIcon.appiconset                  primary icon "Alpine Glass": 1024 px light / dark / tinted (iOS 18+ appearances)
  AppIcon-<Name>.appiconset           alternate icons (Nacht, Sonnenaufgang, Gletscher, Minimal), same three appearances
  AppIconPreview-<Name>.imageset      336 px light + dark previews for Einstellungen › Darstellung › App-Symbol

The asset catalog uses Xcode's single-size format: actool derives every device size (180, 120, 167, 152, 80, 58, 40 …)
from the 1024 px master at build time, so only the masters are committed. `--check` renders those small sizes
(and the tinted home screen) so they can be judged before committing.

Everything is computed in float sRGB at 1024 px; shapes are rasterised at 4× and box-filtered (exact coverage),
gradients interpolate in OKLab (no grey mid-tones between blue and orange). No randomness except seeded stars.
"""
from __future__ import annotations

import argparse
import json
import math
import os
import sys
from dataclasses import dataclass

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG = os.path.join(ROOT, "App", "Resources", "Assets.xcassets")

N = 1024          # master size
SS = 4            # supersampling of shape masks
PREVIEW = 336     # in-app preview size (112 pt @3x)

# ----------------------------------------------------------------------------------------------------------------------
# Colour


def hex_rgb(value: str) -> np.ndarray:
    value = value.lstrip("#")
    return np.array([int(value[i:i + 2], 16) / 255.0 for i in (0, 2, 4)], dtype=np.float64)


def _srgb_to_linear(c):
    c = np.asarray(c, dtype=np.float64)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def _linear_to_srgb(c):
    c = np.clip(c, 0, None)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1 / 2.4) - 0.055)


_M1 = np.array([[0.4122214708, 0.5363325363, 0.0514459929],
                [0.2119034982, 0.6806995451, 0.1073969566],
                [0.0883024619, 0.2817188376, 0.6299787005]])
_M2 = np.array([[0.2104542553, 0.7936177850, -0.0040720468],
                [1.9779984951, -2.4285922050, 0.4505937099],
                [0.0259040371, 0.7827717662, -0.8086757660]])


def to_oklab(rgb):
    lms = _srgb_to_linear(rgb) @ _M1.T
    return np.cbrt(lms) @ _M2.T


def from_oklab(lab):
    lms = (lab @ np.linalg.inv(_M2).T) ** 3
    return np.clip(_linear_to_srgb(lms @ np.linalg.inv(_M1).T), 0, 1)


def ramp(t: np.ndarray, stops) -> tuple[np.ndarray, np.ndarray]:
    """Colour (H,W,3) and alpha (H,W) along `t` for stops [(pos, "#hex", alpha), …], interpolated in OKLab."""
    pos = np.array([s[0] for s in stops])
    labs = np.array([to_oklab(hex_rgb(s[1])) for s in stops])
    alphas = np.array([s[2] if len(s) > 2 else 1.0 for s in stops])
    t = np.clip(t, pos[0], pos[-1])
    lab = np.stack([np.interp(t, pos, labs[:, i]) for i in range(3)], axis=-1)
    return from_oklab(lab), np.interp(t, pos, alphas)


def gray(level: float) -> str:
    v = int(round(np.clip(level, 0, 1) * 255))
    return f"#{v:02X}{v:02X}{v:02X}"


# ----------------------------------------------------------------------------------------------------------------------
# Geometry & rasterisation

_YY, _XX = np.mgrid[0:N, 0:N].astype(np.float64) + 0.5


def linear_t(p0, p1):
    dx, dy = p1[0] - p0[0], p1[1] - p0[1]
    return ((_XX - p0[0]) * dx + (_YY - p0[1]) * dy) / (dx * dx + dy * dy)


def radial_t(center, radius, squash=1.0):
    return np.hypot(_XX - center[0], (_YY - center[1]) / squash) / radius


def rounded(points, radius: float, steps: int = 10):
    """Replaces every corner by a quadratic curve – soft, Liquid-Glass-like geometry."""
    if radius <= 0:
        return list(points)
    out = []
    n = len(points)
    for i in range(n):
        p = np.array(points[i], dtype=np.float64)
        a = np.array(points[i - 1], dtype=np.float64)
        b = np.array(points[(i + 1) % n], dtype=np.float64)
        da, db = a - p, b - p
        la, lb = np.linalg.norm(da), np.linalg.norm(db)
        if la < 1e-6 or lb < 1e-6:
            out.append(tuple(p))
            continue
        r = min(radius, la / 2, lb / 2)
        p1, p2 = p + da / la * r, p + db / lb * r
        for k in range(steps + 1):
            u = k / steps
            q = (1 - u) ** 2 * p1 + 2 * (1 - u) * u * p + u ** 2 * p2
            out.append((q[0], q[1]))
    return out


def rounded_open(points, radius: float, steps: int = 10):
    """Like `rounded` for an open polyline (end points stay)."""
    if radius <= 0 or len(points) < 3:
        return list(points)
    out = [points[0]]
    for i in range(1, len(points) - 1):
        p = np.array(points[i], dtype=np.float64)
        a, b = np.array(points[i - 1], dtype=np.float64), np.array(points[i + 1], dtype=np.float64)
        da, db = a - p, b - p
        la, lb = np.linalg.norm(da), np.linalg.norm(db)
        r = min(radius, la / 2, lb / 2)
        p1, p2 = p + da / la * r, p + db / lb * r
        for k in range(steps + 1):
            u = k / steps
            q = (1 - u) ** 2 * p1 + 2 * (1 - u) * u * p + u ** 2 * p2
            out.append((q[0], q[1]))
    out.append(points[-1])
    return out


def _canvas():
    return Image.new("L", (N * SS, N * SS), 0)


def _coverage(img: Image.Image) -> np.ndarray:
    return np.asarray(img.reduce(SS), dtype=np.float64) / 255.0


def polygon(points, radius: float = 0) -> np.ndarray:
    img = _canvas()
    pts = [(x * SS, y * SS) for x, y in rounded(points, radius)]
    ImageDraw.Draw(img).polygon(pts, fill=255)
    return _coverage(img)


def stroke(points, width: float, radius: float = 0) -> np.ndarray:
    """Round-capped, round-joined polyline: one quad per segment plus a disc at every vertex."""
    img = _canvas()
    draw = ImageDraw.Draw(img)
    pts = [(x * SS, y * SS) for x, y in rounded_open(points, radius)]
    h = width * SS / 2
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        dx, dy = x1 - x0, y1 - y0
        length = math.hypot(dx, dy)
        if length < 1e-6:
            continue
        nx, ny = -dy / length * h, dx / length * h
        draw.polygon([(x0 + nx, y0 + ny), (x1 + nx, y1 + ny), (x1 - nx, y1 - ny), (x0 - nx, y0 - ny)], fill=255)
    for x, y in pts:
        draw.ellipse((x - h, y - h, x + h, y + h), fill=255)
    return _coverage(img)


def circle(center, radius: float) -> np.ndarray:
    img = _canvas()
    x, y, r = center[0] * SS, center[1] * SS, radius * SS
    ImageDraw.Draw(img).ellipse((x - r, y - r, x + r, y + r), fill=255)
    return _coverage(img)


def ring(center, radius: float, width: float) -> np.ndarray:
    return np.clip(circle(center, radius) - circle(center, radius - width), 0, 1)


def blur(a: np.ndarray, sigma: float) -> np.ndarray:
    """Gaussian blur (FFT, edge-padded) for (H,W) or (H,W,C) float arrays."""
    if sigma <= 0:
        return a
    pad = int(math.ceil(3 * sigma))
    widths = ((pad, pad), (pad, pad)) + ((0, 0),) * (a.ndim - 2)
    p = np.pad(a, widths, mode="edge")
    h, w = p.shape[:2]
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.rfftfreq(w)[None, :]
    kernel = np.exp(-2 * (math.pi ** 2) * (sigma ** 2) * (fx ** 2 + fy ** 2))
    if a.ndim == 3:
        kernel = kernel[..., None]
    out = np.fft.irfft2(np.fft.rfft2(p, axes=(0, 1)) * kernel, s=(h, w), axes=(0, 1))
    return out[pad:pad + a.shape[0], pad:pad + a.shape[1]]


def shift(a: np.ndarray, dx: int, dy: int) -> np.ndarray:
    out = np.zeros_like(a)
    ys, yd = (slice(0, N - dy), slice(dy, N)) if dy >= 0 else (slice(-dy, N), slice(0, N + dy))
    xs, xd = (slice(0, N - dx), slice(dx, N)) if dx >= 0 else (slice(-dx, N), slice(0, N + dx))
    out[yd, xd] = a[ys, xs]
    return out


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def rim(mask: np.ndarray, width: float, light=(-0.55, -0.83), focus: float = 1.6) -> np.ndarray:
    """Inner specular band of a glass shape, brightest where the edge faces the light (default: top-left)."""
    soft = blur(mask, width)
    band = mask * (1 - smoothstep(0.5, 0.98, soft))
    gy, gx = np.gradient(soft)
    length = np.hypot(gx, gy) + 1e-9
    # outward normal = −gradient
    facing = np.clip((-gx * light[0] - gy * light[1]) / length, 0, 1) ** focus
    return band * facing


# ----------------------------------------------------------------------------------------------------------------------
# Compositing


class Canvas:
    def __init__(self, base):
        self.rgb = np.broadcast_to(np.asarray(base, dtype=np.float64), (N, N, 3)).copy()

    def paint(self, color, alpha):
        """Source-over with a colour (3,) or field (H,W,3) and coverage/alpha (H,W)."""
        color = np.asarray(color, dtype=np.float64)
        if color.ndim == 1:
            color = color[None, None, :]
        a = np.clip(alpha, 0, 1)[..., None]
        self.rgb = self.rgb * (1 - a) + color * a

    def paint_ramp(self, t, stops, mask=1.0):
        color, alpha = ramp(t, stops)
        self.paint(color, alpha * mask)

    def screen(self, color, alpha):
        color = np.asarray(color, dtype=np.float64)
        if color.ndim == 1:
            color = color[None, None, :]
        a = np.clip(alpha, 0, 1)[..., None]
        self.rgb = 1 - (1 - self.rgb) * (1 - color * a)

    def image(self) -> Image.Image:
        return Image.fromarray(np.round(np.clip(self.rgb, 0, 1) * 255).astype(np.uint8), "RGB")


def stars(canvas: Canvas, count: int, seed: int, region, color="#FFFFFF", max_alpha=0.9, avoid=None, sizes=(1.6, 4.2)):
    rng = np.random.default_rng(seed)
    x0, y0, x1, y1 = region
    placed = 0
    attempts = 0
    while placed < count and attempts < count * 40:
        attempts += 1
        x, y = rng.uniform(x0, x1), rng.uniform(y0, y1)
        if avoid is not None and avoid[int(min(y, N - 1)), int(min(x, N - 1))] > 0.02:
            continue
        r = rng.uniform(*sizes) * (1.0 if rng.uniform() > 0.18 else 1.6)
        a = rng.uniform(0.35, 1.0) * max_alpha
        dot = circle((x, y), r)
        canvas.paint(hex_rgb(color), dot * a)
        if r > sizes[1] * 1.2:  # a few brighter stars get a halo
            canvas.paint(hex_rgb(color), blur(dot, r * 2.2) * a * 0.9)
        placed += 1


# ----------------------------------------------------------------------------------------------------------------------
# The Alpine Glass scene

# Summit + ridges on the 1024 grid (the system mask cuts ~10 % at the corners; everything that matters sits inside).
APEX = (548.0, 262.0)
# left skyline of the summit = the amortisation line (the route is drawn exactly on it)
SKYLINE = [(-40, 846), (112, 760), (206, 790), (370, 566), (426, 600), APEX]
MAIN = SKYLINE + [(650, 428), (704, 396), (842, 566), (1084, 760), (1084, 1084), (-40, 1084)]
# shadow facet below the summit (light comes from the top left)
# shaded east face; its shadow fades out towards the valley so the faces read as one body of glass
FACET = [APEX, (650, 428), (704, 396), (842, 566), (1084, 760), (1084, 1084), (730, 1084), (650, 780), (636, 576),
         (596, 452)]
FAR = [(-60, 640), (96, 566), (214, 628), (330, 530), (470, 600), (676, 452), (800, 352), (918, 446), (1084, 396),
       (1084, 1084), (-60, 1084)]
ROUTE = SKYLINE


@dataclass
class Look:
    sky: list                 # vertical sky stops (pos, hex[, alpha])
    sky_tilt: tuple = (0.0, 0.0, 0.35, 1.0)   # gradient direction in unit coords
    glow: str | None = None   # warm glow behind the summit
    glow_alpha: float = 0.8
    glow_radius: float = 470
    sun: tuple | None = None  # (top hex, bottom hex) of a sun disc behind the summit
    sun_center: tuple = (628, 318)
    sun_radius: float = 150
    moon: bool = False
    star_count: int = 0
    far_alpha: tuple = (0.26, 0.05)
    far_color: str = "#FFFFFF"
    glass_top: float = 0.96   # white mix of the glass at the summit …
    glass_bottom: float = 0.66  # … and at the foot
    glass_white: str = "#FFFFFF"
    glass_tint: str = "#E3E8FA"  # bottom colour of the glass
    shade: str = "#B9C3F0"     # shadow face colour
    shade_alpha: float = 0.55
    sheen: float = 0.16       # diagonal light band across the glass
    frost: float = 26          # blur radius of the sky seen through the glass
    rim_color: str = "#FFFFFF"
    rim_alpha: float = 0.9
    edge_glow: float = 0.0     # outer glow of the glass silhouette (dark looks)
    shadow_alpha: float = 0.22
    route: list = None         # route stops along the climb
    route_width: float = 54
    route_glow: float = 0.45
    route_casing: str | None = None
    route_shadow: str | None = None
    marker_ring: str = "#FFFFFF"
    marker_fill: str = "#FF8550"
    marker_glow: str = "#FFB08A"


ALPINE_ROUTE = [(0, "#3C95FF"), (0.5, "#7F6BFF"), (0.86, "#FF7E55"), (1, "#FF8A50")]
ALPINE_ROUTE_DARK = [(0, "#6CB6FF"), (0.55, "#A99FFF"), (1, "#FFAD85")]

LOOKS: dict[str, dict[str, Look]] = {}


def look(icon: str, appearance: str, **kw):
    LOOKS.setdefault(icon, {})[appearance] = Look(**kw)


# Alpine Glass – the primary icon: morning sky, glass summit, route to the dawn marker.
look("alpine", "light",
     sky=[(0, "#15348F"), (0.45, "#3A46BE"), (0.8, "#7354C8"), (1, "#A060B8")],
     glow="#FFB48C", glow_alpha=0.95, glow_radius=420, far_alpha=(0.20, 0.05), route=ALPINE_ROUTE, route_glow=0.5,
     route_shadow="#0E1550", star_count=0)
look("alpine", "dark",
     sky=[(0, "#050C22"), (0.5, "#13194A"), (0.85, "#2B2366"), (1, "#3E2A6E")],
     glow="#FF8FAB", glow_alpha=0.42, glow_radius=430, star_count=14,
     far_alpha=(0.16, 0.03), glass_top=0.36, glass_bottom=0.08, glass_tint="#6A80E0", shade="#0B1238", shade_alpha=0.42,
     frost=30, rim_alpha=0.95, edge_glow=0.20, shadow_alpha=0.45,
     route=ALPINE_ROUTE_DARK, route_glow=0.7, marker_fill="#FF9A6E", marker_glow="#FF8FAB")
look("alpine", "tinted",
     sky=[(0, "#000000"), (1, "#0A0A0A")], glow="#3A3A3A", glow_alpha=0.85, star_count=0,
     far_alpha=(0.20, 0.04), glass_top=0.86, glass_bottom=0.40, glass_tint="#7A7A7A", shade="#5A5A5A", shade_alpha=0.5,
     frost=24, rim_alpha=1.0, shadow_alpha=0.3,
     route=[(0, "#FFFFFF"), (1, "#FFFFFF")], route_glow=0.0, route_casing="#2A2A2A",
     marker_ring="#FFFFFF", marker_fill="#3A3A3A", marker_glow="#555555")

# Nacht – blue hour: stars, crescent moon, dark glass with a moonlit rim, luminous route.
look("nacht", "light",
     sky=[(0, "#030716"), (0.55, "#0C1A44"), (1, "#1D3170")], glow="#4F7BFF", glow_alpha=0.30, glow_radius=520,
     moon=True, star_count=26,
     far_alpha=(0.14, 0.02), far_color="#A9C8FF", glass_top=0.26, glass_bottom=0.05, glass_tint="#6C8DE0",
     shade="#050B24", shade_alpha=0.50, frost=30, rim_color="#DDE9FF", rim_alpha=1.0, edge_glow=0.26, shadow_alpha=0.5,
     route=[(0, "#33D1E0"), (0.6, "#6CB6FF"), (1, "#C9B8FF")], route_glow=0.85,
     marker_ring="#FFFFFF", marker_fill="#FFD27A", marker_glow="#FFE6A8")
look("nacht", "dark",
     sky=[(0, "#000208"), (0.55, "#070F2C"), (1, "#122158")], glow="#4F7BFF", glow_alpha=0.22, glow_radius=520,
     moon=True, star_count=26,
     far_alpha=(0.11, 0.02), far_color="#A9C8FF", glass_top=0.22, glass_bottom=0.04, glass_tint="#5A78D0",
     shade="#03081C", shade_alpha=0.55, frost=30, rim_color="#DDE9FF", rim_alpha=0.95, edge_glow=0.22, shadow_alpha=0.55,
     route=[(0, "#33D1E0"), (0.6, "#6CB6FF"), (1, "#C9B8FF")], route_glow=0.8,
     marker_ring="#FFFFFF", marker_fill="#FFD27A", marker_glow="#FFE6A8")
look("nacht", "tinted",
     sky=[(0, "#000000"), (1, "#101010")], moon=True, star_count=22, glow=None,
     far_alpha=(0.14, 0.02), glass_top=0.30, glass_bottom=0.06, glass_tint="#808080", shade="#000000", shade_alpha=0.5,
     frost=30, rim_alpha=1.0, edge_glow=0.22, shadow_alpha=0.5,
     route=[(0, "#FFFFFF"), (1, "#FFFFFF")], route_glow=0.5, marker_fill="#FFFFFF", marker_glow="#999999")

# Sonnenaufgang – the summit as a silhouette in front of a rising sun.
look("sonnenaufgang", "light",
     sky=[(0, "#4B3FC9"), (0.40, "#B45BC0"), (0.72, "#F27D7F"), (1, "#FFB86E")], sky_tilt=(0.0, 0.0, 0.0, 1.0),
     glow="#FFD9A0", glow_alpha=0.75, glow_radius=520, sun=("#FFF4D6", "#FFC46E"), sun_center=(628, 334),
     sun_radius=176,
     far_alpha=(0.26, 0.08), far_color="#FFD6C4", glass_top=0.62, glass_bottom=0.86, glass_white="#7B3F8C",
     glass_tint="#3A1F66", shade="#24124A", shade_alpha=0.6, frost=26, rim_color="#FFE9C4", rim_alpha=1.0,
     edge_glow=0.18, shadow_alpha=0.25, route=[(0, "#FFFFFF"), (0.65, "#FFF0C8"), (1, "#FFD27A")], route_glow=0.35,
     marker_ring="#FFFFFF", marker_fill="#FF7A4A", marker_glow="#FFF0C8")
look("sonnenaufgang", "dark",
     sky=[(0, "#160E3E"), (0.45, "#4A1F6E"), (0.78, "#A2406E"), (1, "#E8735A")], sky_tilt=(0.0, 0.0, 0.0, 1.0),
     glow="#FF9A6E", glow_alpha=0.55, glow_radius=500, sun=("#FFE2B0", "#FF9A5A"), sun_center=(628, 334),
     sun_radius=176,
     far_alpha=(0.18, 0.05), far_color="#FFB8A8", glass_top=0.66, glass_bottom=0.9, glass_white="#4A2266",
     glass_tint="#1A0C34", shade="#0E0622", shade_alpha=0.6, frost=26, rim_color="#FFE1C0", rim_alpha=0.95,
     edge_glow=0.16, shadow_alpha=0.4, route=[(0, "#FFFFFF"), (0.65, "#FFE6B8"), (1, "#FFC46E")], route_glow=0.5,
     marker_ring="#FFFFFF", marker_fill="#FF7A4A", marker_glow="#FFE6B8")
look("sonnenaufgang", "tinted",
     sky=[(0, "#050505"), (1, "#202020")], sky_tilt=(0.0, 0.0, 0.0, 1.0), glow="#5A5A5A", glow_alpha=0.6,
     sun=("#FFFFFF", "#C8C8C8"), sun_center=(628, 334), sun_radius=176,
     far_alpha=(0.18, 0.04), glass_top=0.6, glass_bottom=0.85, glass_white="#2A2A2A", glass_tint="#101010",
     shade="#000000", shade_alpha=0.5, frost=26, rim_alpha=1.0, shadow_alpha=0.3,
     route=[(0, "#FFFFFF"), (1, "#FFFFFF")], route_glow=0.2, route_casing="#000000",
     marker_ring="#FFFFFF", marker_fill="#9A9A9A", marker_glow="#777777")

# Gletscher – ice: pale cold sky, crystal glass with turquoise facets, deep glacier-blue route.
look("gletscher", "light",
     sky=[(0, "#F4FBFF"), (0.45, "#CFEAFB"), (1, "#8CCBEF")], sky_tilt=(0.2, 0.0, 0.6, 1.0),
     glow="#FFFFFF", glow_alpha=0.75, glow_radius=420,
     far_alpha=(0.55, 0.20), far_color="#FFFFFF", glass_top=0.70, glass_bottom=0.30, glass_white="#FFFFFF",
     glass_tint="#5CC3DE", shade="#3D9DD0", shade_alpha=0.55, frost=22, rim_color="#FFFFFF", rim_alpha=1.0,
     shadow_alpha=0.18, route=[(0, "#1D5FB0"), (0.6, "#2A7BD4"), (1, "#1FA9B8")], route_glow=0.25,
     marker_ring="#FFFFFF", marker_fill="#1FA9B8", marker_glow="#FFFFFF")
look("gletscher", "dark",
     sky=[(0, "#02121E"), (0.55, "#06304A"), (1, "#0B5070")], sky_tilt=(0.2, 0.0, 0.6, 1.0),
     glow="#4FD3DD", glow_alpha=0.30, glow_radius=460, star_count=8,
     far_alpha=(0.16, 0.03), far_color="#A8F0FF", glass_top=0.30, glass_bottom=0.06, glass_white="#E6FBFF",
     glass_tint="#2AA6C8", shade="#021A2A", shade_alpha=0.5, frost=26, rim_color="#CFFAFF", rim_alpha=1.0,
     edge_glow=0.22, shadow_alpha=0.5, route=[(0, "#6CB6FF"), (0.6, "#4FD3DD"), (1, "#A8F0FF")], route_glow=0.7,
     marker_ring="#FFFFFF", marker_fill="#4FD3DD", marker_glow="#A8F0FF")
look("gletscher", "tinted",
     sky=[(0, "#000000"), (1, "#121212")], glow="#2C2C2C", glow_alpha=0.8,
     far_alpha=(0.18, 0.03), glass_top=0.80, glass_bottom=0.30, glass_tint="#707070", shade="#3A3A3A", shade_alpha=0.6,
     frost=22, rim_alpha=1.0, shadow_alpha=0.3,
     route=[(0, "#FFFFFF"), (1, "#FFFFFF")], route_glow=0.0, route_casing="#1A1A1A",
     marker_ring="#FFFFFF", marker_fill="#3A3A3A", marker_glow="#555555")

ICON_ORDER = ["alpine", "nacht", "sonnenaufgang", "gletscher", "minimal"]
ASSET_NAMES = {
    "alpine": "AppIcon",
    "nacht": "AppIcon-Nacht",
    "sonnenaufgang": "AppIcon-Sonnenaufgang",
    "gletscher": "AppIcon-Gletscher",
    "minimal": "AppIcon-Minimal",
}
PREVIEW_NAMES = {
    "alpine": "AppIconPreview-Alpin",
    "nacht": "AppIconPreview-Nacht",
    "sonnenaufgang": "AppIconPreview-Sonnenaufgang",
    "gletscher": "AppIconPreview-Gletscher",
    "minimal": "AppIconPreview-Minimal",
}


def render_scene(lk: Look) -> Image.Image:
    sx0, sy0, sx1, sy1 = lk.sky_tilt
    c = Canvas(hex_rgb(lk.sky[0][1]))
    c.paint_ramp(linear_t((sx0 * N, sy0 * N), (sx1 * N, sy1 * N)), lk.sky)

    main = polygon(MAIN, radius=14)
    far = polygon(FAR, radius=10)

    if lk.glow:
        c.paint_ramp(radial_t((APEX[0] + 90, APEX[1] + 110), lk.glow_radius, squash=0.92),
                     [(0, lk.glow, lk.glow_alpha), (0.45, lk.glow, lk.glow_alpha * 0.45), (1, lk.glow, 0)])
    if lk.star_count:
        stars(c, lk.star_count, seed=7 + lk.star_count, region=(60, 50, 980, 520),
              avoid=np.clip(blur(far, 18) * 3, 0, 1) + circle(APEX, 170)
              + (circle((lk.sun_center if lk.sun else (790, 210)), 150) if (lk.moon or lk.sun) else 0),
              max_alpha=0.85)
    if lk.moon:
        moon_c, moon_r = (792, 214), 70
        disc = np.clip(circle(moon_c, moon_r) - circle((moon_c[0] + 34, moon_c[1] - 22), moon_r * 0.92), 0, 1)
        c.paint(hex_rgb("#FFF3D6"), blur(disc, 30) * 0.45)
        c.paint(hex_rgb("#FFF6E2"), disc)
    if lk.sun:
        sc, sr = lk.sun_center, lk.sun_radius
        halo = blur(circle(sc, sr), 46)
        c.paint(hex_rgb(lk.sun[0]), halo * 0.55)
        sun_color, _ = ramp(linear_t((sc[0], sc[1] - sr), (sc[0], sc[1] + sr)), [(0, lk.sun[0]), (1, lk.sun[1])])
        c.paint(sun_color, circle(sc, sr))

    # far ridge: frosted, light from above
    under = blur(c.rgb, lk.frost)
    c.paint(under, far)
    c.paint_ramp(linear_t((0, 330), (0, 900)), [(0, lk.far_color, lk.far_alpha[0]), (1, lk.far_color, lk.far_alpha[1])], far)
    c.paint(hex_rgb(lk.rim_color), rim(far, 3.0) * 0.55 * lk.rim_alpha)

    # soft contact shadow of the main glass onto the sky / far ridge
    shadow = blur(shift(main, 0, 18), 26) * (1 - main)
    c.paint(np.zeros(3), shadow * lk.shadow_alpha)
    if lk.edge_glow:
        c.paint(hex_rgb(lk.rim_color), blur(main, 22) * (1 - main) * lk.edge_glow)

    # main summit: frosted glass = blurred sky + white body, cooler shadow face, specular rim
    under = blur(c.rgb, lk.frost)
    body, body_alpha = ramp(linear_t((0, APEX[1]), (0, 1000)),
                            [(0, lk.glass_white, lk.glass_top), (0.55, lk.glass_white, (lk.glass_top + lk.glass_bottom) / 2),
                             (1, lk.glass_tint, lk.glass_bottom)])
    glass = under * (1 - body_alpha[..., None]) + body * body_alpha[..., None]
    c.paint(glass, main)
    # light from the top left: the glass cools towards the bottom right, the facet below the summit is in shadow
    c.paint_ramp(linear_t((380, 360), (1000, 980)), [(0, lk.shade, 0), (1, lk.shade, lk.shade_alpha)], main)
    facet = blur(polygon(FACET, radius=8), 1.5) * main
    c.paint_ramp(linear_t((0, APEX[1]), (0, 1000)),
                 [(0, lk.shade, lk.shade_alpha * 0.95), (0.3, lk.shade, lk.shade_alpha * 0.5), (0.62, lk.shade, 0.0)], facet)
    # diagonal sheen across the glass
    t = linear_t((180, 980), (760, 300))
    c.paint(hex_rgb(lk.glass_white), np.exp(-((t - 0.52) / 0.16) ** 2) * main * lk.sheen)
    c.paint(hex_rgb(lk.rim_color), rim(main, 5.0) * lk.rim_alpha)
    c.paint(hex_rgb(lk.rim_color), rim(main, 2.0, light=(0.6, -0.8)) * lk.rim_alpha * 0.45)

    # route on the skyline: soft shadow + glow, (casing), gradient stroke
    route_color, _ = ramp(linear_t((ROUTE[0][0] + 80, ROUTE[0][1]), APEX), lk.route)
    line = stroke(ROUTE, lk.route_width, radius=14)
    if lk.route_shadow:
        c.paint(hex_rgb(lk.route_shadow), blur(shift(line, 0, 10), 12) * (1 - line) * 0.45)
    if lk.route_glow:
        c.paint(route_color, blur(line, 20) * lk.route_glow * (1 - line))
    if lk.route_casing:
        c.paint(hex_rgb(lk.route_casing), stroke(ROUTE, lk.route_width + 22, radius=14))
    c.paint(route_color, line)

    # break-even marker on the summit
    if lk.route_shadow:
        c.paint(hex_rgb(lk.route_shadow), blur(shift(circle(APEX, 64), 0, 12), 14) * 0.45)
    c.paint(hex_rgb(lk.marker_glow), blur(circle(APEX, 70), 28) * 0.8)
    c.paint(hex_rgb(lk.marker_ring), circle(APEX, 64))
    c.paint(hex_rgb(lk.marker_fill), circle(APEX, 40))
    return c.image()


def render_minimal(appearance: str) -> Image.Image:
    """Minimal: one continuous line – the climb in the route gradient, the descent in ink – and the dawn marker."""
    if appearance == "light":
        bg, glow, ink, route, marker, ring_c = "#F7F9FC", "#E6ECF3", "#0C1A2B", ALPINE_ROUTE, "#F08A5B", "#FFFFFF"
    elif appearance == "dark":
        bg, glow, ink, route, marker, ring_c = "#08132A", "#13214A", "#F3F7FC", ALPINE_ROUTE_DARK, "#FFAD85", "#08132A"
    else:
        bg, glow, ink, route, marker, ring_c = "#000000", "#111111", "#9A9A9A", [(0, "#FFFFFF"), (1, "#FFFFFF")], "#FFFFFF", "#000000"
    c = Canvas(hex_rgb(bg))
    c.paint_ramp(radial_t((512, 300), 760), [(0, glow, 1.0), (1, glow, 0.0)])
    apex = (512, 300)
    climb = [(170, 742), (300, 586), (372, 630), apex]
    descent = [apex, (630, 488), (690, 446), (856, 742)]
    width = 58
    descent_line = stroke(descent, width, radius=30)
    c.paint(hex_rgb(ink), descent_line)
    route_color, _ = ramp(linear_t(climb[0], apex), route)
    climb_line = stroke(climb, width, radius=30)
    c.paint(route_color, climb_line)
    c.paint(hex_rgb(ring_c), circle(apex, 66))
    c.paint(hex_rgb(marker), circle(apex, 44))
    return c.image()


def render(icon: str, appearance: str) -> Image.Image:
    if icon == "minimal":
        img = render_minimal(appearance)
    else:
        img = render_scene(LOOKS[icon][appearance])
    if appearance == "tinted":
        img = img.convert("L").convert("RGB")
    return img


# ----------------------------------------------------------------------------------------------------------------------
# Output


def write_json(path: str, payload: dict):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2, ensure_ascii=False)
        f.write("\n")


def save_png(img: Image.Image, path: str):
    img.save(path, "PNG", optimize=True)


def write_icon_set(icon: str, images: dict[str, Image.Image]):
    name = ASSET_NAMES[icon]
    folder = os.path.join(CATALOG, f"{name}.appiconset")
    os.makedirs(folder, exist_ok=True)
    for entry in os.listdir(folder):
        if entry.endswith(".png"):
            os.remove(os.path.join(folder, entry))
    files = {"light": f"{name}.png", "dark": f"{name}-Dark.png", "tinted": f"{name}-Tinted.png"}
    entries = []
    for appearance in ("light", "dark", "tinted"):
        save_png(images[appearance], os.path.join(folder, files[appearance]))
        entry = {"filename": files[appearance], "idiom": "universal", "platform": "ios", "size": "1024x1024"}
        if appearance != "light":
            entry = {"appearances": [{"appearance": "luminosity", "value": appearance}], **entry}
        entries.append(entry)
    write_json(os.path.join(folder, "Contents.json"), {"images": entries, "info": {"author": "xcode", "version": 1}})


def write_preview_set(icon: str, images: dict[str, Image.Image]):
    name = PREVIEW_NAMES[icon]
    folder = os.path.join(CATALOG, f"{name}.imageset")
    os.makedirs(folder, exist_ok=True)
    for entry in os.listdir(folder):
        if entry.endswith(".png"):
            os.remove(os.path.join(folder, entry))
    entries = []
    for appearance in ("light", "dark"):
        filename = f"{name}{'' if appearance == 'light' else '-Dark'}.png"
        save_png(images[appearance].resize((PREVIEW, PREVIEW), Image.LANCZOS), os.path.join(folder, filename))
        entry = {"filename": filename, "idiom": "universal"}
        if appearance == "dark":
            entry = {"appearances": [{"appearance": "luminosity", "value": "dark"}], **entry}
        entries.append(entry)
    write_json(os.path.join(folder, "Contents.json"), {"images": entries, "info": {"author": "xcode", "version": 1}})


# ---- check sheets (not committed) ------------------------------------------------------------------------------------


def squircle_mask(size: int) -> Image.Image:
    """iOS icon mask approximation (continuous corners, radius 22.37 %)."""
    s = size * SS
    img = Image.new("L", (s, s), 0)
    ImageDraw.Draw(img).rounded_rectangle((0, 0, s - 1, s - 1), radius=s * 0.2237, fill=255)
    return img.resize((size, size), Image.LANCZOS)


def masked(img: Image.Image, size: int) -> Image.Image:
    small = img.resize((size, size), Image.LANCZOS).convert("RGBA")
    small.putalpha(squircle_mask(size))
    return small


def tinted_preview(img: Image.Image, tint="#7CC4FF") -> Image.Image:
    lum = np.asarray(img.convert("L"), dtype=np.float64)[..., None] / 255.0
    t = hex_rgb(tint)[None, None, :]
    rgb = lum * t + (1 - lum) * np.array([0.05, 0.06, 0.08])
    return Image.fromarray(np.round(rgb * 255).astype(np.uint8), "RGB")


def check_sheet(renders: dict, out_dir: str):
    os.makedirs(out_dir, exist_ok=True)
    walls = {"light": ((210, 222, 240), (150, 170, 205)), "dark": ((14, 18, 32), (40, 36, 70)),
             "tinted": ((14, 18, 32), (40, 36, 70))}
    for appearance in ("light", "dark", "tinted"):
        cols = len(renders)
        sheet = Image.new("RGB", (40 + cols * 260, 520), walls[appearance][0])
        grad = np.linspace(0, 1, sheet.size[1])[:, None, None]
        a, b = np.array(walls[appearance][0]), np.array(walls[appearance][1])
        sheet = Image.fromarray(np.broadcast_to((a * (1 - grad) + b * grad), (sheet.size[1], sheet.size[0], 3)).astype(np.uint8))
        for i, (icon, imgs) in enumerate(renders.items()):
            img = imgs[appearance]
            if appearance == "tinted":
                img = tinted_preview(img)
            x = 40 + i * 260
            big = masked(img, 200)
            sheet.paste(big, (x, 30), big)
            for j, size in enumerate((60, 40, 29)):
                small = masked(img, size)
                sheet.paste(small, (x + [0, 80, 140][j], 270), small)
            # 60 pt @1x next to an upscaled copy of the 60 px render (what a home screen shows at 1x)
            pix = masked(img, 60).resize((180, 180), Image.NEAREST)
            sheet.paste(pix, (x, 330), pix)
        sheet.save(os.path.join(out_dir, f"check-{appearance}.png"))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", metavar="DIR", help="also write home-screen check sheets to DIR")
    parser.add_argument("--only", choices=ICON_ORDER, action="append", help="render only these icons")
    parser.add_argument("--no-write", action="store_true", help="do not touch the asset catalog")
    args = parser.parse_args(argv)

    icons = args.only or ICON_ORDER
    renders = {}
    for icon in icons:
        renders[icon] = {appearance: render(icon, appearance) for appearance in ("light", "dark", "tinted")}
        if not args.no_write:
            write_icon_set(icon, renders[icon])
            write_preview_set(icon, renders[icon])
        print(f"rendered {icon}", file=sys.stderr)
    if args.check:
        check_sheet(renders, args.check)
        for icon, imgs in renders.items():
            for appearance, img in imgs.items():
                img.save(os.path.join(args.check, f"{icon}-{appearance}.png"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
