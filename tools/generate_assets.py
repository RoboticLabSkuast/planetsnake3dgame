"""Procedural PBR texture, app icon, and WAV sound effect generator for Planet Snake 3D."""

from __future__ import annotations

import math
import os
import wave
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
TEX_DIR = ROOT / "assets" / "textures"
UI_TEX_DIR = TEX_DIR / "ui"
AUDIO_DIR = ROOT / "assets" / "audio"


def ensure_dirs() -> None:
    TEX_DIR.mkdir(parents=True, exist_ok=True)
    UI_TEX_DIR.mkdir(parents=True, exist_ok=True)
    AUDIO_DIR.mkdir(parents=True, exist_ok=True)


def tileable_value_noise(size: int, period: int, seed: int) -> np.ndarray:
    """Generate smooth periodic 2D value noise in [0, 1] of shape (size, size)."""
    rng = np.random.default_rng(seed)
    grid = rng.random((period, period), dtype=np.float32)

    coords = np.linspace(0.0, float(period), size, endpoint=False, dtype=np.float32)
    x0 = np.floor(coords).astype(np.int32) % period
    x1 = (x0 + 1) % period
    fx = coords - np.floor(coords)
    # Quintic smoothstep
    sx = fx * fx * fx * (fx * (fx * 6.0 - 15.0) + 10.0)

    gx0, gy0 = np.meshgrid(x0, x0, indexing="xy")
    gx1, gy1 = np.meshgrid(x1, x1, indexing="xy")
    ux, uy = np.meshgrid(sx, sx, indexing="xy")

    n00 = grid[gy0, gx0]
    n10 = grid[gy0, gx1]
    n01 = grid[gy1, gx0]
    n11 = grid[gy1, gx1]

    nx0 = n00 * (1.0 - ux) + n10 * ux
    nx1 = n01 * (1.0 - ux) + n11 * ux
    return (nx0 * (1.0 - uy) + nx1 * uy).astype(np.float32)


def tileable_fbm(size: int, base_period: int, octaves: int, seed: int) -> np.ndarray:
    """Multi-octave seamless tileable FBM noise in [0, 1]."""
    total = np.zeros((size, size), dtype=np.float32)
    amp = 0.5
    norm = 0.0
    period = base_period
    for i in range(octaves):
        total += amp * tileable_value_noise(size, period, seed + i * 137)
        norm += amp
        amp *= 0.5
        period *= 2
    return np.clip(total / norm, 0.0, 1.0)


def height_to_normal(height: np.ndarray, strength: float = 3.5) -> np.ndarray:
    """Convert periodic heightmap [0, 1] to tangent-space RGB normal map uint8."""
    dx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * 0.5 * strength
    dy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * 0.5 * strength
    nx = -dx
    ny = -dy
    nz = np.ones_like(height, dtype=np.float32)
    length = np.sqrt(nx * nx + ny * ny + nz * nz) + 1e-8
    nx /= length
    ny /= length
    nz /= length
    rgb = np.stack([nx * 0.5 + 0.5, ny * 0.5 + 0.5, nz * 0.5 + 0.5], axis=-1)
    return np.clip(rgb * 255.0, 0, 255).astype(np.uint8)


def save_rgb(path: Path, arr: np.ndarray) -> None:
    Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), mode="RGB").save(path)


def save_gray(path: Path, arr: np.ndarray) -> None:
    Image.fromarray(np.clip(arr * 255.0, 0, 255).astype(np.uint8), mode="L").save(path)


