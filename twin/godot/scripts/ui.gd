extends CanvasLayer
## Интерфейс двойника: шапка с живыми цифрами, кнопки слоёв и видов, панель «Путь рамы», карточка,
## окна «Параметры», «Пути развития», «Точки фото», «Зачем это», панель планировщика.

var main: Node
var top_label: Label
var src_label: Label
var steps_box: VBoxContainer
var step_rows := {}
var info_panel: PanelContainer
var info_title: Label
var info_text: RichTextLabel
var dialogs := {}
var btn := {}
var planner_panel: PanelContainer
var planner_info: Label
var metrics_label: RichTextLabel
var variants_list: ItemList
var variant_name: LineEdit
var hint: Label
var speed_btns := {}
var photo_list: ItemList
var photo_bar: PanelContainer
var photo_title: Label
var t_up := 0.0
var run_btn: Button
var top_panel: PanelContainer
var left_panel: PanelContainer
var folded_auto := false
var ui_root: Control

const BG := Color(0.09, 0.10, 0.11, 0.86)
const ACC := Color(0.98, 0.62, 0.18)

func _ready() -> void:
	layer = 5

func _style(c: Color = BG, r := 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.corner_radius_top_left = r
	s.corner_radius_top_right = r
	s.corner_radius_bottom_left = r
	s.corner_radius_bottom_right = r
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s

func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _style())
	return p

func _btn(text: String, cb: Callable, toggle := false, tip := "") -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = toggle
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tip
	b.add_theme_font_size_override("font_size", 15)
	var n := _style(Color(0.18, 0.19, 0.21, 0.95), 6)
	n.content_margin_left = 9
	n.content_margin_right = 9
	n.content_margin_top = 5
	n.content_margin_bottom = 5
	var h := n.duplicate()
	h.bg_color = Color(0.26, 0.27, 0.30, 0.95)
	var pr := n.duplicate()
	pr.bg_color = Color(0.55, 0.33, 0.08, 0.95)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", pr)
	b.add_theme_stylebox_override("hover_pressed", pr)
	if toggle:
		b.toggled.connect(func(on): cb.call(on))
	else:
		b.pressed.connect(cb)
	return b

