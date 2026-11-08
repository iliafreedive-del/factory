extends Node3D
## Планировщик: перетаскивание участков пути рамы, точек маршрута, зданий и новых предметов;
## после каждого шага пересчитываются маршруты, пробег рамы и пропускная способность.
## Варианты хранятся в браузере (user:// → IndexedDB) и скачиваются файлом JSON.

const CATALOG := [
	["stack", "Стопка рам"], ["trailer", "Прицеп"], ["cont", "Контейнер 20′"], ["rack", "Стеллаж"],
	["bench", "Верстак"], ["kara", "Кара"], ["hall", "Цех 30×12"],
]
const VFILE := "user://variants.json"

var main: Node
var active := false
var sel := {}            # {kind, id, node?}
var dragging := false
var grab := Vector2.ZERO
var undo_stack: Array = []
var props: Array = []    # {type, node}
var bshift := {}         # building id -> [dx, dz, rot_deg]
var base_state: Dictionary
var variants := {}
var ruler_on := false
var ruler_pts: Array = []
var ruler_node: MeshInstance3D
var ruler_label: Label3D
var sel_ring: MeshInstance3D
var js_cb

func setup(m: Node) -> void:
	main = m
	sel_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 2.6
	tm.outer_radius = 3.0
	sel_ring.mesh = tm
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Color(0.2, 0.9, 1.0)
	sel_ring.material_override = rm
	sel_ring.visible = false
	add_child(sel_ring)
	ruler_label = main.viz._label("", 18, Color(1, 1, 0.6))
	ruler_label.visible = false
	add_child(ruler_label)
	ruler_node = MeshInstance3D.new()
	add_child(ruler_node)
	base_state = serialize()
	_load_variants()

func set_active(on: bool) -> void:
	active = on
	main.viz.handles_root.visible = on
	sel_ring.visible = false
	sel = {}
	if not on:
		set_ruler(false)

# ---------- выбор и перетаскивание ----------
func _unhandled_input(ev: InputEvent) -> void:
	if not active:
		return
	if ev is InputEventMouse and ev.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if ev is InputEventKey and ev.pressed and not ev.echo:
		var k := ev as InputEventKey
		if k.keycode == KEY_R:
			rotate_sel(15.0)
		elif k.keycode == KEY_DELETE or k.keycode == KEY_BACKSPACE:
			delete_sel()
		elif k.keycode == KEY_Z and k.ctrl_pressed:
			undo()
		return
	var pos := Vector2.ZERO
	var pressed := false
	var released := false
	var moved := false
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		pos = ev.position
		pressed = ev.pressed
		released = not ev.pressed
	elif ev is InputEventMouseMotion and dragging:
		pos = ev.position
		moved = true
	elif ev is InputEventScreenTouch and ev.index == 0:
		pos = ev.position
		pressed = ev.pressed
		released = not ev.pressed
	elif ev is InputEventScreenDrag and dragging and ev.index == 0:
		pos = ev.position
		moved = true
	else:
		return
	var g = main.cam_rig.ground_at(pos)
	if g == null:
		return
	var p := Vector2(g.x, g.z)
	if ruler_on and pressed:
		_ruler_click(p)
		get_viewport().set_input_as_handled()
		return
	if pressed:
		var hit := _pick(p)
		if hit.is_empty():
			sel = {}
			sel_ring.visible = false
			main.ui.planner_info.text = "Ничего не выбрано"
			return
		_push_undo()
		sel = hit
		dragging = true
		main.cam_rig.blocked = true
		grab = _sel_pos() - p
		_show_sel()
		get_viewport().set_input_as_handled()
	elif moved and dragging:
		_set_sel_pos(p + grab)
		_show_sel()
		get_viewport().set_input_as_handled()
	elif released and dragging:
		dragging = false
		main.cam_rig.blocked = false
		main.after_plan_change()
		get_viewport().set_input_as_handled()

