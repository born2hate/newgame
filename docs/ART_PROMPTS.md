# Промты для арта «Глубины»

Игра сама подхватывает картинки из папки `art/`: положил файл, перезапустил, и он встал вместо
нарисованной кодом заглушки. Можно добавлять по одному файлу.

## Чем генерировать

- **ChatGPT (генерация картинок)** — лучше всех держит один стиль и умеет прозрачный фон. Рекомендую начать с него.
- **Midjourney** — самая красивая картинка. Прозрачного фона нет, его убирают через remove.bg; единый стиль держится через `--sref`.
- Leonardo.ai, Ideogram, Recraft — тоже подходят. Recraft удобен для иконок.

## Как добиться единого стиля

1. Сначала сгенерируй **реактор** (промт ниже) и перебирай варианты, пока один не понравится.
2. Дальше прикладывай его к каждому запросу: в ChatGPT — «в том же стиле, что на картинке»,
   в Midjourney — `--sref <ссылка на картинку>`.
3. В начало каждого промта вставляй общий блок стиля.

## Общий блок стиля (вставлять в начало каждого промта)

```
Stylized 2D mobile game art, cozy sci-fi underwater colony, hand-painted look with clean
readable shapes, soft volumetric lighting, glowing accents, rich teal and deep blue palette
with warm amber lights, subtle bioluminescence, high detail but uncluttered, polished
premium mobile game quality, consistent art style.
```

## Отсеки → `art/rooms/<имя>.png`

Все отсеки: **1600×1000 px** (16:10), вид строго сбоку, как кукольный домик в разрезе, без перспективы.
Интерьер заполняет кадр целиком до краёв, пол проходит по нижнему краю.
**Без людей, без текста, без внешней рамки.**

Хвост, который добавляется к каждому промту отсека:
```
Flat orthographic side-view cutaway of a single room interior, front wall removed like a
dollhouse, no perspective, interior fills the entire frame edge to edge, flat floor along the
bottom edge, empty room with no people or characters, no text, no labels, no border, 16:10.
```

| Файл | Промт (после блока стиля, перед хвостом) |
|---|---|
| `reactor.png` | `Underwater colony power reactor room: a large glowing amber fusion core in the center inside a reinforced glass cylinder, thick cables and pipes along the walls, warning stripes, control panels with small screens, warm orange light spilling across riveted metal walls.` |
| `oxygen.png` | `Underwater colony oxygen generator room: three tall glass electrolysis tanks filled with seawater and rising bubbles, cyan glowing tubes, pressure gauges and valves, clean white-teal metal panels, fresh cool lighting.` |
| `farm.png` | `Underwater colony algae farm: rows of hydroponic trays with lush green and emerald kelp and seaweed, glowing grow lamps overhead, water pipes, small bioluminescent plants, greenhouse feel, soft green light.` |
| `living.png` | `Underwater colony living quarters: two cozy bunk beds with blankets, a small round porthole window showing dark ocean and a passing fish, a small table with mugs, personal items, posters, warm homely purple and amber lighting.` |
| `storage.png` | `Underwater colony storage room: metal shelving with stacked crates, barrels and supply boxes, cargo nets, a small forklift cart, labeled containers without readable text, industrial brownish lighting.` |
| `pearl.png` | `Underwater colony pearl farm: large open giant clam shells on stands, each holding a glowing pearl, aquarium tanks with pink coral, soft pink and violet iridescent lighting, precious and magical mood.` |
| `medbay.png` | `Underwater colony medical bay: a medical bed with a scanner arm, a glowing healing capsule, cabinets with medkits, a red cross sign without text, sterile white and soft red lighting.` |
| `airlock.png` | `Underwater colony entrance airlock: a heavy round pressure hatch door in the center with a wheel handle, water draining grates on the floor, diving suits and helmets hanging on the wall, yellow-black warning stripes, red and blue signal lights.` |
| `elevator.png` | **750×1000 px (3:4)**: `Underwater colony vertical elevator shaft section, metal rails on both sides, cables, a small platform, industrial lights, seamless so it can stack vertically, flat side view, no people, no text.` |

