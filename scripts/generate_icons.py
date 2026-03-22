#!/usr/bin/env python3
"""Generate Noor AI app icons for all densities + Play Store."""

from PIL import Image, ImageDraw, ImageFont
import math
import os

# ── Colors matching the app theme ──
BG_COLOR = (6, 11, 17)         # #060B11 deep navy
GOLD = (218, 165, 32)          # #DAA520 gold
GOLD_LIGHT = (255, 215, 90)    # lighter gold highlight


def draw_icon(size):
    """Draw the master icon at given size."""
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    cx, cy = size // 2, size // 2

    # Background circle
    margin = int(size * 0.02)
    draw.ellipse([margin, margin, size - margin, size - margin], fill=BG_COLOR)

    # Subtle radial glow behind crescent
    for r in range(int(size * 0.32), 0, -3):
        alpha = int(20 * (r / (size * 0.32)))
        draw.ellipse(
            [cx - r, cy - r, cx + r, cy + r],
            fill=(GOLD[0], GOLD[1], GOLD[2], alpha)
        )

    # Crescent moon
    moon_r = int(size * 0.26)
    draw.ellipse(
        [cx - moon_r, cy - moon_r, cx + moon_r, cy + moon_r],
        fill=GOLD
    )
    # Cut-out to form crescent shape
    cut_offset = int(size * 0.13)
    cut_r = int(size * 0.22)
    draw.ellipse(
        [cx - cut_r + cut_offset, cy - cut_r - int(size * 0.02),
         cx + cut_r + cut_offset, cy + cut_r - int(size * 0.02)],
        fill=BG_COLOR
    )

    # 5-pointed star
    star_cx = cx + int(size * 0.15)
    star_cy = cy - int(size * 0.15)
    star_r_outer = int(size * 0.06)
    star_r_inner = int(size * 0.026)
    points = []
    for i in range(10):
        angle = math.radians(-90 + i * 36)
        r = star_r_outer if i % 2 == 0 else star_r_inner
        points.append((star_cx + r * math.cos(angle), star_cy + r * math.sin(angle)))
    draw.polygon(points, fill=GOLD_LIGHT)

    return img


def draw_adaptive_foreground(size):
    """Adaptive icon foreground (transparent bg, icon within safe zone)."""
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    cx, cy = size // 2, size // 2

    # Safe zone ~ 66/108 = 61% of canvas
    safe = int(size * 0.61)

    # Radial glow
    glow_r = int(safe * 0.45)
    for r in range(glow_r, 0, -3):
        alpha = int(22 * (r / glow_r))
        draw.ellipse(
            [cx - r, cy - r, cx + r, cy + r],
            fill=(GOLD[0], GOLD[1], GOLD[2], alpha)
        )

    # Crescent
    moon_r = int(safe * 0.36)
    draw.ellipse(
        [cx - moon_r, cy - moon_r, cx + moon_r, cy + moon_r],
        fill=GOLD
    )
    cut_offset = int(safe * 0.18)
    cut_r = int(safe * 0.30)
    draw.ellipse(
        [cx - cut_r + cut_offset, cy - cut_r - int(safe * 0.02),
         cx + cut_r + cut_offset, cy + cut_r - int(safe * 0.02)],
        fill=(0, 0, 0, 0)
    )

    # Star
    star_cx = cx + int(safe * 0.21)
    star_cy = cy - int(safe * 0.21)
    star_r_outer = int(safe * 0.08)
    star_r_inner = int(safe * 0.035)
    points = []
    for i in range(10):
        angle = math.radians(-90 + i * 36)
        r = star_r_outer if i % 2 == 0 else star_r_inner
        points.append((star_cx + r * math.cos(angle), star_cy + r * math.sin(angle)))
    draw.polygon(points, fill=GOLD_LIGHT)

    return img


def main():
    res_dir = os.path.join(os.path.dirname(__file__), '..', 'android', 'app', 'src', 'main', 'res')
    res_dir = os.path.abspath(res_dir)

    print("Generating master icon (1024px)...")
    master = draw_icon(1024)

    # ── Legacy icons ──
    densities = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}
    for density, px in densities.items():
        folder = os.path.join(res_dir, f'mipmap-{density}')
        os.makedirs(folder, exist_ok=True)
        icon = master.resize((px, px), Image.LANCZOS).convert('RGBA')
        icon.save(os.path.join(folder, 'ic_launcher.png'), 'PNG')

        # Round version with circular mask
        mask = Image.new('L', (px, px), 0)
        ImageDraw.Draw(mask).ellipse([0, 0, px, px], fill=255)
        round_icon = Image.new('RGBA', (px, px), (0, 0, 0, 0))
        round_icon.paste(icon, mask=mask)
        round_icon.save(os.path.join(folder, 'ic_launcher_round.png'), 'PNG')
        print(f"  {density}: {px}x{px}")

    # ── Adaptive foreground ──
    print("Generating adaptive foregrounds...")
    fg_master = draw_adaptive_foreground(1024)
    fg_densities = {'mdpi': 108, 'hdpi': 162, 'xhdpi': 216, 'xxhdpi': 324, 'xxxhdpi': 432}
    for density, px in fg_densities.items():
        folder = os.path.join(res_dir, f'mipmap-{density}')
        fg_resized = fg_master.resize((px, px), Image.LANCZOS)
        fg_resized.save(os.path.join(folder, 'ic_launcher_foreground.png'), 'PNG')
        print(f"  {density} fg: {px}x{px}")

    # ── Play Store 512x512 ──
    print("Generating Play Store icon (512x512)...")
    ps = master.resize((512, 512), Image.LANCZOS).convert('RGBA')
    flat = Image.new('RGB', (512, 512), BG_COLOR)
    flat.paste(ps, mask=ps.split()[3])
    ps_path = os.path.join(res_dir, '..', 'ic_launcher-playstore.png')
    flat.save(ps_path, 'PNG')
    print(f"  Saved: {os.path.abspath(ps_path)}")

    print("\nDone! All icons generated.")


if __name__ == '__main__':
    main()