def generate_planet_tile_biome(
    name: str,
    size: int,
    seed: int,
    stone_dark: tuple[float, float, float],
    stone_light: tuple[float, float, float],
    seam_color: tuple[float, float, float],
    seam_roughness: float,
    stone_roughness: float,
    normal_strength: float,
    seam_glow: bool = False,
) -> None:
    """Generate a single-cell seamless bevelled natural stone tile PBR set."""
    y, x = np.mgrid[0:size, 0:size].astype(np.float32) / float(size)
    # Distance to closest cell edge in [0, 0.5]
    ex = np.minimum(x, 1.0 - x)
    ey = np.minimum(y, 1.0 - y)
    edge_dist = np.minimum(ex, ey)

    # Organic irregularity along mortar border
    jitter = (tileable_fbm(size, 8, 4, seed + 11) - 0.5) * 0.025
    bevel_dist = np.clip((edge_dist + jitter) / 0.075, 0.0, 1.0)
    bevel_profile = bevel_dist * bevel_dist * (3.0 - 2.0 * bevel_dist)

    # Micro stone grain + fractures
    macro = tileable_fbm(size, 4, 4, seed + 29)
    micro = tileable_fbm(size, 16, 4, seed + 71)
    speckle = tileable_fbm(size, 32, 3, seed + 109)

    # Subtle rounded central dome + bevel + rock texture
    center_dome = np.sin(np.pi * x) * np.sin(np.pi * y) * 0.06
    height = (
        0.18 * (1.0 - bevel_profile) * -1.0
        + 0.45 * bevel_profile
        + center_dome
        + macro * 0.24
        + micro * 0.14
        + speckle * 0.06
    )
    height = (height - height.min()) / (height.max() - height.min() + 1e-6)

    # Color mixing
    stone_mix = np.clip(macro * 0.65 + micro * 0.35, 0.0, 1.0)[..., None]
    c_dark = np.array(stone_dark, dtype=np.float32)
    c_light = np.array(stone_light, dtype=np.float32)
    c_seam = np.array(seam_color, dtype=np.float32)

    albedo = c_dark * (1.0 - stone_mix) + c_light * stone_mix
    # Darken recessed beveled edges slightly for AO + blend mortar/seam
    ao = 0.62 + 0.38 * bevel_profile
    albedo *= ao[..., None]

    seam_mask = np.clip(1.0 - (edge_dist + jitter * 0.5) / 0.048, 0.0, 1.0)
    seam_mask = seam_mask * seam_mask
    if seam_glow:
        # Volcanic magma veins glow warmly inside mortar seams
        vein = np.clip((macro - 0.32) * 2.2, 0.25, 1.0)
        albedo = albedo * (1.0 - seam_mask[..., None]) + (c_seam * vein[..., None]) * seam_mask[..., None]
    else:
        albedo = albedo * (1.0 - seam_mask[..., None] * 0.88) + c_seam * (seam_mask[..., None] * 0.88)

    # Subtle mineral sparkles
    albedo += (speckle[..., None] - 0.5) * 18.0

    rough = (
        stone_roughness
        + (macro - 0.5) * 0.16
        + (micro - 0.5) * 0.10
        + (seam_roughness - stone_roughness) * seam_mask
    )
    rough = np.clip(rough, 0.14, 0.96)

    normal = height_to_normal(height, strength=normal_strength)

    save_rgb(TEX_DIR / f"{name}_albedo.png", albedo)
    save_rgb(TEX_DIR / f"{name}_normal.png", normal)
    save_gray(TEX_DIR / f"{name}_roughness.png", rough)


