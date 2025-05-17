package game

import "core:fmt"
import "core:math"

SCN_GAME_HANDLE :: SCN_Handle(#hash("game", "fnv64a"))
SCN_GAME_CALLBACKS :: SCN_Callbacks{scn_game_init, scn_game_uninit, scn_game_tick, scn_game_draw}

@(private="file")
_ctx: struct {
	ren: GFX_Renderer_2D,
	tex: GFX_Texture,

	// e: PART_Handle,
}

scn_game_init :: proc() {
	GFX_create_renderer_2d(&_ctx.ren, 1280, 720)
	GFX_load_texture_from_file(&_ctx.tex, "res/image/sketch.png")

	// _ctx.e = PART_emitter_create({
	// 	particle_count = 24,
	// 	// particle_shape = PART_Particle_Shape_Spark{
	// 	// 	min_half_width = 1.0,
	// 	// 	max_half_width = 2.0,
	// 	// 	min_head_length = 2.0,
	// 	// 	max_head_length = 4.0,
	// 	// 	min_tail_length = 6.0,
	// 	// 	max_tail_length = 10.0,
	// 	// },
	// 	particle_shape = PART_Particle_Shape_Square{
	// 		min_length = 4.0,
	// 		max_length = 8.0,
	// 	},
	// 	emission_shape = PART_Emission_Shape_Point{
	// 	},
	// 	emission_spread = 30.0,
	// 	min_lifetime = 0.5,
	// 	max_lifetime = 1.0,
	// 	min_initial_rotation = -360.0,
	// 	max_initial_rotation = 360.0,
	// 	min_initial_linear_vel = 150.0,
	// 	max_initial_linear_vel = 200.0,
	// 	min_initial_angular_vel = 180.0,
	// 	max_initial_angular_vel = 360.0,
	// 	min_initial_radial_vel = 0.0,
	// 	max_initial_radial_vel = 0.0,
	// 	min_initial_tangential_vel = 0.0,
	// 	max_initial_tangential_vel = 0.0,
	// 	min_linear_accel = 0.0,
	// 	max_linear_accel = 0.0,
	// 	min_angular_accel = 0.0,
	// 	max_angular_accel = 0.0,
	// 	min_radial_accel = 0.0,
	// 	max_radial_accel = 0.0,
	// 	min_tangential_accel = 0.0,
	// 	max_tangential_accel = 0.0,
	// 	min_damping = 200.0,
	// 	max_damping = 300.0,
	// 	scale_curve = {
	// 		{0.000000, 0.000000}, {0.000000, 0.501736}, {0.003681, 1.000000},
	// 		{0.153681, 1.000000}, {0.303681, 1.000000}, {0.902778, 0.000000},
	// 		{1.000000, 0.000000},
	// 	},
	// 	color_curve = {
	// 		{0.0, 1.0, 1.0, 1.0, 1.0},
	// 		{0.2, 1.0, 0.8, 0.2, 1.0},
	// 		{0.6, 1.0, 0.2, 0.2, 1.0},
	// 		{0.8, 0.2, 0.2, 0.2, 1.0},
	// 	},
	// })

	// PART_emitter_set_direction(_ctx.e, {1.0, 0.0})
	// PART_emitter_set_position(_ctx.e, {VIEWPORT_WIDTH, VIEWPORT_HEIGHT}/2.0)
	// PART_emitter_start(_ctx.e)
}

scn_game_uninit :: proc() {
	// PART_emitter_destroy(_ctx.e)
	// PART_destroy_all()

	GFX_unload_texture(&_ctx.tex)
	GFX_destroy_renderer_2d(&_ctx.ren)
}

mpos: M_Vec2f32
scn_game_tick :: proc(input: INP_State, delta: f32) {
	when DEV_BUILD {
		// if INP_is_key_pressed(.F1) {
		// 	SCN_change(SCN_EDITOR_HANDLE)
		// }
	}

	mpos = INP_get_mouse_pos(input)

	if INP_is_key_pressed(input, .ESCAPE) {
		WND_set_should_close(true)
	}

	// PART_tick(delta)
}

scn_game_draw :: proc(alpha: f32) {
	// PART_draw(alpha)

	GFX_begin_frame()
	GFX_begin_renderer_2d(&_ctx.ren)

	GFX_draw_2d_triangle(
		&_ctx.ren,
		{100.0, 100.0}, {255, 0, 0, 255},
		{600.0, 200.0}, {0, 255, 0, 255},
		{300.0, 500.0}, {0, 0, 255, 255},
	)

	GFX_set_renderer_2d_layer(&_ctx.ren, 1.0)

	// GFX_draw_2d_rect(
	// 	&_ctx.ren,
	// 	{mpos.x, mpos.y, 150.0, 200.0},
	// 	M_urgba_from_frgba(M_frgba_from_hsva({math.sin(f32(TIME_now()))*0.5 + 0.5, 1.0, 1.0, math.cos(f32(TIME_now())*5.0)*0.5 + 0.5})),
	// )

	GFX_draw_2d_texture(
		&_ctx.ren,
		_ctx.tex,
		{0.0, 0.0, f32(_ctx.tex.width), f32(_ctx.tex.height)},
		{mpos.x, mpos.y, 500.0, 500.0},
		M_urgba_from_frgba(M_frgba_from_hsva({math.sin(f32(TIME_now()))*0.5 + 0.5, 1.0, 1.0, math.cos(f32(TIME_now())*5.0)*0.5 + 0.5})),
	)

	GFX_end_renderer_2d(&_ctx.ren)
	GFX_end_frame()
}
