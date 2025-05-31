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
	ren_fx: GFX_Post_FX_Renderer,
	font: GFX_Font,
	tex: sg.Image,
	smp: sg.Sampler,

	cam: GFX_Camera,

	disable_bloom: bool,
	bloom_filter_radius: f32,
	tonemap_exposure: f32,
	tonemap_gamma: f32,
}

scn_game_init :: proc() {
	GFX_create_2d_renderer(&_ctx.ren2d)
	GFX_create_3d_renderer(&_ctx.ren3d, VIEWPORT_WIDTH, VIEWPORT_HEIGHT)
	GFX_create_post_fx_renderer(&_ctx.ren_fx, VIEWPORT_WIDTH, VIEWPORT_HEIGHT)

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

	_ctx.cam.position.y = 1.0
	_ctx.cam.fovy = math.PI/2.0

	_ctx.bloom_filter_radius = 0.01
	_ctx.tonemap_exposure = 1.2
	_ctx.tonemap_gamma = 1.0
}

scn_game_uninit :: proc() {
	sg.destroy_image(_ctx.tex)
	GFX_unload_font(&_ctx.font)
	GFX_destroy_2d_renderer(&_ctx.ren2d)
	GFX_destroy_3d_renderer(&_ctx.ren3d)
	GFX_destroy_post_fx_renderer(&_ctx.ren_fx)
	_ctx = {}
}

mpos: M_Vec2f32
scn_game_tick :: proc(input: INP_State, delta: f32) {
	when DEV_BUILD {
		if INP_is_key_pressed(input, .F1) {
			WND_lock_mouse(false)
			SCN_change(SCN_EDITOR_HANDLE)
		}
	}

	mpos = INP_get_mouse_pos(input)

	if INP_is_key_pressed(input, .ESCAPE) {
		WND_set_should_close(true)
	}

	if INP_is_key_pressed(input, .TAB) {
		@(static) lock_mouse := false
		lock_mouse = !lock_mouse
		WND_lock_mouse(lock_mouse)
	}

	mdelta := INP_get_mouse_delta(input)

	MOUSE_SENS :: 0.05
	_ctx.cam.pitch += mdelta.y*MOUSE_SENS
	_ctx.cam.yaw += mdelta.x*MOUSE_SENS

	_ctx.cam.pitch = clamp(_ctx.cam.pitch, -89.0, 89.0)
	_ctx.cam.yaw = math.mod(_ctx.cam.yaw, 360.0)

	forward, _, right := GFX_get_camera_forward_up_right(_ctx.cam)
	mov_vec: M_Vec3f32
	if INP_is_key_down(input, .W) {mov_vec -= forward}
	if INP_is_key_down(input, .S) {mov_vec += forward}
	if INP_is_key_down(input, .D) {mov_vec += right}
	if INP_is_key_down(input, .A) {mov_vec -= right}
	mov_vec = linalg.normalize0(mov_vec)
	mov_vec *= 8.0*delta
	_ctx.cam.position += mov_vec

	@(static) bob_t: f32
	if mov_vec != {} {
		bob_t += delta*4.0
	} else {
		bob_t -= delta*4.0
	}
	bob_t = clamp(bob_t, 0.0, 1.0)
	_ctx.cam.offset.y = 0.06*bob_t*math.sin(f32(TIME_now())*14.0)
}