def generate_snake_textures(size: int = 512) -> None:
    """Generate seamless diamond viper scale PBR textures with belly plates along u=0/1."""
    y, x = np.mgrid[0:size, 0:size].astype(np.float32) / float(size)
    # Cross-section circumference U: 0.0/1.0 = belly (bottom), 0.5 = dorsal spine (top)
    dorsal = 0.5 - 0.5 * np.cos(2.0 * np.pi * x)  # 0 at belly, 1 at spine

    # Staggered hexagonal/diamond scale lattice (14 columns around, 18 rows along body)
    cols = 14.0
    rows = 18.0
    u_scaled = x * cols
    v_scaled = y * rows

    # Two offset grids for overlapping diamond scales
    p1_u = (u_scaled % 1.0) - 0.5
    p1_v = (v_scaled % 1.0) - 0.5
    d1 = np.abs(p1_u) * 1.15 + np.abs(p1_v) * 0.95

    p2_u = ((u_scaled + 0.5) % 1.0) - 0.5
    p2_v = ((v_scaled + 0.5) % 1.0) - 0.5
    d2 = np.abs(p2_u) * 1.15 + np.abs(p2_v) * 0.95

    # Overlap order: scales point backward (+v)
    scale_height_1 = np.clip(1.0 - d1 * 1.65, 0.0, 1.0)
    scale_height_2 = np.clip(1.0 - d2 * 1.65, 0.0, 1.0)
    scale_dome = np.maximum(scale_height_1, scale_height_2)
    scale_dome = np.power(scale_dome, 0.65)

    # Ventral belly scutes (broad horizontal bands near belly u~0 or u~1)
    belly_mask = np.clip((0.28 - dorsal) / 0.16, 0.0, 1.0)
    belly_ribs = 0.5 + 0.5 * np.cos(2.0 * np.pi * v_scaled * 0.5)
    belly_height = 0.45 + 0.45 * np.power(belly_ribs, 0.4)

    height = scale_dome * (1.0 - belly_mask) + belly_height * belly_mask
    micro = tileable_fbm(size, 16, 3, 501)
    height = np.clip(height * 0.92 + micro * 0.08, 0.0, 1.0)

    # Diamondback / emerald tree viper markings
    diamond_wave = np.sin(2.0 * np.pi * y * 3.0) * 0.5 + 0.5
    ridge_band = np.exp(-((dorsal - 0.78) ** 2) / 0.045)
    lateral_gold = np.exp(-((dorsal - 0.42) ** 2) / 0.03) * diamond_wave

    c_jade_dark = np.array([18.0, 68.0, 42.0], dtype=np.float32)
    c_emerald = np.array([34.0, 138.0, 74.0], dtype=np.float32)
    c_gold_flank = np.array([178.0, 162.0, 64.0], dtype=np.float32)
    c_belly = np.array([216.0, 198.0, 146.0], dtype=np.float32)

    albedo = c_emerald * (0.65 + 0.35 * scale_dome)[..., None]
    # Darker diamond ridge markings along dorsal spine
    albedo = albedo * (1.0 - 0.58 * ridge_band[..., None]) + c_jade_dark * (0.58 * ridge_band[..., None])
    # Golden lateral flecks
    albedo = albedo * (1.0 - 0.52 * lateral_gold[..., None]) + c_gold_flank * (0.52 * lateral_gold[..., None])
    # Dark scale crevices
    crevice = np.clip(1.0 - scale_dome * 1.4, 0.0, 1.0)
    albedo *= (1.0 - 0.42 * crevice[..., None])
    # Belly color
    albedo = albedo * (1.0 - belly_mask[..., None]) + c_belly * (belly_mask * (0.85 + 0.15 * belly_ribs))[..., None]
    albedo += (micro[..., None] - 0.5) * 12.0

    # Keratin scale roughness: glossy scale tops (0.24), matte crevices (0.58)
    roughness = 0.24 + 0.36 * (1.0 - scale_dome) * (1.0 - belly_mask) + 0.18 * belly_mask
    roughness = np.clip(roughness + (micro - 0.5) * 0.08, 0.18, 0.72)

    normal = height_to_normal(height, strength=4.6)

    save_rgb(TEX_DIR / "snake_albedo.png", albedo)
    save_rgb(TEX_DIR / "snake_normal.png", normal)
    save_gray(TEX_DIR / "snake_roughness.png", roughness)


