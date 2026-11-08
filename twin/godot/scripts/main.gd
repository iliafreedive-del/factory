extends Node3D
## Точка входа двойника: окружение и солнце, сцена завода из Blender, камера,
## «состояние завода» (поток событий), симуляция пути рамы, слои, интерфейс и планировщик.

const Mats := preload("res://scripts/mats.gd")

const CONCEPT := """[b]Цель.[/b] Видеть завод целиком на одном экране и решать, куда его развивать, на модели, а не на живом производстве: где сейчас рамы, где очередь, где простой и что будет, если что-то поменять.

[b]Чем помогает собственнику[/b]
• [b]Видно узкое место.[/b] Где копятся рамы и стоят посты, показано цветом: зелёный, жёлтый, красный. Сейчас это видно только обходом цехов.
• [b]Перестановки проверяются до переноса станков.[/b] Участок, точку маршрута или целое здание тянут мышью, и модель сразу пересчитывает пробег рамы и пропускную способность.
• [b]Рост считается заранее.[/b] Сколько постов и площади нужно под план 14 или 18 рам в смену, что дают строящийся цех, второй пост малярки, ещё один сварщик.
• [b]Движение координируется.[/b] Маршруты кар и погрузчиков, где пересекаются потоки, где стоит готовое и ждёт отгрузки.
• [b]Завод легко показать.[/b] Новому мастеру, партнёру, банку или покупателю: весь процесс за пять минут, без поездки.
• [b]Дальше это пульт в реальном времени.[/b] Тот же экран, но цифры идут не от модели, а с завода.

[b]Как будет в реальном времени, без QR-кодов на деталях[/b]
• [b]Резка и сварка:[/b] сменное задание партией (из 1С или с планшета мастера) и датчики тока на станках: работает или простой. На металл ничего не клеим.
• [b]До покраски на раме нет никаких меток:[/b] пескоструй всё снимает. Раму ведут камеры по зонам: въехала в песко, вышла из малярки.
• [b]После малярки[/b] у рамы есть VIN и шильдик. Камера читает его один раз на входе в сборку и один раз на отгрузке.
• [b]Металл и комплектующие[/b] берутся из складского учёта 1С.
• [b]Люди и прицепы:[/b] камеры считают, сколько людей и прицепов в зоне. Это не слежка за лицами.
• [b]Камеры уже висят:[/b] IP-кубик RVi в офисе, уличные и купольные в Сборке 1 (кнопка «Камеры»). Начинаем с потока RTSP с регистратора. Для чтения VIN нужны одна-две новые IP-камеры на входе в сборку и на отгрузке.
• [b]Всё сходится в один поток событий «состояние завода».[/b] Сейчас его даёт симуляция, потом камеры, датчики и 1С. Двойник при этом переделывать не надо.

[b]Что нужно от завода, чтобы цифры стали настоящими:[/b] минуты на раму по участкам, число постов и людей, план в смену, сменность. Пока стоят условные цифры, и они так и подписаны."""

const SCENARIOS := [
	{"id": "base", "name": "Как сейчас", "text": "Посты и места участков как на заводе, времена условные."},
	{"id": "plan14", "name": "План 14 рам в смену", "text": "Запуск в резку растёт с 10 до 14 рам. Видно, какой участок первым перестанет успевать: перед ним начнут копиться рамы."},
	{"id": "paint2", "name": "Второй пост в малярке", "text": "Малярка красит две рамы сразу. Помогает, только если узкое место в малярке."},
	{"id": "weld4", "name": "Ещё один пост сварки рамы", "text": "Четвёртый сварщик рам в Цехе 1."},
	{"id": "b5asm", "name": "Сборка 2 в строящемся цехе", "text": "Сборка 2 переезжает в новый цех южнее ЛГЦ на три поста. Маршрут кары условный, точки можно двигать в «Планировщике»."},
	{"id": "grow18", "name": "18 рам в смену: всё под план", "text": "План 18 рам, посты добавлены там, где не хватает по расчёту: сварка 4, песко 2, малярка 2, сборка 3 и 3."},
]

