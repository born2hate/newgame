class_name Defs
extends RefCounted
## Статические данные игры: типы комнат, ресурсы, имена колонистов.

const GRID_COLS := 14
const MAX_DEPTH := 14
const MAX_LEVEL := 5
## Уровень колонии, с которого можно улучшать отсеки до 4 и 5 уровня.
const LEVEL_GATE := {4: 8, 5: 12}
## Множитель цены улучшения: 1→2, 2→3, 3→4, 4→5 (от базовой цены отсека).
const UPGRADE_MULT := [1.5, 4.0, 18.0, 45.0]

const RESOURCES := {
	"energy": {"name": "Energy", "short": "E", "color": Color(1.0, 0.82, 0.3)},
	"oxygen": {"name": "Oxygen", "short": "O₂", "color": Color(0.35, 0.92, 1.0)},
	"food": {"name": "Food", "short": "F", "color": Color(0.5, 1.0, 0.55)},
	"pearls": {"name": "Pearls", "short": "P", "color": Color(1.0, 0.75, 0.95)},
	"crystals": {"name": "Crystals", "short": "C", "color": Color(0.55, 0.8, 1.0)},
	"science": {"name": "Science", "short": "S", "color": Color(0.75, 0.6, 1.0)},
	"gear": {"name": "Gear", "short": "G", "color": Color(1.0, 0.65, 0.35)},
}

const STATS := {
	"str": "Strength",
	"tech": "Tech",
	"bio": "Biology",
	"end": "Endurance",
	"cha": "Charm",
	"luck": "Luck",
}
const ALL_STATS := ["str", "tech", "bio", "end", "cha", "luck"]
const STAT_COLORS := {
	"str": Color(1.0, 0.72, 0.25), "tech": Color(0.35, 0.85, 1.0), "bio": Color(0.45, 0.95, 0.5),
	"end": Color(1.0, 0.45, 0.4), "cha": Color(1.0, 0.55, 0.9), "luck": Color(0.75, 1.0, 0.35),
}

