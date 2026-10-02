#!/usr/bin/env python3
"""Публикация в Google Play через Android Publisher API.

Ключ сервисного аккаунта: переменная PLAY_KEY (путь к JSON). Ключ в репозиторий не класть.

  python3 tools/play_publish.py check                 — проверить доступ к приложению
  python3 tools/play_publish.py listings [--images]   — тексты страницы магазина на 10 языках (+ иконка, обложка, скриншоты)
  python3 tools/play_publish.py show                  — что сейчас загружено в Play
"""
import os
import re
import sys

from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.http import MediaFileUpload

PACKAGE = "com.deepcolony.game"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STORE = os.path.join(ROOT, "docs", "store")
# язык в Play → папка со скриншотами
LANGS = {
    "en-US": "en", "ru-RU": "ru", "de-DE": "de", "es-ES": "es", "fr-FR": "fr",
    "it-IT": "it", "pt-BR": "pt_BR", "tr-TR": "tr", "pl-PL": "pl", "id": "id",
}


def service():
    key = os.environ.get("PLAY_KEY")
    if not key or not os.path.exists(key):
        sys.exit("Set PLAY_KEY to the service account JSON path")
    creds = service_account.Credentials.from_service_account_file(
        key, scopes=["https://www.googleapis.com/auth/androidpublisher"])
    return build("androidpublisher", "v3", credentials=creds, cache_discovery=False)


def parse_listing(lang: str) -> dict:
    """docs/store/listing/<lang>.md → title / shortDescription / fullDescription."""
    text = open(os.path.join(STORE, "listing", lang + ".md"), encoding="utf-8").read()
    parts = re.split(r"^# .*$", text, flags=re.M)[1:]
    title, short, full = (p.strip() for p in parts[:3])
    assert len(title) <= 30 and len(short) <= 80 and len(full) <= 4000, lang
    return {"language": lang, "title": title, "shortDescription": short, "fullDescription": full}


def upload_images(svc, edit_id: str, lang: str, folder: str) -> None:
    ed = svc.edits().images()
    if lang == "en-US":
        for kind, f in [("icon", "icon_512.png"), ("featureGraphic", "feature_graphic.png")]:
            ed.deleteall(packageName=PACKAGE, editId=edit_id, language=lang, imageType=kind).execute(num_retries=6)
            ed.upload(packageName=PACKAGE, editId=edit_id, language=lang, imageType=kind,
                      media_body=MediaFileUpload(os.path.join(STORE, f), mimetype="image/png")).execute(num_retries=6)
    shots = sorted(f for f in os.listdir(os.path.join(STORE, "screenshots", folder)) if f.endswith(".jpg"))
    for kind in ["phoneScreenshots", "sevenInchScreenshots", "tenInchScreenshots"]:
        ed.deleteall(packageName=PACKAGE, editId=edit_id, language=lang, imageType=kind).execute(num_retries=6)
        for f in shots:
            ed.upload(packageName=PACKAGE, editId=edit_id, language=lang, imageType=kind,
                      media_body=MediaFileUpload(os.path.join(STORE, "screenshots", folder, f),
                                                 mimetype="image/jpeg")).execute(num_retries=6)
    print(f"  {lang}: images uploaded ({len(shots)} screenshots)")


def cmd_listings(images: bool) -> None:
    svc = service()
    edit = svc.edits().insert(packageName=PACKAGE, body={}).execute(num_retries=6)
    eid = edit["id"]
    for lang, folder in LANGS.items():
        body = parse_listing(lang)
        svc.edits().listings().update(packageName=PACKAGE, editId=eid, language=lang, body=body).execute(num_retries=6)
        print(f"  {lang}: {body['title']}")
        if images:
            upload_images(svc, eid, lang, folder)
    svc.edits().commit(packageName=PACKAGE, editId=eid, changesNotSentForReview=False).execute(num_retries=6)
    print("committed")


def cmd_show() -> None:
    svc = service()
    eid = svc.edits().insert(packageName=PACKAGE, body={}).execute(num_retries=6)["id"]
    det = svc.edits().details().get(packageName=PACKAGE, editId=eid).execute(num_retries=6)
    print("details:", det)
    for l in svc.edits().listings().list(packageName=PACKAGE, editId=eid).execute(num_retries=6).get("listings", []):
        print(" ", l["language"], "|", l.get("title"))
    for t in svc.edits().tracks().list(packageName=PACKAGE, editId=eid).execute(num_retries=6).get("tracks", []):
        print("  track", t["track"], t.get("releases"))
    svc.edits().delete(packageName=PACKAGE, editId=eid).execute(num_retries=6)


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "check"
    if cmd == "listings":
        cmd_listings("--images" in sys.argv)
    elif cmd in ("show", "check"):
        cmd_show()
    else:
        sys.exit(__doc__)