var factory: Node3D
var cam_rig: Node3D
var state: Node
var sim: Node
var viz: Node3D
var ui: CanvasLayer
var planner: Node3D
var shot_path := ""
var shot_frames := 0
var args := {}
var shot_views: Array = []
var shot_i := 0
var env: Environment
var data: Dictionary
var current_vp := -1
var weather := "photo"
var sun: DirectionalLight3D
var bnodes := {}          # здание -> [узлы сцены]: стены, крыша, внутренности, подписи
var bcenter := {}         # здание -> центр прямоугольника на плане
var roofs: Array = []     # MeshInstance3D крыш
var roof_mode := 0        # 0 авто, 1 сняты, 2 на месте
var roofs_shown := true
var walls_of := {}        # здание -> стены 1 этажа (при снятых крышах срезаются по высоте, как в старой игре)
var walls2_of := {}       # здание -> стены 2 этажа
var fl2_of := {}          # здание -> 2 этаж (пол, мебель, люди)
var cut_key := ""
var floor1_b := ""        # здание, у которого сейчас показан 1 этаж (2 этаж спрятан)
const WALL_CUT := 0.4     # сколько высоты стен оставить, когда крыши сняты
const FLOOR1_CUT := 0.3   # стены 1 этажа, когда 2 этаж спрятан
const FLOOR1_DIST := 80.0 # ближе — показать 1 этаж двухэтажного здания
var labels_root: Node3D
var label_items: Array = []   # {node, id, b}
var people_node: Node3D
var base_route := 0.0
var press_pos := Vector2(-1, -1)
var hash_t := -1.0
var last_hash := ""
var overlay_walk := false

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	data = JSON.parse_string(FileAccess.get_file_as_string("res://data/twin.json"))
	_setup_font()
	_setup_screen()
	_setup_world()
	_load_factory()
	cam_rig = preload("res://scripts/cam.gd").new()
	cam_rig.name = "CamRig"
	add_child(cam_rig)
	cam_rig.moved.connect(func(): hash_t = 1.0)
	_build_labels()
	# состояние завода и симуляция
	state = preload("res://scripts/state.gd").new()
	state.name = "Состояние"
	add_child(state)
	sim = preload("res://scripts/sim.gd").new()
	sim.name = "Симуляция"
	add_child(sim)
	sim.setup(state, data)
	state.event.connect(sim.apply_event)
	state.source_changed.connect(func(_s): sim.on_source(state.source))
	viz = preload("res://scripts/viz.gd").new()
	viz.name = "Живой завод"
	add_child(viz)
	viz.setup(state, sim, data)
	planner = preload("res://scripts/planner.gd").new()
	planner.name = "Планировщик"
	add_child(planner)
	ui = preload("res://scripts/ui.gd").new()
	ui.name = "UI"
	add_child(ui)
	ui.build(self)
	planner.setup(self)
	base_route = sim.route_total()
	set_speed(float(args.get("speed", "60")))
	if args.has("simtime"):
		sim.advance(float(args["simtime"]))
	_read_url()
	if args.has("view"):
		cam_rig.set_view_str(args["view"])
	if args.has("scenario"):
		apply_scenario(args["scenario"])
	if args.has("planner"):
		ui.btn["plan"].button_pressed = true
	if args.has("dialog"):
		ui.toggle_dialog(args["dialog"])
	if args.has("zones"):
		ui.btn["zones"].button_pressed = true
	if args.get("ui", "1") == "0":
		ui.visible = false
	if args.has("shot"):
		# --shot=путь_без_.png --views=v1;v2;… : несколько кадров за один запуск
		shot_path = args["shot"]
		shot_frames = int(args.get("frames", "40"))
		if args.has("views"):
			shot_views = Array(args["views"].split(";"))
			_next_view()

## В веб-версии нет системных шрифтов: стрелки, кружки и значки берём из DejaVu Sans (свободная лицензия, fonts/).
func _setup_font() -> void:
	var dv: Font = load("res://fonts/DejaVuSans.ttf")
	var fv := FontVariation.new()
	fv.base_font = ThemeDB.fallback_font
	fv.fallbacks = [dv]
	ThemeDB.fallback_font = fv
	ThemeDB.get_default_theme().default_font = fv

## На телефоне и экранах с высокой плотностью интерфейс крупнее, а 3D считается в меньшем разрешении.
func _setup_screen() -> void:
	var dpr := DisplayServer.screen_get_scale()
	if args.has("dpr"):
		dpr = float(args["dpr"])
	if dpr > 1.05:
		get_window().content_scale_factor = clampf(dpr, 1.0, 3.0)
		get_viewport().scaling_3d_scale = clampf(1.6 / dpr, 0.5, 1.0)

func _setup_world() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var psm := ShaderMaterial.new()
	psm.shader = load("res://shaders/sky.gdshader")
	sky.sky_material = psm
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.ambient_light_sky_contribution = 0.85
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 0.95
	env.fog_enabled = true
	env.fog_light_color = Color(0.76, 0.81, 0.86)
	env.fog_density = 0.0009
	env.fog_aerial_perspective = 0.15
	env.fog_sky_affect = 0.3
	env.glow_enabled = true
	env.glow_intensity = 0.3
	env.glow_bloom = 0.02
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.05
	env.adjustment_contrast = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	# Красноярск 56° с. ш., день: солнце на юго-юго-западе на высоте ≈36°.
	# Азимут β в осях плана: x = cos(β−75°), z = cos(β−165°).
	var beta := deg_to_rad(205.0)
	var to_sun := Vector3(cos(beta - deg_to_rad(75.0)), 0.0, cos(beta - deg_to_rad(165.0))).normalized()
	var elev := deg_to_rad(36.0)
	var dir := (to_sun * cos(elev) + Vector3.UP * sin(elev)).normalized()
	sun.look_at_from_position(dir * 100.0, Vector3.ZERO, Vector3.UP)
	sun.light_color = Color(1.0, 0.95, 0.88)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 1.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 420.0
	sun.directional_shadow_split_1 = 0.06
	sun.directional_shadow_split_2 = 0.18
	sun.directional_shadow_split_3 = 0.45
	sun.directional_shadow_blend_splits = true
	add_child(sun)
	apply_weather(args.get("weather", "photo"))
	# подбор света из командной строки (для сверки с фото)
	if args.has("sun"): sun.light_energy = float(args["sun"])
	if args.has("amb"): env.ambient_light_energy = float(args["amb"])
	if args.has("exp"): env.tonemap_exposure = float(args["exp"])
	if args.has("fog"): env.fog_density = float(args["fog"])
	if args.has("tm"): env.tonemap_mode = int(args["tm"])
	if args.has("glow"): env.glow_enabled = args["glow"] == "1"
	if args.has("adj"): env.adjustment_enabled = args["adj"] == "1"