## width — ширина в клетках; slots — рабочих мест на 1 уровне;
## produces/stat/amount/cycle — производство; energy — расход энергии в секунду;
## unlock_pop — сколько колонистов нужно для открытия.
const ROOMS := {
	"airlock": {
		"name": "Airlock", "width": 2, "cost": 200, "buildable": false, "upgradable": true, "slots": 0,
		"energy": 0.0, "color": Color(0.35, 0.4, 0.5), "icon": "⇅",
		"desc": "Colony entrance. New colonists arrive here. Upgrade the door to hold pirates back longer.",
	},
	"elevator": {
		"name": "Elevator", "width": 1, "cost": 40, "buildable": true, "slots": 0,
		"energy": 0.0, "color": Color(0.25, 0.3, 0.38), "icon": "↕", "unlock_pop": 0,
		"desc": "Connects levels. Build above or below another elevator.",
	},
	"living": {
		"name": "Living Quarters", "width": 2, "cost": 100, "buildable": true,
		"capacity": 4, "energy": 0.05, "color": Color(0.75, 0.45, 0.9), "icon": "⌂",
		"slots": 2, "stat": "cha", "breeds": true,
		"unlock_pop": 0, "desc": "+4 colonist capacity per level. Put two colonists here and they may have a child. Charm helps.",
	},
	"reactor": {
		"name": "Reactor", "width": 2, "cost": 100, "buildable": true, "slots": 2,
		"produces": "energy", "stat": "str", "amount": 14.0, "cycle": 20.0,
		"energy": 0.0, "color": Color(1.0, 0.72, 0.2), "icon": "ϟ", "unlock_pop": 0,
		"desc": "Produces energy. Needs Strength.",
	},
	"oxygen": {
		"name": "O₂ Generator", "width": 2, "cost": 100, "buildable": true, "slots": 2,
		"produces": "oxygen", "stat": "tech", "amount": 12.0, "cycle": 20.0,
		"energy": 0.12, "color": Color(0.3, 0.85, 1.0), "icon": "○", "unlock_pop": 0,
		"desc": "Extracts oxygen from seawater. Needs Tech.",
	},
	"farm": {
		"name": "Algae Farm", "width": 2, "cost": 100, "buildable": true, "slots": 2,
		"produces": "food", "stat": "bio", "amount": 12.0, "cycle": 20.0,
		"energy": 0.12, "color": Color(0.4, 0.95, 0.45), "icon": "❦", "unlock_pop": 0,
		"desc": "Grows food. Needs Biology.",
	},
	"storage": {
		"name": "Storage", "width": 2, "cost": 150, "buildable": true, "slots": 0,
		"storage": 60.0, "energy": 0.05, "color": Color(0.6, 0.55, 0.45), "icon": "▦",
		"unlock_pop": 8, "desc": "+60 capacity for every resource per level.",
	},
	"pearl": {
		"name": "Pearl Farm", "width": 2, "cost": 250, "buildable": true, "slots": 2,
		"produces": "pearls", "stat": "bio", "amount": 40.0, "cycle": 120.0,
		"energy": 0.2, "color": Color(1.0, 0.6, 0.9), "icon": "◉", "unlock_pop": 10,
		"desc": "Grows pearls, the colony currency.",
	},
	"dock": {
		"name": "Sub Dock", "width": 2, "cost": 180, "buildable": true, "slots": 0,
		"energy": 0.1, "color": Color(1.0, 0.8, 0.3), "icon": "⚓", "unlock_pop": 5,
		"desc": "Home of a bathyscaphe. Send crews on expeditions for loot.",
	},
	"lab": {
		"name": "Research Lab", "width": 2, "cost": 220, "buildable": true, "slots": 2,
		"produces": "science", "stat": "tech", "amount": 10.0, "cycle": 30.0,
		"energy": 0.18, "color": Color(0.7, 0.55, 1.0), "icon": "⚗", "unlock_pop": 6,
		"desc": "Produces science for research. Needs Tech.",
	},
	"medbay": {
		"name": "Medbay", "width": 2, "cost": 200, "buildable": true, "slots": 2,
		"stat": "bio", "heal": true, "energy": 0.15, "color": Color(1.0, 0.4, 0.45),
		"icon": "✚", "unlock_pop": 12, "desc": "Heals all colonists. Needs Biology.",
	},
	## Вторая волна: открываются позже, чтобы стройка не заканчивалась быстро.
	## train — какие характеристики качают работники; mood — прибавка к настроению всех;
	## auto — работает без людей; min_row — строится не выше этого ряда.
	"kitchen": {
		"name": "Kitchen", "width": 2, "cost": 300, "buildable": true, "slots": 2,
		"produces": "food", "stat": "bio", "amount": 30.0, "cycle": 40.0, "mood": 6,
		"energy": 0.15, "color": Color(1.0, 0.75, 0.4), "icon": "♨", "unlock_pop": 14,
		"desc": "Cooks hearty meals: lots of food and a better mood. Needs Biology.",
	},
	"gym": {
		"name": "Gym", "width": 2, "cost": 350, "buildable": true, "slots": 2,
		"stat": "end", "train": ["str", "end"], "energy": 0.1,
		"color": Color(1.0, 0.45, 0.35), "icon": "✊", "unlock_pop": 16,
		"desc": "Workers train Strength and Endurance.",
	},
	"school": {
		"name": "School", "width": 2, "cost": 350, "buildable": true, "slots": 2,
		"stat": "tech", "train": ["tech", "bio"], "energy": 0.1,
		"color": Color(0.45, 0.7, 1.0), "icon": "✎", "unlock_pop": 18,
		"desc": "Workers study Tech and Biology.",
	},
	"radio": {
		"name": "Radio Room", "width": 2, "cost": 400, "buildable": true, "slots": 2,
		"stat": "cha", "energy": 0.15, "color": Color(0.5, 1.0, 0.6), "icon": "☊",
		"unlock_pop": 8, "desc": "Broadcasts to survivors: the main way to get new colonists once the colony grows. Also attracts traders. Needs Charm.",
	},
	"lounge": {
		"name": "Lounge", "width": 2, "cost": 400, "buildable": true, "slots": 2,
		"stat": "cha", "train": ["cha", "luck"], "mood": 10, "energy": 0.1,
		"color": Color(0.85, 0.5, 1.0), "icon": "♫", "unlock_pop": 22,
		"desc": "Raises everyone's mood. Workers train Charm and Luck.",
	},
	"workshop": {
		"name": "Workshop", "width": 2, "cost": 500, "buildable": true, "slots": 2,
		"produces": "gear", "stat": "tech", "amount": 1.0, "cycle": 600.0,
		"energy": 0.2, "color": Color(1.0, 0.6, 0.3), "icon": "⚒", "unlock_pop": 25,
		"desc": "Crafts gear from blueprints and materials, and makes scrap on its own. Needs Tech.",
	},
	"armory": {
		"name": "Armory", "width": 2, "cost": 450, "buildable": true, "slots": 2,
		"stat": "end", "energy": 0.1, "color": Color(0.9, 0.3, 0.3), "icon": "⚔",
		"unlock_pop": 28, "desc": "Everyone fights fires, floods and monsters harder. Needs Endurance.",
	},
	"aquarium": {
		"name": "Aquarium", "width": 2, "cost": 600, "buildable": true, "slots": 0,
		"mood": 8, "pearl_bonus": 0.05, "energy": 0.1, "color": Color(0.3, 0.9, 0.9), "icon": "✦",
		"unlock_pop": 30, "desc": "Beautiful fish: better mood for all and +5% pearls per level.",
	},
	"turbine": {
		"name": "Current Turbine", "width": 2, "cost": 700, "buildable": true, "slots": 0,
		"produces": "energy", "auto": 5.0, "amount": 25.0, "cycle": 30.0, "min_row": 6,
		"energy": 0.0, "color": Color(0.4, 0.8, 1.0), "icon": "✇", "unlock_pop": 35,
		"desc": "Free energy from deep currents, no workers needed. Only from row 7 down.",
	},
	"observatory": {
		"name": "Observation Deck", "width": 2, "cost": 900, "buildable": true, "slots": 0,
		"mood": 15, "xp_bonus": 0.1, "energy": 0.15, "color": Color(0.35, 0.75, 1.0), "icon": "◎",
		"unlock_pop": 40, "desc": "A view of the deep: great mood for all and +10% colonist XP per level.",
	},
}

## Ящики припасов: rolls — сколько наград, table — [вес, вид, мин, макс].
## Шансы показываются игроку в магазине (требование Apple/Google).
const CRATES := {
	"common": {"name": "Supply Crate", "rolls": 2, "color": Color(0.55, 0.75, 0.9), "table": [
		[50, "pearls", 50, 120], [20, "resources", 40, 80], [10, "crystals", 1, 2],
		[2, "colonist_rare", 1, 1], [1, "colonist_legendary", 1, 1]]},
	"silver": {"name": "Silver Crate", "rolls": 3, "color": Color(0.85, 0.9, 1.0), "table": [
		[40, "pearls", 120, 280], [20, "resources", 80, 150], [12, "crystals", 2, 4],
		[5, "colonist_rare", 1, 1], [1, "colonist_legendary", 1, 1], [3, "pet", 1, 1]]},
	"gold": {"name": "Gold Crate", "rolls": 4, "color": Color(1.0, 0.8, 0.3), "guaranteed": "colonist_rare", "table": [
		[35, "pearls", 250, 550], [20, "resources", 150, 250], [15, "crystals", 4, 8],
		[10, "colonist_rare", 1, 1], [4, "colonist_legendary", 1, 1], [8, "pet", 1, 1]]},
}

## Ежедневные награды: 7-дневный цикл, серия сбрасывается при пропуске дня.
const DAILY := [
	{"pearls": 60}, {"pearls": 100}, {"crystals": 2}, {"pearls": 180},
	{"crates": {"common": 1}}, {"crystals": 8}, {"crates": {"silver": 1}},
]

