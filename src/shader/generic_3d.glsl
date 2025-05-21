@header package shader
@header import sg "lib:sokol/gfx"

@module generic_3d

@block max_point_light
const int MAX_POINT_LIGHT = 16;
@end

@vs generic_3d_vert
@include_block max_point_light

layout(binding=0) uniform Vertex_Param {
	mat4 view;
	mat4 proj;
	vec4 light_data[MAX_POINT_LIGHT]; // {pos_x, pos_y, pos_z, _}
} U_param;

in vec3 A_position;
in vec3 A_normal;
in vec2 A_uv;
in vec4 A_color;

out vec3 F_normal;
out vec2 F_uv;
out vec4 F_color;
out vec3 F_rel_vertex_pos;
out vec3 F_to_lights[MAX_POINT_LIGHT];

void main() {
	gl_Position = U_param.proj*U_param.view*vec4(A_position, 1.0);
	F_normal = A_normal;
	F_uv = A_uv;
	F_color = A_color;
	F_rel_vertex_pos = (U_param.view*vec4(A_position, 1.0)).xyz;

	for (int i = 0; i < MAX_POINT_LIGHT; i++) {
		vec3 light_pos = vec3(U_param.light_data[i].x, U_param.light_data[i].y, U_param.light_data[i].z);
		F_to_lights[i] = light_pos - A_position;
	}
}
@end

@fs generic_3d_frag
@include_block max_point_light

in vec3 F_normal;
in vec2 F_uv;
in vec4 F_color;
in vec3 F_rel_vertex_pos;
in vec3 F_to_lights[MAX_POINT_LIGHT];

out vec4 O_color;

layout(binding=0) uniform texture2D U_texture;
layout(binding=0) uniform sampler U_sampler;

layout(binding=1) uniform Fragment_Param {
	float fog_density;
	float fog_gradient;
	vec3 fog_color;
	int light_count;
	vec4 light_data1[MAX_POINT_LIGHT]; // {col_r, col_g, col_b, radius}
	vec4 light_data2[MAX_POINT_LIGHT]; // {intensity, falloff}
} U_param;

void main() {
	float cam_rel_dist = length(F_rel_vertex_pos);
	float F_visibility = exp(-pow(cam_rel_dist*U_param.fog_density, U_param.fog_gradient));
	F_visibility = clamp(F_visibility, 0.0, 1.0);

	vec3 unit_normal = normalize(F_normal);
	vec3 total_diffuse = vec3(0.0);

	for (int i = 0; i < U_param.light_count; i++) {
		float light_radius = U_param.light_data1[i].w;

		float dist_to_light = length(F_to_lights[i]);
		if (dist_to_light > light_radius) {
			continue;
		}

		vec3 light_color = vec3(U_param.light_data1[i].r, U_param.light_data1[i].g, U_param.light_data1[i].b);
		float light_intensity = U_param.light_data2[i].x;
		float light_falloff = U_param.light_data2[i].y;
		float attenuation = pow(clamp(1.0 - (dist_to_light/light_radius), 0.0, 1.0), light_falloff);
		vec3 unit_to_light = normalize(F_to_lights[i]);

		float ndotl = max(dot(unit_normal, unit_to_light), 0.0);
		total_diffuse += light_color*ndotl*attenuation*light_intensity;
	}

	// ambient light
	total_diffuse = max(total_diffuse, 0.16);

	O_color = vec4(total_diffuse, 1.0)*texture(sampler2D(U_texture, U_sampler), F_uv)*F_color;
	O_color = mix(vec4(U_param.fog_color, 1.0), O_color, F_visibility);
}
@end

// @vs generic_3d_vert
// @include_block max_point_light

// layout(binding=0) uniform Vertex_Param {
// 	mat4 view;
// 	mat4 proj;
// 	float fog_density;
// 	float fog_gradient;
// 	vec4 light_data[MAX_POINT_LIGHT]; // {pos_x, pos_y, pos_z, _}
// } U_param;

// in vec3 A_position;
// in vec3 A_normal;
// in vec2 A_uv;
// in vec4 A_color;

// out vec3 F_normal;
// out vec2 F_uv;
// out vec4 F_color;
// out float F_visibility;
// out vec3 F_to_lights[MAX_POINT_LIGHT];

// void main() {
// 	gl_Position = U_param.proj*U_param.view*vec4(A_position, 1.0);
// 	F_normal = A_normal;
// 	F_uv = A_uv;
// 	F_color = A_color;

// 	float cam_rel_dist = length(U_param.view*vec4(A_position, 1.0));
// 	F_visibility = exp(-pow(cam_rel_dist*U_param.fog_density, U_param.fog_gradient));
// 	F_visibility = clamp(F_visibility, 0.0, 1.0);

// 	for (int i = 0; i < MAX_POINT_LIGHT; i++) {
// 		vec3 light_pos = vec3(U_param.light_data[i].x, U_param.light_data[i].y, U_param.light_data[i].z);
// 		F_to_lights[i] = light_pos - A_position;
// 	}
// }
// @end

// @fs generic_3d_frag
// @include_block max_point_light

// in vec3 F_normal;
// in vec2 F_uv;
// in vec4 F_color;
// in float F_visibility;
// in vec3 F_to_lights[MAX_POINT_LIGHT];

// out vec4 O_color;

// layout(binding=0) uniform texture2D U_texture;
// layout(binding=0) uniform sampler U_sampler;

// layout(binding=1) uniform Fragment_Param {
// 	vec3 fog_color;
// 	int light_count;
// 	vec4 light_data1[MAX_POINT_LIGHT]; // {col_r, col_g, col_b, radius}
// 	vec4 light_data2[MAX_POINT_LIGHT]; // {att_x, att_y, att_z, _}
// } U_param;

// void main() {
// 	vec3 unit_normal = normalize(F_normal);
// 	vec3 total_diffuse = vec3(0.0);

// 	for (int i = 0; i < U_param.light_count; i++) {
// 		vec3 light_color = vec3(U_param.light_data1[i].r, U_param.light_data1[i].g, U_param.light_data1[i].b);
// 		float light_radius = U_param.light_data1[i].w;

// 		vec3 attenuation = vec3(U_param.light_data2[i].x, U_param.light_data2[i].y, U_param.light_data2[i].z);
// 		float dist_to_light = length(F_to_lights[i]);
// 		float att_factor =
// 			attenuation.x +
// 			attenuation.y*dist_to_light +
// 			attenuation.z*dist_to_light*dist_to_light;

// 		vec3 unit_to_light = normalize(F_to_lights[i]);

// 		float norm_dot_light = dot(unit_normal, unit_to_light);
// 		float brightness = max(norm_dot_light, 0.0);
// 		total_diffuse += brightness*light_color/att_factor;
// 	}

// 	// ambient light
// 	total_diffuse = max(total_diffuse, 0.16);

// 	O_color = vec4(total_diffuse, 1.0)*texture(sampler2D(U_texture, U_sampler), F_uv)*F_color;
// 	O_color = mix(vec4(U_param.fog_color, 1.0), O_color, F_visibility);
// }
// @end

@program generic_3d generic_3d_vert generic_3d_frag