def generate_apple_textures(size: int = 512) -> None:
    """Generate realistic crimson apple and golden bonus apple textures."""
    y, x = np.mgrid[0:size, 0:size].astype(np.float32) / float(size)
    fbm = tileable_fbm(size, 8, 4, 701)
    stripes = tileable_fbm(size, 32, 2, 733)
    # Vertical apple skin striations
    vert_streak = 0.5 + 0.5 * np.sin(x * 2.0 * np.pi * 18.0 + fbm * 4.0)
    blush = np.clip(1.0 - np.abs(y - 0.22) * 3.0, 0.0, 1.0) * (0.4 + 0.6 * fbm)

    # Crimson apple
    c_deep_red = np.array([138.0, 14.0, 18.0], dtype=np.float32)
    c_bright_red = np.array([218.0, 34.0, 32.0], dtype=np.float32)
    c_yellow_blush = np.array([228.0, 178.0, 62.0], dtype=np.float32)

    mix = np.clip(vert_streak * 0.45 + fbm * 0.55, 0.0, 1.0)[..., None]
    albedo = c_deep_red * (1.0 - mix) + c_bright_red * mix
    albedo = albedo * (1.0 - 0.35 * blush[..., None]) + c_yellow_blush * (0.35 * blush[..., None])

    # Tiny pale apple lenticels (speckles)
    rng = np.random.default_rng(777)
    speck = (rng.random((size, size)) > 0.9965).astype(np.float32)
    speck = np.array(Image.fromarray((speck * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8)), dtype=np.float32) / 255.0
    albedo = albedo * (1.0 - speck[..., None] * 0.5) + np.array([245.0, 224.0, 175.0]) * (speck[..., None] * 0.5)

    roughness = np.clip(0.18 + 0.14 * fbm + 0.06 * stripes, 0.14, 0.42)
    height = np.clip(0.5 + 0.22 * vert_streak + 0.25 * fbm, 0.0, 1.0)
    normal = height_to_normal(height, strength=1.4)

    save_rgb(TEX_DIR / "apple_albedo.png", albedo)
    save_rgb(TEX_DIR / "apple_normal.png", normal)
    save_gray(TEX_DIR / "apple_roughness.png", roughness)

    # Golden fruit albedo
    c_gold_dark = np.array([196.0, 134.0, 18.0], dtype=np.float32)
    c_gold_bright = np.array([255.0, 220.0, 88.0], dtype=np.float32)
    gold_albedo = c_gold_dark * (1.0 - mix) + c_gold_bright * mix
    save_rgb(TEX_DIR / "gold_apple_albedo.png", gold_albedo)


def generate_boulder_textures(size: int = 512) -> None:
    """Generate realistic mossy craggy granite boulder textures."""
    macro = tileable_fbm(size, 6, 4, 901)
    micro = tileable_fbm(size, 20, 4, 937)
    cracks = np.abs(tileable_fbm(size, 8, 3, 971) - 0.5) * 2.0
    crack_mask = np.clip(1.0 - cracks / 0.18, 0.0, 1.0)

    c_granite_a = np.array([78.0, 82.0, 84.0], dtype=np.float32)
    c_granite_b = np.array([138.0, 136.0, 128.0], dtype=np.float32)
    c_moss = np.array([56.0, 96.0, 42.0], dtype=np.float32)

    mix = np.clip(macro * 0.65 + micro * 0.35, 0.0, 1.0)[..., None]
    albedo = c_granite_a * (1.0 - mix) + c_granite_b * mix
    moss_patch = np.clip((macro - 0.54) * 3.5, 0.0, 0.72)[..., None]
    albedo = albedo * (1.0 - moss_patch) + c_moss * moss_patch
    albedo *= (1.0 - 0.45 * crack_mask[..., None])

    height = np.clip(macro * 0.55 + micro * 0.35 - crack_mask * 0.35, 0.0, 1.0)
    rough = np.clip(0.72 + 0.18 * micro + 0.10 * crack_mask, 0.52, 0.96)
    normal = height_to_normal(height, strength=4.2)

    save_rgb(TEX_DIR / "boulder_albedo.png", albedo)
    save_rgb(TEX_DIR / "boulder_normal.png", normal)
    save_gray(TEX_DIR / "boulder_roughness.png", rough)