func _pick(p: Vector2) -> Dictionary:
	# 1) точки маршрута, 2) участки, 3) предметы, 4) здания
	var best := {}
	var bd := 2.2
	for h in main.viz.handles_root.get_children():
		var d := Vector2(h.position.x, h.position.z).distance_to(p)
		if d < bd:
			bd = d
			best = {"kind": "handle", "route": h.get_meta("route"), "idx": h.get_meta("idx"), "node": h}
	if not best.is_empty():
		return best
	bd = 3.5
	for id in main.sim.nodes:
		var d: float = main.sim.nodes[id].pos.distance_to(p)
		if d < bd:
			bd = d
			best = {"kind": "station", "id": id}
	if not best.is_empty():
		return best
	for pr in props:
		var n: Node3D = pr.node
		var loc: Vector3 = n.global_transform.affine_inverse() * Vector3(p.x, 0, p.y)
		var half: Vector2 = pr.half
		if absf(loc.x) <= half.x + 0.5 and absf(loc.z) <= half.y + 0.5:
			return {"kind": "prop", "prop": pr, "node": n}
	var small := 1e9
	for b in main.data.buildings:
		var d: Dictionary = b
		if not main.bnodes.has(d.id):
			continue
		var r: Array = d.r
		var sh: Array = bshift.get(d.id, [0.0, 0.0, 0.0])
		var q := p - Vector2(sh[0], sh[1])
		if q.x >= float(r[0]) and q.x <= float(r[2]) and q.y >= float(r[1]) and q.y <= float(r[3]):
			var area := (float(r[2]) - float(r[0])) * (float(r[3]) - float(r[1]))
			if area < small:
				small = area
				best = {"kind": "building", "id": d.id, "name": d.name}
	return best

func _sel_pos() -> Vector2:
	match String(sel.kind):
		"handle":
			return main.sim.routes[sel.route][sel.idx]
		"station":
			return main.sim.nodes[sel.id].pos
		"prop":
			return Vector2(sel.node.position.x, sel.node.position.z)
		"building":
			var sh: Array = bshift.get(sel.id, [0.0, 0.0, 0.0])
			return Vector2(sh[0], sh[1])
	return Vector2.ZERO

func _set_sel_pos(p: Vector2) -> void:
	match String(sel.kind):
		"handle":
			var arr: PackedVector2Array = main.sim.routes[sel.route]
			arr[sel.idx] = p
			main.sim.routes[sel.route] = arr
			sel.node.position = Vector3(p.x, 0.9, p.y)
		"station":
			main.sim.nodes[sel.id].pos = p
			main.viz.sync_markers()
		"prop":
			sel.node.position = Vector3(p.x, 0, p.y)
		"building":
			var sh: Array = bshift.get(sel.id, [0.0, 0.0, 0.0])
			bshift[sel.id] = [p.x, p.y, sh[2]]
			_apply_building(sel.id)

func _apply_building(id: String) -> void:
	var sh: Array = bshift.get(id, [0.0, 0.0, 0.0])
	var c: Vector2 = main.bcenter[id]
	var rot := deg_to_rad(float(sh[2]))
	# поворот вокруг центра здания, затем сдвиг
	var t := Transform3D(Basis(), Vector3(c.x + sh[0], 0, c.y + sh[1])) * Transform3D(Basis(Vector3.UP, rot), Vector3.ZERO) * Transform3D(Basis(), Vector3(-c.x, 0, -c.y))
	for n in main.bnodes[id]:
		(n as Node3D).transform = t

func _show_sel() -> void:
	var p := _sel_pos()
	var txt := ""
	match String(sel.kind):
		"handle":
			txt = "Точка маршрута %s" % String(sel.route).replace(">", " → ")
		"station":
			txt = "Участок: %s" % main.sim.nodes[sel.id].name
		"prop":
			txt = "Предмет: %s" % sel.prop.name
		"building":
			txt = "Здание: %s (сдвиг %.1f; %.1f м)" % [sel.name, p.x, p.y]
			var c: Vector2 = main.bcenter[sel.id]
			p = c + p
	sel_ring.position = Vector3(p.x, 0.3, p.y)
	sel_ring.visible = true
	main.ui.planner_info.text = txt