## Колонисты → `art/characters/diver.png` или `diver_0.png` … `diver_5.png`

**512×1024 px, прозрачный фон**, персонаж в полный рост, смотрит **вправо**, ноги касаются нижнего края.
Одного `diver.png` достаточно; если хочешь разные цвета костюмов — сделай `diver_0…5`
(0 — оранжевый, 1 — жёлтый, 2 — голубой, 3 — розовый, 4 — зелёный, 5 — белый).

```
Full body character, cute chibi underwater colonist in a diving suit with a big round glass
helmet showing a friendly face, small oxygen tank on the back, chunky boots, <orange> suit with
white details, standing pose facing right, side view, feet at the bottom edge, transparent
background, no shadow, no text, 1:2 aspect ratio.
```

## Иконки → `art/icons/<имя>.png`

**256×256 px, прозрачный фон.** Все четыре лучше делать одним запросом («набор из 4 иконок»),
а потом разрезать — так стиль точно совпадёт.

```
Game UI icon, glossy stylized mobile game icon, bold outline, soft inner glow, centered,
transparent background, no text: <объект>
```

| Файл | Объект |
|---|---|
| `energy.png` | `a glowing amber lightning bolt` |
| `oxygen.png` | `a cluster of cyan oxygen bubbles with O2 feel` |
| `food.png` | `a bundle of fresh green kelp leaves` |
| `pearls.png` | `a shiny iridescent pink-white pearl in a small open shell` |

## Фоны → `art/backgrounds/`

| Файл | Размер | Промт |
|---|---|---|
| `ocean.png` | 1080×1920 | `Deep ocean water background, vertical, bright turquoise light and sun rays from the surface at the top fading to dark navy at the bottom, floating particles, distant silhouettes of fish and whales, no seabed, no objects in foreground, no text.` |
| `rock.png` | 1024×1024 | `Seamless tileable texture of dark underwater sedimentary rock, subtle layered strata, small embedded glowing cyan mineral specks, stylized hand-painted, low contrast so objects on top stay readable, top-down flat texture, seamless tile.` |

## Проверка перед тем как класть в игру

- Размер и соотношение сторон как в таблице (иначе картинку растянет).
- Для персонажей и иконок — действительно прозрачный фон (PNG с альфой).
- Нет текста и людей в отсеках.

Готовые файлы можно прислать мне в чат или закинуть в папку `art/`; дальше я подгоню подсветку,
анимацию и эффекты под новый арт.

## Магазин → `art/ui/shop/` и `art/icons/`

| Файл | Что |
|---|---|
| `art/icons/crystals.png` | иконка кристалла (256×256, прозрачный фон) |
| `art/ui/shop/crystals_0.png` … `crystals_5.png` | кучки кристаллов от маленькой до огромной |
| `art/ui/shop/crate_common.png`, `crate_silver.png`, `crate_gold.png` | ящики припасов |
| `art/ui/shop/starter.png`, `premium.png`, `season.png` | баннеры 16:9 |

## Экспедиции

| Файл | Что |
|---|---|
| `art/rooms/dock.png` | отсек-док 16:10: `underwater submarine dock room, a water pool with an open hatch in the floor, mechanical crane arm, fuel pipes, tool racks, yellow warning stripes, no submarine, no people` |
| `art/ui/shop/season.png` | баннер сезонного пропуска 16:9 |

## Новые отсеки (волна 2) → `art/rooms/<имя>.png`

Формат как у остальных отсеков: 1600×1000, блок стиля в начале, хвост отсека в конце.

