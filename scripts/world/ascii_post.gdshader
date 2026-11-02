shader_type canvas_item;
render_mode unshaded;

// Full-screen ASCII mosaic. Samples the screen once per character cell and
// stamps a glyph from a 10-cell atlas. Sits below the HUD so UI stays readable.

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform sampler2D glyphs : repeat_disable, filter_linear;
uniform vec2 cell_size = vec2(6.0, 9.0);
uniform float contrast = 1.8;
uniform float glyph_count = 10.0;
uniform vec3 ink = vec3(0.32, 0.95, 0.5);
uniform bool color_mode = true;

void fragment() {
	vec2 resolution = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 cells = max(vec2(1.0), resolution / cell_size);
	vec2 cell = floor(SCREEN_UV * cells);
	vec2 cell_uv = fract(SCREEN_UV * cells);

	vec3 src = texture(screen_texture, (cell + 0.5) / cells).rgb;
	float maxc = max(src.r, max(src.g, src.b));
	float minc = min(src.r, min(src.g, src.b));
	float lum = dot(src, vec3(0.299, 0.587, 0.114)) + (maxc - minc) * 0.45;
	lum = clamp((lum - 0.03) * contrast, 0.0, 1.0);
	lum = pow(lum, 0.95);

	float index = floor(lum * (glyph_count - 1.0) + 0.5);
	vec2 glyph_uv = vec2((index + cell_uv.x) / glyph_count, cell_uv.y);
	float mask = texture(glyphs, glyph_uv).a;

	vec3 col = color_mode ? src * 2.2 * (0.25 + 0.95 * mask) : ink * mask * (0.35 + 0.9 * lum);
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
