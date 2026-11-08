extends Node3D
## Слой «живого завода»: участки пути рамы с цифрами, стопки рам в очередях, кары с рамами в пути,
## линии маршрутов, камеры наблюдения. Всё рисуется по «состоянию завода» — от симуляции или от живого потока.

var state: Node
var sim: Node
var data: Dictionary
var markers := {}       # node id -> {root, title: Label3D, info: Label3D, disc}
var frames_mm: MultiMeshInstance3D
var karas_mm: MultiMeshInstance3D
var routes_root: Node3D
var cams_root: Node3D
var handles_root: Node3D
var show_routes := true
var show_cams := true
var status_cache := {}
var t_label := 0.0

const C_RAW := Color(0.36, 0.27, 0.21)     # чёрная/ржавая сырая сталь до песко
const C_SAND := Color(0.55, 0.56, 0.57)    # после песко — серый металл
const C_PAINT := Color(0.07, 0.07, 0.08)   # после малярки — чёрная порошковая
const PAINTED := {"distrib": true, "asm1": true, "asm2": true, "ship1": true}

func setup(st: Node, sm: Node, d: Dictionary) -> void:
	state = st
	sim = sm
	data = d
	_build_frames()
	_build_markers()
	routes_root = Node3D.new()
	routes_root.name = "Маршруты"
	add_child(routes_root)
	handles_root = Node3D.new()
	handles_root.name = "Точки маршрута"
	handles_root.visible = false
	add_child(handles_root)
	rebuild_routes()
	_build_cams()

# ---------- геометрия ----------
static func boxes(parts: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for pr in parts:
		var bm := BoxMesh.new()
		bm.size = pr[0]
		st.append_from(bm, 0, Transform3D(Basis(), pr[1]))
	st.generate_normals()
	return st.commit()

static func frame_mesh() -> ArrayMesh:
	# рама прицепа ≈4,0×1,9 м: два лонжерона, поперечины, дышло-треугольник
	var p: Array = []
	for s in [-0.9, 0.9]:
		p.append([Vector3(4.0, 0.12, 0.08), Vector3(0, 0.06, s)])
	for i in 6:
		p.append([Vector3(0.06, 0.08, 1.8), Vector3(-1.95 + i * 0.78, 0.06, 0)])
	for s in [-1.0, 1.0]:
		p.append([Vector3(1.35, 0.08, 0.07), Vector3(2.6, 0.06, s * 0.45)])
	p.append([Vector3(0.25, 0.1, 0.12), Vector3(3.3, 0.06, 0)])
	return boxes(p)

static func kara_mesh() -> ArrayMesh:
	# кара/погрузчик: корпус, кабина-рама, мачта
	return boxes([
		[Vector3(2.2, 0.9, 1.15), Vector3(0, 0.75, 0)],
		[Vector3(0.9, 1.1, 1.05), Vector3(-0.2, 1.75, 0)],
		[Vector3(0.12, 2.6, 0.9), Vector3(1.2, 1.3, 0)],
		[Vector3(1.2, 0.06, 0.9), Vector3(1.85, 0.25, 0)],
		[Vector3(0.6, 0.55, 0.3), Vector3(-0.7, 0.3, 0.6)],
		[Vector3(0.6, 0.55, 0.3), Vector3(-0.7, 0.3, -0.6)],
		[Vector3(0.6, 0.55, 0.3), Vector3(0.7, 0.3, 0.6)],
		[Vector3(0.6, 0.55, 0.3), Vector3(0.7, 0.3, -0.6)],
	])

func _mm(mesh: Mesh, mat: Material, count: int) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = count
	mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	add_child(mi)
	return mi

func _build_frames() -> void:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.55
	m.metallic = 0.5
	frames_mm = _mm(frame_mesh(), m, 600)
	var k := StandardMaterial3D.new()
	k.vertex_color_use_as_albedo = true
	k.roughness = 0.6
	karas_mm = _mm(kara_mesh(), k, 80)

func _label(txt: String, size: int, col: Color) -> Label3D:
	var l := Label3D.new()
	l.text = txt
	l.font_size = size
	l.outline_size = 6
	l.modulate = col
	l.outline_modulate = Color(0.05, 0.06, 0.07, 0.9)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = true
	l.pixel_size = 0.0008
	l.render_priority = 10
	l.outline_render_priority = 9
	return l

func _build_markers() -> void:
	var pole := CylinderMesh.new()
	pole.top_radius = 0.06
	pole.bottom_radius = 0.06
	pole.height = 4.5
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.95, 0.75, 0.15)
	pm.emission_enabled = true
	pm.emission = Color(0.6, 0.45, 0.05)
	for n in data.stations:
		var d: Dictionary = n
		var root := Node3D.new()
		root.name = "Участок_" + String(d.id)
		add_child(root)
		var pi := MeshInstance3D.new()
		pi.mesh = pole
		pi.material_override = pm
		pi.position = Vector3(0, 2.25, 0)
		pi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(pi)
		var disc := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 2.2
		cm.bottom_radius = 2.2
		cm.height = 0.05
		disc.mesh = cm
		var dm := StandardMaterial3D.new()
		dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		dm.albedo_color = Color(0.2, 0.8, 0.3, 0.45)
		disc.material_override = dm
		disc.position = Vector3(0, 0.1, 0)
		disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(disc)
		var title := _label("%s  %s" % [d.num, d.name], 17, Color(1, 0.86, 0.5))
		title.position = Vector3(0, 4.9, 0)
		title.offset = Vector2(0, 10)
		title.visibility_range_end = 330.0
		root.add_child(title)
		var info := _label("", 14, Color(0.85, 0.95, 1.0))
		info.position = Vector3(0, 4.9, 0)
		info.offset = Vector2(0, -8)
		info.visibility_range_end = 170.0
		root.add_child(info)
		markers[d.id] = {"root": root, "title": title, "info": info, "disc": disc, "dm": dm}
	sync_markers()

