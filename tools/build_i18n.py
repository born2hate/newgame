"""Собирает i18n/src/<lang>.txt (по строке на ключ из keys.json) в i18n/<lang>.gd.
Проверяет, что в переводе те же %d/%s/{n}, что и в оригинале."""
import json, re, sys, os

LANGS = ["ru", "es", "pt_BR", "de", "fr", "it", "tr", "pl", "id", "ja", "ko", "zh_CN"]
keys = json.load(open("i18n/src/keys.json"))


def sig(s):
    return re.findall(r"%[ds%]|\{n\}", s)


def esc(s):
    return s.replace("\\", "\\\\").replace('"', '\\"')


ok = True
for lang in LANGS:
    path = f"i18n/src/{lang}.txt"
    if not os.path.exists(path):
        continue
    # формат строки: «номер|перевод»
    tr_map = {}
    for line in open(path, encoding="utf-8").read().split("\n"):
        if "|" in line:
            n, v = line.split("|", 1)
            tr_map[int(n)] = v.strip()
    missing = [i for i in range(len(keys)) if i not in tr_map]
    if missing:
        print(f"{lang}: нет перевода для {missing[:20]}{'…' if len(missing) > 20 else ''}")
        ok = False
        continue
    lines = [tr_map[i] for i in range(len(keys))]
    bad = [(i, k, v) for i, (k, v) in enumerate(zip(keys, lines)) if sig(k) != sig(v)]
    for i, k, v in bad:
        print(f"{lang} #{i}: {k!r} -> {v!r}")
        ok = False
    if bad:
        continue
    with open(f"i18n/{lang}.gd", "w", encoding="utf-8") as f:
        f.write("extends RefCounted\n## Сгенерировано tools/build_i18n.py из i18n/src — не править вручную.\n\n")
        f.write(f'const LOCALE := "{lang}"\n\nconst T := {{\n')
        for k, v in zip(keys, lines):
            f.write(f'\t"{esc(k)}": "{esc(v)}",\n')
        f.write("}\n\nstatic func make() -> Translation:\n\tvar t := Translation.new()\n\tt.locale = LOCALE\n")
        f.write("\tfor k in T:\n\t\tt.add_message(k, T[k])\n\treturn t\n")
    print(f"{lang}: ok")
sys.exit(0 if ok else 1)