func _lbl(t: String, size := 15, col := Color(0.92, 0.93, 0.94)) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func build(m: Node) -> void:
	main = m
	var root := Control.new()
	ui_root = root
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	# ---------- шапка ----------
	var top := _panel()
	top_panel = top
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 8
	top.offset_right = -8
	top.offset_top = 8
	root.add_child(top)
	var tv := VBoxContainer.new()
	top.add_child(tv)
	var th := HBoxContainer.new()
	tv.add_child(th)
	var title := _lbl("Завод «Аляска» · цифровой двойник", 18, Color(1, 1, 1))
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	th.add_child(title)
	src_label = _lbl("  ● симуляция", 14, ACC)
	src_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	src_label.tooltip_text = "Цифры сейчас от симуляции с условными временами. Живые данные — камеры, датчики тока, 1С — подключаются тем же потоком событий"
	src_label.mouse_filter = Control.MOUSE_FILTER_PASS
	th.add_child(src_label)
	top_label = _lbl("", 14, Color(0.85, 0.88, 0.9))
	tv.add_child(top_label)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 5)
	flow.add_theme_constant_override("v_separation", 5)
	tv.add_child(flow)
	for spec in [
		["obzor", "Обзор", func(): main.view_overview(), false, "Общий вид завода"],
		["top", "Сверху", func(): main.view_top(), false, "Вид сверху, север вверх, как на 2ГИС"],
		["walk", "С земли", func(): main.view_walk(), false, "Пройтись по двору на высоте глаз: WASD или стрелки, мышь — оглядеться"],
		["photos", "Точки фото", func(): toggle_dialog("photos"), false, "99 точек, откуда сняты фото и кадры видео"],
		["roof", "Крыши: авто", func(): main.cycle_roofs(), false, "Авто — пропадают при приближении; сняты; на месте"],
		["zones", "Зоны", func(on): main.set_zones(on), true, "Цветные зоны плана Excel"],
		["flows", "Потоки", func(on): main.set_flows(on), true, "Маршруты рам и кары с рамами"],
		["cams", "Камеры", func(on): main.set_cams(on), true, "Камеры наблюдения, которые уже висят (места примерные)"],
		["labels", "Подписи", func(on): main.set_labels(on), true, "Названия участков и мест"],
		["people", "Люди", func(on): main.set_people(on), true, "Рабочие на местах"],
		["weather", "Погода: как на фото", func(): main.toggle_weather(), false, "Пасмурно, как 26.10, или ясный день"],
		["plan", "Планировщик", func(on): main.set_planner(on), true, "Двигать участки, точки маршрута, здания и ставить предметы — цифры пересчитываются"],
		["ways", "Пути развития", func(): toggle_dialog("ways"), false, "Что будет, если: второй пост, две смены, сборка в новом цехе"],
		["why", "Зачем это?", func(): toggle_dialog("why"), false, "Зачем собственнику цифровая копия завода"],
	]:
		var b := _btn(spec[1], spec[2], spec[3], spec[4])
		btn[spec[0]] = b
		flow.add_child(b)
	for k in ["flows", "cams", "labels", "people"]:
		btn[k].set_pressed_no_signal(true)
	# ---------- путь рамы ----------
	var left := _panel()
	left_panel = left
	left.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	left.anchor_top = 1.0
	left.anchor_bottom = 1.0
	left.offset_left = 8
	left.offset_bottom = -8
	left.grow_vertical = Control.GROW_DIRECTION_BEGIN
	left.custom_minimum_size = Vector2(330, 0)
	root.add_child(left)
	var lv := VBoxContainer.new()
	left.add_child(lv)
	var lh := HBoxContainer.new()
	lv.add_child(lh)
	var lt := _lbl("Путь рамы", 17, Color(1, 1, 1))
	lt.autowrap_mode = TextServer.AUTOWRAP_OFF
	lh.add_child(lt)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lh.add_child(sp)
	var fold := _btn("▾", func(): steps_box.visible = not steps_box.visible)
	lh.add_child(fold)
	steps_box = VBoxContainer.new()
	lv.add_child(steps_box)
	for id in main.sim.order:
		var n: Dictionary = main.sim.nodes[id]
		var b := Button.new()
		b.flat = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 14)
		b.text = "%s  %s" % [n.num, n.name]
		b.pressed.connect(func(): main.focus_station(id))
		steps_box.add_child(b)
		step_rows[id] = b
	var sim_h := HBoxContainer.new()
	steps_box.add_child(sim_h)
	run_btn = _btn("Пауза", func(): main.toggle_run(), false, "Пауза / пуск симуляции")
	sim_h.add_child(run_btn)
	for s in [[10.0, "×10"], [60.0, "×60"], [600.0, "×600"]]:
		var sb := _btn(s[1], func(): main.set_speed(s[0]), false, "Скорость модели: ×60 — минута за секунду")
		speed_btns[s[0]] = sb
		sim_h.add_child(sb)
	sim_h.add_child(_btn("Сброс", func(): main.reset_sim()))
	sim_h.add_child(_btn("Параметры", func(): toggle_dialog("params"), false, "Посты и времена операций"))
	steps_box.add_child(_lbl("Времена операций условные — впишите свои в «Параметры».", 12, Color(0.75, 0.75, 0.7)))
	# ---------- карточка ----------
	info_panel = _panel()
	info_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	info_panel.anchor_left = 1.0
	info_panel.offset_left = -390
	info_panel.offset_right = -8
	info_panel.offset_top = 150
	info_panel.custom_minimum_size = Vector2(380, 0)
	info_panel.visible = false
	root.add_child(info_panel)
	var iv := VBoxContainer.new()
	info_panel.add_child(iv)
	var ih := HBoxContainer.new()
	iv.add_child(ih)
	info_title = _lbl("", 17, Color(1, 1, 1))
	info_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ih.add_child(info_title)
	ih.add_child(_btn("×", func(): info_panel.visible = false))
	info_text = RichTextLabel.new()
	info_text.bbcode_enabled = true
	info_text.fit_content = true
	info_text.custom_minimum_size = Vector2(360, 0)
	info_text.add_theme_font_size_override("normal_font_size", 14)
	info_text.add_theme_font_size_override("bold_font_size", 14)
	iv.add_child(info_text)
	# ---------- подсказка ----------
	hint = _lbl("", 13, Color(0.9, 0.9, 0.85))
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.anchor_left = 0.5
	hint.anchor_right = 0.5
	hint.offset_left = -260
	hint.offset_right = 260
	hint.offset_top = -40
	hint.offset_bottom = -10
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	hint.add_theme_constant_override("outline_size", 6)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hint)
	set_hint("Мышь: тянуть — двигать карту, правая или Shift — повернуть, колесо — приблизить. Нажмите на цех, участок или камеру.")
	_build_dialogs(root)
	_build_planner(root)
	_build_photo_bar(root)

