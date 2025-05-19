@header package shader
@header import sg "lib:sokol/gfx"

@module generic_3d

@vs generic_3d_vert
layout(binding=0) uniform Vertex_Param {
	mat4 viewproj;
} U_param;

in vec3 A_position;
in vec3 A_normal;
in vec2 A_uv;
in vec4 A_color;

out vec3 F_normal;
out vec2 F_uv;
out vec4 F_color;

void main() {
	gl_Position = U_param.viewproj*vec4(A_position, 1.0);
	F_normal = A_normal;
	F_uv = A_uv;
	F_color = A_color;
}
@end

@fs generic_3d_frag
in vec3 F_normal;
in vec2 F_uv;
in vec4 F_color;

out vec4 O_color;

layout(binding=0) uniform texture2D U_texture;
layout(binding=0) uniform sampler U_sampler;

void main() {
	O_color = texture(sampler2D(U_texture, U_sampler), F_uv)*F_color;
}
@end

@program generic_3d generic_3d_vert generic_3d_frag
