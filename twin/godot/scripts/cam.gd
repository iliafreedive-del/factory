extends Node3D
## Камера: облёт вокруг точки (мышь, колесо, пальцы, клавиши), вид сверху и вид с земли (рост 1,6 м).
## Положение: tx, tz — точка на плане (м), az — поворот, el — наклон, dist — расстояние.

signal moved

var cam: Camera3D
var tx := 20.0
var tz := 40.0
var az := 0.62
var el := 0.62
var dist := 260.0
var t := {}            # цель для плавного перехода
var mode := "orbit"     # orbit | top | walk
var walk_yaw := 0.0
var walk_pitch := 0.0
var walk_pos := Vector3.ZERO
var fov_walk := 72.0
var drag_btn := -1
var touches := {}
var last_pinch := 0.0
var last_ang := 0.0
var blocked := false    # когда планировщик тащит предмет

const MIN_D := 6.0
const MAX_D := 900.0

func _ready() -> void:
	cam = Camera3D.new()
	cam.fov = 40.0
	cam.near = 0.15
	cam.far = 4000.0
	add_child(cam)
	cam.current = true
	_sync_t()
	_apply(1.0)

func _sync_t() -> void:
	t = {"tx": tx, "tz": tz, "az": az, "el": el, "dist": dist}

func set_view(ntx: float, ntz: float, naz: float, nel: float, nd: float, instant := false) -> void:
	mode = "orbit"
	t = {"tx": ntx, "tz": ntz, "az": naz, "el": clampf(nel, 0.05, 1.55), "dist": clampf(nd, MIN_D, MAX_D)}
	if instant:
		tx = ntx; tz = ntz; az = naz; el = t.el; dist = t.dist
	cam.fov = 40.0

func set_view_str(s: String) -> void:
	var p := s.split(",")
	if p.size() >= 5:
		set_view(float(p[0]), float(p[1]), float(p[2]), float(p[3]), float(p[4]), true)
		_apply(1.0)

func view_str() -> String:
	if mode == "walk":
		return "w%.1f,%.1f,%.3f,%.3f,%.0f" % [walk_pos.x, walk_pos.z, walk_yaw, walk_pitch, fov_walk]
	return "%.1f,%.1f,%.3f,%.3f,%.1f" % [tx, tz, az, el, dist]

func set_top(on: bool) -> void:
	if on:
		mode = "top"
		# вид сверху, повёрнутый на север вверх (как на 2ГИС): ось z плана смотрит на 165°
		t.az = deg_to_rad(-15.0) + PI
		t.el = 1.5
		t.dist = maxf(t.dist, 420.0)
	else:
		mode = "orbit"
		t.el = 0.62

## Вид с земли: камера на высоте 1,6 м, смотрит в точку look (метры плана), объектив по фокусу.
func set_walk(pos: Vector2, look: Vector2, f35 := 24.0, h := 1.6) -> void:
	mode = "walk"
	walk_pos = Vector3(pos.x, h, pos.y)
	var d := look - pos
	walk_yaw = atan2(-d.x, -d.y)
	walk_pitch = 0.0
	# горизонтальный угол объектива 35 мм-экв. → вертикальный FOV при текущем соотношении сторон
	var hfov := 2.0 * atan(36.0 / (2.0 * f35))
	var asp := get_viewport().get_visible_rect().size.aspect()
	fov_walk = rad_to_deg(2.0 * atan(tan(hfov / 2.0) / asp))
	cam.fov = fov_walk
	_apply(1.0)

## Как в старой игре: горизонтальный угол 2·atan(17,3/f35), вертикальный — по соотношению сторон (не меньше 1)
func set_walk_photo(pos: Vector2, look: Vector2, f35: float, vfov: float, h: float, pitch_deg: float) -> void:
	mode = "walk"
	walk_pos = Vector3(pos.x, h, pos.y)
	var d := look - pos
	walk_yaw = atan2(-d.x, -d.y)
	walk_pitch = deg_to_rad(pitch_deg)
	var asp := get_viewport().get_visible_rect().size.aspect()
	if vfov > 0.0:
		fov_walk = vfov
	else:
		var hf := 2.0 * atan(17.3 / maxf(f35, 1.0))
		fov_walk = rad_to_deg(2.0 * atan(tan(hf / 2.0) / maxf(asp, 1.0)))
	cam.fov = fov_walk
	_apply(1.0)

func _process(dt: float) -> void:
	if mode == "walk":
		var mv := Vector3.ZERO
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): mv.z -= 1
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): mv.z += 1
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): mv.x -= 1
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): mv.x += 1
		if mv != Vector3.ZERO:
			var sp := 9.0 if Input.is_key_pressed(KEY_SHIFT) else 3.5
			walk_pos += Basis(Vector3.UP, walk_yaw) * mv.normalized() * sp * dt
			moved.emit()
	else:
		var pan := Vector2.ZERO
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): pan.y -= 1
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): pan.y += 1
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): pan.x -= 1
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): pan.x += 1
		if pan != Vector2.ZERO:
			_pan_world(pan * t.dist * 0.6 * dt)
		if Input.is_key_pressed(KEY_Q): t.az += 1.2 * dt
		if Input.is_key_pressed(KEY_E): t.az -= 1.2 * dt
	_apply(1.0 - exp(-dt * 10.0))

