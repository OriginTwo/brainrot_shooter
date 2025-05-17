#version 460

layout(set=1, binding=0) uniform UBO {
	mat4 U_proj;
};

layout(location=0) in vec3 A_position;
layout(location=1) in vec2 A_uv;
layout(location=2) in vec4 A_color;

layout(location=0) out vec2 O_uv;
layout(location=1) out vec4 O_color;

void main() {
	gl_Position = U_proj*vec4(A_position, 1.0);
	O_uv = A_uv;
	O_color = A_color;
}