def generate_app_icon(size: int = 1024) -> None:
    """Render a crisp 1024x1024 realistic-styled Planet Snake 3D app icon."""
    img = Image.new("RGBA", (size, size), (10, 16, 26, 255))
    y, x = np.mgrid[0:size, 0:size].astype(np.float32)
    cx = cy = size * 0.5
    dx = (x - cx) / (size * 0.39)
    dy = (y - cy) / (size * 0.39)
    r2 = dx * dx + dy * dy

    # Deep space background gradient + subtle atmosphere halo
    bg_r = np.clip(14.0 + 26.0 * np.exp(-r2 * 0.9), 0, 255)
    bg_g = np.clip(24.0 + 58.0 * np.exp(-r2 * 0.8), 0, 255)
    bg_b = np.clip(42.0 + 108.0 * np.exp(-r2 * 0.7), 0, 255)
    canvas = np.stack([bg_r, bg_g, bg_b], axis=-1)

    # Sphere shading
    inside = r2 <= 1.0
    nz = np.sqrt(np.clip(1.0 - r2, 0.0, 1.0))
    lx, ly, lz = -0.48, -0.52, 0.70
    ndotl = np.clip(dx * lx + dy * ly + nz * lz, 0.0, 1.0)
    rim = np.power(1.0 - nz, 3.0)

    # Procedural continents on globe
    angle = np.arctan2(dy, dx)
    lat = np.arcsin(np.clip(dy, -1.0, 1.0))
    tex = 0.5 + 0.5 * np.sin(angle * 4.0 + lat * 3.0) * np.cos(dx * 5.0 - dy * 4.0)
    planet_col = (
        np.array([42.0, 92.0, 56.0]) * tex[..., None]
        + np.array([56.0, 68.0, 64.0]) * (1.0 - tex[..., None])
    )
    lit_planet = planet_col * (0.22 + 0.95 * ndotl[..., None]) + np.array([75.0, 165.0, 255.0]) * (rim[..., None] * 0.65)
    canvas[inside] = lit_planet[inside]

    img = Image.fromarray(np.clip(canvas, 0, 255).astype(np.uint8), mode="RGB").convert("RGBA")
    draw = ImageDraw.Draw(img)

    # Draw stylized coiled emerald snake body wrapping across the planet
    pts = []
    for i in range(60):
        t = i / 59.0
        px = cx + math.sin(t * 4.5 - 1.2) * size * 0.25
        py = cy + (0.26 - t * 0.46) * size * 0.78 + math.cos(t * 6.0) * size * 0.04
        pts.append((px, py, 20.0 + 26.0 * math.sin(t * math.pi * 0.85)))

    for idx, (px, py, rad) in enumerate(pts):
        col = (22, 118, 60, 255) if idx % 3 else (38, 172, 86, 255)
        draw.ellipse([px - rad, py - rad, px + rad, py + rad], fill=col, outline=(14, 62, 34, 255), width=3)

    # Snake head + amber eyes
    hx, hy, hr = pts[-1][0], pts[-1][1], 44
    draw.ellipse([hx - hr * 1.15, hy - hr, hx + hr * 1.15, hy + hr], fill=(42, 190, 92, 255), outline=(18, 76, 40, 255), width=5)
    draw.ellipse([hx - 24, hy - 22, hx - 6, hy - 2], fill=(255, 198, 42, 255))
    draw.ellipse([hx + 6, hy - 22, hx + 24, hy - 2], fill=(255, 198, 42, 255))
    draw.ellipse([hx - 17, hy - 19, hx - 13, hy - 5], fill=(12, 14, 16, 255))
    draw.ellipse([hx + 13, hy - 19, hx + 17, hy - 5], fill=(12, 14, 16, 255))

    # Glossy crimson apple target on upper right of globe
    ax, ay, ar = cx + size * 0.19, cy - size * 0.14, 38
    draw.ellipse([ax - ar, ay - ar, ax + ar, ay + ar], fill=(220, 32, 34, 255), outline=(120, 14, 18, 255), width=4)
    draw.ellipse([ax - 18, ay - 22, ax - 2, ay - 8], fill=(255, 165, 160, 190))
    draw.line([(ax, ay - ar + 4), (ax + 10, ay - ar - 16)], fill=(96, 62, 32, 255), width=7)

    img.save(ROOT / "assets" / "icon.png")