## Погода: «photo» — как в день съёмки 26.10 (пасмурно, мягкий свет), «sun» — ясный день.
func apply_weather(w: String) -> void:
	var psm: ShaderMaterial = env.sky.sky_material
	weather = w
	env.glow_enabled = false
	env.adjustment_enabled = false
	if w == "sun":
		psm.set_shader_parameter("top_col", Color(0.30, 0.50, 0.80))
		psm.set_shader_parameter("hor_col", Color(0.74, 0.80, 0.86))
		psm.set_shader_parameter("cloud_lit", Color(0.97, 0.97, 0.97))
		psm.set_shader_parameter("cloud_dark", Color(0.75, 0.78, 0.82))
		psm.set_shader_parameter("cover", 0.25)
		env.ambient_light_energy = 0.4
		env.tonemap_mode = Environment.TONE_MAPPER_ACES
		env.tonemap_exposure = 0.9
		env.fog_light_color = Color(0.76, 0.81, 0.86)
		env.fog_density = 0.0004
		sun.light_energy = 1.25
		sun.light_color = Color(1.0, 0.95, 0.88)
		sun.shadow_blur = 1.2
	else:
		psm.set_shader_parameter("top_col", Color(0.50, 0.53, 0.57))
		psm.set_shader_parameter("hor_col", Color(0.80, 0.81, 0.82))
		psm.set_shader_parameter("cloud_lit", Color(0.86, 0.87, 0.88))
		psm.set_shader_parameter("cloud_dark", Color(0.44, 0.46, 0.49))
		psm.set_shader_parameter("cover", 0.62)
		env.ambient_light_energy = 0.45
		env.ambient_light_sky_contribution = 1.0
		env.tonemap_mode = Environment.TONE_MAPPER_ACES
		env.tonemap_exposure = 0.9
		env.fog_light_color = Color(0.74, 0.75, 0.77)
		env.fog_density = 0.0005
		sun.light_energy = 0.5
		sun.light_color = Color(0.95, 0.96, 1.0)
		sun.shadow_blur = 4.0

func toggle_weather() -> void:
	apply_weather("photo" if weather == "sun" else "sun")
	ui.btn["weather"].text = "Погода: ясно" if weather == "sun" else "Погода: как на фото"

func _load_factory() -> void:
	var ps: PackedScene = load("res://assets/factory.glb")
	factory = ps.instantiate()
	factory.name = "Factory"
	add_child(factory)
	var st := Mats.apply(factory)
	print("materials: ", st)
	for b in data.buildings:
		var d: Dictionary = b
		var r: Array = d.r
		bcenter[d.id] = Vector2((float(r[0]) + float(r[2])) * 0.5, (float(r[1]) + float(r[3])) * 0.5)
	for c in factory.get_children():
		var nm := String(c.name)
		var parts := nm.split("|")
		var bid := parts[0]
		var part := parts[1] if parts.size() > 1 else ""
		if bid == "people":
			people_node = c
		if bcenter.has(bid):
			if not bnodes.has(bid):
				bnodes[bid] = []
			bnodes[bid].append(c)
		if part == "roof" or part == "roofIn":
			for m in c.find_children("*", "MeshInstance3D", true, false):
				roofs.append(m)
			if c is MeshInstance3D:
				roofs.append(c)
		for pr in [["walls", walls_of], ["walls2", walls2_of], ["fl2", fl2_of]]:
			if part == pr[0]:
				var dd: Dictionary = pr[1]
				if not dd.has(bid):
					dd[bid] = []
				dd[bid].append(c)

# ---------- подписи участков и мест ----------
func _build_labels() -> void:
	labels_root = Node3D.new()
	labels_root.name = "Подписи"
	add_child(labels_root)
	var groups := {}
	for l in data.labels:
		var d: Dictionary = l
		var kind := String(d.kind)
		var size := 14
		var col := Color(0.93, 0.94, 0.95)
		var far := 130.0
		match kind:
			"b":
				size = 17
				col = Color(1, 1, 1)
				far = 0.0
			"z":
				size = 14
				col = Color(0.82, 0.95, 0.82)
				far = 260.0
			"r":
				size = 14
				col = Color(0.97, 0.9, 0.72)
				far = 140.0
			"f":
				size = 13
				col = Color(0.85, 0.9, 1.0)
				far = 80.0
			_:
				size = 13
				col = Color(0.92, 0.92, 0.88)
				far = 75.0
		var info: Dictionary = data.info.get(String(d.id), {})
		var txt := String(d.t)
		if info.has("ask") and info.ask.size() > 0:
			# есть вопросы к заводу — подпись чуть оранжевее, вопросы в карточке
			col = col.lerp(Color(1.0, 0.7, 0.35), 0.45)
		var lab := Label3D.new()
		lab.text = txt
		lab.font_size = size
		lab.outline_size = 6
		lab.modulate = col
		lab.outline_modulate = Color(0.04, 0.05, 0.06, 0.85)
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lab.no_depth_test = true
		lab.fixed_size = true
		lab.pixel_size = 0.0008
		lab.render_priority = 8
		lab.outline_render_priority = 7
		lab.position = Vector3(d.x, d.y, d.z)
		if far > 0.0:
			lab.visibility_range_end = far
		var bid = d.b
		var parent: Node3D = labels_root
		if bid != null and bcenter.has(String(bid)):
			# подписи здания едут вместе с ним в планировщике
			if not groups.has(bid):
				var g := Node3D.new()
				g.name = "Подписи_" + String(bid)
				labels_root.add_child(g)
				groups[bid] = g
				if not bnodes.has(bid):
					bnodes[bid] = []
				bnodes[bid].append(g)
			parent = groups[bid]
		parent.add_child(lab)
		var fl := 0
		if bid != null and kind != "b":
			# в двухэтажном здании подписи только текущего этажа (как в старой игре)
			fl = 2 if float(d.y) > 4.0 else 1
		label_items.append({"node": lab, "id": String(d.id), "far": far, "b": String(bid) if bid != null else "", "fl": fl, "kind": kind})