func set_hint(t: String) -> void:
	hint.text = t

# ---------- окна ----------
func _dialog(id: String, title: String, root: Control, w := 560.0) -> VBoxContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _style(Color(0.09, 0.10, 0.11, 0.96)))
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.anchor_left = 0.5
	p.anchor_right = 0.5
	p.anchor_top = 0.5
	p.anchor_bottom = 0.5
	p.offset_left = -w / 2
	p.offset_right = w / 2
	p.offset_top = -280
	p.offset_bottom = 280
	p.set_meta("w", w)
	p.visible = false
	root.add_child(p)
	var v := VBoxContainer.new()
	p.add_child(v)
	var h := HBoxContainer.new()
	v.add_child(h)
	var t := _lbl(title, 18, Color(1, 1, 1))
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)
	h.add_child(_btn("×", func(): p.visible = false))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(body)
	dialogs[id] = p
	return body

func toggle_dialog(id: String) -> void:
	for k in dialogs:
		if k != id:
			dialogs[k].visible = false
	dialogs[id].visible = not dialogs[id].visible
	if id == "ways" and dialogs[id].visible:
		refresh_ways()

func _rich(text: String, size := 14) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.text = text
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return r

var ways_result: RichTextLabel
var param_spins := {}

func _build_dialogs(root: Control) -> void:
	# Зачем это
	var why := _dialog("why", "Зачем собственнику цифровая копия завода", root, 640)
	why.add_child(_rich(main.CONCEPT))
	# Параметры
	var pr := _dialog("params", "Параметры потока (условные — впишите свои)", root, 560)
	var g := GridContainer.new()
	g.columns = 3
	pr.add_child(g)
	g.add_child(_lbl("Участок", 14, ACC))
	g.add_child(_lbl("Постов", 14, ACC))
	g.add_child(_lbl("Минут на раму", 14, ACC))
	for id in main.sim.order:
		var n: Dictionary = main.sim.nodes[id]
		if n.kind != "proc":
			continue
		g.add_child(_lbl("%s %s" % [n.num, n.name], 14))
		var a := SpinBox.new()
		a.min_value = 0
		a.max_value = 20
		a.value = n.posts
		a.value_changed.connect(func(v): main.set_param(id, "posts", v))
		g.add_child(a)
		var c := SpinBox.new()
		c.min_value = 1
		c.max_value = 2000
		c.step = 1
		c.value = n.cycle
		c.value_changed.connect(func(v): main.set_param(id, "cycle", v))
		g.add_child(c)
		param_spins[id] = [a, c]
	var g2 := GridContainer.new()
	g2.columns = 2
	pr.add_child(g2)
	for spec in [["plan", "План запуска, рам за смену", 0, 200, 1], ["shift_h", "Часов в смене", 1, 24, 0.5],
			["v_kara", "Скорость кары, м/с", 0.3, 5, 0.1], ["handle_s", "Погрузка-выгрузка, сек", 0, 1800, 10]]:
		g2.add_child(_lbl(spec[1], 14))
		var s := SpinBox.new()
		s.min_value = spec[2]
		s.max_value = spec[3]
		s.step = spec[4]
		s.value = main.sim.p[spec[0]]
		var key: String = spec[0]
		s.value_changed.connect(func(v): main.set_global(key, v))
		g2.add_child(s)
		param_spins[key] = [s]
	pr.add_child(_lbl("Ни одной цифры с завода пока нет: здесь подставлены условные, чтобы показать, как работает расчёт. Пришлите реальные времена — и модель покажет настоящее узкое место.", 13, Color(0.8, 0.8, 0.75)))
	# Пути развития
	var w := _dialog("ways", "Пути развития: что будет, если…", root, 640)
	ways_result = _rich("")
	w.add_child(ways_result)
	w.add_child(_lbl("Каждый вариант меняет посты, план или места участков. Пропускная способность считается по постам и временам из «Параметров» (сейчас условным), пробег рамы — по маршрутам на плане. «Показать» прогоняет модель на одну смену.", 13, Color(0.82, 0.82, 0.78)))
	for sc in main.SCENARIOS:
		var row := VBoxContainer.new()
		w.add_child(row)
		var h := HBoxContainer.new()
		row.add_child(h)
		var t := _lbl(sc.name, 15, Color(1, 1, 1))
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(t)
		var sid: String = sc.id
		h.add_child(_btn("Показать", func(): main.apply_scenario(sid)))
		row.add_child(_lbl(sc.text, 13, Color(0.8, 0.82, 0.84)))
	# Точки фото
	var ph := _dialog("photos", "Точки фото: откуда сняты кадры", root, 560)
	ph.add_child(_lbl("Камера встаёт туда, где стоял человек с телефоном, с тем же объективом. Фото в открытую версию не кладём — сравнивайте со своими снимками.", 13, Color(0.8, 0.8, 0.78)))
	photo_list = ItemList.new()
	photo_list.custom_minimum_size = Vector2(500, 380)
	photo_list.add_theme_font_size_override("font_size", 14)
	for i in main.data.viewpoints.size():
		var v: Dictionary = main.data.viewpoints[i]
		photo_list.add_item("%d · %s · %s" % [i, v.photo, v.title])
	photo_list.item_selected.connect(func(i): main.show_photo_point(i); dialogs["photos"].visible = false)
	ph.add_child(photo_list)