| Файл | Промт |
|---|---|
| `kitchen.png` | `Underwater colony kitchen and canteen: stainless steel counters, big cooking pots steaming, algae noodles hanging to dry, fridge with glowing green jars, a long dining table with benches, warm cozy yellow light.` |
| `gym.png` | `Underwater colony gym: weight racks with dumbbells and barbells, a punching bag, a treadmill facing a round porthole with fish outside, rubber floor mats, energetic orange and red accent lights.` |
| `workshop.png` | `Underwater colony workshop: a heavy workbench with a vise, welding torch sparks, tools hanging on a pegboard wall, half-built diving suit on a stand, metal scraps and gears, blue welding glow mixed with warm light.` |
| `lounge.png` | `Underwater colony lounge bar: a curved bar counter with glowing bottles, cozy sofas, a jukebox, neon jellyfish decorations, a large round window onto the dark ocean, relaxed purple and pink lighting.` |
| `radio.png` | `Underwater colony radio room: a big antenna console with dials and blinking lights, sonar screen with a green sweep, headphones on a hook, stacked radio equipment, cables running to the ceiling, dim green light.` |
| `armory.png` | `Underwater colony armory: wall racks with harpoon guns and spears, lockers with armored diving suits, ammunition crates, a target board, red warning lights and yellow-black hazard stripes.` |
| `school.png` | `Underwater colony classroom: a big glowing holographic board with a fish diagram, small desks with tablets, shelves with books and specimen jars, a globe of the ocean floor, friendly soft blue light.` |
| `turbine.png` | `Underwater colony current turbine room: a huge spinning turbine propeller behind thick glass, water currents with swirling bubbles, big generators with glowing blue coils, heavy pipes, powerful cool blue lighting.` |
| `aquarium.png` | `Underwater colony aquarium hall: large glass tanks with colorful tropical fish, glowing jellyfish and corals, decorative plants, a bench for visitors, calm turquoise lighting with light ripples on the walls.` |

## Пираты (налёты) → `art/creatures/`

| Файл | Промт |
|---|---|
| `raider_0.png` | `cartoon underwater pirate raider in a rusty patched diving suit with a red bandana and harpoon gun, side view facing right, full body, standing, chibi proportions like a mobile game character, transparent background` |
| `raider_1.png` | то же, но `with a big rusty knife and eye patch` |
| `raider_2.png` | то же, но `a big brute with a riveted metal shield` |
| `pirate_sub.png` | `cartoon pirate submarine, rusty dark hull with skull flag and spikes, side view facing left, transparent background, mobile game style` |

## Боссы глубины → `art/creatures/boss_<id>.png`

Прозрачный фон, вид сбоку, смотрит влево, огромный и страшный, но в мультяшном стиле игры.

| Файл | Промт |
|---|---|
| `boss_angler.png` | `giant monstrous anglerfish boss, glowing lure, huge jagged teeth, dark red and purple scales, side view facing left, cartoon mobile game boss, transparent background` |
| `boss_squid.png` | `giant kraken squid boss with long tentacles and glowing eyes, purple and pink, side view facing left, cartoon mobile game boss, transparent background` |
| `boss_serpent.png` | `huge sea serpent boss, long coiled body, green scales with glowing spines, open jaws, side view facing left, cartoon mobile game boss, transparent background` |
| `boss_crab.png` | `titan crab boss with enormous claws and armored barnacle shell, orange and rust colors, side view facing left, cartoon mobile game boss, transparent background` |

## Питомцы → `art/creatures/pet_<id>.png`

Милые, круглые, в стиле детей-колонистов, вид сбоку, смотрят вправо, прозрачный фон.

| Файл | Промт |
|---|---|
| `pet_clownfish.png` | `cute chibi clownfish pet with big sparkly eyes and a tiny diving helmet bubble, side view facing right, glossy cartoon mobile game style, transparent background` |
| `pet_puffer.png` | `cute chibi pufferfish pet, half puffed with tiny spikes, brave expression, side view facing right, glossy cartoon mobile game style, transparent background` |
| `pet_angel.png` | `cute chibi angelfish pet with flowing fins and a little halo of bubbles, side view facing right, glossy cartoon mobile game style, transparent background` |
| `pet_lion.png` | `cute chibi lionfish pet wearing a tiny explorer hat, side view facing right, glossy cartoon mobile game style, transparent background` |
| `pet_parrot.png` | `cute chibi parrotfish pet, rainbow scales, cheeky smile, side view facing right, glossy cartoon mobile game style, transparent background` |
| `pet_tang.png` | `cute chibi yellow tang fish pet with a tiny red cross medic badge, side view facing right, glossy cartoon mobile game style, transparent background` |

