extends Node
## Симуляция потока рам. Пишет события в «состояние завода» (state.gd) — ровно те, что потом будут
## приходить от камер и датчиков. Времена операций УСЛОВНЫЕ: их надо заменить настоящими (панель «Параметры»).

signal metrics_changed

var state: Node
var nodes := {}          # id -> узел
var order: Array = []    # порядок для панели
var routes := {}         # "a>b" -> PackedVector2Array (метры двойника)
var transit: Array = []  # {id, to, end, from, path, t0}
var clock := 0.0         # сек модели
var speed := 60.0        # сек модели за 1 сек экрана
var running := true
var next_release := 0.0
var seq := 0
var released := {}       # id -> время запуска
var lead_sum := 0.0
var lead_n := 0
var done_total := 0
var done_log: Array = [] # времена выхода из сборки
var p := {"plan": 10.0, "shift_h": 8.0, "v_kara": 1.5, "handle_s": 120.0}
var rng := RandomNumberGenerator.new()

const DEFAULTS := {
	# posts — постов, cycle — минут на одну раму на посту (условно!)
	"cut": {"posts": 1, "cycle": 25.0},
	"weld": {"posts": 3, "cycle": 90.0},
	"sand": {"posts": 1, "cycle": 30.0},
	"paint": {"posts": 1, "cycle": 35.0},
	"asm1": {"posts": 2, "cycle": 150.0},
	"asm2": {"posts": 2, "cycle": 150.0},
}

func setup(st: Node, data: Dictionary) -> void:
	state = st
	rng.seed = 156944872
	nodes.clear()
	order.clear()
	for n in data.stations:
		var d: Dictionary = n
		var node := {"id": d.id, "name": d.name, "num": d.get("num", ""), "kind": d.kind,
			"pos": Vector2(d.pos[0], d.pos[1]), "posts": 1, "cycle": 30.0, "feed": d.get("feed", ""),
			"next": d.get("next", ""), "queue": [], "busy": [], "reserved": 0, "busy_s": 0.0, "done": 0}
		if DEFAULTS.has(d.id):
			node.posts = DEFAULTS[d.id].posts
			node.cycle = DEFAULTS[d.id].cycle
		nodes[d.id] = node
		order.append(d.id)
	routes.clear()
	for k in data.routes:
		var pts := PackedVector2Array()
		for q in data.routes[k]:
			pts.append(Vector2(q[0], q[1]))
		routes[k] = pts

func reset() -> void:
	clock = 0.0
	next_release = 0.0
	seq = 0
	transit.clear()
	released.clear()
	lead_sum = 0.0
	lead_n = 0
	done_total = 0
	done_log.clear()
	rng.seed = 156944872
	for id in nodes:
		var n: Dictionary = nodes[id]
		n.queue = []
		n.busy = []
		n.reserved = 0
		n.busy_s = 0.0
		n.done = 0
	state.reset()

## Путь между узлами: точки маршрута плюс сами узлы (позиции берутся живыми — планировщик их двигает).
func path(a: String, b: String) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.append(nodes[a].pos)
	var k := a + ">" + b
	if routes.has(k):
		out.append_array(routes[k])
	out.append(nodes[b].pos)
	return out

func path_len(a: String, b: String) -> float:
	var pts := path(a, b)
	var L := 0.0
	for i in pts.size() - 1:
		L += pts[i].distance_to(pts[i + 1])
	return L

func transit_s(a: String, b: String) -> float:
	return path_len(a, b) / float(p.v_kara) + float(p.handle_s)

func _ev(ty: String, extra: Dictionary) -> void:
	var e := {"t": clock, "src": "sim", "type": ty}
	e.merge(extra)
	state.push(e)

func _process(dt: float) -> void:
	if state == null:
		return
	if state.source == "live":
		# живой поток: время идёт по часам, загрузка постов копится по событиям
		clock += dt
		for nid in order:
			var n: Dictionary = nodes[nid]
			n.busy_s = float(n.busy_s) + dt * n.busy.size()
		return
	if not running:
		return
	advance(dt * speed)

