# Changelog

All notable changes to **Deep Colony** are listed here, newest first.
APK builds live in [`releases/`](releases/).

## Unreleased
### Added
- **Phone notifications** (scheduled when the game goes to the background, cancelled on return): expedition back, child grown up, research done, all rooms ready, free crate, daily reward, a gentle "we miss you" after 2 days. At most one every 30 minutes; can be turned off in Settings. Needs the native local-notification plugin in the release build.
- **New sounds**: hits on bosses, boss roar, raid horn, rising notes while combo collecting, coins flying to the top bar, a lullaby for a newborn, repair clinks.
- **Tense music** fades in during pirate raids and boss fights.
### Changed
- **Shorter tutorial**: 6 hands-on steps instead of 11 — collect, build, place, drag, done.

## 0.11 — 2026-10-01
### Added
- **Colony stats** screen (Tasks → Colony stats): days since founding, population record, children born, raids and bosses defeated, incidents, expeditions, research, crates, losses and revivals.
- **Weapons** — a fourth gear slot with 6 weapons (Bone Spear, Harpoon Gun, Shock Baton, Trident, Plasma Cutter, Sonic Blaster). Each has its own attack animation and helps against pirates, monsters and bosses.
- **4 new armors**: Kelp Vest, Coral Plate, Titan Suit, Abyss Armor.
- **Pets** — 6 collectible fish, each with its own bonus (collections, combat, mood, loot, rush luck, healing). Found in Silver and Gold crates.
- **Room damage and repair** — an incident left to burn out breaks the room (half speed) until repaired.
- **No helmets at rest** — colonists in Living Quarters, the Lounge and the Observation Deck take their helmets off.
- Tapping a **locked depth zone** opens Research with the whole path to *Deep Drilling* / *Abyssal Engineering* highlighted.
### Changed
- Monster attacks show **which creature** attacks (Anglerfish, Giant Crab, Giant Squid, Sea Serpent) with a big readable sprite and name; zoomed-out view shows a blinking hazard icon above the room.
- The **Collect all** button no longer builds combo — combo comes only from tapping rooms one by one.
- Pearl crates are cheaper: Supply Crate 1,500, Silver Crate 5,000 (+50% per purchase each day).

## 0.10 — 2026-10-01
### Added
- **Pirate raids** (from 10 colonists): a pirate sub docks, raiders break the airlock door (upgradeable) and move room to room, stealing from empty rooms and fighting colonists. Defeated raiders leave bodies to loot for 10 minutes.
- **Deep bosses** (from 15 colonists): Giant Anglerfish, Kraken, Sea Serpent, Titan Crab. Tap to fight, colonists help, the boss attacks rooms; 2.5 minutes to win.
- **Expedition choices**: a sealed chest, a wounded stranger, a cave shortcut, glowing coral — risk it or play safe.
- **Children**: two colonists in Living Quarters can have a child who grows up into a colonist with mixed stats.
- **Combo collecting** (+10% per quick tap, up to +50%), resources fly to the top bar, light screen shake.
- **Colony level** with a golden progress bar and rewards.
- Pearls → crates exchange in the shop.
- Fallout-style room perspective that follows the camera.
### Changed
- After 8 colonists, new people arrive **only through the Radio Room**.
- Economy rebalanced with a bot simulator (`tools/economy_sim.gd`): diminishing returns, capped room speed, ad rewards limited to 12 per day, fewer crystals.
- Revive timers and raider bodies pause while you are away; minimising the app now counts as time away.

## 0.9 — 2026-10-01
### Added
- **Death and revival**: fallen colonists can be revived for pearls (cost grows with level) within 2 hours (30 minutes in Survival).
- **Fallout-style expeditions**: named enemies, damage and XP per fight, loot found along the way, live summary.
- Fire extinguisher, bucket and pump while fighting incidents; ambient room animations.
- 18 daily quest types (4 per day, targets scale with the colony) and 8 new story chapters.
### Changed
- Harder economy and slower colonist levelling.
- Unattended incidents spread to neighbouring rooms (including floors above/below) and eventually burn out.
- Offline resource drain is 4× slower and never empties your stores.
- The trader opens from the "$" icon above its sub; the pet no longer swims over the rooms.

## 0.8 — 2026-09-30
### Added
- **10 new rooms**: Kitchen, Gym, School, Radio Room, Lounge, Workshop, Armory, Aquarium, Current Turbine, Observation Deck; new Living Quarters art at level 3.
- **New colonist stats**: Endurance, Charm, Luck and Mood.
- **Landscape mode** — rotate the phone, menus open on the right.
- Hand-drawn fire, smoke, water, splashes and sparks; 12 new fish; loading screen; room thumbnails in the Build menu.

## 0.7.1 — 2026-09-30
### Fixed
- Collecting the reactor during the tutorial, a "Collect" button in the room card, reward popup text wrapping.

## 0.7 — 2026-09-30
### Added
- Automated UI self-test in all 10 languages; many layout fixes.

## 0.6 — 2026-09-30
### Added
- Colonists stand at work stations with work effects, fights during attacks, depth sorting.
- Going outside through the airlock dome, safe-area support for punch-hole screens.
### Changed
- Slower game pace, wider base.

## 0.5 — 2026-09-30
### Added
- First Android build: cross-section base, rooms, colonists, resources, shop, expeditions, daily quests, season pass, incidents, research, depth zones, gear, room merging, story, achievements, tutorial, difficulty modes, 10 languages, sound and music.