## Зоны экспедиций. danger — риск потерь здоровья, power — рекомендуемая сила экипажа
## (сумма всех характеристик). loot — [мин, макс] на каждую награду.
const ZONES := [
	{"id": "kelp", "name": "Kelp Forest", "minutes": 10, "danger": 0.1, "power": 10, "unlock_pop": 0,
		"desc": "Calm and shallow. A good first trip.",
		"loot": {"pearls": [20, 50], "resources": [15, 35]}},
	{"id": "reef", "name": "Coral Reef", "minutes": 30, "danger": 0.2, "power": 18, "unlock_pop": 0,
		"desc": "Colorful and full of pearls.",
		"loot": {"pearls": [55, 115], "resources": [30, 60]}},
	{"id": "wreck", "name": "Sunken Ship", "minutes": 60, "danger": 0.35, "power": 26, "unlock_pop": 8,
		"desc": "An old wreck. Treasure and trouble.",
		"loot": {"pearls": [110, 215], "crystals": [0, 1], "crate": "common"}},
	{"id": "vents", "name": "Hydrothermal Vents", "minutes": 120, "danger": 0.5, "power": 34, "unlock_pop": 12,
		"desc": "Scalding water, rare minerals.",
		"loot": {"pearls": [180, 330], "crystals": [0, 1], "crate": "silver"}},
	{"id": "trench", "name": "Abyssal Trench", "minutes": 240, "danger": 0.7, "power": 45, "unlock_pop": 16,
		"desc": "The deepest dark. Legends live here.",
		"loot": {"pearls": [330, 570], "crystals": [1, 3], "crate": "gold", "survivor": 0.25}},
]

## Шаблоны записей журнала экспедиции ({n} — имя члена экипажа).
## Дополнительные записи журнала для конкретных зон.
const LOG_ZONE := {
	"kelp": ["{n} got lost in the kelp for a moment, then found the way back.", "Sea otters? This deep? {n} swears they waved.",
		"{n} harvested a bundle of sweet kelp.", "A seahorse hitched a ride on the hull."],
	"reef": ["{n} found a pearl the size of a fist!", "Parrotfish crunch coral all around the sub.",
		"{n} photographed a rare blue octopus.", "A reef shark circled twice, then lost interest."],
	"wreck": ["{n} found an old captain's log. The last page is torn out.", "The wreck groans. {n} decides not to go deeper.",
		"{n} pulled a rusty chest out of the cargo hold!", "Something moved in the dark hallway. {n} didn't wait to see what."],
	"vents": ["The water here is boiling. {n} keeps the sub steady.", "Giant tube worms sway around the vents.",
		"{n} scraped rare minerals off a black smoker.", "Yeti crabs! {n} counts at least forty of them."],
	"trench": ["Total darkness. Only the glow of the lure ahead...", "{n} hears singing through the hull. Whales? Something else?",
		"A shape bigger than the colony passed under the sub.", "{n} found ruins with carvings of the trident symbol."],
}
const LOG_CALM := [
	"{n} spotted a school of glowing fish.", "The bathyscaphe hums along quietly.",
	"{n} hums an old sea shanty.", "A curious turtle follows the sub for a while.",
	"{n} sketches a strange coral formation.", "Sonar pings echo in the dark.",
]
const LOG_FIND := [
	"{n} found a pearl-filled clam!", "{n} pried open an old chest.",
	"{n} collected rare glowing minerals.", "The crew salvaged useful supplies.",
]
const LOG_DANGER := [
	"An anglerfish attacked! {n} fought it off.", "A pressure leak! {n} patched it up.",
	"{n} got tangled in kelp and scraped an arm.", "Strong currents rocked the sub. {n} bumped a head.",
]

## Существа, с которыми экипаж может подраться в каждой зоне.
const ENEMIES := {
	"kelp": ["Angry Crab", "Moray Eel", "Jellyfish Swarm"],
	"reef": ["Reef Shark", "Lionfish", "Barracuda", "Giant Crab"],
	"wreck": ["Giant Eel", "Spider Crab", "Sea Snake", "Ghost Octopus"],
	"vents": ["Lava Crab", "Bone Shark", "Vent Worm"],
	"trench": ["Anglerfish", "Giant Squid", "Abyssal Serpent"],
}
## Записи журнала с цифрами: {n} — кто, {e} — существо, {h} — урон, {x} — опыт, {v} — находка.
const LOG_FIGHT_WIN := [
	"{n} fought a {e} and won. −{h} HP, +{x} XP",
	"A {e} attacked! {n} drove it off. −{h} HP, +{x} XP",
]
const LOG_FIGHT_LOSE := [
	"A {e} ambushed the crew! {n} barely escaped. −{h} HP, +{x} XP",
	"{n} lost a fight with a {e} and had to retreat. −{h} HP, +{x} XP",
]
const LOG_LOOT := {
	"pearls": "{n} found {v} pearls.",
	"crystals": "{n} dug out {v} crystals.",
	"resources": "The crew salvaged {v} supplies.",
	"item": "{n} found gear: {v}!",
	"crate": "{n} hauled up a {v}!",
	"colonist": "{n} rescued a survivor! They will join the colony.",
}

## События с выбором в экспедиции: a — рискнуть, b — пройти мимо.
const EXP_CHOICES := [
	{"id": "chest", "text": "The crew found a sealed chest covered in barnacles. It might be trapped.", "a": "Open it", "b": "Leave it"},
	{"id": "stranger", "text": "A wounded stranger is signaling for help from a wreck.", "a": "Help them", "b": "Sail on"},
	{"id": "cave", "text": "Sonar shows a shortcut through a dark cave. Something lives there.", "a": "Take the shortcut", "b": "Go around"},
	{"id": "glow", "text": "A strange glowing coral pulses nearby. Rare minerals... or poison?", "a": "Harvest it", "b": "Don't touch"},
]

## Питомцы: одного можно взять с собой, у каждого свой бонус.
const PETS := {
	"clownfish": {"name": "Nemo the Clownfish", "art": "res://art/creatures/clownfish.png", "desc": "+10% to all collections"},
	"puffer": {"name": "Spike the Pufferfish", "art": "res://art/creatures/fish/fish_puffer.png", "desc": "+25% damage against pirates, monsters and bosses"},
	"angel": {"name": "Grace the Angelfish", "art": "res://art/creatures/fish/fish_angel2.png", "desc": "+10 mood for everyone"},
	"lion": {"name": "Leo the Lionfish", "art": "res://art/creatures/fish/fish_lion.png", "desc": "+20% expedition loot"},
	"parrot": {"name": "Polly the Parrotfish", "art": "res://art/creatures/fish/fish_parrot.png", "desc": "+15% chance for a successful rush"},
	"tang": {"name": "Sunny the Yellow Tang", "art": "res://art/creatures/fish/fish_yellow_tang.png", "desc": "Colonists heal 50% faster"},
}

