shader_type canvas_item;
// Фон океана: градиент глубины, лучи света сверху, каустики, частицы-«снег».

uniform float depth = 0.0;       // 0 — у поверхности дна, 1 — глубоко
uniform vec2 cam_offset = vec2(0.0);
uniform bool use_tex = false;
uniform sampler2D bg_tex : filter_linear, repeat_disable;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	float a = hash(i), b = hash(i + vec2(1, 0)), c = hash(i + vec2(0, 1)), d = hash(i + vec2(1, 1));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

void fragment() {
	vec2 uv = UV;
	float d = clamp(depth, 0.0, 1.0);
	vec3 top = mix(vec3(0.06, 0.45, 0.62), vec3(0.02, 0.12, 0.25), d);
	vec3 bottom = mix(vec3(0.01, 0.12, 0.24), vec3(0.0, 0.02, 0.06), d);
	vec3 col = mix(top, bottom, smoothstep(0.0, 1.0, uv.y));
	if (use_tex) {
		vec2 tuv = vec2(uv.x, clamp(uv.y * 0.8 + d * 0.2, 0.0, 1.0));
		col = texture(bg_tex, tuv).rgb * mix(1.0, 0.35, d);
	}

	// лучи света
	float x = uv.x + cam_offset.x * 0.0002;
	float rays = 0.0;
	rays += pow(max(0.0, sin(x * 9.0 + uv.y * 2.0 + TIME * 0.25)), 8.0);
	rays += pow(max(0.0, sin(x * 13.0 - uv.y * 3.0 - TIME * 0.18 + 1.3)), 10.0) * 0.7;
	rays *= (1.0 - uv.y) * (1.0 - d * 0.85);
	col += vec3(0.35, 0.7, 0.8) * rays * 0.22;

	// каустики
	vec2 cp = (uv + cam_offset * 0.0003) * vec2(6.0, 10.0);
	float c = noise(cp + TIME * 0.3) * noise(cp * 1.7 - TIME * 0.2);
	col += vec3(0.2, 0.5, 0.6) * pow(c, 2.0) * 0.35 * (1.0 - uv.y) * (1.0 - d);

	// морской «снег»
	for (int i = 0; i < 3; i++) {
		float layer = float(i) + 1.0;
		vec2 sp = uv * vec2(18.0, 32.0) / layer + vec2(TIME * 0.05 * layer, -TIME * 0.12 / layer) + cam_offset * 0.0008 / layer;
		vec2 cell = floor(sp);
		vec2 f = fract(sp) - 0.5;
		float h = hash(cell + layer * 17.0);
		if (h > 0.82) {
			vec2 off = vec2(hash(cell + 3.1), hash(cell + 7.7)) - 0.5;
			float dist = length(f - off * 0.6);
			col += vec3(0.6, 0.85, 0.9) * smoothstep(0.08 / layer, 0.0, dist) * 0.35;
		}
	}
	// виньетка
	float v = smoothstep(1.2, 0.35, length(uv - 0.5));
	col *= mix(0.7, 1.0, v);
	COLOR = vec4(col, 1.0);
}
