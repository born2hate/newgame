shader_type canvas_item;
// Скальная порода в мировых координатах: слои, трещины, темнеет с глубиной.

varying vec2 world;
uniform bool use_tex = false;
uniform sampler2D rock_tex : filter_linear_mipmap, repeat_enable;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	float a = hash(i), b = hash(i + vec2(1, 0)), c = hash(i + vec2(0, 1)), d = hash(i + vec2(1, 1));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}
float fbm(vec2 p) {
	float v = 0.0, a = 0.5;
	for (int i = 0; i < 5; i++) { v += a * noise(p); p *= 2.03; a *= 0.5; }
	return v;
}

void vertex() { world = VERTEX; }

void fragment() {
	vec2 p = world * 0.006;
	float n = fbm(p + vec2(0.0, fbm(p * 0.7) * 1.5));
	// слои пород
	float strata = sin(world.y * 0.035 + fbm(p * 0.5) * 6.0) * 0.5 + 0.5;
	vec3 a = vec3(0.13, 0.11, 0.14);
	vec3 b = vec3(0.19, 0.15, 0.15);
	vec3 col = mix(a, b, strata * 0.6 + n * 0.4);
	// трещины
	float cr = abs(fbm(p * 1.6 + 3.0) - 0.5);
	col *= mix(0.75, 1.0, smoothstep(0.0, 0.05, cr));
	// крупные валуны
	float boulder = smoothstep(0.55, 0.7, fbm(world * 0.012 + 9.0));
	col = mix(col, col * 1.25 + vec3(0.02), boulder * 0.5);
	// вкрапления минералов
	vec2 sc = floor(world / 14.0);
	float spark = step(0.992, hash(sc)) * smoothstep(5.0, 0.0, length(fract(world / 14.0) * 14.0 - 7.0));
	col += vec3(0.3, 0.7, 0.8) * spark * (0.5 + 0.5 * sin(TIME * 2.0 + hash(sc + 1.0) * 6.28));
	if (use_tex) {
		// текстура затемнена и смешана с шумом, чтобы не спорить с отсеками и скрыть повтор
		vec3 tx = texture(rock_tex, world / 900.0).rgb;
		col = mix(tx * 0.5, col, 0.35) * mix(0.8, 1.1, fbm(world * 0.002));
	}
	// темнее с глубиной, песок у поверхности
	float depth = clamp(world.y / 1800.0, 0.0, 1.0);
	col *= mix(1.0, 0.45, depth);
	col = mix(vec3(0.42, 0.35, 0.26), col, smoothstep(0.0, 60.0, world.y));
	COLOR = vec4(col, 1.0);
}
