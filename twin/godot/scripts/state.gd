extends Node
## «Состояние завода»: единая точка, куда приходят события, и откуда их берут все слои сцены.
## Сейчас события даёт симуляция (sim.gd). Потом тот же поток пойдёт от камер, датчиков тока и 1С
## через WebSocket: адрес задаётся в ссылке ?live=wss://сервер/поток (см. twin/README.md, формат событий).
##
## Событие — словарь (одна строка JSON):
##   {"t": секунды, "src": "sim|cam|power|1c|scan", "type": "...", ...}
## Типы:
##   frame.enter  {zone, id}            рама вошла в зону (камера: «рама въехала в песко»)
##   frame.leave  {zone, id}            рама вышла из зоны
##   frame.move   {id, from, to, sec}   везут между зонами (кара, погрузчик)
##   work.start / work.finish {zone, id, post}  операция на посту
##   zone.status  {zone, status: run|idle|stop, note}
##   machine.power {zone, machine, on, amps}   датчик тока на станке (работает / простой)
##   batch.start / batch.done {zone, batch, qty}   сменное задание партией (резка, сварка)
##   vin.read     {zone, vin, cam}      VIN/шильдик прочитан на входе в сборку или на отгрузке
##   person.count {zone, n, cam}        людей в зоне по камере

signal event(ev: Dictionary)
signal source_changed(name: String)

var zones := {}        # zone -> {frames: {id: true}, status, persons, last}
var frames := {}       # id -> {zone, since}
var log_lines: Array = []
var source := "sim"    # sim | live
var ws: WebSocketPeer
var live_url := ""
var clock := 0.0       # время по событиям (сек)

func zone(z: String) -> Dictionary:
	if not zones.has(z):
		zones[z] = {"frames": {}, "status": "idle", "persons": 0, "last": 0.0, "done": 0}
	return zones[z]

func push(ev: Dictionary) -> void:
	var t := float(ev.get("t", clock))
	clock = maxf(clock, t)
	var ty := String(ev.get("type", ""))
	match ty:
		"frame.enter":
			var z := zone(String(ev.zone))
			z.frames[String(ev.id)] = true
			z.last = t
			frames[String(ev.id)] = {"zone": String(ev.zone), "since": t}
		"frame.leave":
			var z := zone(String(ev.zone))
			z.frames.erase(String(ev.id))
			z.done = int(z.done) + 1
			z.last = t
		"frame.move":
			frames[String(ev.id)] = {"zone": "", "since": t, "to": String(ev.get("to", ""))}
		"zone.status":
			zone(String(ev.zone)).status = String(ev.status)
		"person.count":
			zone(String(ev.zone)).persons = int(ev.n)
		"frame.done":
			frames.erase(String(ev.id))
	if ty != "frame.move":
		log_lines.append(ev)
		if log_lines.size() > 400:
			log_lines = log_lines.slice(200)
	event.emit(ev)

func reset() -> void:
	zones.clear()
	frames.clear()
	log_lines.clear()
	clock = 0.0

## Живой поток: WebSocket, по одному JSON-событию в сообщении (или массив событий).
func connect_live(url: String) -> void:
	live_url = url
	ws = WebSocketPeer.new()
	var err := ws.connect_to_url(url)
	if err != OK:
		push_warning("live: не подключиться к " + url)
		ws = null
		return
	source = "live"
	source_changed.emit(source)

func _process(_dt: float) -> void:
	if ws == null:
		return
	ws.poll()
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		while ws.get_available_packet_count() > 0:
			var txt := ws.get_packet().get_string_from_utf8()
			var v = JSON.parse_string(txt)
			if v is Dictionary:
				push(v)
			elif v is Array:
				for e in v:
					if e is Dictionary:
						push(e)
	elif ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
		ws = null
		source = "sim"
		source_changed.emit(source)