func sync_markers() -> void:
	for id in markers:
		var p: Vector2 = sim.nodes[id].pos
		markers[id].root.position = Vector3(p.x, 0, p.y)

func _build_cams() -> void:
	cams_root = Node3D.new()
	cams_root.name = "Камеры"
	add_child(cams_root)
	var body := boxes([[Vector3(0.32, 0.18, 0.18), Vector3(0.12, 0, 0)], [Vector3(0.06, 0.06, 0.06), Vector3(-0.08, 0, 0)]])
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(0.93, 0.93, 0.92)
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 3.5
	cone.height = 9.0
	cone.radial_segments = 16
	var vm := StandardMaterial3D.new()
	vm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	vm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	vm.albedo_color = Color(0.3, 0.75, 1.0, 0.10)
	vm.cull_mode = BaseMaterial3D.CULL_DISABLED
	for c in data.cams:
		var d: Dictionary = c
		var n := Node3D.new()
		n.name = String(d.id)
		n.position = Vector3(d.pos[0], d.y, d.pos[1])
		n.rotation.y = deg_to_rad(float(d.yaw))
		var b := MeshInstance3D.new()
		b.mesh = body
		b.material_override = cm
		b.scale = Vector3(2.5, 2.5, 2.5)
		n.add_child(b)
		var v := MeshInstance3D.new()
		v.mesh = cone
		v.material_override = vm
		v.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# конус смотрит по +x камеры и вниз под 25°
		v.rotation = Vector3(0, 0, deg_to_rad(90 + 25))
		v.position = Vector3(4.5 * cos(deg_to_rad(25)), -4.5 * sin(deg_to_rad(25)), 0)
		n.add_child(v)
		var l := _label("◉ " + String(d.name), 13, Color(0.75, 0.9, 1.0))
		l.position = Vector3(0, 0.9, 0)
		l.visibility_range_end = 110.0
		n.add_child(l)
		cams_root.add_child(n)

## Линии маршрутов: лента 0,9 м над плитами, оранжевая — путь рамы.
func rebuild_routes() -> void:
	for c in routes_root.get_children():
		c.queue_free()
	for c in handles_root.get_children():
		c.queue_free()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.55, 0.15, 0.8)
	mat.render_priority = 2
	var pairs := _pairs()
	for pr in pairs:
		var pts: PackedVector2Array = sim.path(pr[0], pr[1])
		var mi := MeshInstance3D.new()
		mi.mesh = _ribbon(pts, 0.9, 0.16)
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		routes_root.add_child(mi)
	# ручки точек маршрута для планировщика
	var hm := SphereMesh.new()
	hm.radius = 0.9
	hm.height = 1.8
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color(1.0, 0.6, 0.2)
	hmat.emission_enabled = true
	hmat.emission = Color(0.6, 0.3, 0.05)
	for k in sim.routes:
		var arr: PackedVector2Array = sim.routes[k]
		for i in arr.size():
			var h := MeshInstance3D.new()
			h.mesh = hm
			h.material_override = hmat
			h.position = Vector3(arr[i].x, 0.9, arr[i].y)
			h.set_meta("route", k)
			h.set_meta("idx", i)
			handles_root.add_child(h)
	routes_root.visible = show_routes

func _pairs() -> Array:
	var out: Array = []
	for id in sim.order:
		var n: Dictionary = sim.nodes[id]
		if n.next != "":
			out.append([id, n.next])
		if n.feed != "":
			out.append([n.feed, id])
	return out

