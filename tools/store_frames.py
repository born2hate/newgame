#!/usr/bin/env python3
"""Store screenshots: caption on top + game screenshot in a frame (1080x1920).
python3 tools/store_frames.py <raw_dir> <out_dir> <font.ttf>
raw_dir/<lang>/<n>.png -> out_dir/<lang>/<n>.png"""
import sys, os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

CAPTIONS = {
 "en": ['Build your own underwater colony', 'Fight giant deep-sea bosses', 'Explore the deep — if you dare', 'Craft legendary weapons and armor', 'Defend against pirate raids', 'Put out fires, stop floods', 'Build wonders of the deep', 'Collect pets with special powers'],
 "ru": ['Построй свою подводную колонию', 'Сражайся с гигантскими боссами', 'Исследуй бездну — если осмелишься', 'Создавай легендарное оружие и броню', 'Отбивай налёты пиратов', 'Туши пожары, останавливай потопы', 'Строй чудеса глубин', 'Собирай питомцев с бонусами'],
 "es": ['Construye tu colonia submarina', 'Lucha contra jefes gigantes', 'Explora el abismo, si te atreves', 'Fabrica armas y armaduras legendarias', 'Defiéndete de los piratas', 'Apaga incendios, detén inundaciones', 'Construye maravillas del abismo', 'Colecciona mascotas con poderes'],
 "pt_BR": ['Construa sua colônia submarina', 'Enfrente chefes gigantes', 'Explore o abismo, se tiver coragem', 'Fabrique armas e armaduras lendárias', 'Defenda-se de ataques piratas', 'Apague incêndios, pare inundações', 'Construa maravilhas das profundezas', 'Colecione mascotes com poderes'],
 "de": ['Baue deine Unterwasserkolonie', 'Kämpfe gegen riesige Bosse', 'Erkunde die Tiefe – wenn du dich traust', 'Schmiede legendäre Waffen und Rüstungen', 'Wehre Piratenüberfälle ab', 'Lösche Brände, stoppe Fluten', 'Baue Wunder der Tiefe', 'Sammle Haustiere mit Boni'],
 "fr": ['Bâtis ta colonie sous-marine', 'Affronte des boss géants', "Explore les abysses, si tu l'oses", 'Forge armes et armures légendaires', 'Repousse les raids pirates', 'Éteins les incendies, stoppe les inondations', 'Bâtis les merveilles des profondeurs', 'Collectionne des familiers'],
 "it": ['Costruisci la tua colonia sottomarina', 'Combatti boss giganti', 'Esplora gli abissi, se ne hai il coraggio', 'Crea armi e armature leggendarie', 'Respingi i raid dei pirati', 'Spegni incendi, ferma allagamenti', 'Costruisci meraviglie degli abissi', 'Colleziona animali con poteri'],
 "tr": ['Kendi sualtı kolonini kur', 'Dev boslarla savaş', 'Cesaretin varsa derinlikleri keşfet', 'Efsanevi silah ve zırhlar üret', 'Korsan baskınlarını püskürt', 'Yangınları söndür, selleri durdur', 'Derinliklerin harikalarını inşa et', 'Güçlü evcil hayvanlar topla'],
 "pl": ['Zbuduj podwodną kolonię', 'Walcz z gigantycznymi bossami', 'Eksploruj głębiny, jeśli się odważysz', 'Wytwarzaj legendarną broń i pancerze', 'Odpieraj ataki piratów', 'Gaś pożary, zatrzymuj powodzie', 'Buduj cuda głębin', 'Zbieraj zwierzaki z bonusami'],
 "id": ['Bangun koloni bawah lautmu', 'Lawan bos raksasa laut dalam', 'Jelajahi kedalaman, jika berani', 'Buat senjata dan zirah legendaris', 'Tangkis serangan bajak laut', 'Padamkan api, hentikan banjir', 'Bangun keajaiban laut dalam', 'Kumpulkan hewan peliharaan'],
}

W, H, TOP, SCALE = 1080, 1920, 330, 0.8

def wrap(draw, text, font, maxw):
    words, lines, cur = text.split(), [], ""
    for w in words:
        t = (cur + " " + w).strip()
        if draw.textlength(t, font=font) <= maxw or not cur:
            cur = t
        else:
            lines.append(cur); cur = w
    lines.append(cur)
    return lines

def frame(src, text, font_path):
    bg = Image.new("RGB", (W, H))
    d = ImageDraw.Draw(bg)
    for y in range(H):
        k = y / H
        d.line([(0, y), (W, y)], fill=(int(8 + 10 * k), int(40 + 20 * (1 - k)), int(90 + 40 * (1 - k))))
    shot = Image.open(src).convert("RGB")
    sw, sh = int(W * SCALE), int(H * SCALE)
    shot = shot.resize((sw, sh), Image.LANCZOS)
    x, y = (W - sw) // 2, TOP + 20
    glow = Image.new("L", (W, H), 0)
    ImageDraw.Draw(glow).rounded_rectangle([x - 14, y - 14, x + sw + 14, y + sh + 14], 50, fill=255)
    bg.paste(Image.new("RGB", (W, H), (90, 210, 255)), (0, 0), glow.filter(ImageFilter.GaussianBlur(22)).point(lambda v: v * 0.7))
    mask = Image.new("L", (sw, sh), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, sw - 1, sh - 1], 40, fill=255)
    ImageDraw.Draw(bg).rounded_rectangle([x - 6, y - 6, x + sw + 5, y + sh + 5], 46, fill=(255, 205, 90))
    bg.paste(shot, (x, y), mask)
    size = 92
    while True:
        font = ImageFont.truetype(font_path, size)
        lines = wrap(d, text, font, W - 110)
        if len(lines) <= 2 or size <= 60:
            break
        size -= 4
    lh = int(size * 1.15)
    ty = (TOP - lh * len(lines)) // 2 + 10
    for i, ln in enumerate(lines):
        tw = d.textlength(ln, font=font)
        col = (255, 214, 92) if i == 0 else (255, 255, 255)
        d.text(((W - tw) / 2, ty + i * lh), ln, font=font, fill=col, stroke_width=6, stroke_fill=(10, 25, 55))
    return bg

if __name__ == "__main__":
    raw, out, fp = sys.argv[1:4]
    for lang in sorted(os.listdir(raw)):
        if lang not in CAPTIONS:
            continue
        os.makedirs(os.path.join(out, lang), exist_ok=True)
        for n in range(1, 9):
            src = os.path.join(raw, lang, "%d.png" % n)
            if os.path.exists(src):
                frame(src, CAPTIONS[lang][n - 1], fp).save(os.path.join(out, lang, "%d.png" % n), optimize=True)