# ---------- виды ----------
func view_overview() -> void:
	current_vp = -1
	ui.show_photo_bar(-1)
	cam_rig.set_view(5.0, 42.0, 0.62, 0.62, 230.0)
	ui.set_hint("Мышь: тянуть — двигать карту, правая или Shift — повернуть, колесо — приблизить. Нажмите на цех, участок или камеру.")

func view_top() -> void:
	current_vp = -1
	ui.show_photo_bar(-1)
	if cam_rig.mode == "walk":
		cam_rig.set_view(10.0, 40.0, 0.62, 0.62, 420.0)
	cam_rig.t.tx = 10.0
	cam_rig.t.tz = 40.0
	cam_rig.set_top(true)
	ui.set_hint("Вид сверху: север вверху, как на 2ГИС.")

func view_walk() -> void:
	current_vp = -1
	ui.show_photo_bar(-1)
	cam_rig.set_walk(Vector2(-10.5, 57.0), Vector2(47.5, 56.0), 24.0)
	ui.set_hint("С земли: WASD или стрелки — идти, Shift — быстрее, мышь — оглядеться, колесо — шаг.")

func _next_view() -> void:
	var v: String = shot_views[shot_i]
	if v.begins_with("photo"):
		show_photo_point(int(v.substr(5)))
	elif v == "top":
		cam_rig.set_top(true)
		cam_rig.tx = 140; cam_rig.tz = 70; cam_rig.t.tx = 140; cam_rig.t.tz = 70
		cam_rig.dist = 520; cam_rig.t.dist = 520; cam_rig.az = cam_rig.t.az; cam_rig.el = cam_rig.t.el
	elif v.begins_with("st:"):
		focus_station(v.substr(3))
		cam_rig.tx = cam_rig.t.tx; cam_rig.tz = cam_rig.t.tz; cam_rig.dist = cam_rig.t.dist
		cam_rig.az = cam_rig.t.az; cam_rig.el = cam_rig.t.el
	else:
		cam_rig.set_view_str(v)

## точка съёмки фото: камера там, где стоял Илья, с тем же объективом (данные plan.json → twin.json)
func show_photo_point(i: int) -> void:
	var vps: Array = data.viewpoints
	var v: Dictionary = vps[posmod(i, vps.size())]
	var pos := Vector2(v.pos[0], v.pos[1])
	var look := Vector2(v.look[0], v.look[1])
	cam_rig.set_walk_photo(pos, look, float(v.f35), float(v.vfov), float(v.y), float(v.pitch))
	current_vp = posmod(i, vps.size())
	if ui:
		ui.info_panel.visible = false
		ui.show_photo_bar(current_vp)
		ui.set_hint("Вид с точки, где снято фото %s. Мышь — оглядеться, WASD — шаг." % v.photo)
	hash_t = 0.2

func focus_station(id: String) -> void:
	if not sim.nodes.has(id):
		return
	var p: Vector2 = sim.nodes[id].pos
	current_vp = -1
	ui.show_photo_bar(-1)
	var az: float = cam_rig.t.az if cam_rig.mode == "orbit" else 0.62
	cam_rig.set_view(p.x, p.y, az, 0.78, 75.0)
	_show_station(id)

# ---------- слои ----------
func cycle_roofs() -> void:
	roof_mode = (roof_mode + 1) % 3
	ui.btn["roof"].text = ["Крыши: авто", "Крыши: сняты", "Крыши: на месте"][roof_mode]
	_update_roofs(true)