static func _ribbon(pts: PackedVector2Array, w: float, y: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var d := (b - a)
		if d.length() < 0.01:
			continue
		var n := Vector2(-d.y, d.x).normalized() * w * 0.5
		var A := Vector3(a.x + n.x, y, a.y + n.y)
		var B := Vector3(a.x - n.x, y, a.y - n.y)
		var C := Vector3(b.x + n.x, y, b.y + n.y)
		var D := Vector3(b.x - n.x, y, b.y - n.y)
		for v in [A, C, B, B, C, D]:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
		# стрелка посередине сегмента
		var m := (a + b) * 0.5
		var f := d.normalized() * 1.6
		var s := Vector2(-f.y, f.x) * 0.8
		var tip := Vector3(m.x + f.x, y + 0.01, m.y + f.y)
		var l := Vector3(m.x - f.x * 0.3 + s.x, y + 0.01, m.y - f.y * 0.3 + s.y)
		var r := Vector3(m.x - f.x * 0.3 - s.x, y + 0.01, m.y - f.y * 0.3 - s.y)
		for v in [tip, l, r]:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	return st.commit()

# ---------- каждый кадр: рамы, кары, цифры ----------
func _process(dt: float) -> void:
	if sim == null:
		return
	var fm: MultiMesh = frames_mm.multimesh
	var km: MultiMesh = karas_mm.multimesh
	var fi := 0
	var ki := 0
	# стопки в очередях и рамы на постах
	for id in sim.order:
		var n: Dictionary = sim.nodes[id]
		var base: Vector2 = n.pos
		var col := C_PAINT if PAINTED.has(id) else (C_SAND if id == "paint" else C_RAW)
		var q: Array = n.queue
		for i in q.size():
			if fi >= fm.instance_count:
				break
			var stack := i / 10
			var lev := i % 10
			var off := Vector2(4.5 + stack * 2.4, -3.0)
			fm.set_instance_transform(fi, Transform3D(Basis(), Vector3(base.x + off.x, 0.02 + lev * 0.15, base.y + off.y)))
			fm.set_instance_color(fi, col)
			fi += 1
		for b in n.busy:
			if fi >= fm.instance_count:
				break
			var post := int(b.post)
			var o := Vector2(-3.0 + (post % 3) * 0.0, -6.0 + (post % 3) * 3.0 + float(post / 3) * 9.0)
			var tw := Transform3D(Basis(), Vector3(base.x + o.x - 5.0, 0.9, base.y + o.y))
			fm.set_instance_transform(fi, tw)
			var c2 := col
			if id == "sand":
				c2 = C_SAND
			elif id == "paint":
				c2 = C_PAINT
			fm.set_instance_color(fi, c2)
			fi += 1
	# в пути
	for tr in sim.transit:
		var pts: PackedVector2Array = sim.path(tr.from, tr.to)
		var k := clampf((sim.clock - float(tr.t0)) / maxf(float(tr.end) - float(tr.t0), 1.0), 0.0, 1.0)
		var pose := _along(pts, k)
		var pos: Vector2 = pose[0]
		var yaw: float = pose[1]
		var bas := Basis(Vector3.UP, yaw)
		if ki < km.instance_count:
			km.set_instance_transform(ki, Transform3D(bas, Vector3(pos.x, 0, pos.y)))
			km.set_instance_color(ki, Color(0.95, 0.72, 0.12))
			ki += 1
		if fi < fm.instance_count:
			var c3 := C_PAINT if PAINTED.has(String(tr.to)) else (C_SAND if String(tr.from) == "sand" else C_RAW)
			fm.set_instance_transform(fi, Transform3D(bas, Vector3(pos.x, 1.55, pos.y) + bas * Vector3(0.6, 0, 0)))
			fm.set_instance_color(fi, c3)
			fi += 1
	fm.visible_instance_count = fi
	km.visible_instance_count = ki
	t_label -= dt
	if t_label <= 0.0:
		t_label = 0.3
		_update_labels()

func _along(pts: PackedVector2Array, k: float) -> Array:
	var L := 0.0
	var seg: Array = []
	for i in pts.size() - 1:
		var l := pts[i].distance_to(pts[i + 1])
		seg.append(l)
		L += l
	var s := k * L
	for i in seg.size():
		if s <= float(seg[i]) or i == seg.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var u := clampf(s / maxf(float(seg[i]), 0.001), 0.0, 1.0)
			var d := b - a
			return [a.lerp(b, u), atan2(-d.y, d.x)]
		s -= float(seg[i])
	return [pts[pts.size() - 1], 0.0]

func _update_labels() -> void:
	for id in markers:
		var n: Dictionary = sim.nodes[id]
		var mk: Dictionary = markers[id]
		var txt := ""
		var col := Color(0.2, 0.8, 0.3, 0.45)
		if n.kind == "proc":
			var u: float = sim.util(id)
			txt = "в работе %d/%d · очередь %d · загрузка %d%%" % [n.busy.size(), n.posts, n.queue.size(), int(round(u * 100.0))]
			if u > 0.92:
				col = Color(0.95, 0.2, 0.15, 0.5)
			elif u > 0.75:
				col = Color(0.98, 0.75, 0.1, 0.5)
		elif n.kind == "buf":
			txt = "ждут: %d" % n.queue.size()
			if n.queue.size() > 15:
				col = Color(0.95, 0.2, 0.15, 0.5)
			elif n.queue.size() > 6:
				col = Color(0.98, 0.75, 0.1, 0.5)
		else:
			txt = "готово к отправке: %d · всего %d" % [n.queue.size(), sim.done_total]
		mk.info.text = txt
		mk.dm.albedo_color = col

func set_routes_visible(v: bool) -> void:
	show_routes = v
	routes_root.visible = v

func set_cams_visible(v: bool) -> void:
	show_cams = v
	cams_root.visible = v