func rotate_sel(deg: float) -> void:
	if sel.is_empty():
		return
	_push_undo()
	if sel.kind == "prop":
		sel.node.rotation.y += deg_to_rad(deg)
	elif sel.kind == "building":
		var sh: Array = bshift.get(sel.id, [0.0, 0.0, 0.0])
		bshift[sel.id] = [sh[0], sh[1], float(sh[2]) + deg]
		_apply_building(sel.id)
	main.after_plan_change()

func delete_sel() -> void:
	if sel.is_empty() or sel.kind != "prop":
		return
	_push_undo()
	props.erase(sel.prop)
	sel.node.queue_free()
	sel = {}
	sel_ring.visible = false
	main.after_plan_change()

# ---------- предметы ----------
func _mat(c: Color, metal := 0.2, rough := 0.7) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	return m

func make_prop(type: String) -> Dictionary:
	var V = main.viz
	var n := Node3D.new()
	var mi := MeshInstance3D.new()
	n.add_child(mi)
	var half := Vector2(1, 1)
	var title := type
	match type:
		"stack":
			var parts: Array = []
			for i in 8:
				parts.append([Vector3(4.0, 0.12, 1.9), Vector3(0, 0.08 + i * 0.15, 0)])
			mi.mesh = V.boxes(parts)
			mi.material_override = _mat(Color(0.1, 0.1, 0.11), 0.4, 0.5)
			half = Vector2(2.0, 0.95); title = "Стопка рам"
		"trailer":
			mi.mesh = V.boxes([[Vector3(4.2, 0.35, 2.0), Vector3(0, 0.75, 0)], [Vector3(0.2, 0.6, 1.9), Vector3(0, 0.3, 0)],
				[Vector3(1.4, 0.1, 0.1), Vector3(2.7, 0.55, 0)], [Vector3(4.2, 0.4, 0.04), Vector3(0, 1.1, 1.0)], [Vector3(4.2, 0.4, 0.04), Vector3(0, 1.1, -1.0)]])
			mi.material_override = _mat(Color(0.75, 0.78, 0.8), 0.7, 0.35)
			half = Vector2(2.8, 1.0); title = "Прицеп"
		"cont":
			var bm := BoxMesh.new(); bm.size = Vector3(6.06, 2.59, 2.44)
			mi.mesh = bm; mi.position.y = 1.3
			mi.material_override = _mat(Color(0.18, 0.35, 0.6), 0.3, 0.6)
			half = Vector2(3.03, 1.22); title = "Контейнер 20′"
		"rack":
			var parts2: Array = []
			for y in [0.1, 1.0, 1.9]:
				parts2.append([Vector3(6.0, 0.08, 1.0), Vector3(0, y, 0)])
			for x in [-2.95, 0.0, 2.95]:
				for z in [-0.45, 0.45]:
					parts2.append([Vector3(0.08, 2.3, 0.08), Vector3(x, 1.15, z)])
			mi.mesh = V.boxes(parts2)
			mi.material_override = _mat(Color(0.2, 0.37, 0.66), 0.3, 0.6)
			half = Vector2(3.0, 0.5); title = "Стеллаж"
		"bench":
			mi.mesh = V.boxes([[Vector3(2.0, 0.08, 0.8), Vector3(0, 0.88, 0)], [Vector3(1.9, 0.8, 0.7), Vector3(0, 0.42, 0)]])
			mi.material_override = _mat(Color(0.35, 0.37, 0.4), 0.4, 0.6)
			half = Vector2(1.0, 0.4); title = "Верстак"
		"kara":
			mi.mesh = V.kara_mesh()
			mi.material_override = _mat(Color(0.95, 0.72, 0.12), 0.1, 0.6)
			half = Vector2(1.3, 0.6); title = "Кара"
		"hall":
			var parts3: Array = [[Vector3(30, 6, 0.15), Vector3(0, 3, 6)], [Vector3(30, 6, 0.15), Vector3(0, 3, -6)],
				[Vector3(0.15, 6, 12), Vector3(15, 3, 0)], [Vector3(0.15, 6, 12), Vector3(-15, 3, 0)], [Vector3(30.6, 0.12, 12.6), Vector3(0, 6.6, 0)]]
			mi.mesh = V.boxes(parts3)
			var m := main.Mats.get_mat("corr").duplicate() as StandardMaterial3D
			m.vertex_color_use_as_albedo = false
			m.albedo_color = Color(0.8, 0.83, 0.85)
			mi.material_override = m
			half = Vector2(15, 6); title = "Новый цех 30×12"
	return {"type": type, "node": n, "half": half, "name": title}

