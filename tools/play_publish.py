#!/usr/bin/env python3
"""Публикация в Google Play через Android Publisher API.

Ключ сервисного аккаунта: переменная PLAY_KEY (путь к JSON). Ключ в репозиторий не класть.

  python3 tools/play_publish.py check                 — проверить доступ к приложению
  python3 tools/play_publish.py listings [--images]   — тексты страницы магазина на 10 языках (+ иконка, обложка, скриншоты)
  python3 tools/play_publish.py show                  — что сейчас загружено в Play
  python3 tools/play_publish.py bundle build/DeepColony.aab [--track internal]
                                                      — загрузить AAB и выпустить в трек (по умолчанию internal)
  python3 tools/play_publish.py products              — создать/обновить и активировать товары из scripts/store.gd
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


def cmd_bundle(path: str, track: str) -> None:
    svc = service()
    eid = svc.edits().insert(packageName=PACKAGE, body={}).execute(num_retries=6)["id"]
    media = MediaFileUpload(path, mimetype="application/octet-stream", resumable=True, chunksize=8 * 1024 * 1024)
    bundle = svc.edits().bundles().upload(packageName=PACKAGE, editId=eid, media_body=media).execute(num_retries=6)
    vc = bundle["versionCode"]
    print(f"  uploaded versionCode {vc} ({bundle.get('sha256', '')[:12]})")
    name = re.search(r'version/name="([^"]+)"', open(os.path.join(ROOT, "export_presets.cfg")).read()).group(1)
    for status in ("completed", "draft"):
        release = {"name": f"{name} ({vc})", "versionCodes": [str(vc)], "status": status}
        try:
            svc.edits().tracks().update(packageName=PACKAGE, editId=eid, track=track,
                                        body={"track": track, "releases": [release]}).execute(num_retries=6)
            svc.edits().commit(packageName=PACKAGE, editId=eid).execute(num_retries=6)
            print(f"  {track}: release {release['name']} — {status}")
            return
        except Exception as e:  # у ещё не опубликованного приложения можно создать только черновик
            if status == "draft" or "draft" not in str(e).lower():
                raise
            print("  app is still a draft in Play: creating the release as a draft")


# Цены в долларах — как в docs/store/play_console_answers.md; Play пересчитывает их по странам.


def iap_products() -> list:
    """Товары из scripts/store.gd (const IAP): id, название, описание, цена."""
    src = open(os.path.join(ROOT, "scripts", "store.gd"), encoding="utf-8").read()
    block = src[src.index("const IAP := ["):src.index("## Товары за кристаллы.")]
    items = []
    for m in re.finditer(r'\{"id": "([a-z0-9_]+)", "title": "([^"]+)", "price": "\$([0-9.]+)"(.*?)(?=\n\t\{"id"|\n\]|\n\t#)', block, re.S):
        pid, title, price, rest = m.groups()
        d = re.search(r'"desc": "([^"]+)"', rest)
        cr = re.search(r'"crystals": (\d+)\}, "pack"', rest)
        desc = d.group(1) if d else (f"{cr.group(1)} crystals (double on the first purchase)" if cr else title)
        items.append({"id": pid, "title": title[:55], "desc": desc[:200], "price": price})
    return items


def money(usd: str) -> dict:
    units, _, cents = usd.partition(".")
    return {"currencyCode": "USD", "units": units, "nanos": int((cents + "00")[:2]) * 10_000_000}


def cmd_products() -> None:
    svc = service()
    otp = svc.monetization().onetimeproducts()
    items = iap_products()
    assert len(items) == 15, [i["id"] for i in items]
    for it in items:
        conv = svc.monetization().convertRegionPrices(
            packageName=PACKAGE, body={"price": money(it["price"])}).execute(num_retries=6)
        regions = [{"regionCode": code, "price": r["price"], "availability": "AVAILABLE"}
                   for code, r in sorted(conv.get("convertedRegionPrices", {}).items())]
        other = conv.get("convertedOtherRegionsPrice", {})
        option = {
            "purchaseOptionId": "buy",
            "buyOption": {"legacyCompatible": True, "multiQuantityEnabled": False},
            "regionalPricingAndAvailabilityConfigs": regions,
        }
        if other:
            option["newRegionsConfig"] = {"usdPrice": other["usdPrice"], "eurPrice": other["eurPrice"],
                                          "availability": "AVAILABLE"}
        body = {
            "packageName": PACKAGE, "productId": it["id"],
            "listings": [{"languageCode": "en-US", "title": it["title"], "description": it["desc"]}],
            "purchaseOptions": [option],
        }
        otp.patch(packageName=PACKAGE, productId=it["id"], body=body, allowMissing=True,
                  updateMask="listings,purchaseOptions",
                  regionsVersion_version=conv["regionVersion"]["version"]
                  ).execute(num_retries=6)
        otp.purchaseOptions().batchUpdateStates(packageName=PACKAGE, productId=it["id"], body={"requests": [
            {"activatePurchaseOptionRequest": {"packageName": PACKAGE, "productId": it["id"],
                                               "purchaseOptionId": "buy"}}]}).execute(num_retries=6)
        print(f"  {it['id']}: ${it['price']} — {it['title']} ({len(regions)} regions), active")


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "check"
    if cmd == "listings":
        cmd_listings("--images" in sys.argv)
    elif cmd == "bundle" and len(sys.argv) > 2:
        cmd_bundle(sys.argv[2], sys.argv[sys.argv.index("--track") + 1] if "--track" in sys.argv else "internal")
    elif cmd == "products":
        cmd_products()
    elif cmd in ("show", "check"):
        cmd_show()
    else:
        sys.exit(__doc__)