## Оружие и новая броня → `art/items/<id>.png`

Как остальные предметы: квадрат, прозрачный фон, блестящий мультяшный стиль, лежит по диагонали.

| Файл | Промт |
|---|---|
| `spear.png` | `cartoon underwater bone spear weapon with a shark tooth tip and rope wrapping, game item icon, transparent background` |
| `harpoon_gun.png` | `cartoon brass harpoon gun with a barbed harpoon loaded, game item icon, transparent background` |
| `shock_baton.png` | `cartoon electric shock baton with glowing blue coils and sparks, game item icon, transparent background` |
| `trident.png` | `cartoon golden trident with glowing aqua gems, game item icon, transparent background` |
| `plasma_cutter.png` | `cartoon sci-fi plasma cutter tool with an orange glowing blade, game item icon, transparent background` |
| `sonic_blaster.png` | `cartoon sonic blaster gun with a purple glowing dish emitter, game item icon, transparent background` |
| `kelp_vest.png` | `cartoon woven kelp vest armor, green and brown, game item icon, transparent background` |
| `coral_plate.png` | `cartoon armor chestplate made of pink and orange coral pieces, game item icon, transparent background` |
| `titan_suit.png` | `cartoon heavy titanium diving armor suit, silver with rivets, game item icon, transparent background` |
| `abyss_armor.png` | `cartoon dark abyss armor with glowing bioluminescent blue lines and anglerfish motifs, game item icon, transparent background` |

## Колонисты без шлема (отдых) → `art/characters/rest/rest_<0..6>.png`

Тот же персонаж, что в скафандре (art/characters/walk/walk_N_0.png), но без шлема и баллона —
в облегающем комбинезоне того же цвета, стоит боком, смотрит вправо, прозрачный фон.
0 — оранжевый, 1 — жёлтый, 2 — синий, 3 — розовый, 4 — зелёный, 5 — белый, 6 — капитан (золото).

`same chibi character style as the attached diver, but without helmet and air tank, wearing a fitted <color> jumpsuit with white panels, relaxed happy pose, side view facing right, full body, standing, transparent background`

## Research icons → `art/research/<id>.png`

Square, transparent background, glossy cartoon game icon in a round brass frame. A 4×5 grid on one sheet is fine — I'll cut it.
Order: efficient_reactors, hydroponics, electrolysis, reinforced_hull, training_programs, sonar_mapping, fire_suppression, deep_drilling, auto_collectors, medical_ai, bathyscaphe_engines, storage_compression, pearl_cultivation, trader_beacon, abyssal_engineering, legendary_signal, fusion_core.

## Материалы для крафта → `art/materials/<id>.png`

Квадрат, прозрачный фон, блестящий мультяшный стиль, как иконки предметов. Можно одним листом 4×2 — я разрежу.
Порядок: scrap, kelp_fiber, shell, coral, copper, vent_crystal, kraken_ink, abyss_pearl.

`set of 8 cartoon game material icons for an underwater colony game, glossy mobile game style, each on its own, transparent background: 1) pile of rusty scrap metal plates and bolts, 2) bundle of green kelp fiber rope, 3) iridescent pearl shell, 4) branch of red-orange coral, 5) coil of shiny copper wire, 6) glowing cyan hydrothermal vent crystal, 7) bottle of glowing purple kraken ink, 8) large glowing white abyss pearl with a faint blue aura`

## Чертёж → `art/ui/blueprint.png`

`cartoon rolled-out blueprint scroll with white technical drawing of a harpoon on blue paper, slightly curled edges, glossy mobile game item icon, transparent background`

## Таинственный незнакомец → `art/characters/stranger.png`

Как колонисты (тот же чиби-стиль), вид сбоку, смотрит вправо, во весь рост.

