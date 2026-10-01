extends SceneTree
## Сравнение «задание» и «исследование»: добыча в час и риск по зонам.
## godot --headless --path . --script res://tools/explore_calc.gd

func _initialize() -> void:
	print("zone        mode     hours  pearls/h  cryst/h  items/h  crates/h  deaths%  hp_left")
	for z in Defs.ZONES.size():
		for power_k in [1.0, 1.4]:
			var tot := {"h": 0.0, "p": 0.0, "c": 0.0, "i": 0.0, "k": 0.0, "d": 0, "hp": 0.0}
			var tm := {"h": 0.0, "p": 0.0, "c": 0.0, "i": 0.0, "k": 0.0, "d": 0, "hp": 0.0}
			var runs := 200
			for run in runs:
				for mode in ["mission", "explore"]:
					var g = load("res://scripts/game_state.gd").new()
					g.new_game()
					g.set_difficulty("normal")
					g.rng.seed = run * 7 + z
					var dock: Dictionary = g._add_room("dock", 3, 1)
					var crew := []
					for i in 2:
						var c: Dictionary = g.colonists[i]
						var each: float = Defs.ZONES[z].power * power_k / 2.0 / 3.0
						c.str = int(round(each)); c.tech = int(round(each)); c.bio = int(round(each))
						c.health = 100.0
						crew.append(c.id)
					var t0: float = g.now()
					var p0: int = g.pearls
					var c0: int = g.crystals
					var i0: int = g.items.size()
					var k0 := 0
					for t in g.crates: k0 += g.crates[t]
					if mode == "mission":
						g.launch_expedition(dock.id, z, crew)
					else:
						g.launch_exploration(dock.id, z, crew, true)
					var e: Dictionary = g.expedition_at(dock.id)
					var guard := 0
					while not e.is_empty() and not g.expedition_done(e) and guard < 2000:
						guard += 1
						g.clock_offset += 120.0
						g._tick_explorations()
						if not e in g.expeditions:
							e = {}
					var dead := e.is_empty()
					if not e.is_empty():
						g.claim_expedition(e)
					var k1 := 0
					for t in g.crates: k1 += g.crates[t]
					var acc: Dictionary = tm if mode == "mission" else tot
					acc.h += (g.now() - t0) / 3600.0
					acc.p += g.pearls - p0
					acc.c += g.crystals - c0
					acc.i += g.items.size() - i0
					acc.k += k1 - k0
					var hp := 0.0
					var alive := 0
					for id in crew:
						var cc: Dictionary = g.get_colonist(id)
						if cc.is_empty():
							acc.d += 1
						else:
							hp += cc.health
							alive += 1
					acc.hp += hp / maxf(1, alive)
					g.clock_offset = 0.0
					g.free()
			for pair in [["mission", tm], ["explore", tot]]:
				var a: Dictionary = pair[1]
				print("%-11s %-8s %5.1f  %8.0f  %7.2f  %7.2f  %8.2f  %6.1f  %6.0f   (power x%.1f)" % [Defs.ZONES[z].id, pair[0], a.h / runs, a.p / a.h, a.c / a.h, a.i / a.h, a.k / a.h, 100.0 * a.d / (runs * 2), a.hp / runs, power_k])
	quit()