func _update_roofs(force := false) -> void:
	var show := true
	if roof_mode == 1:
		show = false
	elif roof_mode == 0:
		if cam_rig.mode == "walk":
			show = true
		else:
			var d: float = cam_rig.dist
			show = d > (165.0 if roofs_shown else 150.0)
	_update_cut(show)
	if show == roofs_shown and not force:
		return
	roofs_shown = show
	for m in roofs:
		# снятая крыша продолжает отбрасывать тень: внутри цеха остаётся полумрак, как на фото
		(m as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if show else GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY

## Крыши сняты — стены срезаны по высоте, видно, что внутри. У двухэтажного здания (Офис 1) ближе 80 м
## прячется 2 этаж и видно 1 этаж: «2 этаж · ближе — 1 этаж», как в старой игре.
func _update_cut(roofs_on: bool) -> void:
	var cut: bool = not roofs_on and cam_rig.mode != "walk"
	var f1 := ""
	if cut and cam_rig.dist < FLOOR1_DIST:
		var tp := Vector2(cam_rig.tx, cam_rig.tz)
		var best := 1e9
		for bid in fl2_of:
			var sh: Array = planner.bshift.get(bid, [0.0, 0.0, 0.0]) if planner else [0.0, 0.0, 0.0]
			var c: Vector2 = bcenter[bid] + Vector2(sh[0], sh[1])
			var d := c.distance_to(tp)
			if d < 35.0 and d < best:
				best = d
				f1 = bid
	var key := "%s|%s" % [cut, f1]
	if key == cut_key:
		return
	cut_key = key
	floor1_b = f1
	for bid in walls_of:
		var k := 1.0
		if cut:
			k = FLOOR1_CUT if bid == f1 else (1.0 if fl2_of.has(bid) else WALL_CUT)
		for n in walls_of[bid]:
			(n as Node3D).scale.y = k
	for bid in walls2_of:
		for n in walls2_of[bid]:
			(n as Node3D).scale.y = WALL_CUT if cut else 1.0
			(n as Node3D).visible = bid != f1
	for bid in fl2_of:
		for n in fl2_of[bid]:
			(n as Node3D).visible = bid != f1
	for it in label_items:
		var bid: String = it.b
		if bid == "" or not fl2_of.has(bid):
			continue
		var lab: Label3D = it.node
		if it.kind == "f":
			lab.visible = cut
			lab.text = "1 этаж · дальше — 2 этаж" if bid == f1 else "2 этаж · ближе — 1 этаж"
		elif int(it.fl) == 2:
			lab.visible = bid != f1
		elif int(it.fl) == 1:
			lab.visible = bid == f1 or not cut

## Ссылка в карточке: «Заглянуть внутрь» — камера подлетает к зданию, крыша снимается, у Офиса 1 виден 1 этаж
func on_info_link(m: String) -> void:
	if m.begins_with("in:"):
		var bid := m.substr(3)
		for b in data.buildings:
			var d: Dictionary = b
			if String(d.id) != bid:
				continue
			var r: Array = d.r
			var sh: Array = planner.bshift.get(bid, [0.0, 0.0, 0.0])
			var c: Vector2 = bcenter[bid] + Vector2(sh[0], sh[1])
			var size := maxf(float(r[2]) - float(r[0]), float(r[3]) - float(r[1]))
			var az: float = cam_rig.t.az if cam_rig.mode == "orbit" else 0.62
			if cam_rig.mode == "walk":
				cam_rig.mode = "orbit"
			cam_rig.set_view(c.x, c.y, az, 0.95, clampf(size * 1.3, 30.0, 140.0))
			ui.info_panel.visible = false
			return

func set_zones(on: bool) -> void:
	Mats.set_zones_visible(on)

func set_flows(_on: bool) -> void:
	_apply_layers()

func set_cams(_on: bool) -> void:
	_apply_layers()

func set_labels(_on: bool) -> void:
	_apply_layers()

## Слои по кнопкам; с земли (вид с фото, прогулка) схемы прячутся, чтобы картинку можно было сверять с фото.
func _apply_layers() -> void:
	var w: bool = cam_rig.mode == "walk"
	overlay_walk = w
	var flows: bool = ui.btn["flows"].button_pressed
	viz.set_routes_visible(flows and not w)
	viz.frames_mm.visible = flows
	viz.karas_mm.visible = flows
	for id in viz.markers:
		viz.markers[id].root.visible = flows and not w
	viz.set_cams_visible(ui.btn["cams"].button_pressed and not w)
	labels_root.visible = ui.btn["labels"].button_pressed and not w

func set_people(on: bool) -> void:
	if people_node:
		people_node.visible = on

func set_planner(on: bool) -> void:
	planner.set_active(on)
	ui.planner_panel.visible = on
	ui.info_panel.visible = false
	if on:
		ui.metrics_label.text = metrics_text(false)
		ui.set_hint("Планировщик: тяните участки, точки маршрута, здания и предметы. Цифры справа пересчитываются.")
	else:
		ui.set_hint("")

# ---------- симуляция ----------
func toggle_run() -> void:
	sim.running = not sim.running
	ui.run_btn.text = "Пауза" if sim.running else "Пуск"

func set_speed(s: float) -> void:
	sim.speed = s
	sim.running = true
	ui.run_btn.text = "Пауза"
	for k in ui.speed_btns:
		ui.speed_btns[k].modulate = Color(1.0, 0.75, 0.35) if is_equal_approx(float(k), s) else Color(1, 1, 1)

func reset_sim() -> void:
	sim.reset()

func set_param(id: String, key: String, v: float) -> void:
	if not sim.nodes.has(id):
		return
	if key == "posts":
		sim.nodes[id].posts = int(v)
	else:
		sim.nodes[id].cycle = float(v)
	_refresh_metrics()

func set_global(key: String, v: float) -> void:
	sim.p[key] = float(v)
	_refresh_metrics()

func sync_param_ui() -> void:
	if ui == null:
		return
	for id in ui.param_spins:
		var sp: Array = ui.param_spins[id]
		if sim.nodes.has(id):
			(sp[0] as SpinBox).set_value_no_signal(sim.nodes[id].posts)
			(sp[1] as SpinBox).set_value_no_signal(sim.nodes[id].cycle)
		elif sim.p.has(id):
			(sp[0] as SpinBox).set_value_no_signal(sim.p[id])

func after_plan_change() -> void:
	viz.sync_markers()
	viz.rebuild_routes()
	_refresh_metrics()

func _refresh_metrics() -> void:
	if ui == null:
		return
	if ui.planner_panel.visible:
		ui.metrics_label.text = metrics_text(false)
	if ui.dialogs.has("ways") and ui.dialogs["ways"].visible:
		ui.refresh_ways()

func apply_scenario(id: String) -> void:
	planner._push_undo()
	planner.apply_state(planner.base_state)
	var n: Dictionary = sim.nodes
	match id:
		"plan14":
			sim.p.plan = 14.0
		"paint2":
			n.paint.posts = 2
		"weld4":
			n.weld.posts = 4
		"b5asm":
			# новый цех южнее ЛГЦ: центр прямоугольника 2ГИС, кара едет по двору мимо красного ангара
			n.asm2.pos = bcenter.get("b5", Vector2(102.5, 21.9))
			n.asm2.posts = 3
			sim.routes["distrib>asm2"] = PackedVector2Array([Vector2(62, 58), Vector2(68, 30), Vector2(84, 30)])
			sim.routes["asm2>ship1"] = PackedVector2Array([Vector2(84, 30), Vector2(68, 30), Vector2(62, 66)])
			cam_rig.set_view(60.0, 40.0, 0.62, 0.7, 170.0)
		"grow18":
			sim.p.plan = 18.0
			n.weld.posts = 4
			n.sand.posts = 2
			n.paint.posts = 2
			n.asm1.posts = 3
			n.asm2.posts = 3
	viz.sync_markers()
	sync_param_ui()
	after_plan_change()
	sim.reset()
	sim.advance(float(sim.p.shift_h) * 3600.0)
	if ui:
		ui.refresh_ways()
		ui.set_hint("Вариант «%s»: модель прогнала одну смену. Вернуть как было — «Как сейчас»." % _scenario_name(id))

func _scenario_name(id: String) -> String:
	for s in SCENARIOS:
		if s.id == id:
			return s.name
	return id

# ---------- цифры ----------
static func f1(x: float) -> String:
	return ("%.1f" % x).replace(".", ",")

func metrics_text(full: bool) -> String:
	var caps: Array = sim.capacity()
	var bn: Dictionary = sim.bottleneck()
	var plan := float(sim.p.plan)
	var shift_min := float(sim.p.shift_h) * 60.0
	var L: float = sim.route_total()
	var s := ""
	s += "[b]Узкое место:[/b] %s, %s рам за смену\n" % [bn.name, f1(bn.cap)]
	if plan > float(bn.cap) + 0.01:
		s += "[color=#ff8a70]План %s рам больше, чем пропускает этот участок: перед ним будут копиться рамы.[/color]\n" % f1(plan)
	else:
		s += "План %s рам в смену поток пропускает, запас %d%%.\n" % [f1(plan), int(round((float(bn.cap) / maxf(plan, 0.1) - 1.0) * 100.0))]
	s += "Пробег рамы от резки до отгрузки: %d м" % int(round(L))
	if absf(L - base_route) > 1.0:
		s += " (было %d м)" % int(round(base_route))
	s += "\n"
	if full:
		s += "\n[b]Пропускная способность, рам за смену[/b]\n"
		for c in caps:
			s += "• %s: %s\n" % [c.name, f1(c.cap)]
		var need := ""
		var asm_posts := 0
		var asm_cycle := 0.0
		for id in sim.order:
			var nd: Dictionary = sim.nodes[id]
			if nd.kind != "proc":
				continue
			if String(id).begins_with("asm"):
				asm_posts += int(nd.posts)
				asm_cycle = maxf(asm_cycle, float(nd.cycle))
				continue
			var k := int(ceil(plan * float(nd.cycle) / shift_min - 0.001))
			if k > int(nd.posts):
				need += "• %s: нужно %d, сейчас %d\n" % [nd.name, k, nd.posts]
		var ka := int(ceil(plan * asm_cycle / shift_min - 0.001))
		if ka > asm_posts:
			need += "• Сборка 1 и 2: нужно %d постов, сейчас %d\n" % [ka, asm_posts]
		s += "\n[b]Под план %s рам в смену[/b]\n" % f1(plan)
		s += need if need != "" else "• постов хватает на всех участках\n"
	s += "\n[b]В модели сейчас:[/b] вышло %d рам, в работе %d, от резки до конца сборки ≈ %s ч\n" % [sim.done_total, sim.wip(), f1(sim.lead_h())]
	s += "[color=#b4b4a4]Времена операций условные, пока нет цифр с завода.[/color]"
	return s

func top_text() -> String:
	if state.source == "live":
		return "Живые данные · рам на заводе %d · событий %d · %s" % [state.frames.size(), state.log_lines.size(), state.live_url]
	var t := 8.0 * 3600.0 + float(sim.clock)
	var day := int(t / 86400.0) + 1
	var hh := int(fmod(t, 86400.0) / 3600.0)
	var mm := int(fmod(t, 3600.0) / 60.0)
	var bn: Dictionary = sim.bottleneck()
	return "Модель: день %d, %02d:%02d%s · вышло %d рам · в работе %d · за смену ≈ %s · узкое место: %s" % [
		day, hh, mm, "" if sim.running else " (пауза)", sim.done_total, sim.wip(), f1(sim.out_per_shift()), bn.name]

# ---------- карточки по клику ----------
func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.device == InputEvent.DEVICE_ID_EMULATION:
			return
		if ev.pressed:
			press_pos = ev.position
		elif press_pos.x >= 0.0 and press_pos.distance_to(ev.position) < 6.0:
			_click(ev.position)
	elif ev is InputEventScreenTouch and ev.index == 0:
		if ev.pressed:
			press_pos = ev.position
		elif press_pos.x >= 0.0 and press_pos.distance_to(ev.position) < 10.0:
			_click(ev.position)

func _screen_d(cam: Camera3D, p: Vector3, at: Vector2) -> float:
	if cam.is_position_behind(p):
		return 1e9
	return cam.unproject_position(p).distance_to(at)

func _click(at: Vector2) -> void:
	if planner.active and (planner.dragging or not planner.sel.is_empty()):
		return
	var cam: Camera3D = cam_rig.cam
	var best := 30.0
	var hit := {}
	if viz.show_cams and viz.cams_root.visible:
		for c in data.cams:
			var d: Dictionary = c
			var dd := _screen_d(cam, Vector3(d.pos[0], d.y, d.pos[1]), at)
			if dd < best:
				best = dd
				hit = {"kind": "cam", "d": d}
	if viz.routes_root.visible:
		for id in viz.markers:
			var mk: Dictionary = viz.markers[id]
			var base: Vector3 = mk.root.position
			for y in [0.5, 5.6]:
				var dd := _screen_d(cam, base + Vector3(0, y, 0), at)
				if dd < best:
					best = dd
					hit = {"kind": "station", "id": id}
	if labels_root.visible:
		var cp := cam.global_position
		for it in label_items:
			var lab: Label3D = it.node
			var wp := lab.global_position
			if float(it.far) > 0.0 and cp.distance_to(wp) > float(it.far):
				continue
			var dd := _screen_d(cam, wp, at)
			if dd < best * 0.8:
				best = dd / 0.8
				hit = {"kind": "info", "id": it.id, "t": lab.text}
	if hit.is_empty():
		var g = cam_rig.ground_at(at)
		if g == null:
			return
		var p := Vector2(g.x, g.z)
		var small := 1e12
		for b in data.buildings:
			var d: Dictionary = b
			var sh: Array = planner.bshift.get(d.id, [0.0, 0.0, 0.0])
			var q := p - Vector2(sh[0], sh[1])
			for rm in d.rooms:
				var rr: Array = rm.r
				if q.x >= float(rr[0]) and q.x <= float(rr[2]) and q.y >= float(rr[1]) and q.y <= float(rr[3]):
					var a := (float(rr[2]) - float(rr[0])) * (float(rr[3]) - float(rr[1]))
					if a < small and not roofs_shown:
						small = a
						hit = {"kind": "info", "id": String(rm.id), "t": String(rm.name), "b": d}
			var r: Array = d.r
			if q.x >= float(r[0]) and q.x <= float(r[2]) and q.y >= float(r[1]) and q.y <= float(r[3]):
				var a2 := (float(r[2]) - float(r[0])) * (float(r[3]) - float(r[1]))
				if hit.is_empty() or (roofs_shown and a2 < small):
					small = a2
					hit = {"kind": "info", "id": String(d.id), "t": String(d.name), "b": d}
		if hit.is_empty():
			for z in data.zones:
				var d: Dictionary = z
				if absf(p.x - float(d.x)) <= float(d.w) * 0.5 and absf(p.y - float(d.z)) <= float(d.d) * 0.5:
					hit = {"kind": "info", "id": String(d.id), "t": String(d.id)}
					break
	if hit.is_empty():
		ui.info_panel.visible = false
		return
	match String(hit.kind):
		"cam":
			_show_cam(hit.d)
		"station":
			_show_station(hit.id)
		"info":
			_show_info_id(hit.id, String(hit.t), hit.get("b", {}))

static func _esc(s: String) -> String:
	return s.replace("[", "[lb]")

func _info_body(d: Dictionary) -> String:
	var s := ""
	if d.has("tag"):
		s += "[color=#f5a54a]%s[/color]\n" % _esc(String(d.tag))
	if d.has("text"):
		s += _esc(String(d.text)) + "\n"
	if d.has("ask") and d.ask.size() > 0:
		s += "\n[b]Вопросы к заводу[/b]\n"
		for q in d.ask:
			s += "• " + _esc(String(q)) + "\n"
	return s

func _show_info_id(id: String, fallback: String, b: Dictionary) -> void:
	var d: Dictionary = data.info.get(id, {})
	var title := String(d.get("title", fallback)).trim_suffix(" ?")
	var body := _info_body(d)
	if not b.is_empty() and String(b.id) == id:
		if b.get("h") != null:
			body += "\nВысота ≈ %s м" % f1(float(b.h))
		if b.get("src") != null:
			body += "\n[color=#a8b0b8]Источник: %s[/color]" % _esc(String(b.src))
	elif not b.is_empty():
		body += "\n[color=#a8b0b8]%s[/color]" % _esc(String(b.name))
	if not b.is_empty() and String(b.id) == id and not bool(b.get("locked", false)):
		body += "\n\n[url=in:%s][color=#f5a54a]▸ Заглянуть внутрь[/color][/url]" % id
	if body == "":
		body = "Пока без описания."
	ui.show_info(title, body)

func _show_station(id: String) -> void:
	var n: Dictionary = sim.nodes[id]
	var s := ""
	if n.kind == "proc":
		var cap := float(n.posts) * float(sim.p.shift_h) * 60.0 / maxf(float(n.cycle), 0.1)
		s += "[b]Постов:[/b] %d · [b]минут на раму:[/b] %s (условно)\n" % [n.posts, f1(float(n.cycle))]
		s += "[b]Пропускает:[/b] %s рам за смену\n" % f1(cap)
		s += "[b]Сейчас:[/b] в работе %d, ждут %d, загрузка %d%%\n" % [n.busy.size(), n.queue.size(), int(round(sim.util(id) * 100.0))]
	elif n.kind == "buf":
		s += "[b]Ждут:[/b] %d рам\n" % n.queue.size()
	else:
		s += "[b]Готово к отправке:[/b] %d · всего вышло %d\n" % [n.queue.size(), sim.done_total]
	var d: Dictionary = data.info.get(id, {})
	if not d.is_empty():
		s += "\n" + _info_body(d)
	s += "\n[color=#a8b0b8]В реальном времени: %s[/color]" % _live_source(id)
	ui.show_info("%s %s" % [n.num, n.name], s)

func _live_source(id: String) -> String:
	match id:
		"cut", "weld":
			return "сменное задание партией и датчики тока на станках (работает или простой). Метки на металл не клеим."
		"waitSand", "sand", "paint":
			return "камера по зоне: рама въехала и выехала. До покраски на раме никаких меток, пескоструй всё снимает."
		"distrib":
			return "камера по зоне: сколько окрашенных рам ждёт."
		"asm1", "asm2":
			return "VIN или шильдик читает камера на входе в сборку, людей на постах считает камера."
		"ship1":
			return "VIN читает камера на отгрузке, остатки сверяются с 1С."
	return "камеры по зонам"

func _show_cam(d: Dictionary) -> void:
	var s := "%s\n\n" % _esc(String(d.note))
	if d.kind == "ip":
		s += "[b]Тип:[/b] IP-камера, поток RTSP можно брать напрямую.\n"
	else:
		s += "[b]Тип:[/b] аналоговая, идёт через регистратор, поток RTSP берём с него.\n"
	s += "[b]Для двойника:[/b] сколько людей и прицепов в зоне, въехала или выехала рама. Для чтения VIN этого мало: нужна новая IP-камера на входе в сборку и на отгрузке.\n"
	s += "[color=#a8b0b8]Фото %s (в реестре, в открытую версию не кладём). Место на модели примерное.[/color]" % String(d.photo)
	ui.show_info(String(d.name), s)

# ---------- ссылка на вид ----------
func _read_url() -> void:
	if not OS.has_feature("web"):
		if args.has("live"):
			state.connect_live(args["live"])
		return
	var q := String(JavaScriptBridge.eval("location.search", true))
	var h := String(JavaScriptBridge.eval("decodeURIComponent(location.hash)", true)).trim_prefix("#")
	for kv in q.trim_prefix("?").split("&", false):
		var p := kv.split("=", true, 1)
		if p[0] == "live" and p.size() > 1:
			state.connect_live(p[1].uri_decode())
	if h == "":
		view_overview()
	elif h == "top":
		view_top()
	elif h.begins_with("v="):
		cam_rig.set_view_str(h.substr(2))
	elif h.begins_with("IMG_"):
		for i in data.viewpoints.size():
			if String(data.viewpoints[i].photo) == h:
				show_photo_point(i)
				break
	elif h.begins_with("photo"):
		show_photo_point(int(h.substr(5)))
	last_hash = h

func _write_url() -> void:
	if not OS.has_feature("web"):
		return
	var h := ""
	if current_vp >= 0:
		h = String(data.viewpoints[current_vp].photo)
	elif cam_rig.mode == "top":
		h = "top"
	elif cam_rig.mode == "orbit":
		h = "v=" + cam_rig.view_str()
	if h == "" or h == last_hash:
		return
	last_hash = h
	JavaScriptBridge.eval("history.replaceState(null,'','#%s')" % h, true)

func _process(dt: float) -> void:
	if cam_rig:
		_update_roofs()
		if ui and (cam_rig.mode == "walk") != overlay_walk:
			_apply_layers()
	if hash_t > 0.0:
		hash_t -= dt
		if hash_t <= 0.0:
			_write_url()
	if shot_path != "":
		shot_frames -= 1
		if shot_frames <= 0:
			var img := get_viewport().get_texture().get_image()
			var p := shot_path
			if shot_views.size() > 0:
				p = shot_path + "_%d.png" % shot_i
			else:
				p = shot_path + ".png"
			img.save_png(p)
			print("shot saved ", p)
			shot_i += 1
			if shot_i < shot_views.size():
				_next_view()
				shot_frames = 12
			else:
				shot_path = ""
				get_tree().quit()
