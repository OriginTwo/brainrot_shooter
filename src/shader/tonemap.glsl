@header package shader
@header import sg "lib:sokol/gfx"

@module tonemap

@vs tonemap_vert
in vec2 A_position;
in vec2 A_uv;

out vec2 F_uv;

void main() {
	gl_Position = vec4(A_position, 0.0, 1.0);
	F_uv = A_uv;
}
@end

@fs tonemap_frag
in vec2 F_uv;

out vec4 O_color;

layout(binding=0) uniform texture2D U_texture;
layout(binding=0) uniform sampler U_sampler;

// https://github.com/dmnsgn/glsl-tone-map/blob/main/aces.glsl
vec3 aces(vec3 x) {
	const float a = 2.51;
	const float b = 0.03;
	const float c = 2.43;
	const float d = 0.59;
	const float e = 0.14;
	return clamp((x*(a*x + b))/(x*(c*x + d) + e), 0.0, 1.0);
}

void main() {
	vec4 color = texture(sampler2D(U_texture, U_sampler), F_uv);
	O_color = vec4(aces(color.rgb), color.a);
}
@end

@program tonemap tonemap_vert tonemap_frag