def write_wav(path: Path, samples: np.ndarray, sample_rate: int = 44100) -> None:
    clipped = np.clip(samples, -1.0, 1.0)
    pcm = (clipped * 32767.0).astype(np.int16)
    with wave.open(str(path), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(sample_rate)
        wf.writeframes(pcm.tobytes())


def generate_audio() -> None:
    sr = 44100
    rng = np.random.default_rng(42)

    # 1. Apple bite + crisp bright pop
    t = np.linspace(0.0, 0.24, int(sr * 0.24), endpoint=False)
    crunch = rng.normal(0.0, 1.0, len(t)) * np.exp(-t * 48.0) * 0.45
    pop = np.sin(2.0 * np.pi * (420.0 + 620.0 * np.exp(-t * 28.0)) * t) * np.exp(-t * 16.0) * 0.48
    chime = np.sin(2.0 * np.pi * 880.0 * t) * np.exp(-t * 14.0) * 0.25
    write_wav(AUDIO_DIR / "eat.wav", crunch + pop + chime, sr)

    # 2. Golden apple sparkle chord
    t = np.linspace(0.0, 0.48, int(sr * 0.48), endpoint=False)
    gold = (
        np.sin(2.0 * np.pi * 659.25 * t) * np.exp(-t * 6.5) * 0.30
        + np.sin(2.0 * np.pi * 830.61 * np.maximum(t - 0.05, 0.0)) * (t >= 0.05) * np.exp(-np.maximum(t - 0.05, 0.0) * 6.5) * 0.30
        + np.sin(2.0 * np.pi * 1318.51 * np.maximum(t - 0.11, 0.0)) * (t >= 0.11) * np.exp(-np.maximum(t - 0.11, 0.0) * 5.5) * 0.34
    )
    write_wav(AUDIO_DIR / "eat_gold.wav", gold, sr)

    # 3. Subtle turn brush tick
    t = np.linspace(0.0, 0.055, int(sr * 0.055), endpoint=False)
    turn = (
        np.sin(2.0 * np.pi * (240.0 + 160.0 * np.exp(-t * 60.0)) * t) * np.exp(-t * 58.0) * 0.22
        + rng.normal(0.0, 1.0, len(t)) * np.exp(-t * 95.0) * 0.08
    )
    write_wav(AUDIO_DIR / "turn.wav", turn, sr)

    # 4. Collision thud
    t = np.linspace(0.0, 0.45, int(sr * 0.45), endpoint=False)
    freq = 155.0 * np.exp(-t * 5.5) + 42.0
    phase = 2.0 * np.pi * np.cumsum(freq) / sr
    thud = np.sin(phase) * np.exp(-t * 7.0) * 0.65
    grit = rng.normal(0.0, 1.0, len(t)) * np.exp(-t * 22.0) * 0.32
    write_wav(AUDIO_DIR / "crash.wav", thud + grit, sr)

    # 5. Seamless calm cosmic/breeze ambient loop (4.0s exact periodic frequencies)
    dur = 4.0
    t = np.linspace(0.0, dur, int(sr * dur), endpoint=False)
    pad = (
        np.sin(2.0 * np.pi * 55.0 * t) * 0.14
        + np.sin(2.0 * np.pi * 82.5 * t) * 0.09
        + np.sin(2.0 * np.pi * 110.0 * t) * 0.07
        + np.sin(2.0 * np.pi * 165.0 * t) * (0.04 + 0.02 * np.sin(2.0 * np.pi * 0.25 * t))
    )
    write_wav(AUDIO_DIR / "ambient_space.wav", pad, sr)

    # 6. Crisp subtle UI button click
    t = np.linspace(0.0, 0.045, int(sr * 0.045), endpoint=False)
    click = np.sin(2.0 * np.pi * (920.0 * np.exp(-t * 40.0) + 260.0) * t) * np.exp(-t * 85.0) * 0.35
    write_wav(AUDIO_DIR / "ui_click.wav", click, sr)

    # 7. Milestone / speed-up chime
    t = np.linspace(0.0, 0.42, int(sr * 0.42), endpoint=False)
    mile = (
        np.sin(2.0 * np.pi * 523.25 * t) * np.exp(-t * 7.5) * 0.28
        + np.sin(2.0 * np.pi * 783.99 * np.maximum(t - 0.07, 0.0)) * (t >= 0.07) * np.exp(-np.maximum(t - 0.07, 0.0) * 6.5) * 0.30
    )
    write_wav(AUDIO_DIR / "milestone.wav", mile, sr)

    # 8. Sparkling power-up pickup chime
    t = np.linspace(0.0, 0.44, int(sr * 0.44), endpoint=False)
    pwr = (
        np.sin(2.0 * np.pi * 587.33 * t) * np.exp(-t * 8.0) * 0.26
        + np.sin(2.0 * np.pi * 880.00 * np.maximum(t - 0.05, 0.0)) * (t >= 0.05) * np.exp(-np.maximum(t - 0.05, 0.0) * 7.0) * 0.28
        + np.sin(2.0 * np.pi * 1174.66 * np.maximum(t - 0.11, 0.0)) * (t >= 0.11) * np.exp(-np.maximum(t - 0.11, 0.0) * 6.0) * 0.32
    )
    write_wav(AUDIO_DIR / "powerup.wav", pwr, sr)

    # 9. Shield stone shatter impact
    t = np.linspace(0.0, 0.40, int(sr * 0.40), endpoint=False)
    shatter_noise = rng.normal(0.0, 1.0, len(t)) * np.exp(-t * 14.0) * 0.55
    metal_ring = np.sin(2.0 * np.pi * 410.0 * t) * np.exp(-t * 9.0) * 0.35 + np.sin(2.0 * np.pi * 220.0 * t) * np.exp(-t * 11.0) * 0.40
    write_wav(AUDIO_DIR / "shield_break.wav", shatter_noise + metal_ring, sr)


def generate_ui_icons() -> None:
    """Generate crisp 96x96 supersampled transparent UI icons for cross-platform HUD/menus."""
    S = 256  # render 256 then downsample to 64 for sharp antialiased edges

    def finish(img: Image.Image, name: str) -> None:
        out = img.resize((64, 64), Image.Resampling.LANCZOS)
        out.save(UI_TEX_DIR / f"{name}.png")

    # 1. Trophy icon (gold)
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    gold = (255, 210, 64, 255)
    gold_dk = (212, 152, 24, 255)
    d.arc([34, 52, 92, 134], 90, 270, fill=gold_dk, width=16)
    d.arc([164, 52, 222, 134], 270, 90, fill=gold_dk, width=16)
    d.pieslice([62, 34, 194, 168], 0, 180, fill=gold, outline=gold_dk, width=6)
    d.rectangle([62, 36, 194, 102], fill=gold)
    d.rectangle([114, 156, 142, 198], fill=gold_dk)
    d.rounded_rectangle([78, 194, 178, 224], radius=10, fill=gold, outline=gold_dk, width=5)
    finish(im, "trophy")

    # 2. Mini crimson apple icon
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse([44, 64, 212, 226], fill=(228, 38, 38, 255), outline=(140, 16, 20, 255), width=6)
    d.ellipse([74, 86, 114, 124], fill=(255, 165, 165, 175))
    d.line([(128, 72), (144, 30)], fill=(120, 74, 36, 255), width=14)
    d.polygon([(136, 56), (192, 36), (174, 78)], fill=(68, 192, 84, 255))
    finish(im, "apple")

    # 3. Globe / Worlds icon
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse([30, 30, 226, 226], fill=(42, 138, 196, 255), outline=(165, 225, 255, 255), width=10)
    d.ellipse([76, 30, 180, 226], outline=(185, 235, 255, 220), width=8)
    d.line([(32, 128), (224, 128)], fill=(185, 235, 255, 220), width=8)
    d.arc([42, 66, 214, 118], 180, 360, fill=(185, 235, 255, 200), width=7)
    d.arc([42, 138, 214, 190], 0, 180, fill=(185, 235, 255, 200), width=7)
    finish(im, "globe")

    # 4. Settings gear icon
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    cx = cy = S / 2.0
    for k in range(8):
        ang = k * (math.pi / 4.0)
        px = cx + math.cos(ang) * 86.0
        py = cy + math.sin(ang) * 86.0
        d.ellipse([px - 22, py - 22, px + 22, py + 22], fill=(220, 234, 250, 255))
    d.ellipse([52, 52, 204, 204], fill=(220, 234, 250, 255))
    d.ellipse([88, 88, 168, 168], fill=(0, 0, 0, 0))
    finish(im, "gear")

    # 5. Book / Guide icon
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([42, 42, 214, 214], radius=24, fill=(76, 152, 232, 255), outline=(198, 228, 255, 255), width=10)
    d.text((104, 58), "?", fill=(255, 255, 255, 255))
    # Fallback bold "?" vector shape so font size doesn't matter
    d.arc([84, 62, 172, 136], 190, 65, fill=(255, 255, 255, 255), width=22)
    d.line([(128, 128), (128, 158)], fill=(255, 255, 255, 255), width=22)
    d.ellipse([116, 174, 140, 198], fill=(255, 255, 255, 255))
    finish(im, "guide")

    # 6. Sound On & Off icons
    for muted in [False, True]:
        im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        col = (240, 110, 110, 255) if muted else (225, 240, 255, 255)
        d.polygon([(46, 98), (94, 98), (146, 54), (146, 202), (94, 158), (46, 158)], fill=col)
        if not muted:
            d.arc([148, 82, 192, 174], 295, 65, fill=col, width=14)
            d.arc([164, 56, 224, 200], 295, 65, fill=col, width=14)
        else:
            d.line([(166, 90), (218, 166)], fill=col, width=16)
            d.line([(218, 90), (166, 166)], fill=col, width=16)
        finish(im, "sound_off" if muted else "sound_on")

    # 7. Play triangle icon
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.polygon([(70, 44), (212, 128), (70, 212)], fill=(255, 255, 255, 255))
    finish(im, "play")

    # 8. Shield icon (emerald-cyan)
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.polygon([(128, 28), (214, 62), (198, 160), (128, 228), (58, 160), (42, 62)],
              fill=(54, 216, 148, 255), outline=(190, 255, 225, 255), width=10)
    d.polygon([(128, 56), (186, 80), (174, 148), (128, 198), (82, 148), (70, 80)],
              fill=(28, 148, 102, 255))
    finish(im, "shield")

    # 9. Magnet icon (violet-magenta)
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.arc([52, 46, 204, 208], 180, 360, fill=(210, 92, 255, 255), width=32)
    d.rectangle([52, 124, 84, 196], fill=(210, 92, 255, 255))
    d.rectangle([172, 124, 204, 196], fill=(210, 92, 255, 255))
    d.rectangle([52, 174, 84, 206], fill=(225, 240, 255, 255))
    d.rectangle([172, 174, 204, 206], fill=(225, 240, 255, 255))
    finish(im, "magnet")

    # 10. Frost snowflake / crystal icon (icy cyan)
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    cx = cy = S / 2.0
    for k in range(6):
        ang = k * (math.pi / 3.0)
        ex = cx + math.cos(ang) * 86.0
        ey = cy + math.sin(ang) * 86.0
        d.line([(cx, cy), (ex, ey)], fill=(120, 225, 255, 255), width=16)
    d.ellipse([cx - 26, cy - 26, cx + 26, cy + 26], fill=(215, 248, 255, 255))
    finish(im, "frost")


def main() -> None:
    ensure_dirs()
    generate_planet_tile_biome(
        name="terra",
        size=512,
        seed=101,
        stone_dark=(62.0, 74.0, 68.0),
        stone_light=(114.0, 128.0, 114.0),
        seam_color=(42.0, 76.0, 34.0),
        seam_roughness=0.88,
        stone_roughness=0.62,
        normal_strength=3.6,
    )
    generate_planet_tile_biome(
        name="volcanic",
        size=512,
        seed=202,
        stone_dark=(28.0, 30.0, 36.0),
        stone_light=(64.0, 62.0, 70.0),
        seam_color=(248.0, 92.0, 22.0),
        seam_roughness=0.28,
        stone_roughness=0.58,
        normal_strength=4.2,
        seam_glow=True,
    )
    generate_planet_tile_biome(
        name="desert",
        size=512,
        seed=303,
        stone_dark=(162.0, 122.0, 78.0),
        stone_light=(214.0, 178.0, 126.0),
        seam_color=(122.0, 86.0, 48.0),
        seam_roughness=0.90,
        stone_roughness=0.72,
        normal_strength=3.4,
    )
    generate_snake_textures(512)
    generate_apple_textures(512)
    generate_boulder_textures(512)
    generate_app_icon(1024)
    generate_ui_icons()
    generate_audio()
    print("Generated all textures, app icon, and audio assets successfully.")


if __name__ == "__main__":
    main()
