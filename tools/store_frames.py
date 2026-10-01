#!/usr/bin/env python3
"""Store screenshots: caption on top + game screenshot in a frame (1080x1920).
python3 tools/store_frames.py <raw_dir> <out_dir> <font.ttf>
raw_dir/<lang>/<n>.png -> out_dir/<lang>/<n>.png"""
import sys, os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

CAPTIONS = {
 "en": ["Build your own underwater colony", "Fight giant deep-sea bosses", "Defend against pirate raids", "Put out fires, stop floods",
        "Send crews on risky expeditions", "Gear up with weapons and armor", "Raise families, grow your colony", "Collect pets with special powers"],
 "ru": ["Построй свою подводную колонию", "Сражайся с гигантскими боссами", "Отбивай налёты пиратов", "Туши пожары, останавливай потопы",
        "Отправляй отряды в экспедиции", "Оружие и броня для героев", "Создавай семьи, расти колонию", "Собирай питомцев с бонусами"],
 "es": ["Construye tu colonia submarina", "Lucha contra jefes gigantes", "Defiéndete de los piratas", "Apaga incendios, detén inundaciones",
        "Envía equipos a expediciones", "Equípate con armas y armaduras", "Forma familias, haz crecer tu colonia", "Colecciona mascotas con poderes"],
 "pt_BR": ["Construa sua colônia submarina", "Enfrente chefes gigantes", "Defenda-se de ataques piratas", "Apague incêndios, pare inundações",
        "Envie equipes em expedições", "Equipe-se com armas e armaduras", "Forme famílias, cresça a colônia", "Colecione mascotes com poderes"],
 "de": ["Baue deine Unterwasserkolonie", "Kämpfe gegen riesige Bosse", "Wehre Piratenüberfälle ab", "Lösche Brände, stoppe Fluten",
        "Schicke Trupps auf Expeditionen", "Rüste dich mit Waffen und Rüstung", "Gründe Familien, lass die Kolonie wachsen", "Sammle Haustiere mit Boni"],
 "fr": ["Bâtis ta colonie sous-marine", "Affronte des boss géants", "Repousse les raids pirates", "Éteins les incendies, stoppe les inondations",
        "Envoie des équipes en expédition", "Équipe-toi d'armes et d'armures", "Fonde des familles, agrandis ta colonie", "Collectionne des familiers"],
 "it": ["Costruisci la tua colonia sottomarina", "Combatti boss giganti", "Respingi i raid dei pirati", "Spegni incendi, ferma allagamenti",
        "Invia squadre in spedizione", "Armi e armature per i tuoi eroi", "Crea famiglie, fai crescere la colonia", "Colleziona animali con poteri"],
 "tr": ["Kendi sualtı koloni̇ni kur", "Dev boslarla savaş", "Korsan baskınlarını püskürt", "Yangınları söndür, selleri durdur",
        "Ekipleri keşiflere gönder", "Silah ve zırhla donan", "Aileler kur, koloniyi büyüt", "Güçlü evcil hayvanlar topla"],
 "pl": ["Zbuduj podwodną kolonię", "Walcz z gigantycznymi bossami", "Odpieraj ataki piratów", "Gaś pożary, zatrzymuj powodzie",
        "Wysyłaj drużyny na wyprawy", "Broń i pancerze dla bohaterów", "Zakładaj rodziny, rozwijaj kolonię", "Zbieraj zwierzaki z bonusami"],
 "id": ["Bangun koloni bawah lautmu", "Lawan bos raksasa laut dalam", "Tangkis serangan bajak laut", "Padamkan api, hentikan banjir",
        "Kirim tim ke ekspedisi", "Senjata dan zirah untuk timmu", "Bangun keluarga, besarkan koloni", "Kumpulkan hewan peliharaan"],
}
CAPTIONS["tr"][0] = "Kendi sualtı kolonini kur"

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
