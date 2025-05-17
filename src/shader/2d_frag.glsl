#version 460

layout(location=0) in vec2 I_uv;
layout(location=1) in vec4 I_color;

layout(location=0) out vec4 O_color;

layout(set=2, binding=0) uniform sampler2D U_texture;

void main() {
	O_color = texture(U_texture, I_uv)*I_color;
}
