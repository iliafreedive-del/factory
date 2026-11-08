shader_type sky;
// Пасмурное небо как на фото 26.10: серые слоистые облака, светлый горизонт. Для «солнца» — ясное небо с редкими облаками.
uniform vec3 top_col : source_color = vec3(0.50, 0.53, 0.57);
uniform vec3 hor_col : source_color = vec3(0.80, 0.81, 0.82);
uniform vec3 cloud_lit : source_color = vec3(0.86, 0.87, 0.88);
uniform vec3 cloud_dark : source_color = vec3(0.44, 0.46, 0.49);
uniform float cover = 0.62;
uniform float energy = 1.0;

float hash(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p){
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p){
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 5; i++){ v += a * noise(p); p = p * 2.03 + vec2(1.7, 9.2); a *= 0.5; }
	return v;
}
void sky(){
	vec3 d = EYEDIR;
	float h = clamp(d.y, 0.0, 1.0);
	vec3 col = mix(hor_col, top_col, pow(h, 0.6));
	if (d.y > 0.0) {
		vec2 uv = d.xz / (d.y + 0.08) * 1.3;
		float n = fbm(uv + vec2(TIME * 0.004, 0.0));
		float n2 = fbm(uv * 2.7 + 3.1);
		float c = smoothstep(1.0 - cover, 1.0 - cover + 0.35, n * 0.75 + n2 * 0.35);
		float shade = smoothstep(0.25, 0.85, n2);
		vec3 cc = mix(cloud_dark, cloud_lit, shade);
		col = mix(col, cc, c * smoothstep(0.0, 0.12, d.y));
	} else {
		col = mix(hor_col * 0.85, vec3(0.32, 0.31, 0.29), clamp(-d.y * 3.0, 0.0, 1.0));
	}
	COLOR = col * energy;
}
