extends Node
## Уведомления на телефоне: когда игра уходит в фон, планируем напоминания
## («экспедиция вернулась», «ребёнок вырос», «отсеки готовы»…), при возврате — отменяем.
##
## Само показывание делает нативный плагин (при релизной сборке с Gradle):
## синглтон с методами show(title, text, delay_sec, id) и cancel_all().
## Без плагина (тестовые APK, редактор) план просто считается и пишется в лог.

const PLUGIN_NAMES := ["LocalNotification", "GodotLocalNotification", "NotificationScheduler"]
## Не будим игрока ночью и не спамим: не чаще одного напоминания за MIN_GAP секунд.
const MIN_GAP := 1800.0

var enabled := true
var plugin = null
var last_plan: Array = []

func _ready() -> void:
	for n in PLUGIN_NAMES:
		if Engine.has_singleton(n):
			plugin = Engine.get_singleton(n)
			break
	var cfg := ConfigFile.new()
	if cfg.load(Audio.SETTINGS_PATH) == OK:
		enabled = cfg.get_value("general", "notifications", true)

func set_enabled(on: bool) -> void:
	enabled = on
	var cfg := ConfigFile.new()
	cfg.load(Audio.SETTINGS_PATH)
	cfg.set_value("general", "notifications", on)
	cfg.save(Audio.SETTINGS_PATH)
	if not on:
		_cancel()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		schedule()
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		_cancel()

## Что и через сколько секунд напомнить. Возвращает [[секунды, заголовок, текст], …].
func plan() -> Array:
	var g = Game
	var out := []
	var tnow: float = g.now()
	for e in g.expeditions:
		var left: float = float(e.end) - tnow
		if left > 60.0:
			out.append([left, tr("The bathyscaphe is back!"), tr("Your crew returned from %s with loot.") % tr(Defs.ZONES[e.zone].name)])
	for c in g.colonists:
		if c.get("child", false):
			# дети растут и вне игры (как экспедиции) — время в c.grow
			out.append([float(c.grow), tr("All grown up!"), tr("%s is ready to work.") % c.name])
	if not g.research_current.is_empty():
		var rl: float = float(g.research_current.end) - tnow
		if rl > 60.0:
			out.append([rl, tr("Research complete"), tr(g.research_def(g.research_current.id).name)])
	# отсеки: когда будет готов самый долгий из производящих (полный сбор)
	var longest := 0.0
	for r in g.rooms:
		if Defs.ROOMS[r.type].has("produces") and not r.ready:
			var ct: float = g.cycle_time(r)
			if ct < INF:
				longest = maxf(longest, (1.0 - float(r.progress)) * ct)
	if longest > 120.0:
		out.append([longest, tr("Your colony is ready"), tr("All rooms have finished production. Come and collect!")])
	if g.free_crate_left() > 60.0:
		out.append([g.free_crate_left(), tr("Free crate"), tr("A free Supply Crate is waiting in the shop.")])
	# ежедневная награда — завтра в 10 утра по времени телефона
	var tz: int = int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var local := tnow + tz
	var next_day := (floorf(local / 86400.0) + 1.0) * 86400.0 + 10 * 3600.0
	out.append([next_day - local, tr("Daily reward"), tr("Your daily reward is ready, Overseer!")])
	# через 2 дня без игры — мягкое «скучаем»
	out.append([2 * 86400.0, tr("Commander Reyes"), tr("The colony misses you, Overseer. Things are getting rough down here!")])
	out.sort_custom(func(a, b): return a[0] < b[0])
	# прореживаем: не ближе MIN_GAP друг к другу
	var thin := []
	var last := -INF
	for n in out:
		if n[0] - last >= MIN_GAP or thin.is_empty():
			thin.append(n)
			last = n[0]
	return thin

func schedule() -> void:
	_cancel()
	if not enabled or Game.colony_lost:
		return
	last_plan = plan()
	if plugin == null:
		return
	for i in last_plan.size():
		var n: Array = last_plan[i]
		plugin.show(n[1], n[2], int(n[0]), i + 1)

func _cancel() -> void:
	if plugin and plugin.has_method("cancel_all"):
		plugin.cancel_all()
