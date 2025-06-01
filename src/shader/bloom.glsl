// https://learnopengl.com/Guest-Articles/2022/Phys.-Based-Bloom

@header package shader
@header import sg "lib:sokol/gfx"

@module bloom


@vs bloom_vert
in vec2 A_position;
in vec2 A_uv;

out vec2 F_uv;

void main() {
	gl_Position = vec4(A_position, 0.0, 1.0);
	F_uv = A_uv;
}
@end


@fs bloom_downsample_frag
in vec2 F_uv;

out vec4 O_color;

layout(binding=0) uniform texture2D U_src_texture;
layout(binding=0) uniform sampler U_src_sampler;
layout(binding=0) uniform Downsample_Fragment_Param {
	vec2 src_resolution;
} U_param;

void main() {
	vec2 src_texel_size = 1.0/U_param.src_resolution;
	float x = src_texel_size.x;
	float y = src_texel_size.y;

	// take 13 samples around current texel (e)
	// a - b - c
	// - j - k -
	// d - e - f
	// - l - m -
	// g - h - i
	vec3 a = texture(sampler2D(U_src_texture, U_src_sampler), vec2(F_uv.x - 2.0*x, F_uv.y + 2.0*y)).rgb;
	vec3 b = texture(sampler2D(U_src_texture, U_src_sampler), vec2(F_uv.x,         F_uv.y + 2.0*y)).rgb;
	vec3 c = texture(sampler2D(U_src_texture, U_src_sampler), vec2(F_uv.x + 2.0*x, F_uv.y + 2.0*y)).rgb;

	vec3 d = texture(sampler2D(U_src_texture, U_src_sampler), vec2(F_uv.x - 2.0*x, F_uv.y)).rgb;
	vec3 e = texture(sampler2D(U_src_texture, U_src_sampler), vec2(F_uv.x,         F_uv.y)).rgb;
	vec3 f = texture(sampler2D(U_src_texture, U_src_sampler), vec2(F_uv.x + 2.0*x, F_uv.y)).rgb;

	vec3 g = texture(sampler2D(U_src_texture, U_src_sampler), vec2(F_uv.x - 2.0*x, F_uv.y - 2.0*y)).rgb;
	vec3 h = texture(sampler2D(U_src_texture, U_src_sampler), vec2(F_uv.x,         F_uv.y - 2.0*y)).rgb;
	vec3 i = texture(sampler2D(U_src_texture, U_src_sampler), vec2(F_uv.x + 2.0*x, F_uv.y - 2.0*y)).rgb;

	vec3 j = texture(sampler2D(U_src_texture, U_src_sampler), vec2(F_uv.x - x, F_uv.y + y)).rgb;
	vec3 k = texture(sampler2D(U_src_texture, U_src_sampler), vec2(F_uv.x + x, F_uv.y + y)).rgb;
	vec3 l = texture(sampler2D(U_src_texture, U_src_sampler), vec2(F_uv.x - x, F_uv.y - y)).rgb;
	vec3 m = texture(sampler2D(U_src_texture, U_src_sampler), vec2(F_uv.x + x, F_uv.y - y)).rgb;

	// apply weighted distribution
	vec3 color = e*0.125;
	color += (a + c + g + i)*0.03125;
	color += (b + d + f + h)*0.0625;
	color += (j + k + l + m)*0.125;
	O_color = vec4(color, 1.0);
}
@end


@fs bloom_upsample_frag
in vec2 F_uv;

out vec4 O_color;

layout(binding=0) uniform texture2D U_downsampled_texture;
layout(binding=1) uniform texture2D U_upsampled_texture;
layout(binding=1) uniform sampler U_sampler;
layout(binding=0) uniform Upsample_Fragment_Param {
	float filter_radius;
} U_param;

void main() {
	float x = U_param.filter_radius;
	float y = U_param.filter_radius;

	// take 9 samples around current texel (e)
	// a - b - c
	// d - e - f
	// g - h - i
	vec3 a = texture(sampler2D(U_downsampled_texture, U_sampler), vec2(F_uv.x - x, F_uv.y + y)).rgb;
	vec3 b = texture(sampler2D(U_downsampled_texture, U_sampler), vec2(F_uv.x,     F_uv.y + y)).rgb;
	vec3 c = texture(sampler2D(U_downsampled_texture, U_sampler), vec2(F_uv.x + x, F_uv.y + y)).rgb;

	vec3 d = texture(sampler2D(U_downsampled_texture, U_sampler), vec2(F_uv.x - x, F_uv.y)).rgb;
	vec3 e = texture(sampler2D(U_downsampled_texture, U_sampler), vec2(F_uv.x,     F_uv.y)).rgb;
	vec3 f = texture(sampler2D(U_downsampled_texture, U_sampler), vec2(F_uv.x + x, F_uv.y)).rgb;

	vec3 g = texture(sampler2D(U_downsampled_texture, U_sampler), vec2(F_uv.x - x, F_uv.y - y)).rgb;
	vec3 h = texture(sampler2D(U_downsampled_texture, U_sampler), vec2(F_uv.x,     F_uv.y - y)).rgb;
	vec3 i = texture(sampler2D(U_downsampled_texture, U_sampler), vec2(F_uv.x + x, F_uv.y - y)).rgb;

	// apply weighted distribution
	vec3 color = e*4.0;
	color += (b + d + f + h)*2.0;
	color += (a + c + g + i);
	color *= 1.0/16.0;

	vec3 upsampled_color = texture(sampler2D(U_upsampled_texture, U_sampler), F_uv).rgb;
	O_color = vec4(upsampled_color + color, 1.0);
}
@end


@program bloom_downsample bloom_vert bloom_downsample_frag
@program bloom_upsample bloom_vert bloom_upsample_frag
