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
layout(binding=0) uniform Fragment_Param {
	float exposure;
	float gamma;
} U_param;

vec3 reinhard(vec3 x) {
	vec3 mapped = vec3(1.0) - exp(-x*U_param.exposure);
	mapped = pow(mapped, vec3(1.0/U_param.gamma));
	return mapped;
}

void main() {
	vec4 color = texture(sampler2D(U_texture, U_sampler), F_uv);
	O_color = vec4(reinhard(color.rgb), color.a);
}
@end

@program tonemap tonemap_vert tonemap_frag