## Ежедневные задания: event — что считаем, target — [мин, макс], reward.
## needs — отсек, без которого задание не выдаётся; scales — цель растёт с размером колонии.
const QUEST_POOL := [
	{"event": "collect_energy", "text": "Collect %d energy", "target": [250, 450], "scales": true, "reward": {"pearls": 60}, "xp": 40},
	{"event": "collect_oxygen", "text": "Collect %d oxygen", "target": [250, 450], "scales": true, "reward": {"pearls": 60}, "xp": 40},
	{"event": "collect_food", "text": "Collect %d food", "target": [250, 450], "scales": true, "reward": {"pearls": 60}, "xp": 40},
	{"event": "collect_pearls", "text": "Harvest %d pearls from pearl farms", "target": [150, 300], "scales": true, "needs": "pearl", "reward": {"crystals": 2}, "xp": 60},
	{"event": "collect_science", "text": "Produce %d science", "target": [60, 120], "scales": true, "needs": "lab", "reward": {"pearls": 120}, "xp": 60},
	{"event": "build", "text": "Build %d rooms", "target": [2, 3], "reward": {"crystals": 2}, "xp": 60},
	{"event": "upgrade", "text": "Upgrade %d rooms", "target": [2, 3], "reward": {"crystals": 2}, "xp": 60},
	{"event": "expedition", "text": "Send %d expeditions", "target": [2, 3], "needs": "dock", "reward": {"crystals": 2}, "xp": 80},
	{"event": "expedition_done", "text": "Bring %d expeditions home", "target": [2, 3], "needs": "dock", "reward": {"pearls": 150}, "xp": 80},
	{"event": "expedition_reef", "text": "Explore the Coral Reef %d times", "target": [1, 2], "needs": "dock", "reward": {"crystals": 3}, "xp": 90},
	{"event": "incident_resolved", "text": "Handle %d incidents", "target": [2, 4], "reward": {"crystals": 2}, "xp": 70},
	{"event": "rush", "text": "Rush rooms %d times", "target": [4, 8], "reward": {"pearls": 80}, "xp": 40},
	{"event": "bubble", "text": "Pop %d treasure bubbles", "target": [4, 8], "reward": {"pearls": 80}, "xp": 40},
	{"event": "trade", "text": "Make %d deals with the trader", "target": [1, 2], "reward": {"crystals": 2}, "xp": 60},
	{"event": "level_up", "text": "Level up colonists %d times", "target": [3, 6], "reward": {"crystals": 2}, "xp": 60},
	{"event": "research", "text": "Finish %d research projects", "target": [1, 1], "needs": "lab", "reward": {"crystals": 3}, "xp": 80},
	{"event": "craft", "text": "Craft %d pieces of gear", "target": [1, 2], "needs": "workshop", "reward": {"crystals": 4}, "xp": 90},
	{"event": "crate", "text": "Open %d crates", "target": [1, 2], "reward": {"pearls": 100}, "xp": 50},
]
const QUESTS_PER_DAY := 4

## Сезонный пропуск: уровень каждые SEASON_XP_PER_TIER очков.
const SEASON_DAYS := 30
const SEASON_XP_PER_TIER := 100
const SEASON_TIERS := [
	{"free": {"pearls": 200}, "premium": {"crystals": 30}},
	{"free": {"crystals": 5}, "premium": {"crates": {"silver": 1}}},
	{"free": {"pearls": 300}, "premium": {"pearls": 1000}},
	{"free": {"crates": {"common": 1}}, "premium": {"crystals": 50}},
	{"free": {"pearls": 400}, "premium": {"colonist": "rare"}},
	{"free": {"crystals": 10}, "premium": {"crates": {"gold": 1}}},
	{"free": {"pearls": 500}, "premium": {"crystals": 80}},
	{"free": {"crates": {"silver": 1}}, "premium": {"pearls": 2500}},
	{"free": {"crystals": 15}, "premium": {"crates": {"gold": 1}}},
	{"free": {"crates": {"gold": 1}}, "premium": {"colonist": "legendary"}},
]

## Режимы сложности.
const DIFFICULTY := {
	"calm": {"name": "Calm", "desc": "Fewer and weaker incidents, slower resource use, no harm from hunger. Just build and relax.",
		"incidents": 2.0, "damage": 0.5, "consume": 0.7, "hunger": false, "permadeath": false, "crystal_rush": true, "reward": 1.0,
		"death": false, "revive_window": 0.0, "revive_mult": 1.0,
		"color": Color(0.5, 0.95, 0.6)},
	"normal": {"name": "Normal", "desc": "The intended experience. Fallen colonists can be revived for pearls within 2 hours.",
		"incidents": 1.0, "damage": 1.0, "consume": 1.0, "hunger": true, "permadeath": false, "crystal_rush": true, "reward": 1.0,
		"death": true, "revive_window": 7200.0, "revive_mult": 1.0,
		"color": Color(0.45, 0.85, 1.0)},
	"survival": {"name": "Survival", "desc": "More and stronger incidents, faster resource use. The fallen can be revived only within 30 minutes and for double the price. No crystal speed-ups. +50% rewards.",
		"incidents": 0.6, "damage": 1.5, "consume": 1.3, "hunger": true, "permadeath": true, "crystal_rush": false, "reward": 1.5,
		"death": true, "revive_window": 1800.0, "revive_mult": 2.0,
		"color": Color(1.0, 0.4, 0.35)},
}