scn_game_draw :: proc(alpha: f32) {
	GFX_begin_frame()
	GFX_clear_background(M_FCOLOR_BLACK)

	GFX_begin_3d_renderer(&_ctx.ren3d, _ctx.cam)

	GFX_draw_3d_rect(
		&_ctx.ren3d,
		{-100.0, -1.0, -100.0}, {0.0, 1.0, 0.0}, {127, 127, 127, 255},
		{ 100.0, -1.0, -100.0}, {0.0, 1.0, 0.0}, {127, 127, 127, 255},
		{ 100.0, -1.0,  100.0}, {0.0, 1.0, 0.0}, {127, 127, 127, 255},
		{-100.0, -1.0,  100.0}, {0.0, 1.0, 0.0}, {127, 127, 127, 255},
	)

	GFX_draw_3d_billboard_triangle(
		&_ctx.ren3d,
		{ 0.0,  1.0, -5.0}, {255, 0, 0, 255},
		{ 1.0, -1.0, -5.0}, {0, 0, 255, 255},
		{-1.0, -1.0, -5.0}, {0, 255, 0, 255},
		false,
	)

	GFX_draw_3d_billboard_triangle(
		&_ctx.ren3d,
		{2.0,  1.0, -5.0}, {255, 0, 0, 255},
		{3.0, -1.0, -5.0}, {0, 0, 255, 255},
		{1.0, -1.0, -5.0}, {0, 255, 0, 255},
		true,
	)

	GFX_draw_3d_billboard_rect(
		&_ctx.ren3d,
		{0.0, 2.0, -5.0},
		{2.0, 2.0},
		{200, 40, 40, 255},
		false,
	)

	GFX_draw_3d_billboard_rect(
		&_ctx.ren3d,
		{2.0, 2.0, -5.0},
		{1.0, 2.0},
		{200, 40, 40, 255},
		true,
	)

	GFX_draw_3d_billboard_texture(
		&_ctx.ren3d,
		_ctx.tex,
		_ctx.smp,
		{0.0, 4.0, -5.0},
		{2.0, 2.0},
		{0.0, 0.0, 1920.0, 1080.0},
		{255, 255, 255, 255},
		false,
	)

	GFX_draw_3d_billboard_texture(
		&_ctx.ren3d,
		_ctx.tex,
		_ctx.smp,
		{2.0, 4.0, -5.0},
		{1.0, 2.0},
		{800.0, 500.0, 1000.0, 500.0},
		{255, 255, 255, 255},
		true,
	)

	GFX_draw_3d_decal_texture(
		&_ctx.ren3d,
		_ctx.tex,
		_ctx.smp,
		{-10.0, -1.0, -10.0},
		{ 10.0, -1.0, -10.0},
		{ 10.0, -1.0,  10.0},
		{-10.0, -1.0,  10.0},
		{0.0, 1.0, 0.0},
		{800.0, 500.0, 1000.0, 500.0},
		{255, 255, 255, 255},
	)

	GFX_add_3d_light(&_ctx.ren3d, {
		position = {-3.0, 1.5, -2.0},
		intensity = 7.0,
		radius = 9.0,
		color = {1.0, 0.4, 0.4},
		falloff = 1.0,
	})

	GFX_add_3d_light(&_ctx.ren3d, {
		position = {3.0, 1.5, -2.0},
		intensity = 7.0,
		radius = 9.0,
		color = {0.4, 0.4, 1.0},
		falloff = 1.0,
	})

	GFX_add_3d_light(&_ctx.ren3d, {
		position = _ctx.cam.position,
		intensity = 2.0,
		radius = 6.0,
		color = {1.0, 1.0, 1.0},
		falloff = 2.0,
	})

	GFX_end_3d_renderer(&_ctx.ren3d)

	GFX_do_post_fx_bloom(&_ctx.ren_fx, _ctx.ren3d.bright_color_texture, _ctx.bloom_filter_radius)
	GFX_do_post_fx_tonemap(&_ctx.ren_fx, _ctx.ren_fx.bloom_mip_chain[0].texture, _ctx.tonemap_exposure, _ctx.tonemap_gamma)
	GFX_do_post_fx_additive(&_ctx.ren_fx, _ctx.ren3d.color_texture, _ctx.ren_fx.tonemap_texture, _ctx.ren_fx.bloom_sampler, _ctx.ren_fx.bloom_sampler)

	GFX_begin_2d_renderer(&_ctx.ren2d)

	win_size: [2]i32
	sdl.GetWindowSize(WND_get_handle(), &win_size.x, &win_size.y)

	if _ctx.disable_bloom {
		w := f32(sg.query_image_width(_ctx.ren3d.color_texture))
		h := f32(sg.query_image_height(_ctx.ren3d.color_texture))
		GFX_draw_2d_texture(
			&_ctx.ren2d,
			_ctx.ren3d.color_texture,
			GFX_get_default_2d_sampler(_ctx.ren2d),
			{0.0, h, w, -h},
			{0.0, 0.0, f32(win_size.x), f32(win_size.y)},
			M_COLOR_WHITE,
		)
	} else {
		w := f32(sg.query_image_width(_ctx.ren_fx.additive_texture))
		h := f32(sg.query_image_height(_ctx.ren_fx.additive_texture))
		GFX_draw_2d_texture(
			&_ctx.ren2d,
			_ctx.ren_fx.additive_texture,
			GFX_get_default_2d_sampler(_ctx.ren2d),
			{0.0, 0.0, w, h},
			{0.0, 0.0, f32(win_size.x), f32(win_size.y)},
			M_COLOR_WHITE,
		)
	}

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

	im.SetNextWindowSize({200.0, 400.0}, .Once)
	im.Begin("Debug")
	{
		im.SliderFloat("pos_x", &_ctx.cam.position.x, -10.0, 10.0)
		im.SliderFloat("pos_y", &_ctx.cam.position.y, -10.0, 10.0)
		im.SliderFloat("pos_z", &_ctx.cam.position.z, -10.0, 10.0)
		im.SliderFloat("pitch", &_ctx.cam.pitch, -89.0, 89.0)
		im.SliderFloat("yaw", &_ctx.cam.yaw, 0.0, 360.0)
		im.SliderFloat("roll", &_ctx.cam.roll, -30.0, 30.0)
		im.Checkbox("disable bloom", &_ctx.disable_bloom)
		im.SliderFloat("bloom_filter_radius", &_ctx.bloom_filter_radius, 0.0001, 0.1)
		im.SliderFloat("tonemap_exposure", &_ctx.tonemap_exposure, 0.1, 10.0)
		im.SliderFloat("tonemap_gamma", &_ctx.tonemap_gamma, 0.1, 5.0)
	}
	im.End()

	GFX_end_frame()

	sg.commit()
}