## Прогнать модель вперёд на sec секунд (шаг 10 с).
func advance(sec: float) -> void:
	var target := clock + sec
	while clock < target:
		var step := minf(10.0, target - clock)
		clock += step
		_tick(step)

## Переключение источника: при живом потоке очереди и посты наполняются событиями с завода.
func on_source(src: String) -> void:
	reset()
	if src == "live":
		running = false

## События живого потока двигают те же узлы, что и симуляция, поэтому слой «живой завод» рисует их так же.
func apply_event(ev: Dictionary) -> void:
	if state.source != "live":
		return
	var ty := String(ev.get("type", ""))
	var id := String(ev.get("id", ""))
	var z := String(ev.get("zone", ""))
	clock = maxf(clock, float(ev.get("t", clock)))
	match ty:
		"frame.enter":
			_drop(id)
			if nodes.has(z):
				nodes[z].queue.append(id)
				if not released.has(id) and z == order[0]:
					released[id] = clock
		"work.start":
			if nodes.has(z):
				nodes[z].queue.erase(id)
				nodes[z].busy.append({"id": id, "end": 1e15, "post": int(ev.get("post", nodes[z].busy.size())), "t0": clock})
		"work.finish":
			if nodes.has(z):
				_drop_busy(nodes[z], id)
				nodes[z].done = int(nodes[z].done) + 1
				if z.begins_with("asm"):
					done_total += 1
					done_log.append(clock)
					if released.has(id):
						lead_sum += clock - float(released[id])
						lead_n += 1
		"frame.leave":
			if nodes.has(z):
				nodes[z].queue.erase(id)
				_drop_busy(nodes[z], id)
		"frame.move":
			_drop(id)
			var a := String(ev.get("from", ""))
			var b := String(ev.get("to", ""))
			if nodes.has(a) and nodes.has(b):
				transit.append({"id": id, "from": a, "to": b, "t0": clock, "end": clock + float(ev.get("sec", 120.0)), "res": false})
		"frame.done":
			_drop(id)
			released.erase(id)

func _drop_busy(n: Dictionary, id: String) -> void:
	var keep: Array = []
	for b in n.busy:
		if String(b.id) != id:
			keep.append(b)
	n.busy = keep

func _drop(id: String) -> void:
	for nid in order:
		nodes[nid].queue.erase(id)
		_drop_busy(nodes[nid], id)
	var keep: Array = []
	for tr in transit:
		if String(tr.id) != id:
			keep.append(tr)
	transit = keep

func _tick(step: float) -> void:
	# запуск рам в резку по плану
	var interval := float(p.shift_h) * 3600.0 / maxf(float(p.plan), 0.1)
	while clock >= next_release:
		seq += 1
		var id := "Р-%03d" % seq
		released[id] = next_release
		nodes["cut"].queue.append(id)
		_ev("frame.enter", {"zone": "cut", "id": id})
		next_release += interval
	# окончание операций
	for nid in order:
		var n: Dictionary = nodes[nid]
		if n.kind != "proc":
			continue
		n.busy_s = float(n.busy_s) + step * n.busy.size()
		var still: Array = []
		for b in n.busy:
			if clock >= float(b.end):
				_finish(n, b)
			else:
				still.append(b)
		n.busy = still
	# прибытие
	var keep: Array = []
	for tr in transit:
		if clock >= float(tr.end):
			_arrive(tr)
		else:
			keep.append(tr)
	transit = keep
	# начать работу на свободных постах
	for nid in order:
		var n: Dictionary = nodes[nid]
		if n.kind != "proc":
			continue
		while n.busy.size() + int(n.reserved) < int(n.posts):
			if n.feed != "":
				var f: Dictionary = nodes[n.feed]
				if f.queue.is_empty():
					break
				var id: String = f.queue.pop_front()
				_ev("frame.leave", {"zone": f.id, "id": id})
				n.reserved = int(n.reserved) + 1
				_send(id, f.id, n.id, true)
			else:
				if n.queue.is_empty():
					break
				var id2: String = n.queue.pop_front()
				_start(n, id2)