## Зоны глубины. Каждые 5 рядов — новая зона: больше добычи, но и больше бед.
const DEPTH_ZONES := [
	{"name": "Twilight Shelf", "from": 0, "bonus": 0.0, "crystal_chance": 0.0, "danger": 1.0, "research": "",
		"color": Color(0.3, 0.7, 0.9)},
	{"name": "Midnight Zone", "from": 5, "bonus": 0.3, "crystal_chance": 0.02, "danger": 1.5, "research": "deep_drilling",
		"color": Color(0.5, 0.4, 1.0)},
	{"name": "The Abyss", "from": 10, "bonus": 0.7, "crystal_chance": 0.05, "danger": 2.2, "research": "abyssal_engineering",
		"color": Color(1.0, 0.35, 0.5)},
]

## Дерево исследований. cost — наука, minutes — время, req — что нужно изучить раньше.
const RESEARCH := [
	{"id": "efficient_reactors", "tier": 1, "name": "Efficient Reactors", "desc": "+20% energy from reactors.", "cost": 40, "minutes": 10, "req": []},
	{"id": "hydroponics", "tier": 1, "name": "Hydroponics", "desc": "+20% food from farms.", "cost": 40, "minutes": 10, "req": []},
	{"id": "electrolysis", "tier": 1, "name": "Better Electrolysis", "desc": "+20% oxygen from generators.", "cost": 40, "minutes": 10, "req": []},
	{"id": "reinforced_hull", "tier": 1, "name": "Reinforced Hull", "desc": "Incidents happen 30% less often.", "cost": 60, "minutes": 15, "req": []},
	{"id": "training_programs", "tier": 2, "name": "Training Programs", "desc": "Colonists gain XP 50% faster.", "cost": 90, "minutes": 30, "req": ["hydroponics"]},
	{"id": "sonar_mapping", "tier": 2, "name": "Sonar Mapping", "desc": "Expeditions bring 25% more loot.", "cost": 100, "minutes": 30, "req": ["electrolysis"]},
	{"id": "fire_suppression", "tier": 2, "name": "Fire Suppression", "desc": "Incidents are handled twice as fast.", "cost": 100, "minutes": 30, "req": ["reinforced_hull"]},
	{"id": "deep_drilling", "tier": 2, "name": "Deep Drilling", "desc": "Build in the Midnight Zone (rows 6-10).", "cost": 150, "minutes": 60, "req": ["efficient_reactors", "reinforced_hull"]},
	{"id": "auto_collectors", "tier": 3, "name": "Auto-Collectors", "desc": "While you play, energy, oxygen and food rooms collect half their output by themselves.", "cost": 250, "minutes": 120, "req": ["efficient_reactors", "hydroponics", "electrolysis"]},
	{"id": "medical_ai", "tier": 3, "name": "Medical AI", "desc": "Colonists heal 3 times faster.", "cost": 200, "minutes": 90, "req": ["training_programs"]},
	{"id": "bathyscaphe_engines", "tier": 3, "name": "Turbo Engines", "desc": "Expeditions are 30% shorter.", "cost": 220, "minutes": 90, "req": ["sonar_mapping"]},
	{"id": "storage_compression", "tier": 3, "name": "Compressed Storage", "desc": "+50% storage for all resources.", "cost": 200, "minutes": 90, "req": ["deep_drilling"]},
	{"id": "pearl_cultivation", "tier": 3, "name": "Pearl Cultivation", "desc": "+40% pearls from pearl farms.", "cost": 220, "minutes": 120, "req": ["hydroponics"]},
	{"id": "trader_beacon", "tier": 3, "name": "Trader Beacon", "desc": "Wandering traders visit twice as often.", "cost": 180, "minutes": 60, "req": ["sonar_mapping"]},
	{"id": "abyssal_engineering", "tier": 4, "name": "Abyssal Engineering", "desc": "Build in The Abyss (rows 11-14).", "cost": 400, "minutes": 240, "req": ["deep_drilling", "fire_suppression"]},
	{"id": "legendary_signal", "tier": 4, "name": "Legendary Signal", "desc": "10% of new arrivals are Rare colonists.", "cost": 350, "minutes": 180, "req": ["training_programs", "sonar_mapping"]},
	{"id": "fusion_core", "tier": 4, "name": "Fusion Core", "desc": "All rooms use 40% less energy.", "cost": 450, "minutes": 300, "req": ["auto_collectors", "storage_compression"]},
]