func add_prop(type: String, at = null, rot := 0.0) -> Dictionary:
	var pr := make_prop(type)
	add_child(pr.node)
	var p: Vector2
	if at == null:
		p = Vector2(main.cam_rig.t.tx, main.cam_rig.t.tz)
		_push_undo()
	else:
		p = at
	pr.node.position = Vector3(p.x, 0, p.y)
	pr.node.rotation.y = rot
	props.append(pr)
	if at == null:
		sel = {"kind": "prop", "prop": pr, "node": pr.node}
		_show_sel()
		main.after_plan_change()
	return pr

# ---------- линейка ----------
func set_ruler(on: bool) -> void:
	ruler_on = on
	ruler_pts.clear()
	ruler_label.visible = false
	ruler_node.mesh = null
	if on:
		main.ui.planner_info.text = "Линейка: нажмите две точки на земле"

func _ruler_click(p: Vector2) -> void:
	ruler_pts.append(p)
	if ruler_pts.size() > 2:
		ruler_pts = [p]
	if ruler_pts.size() == 2:
		var a: Vector2 = ruler_pts[0]
		var b: Vector2 = ruler_pts[1]
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(1, 1, 0.3)
		ruler_node.mesh = main.viz._ribbon(PackedVector2Array([a, b]), 0.35, 0.3)
		ruler_node.material_override = m
		var mid := (a + b) * 0.5
		ruler_label.position = Vector3(mid.x, 2.0, mid.y)
		ruler_label.text = ("%.1f м" % a.distance_to(b)).replace(".", ",")
		ruler_label.visible = true
		main.ui.planner_info.text = "Расстояние: " + ruler_label.text

# ---------- снимок состояния, отмена, варианты ----------
func serialize() -> Dictionary:
	var st := {}
	for id in main.sim.nodes:
		var p: Vector2 = main.sim.nodes[id].pos
		st[id] = [snappedf(p.x, 0.01), snappedf(p.y, 0.01)]
	var rt := {}
	for k in main.sim.routes:
		var arr: Array = []
		for q in main.sim.routes[k]:
			arr.append([snappedf(q.x, 0.01), snappedf(q.y, 0.01)])
		rt[k] = arr
	var pr: Array = []
	for p in props:
		var n: Node3D = p.node
		pr.append({"type": p.type, "x": snappedf(n.position.x, 0.01), "z": snappedf(n.position.z, 0.01), "rot": snappedf(n.rotation.y, 0.001)})
	var params := {}
	for id in main.sim.nodes:
		var n2: Dictionary = main.sim.nodes[id]
		if n2.kind == "proc":
			params[id] = [n2.posts, n2.cycle]
	return {"stations": st, "routes": rt, "buildings": bshift.duplicate(true), "props": pr, "params": params,
		"global": main.sim.p.duplicate()}

