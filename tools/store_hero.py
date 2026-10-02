#!/usr/bin/env python3
"""Title screenshot for the store (1080x1920): logo, tagline and the key art banners.
python3 tools/store_hero.py <out_dir>   ->   out_dir/<lang>.jpg"""
import os, sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT = os.path.join(ROOT, "tools", "fonts", "Rubik-ExtraBold.ttf")
W, H = 1080, 1920

TAGLINES = {
 "en": ("Your colony on the ocean floor", "Build · Explore · Survive"),
 "ru": ("Твоя колония на дне океана", "Строй · Исследуй · Выживай"),
 "es": ("Tu colonia en el fondo del océano", "Construye · Explora · Sobrevive"),
 "pt_BR": ("Sua colônia no fundo do oceano", "Construa · Explore · Sobreviva"),
 "de": ("Deine Kolonie am Meeresgrund", "Bauen · Erkunden · Überleben"),
 "fr": ("Ta colonie au fond de l'océan", "Bâtis · Explore · Survis"),
 "it": ("La tua colonia in fondo all'oceano", "Costruisci · Esplora · Sopravvivi"),
 "tr": ("Okyanus tabanında kendi kolonin", "İnşa et · Keşfet · Hayatta kal"),
 "pl": ("Twoja kolonia na dnie oceanu", "Buduj · Odkrywaj · Przetrwaj"),
 "id": ("Kolonimu di dasar samudra", "Bangun · Jelajahi · Bertahan"),
}


def cover(img, w, h):
    k = max(w / img.width, h / img.height)
    img = img.resize((int(img.width * k) + 1, int(img.height * k) + 1), Image.LANCZOS)
    x, y = (img.width - w) // 2, (img.height - h) // 2
    return img.crop((x, y, x + w, y + h))


def framed(bg, art, x, y, w):
    h = int(art.height * w / art.width)
    art = art.resize((w, h), Image.LANCZOS)
    glow = Image.new("L", (W, H), 0)
    ImageDraw.Draw(glow).rounded_rectangle([x - 14, y - 14, x + w + 14, y + h + 14], 44, fill=255)
    bg.paste(Image.new("RGB", (W, H), (90, 210, 255)), (0, 0), glow.filter(ImageFilter.GaussianBlur(22)).point(lambda v: v * 0.7))
    ImageDraw.Draw(bg).rounded_rectangle([x - 6, y - 6, x + w + 5, y + h + 5], 40, fill=(255, 205, 90))
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, w - 1, h - 1], 34, fill=255)
    bg.paste(art, (x, y), mask)
    return y + h


def text(d, cx, y, s, size, fill, maxw=W - 100):
    while True:
        font = ImageFont.truetype(FONT, size)
        if d.textlength(s, font=font) <= maxw or size <= 40:
            break
        size -= 2
    tw = d.textlength(s, font=font)
    d.text((cx - tw / 2, y), s, font=font, fill=fill, stroke_width=max(3, size // 14), stroke_fill=(10, 20, 45))
    return y + int(size * 1.2)


def hero(lang):
    sea = Image.open(os.path.join(ROOT, "art", "backgrounds", "splash_3.png")).convert("RGB")
    bg = cover(sea, W, H).filter(ImageFilter.GaussianBlur(14))
    bg = Image.blend(bg, Image.new("RGB", (W, H), (6, 22, 60)), 0.45)
    logo = Image.open(os.path.join(ROOT, "art", "ui", "logo.png")).convert("RGBA")
    lw = 920
    logo = logo.resize((lw, int(logo.height * lw / logo.width)), Image.LANCZOS)
    bg.paste(logo, ((W - lw) // 2, 50), logo)
    d = ImageDraw.Draw(bg)
    top, bottom = TAGLINES[lang]
    y = text(d, W // 2, 50 + logo.height + 10, top, 64, (255, 214, 90))
    a = Image.open(os.path.join(ROOT, "art", "_source", "banner_a.png")).convert("RGB")
    b = Image.open(os.path.join(ROOT, "art", "backgrounds", "splash_2.png")).convert("RGB")
    y = framed(bg, a, 50, y + 40, W - 100)
    y = framed(bg, b, 50, y + 50, W - 100)
    text(d, W // 2, (y + H) // 2 - 36, bottom, 62, (255, 255, 255))
    return bg


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    os.makedirs(out, exist_ok=True)
    for lang in TAGLINES:
        hero(lang).save(os.path.join(out, lang + ".jpg"), quality=92)
        print(lang)
