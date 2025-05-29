package game

import "core:fmt"
import "core:math"
import "core:bytes"
import "core:unicode/utf16"
import "core:path/filepath"
import win32 "core:sys/windows"

import sdl "vendor:sdl3"

import im "lib:imgui"
import sg "lib:sokol/gfx"

LVL_UNIT_PER_GRID :: 0.5

LVL_Sector :: struct {
	id: int,
	position: [2]int, // x, z
	size: [2]int,
	floor_height: f32,
	ceiling_height: f32,
}

LVL_Level :: struct {
	sectors: [dynamic]LVL_Sector,
}

@(private="file") _INVALID_GRID :: [2]int{65535, 65535}
@(private="file") _2D_GRID_SIZE :: 24
@(private="file") _2D_GRID_POINT_SIZE :: 4
@(private="file") _2D_CAM_SPEED :: 400.0
@(private="file") _DEFAULT_FLOOR_HEIGHT :: 0.0
@(private="file") _DEFAULT_CEILING_HEIGHT :: 3.0

when DEV_BUILD {

SCN_EDITOR_HANDLE :: SCN_Handle(#hash("editor", "fnv64a"))
SCN_EDITOR_CALLBACKS :: SCN_Callbacks{
	scn_editor_init,
	scn_editor_uninit,
	scn_editor_tick,
	scn_editor_draw,
}

@(private="file")
_ctx: struct {
	ren2d: GFX_2D_Renderer,
	ren3d: GFX_3D_Renderer,
	ren_fx: GFX_Post_FX_Renderer,
	cam: GFX_Camera,

	level: LVL_Level,

	mouse_pressed_grid: [2]int,

	is_placing_sector: bool,
	placing_sector_p1: [2]int,
	placing_sector_p2: [2]int,

	is_3d_preview: bool,

	offset_2d: M_Vec2f32,
}

scn_editor_init :: proc() {
	GFX_create_2d_renderer(&_ctx.ren2d)
	GFX_create_3d_renderer(&_ctx.ren3d, VIEWPORT_WIDTH, VIEWPORT_HEIGHT)
	GFX_create_post_fx_renderer(&_ctx.ren_fx, VIEWPORT_WIDTH, VIEWPORT_HEIGHT)

	_ctx.cam.fovy = math.PI/2.0

	_ctx.mouse_pressed_grid = _INVALID_GRID

	{
		win_size: [2]i32
		sdl.GetWindowSize(WND_get_handle(), &win_size.x, &win_size.y)
		_ctx.offset_2d = -{f32(win_size.x), f32(win_size.y)}/2.0
	}
}

scn_editor_uninit :: proc() {
	GFX_destroy_2d_renderer(&_ctx.ren2d)
	GFX_destroy_3d_renderer(&_ctx.ren3d)
	GFX_destroy_post_fx_renderer(&_ctx.ren_fx)
	_ctx = {}
}

scn_editor_tick :: proc(input: INP_State, delta: f32) {
	if INP_is_key_pressed(input, .F1) {
		SCN_change(SCN_GAME_HANDLE)
	}

	if _ctx.is_3d_preview {
		return
	}

	{
		vel := M_Vec2f32{
			f32(int(INP_is_key_down(input, .D)) - int(INP_is_key_down(input, .A))),
			f32(int(INP_is_key_down(input, .S)) - int(INP_is_key_down(input, .W))),
		}*_2D_CAM_SPEED
		if INP_is_key_down(input, .LSHIFT) {
			vel *= 3.0
		}
		_ctx.offset_2d += vel*delta
	}

	world_mouse_pos := INP_get_mouse_pos(input) + _ctx.offset_2d
	grid_mouse_pos: [2]int
	{
		mp := [2]int{
			int(world_mouse_pos.x if world_mouse_pos.x > 0 else world_mouse_pos.x - _2D_GRID_SIZE),
			int(world_mouse_pos.y if world_mouse_pos.y > 0 else world_mouse_pos.y - _2D_GRID_SIZE),
		}
		grid_mouse_pos = mp/_2D_GRID_SIZE
	}

	if INP_is_mouse_pressed(input, .Left) {
		_ctx.mouse_pressed_grid = grid_mouse_pos
	}

	if INP_is_mouse_down(input, .Left) && !_ctx.is_placing_sector && grid_mouse_pos - _ctx.mouse_pressed_grid != {} {
		_ctx.is_placing_sector = true
		_ctx.placing_sector_p1 = _ctx.mouse_pressed_grid
		_ctx.placing_sector_p2 = grid_mouse_pos
	}

	if _ctx.is_placing_sector {
		_ctx.placing_sector_p2 = grid_mouse_pos
	}

	if INP_is_mouse_released(input, .Left) {
		if _ctx.is_placing_sector {
			// placing sector
			minimum := [2]int{
				min(_ctx.placing_sector_p1.x, _ctx.placing_sector_p2.x),
				min(_ctx.placing_sector_p1.y, _ctx.placing_sector_p2.y),
			}
			maximum := [2]int{
				max(_ctx.placing_sector_p1.x, _ctx.placing_sector_p2.x) + 1,
				max(_ctx.placing_sector_p1.y, _ctx.placing_sector_p2.y) + 1,
			}

			append(&_ctx.level.sectors, LVL_Sector{
				id = len(_ctx.level.sectors),
				position = minimum,
				size = maximum - minimum,
				floor_height = _DEFAULT_FLOOR_HEIGHT,
				ceiling_height = _DEFAULT_CEILING_HEIGHT,
			})

			_ctx.is_placing_sector = false
			_ctx.placing_sector_p1 = _INVALID_GRID
			_ctx.placing_sector_p2 = _INVALID_GRID
		} else {
			// selecting sector
		}

		_ctx.mouse_pressed_grid = _INVALID_GRID
	}
}

scn_editor_draw :: proc(alpha: f32) {
	win_size: [2]i32
	sdl.GetWindowSize(WND_get_handle(), &win_size.x, &win_size.y)

	GFX_begin_frame()
	GFX_clear_background(M_FCOLOR_BLACK)

	if !_ctx.is_3d_preview {
		GFX_begin_2d_renderer(&_ctx.ren2d)

		// draw grid
		GFX_set_2d_layer(&_ctx.ren2d, -10)
		{
			minimum := _ctx.offset_2d
			maximum := _ctx.offset_2d + {f32(win_size.x), f32(win_size.y)}

			start_x := int(minimum.x)/_2D_GRID_SIZE
			start_y := int(minimum.y)/_2D_GRID_SIZE
			end_x := int(maximum.x)/_2D_GRID_SIZE + 1
			end_y := int(maximum.y)/_2D_GRID_SIZE + 1

			for y := start_y; y < end_y; y += 1 {
				for x := start_x; x < end_x; x += 1 {
					GFX_draw_2d_rect(
						&_ctx.ren2d,
						{
							f32(x*_2D_GRID_SIZE) - _2D_GRID_POINT_SIZE/2.0 - _ctx.offset_2d.x,
							f32(y*_2D_GRID_SIZE) - _2D_GRID_POINT_SIZE/2.0 - _ctx.offset_2d.y,
							_2D_GRID_POINT_SIZE,
							_2D_GRID_POINT_SIZE,
						},
						{127, 127, 127, 200},
					)
				}
			}
		}

		// draw origin
		GFX_set_2d_layer(&_ctx.ren2d, 100)
		GFX_draw_2d_rect(&_ctx.ren2d, {-4.0 - _ctx.offset_2d.x, -4.0 - _ctx.offset_2d.y, 8.0, 8.0}, M_COLOR_MAGENTA)

		// draw sector
		GFX_set_2d_layer(&_ctx.ren2d, 0)
		for sector in _ctx.level.sectors {
			GFX_draw_2d_rect_line(
				&_ctx.ren2d,
				{
					f32(sector.position.x)*_2D_GRID_SIZE - _ctx.offset_2d.x,
					f32(sector.position.y)*_2D_GRID_SIZE - _ctx.offset_2d.y,
					f32(sector.size.x)*_2D_GRID_SIZE,
					f32(sector.size.y)*_2D_GRID_SIZE,
				},
				{255, 255, 255, 200},
				2.0,
			)
		}

		// draw sector preview
		GFX_set_2d_layer(&_ctx.ren2d, 200)
		if _ctx.is_placing_sector {
			minimum := [2]int{
				min(_ctx.placing_sector_p1.x, _ctx.placing_sector_p2.x),
				min(_ctx.placing_sector_p1.y, _ctx.placing_sector_p2.y),
			}
			maximum := [2]int{
				max(_ctx.placing_sector_p1.x, _ctx.placing_sector_p2.x) + 1,
				max(_ctx.placing_sector_p1.y, _ctx.placing_sector_p2.y) + 1,
			}

			GFX_draw_2d_rect_line(
				&_ctx.ren2d,
				{
					f32(minimum.x)*_2D_GRID_SIZE - _ctx.offset_2d.x,
					f32(minimum.y)*_2D_GRID_SIZE - _ctx.offset_2d.y,
					f32(maximum.x - minimum.x)*_2D_GRID_SIZE,
					f32(maximum.y - minimum.y)*_2D_GRID_SIZE,
				},
				{255, 200, 25, u8((math.sin(8.0*f32(TIME_now()))*0.35 + 0.65)*255.0)},
				2.0,
			)
		}

		GFX_end_2d_renderer(&_ctx.ren2d)
	} else {
		GFX_begin_3d_renderer(&_ctx.ren3d, _ctx.cam)

		GFX_draw_3d_rect(
			&_ctx.ren3d,
			{-10.0*LVL_UNIT_PER_GRID, -1.0, -10.0*LVL_UNIT_PER_GRID}, {0.0, 1.0, 0.0}, {127, 127, 127, 255},
			{ 10.0*LVL_UNIT_PER_GRID, -1.0, -10.0*LVL_UNIT_PER_GRID}, {0.0, 1.0, 0.0}, {127, 127, 127, 255},
			{ 10.0*LVL_UNIT_PER_GRID, -1.0,  10.0*LVL_UNIT_PER_GRID}, {0.0, 1.0, 0.0}, {127, 127, 127, 255},
			{-10.0*LVL_UNIT_PER_GRID, -1.0,  10.0*LVL_UNIT_PER_GRID}, {0.0, 1.0, 0.0}, {127, 127, 127, 255},
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
			{1.0*LVL_UNIT_PER_GRID, 2.0},
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

		GFX_add_3d_light(&_ctx.ren3d, {
			position = {-3.0, 1.5, -2.0},
			intensity = 5.0,
			radius = 8.0,
			color = {1.0, 0.4, 0.4},
			falloff = 1.0,
		})

		GFX_add_3d_light(&_ctx.ren3d, {
			position = {3.0, 1.5, -2.0},
			intensity = 5.0,
			radius = 8.0,
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

		GFX_do_post_fx_bloom(&_ctx.ren_fx, _ctx.ren3d.bright_color_texture, 0.01)
		GFX_do_post_fx_tonemap(&_ctx.ren_fx, _ctx.ren_fx.bloom_mip_chain[0].texture, 1.2, 1.0)
		GFX_do_post_fx_additive(
			&_ctx.ren_fx,
			_ctx.ren3d.color_texture,
			_ctx.ren_fx.tonemap_texture,
			_ctx.ren_fx.bloom_sampler,
			_ctx.ren_fx.bloom_sampler,
		)

		GFX_begin_2d_renderer(&_ctx.ren2d)

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

		GFX_set_2d_layer(&_ctx.ren2d, 10)

		GFX_end_2d_renderer(&_ctx.ren2d)
	}

	im.SetNextWindowSize({200, 400})
	if im.Begin("Debug") {
		im.SliderFloat("pos_x", &_ctx.cam.position.x, -10.0, 10.0)
		im.SliderFloat("pos_y", &_ctx.cam.position.y, -10.0, 10.0)
		im.SliderFloat("pos_z", &_ctx.cam.position.z, -10.0, 10.0)
		im.SliderFloat("pitch", &_ctx.cam.pitch, -89.0, 89.0)
		im.SliderFloat("yaw", &_ctx.cam.yaw, 0.0, 360.0)
		im.SliderFloat("roll", &_ctx.cam.roll, -30.0, 30.0)
	}
	im.End()

	GFX_end_frame()

	sg.commit()
}

} // when DEV_BUILD
