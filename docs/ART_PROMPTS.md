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