`mysterious stranger character in the same chibi style as the attached diver: long dark trench coat over an old brass diving suit, wide-brim hat, face hidden in shadow with two glowing eyes behind the helmet glass, holding a small lantern, side view facing right, full body, transparent background`

## Черты характера → `art/ui/traits/<id>.png`

Круглые значки-медальки, прозрачный фон. Можно листом 4×2.
Порядок: brave, tough, lucky, genius, cheerful, night_owl, lazy, clumsy.

`set of 8 round cartoon badge icons for character traits, glossy mobile game style, brass rim, transparent background: 1) brave — red shield with a lion face, 2) tough — flexed arm with a bandage, 3) lucky — four-leaf clover with a pearl, 4) genius — glowing light bulb with a brain, 5) cheerful — big smiling sun, 6) night owl — owl under a crescent moon, 7) lazy — sleeping face with Zzz on a pillow, 8) clumsy — banana peel and a tilted wrench`

## Проекты колонии → `art/projects/<id>.png`

Широкие картинки 16:9, как фоны зон экспедиций. Подводная колония, мультяшный стиль игры.

| Файл | Промт |
|---|---|
| `garden_dome.png` | `huge glass dome garden on the sea floor full of glowing plants and little trees, colonists in diving suits tending it, cartoon underwater colony game art, wide 16:9` |
| `survivor_beacon.png` | `tall underwater radio beacon tower with a bright rotating light beam cutting through dark water, small submarines approaching, cartoon underwater colony game art, wide 16:9` |
| `deep_bathyscaphe.png` | `giant heavy armored bathyscaphe in a dry dock under construction with cranes and sparks, glowing portholes, cartoon underwater colony game art, wide 16:9` |
| `pearl_monument.png` | `grand monument statue of a diver holding a giant glowing pearl in the colony plaza, coral and lights around, cartoon underwater colony game art, wide 16:9` |

## Морская буря → `art/ui/storm.png`

`cartoon underwater storm event icon: swirling dark current vortex with lightning flashes from the surface above and a frightened little fish, glossy mobile game icon, transparent background`

## Жетон события → `art/icons/event_token.png`

`shiny golden event coin with an embossed starfish and tiny pearls around the rim, glossy cartoon mobile game currency icon, transparent background`

## Трофеи событий → `art/ui/trophies/<id>.png`

Можно одним листом 4×1. Порядок: pearl_week, tide, harvest, explorers.

`set of 4 cartoon trophy icons for weekly events in an underwater colony game, glossy mobile game style, each on a small brass pedestal, transparent background: 1) Golden Clam — a golden clam shell opened with a glowing pink pearl, 2) Tide Breaker — a silver-blue trident crossing a breaking wave, 3) Kelp Crown — a crown woven from green kelp with small glowing buds, 4) Brass Compass — an ornate brass diving compass with a glowing needle`

## Баннеры событий недели → `art/events/weekly_<id>.png`

Широкие 16:9, как картинки проектов. Сверху в магазине события.

| Файл | Промт |
|---|---|
| `weekly_pearl_week.png` | `festive underwater colony celebrating Pearl Week: giant oysters opening with glowing pearls, colonists in diving suits collecting pearls into baskets, pink and gold lights, cartoon underwater colony game art, wide 16:9` |
| `weekly_tide.png` | `Abyssal Tide event: dark stormy deep water, swarms of glowing jellyfish and anglerfish approaching an underwater colony, colonists with harpoons defending the airlock, dramatic blue-purple light, cartoon underwater colony game art, wide 16:9` |
| `weekly_harvest.png` | `Harvest Festival in an underwater colony: farms overflowing with glowing kelp and sea fruit, lanterns and garlands, colonists carrying crates of food, warm green and gold light, cartoon underwater colony game art, wide 16:9` |
| `weekly_explorers.png` | `Explorer's Season: a fleet of small submarines leaving the colony dock toward a mysterious glowing trench, treasure map overlay, warm brass and cyan light, cartoon underwater colony game art, wide 16:9` |