func refresh_ways() -> void:
	ways_result.text = main.metrics_text(true)

# ---------- полоса вида с фото ----------
func _build_photo_bar(root: Control) -> void:
	photo_bar = _panel()
	photo_bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	photo_bar.anchor_left = 0.5
	photo_bar.anchor_right = 0.5
	photo_bar.offset_left = -300
	photo_bar.offset_right = 300
	photo_bar.offset_top = 150
	photo_bar.visible = false
	root.add_child(photo_bar)
	var h := HBoxContainer.new()
	photo_bar.add_child(h)
	h.add_child(_btn("◀", func(): main.show_photo_point(main.current_vp - 1)))
	photo_title = _lbl("", 14)
	photo_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(photo_title)
	h.add_child(_btn("▶", func(): main.show_photo_point(main.current_vp + 1)))
	h.add_child(_btn("Выйти", func(): main.view_overview()))

func show_photo_bar(i: int) -> void:
	if i < 0:
		photo_bar.visible = false
		return
	var v: Dictionary = main.data.viewpoints[i]
	photo_title.text = "%s · %s · %s" % [v.photo, v.time, v.title]
	photo_bar.visible = true

# ---------- планировщик ----------
func _build_planner(root: Control) -> void:
	planner_panel = _panel()
	planner_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	planner_panel.anchor_left = 1.0
	planner_panel.offset_left = -390
	planner_panel.offset_right = -8
	planner_panel.offset_top = 150
	planner_panel.custom_minimum_size = Vector2(380, 0)
	planner_panel.visible = false
	root.add_child(planner_panel)
	var v := VBoxContainer.new()
	planner_panel.add_child(v)
	v.add_child(_lbl("Планировщик", 17, Color(1, 1, 1)))
	v.add_child(_lbl("Тяните мышью жёлтые столбы участков, оранжевые точки маршрута, здания и поставленные предметы. R — повернуть, Delete — убрать, Ctrl+Z — отменить.", 13, Color(0.82, 0.82, 0.8)))
	var add := HFlowContainer.new()
	add.add_theme_constant_override("h_separation", 4)
	add.add_theme_constant_override("v_separation", 4)
	v.add_child(add)
	for spec in main.planner.CATALOG:
		var k: String = spec[0]
		add.add_child(_btn("+ " + spec[1], func(): main.planner.add_prop(k)))
	planner_info = _lbl("Ничего не выбрано", 14, ACC)
	v.add_child(planner_info)
	var tools := HFlowContainer.new()
	tools.add_theme_constant_override("h_separation", 4)
	v.add_child(tools)
	tools.add_child(_btn("Повернуть", func(): main.planner.rotate_sel(15.0)))
	tools.add_child(_btn("Убрать", func(): main.planner.delete_sel()))
	tools.add_child(_btn("Отменить", func(): main.planner.undo()))
	tools.add_child(_btn("Линейка", func(on): main.planner.set_ruler(on), true, "Две точки на земле — расстояние в метрах"))
	tools.add_child(_btn("Всё как есть", func(): main.planner.reset_all()))
	metrics_label = _rich("", 13)
	v.add_child(metrics_label)
	v.add_child(_lbl("Варианты", 15, Color(1, 1, 1)))
	var vh := HBoxContainer.new()
	v.add_child(vh)
	variant_name = LineEdit.new()
	variant_name.placeholder_text = "Название варианта"
	variant_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vh.add_child(variant_name)
	vh.add_child(_btn("Сохранить", func(): main.planner.save_variant(variant_name.text)))
	variants_list = ItemList.new()
	variants_list.custom_minimum_size = Vector2(0, 90)
	v.add_child(variants_list)
	var vb := HFlowContainer.new()
	v.add_child(vb)
	vb.add_child(_btn("Открыть", func(): main.planner.load_selected()))
	vb.add_child(_btn("Удалить", func(): main.planner.delete_selected()))
	vb.add_child(_btn("Скачать файл", func(): main.planner.export_variant()))
	vb.add_child(_btn("Загрузить файл", func(): main.planner.import_variant()))