## Снаряжение: база предмета. stats — какие навыки усиливает.
const ITEMS := [
	{"id": "wrench", "kind": "tool", "name": "Wrench", "stats": ["str"]},
	{"id": "harpoon", "kind": "tool", "name": "Harpoon", "stats": ["str"]},
	{"id": "torch", "kind": "tool", "name": "Welding Torch", "stats": ["tech"]},
	{"id": "scanner", "kind": "tool", "name": "Bio Scanner", "stats": ["bio"]},
	{"id": "coral_knife", "kind": "tool", "name": "Coral Knife", "stats": ["bio"]},
	{"id": "reactor_suit", "kind": "suit", "name": "Reactor Suit", "stats": ["str"]},
	{"id": "engineer_suit", "kind": "suit", "name": "Engineer Suit", "stats": ["tech"]},
	{"id": "medic_suit", "kind": "suit", "name": "Medic Suit", "stats": ["bio"]},
	{"id": "explorer_suit", "kind": "suit", "name": "Explorer Suit", "stats": ["str", "tech", "bio"]},
	{"id": "diving_armor", "kind": "armor", "name": "Diving Armor", "stats": []},
	{"id": "shark_mesh", "kind": "armor", "name": "Shark Mesh", "stats": []},
	{"id": "heat_plate", "kind": "armor", "name": "Heat Shield Plate", "stats": []},
	## броня: prot — добавка к защите сверх редкости
	{"id": "kelp_vest", "kind": "armor", "name": "Kelp Vest", "stats": [], "prot": 0.0},
	{"id": "coral_plate", "kind": "armor", "name": "Coral Plate", "stats": [], "prot": 0.05},
	{"id": "titan_suit", "kind": "armor", "name": "Titan Suit", "stats": [], "prot": 0.1},
	{"id": "abyss_armor", "kind": "armor", "name": "Abyss Armor", "stats": [], "prot": 0.15},
	## оружие: atk — сила в бою с пиратами, чудовищами и боссами; anim — как бьёт
	{"id": "spear", "kind": "weapon", "name": "Bone Spear", "stats": [], "atk": 2, "anim": "melee"},
	{"id": "harpoon_gun", "kind": "weapon", "name": "Harpoon Gun", "stats": [], "atk": 3, "anim": "harpoon"},
	{"id": "shock_baton", "kind": "weapon", "name": "Shock Baton", "stats": [], "atk": 3, "anim": "shock"},
	{"id": "trident", "kind": "weapon", "name": "Trident", "stats": [], "atk": 4, "anim": "melee"},
	{"id": "plasma_cutter", "kind": "weapon", "name": "Plasma Cutter", "stats": [], "atk": 5, "anim": "torch"},
	{"id": "sonic_blaster", "kind": "weapon", "name": "Sonic Blaster", "stats": [], "atk": 5, "anim": "sonic"},
]
## Материалы для крафта: находят в исследованиях и заданиях, снимают с пиратов,
## мастерская сама понемногу делает металлолом.
const MATERIALS := {
	"scrap": {"name": "Scrap Metal", "color": Color(0.72, 0.74, 0.8)},
	"kelp_fiber": {"name": "Kelp Fiber", "color": Color(0.45, 0.85, 0.4)},
	"shell": {"name": "Pearl Shell", "color": Color(1.0, 0.82, 0.9)},
	"coral": {"name": "Coral Branch", "color": Color(1.0, 0.5, 0.45)},
	"copper": {"name": "Copper Wire", "color": Color(0.95, 0.6, 0.3)},
	"vent_crystal": {"name": "Vent Crystal", "color": Color(0.4, 0.9, 1.0)},
	"kraken_ink": {"name": "Kraken Ink", "color": Color(0.6, 0.35, 0.9)},
	"abyss_pearl": {"name": "Abyss Pearl", "color": Color(0.95, 0.95, 1.0)},
}
## Что встречается в каждой зоне (первое — чаще всего).
const ZONE_MATERIALS := {
	"kelp": ["kelp_fiber", "shell", "scrap"],
	"reef": ["coral", "shell", "kelp_fiber"],
	"wreck": ["scrap", "copper", "coral"],
	"vents": ["vent_crystal", "copper", "scrap"],
	"trench": ["kraken_ink", "vent_crystal", "abyss_pearl"],
}
## Главный материал каждой вещи (кроме металлолома).
const ITEM_MATERIAL := {
	"wrench": "scrap", "harpoon": "copper", "torch": "vent_crystal", "scanner": "copper", "coral_knife": "coral",
	"reactor_suit": "kelp_fiber", "engineer_suit": "copper", "medic_suit": "shell", "explorer_suit": "kelp_fiber",
	"diving_armor": "scrap", "shark_mesh": "copper", "heat_plate": "vent_crystal", "kelp_vest": "kelp_fiber",
	"coral_plate": "coral", "titan_suit": "copper", "abyss_armor": "kraken_ink",
	"spear": "shell", "harpoon_gun": "copper", "shock_baton": "vent_crystal", "trident": "coral",
	"plasma_cutter": "vent_crystal", "sonic_blaster": "kraken_ink",
}
## Черты характера: у колониста 0–2, дети наследуют. good — положительная.
const TRAITS := {
	"brave": {"name": "Brave", "desc": "Takes less damage in fights.", "good": true, "color": Color(1.0, 0.45, 0.35)},
	"tough": {"name": "Tough", "desc": "Takes less damage and heals faster.", "good": true, "color": Color(0.95, 0.7, 0.4)},
	"lucky": {"name": "Lucky", "desc": "+3 Luck.", "good": true, "color": Color(0.5, 1.0, 0.5)},
	"genius": {"name": "Genius", "desc": "Gains experience 30% faster.", "good": true, "color": Color(0.6, 0.8, 1.0)},
	"cheerful": {"name": "Cheerful", "desc": "Better mood for themselves and everyone in the same room.", "good": true, "color": Color(1.0, 0.85, 0.3)},
	"night_owl": {"name": "Night Owl", "desc": "Heals twice as fast while you are away.", "good": true, "color": Color(0.7, 0.6, 1.0)},
	"lazy": {"name": "Lazy", "desc": "Works 25% slower, but never gets sad.", "good": false, "color": Color(0.7, 0.7, 0.75)},
	"clumsy": {"name": "Clumsy", "desc": "Worse at fighting fires, floods and monsters.", "good": false, "color": Color(0.85, 0.6, 0.5)},
}

## Проекты колонии: большие стройки поздней игры, по 3 этапа. Каждый этап — постоянный бонус.
const PROJECTS := [
	{"id": "garden_dome", "name": "Garden Dome", "desc": "A glass garden on the sea floor. Each stage: +10% food and +5 mood for everyone.",
		"level": 6, "pearls": 3000, "materials": {"kelp_fiber": 10, "coral": 6}, "color": Color(0.45, 0.95, 0.5)},
	{"id": "survivor_beacon", "name": "Survivor Beacon", "desc": "A beacon tower that guides survivors home. Each stage: the Radio Room brings people 25% faster.",
		"level": 9, "pearls": 5000, "materials": {"copper": 12, "vent_crystal": 6}, "color": Color(1.0, 0.85, 0.4)},
	{"id": "deep_bathyscaphe", "name": "Deep Bathyscaphe", "desc": "A heavy armored sub. Each stage: +10% expedition loot and a 15% shorter way home.",
		"level": 12, "pearls": 8000, "materials": {"scrap": 30, "copper": 15, "kraken_ink": 4}, "color": Color(0.5, 0.8, 1.0)},
	{"id": "pearl_monument", "name": "Pearl Monument", "desc": "A monument to the colony. Each stage: +5% pearls and +10% colony experience.",
		"level": 15, "pearls": 12000, "materials": {"shell": 20, "abyss_pearl": 2}, "color": Color(1.0, 0.75, 0.95)},
]
## Цепочки заданий: небольшие истории из 3 шагов, у каждого шага награда.
const CHAINS := [
	{"id": "lost_diver", "name": "The Lost Diver", "steps": [
		{"goal": ["expedition_reef", 1], "reward": {"pearls": 300}},
		{"goal": ["expedition_wreck", 1], "reward": {"materials": {"copper": 4}}},
		{"goal": ["expedition_done", 8], "reward": {"blueprint": "harpoon_gun:rare"}}]},
	{"id": "engineer", "name": "Engineer's Notebook", "steps": [
		{"goal": ["craft", 2], "reward": {"materials": {"scrap": 10}}},
		{"goal": ["blueprint", 2], "reward": {"materials": {"copper": 6, "vent_crystal": 2}}},
		{"goal": ["craft", 6], "reward": {"blueprint": "plasma_cutter:rare"}}]},
	{"id": "night_watch", "name": "Night Watch", "steps": [
		{"goal": ["incident_resolved", 6], "reward": {"pearls": 400}},
		{"goal": ["raid_won", 2], "reward": {"crates": {"silver": 1}}},
		{"goal": ["boss_won", 1], "reward": {"crates": {"gold": 1}}}]},
	{"id": "new_blood", "name": "New Blood", "steps": [
		{"goal": ["birth", 1], "reward": {"pearls": 500}},
		{"goal": ["stranger", 3], "reward": {"crystals": 8}},
		{"goal": ["project", 1], "reward": {"crystals": 15}}]},
]