func _start(n: Dictionary, id: String) -> void:
	# свободный пост с наименьшим номером
	var taken := {}
	for b in n.busy:
		taken[int(b.post)] = true
	var post := 0
	while taken.has(post):
		post += 1
	var dur := float(n.cycle) * 60.0 * rng.randf_range(0.85, 1.15)
	n.busy.append({"id": id, "end": clock + dur, "post": post, "t0": clock})
	_ev("work.start", {"zone": n.id, "id": id, "post": post})

func _finish(n: Dictionary, b: Dictionary) -> void:
	var id: String = b.id
	n.done = int(n.done) + 1
	_ev("work.finish", {"zone": n.id, "id": id, "post": b.post})
	_ev("frame.leave", {"zone": n.id, "id": id})
	if String(n.id).begins_with("asm"):
		done_total += 1
		done_log.append(clock)
		if released.has(id):
			lead_sum += clock - float(released[id])
			lead_n += 1
			released.erase(id)
		metrics_changed.emit()
	if n.next != "":
		_send(id, n.id, n.next, false)

func _send(id: String, a: String, b: String, reserved: bool) -> void:
	var sec := transit_s(a, b)
	transit.append({"id": id, "from": a, "to": b, "t0": clock, "end": clock + sec, "res": reserved})
	_ev("frame.move", {"id": id, "from": a, "to": b, "sec": sec})

func _arrive(tr: Dictionary) -> void:
	var n: Dictionary = nodes[tr.to]
	var id: String = tr.id
	_ev("frame.enter", {"zone": n.id, "id": id})
	if tr.res:
		n.reserved = int(n.reserved) - 1
		_start(n, id)
	elif n.kind == "sink":
		n.queue.append(id)
		_ship(n)
	else:
		n.queue.append(id)

func _ship(n: Dictionary) -> void:
	# держим на площадке отправки до 12 готовых, лишние уезжают (машина дилера)
	while n.queue.size() > 12:
		var id: String = n.queue.pop_front()
		_ev("frame.leave", {"zone": n.id, "id": id})
		_ev("frame.done", {"id": id})

## Пропускная способность по участкам: рам за смену = постов × минут смены / минут на раму.
func capacity() -> Array:
	var out: Array = []
	var shift_min := float(p.shift_h) * 60.0
	var asm_cap := 0.0
	for nid in order:
		var n: Dictionary = nodes[nid]
		if n.kind != "proc":
			continue
		var c := float(n.posts) * shift_min / maxf(float(n.cycle), 0.1)
		if String(nid).begins_with("asm"):
			asm_cap += c
			continue
		out.append({"id": nid, "name": n.name, "cap": c})
	out.append({"id": "asm", "name": "Сборка 1 и 2", "cap": asm_cap})
	return out

func bottleneck() -> Dictionary:
	var best := {}
	for c in capacity():
		if best.is_empty() or float(c.cap) < float(best.cap):
			best = c
	return best

func route_total() -> float:
	# пробег одной рамы: резка → … → отгрузка (через Сборку 2)
	var seqn := ["cut", "weld", "waitSand", "sand", "paint", "distrib", "asm2", "ship1"]
	var L := 0.0
	for i in seqn.size() - 1:
		L += path_len(seqn[i], seqn[i + 1])
	return L

func util(nid: String) -> float:
	var n: Dictionary = nodes[nid]
	if clock <= 0.0 or n.kind != "proc":
		return 0.0
	return float(n.busy_s) / (clock * maxf(float(n.posts), 1.0))

func wip() -> int:
	return released.size()

func out_per_shift() -> float:
	# по последним выходам из сборки
	var win := float(p.shift_h) * 3600.0
	var c := 0
	for t in done_log:
		if clock - float(t) <= win:
			c += 1
	return c if clock >= win else (c * win / maxf(clock, 1.0))

func lead_h() -> float:
	return (lead_sum / lead_n) / 3600.0 if lead_n > 0 else 0.0
