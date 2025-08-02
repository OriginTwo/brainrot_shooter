package game

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:math/ease"
import "core:math/rand"

import sdl "vendor:sdl3"

import sg "lib:sokol/gfx"

SCN_GAME_OVER_HANDLE :: SCN_Handle(#hash("game_over", "fnv64a"))
SCN_GAME_OVER_CALLBACKS :: SCN_Callbacks{
	scn_game_over_init,
	scn_game_over_uninit,
	scn_game_over_tick,
	scn_game_over_draw,
}

@(private="file") _PADDING :: 8.0

@(private="file")
_ctx: struct {
	ren2d: GFX_2D_Renderer,
	font: GFX_Font,

	hovered_sound: AUD_Sound,

	kill_counts: [dynamic]_Kill_Count,
}

@(private="file")
_Kill_Count :: struct {
	name: string,
	count: int,
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
		text = "Play Again",
		click_proc = _play_again_button_proc,
	},
	{
		text = "Back to Main Menu",
		click_proc = _to_main_menu_button_proc,
	},
}

@(private="file")
_play_again_button_proc :: proc() {
	SCN_change(SCN_GAME_HANDLE)
}

@(private="file")
_to_main_menu_button_proc :: proc() {
	SCN_change(SCN_MAIN_MENU_HANDLE)
}

scn_game_over_add_kill_count :: proc(name: string, count: int) {
	append(&_ctx.kill_counts, _Kill_Count{
		name = name,
		count = count,
	})
}

scn_game_over_init :: proc() {
	GFX_create_2d_renderer(&_ctx.ren2d)

	{
		img: GFX_Image
		GFX_load_image_from_file(&img, "res/font/font_big.png")
		GFX_load_font_from_image(&_ctx.font, img)
		GFX_unload_image(&img)
	}

	RES_load_sound(&_ctx.hovered_sound, RES_ID_SOUND_UI_HOVERED_WAV)
}

scn_game_over_uninit :: proc() {
	delete(_ctx.kill_counts)

	AUD_unload_sound(&_ctx.hovered_sound)

	GFX_unload_font(&_ctx.font)
	GFX_destroy_2d_renderer(&_ctx.ren2d)
	_ctx = {}
}

scn_game_over_tick :: proc(input: INP_State, delta: f32) {
	now := f32(TIME_now())

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

	text_scale: f32 = 2.5
	font_height := f32(_ctx.font.base_size)*text_scale*scale
	line_height := font_height*1.2
	y := window_height - line_height*1.5

	#reverse for &button in _buttons {
		mouse := INP_get_mouse_pos(input)
		rate := 1.0 - math.pow(2.0, -25.0*delta)
		rect := M_Rect{window_width/2.0, y, window_width/4.0, line_height}
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

		y -= line_height + _PADDING
	}
}

scn_game_over_draw :: proc(alpha: f32) {
	GFX_begin_frame()
	GFX_clear_background(M_FCOLOR_BLACK)

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

	// text
	{
		text_scale: f32 = 2.0
		font_height := f32(_ctx.font.base_size)*text_scale*scale
		line_height := font_height

		GFX_draw_2d_string_centered(
			&_ctx.ren2d,
			_ctx.font,
			"YOU DIED",
			{window_width/2.0, 40.0*scale},
			M_COLOR_WHITE,
			6.0*scale,
		)

		y := window_height/2.0 - (line_height*f32(len(_ctx.kill_counts)))/2.0

		for kill_count in _ctx.kill_counts {
			GFX_draw_2d_string(
				&_ctx.ren2d,
				_ctx.font,
				kill_count.name,
				{window_width/4.0, y},
				M_COLOR_WHITE,
				text_scale*scale,
			)

			count_str := fmt.tprintf("%d", kill_count.count)
			GFX_draw_2d_string(
				&_ctx.ren2d,
				_ctx.font,
				count_str,
				{window_width*3.0/4.0 - GFX_get_2d_string_width(_ctx.font, count_str, text_scale*scale), y},
				M_COLOR_WHITE,
				text_scale*scale,
			)

			y += line_height + _PADDING
		}

		text_scale = 2.5
		font_height = f32(_ctx.font.base_size)*text_scale*scale
		line_height = font_height*1.2
		y = window_height - line_height*1.5

		#reverse for &button in _buttons {
			rect := M_Rect{window_width/2.0, y, window_width/4.0, line_height}

			GFX_draw_2d_string_centered(
				&_ctx.ren2d,
				_ctx.font,
				button.text,
				{rect.x, y},
				M_COLOR_WHITE,
				text_scale*scale,
			)

			GFX_draw_2d_line(
				&_ctx.ren2d,
				{rect.x - rect.width*button.hot_t/2.0, y + line_height},
				{rect.x + rect.width*button.hot_t/2.0, y + line_height},
				M_COLOR_WHITE,
				6.0*scale,
			)

			y -= line_height + _PADDING
		}
	}

	GFX_end_2d_renderer(&_ctx.ren2d)

	GFX_end_frame()
	sg.commit()
}