const PROJECT_STAGES := 3
const PROJECT_STAGE_MULT := [1.0, 2.5, 6.0]

const RARITIES := ["common", "rare", "legendary"]
const CRAFT_PEARLS := [300, 1200, 4000]
const CRAFT_MINUTES := [20, 60, 240]
## Чертежи, известные с начала игры.
const START_BLUEPRINTS := ["spear:common", "kelp_vest:common", "wrench:common", "reactor_suit:common"]

## Рецепт: «вещь:редкость» → материалы.
static func recipe(key: String) -> Dictionary:
	var parts := key.split(":")
	var base: String = parts[0]
	var r: int = RARITIES.find(parts[1])
	var mats := {}
	var main: String = ITEM_MATERIAL.get(base, "scrap")
	mats["scrap"] = [2, 4, 6][r]
	mats[main] = int(mats.get(main, 0)) + [2, 4, 6][r]
	if r >= 1:
		var extra := "coral" if main == "copper" else "copper"
		mats[extra] = int(mats.get(extra, 0)) + 2
	if r >= 2:
		mats["abyss_pearl"] = int(mats.get("abyss_pearl", 0)) + 1
		mats["kraken_ink"] = int(mats.get("kraken_ink", 0)) + 2
	return mats

static func item_def(id: String) -> Dictionary:
	for b in ITEMS:
		if b.id == id:
			return b
	return {}

const ITEM_RARITY := {
	"common": {"name": "Common", "bonus": 1, "color": Color(0.8, 0.85, 0.9)},
	"rare": {"name": "Rare", "bonus": 2, "color": Color(0.4, 0.75, 1.0)},
	"legendary": {"name": "Legendary", "bonus": 4, "color": Color(1.0, 0.75, 0.25)},
}

## Сюжет: сообщения командира по рации. goal — [событие, сколько].
const STORY := [
	{"title": "Welcome, Overseer", "text": "Commander Reyes here. The surface is gone, and this colony is all we have. Collect what the reactor made to get started.", "goal": ["collect_energy", 10], "reward": {"pearls": 100}},
	{"title": "A Place to Sleep", "text": "More survivors are coming. Build Living Quarters so they have somewhere to rest.", "goal": ["build_living", 1], "reward": {"pearls": 150}},
	{"title": "Everyone Works", "text": "Idle hands won't keep us breathing. Drag a colonist into a room with free slots.", "goal": ["assign", 1], "reward": {"pearls": 100}},
	{"title": "Pearls of the Deep", "text": "Pearls are what we trade and build with down here. Build a Pearl Farm and put someone to work in it.", "goal": ["build_pearl", 1], "reward": {"pearls": 150}, "unlocks": ["pearl"]},
	{"title": "Make It Better", "text": "Every room can be improved: more output, more work slots. Upgrade any room once.", "goal": ["upgrade", 1], "reward": {"pearls": 150}},
	{"title": "Growing Colony", "text": "The beacon is working. Reach 8 colonists.", "goal": ["population", 8], "reward": {"crystals": 3}, "unlocks": ["storage"]},
	{"title": "Into the Blue", "text": "Build a Sub Dock and send our first crew out. Who knows what's out there.", "goal": ["expedition", 1], "reward": {"crates": {"common": 1}}, "unlocks": ["dock"]},
	{"title": "Calling Survivors", "text": "Only a few will find us on their own. Build a Radio Room: its broadcast is how new survivors will reach the colony.", "goal": ["build_radio", 1], "reward": {"crates": {"common": 1}}, "unlocks": ["radio"]},
	{"title": "Knowledge Is Power", "text": "We need science. Build a Research Lab and finish any research.", "goal": ["research", 1], "reward": {"crystals": 3}, "unlocks": ["lab"]},
	{"title": "Trouble Below", "text": "Fires, floods, things with teeth... Handle 3 incidents and keep everyone alive.", "goal": ["incident_resolved", 3], "reward": {"pearls": 400}, "unlocks": ["medbay"]},
	{"title": "A Real Home", "text": "Merge rooms: build a room right next to one of the same type and level. Reach 15 colonists.", "goal": ["population", 15], "reward": {"crystals": 7}},
	{"title": "The Wreck", "text": "Sonar found an old ship. Send an expedition to the Sunken Ship.", "goal": ["expedition_wreck", 1], "reward": {"crates": {"silver": 1}}, "unlocks": ["gym", "school"]},
	{"title": "Deeper", "text": "Our scans show warm vents in the Midnight Zone. Research Deep Drilling and build a room below row 5.", "goal": ["depth", 6], "reward": {"crystals": 6}},
	{"title": "Hot Meals", "text": "Morale is low. Build a Kitchen so the colony eats like people again.", "goal": ["build_kitchen", 1], "reward": {"pearls": 500}, "unlocks": ["kitchen"]},
	{"title": "Stronger Together", "text": "Train our people. Level up colonists 25 times.", "goal": ["level_up", 25], "reward": {"crystals": 7}, "unlocks": ["lounge"]},
	{"title": "Steel and Sparks", "text": "We need better gear. Build a Workshop and craft 3 pieces.", "goal": ["craft", 3], "reward": {"crates": {"silver": 1}}, "unlocks": ["workshop"]},
	{"title": "Hold the Line", "text": "The deep is getting angrier. Handle 25 incidents.", "goal": ["incident_resolved", 25], "reward": {"crystals": 10}, "unlocks": ["armory"]},
	{"title": "Call Them Home", "text": "Turn the radio up and fill the halls. Reach 30 colonists.", "goal": ["population", 30], "reward": {"crates": {"gold": 1}}, "unlocks": ["aquarium"]},
	{"title": "Signal from the Abyss", "text": "Something is calling from the deep. Reach The Abyss (row 11).", "goal": ["depth", 11], "reward": {"crates": {"gold": 1}}},
	{"title": "Legend of the Trench", "text": "Send a crew to the Abyssal Trench. Bring back whatever sings down there.", "goal": ["expedition_trench", 1], "reward": {"crystals": 15, "colonist": "legendary"}, "unlocks": ["observatory"]},
	{"title": "Seasoned Explorers", "text": "Bring 20 expeditions home safely.", "goal": ["expedition_done", 20], "reward": {"crystals": 15}},
	{"title": "Power from the Deep", "text": "Build a Current Turbine down in the dark.", "goal": ["build_turbine", 1], "reward": {"pearls": 1500}, "unlocks": ["turbine"]},
	{"title": "A City Under the Sea", "text": "Reach 45 colonists. Commander Reyes would be proud.", "goal": ["population", 45], "reward": {"crystals": 25, "colonist": "legendary"}},
]

