@header package shader
@header import sg "lib:sokol/gfx"

@module additive


@vs additive_vert
in vec2 A_position;
in vec2 A_uv;

out vec2 F_uv;

void main() {
	gl_Position = vec4(A_position, 0.0, 1.0);
	F_uv = A_uv;
}
@end

@fs additive_frag
in vec2 F_uv;

out vec4 O_color;

layout(binding=0) uniform texture2D U_texture0;
layout(binding=0) uniform sampler U_sampler0;
layout(binding=1) uniform texture2D U_texture1;
layout(binding=1) uniform sampler U_sampler1;

void main() {
	vec3 t0 = texture(sampler2D(U_texture0, U_sampler0), F_uv).rgb;
	vec3 t1 = texture(sampler2D(U_texture1, U_sampler1), F_uv).rgb;
	O_color = vec4(t0 + t1, 1.0);
}
@end

@program additive additive_vert additive_frag
