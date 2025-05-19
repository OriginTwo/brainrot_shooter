package game

import "core:fmt"
import "core:math"
import "core:math/linalg"

import sdl "vendor:sdl3"

import im "lib:imgui"
import sg "lib:sokol/gfx"

SCN_GAME_HANDLE :: SCN_Handle(#hash("game", "fnv64a"))
SCN_GAME_CALLBACKS :: SCN_Callbacks{scn_game_init, scn_game_uninit, scn_game_tick, scn_game_draw}

@(private="file")
_ctx: struct {
	ren2d: GFX_2D_Renderer,
	ren3d: GFX_3D_Renderer,
	font: GFX_Font,
	tex: sg.Image,
	smp: sg.Sampler,

	cam: GFX_Camera,

	// e: PART_Handle,
}

scn_game_init :: proc() {
	GFX_create_2d_renderer(&_ctx.ren2d)
	GFX_create_3d_renderer(&_ctx.ren3d, 1280, 720)

	{
		img: GFX_Image
		GFX_load_image_from_file(&img, "res/font/font_big.png")
		GFX_load_font_from_image(&_ctx.font, img)
		GFX_unload_image(&img)
	}

	{
		img: GFX_Image
		GFX_load_image_from_file(&img, "res/image/HBD_2021.png")
		_ctx.tex = sg.make_image({
			type = ._2D,
			width = i32(img.width),
			height = i32(img.height),
			num_slices = 1,
			num_mipmaps = 1,
			usage = .IMMUTABLE,
			pixel_format = .RGBA8,
			sample_count = 1,
			data = {
				subimage = {0 = {0 = {
					ptr = raw_data(img.pixels),
					size = len(img.pixels)*size_of(img.pixels[0]),
				}}},
			},
		})
		_ctx.smp = GFX_get_default_2d_sampler(_ctx.ren2d)
		GFX_unload_image(&img)
	}

	_ctx.cam.fovy = math.PI/4.0

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

	sg.destroy_image(_ctx.tex)
	GFX_unload_font(&_ctx.font)
	GFX_destroy_2d_renderer(&_ctx.ren2d)
	GFX_destroy_3d_renderer(&_ctx.ren3d)
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

	if INP_is_key_pressed(input, .TAB) {
		@(static) lock_mouse := false
		lock_mouse = !lock_mouse
		window := WND_get_handle()
		win_width: i32
		win_height: i32
		sdl.GetWindowSize(window, &win_width, &win_height)
		_ = sdl.SetWindowRelativeMouseMode(window, lock_mouse)
		sdl.WarpMouseInWindow(window, f32(win_width/2), f32(win_height/2))
	}

	mdelta := INP_get_mouse_delta(input)

	MOUSE_SENS :: 0.05
	_ctx.cam.pitch += mdelta.y*MOUSE_SENS
	_ctx.cam.yaw += mdelta.x*MOUSE_SENS

	_ctx.cam.pitch = clamp(_ctx.cam.pitch, -89.0, 89.0)
	_ctx.cam.yaw = math.mod(_ctx.cam.yaw, 360.0)

	mat := GFX_get_camera_matrix(_ctx.cam)
	forward := M_Vec3f32{mat[2, 0], mat[1, 0], mat[0, 0]}
	right := M_Vec3f32{mat[2, 2], mat[1, 2], mat[0, 2]}
	mov_vec: M_Vec3f32
	if INP_is_key_down(input, .W) {mov_vec -= forward}
	if INP_is_key_down(input, .S) {mov_vec += forward}
	if INP_is_key_down(input, .D) {mov_vec += right}
	if INP_is_key_down(input, .A) {mov_vec -= right}
	mov_vec = linalg.normalize0(mov_vec)
	mov_vec *= 5.0*delta
	_ctx.cam.position += mov_vec

	// PART_tick(delta)
}

scn_game_draw :: proc(alpha: f32) {
	// PART_draw(alpha)

	GFX_begin_frame()
	GFX_clear_background(M_FCOLOR_BLACK)

	GFX_begin_3d_renderer(&_ctx.ren3d)

	GFX_draw_3d_triangle(
		&_ctx.ren3d,
		{ 0.0,  1.0, -5.0}, {0.0, 0.0, 0.0}, {255, 0, 0, 255},
		{-1.0, -1.0, -5.0}, {0.0, 0.0, 0.0}, {0, 255, 0, 255},
		{ 1.0, -1.0, -5.0}, {0.0, 0.0, 0.0}, {0, 0, 255, 255},
	)

	GFX_end_3d_renderer(&_ctx.ren3d, _ctx.cam)

	GFX_begin_2d_renderer(&_ctx.ren2d)

	// GFX_draw_2d_triangle(
	// 	&_ctx.ren2d,
	// 	{100.0, 100.0}, {255, 0, 0, 255},
	// 	{600.0, 200.0}, {0, 255, 0, 255},
	// 	{300.0, 500.0}, {0, 0, 255, 255},
	// )

	// GFX_set_2d_layer(&_ctx.ren2d, -1)

	// GFX_draw_2d_rect(
	// 	&_ctx.ren2d,
	// 	{mpos.x, mpos.y, 150.0, 200.0},
	// 	// M_urgba_from_frgba(M_frgba_from_hsva({math.sin(f32(TIME_now()))*0.5 + 0.5, 1.0, 1.0, math.cos(f32(TIME_now())*5.0)*0.5 + 0.5})),
	// 	M_urgba_from_frgba(M_frgba_from_hsva({math.sin(f32(TIME_now()))*0.5 + 0.5, 1.0, 1.0, 1.0})),
	// )

	// tex_width := f32(sg.query_image_width(_ctx.tex))
	// tex_height := f32(sg.query_image_height(_ctx.tex))

	// GFX_draw_2d_texture(
	// 	&_ctx.ren2d,
	// 	_ctx.tex,
	// 	_ctx.smp,
	// 	{0.0, 0.0, tex_width, tex_height},
	// 	{mpos.x, mpos.y, 500.0, 500.0},
	// 	M_urgba_from_frgba(M_frgba_from_hsva({math.sin(f32(TIME_now()))*0.5 + 0.5, 1.0, 1.0, math.cos(f32(TIME_now())*5.0)*0.5 + 0.5})),
	// )

	GFX_set_2d_layer(&_ctx.ren2d, 10)

	GFX_draw_2d_string(
		&_ctx.ren2d,
		_ctx.font,
		"Hello World!",
		{200.0, 200.0},
		M_urgba_from_frgba(M_frgba_from_hsva({math.sin(f32(TIME_now()))*0.5 + 0.5, 1.0, 1.0, 1.0})),
		3.0,
	)

	GFX_end_2d_renderer(&_ctx.ren2d)

	// im.ShowDemoWindow(nil)

	im.SetNextWindowSize({200, 400})
	if im.Begin("Debug") {
		im.SliderFloat("pos_x", &_ctx.cam.position.x, -10.0, 10.0)
		im.SliderFloat("pos_y", &_ctx.cam.position.y, -10.0, 10.0)
		im.SliderFloat("pos_z", &_ctx.cam.position.z, -10.0, 10.0)
		im.SliderFloat("pitch", &_ctx.cam.pitch, -89.0, 89.0)
		im.SliderFloat("yaw", &_ctx.cam.yaw, 0.0, 360.0)
		im.SliderFloat("roll", &_ctx.cam.roll, 0.0, 360.0)
	}
	im.End()

	GFX_end_frame()

	sg.commit()
}