func _apply(k: float) -> void:
	if mode == "walk":
		cam.global_transform = Transform3D(Basis.from_euler(Vector3(walk_pitch, walk_yaw, 0.0)), walk_pos)
		return
	var prev := Vector3(tx, dist, tz)
	tx = lerpf(tx, t.tx, k)
	tz = lerpf(tz, t.tz, k)
	az = lerp_angle(az, t.az, k)
	el = lerpf(el, t.el, k)
	dist = exp(lerpf(log(dist), log(t.dist), k))
	var target := Vector3(tx, 0.0, tz)
	var off := Vector3(sin(az) * cos(el), sin(el), cos(az) * cos(el)) * dist
	cam.global_transform = Transform3D(Basis(), target + off).looking_at(target, Vector3.UP if el < 1.5 else Vector3(-sin(az), 0, -cos(az)))
	if prev.distance_to(Vector3(tx, dist, tz)) > 0.01:
		moved.emit()

func _pan_world(d: Vector2) -> void:
	var fwd := Vector2(-sin(t.az), -cos(t.az))
	var right := Vector2(cos(t.az), -sin(t.az))
	var w := right * d.x - fwd * d.y
	t.tx += w.x
	t.tz += w.y

func _unhandled_input(ev: InputEvent) -> void:
	if blocked:
		return
	# касания уже обрабатываются как ScreenTouch/ScreenDrag, их копии-«мышь» пропускаем
	if ev is InputEventMouse and ev.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom(0.88, mb.position)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom(1.0 / 0.88, mb.position)
		elif mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			drag_btn = mb.button_index if mb.pressed else -1
	elif ev is InputEventMouseMotion and drag_btn != -1:
		var mm := ev as InputEventMouseMotion
		if mode == "walk":
			walk_yaw -= mm.relative.x * 0.004
			walk_pitch = clampf(walk_pitch - mm.relative.y * 0.004, -1.3, 1.3)
			moved.emit()
		elif drag_btn == MOUSE_BUTTON_LEFT and not Input.is_key_pressed(KEY_SHIFT):
			var s: float = 2.0 * t.dist * tan(deg_to_rad(cam.fov) / 2.0) / get_viewport().get_visible_rect().size.y
			_pan_world(-mm.relative * s * Vector2(1, 1.0 / maxf(sin(el), 0.35)))
		else:
			t.az -= mm.relative.x * 0.006
			if mode != "top":
				t.el = clampf(t.el + mm.relative.y * 0.004, 0.08, 1.5)
	elif ev is InputEventScreenTouch:
		var st := ev as InputEventScreenTouch
		if st.pressed:
			touches[st.index] = st.position
		else:
			touches.erase(st.index)
		last_pinch = 0.0
	elif ev is InputEventScreenDrag:
		var sd := ev as InputEventScreenDrag
		touches[sd.index] = sd.position
		if touches.size() == 1:
			if mode == "walk":
				walk_yaw -= sd.relative.x * 0.005
				walk_pitch = clampf(walk_pitch - sd.relative.y * 0.005, -1.3, 1.3)
				moved.emit()
			else:
				var s: float = 2.0 * t.dist * tan(deg_to_rad(cam.fov) / 2.0) / get_viewport().get_visible_rect().size.y
				_pan_world(-sd.relative * s * Vector2(1, 1.0 / maxf(sin(el), 0.35)))
		elif touches.size() == 2:
			var ks := touches.keys()
			var a: Vector2 = touches[ks[0]]
			var b: Vector2 = touches[ks[1]]
			var d := a.distance_to(b)
			var ang := (b - a).angle()
			if last_pinch > 0.0:
				if mode == "walk":
					walk_pos += Basis(Vector3.UP, walk_yaw) * Vector3(0, 0, -(d - last_pinch) * 0.05)
				else:
					t.dist = clampf(t.dist * last_pinch / d, MIN_D, MAX_D)
					t.az += wrapf(ang - last_ang, -PI, PI)
					if mode != "top":
						t.el = clampf(t.el - sd.relative.y * 0.002, 0.08, 1.5)
			last_pinch = d
			last_ang = ang

func _zoom(f: float, at: Vector2) -> void:
	if mode == "walk":
		walk_pos += Basis(Vector3.UP, walk_yaw) * Vector3(0, 0, -2.0 if f < 1.0 else 2.0)
		moved.emit()
		return
	# приближение к точке под курсором
	var hit = ground_at(at)
	var nd := clampf(t.dist * f, MIN_D, MAX_D)
	if hit != null:
		var k: float = 1.0 - nd / t.dist
		t.tx += (hit.x - t.tx) * k
		t.tz += (hit.z - t.tz) * k
	t.dist = nd

func ground_at(screen: Vector2, y := 0.0):
	var o := cam.project_ray_origin(screen)
	var d := cam.project_ray_normal(screen)
	if absf(d.y) < 1e-5:
		return null
	var k := (y - o.y) / d.y
	if k < 0:
		return null
	return o + d * k
