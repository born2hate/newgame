shader_type canvas_item;
// Постобработка мира (интерфейс не трогает): мягкое свечение ярких мест,
// кинематографичная цветокоррекция, лучи света сверху, размытые частицы
// на переднем плане (ощущение глубины резкости), лёгкая хроматика и виньетка.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float depth = 0.0;          // 0 — у поверхности, 1 — глубоко (лучи слабеют)
uniform vec2 cam_offset = vec2(0.0);
uniform float bloom = 0.45;
uniform float rays = 1.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

vec3 bright(vec2 uv) {
	vec3 c = texture(screen_tex, uv).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	return c * smoothstep(0.78, 1.0, l);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = SCREEN_PIXEL_SIZE;
	// лёгкая хроматика к краям — как у дорогой оптики
	vec2 dir = uv - 0.5;
	float edge = dot(dir, dir);
	vec3 col;
	col.r = texture(screen_tex, uv + dir * edge * 0.006).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - dir * edge * 0.006).b;

	// свечение: яркие места (окна, реактор, огонь, жемчуг) мягко светятся
	vec3 glow = vec3(0.0);
	float total = 0.0;
	for (int i = 0; i < 12; i++) {
		float a = float(i) * 0.5236;
		for (int r = 1; r <= 2; r++) {
			float rad = float(r) * 7.0;
			vec2 o = vec2(cos(a), sin(a)) * rad * px * 1.6;
			float w = 1.0 / float(r);
			glow += bright(uv + o) * w;
			total += w;
		}
	}
	col += glow / total * bloom * 1.6;

	// цветокоррекция: бирюзовые тени, тёплые света, чуть больше контраста и сочности
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	// тени чуть уводим в глубокий синий (не светлее!), света — в тёплый
	col = mix(col, col * vec3(0.86, 0.96, 1.08), 1.0 - smoothstep(0.0, 0.4, l));
	col += vec3(0.035, 0.018, -0.015) * smoothstep(0.55, 1.0, l);
	col = mix(vec3(l), col, 1.18);
	// S-кривая контраста
	col = clamp(col, 0.0, 1.2);
	col = col * col * (3.0 - 2.0 * col) * 0.35 + col * 0.65;

	// лучи света сверху — сквозь толщу воды
	float sx = uv.x + cam_offset.x * 0.00012 - uv.y * 0.18;
	float sh = pow(max(0.0, sin(sx * 7.0 + TIME * 0.17)), 14.0);
	sh += pow(max(0.0, sin(sx * 11.0 - TIME * 0.11 + 2.1)), 18.0) * 0.8;
	sh += pow(max(0.0, sin(sx * 4.3 + TIME * 0.07 + 4.0)), 22.0) * 0.6;
	float fade = (1.0 - uv.y) * (1.0 - uv.y) * (1.0 - depth * 0.9);
	col += vec3(0.55, 0.85, 0.95) * sh * fade * 0.16 * rays;

	// размытые частицы перед камерой (боке) — глубина кадра
	for (int i = 0; i < 2; i++) {
		float layer = float(i) + 1.0;
		vec2 sp = uv * vec2(3.0, 5.5) * layer + vec2(TIME * 0.012 * layer, -TIME * 0.025 * layer) + cam_offset * 0.0006 * layer;
		vec2 cell = floor(sp);
		vec2 f = fract(sp) - 0.5;
		float h = hash(cell + layer * 31.0);
		if (h > 0.86) {
			vec2 off = vec2(hash(cell + 1.7), hash(cell + 4.3)) - 0.5;
			float dd = length(f - off * 0.5);
			float r = mix(0.10, 0.18, hash(cell + 9.1)) / layer;
			float b = smoothstep(r, r * 0.55, dd) * (0.55 + 0.45 * sin(TIME * 0.8 + h * 40.0));
			col += vec3(0.55, 0.8, 0.9) * b * 0.07 * (1.0 - depth * 0.5);
		}
	}

	// виньетка
	float v = smoothstep(0.95, 0.25, length(dir * vec2(0.9, 1.0)));
	col *= mix(0.62, 1.0, v);
	COLOR = vec4(col, 1.0);
}