## Достижения: stat — счётчик в Game.stats, tiers — пороги.
const ACHIEVEMENTS := [
	{"id": "pop", "name": "Colony Founder", "desc": "Reach %d colonists", "stat": "population", "tiers": [10, 20, 35], "reward": [2, 5, 9]},
	{"id": "builder", "name": "Master Builder", "desc": "Build %d rooms", "stat": "build", "tiers": [5, 15, 30], "reward": [2, 4, 7]},
	{"id": "collector", "name": "Harvester", "desc": "Collect from rooms %d times", "stat": "collect", "tiers": [100, 600, 2000], "reward": [2, 5, 9]},
	{"id": "explorer", "name": "Explorer", "desc": "Complete %d expeditions", "stat": "expedition_done", "tiers": [3, 15, 50], "reward": [2, 6, 12]},
	{"id": "firefighter", "name": "First Responder", "desc": "Handle %d incidents", "stat": "incident_resolved", "tiers": [5, 25, 75], "reward": [2, 5, 9]},
	{"id": "scientist", "name": "Scientist", "desc": "Finish %d research projects", "stat": "research", "tiers": [3, 8, 17], "reward": [2, 6, 12]},
	{"id": "deep", "name": "Deep Diver", "desc": "Build on row %d", "stat": "depth", "tiers": [5, 10, 14], "reward": [2, 6, 12]},
	{"id": "looter", "name": "Treasure Hunter", "desc": "Open %d crates", "stat": "crate", "tiers": [5, 20, 60], "reward": [2, 5, 9]},
	{"id": "trainer", "name": "Coach", "desc": "Level up colonists %d times", "stat": "level_up", "tiers": [10, 50, 150], "reward": [2, 5, 9]},
	{"id": "survivor", "name": "True Survivor", "desc": "Reach %d colonists in Survival", "stat": "survival_pop", "tiers": [10, 20, 35], "reward": [4, 9, 18]},
	{"id": "bubbles", "name": "Bubble Popper", "desc": "Pop %d treasure bubbles", "stat": "bubble", "tiers": [10, 50, 200], "reward": [2, 4, 7]},
]

## Еженедельные события: модификатор + цель с 3 наградами.
const WEEKLY := [
	{"name": "Pearl Week", "desc": "Pearl farms produce +50%. Collect pearls from rooms!", "mod": "pearl_week", "goal": "collect_pearls", "tiers": [300, 1200, 3000]},
	{"name": "Abyssal Tide", "desc": "Creatures attack more often, but handling incidents gives double pearls.", "mod": "tide", "goal": "incident_resolved", "tiers": [5, 15, 30]},
	{"name": "Harvest Festival", "desc": "Farms produce +50%. Collect food!", "mod": "harvest", "goal": "collect_food", "tiers": [500, 2000, 5000]},
	{"name": "Explorer's Season", "desc": "Expeditions bring +50% loot. Send expeditions!", "mod": "explorers", "goal": "expedition", "tiers": [3, 8, 15]},
]
const WEEKLY_REWARDS := [{"crystals": 8}, {"crates": {"silver": 1}}, {"crystals": 20, "crates": {"gold": 1}}]

const FIRST_NAMES := [
	"Ava", "Ben", "Cora", "Dan", "Ella", "Finn", "Gina", "Hugo", "Iris", "Jack",
	"Kira", "Leo", "Maya", "Nate", "Olive", "Paul", "Quinn", "Rosa", "Sam", "Tess",
	"Uma", "Vic", "Wade", "Yara", "Zoe", "Max", "Nina", "Owen", "Lily", "Theo",
]
const LAST_NAMES := [
	"Wave", "Deep", "Reef", "Storm", "Marin", "Coral", "Tide", "Keel", "Drift",
	"Abyss", "Ray", "Pearl", "Surf", "Anchor", "Shell", "Kelp", "Brine", "Fathom",
]

## Глава сюжета, которая открывает отсек; -1 — открыт с самого начала.
static func unlock_chapter(type: String) -> int:
	for i in STORY.size():
		if type in STORY[i].get("unlocks", []):
			return i
	return -1

static func room_width(type: String) -> int:
	return ROOMS[type]["width"]

static func room_slots(type: String, level: int) -> int:
	var base: int = ROOMS[type].get("slots", 0)
	if base == 0:
		return 0
	return base + level - 1

static func upgrade_cost(type: String, level: int) -> int:
	return int(ROOMS[type]["cost"] * UPGRADE_MULT[clampi(level - 1, 0, UPGRADE_MULT.size() - 1)])