## Маленький экран (телефон, узкое окно): «Путь рамы» свёрнут, карточки — под шапкой и во всю ширину.
func _layout() -> void:
	var vs := ui_root.size
	if not folded_auto and (vs.y < 760.0 or vs.x < 900.0):
		folded_auto = true
		steps_box.visible = false
	var y := top_panel.size.y + 16.0
	var narrow := vs.x < 820.0
	for p in [info_panel, planner_panel]:
		p.offset_top = y
		if narrow:
			p.offset_left = -vs.x + 16.0
			p.custom_minimum_size.x = 0.0
			info_text.custom_minimum_size.x = 0.0
	photo_bar.offset_top = y
	if narrow:
		photo_bar.offset_left = -vs.x * 0.5 + 8.0
		photo_bar.offset_right = vs.x * 0.5 - 8.0
	for k in dialogs:
		var d: PanelContainer = dialogs[k]
		var w := minf(float(d.get_meta("w", 600.0)), vs.x - 16.0)
		d.offset_left = -w / 2.0
		d.offset_right = w / 2.0
		var h := minf(560.0, vs.y - y - 16.0)
		d.offset_top = -h / 2.0 + (y - 8.0) / 2.0
		d.offset_bottom = h / 2.0 + (y - 8.0) / 2.0

func refresh_variants(names: Array) -> void:
	variants_list.clear()
	for n in names:
		variants_list.add_item(String(n))

# ---------- карточка и цифры ----------
func show_info(title: String, body: String) -> void:
	info_title.text = title
	info_text.text = body
	info_panel.visible = true
	if planner_panel.visible:
		info_panel.visible = false
		planner_info.text = title

func _process(dt: float) -> void:
	if main == null:
		return
	t_up -= dt
	if t_up > 0.0:
		return
	t_up = 0.4
	_layout()
	top_label.text = main.top_text()
	src_label.text = "  ● " + ("живые данные" if main.state.source == "live" else "симуляция")
	for id in step_rows:
		var n: Dictionary = main.sim.nodes[id]
		var t := "%s  %s" % [n.num, n.name]
		if n.kind == "proc":
			t += " — %d/%d, очередь %d" % [n.busy.size(), n.posts, n.queue.size()]
			var u: float = main.sim.util(id)
			step_rows[id].add_theme_color_override("font_color", Color(1, 0.45, 0.4) if u > 0.92 else (Color(1, 0.85, 0.35) if u > 0.75 else Color(0.85, 0.95, 0.85)))
		elif n.kind == "buf":
			t += " — ждут %d" % n.queue.size()
		else:
			t += " — %d готово" % main.sim.done_total
		step_rows[id].text = t
	if planner_panel.visible:
		metrics_label.text = main.metrics_text(false)
