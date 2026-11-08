extends RefCounted
## Библиотека материалов двойника. Цвет берётся из цвета вершин (как в сверенной игре),
## поверх — бесшовные текстуры в реальных метрах, наложенные трипланарно по мировым координатам.

const T := "res://textures/"

static var cache := {}

static func _tex(n: String) -> Texture2D:
	if n == "":
		return null
	return load(T + n + ".png")

static func _mk(alb: String, nrm: String, rgh: String, tile: Vector3, rough := 0.85, metal := 0.0, nscale := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.albedo_color = Color(1.12, 1.12, 1.12)
	if alb != "":
		m.albedo_texture = _tex(alb)
	if nrm != "":
		m.normal_enabled = true
		m.normal_texture = _tex(nrm)
		m.normal_scale = nscale
	if rgh != "":
		m.roughness_texture = _tex(rgh)
	m.roughness = rough
	m.metallic = metal
	m.metallic_specular = 0.4
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_triplanar_sharpness = 6.0
	m.uv1_scale = Vector3(1.0 / tile.x, 1.0 / tile.y, 1.0 / tile.z)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m

static func get_mat(cls: String) -> Material:
	if cache.has(cls):
		return cache[cls]
	var m: StandardMaterial3D
	match cls:
		"corr":
			m = _mk("corr_albedo", "corr_normal", "corr_rough", Vector3(1, 1, 1), 0.65, 0.15, 0.8)
		"corr_z":
			m = _mk("corrz_albedo", "corrz_normal", "corr_rough", Vector3(1, 1, 1), 0.65, 0.15, 0.8)
		"brick":
			m = _mk("brick_albedo", "brick_normal", "brick_rough", Vector3(1.04, 0.75, 1.04), 0.9)
		"panel":
			m = _mk("panel_albedo", "panel_normal", "panel_rough", Vector3(6, 1.2, 6), 0.9)
		"slab":
			m = _mk("slab_albedo", "slab_normal", "slab_rough", Vector3(6, 2, 2), 0.88)
			m.albedo_color = Color(0.95, 0.95, 0.95)
		"floor":
			m = _mk("slab_albedo", "", "slab_rough", Vector3(12, 4, 8), 0.7)
		"asphalt":
			m = _mk("asphalt_albedo", "asphalt_normal", "asphalt_rough", Vector3(4, 4, 4), 0.92)
		"dirt":
			m = _mk("dirt_albedo", "dirt_normal", "", Vector3(4, 4, 4), 0.97)
		"grass":
			m = _mk("grass_albedo", "grass_normal", "", Vector3(4, 4, 4), 0.95)
		"terrain":
			m = _mk("grass_albedo", "dirt_normal", "", Vector3(7, 7, 7), 0.97)
		"zone", "zoneline":
			var z := StandardMaterial3D.new()
			z.vertex_color_use_as_albedo = true
			z.vertex_color_is_srgb = true
			z.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			z.albedo_color = Color(1, 1, 1, 0.0)
			z.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			z.render_priority = 1
			cache[cls] = z
			return z
		"line":
			m = _mk("", "", "", Vector3(1, 1, 1), 0.6)
		"galv":
			m = _mk("galv_albedo", "", "galv_rough", Vector3(1, 1, 1), 0.4, 0.65)
		"rust":
			m = _mk("rust_albedo", "rust_normal", "", Vector3(2, 2, 2), 0.9, 0.1)
		"wood":
			m = _mk("wood_albedo", "", "", Vector3(1, 1, 1), 0.85)
		"cloth":
			m = _mk("fabric_albedo", "", "", Vector3(0.5, 0.5, 0.5), 0.95)
		_:
			m = _mk("metal_albedo", "metal_normal", "metal_rough", Vector3(2, 2, 2), 0.6, 0.2, 0.5)
	cache[cls] = m
	return m

## Слой «Зоны»: цветные плашки зон и белые рамки разметки старой игры (на фото их нет — по умолчанию скрыты)
static func set_zones_visible(v: bool) -> void:
	for k in ["zone", "zoneline"]:
		var m: StandardMaterial3D = get_mat(k)
		m.albedo_color = Color(1, 1, 1, (0.42 if k == "zone" else 0.85) if v else 0.0)

## Заменить материалы импортированной сцены по именам классов из Blender (M_corr, M_slab…).
static func apply(root: Node) -> Dictionary:
	var stats := {}
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var mesh := mi.mesh
		if mesh == null:
			continue
		for s in mesh.get_surface_count():
			var om := mesh.surface_get_material(s)
			var nm := om.resource_name if om else ""
			if nm.begins_with("M_"):
				var cls := nm.substr(2)
				mi.set_surface_override_material(s, get_mat(cls))
				stats[cls] = stats.get(cls, 0) + 1
			elif nm.begins_with("K_glass") and om is StandardMaterial3D:
				var g: StandardMaterial3D = (om as StandardMaterial3D).duplicate()
				g.vertex_color_use_as_albedo = true
				g.vertex_color_is_srgb = true
				g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				g.roughness = 0.08
				g.metallic = 0.3
				g.metallic_specular = 0.8
				mi.set_surface_override_material(s, g)
				stats["glass"] = stats.get("glass", 0) + 1
			elif om is StandardMaterial3D:
				var k: StandardMaterial3D = (om as StandardMaterial3D).duplicate()
				k.vertex_color_is_srgb = true
				mi.set_surface_override_material(s, k)
				stats["keep"] = stats.get("keep", 0) + 1
	return stats