func apply_state(s: Dictionary) -> void:
	for id in s.get("stations", {}):
		if main.sim.nodes.has(id):
			var a: Array = s.stations[id]
			main.sim.nodes[id].pos = Vector2(a[0], a[1])
	for k in s.get("routes", {}):
		var arr := PackedVector2Array()
		for q in s.routes[k]:
			arr.append(Vector2(q[0], q[1]))
		main.sim.routes[k] = arr
	for id in bshift.keys():
		bshift[id] = [0.0, 0.0, 0.0]
		_apply_building(id)
	bshift = {}
	for id in s.get("buildings", {}):
		bshift[id] = s.buildings[id]
		if main.bnodes.has(id):
			_apply_building(id)
	for p in props:
		p.node.queue_free()
	props.clear()
	for p in s.get("props", []):
		add_prop(String(p.type), Vector2(p.x, p.z), float(p.rot))
	for id in s.get("params", {}):
		if main.sim.nodes.has(id):
			main.sim.nodes[id].posts = int(s.params[id][0])
			main.sim.nodes[id].cycle = float(s.params[id][1])
	if s.has("global"):
		for k in s.global:
			main.sim.p[k] = s.global[k]
	main.viz.sync_markers()
	sel = {}
	sel_ring.visible = false
	main.after_plan_change()
	main.sync_param_ui()

func _push_undo() -> void:
	undo_stack.append(serialize())
	if undo_stack.size() > 60:
		undo_stack.pop_front()

func undo() -> void:
	if undo_stack.is_empty():
		return
	apply_state(undo_stack.pop_back())

func reset_all() -> void:
	_push_undo()
	apply_state(base_state)

func _load_variants() -> void:
	if FileAccess.file_exists(VFILE):
		var v = JSON.parse_string(FileAccess.get_file_as_string(VFILE))
		if v is Dictionary:
			variants = v
	main.ui.refresh_variants(variants.keys())

func _save_file() -> void:
	var f := FileAccess.open(VFILE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(variants))
		f.close()
	main.ui.refresh_variants(variants.keys())

func save_variant(vname: String) -> void:
	if vname.strip_edges() == "":
		vname = "Вариант %d" % (variants.size() + 1)
	variants[vname] = serialize()
	_save_file()
	main.ui.planner_info.text = "Сохранено: " + vname

func _selected_name() -> String:
	var ids: PackedInt32Array = main.ui.variants_list.get_selected_items()
	if ids.is_empty():
		return ""
	return main.ui.variants_list.get_item_text(ids[0])

func load_selected() -> void:
	var n := _selected_name()
	if n != "" and variants.has(n):
		_push_undo()
		apply_state(variants[n])
		main.ui.planner_info.text = "Открыт: " + n

func delete_selected() -> void:
	var n := _selected_name()
	if n != "":
		variants.erase(n)
		_save_file()

func export_variant() -> void:
	var txt := JSON.stringify({"zavod_variant": 1, "state": serialize()}, " ")
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(txt.to_utf8_buffer(), "zavod-variant.json", "application/json")
	else:
		var f := FileAccess.open("user://zavod-variant.json", FileAccess.WRITE)
		f.store_string(txt)
		main.ui.planner_info.text = "Файл: " + ProjectSettings.globalize_path("user://zavod-variant.json")

func import_variant() -> void:
	if not OS.has_feature("web"):
		return
	js_cb = JavaScriptBridge.create_callback(_on_js_file)
	var w = JavaScriptBridge.get_interface("window")
	w.zavodImport = js_cb
	JavaScriptBridge.eval("""(function(){const i=document.createElement('input');i.type='file';i.accept='.json,application/json';
		i.onchange=e=>{const f=i.files[0];if(f)f.text().then(t=>window.zavodImport(t))};i.click()})()""")

func _on_js_file(a: Array) -> void:
	var v = JSON.parse_string(String(a[0]))
	if v is Dictionary and v.has("state"):
		_push_undo()
		apply_state(v.state)
		main.ui.planner_info.text = "Загружен вариант из файла"
