package game

import "core:math"
import "core:math/linalg"
import "core:math/ease"
import "core:math/rand"

import sdl "vendor:sdl3"
import ma "vendor:miniaudio"

import sg "lib:sokol/gfx"

SCN_MAIN_MENU_HANDLE :: SCN_Handle(#hash("main_menu", "fnv64a"))
SCN_MAIN_MENU_CALLBACKS :: SCN_Callbacks{
	scn_main_menu_init,
	scn_main_menu_uninit,
	scn_main_menu_tick,
	scn_main_menu_draw,
}

@(private="file") _TEXT_SCALE :: 3.0
@(private="file") _PADDING :: 8.0

@(private="file")
_ctx: struct {
	ren2d: GFX_2D_Renderer,
	ren3d: GFX_3D_Renderer,
	ren_fx: GFX_Post_FX_Renderer,
	font: GFX_Font,

	cam: GFX_Camera,

	tung_tung_sahur_tex: GFX_Texture,

	hovered_sound: AUD_Sound,

	music: AUD_Music,
}

@(private="file")
_Button :: struct {
	text: string,
	hot_t: f32,
	was_hovered: bool,
	click_proc: proc(),
}

@(private="file")
_buttons := [?]_Button{
	{
		text = "Play",
		click_proc = _play_button_proc,
	},
	{
		text = "Quit",
		click_proc = _quit_button_proc,
	},
}

@(private="file")
_play_button_proc :: proc() {
	SCN_change(SCN_GAME_HANDLE)
}

@(private="file")
_quit_button_proc :: proc() {
	WND_set_should_close(true)
}

scn_main_menu_init :: proc() {
	GFX_create_2d_renderer(&_ctx.ren2d)
	GFX_create_3d_renderer(&_ctx.ren3d, VIEWPORT_WIDTH, VIEWPORT_HEIGHT)
	GFX_create_post_fx_renderer(&_ctx.ren_fx, VIEWPORT_WIDTH, VIEWPORT_HEIGHT)

	{
		img: GFX_Image
		RES_load_image(&img, RES_ID_FONT_FONT_PNG)
		GFX_load_font_from_image(&_ctx.font, img)
		GFX_unload_image(&img)
	}

	_ctx.cam.position.y = 1.0
	_ctx.cam.fovy = math.PI/2.0

	RES_load_texture(&_ctx.tung_tung_sahur_tex, RES_ID_IMAGE_TUNG_TUNG_SAHUR_PNG)

	RES_load_sound(&_ctx.hovered_sound, RES_ID_SOUND_UI_HOVERED_WAV)

	RES_load_music(&_ctx.music, RES_ID_MUSIC_DESERT_SIROCCO_OGG)

	ma.sound_set_looping(&_ctx.music.sound, true)
	ma.sound_set_volume(&_ctx.music.sound, 0.3)
	ma.sound_start(&_ctx.music.sound)
}

scn_main_menu_uninit :: proc() {
	AUD_unload_music(&_ctx.music)

	AUD_unload_sound(&_ctx.hovered_sound)

	GFX_unload_texture(&_ctx.tung_tung_sahur_tex)

	GFX_unload_font(&_ctx.font)
	GFX_destroy_2d_renderer(&_ctx.ren2d)
	GFX_destroy_3d_renderer(&_ctx.ren3d)
	GFX_destroy_post_fx_renderer(&_ctx.ren_fx)
	_ctx = {}

	for &button in _buttons {
		button.hot_t = 0.0
	}
}

scn_main_menu_tick :: proc(input: INP_State, delta: f32) {
	now := f32(TIME_now())
	_ctx.cam.pitch = (2.0*math.sin(0.5*now) - 1.4*math.cos(0.25*now))*2.0
	_ctx.cam.yaw = math.cos(0.4*now)*3.0

	window_width: f32
	window_height: f32
	{
		w: i32
		h: i32
		sdl.GetWindowSize(WND_get_handle(), &w, &h)
		window_width = f32(w)
		window_height = f32(h)
	}

	scale_x := window_width/WINDOW_WIDTH
	scale_y := window_height/WINDOW_HEIGHT
	scale := min(scale_x, scale_y)

	font_height := f32(_ctx.font.base_size)*_TEXT_SCALE*scale
	line_height := font_height*1.2

	y := window_height/2.0 - (line_height*len(_buttons))/2.0 - (_PADDING*(len(_buttons) - 1))/2.0
	mouse := INP_get_mouse_pos(input)
	rate := 1.0 - math.pow(2.0, -25.0*delta)

	for &button in _buttons {
		rect := M_Rect{44.0*scale, y, window_width/4.0, line_height}
		target: f32 = 0.0
		is_hovered := M_is_point_in_rect(mouse, rect)

		if is_hovered {
			target = 1.0

			if !button.was_hovered {
				AUD_play_sound(&_ctx.hovered_sound)
			}

			if INP_is_mouse_pressed(input, .Left) {
				button.click_proc()
			}
		}

		button.was_hovered = is_hovered

		button.hot_t += (target - button.hot_t)*rate
		y += line_height + _PADDING
	}
}

scn_main_menu_draw :: proc(alpha: f32) {
	GFX_begin_frame()
	GFX_clear_background(M_FCOLOR_BLACK)

	GFX_begin_3d_renderer(&_ctx.ren3d, _ctx.cam)

	GFX_add_3d_light(&_ctx.ren3d, {
		position = {0.9, 1.5, -1.3},
		intensity = 1.6,
		radius = 12.0,
		color = {1.0, 1.0, 1.0},
		falloff = 2.0,
	})

	GFX_draw_3d_rect(
		&_ctx.ren3d,
		{-10000.0, 0.0, -10000.0}, {0.0, 1.0, 0.0}, {127, 127, 127, 255},
		{ 10000.0, 0.0, -10000.0}, {0.0, 1.0, 0.0}, {127, 127, 127, 255},
		{ 10000.0, 0.0,  10000.0}, {0.0, 1.0, 0.0}, {127, 127, 127, 255},
		{-10000.0, 0.0,  10000.0}, {0.0, 1.0, 0.0}, {127, 127, 127, 255},
	)

	{
		tex_width := sg.query_image_width(_ctx.tung_tung_sahur_tex.texture)
		tex_height := sg.query_image_height(_ctx.tung_tung_sahur_tex.texture)
		GFX_draw_3d_billboard_texture(
			&_ctx.ren3d,
			_ctx.tung_tung_sahur_tex.texture,
			_ctx.tung_tung_sahur_tex.sampler,
			{1.0, 1.0, -1.5},
			{1.0, 1.0},
			{0.0, 0.0, f32(tex_width), f32(tex_height)},
			M_COLOR_WHITE,
			true,
		)
	}

	GFX_end_3d_renderer(&_ctx.ren3d)

	GFX_begin_2d_renderer(&_ctx.ren2d)

	window_width: f32
	window_height: f32
	{
		w: i32
		h: i32
		sdl.GetWindowSize(WND_get_handle(), &w, &h)
		window_width = f32(w)
		window_height = f32(h)
	}

	scale_x := window_width/WINDOW_WIDTH
	scale_y := window_height/WINDOW_HEIGHT
	scale := min(scale_x, scale_y)

	GFX_draw_post_fx(&_ctx.ren_fx, &_ctx.ren2d, &_ctx.ren3d)

	// text
	{
		font_height := f32(_ctx.font.base_size)*_TEXT_SCALE*scale
		line_height := font_height*1.2

		GFX_draw_2d_string(
			&_ctx.ren2d,
			_ctx.font,
			"BRAINROT SHOOTER",
			{44.0*scale, 40.0*scale},
			M_COLOR_WHITE,
			(_TEXT_SCALE + 3.0)*scale,
		)

		GFX_draw_2d_string(
			&_ctx.ren2d,
			_ctx.font,
			"By Rundis Wannapahun 6/1 #10",
			{16.0*scale, window_height - f32(_ctx.font.base_size)*1.25*scale*1.2},
			M_COLOR_WHITE,
			1.3*scale,
		)

		y := window_height/2.0 - (line_height*len(_buttons))/2.0 - (_PADDING*(len(_buttons) - 1))/2.0

		for &button in _buttons {
			rect := M_Rect{44.0*scale, y, window_width/4.0, line_height}

			GFX_draw_2d_string(
				&_ctx.ren2d,
				_ctx.font,
				button.text,
				{rect.x*scale, y},
				M_COLOR_WHITE,
				_TEXT_SCALE*scale,
			)

			GFX_draw_2d_line(
				&_ctx.ren2d,
				{rect.x*scale, y + line_height},
				{rect.x*scale + rect.width*button.hot_t, y + line_height},
				M_COLOR_WHITE,
				6.0*scale,
			)

			y += line_height + _PADDING
		}
	}

	GFX_end_2d_renderer(&_ctx.ren2d)

	GFX_end_frame()
	sg.commit()
}
