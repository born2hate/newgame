# Ответы для анкет Google Play Console

Всё ниже — для текущей сборки: игра без сервера, сохранения на телефоне, реклама AdMob за награду, покупки через Google Play.

## App content → Privacy policy
Ссылка на `privacy_policy.html` (выложить на GitHub Pages, Google Sites или любой хостинг). В файле замени `[your contact email]` на свою почту.

## App content → Ads
**Contains ads: Yes** (видео за награду AdMob).

## App content → App access
All functionality is available without special access.

## App content → Target audience
**13–15, 16–17, 18+** (не выбирать младше 13: иначе обязательна программа Families и особые требования к рекламе).
Appeals to children: **No**.

## App content → Data safety
- Does your app collect or share any of the required user data types? **Yes**
- Data collected: **Device or other IDs** (advertising ID) — collected by the AdMob SDK.
  - Collected: Yes · Shared: Yes (with Google for advertising)
  - Purpose: **Advertising or marketing**, **Analytics**
  - Required/optional: **Required** (when ads are shown)
- **App info and performance → Crash logs / Diagnostics**: collected by AdMob SDK — Purpose: Analytics.
- **Approximate location**: collected by AdMob SDK — Purpose: Advertising.
- Purchase history: **No** (обрабатывает Google Play, нам не передаётся).
- Is all data encrypted in transit? **Yes**
- Can users request deletion? **No server data** — удаление игры удаляет всё. (Можно ответить «No» с пояснением.)

## Content rating (IARC)
- Category: **Game**
- Violence: **Fantasy / cartoon violence** (бои с морскими чудовищами и пиратами, без крови).
- Fear: mild (чудовища).
- Gambling: **No** real gambling.
- **Random items for purchase (loot boxes): Yes** — ящики с наградами можно купить за кристаллы; шансы показаны в магазине.
- In-app purchases: **Yes**. Users interact: **No**. Shares location: **No**.
Ожидаемый рейтинг: PEGI 7 / ESRB Everyone 10+.

## Monetize → In-app products (Managed products)
ID должны совпадать с кодом (`scripts/store.gd`). Цены — рекомендованные, Google сам пересчитает по странам.

| Product ID | Название | Цена |
|---|---|---|
| `starter_pack` | Starter Pack | $1.99 |
| `premium` | Premium | $4.99 |
| `no_ads` | No Ads | $2.99 |
| `season_pass` | Season Pass | $4.99 |
| `piggy_bank` | Treasure Piggy Bank | $2.99 |
| `offer_hero` | Hero Bundle | $4.99 |
| `offer_builder` | Builder Bundle | $3.99 |
| `offer_medic` | Medic Bundle | $1.99 |
| `crystals_60` | Handful of Crystals | $0.99 |
| `crystals_330` | Pouch of Crystals | $4.99 |
| `crystals_700` | Chest of Crystals | $9.99 |
| `crystals_1500` | Big Chest | $19.99 |
| `crystals_4000` | Treasure Hoard | $49.99 |
| `crystals_9000` | Abyss Vault | $99.99 |

Все товары — **одноразовые (managed)**. Повторяемые (кристаллы, копилка, сезонный пропуск) игра сама «потребляет» после выдачи.
