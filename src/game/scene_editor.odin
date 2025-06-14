package game

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:bytes"
import "core:unicode/utf16"
import "core:path/filepath"
import win32 "core:sys/windows"

import sdl "vendor:sdl3"

import im "lib:imgui"
import sg "lib:sokol/gfx"

/*
TODO: when switching to 3d view, construct the level in "runtime" format

	- walls will be construct like 2d light & shadow where there will be and
		intermediate cells that will have the flags of which wall direction they have

NOTE: the cell that is inside a sector and has a neighboring cell inside another sector will not have
	collision and some might have 2 walls as well (top & bottom from different floor & ceiling y)
	- another idea: every wall has collision, but if "wall_height <= 0.25" then you snap up the wall

RUNTIME FORMAT:
	- sectors
		- position   : Vec2f32
		- size       : Vec2f32
		- floor_y    : f32
		- ceiling_y  : f32
	- walls
		- p1         : Vec2f32
		- p2         : Vec2f32
		- height     : f32
		- normal     : Vec3f32
	- chunks (for collision & rendering optimization)
		- sector indices  : int
		- wall indices    : int
*/


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

	level: _Level,
	level_preview: LVL_Level,

	world_mouse_pos: [2]f32,
	grid_mouse_pos: [2]int,

	mouse_pressed_grid: [2]int,

	hovering_sector_handle: _Sector_Handle,
	selected_sector_handle: _Sector_Handle,
	selected_sector_window_open: bool,
	is_placing_sector: bool,
	placing_sector_p1: [2]int,
	placing_sector_p2: [2]int,
	linking_sector1_handle: _Sector_Handle,
	linking_sector2_handle: _Sector_Handle,

	is_3d_view: bool,
	was_3d_view: bool,

	offset_2d: M_Vec2f32,
}

scn_editor_init :: proc() {
	GFX_create_2d_renderer(&_ctx.ren2d)
	GFX_create_3d_renderer(&_ctx.ren3d, VIEWPORT_WIDTH, VIEWPORT_HEIGHT)
	GFX_create_post_fx_renderer(&_ctx.ren_fx, VIEWPORT_WIDTH, VIEWPORT_HEIGHT)

	_ctx.cam.position.y = 1.5
	_ctx.cam.fovy = math.PI/2.0

	_ctx.mouse_pressed_grid = _INVALID_GRID_COORD

	_ctx.hovering_sector_handle = _INVALID_SECTOR_HANDLE
	_ctx.selected_sector_handle = _INVALID_SECTOR_HANDLE
	_ctx.linking_sector1_handle = _INVALID_SECTOR_HANDLE
	_ctx.linking_sector2_handle = _INVALID_SECTOR_HANDLE

	{
		win_size: [2]i32
		sdl.GetWindowSize(WND_get_handle(), &win_size.x, &win_size.y)
		_ctx.offset_2d = -{f32(win_size.x), f32(win_size.y)}/2.0
	}
}

scn_editor_uninit :: proc() {
	for &sector in _ctx.level.sectors {
		delete(sector.linked_sectors)
	}
	delete(_ctx.level.sectors)
	delete(_ctx.level.free_sector_slots)

	_delete_level_preview()

	GFX_destroy_2d_renderer(&_ctx.ren2d)
	GFX_destroy_3d_renderer(&_ctx.ren3d)
	GFX_destroy_post_fx_renderer(&_ctx.ren_fx)

	_ctx = {}
}

scn_editor_tick :: proc(input: INP_State, delta: f32) {
	if INP_is_key_pressed(input, .F1) {
		SCN_change(SCN_GAME_HANDLE)
	}

	if im.IsAnyItemHovered() ||
		im.IsAnyItemActive() ||
		im.IsWindowHovered(im.HoveredFlags_AnyWindow)
	{
		return
	}

	if _ctx.is_3d_view {
		_tick_3d_view(input, delta)
	} else {
		_tick_2d_view(input, delta)
	}
}

scn_editor_draw :: proc(alpha: f32) {
	GFX_begin_frame()
	GFX_clear_background(M_FCOLOR_BLACK)

	if _ctx.is_3d_view {
		if !_ctx.was_3d_view {
			_construct_level_preview()
		}

		_draw_3d_view(alpha)
		_do_3d_view_ui()
	} else {
		_draw_2d_view(alpha)
		_do_2d_view_ui()
	}

	_ctx.was_3d_view = _ctx.is_3d_view

	im.SetNextWindowPos(_MAIN_UI_WINDOW_POSITION, .FirstUseEver)
	im.SetNextWindowSize({200.0, 300.0}, .FirstUseEver)
	im.Begin("MAIN")
	im.Checkbox("3D_VIEW", &_ctx.is_3d_view)
	im.End()

	GFX_end_frame()

	sg.commit()
}



@(private="file") _UNIT_PER_GRID :: 0.5
@(private="file") _MAX_SECTOR_GRID_COORD :: 65535
@(private="file") _INVALID_GRID_COORD :: [2]int{_MAX_SECTOR_GRID_COORD, _MAX_SECTOR_GRID_COORD}
@(private="file") _2D_GRID_SIZE :: 24
@(private="file") _2D_GRID_POINT_SIZE :: 4
@(private="file") _2D_CAM_SPEED :: 400.0
@(private="file") _DEFAULT_FLOOR_Y :: 0.0
@(private="file") _DEFAULT_CEILING_Y :: 3.0
@(private="file") _MAIN_UI_WINDOW_POSITION :: M_Vec2f32{20.0, 20.0}
@(private="file") _UI_WINDOW_OPEN_OFFSET :: M_Vec2f32{30.0, 30.0}


@(private="file")
_tick_2d_view :: proc(input: INP_State, delta: f32) {
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

	_ctx.world_mouse_pos = INP_get_mouse_pos(input) + _ctx.offset_2d
	{
		mp := [2]int{
			int(_ctx.world_mouse_pos.x if _ctx.world_mouse_pos.x > 0 else _ctx.world_mouse_pos.x - _2D_GRID_SIZE),
			int(_ctx.world_mouse_pos.y if _ctx.world_mouse_pos.y > 0 else _ctx.world_mouse_pos.y - _2D_GRID_SIZE),
		}
		_ctx.grid_mouse_pos = mp/_2D_GRID_SIZE
	}

	if !INP_is_mouse_down(input, .Left) && INP_get_mouse_delta(input) != {} {
		// TODO: chunk optimization
		hovering_sector_handle := _INVALID_SECTOR_HANDLE
		hovering_sector_area := _MAX_SECTOR_GRID_COORD*_MAX_SECTOR_GRID_COORD

		for sector in _ctx.level.sectors {
			if sector.is_deleted {
				continue
			}

			if (sector.position.x <= _ctx.grid_mouse_pos.x && _ctx.grid_mouse_pos.x < sector.position.x + sector.size.x) &&
				(sector.position.y <= _ctx.grid_mouse_pos.y && _ctx.grid_mouse_pos.y < sector.position.y + sector.size.y)
			{
				area := sector.size.x*sector.size.y
				if area < hovering_sector_area {
					hovering_sector_handle = sector.handle
					hovering_sector_area = area
				}
			}
		}

		_ctx.hovering_sector_handle = hovering_sector_handle
	}

	if INP_is_mouse_pressed(input, .Left) {
		_ctx.mouse_pressed_grid = _ctx.grid_mouse_pos
	}

	if INP_is_mouse_down(input, .Left) &&
		!_ctx.is_placing_sector &&
		_ctx.grid_mouse_pos - _ctx.mouse_pressed_grid != {}
	{
		_ctx.is_placing_sector = true
		_ctx.placing_sector_p1 = _ctx.mouse_pressed_grid
		_ctx.placing_sector_p2 = _ctx.grid_mouse_pos
	}

	if _ctx.is_placing_sector {
		_ctx.placing_sector_p2 = _ctx.grid_mouse_pos
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

			_append_sector(
				minimum,
				maximum - minimum,
				_DEFAULT_FLOOR_Y,
				_DEFAULT_CEILING_Y,
			)

			_ctx.is_placing_sector = false
			_ctx.placing_sector_p1 = _INVALID_GRID_COORD
			_ctx.placing_sector_p2 = _INVALID_GRID_COORD
		} else {
			// selecting sector
			_ctx.selected_sector_handle = _ctx.hovering_sector_handle
			_ctx.selected_sector_window_open = _ctx.hovering_sector_handle != _INVALID_SECTOR_HANDLE
		}

		_ctx.mouse_pressed_grid = _INVALID_GRID_COORD
	}

	if INP_is_mouse_pressed(input, .Right) && _ctx.hovering_sector_handle != _INVALID_SECTOR_HANDLE {
		_ctx.linking_sector1_handle = _ctx.hovering_sector_handle
	}

	if INP_is_mouse_released(input, .Right) && _ctx.hovering_sector_handle != _INVALID_SECTOR_HANDLE {
		_ctx.linking_sector2_handle = _ctx.hovering_sector_handle

		if _ctx.linking_sector2_handle != _ctx.linking_sector1_handle {
			sector1 := _get_sector_ptr(_ctx.linking_sector1_handle)
			sector2 := _get_sector_ptr(_ctx.linking_sector2_handle)

			if sector1 != nil && sector2 != nil {
				sector1_to_sector2_link_index := -1
				sector2_to_sector1_link_index := -1

				for linked_sector_handle, i in sector1.linked_sectors {
					if linked_sector_handle == sector2.handle {
						sector1_to_sector2_link_index = i
						break
					}
				}

				for linked_sector_handle, i in sector2.linked_sectors {
					if linked_sector_handle == sector1.handle {
						sector2_to_sector1_link_index = i
						break
					}
				}

				if sector1_to_sector2_link_index == -1 && sector2_to_sector1_link_index == -1 {
					// not linked -> link
					append(&sector1.linked_sectors, _ctx.linking_sector2_handle)
					append(&sector2.linked_sectors, _ctx.linking_sector1_handle)
				} else {
					// already linked -> remove
					unordered_remove(&sector1.linked_sectors, sector1_to_sector2_link_index)
					unordered_remove(&sector2.linked_sectors, sector2_to_sector1_link_index)
				}
			}
		}

		_ctx.linking_sector1_handle = _INVALID_SECTOR_HANDLE
		_ctx.linking_sector2_handle = _INVALID_SECTOR_HANDLE
	}
}

@(private="file")
_draw_2d_view :: proc(alpha: f32) {
	win_size: [2]i32
	sdl.GetWindowSize(WND_get_handle(), &win_size.x, &win_size.y)

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
		if sector.is_deleted {
			continue
		}

		rect := M_Rect{
			f32(sector.position.x)*_2D_GRID_SIZE - _ctx.offset_2d.x,
			f32(sector.position.y)*_2D_GRID_SIZE - _ctx.offset_2d.y,
			f32(sector.size.x)*_2D_GRID_SIZE,
			f32(sector.size.y)*_2D_GRID_SIZE,
		}

		if _ctx.hovering_sector_handle == sector.handle || _ctx.selected_sector_handle == sector.handle {
			color := M_Color{255, 200, 25, 100}  // hover color by default

			if _ctx.selected_sector_handle == sector.handle {
				color = {255, 100, 25, u8((math.sin(8.0*f32(TIME_now()))*0.3 + 0.7)*100.0)}
			}

			GFX_draw_2d_rect(&_ctx.ren2d, rect, color)

			GFX_set_2d_layer(&_ctx.ren2d, 1)
			for linked_sector_handle in sector.linked_sectors {
				if linked_sector := _get_sector_ptr(linked_sector_handle); linked_sector != nil {
					p1 := M_Vec2f32{
						f32(sector.position.x) + f32(sector.size.x)/2.0,
						f32(sector.position.y) + f32(sector.size.y)/2.0,
					}*_2D_GRID_SIZE - _ctx.offset_2d
					p2 := M_Vec2f32{
						f32(linked_sector.position.x) + f32(linked_sector.size.x)/2.0,
						f32(linked_sector.position.y) + f32(linked_sector.size.y)/2.0,
					}*_2D_GRID_SIZE - _ctx.offset_2d

					GFX_draw_2d_line(&_ctx.ren2d, p1, p2, M_COLOR_MAGENTA, 2.0)
				}
			}
		}

		GFX_set_2d_layer(&_ctx.ren2d, 0)
		GFX_draw_2d_rect_line(&_ctx.ren2d, rect, {255, 255, 255, 200}, 2.0)
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

	// draw sector link preview
	if _ctx.linking_sector1_handle != _INVALID_SECTOR_HANDLE {
		if sector := _get_sector_ptr(_ctx.linking_sector1_handle); sector != nil {
			p1 := M_Vec2f32{
				f32(sector.position.x) + f32(sector.size.x)/2.0,
				f32(sector.position.y) + f32(sector.size.y)/2.0,
			}*_2D_GRID_SIZE - _ctx.offset_2d
			p2 := _ctx.world_mouse_pos - _ctx.offset_2d

			color := M_Color{255, 200, 25, u8((math.sin(8.0*f32(TIME_now()))*0.3 + 0.7)*255.0)}

			GFX_draw_2d_line(&_ctx.ren2d, p1, p2, color, 2.0)
		}
	}

	GFX_end_2d_renderer(&_ctx.ren2d)
}

@(private="file")
_do_2d_view_ui :: proc() {
	if _ctx.selected_sector_window_open {
		selected_sector := &_ctx.level.sectors[_ctx.selected_sector_handle.index]
		im.SetNextWindowPos(_MAIN_UI_WINDOW_POSITION + _UI_WINDOW_OPEN_OFFSET, .FirstUseEver)
		im.SetNextWindowSize({300.0, 400.0}, .FirstUseEver)
		im.Begin("SELECTED SECTOR", &_ctx.selected_sector_window_open)
		im.Text("ID: %d, GEN: %d", _ctx.selected_sector_handle.index, _ctx.selected_sector_handle.generation)
		{
			SPACING :: 4.0
			x := i32(selected_sector.position.x)
			im.Text("POS_X:"); im.SameLine()
			im.SetNextItemWidth(50.0)
			im.DragInt("###SELECTED_SECTOR_POS_X", &x); im.SameLine(spacing = SPACING)
			if im.Button("-###SELECTED_SECTOR_POS_X_DECREMENT") {x -= 1} im.SameLine(spacing = SPACING)
			if im.Button("+###SELECTED_SECTOR_POS_X_INCREMENT") {x += 1}
			selected_sector.position.x = int(x)

			y := i32(selected_sector.position.y)
			im.Text("POS_Y:"); im.SameLine()
			im.SetNextItemWidth(50.0)
			im.DragInt("###SELECTED_SECTOR_POS_Y", &y); im.SameLine(spacing = SPACING)
			if im.Button("-###SELECTED_SECTOR_POS_Y_DECREMENT") {y -= 1} im.SameLine(spacing = SPACING)
			if im.Button("+###SELECTED_SECTOR_POS_Y_INCREMENT") {y += 1}
			selected_sector.position.y = int(y)

			width := i32(selected_sector.size.x)
			im.Text("WIDTH:"); im.SameLine()
			im.SetNextItemWidth(50.0)
			im.DragInt("###SELECTED_SECTOR_WIDTH", &width, v_min = 1, v_max = _MAX_SECTOR_GRID_COORD); im.SameLine(spacing = SPACING)
			if im.Button("-###SELECTED_SECTOR_WIDTH_DECREMENT") && width > 1                       {width -= 1} im.SameLine(spacing = SPACING)
			if im.Button("+###SELECTED_SECTOR_WIDTH_INCREMENT") && width < _MAX_SECTOR_GRID_COORD - 1 {width += 1}
			selected_sector.size.x = int(width)

			height := i32(selected_sector.size.y)
			im.Text("HEIGHT:"); im.SameLine()
			im.SetNextItemWidth(50.0)
			im.DragInt("###SELECTED_SECTOR_HEIGHT", &height, v_min = 1, v_max = _MAX_SECTOR_GRID_COORD); im.SameLine(spacing = SPACING)
			if im.Button("-###SELECTED_SECTOR_HEIGHT_DECREMENT") && height > 1                       {height -= 1} im.SameLine(spacing = SPACING)
			if im.Button("+###SELECTED_SECTOR_HEIGHT_INCREMENT") && height < _MAX_SECTOR_GRID_COORD - 1 {height += 1}
			selected_sector.size.y = int(height)

			floor_and_ceiling_increment := f32(_UNIT_PER_GRID/2.0)

			floor_y_max := selected_sector.ceiling_y - floor_and_ceiling_increment
			im.Text("FLOOR_Y:"); im.SameLine()
			im.SetNextItemWidth(80.0)
			im.DragFloat("###SELECTED_SECTOR_FLOOR_Y", &selected_sector.floor_y, floor_and_ceiling_increment, -1000.0, floor_y_max); im.SameLine(spacing = SPACING)
			if im.Button("-###SELECTED_SECTOR_FLOOR_Y_DECREMENT") {selected_sector.floor_y -= floor_and_ceiling_increment} im.SameLine(spacing = SPACING)
			if im.Button("+###SELECTED_SECTOR_FLOOR_Y_INCREMENT") {selected_sector.floor_y += floor_and_ceiling_increment}
			selected_sector.floor_y = min(selected_sector.floor_y, floor_y_max)

			ceiling_y_min := selected_sector.floor_y + floor_and_ceiling_increment
			im.Text("CEILING_Y:"); im.SameLine()
			im.SetNextItemWidth(80.0)
			im.DragFloat("###SELECTED_SECTOR_CEILING_Y", &selected_sector.ceiling_y, floor_and_ceiling_increment, ceiling_y_min, 1000.0); im.SameLine(spacing = SPACING)
			if im.Button("-###SELECTED_SECTOR_CEILING_Y_DECREMENT") {selected_sector.ceiling_y -= floor_and_ceiling_increment} im.SameLine(spacing = SPACING)
			if im.Button("+###SELECTED_SECTOR_CEILING_Y_INCREMENT") {selected_sector.ceiling_y += floor_and_ceiling_increment}
			selected_sector.ceiling_y = max(selected_sector.ceiling_y, ceiling_y_min)

			if im.Button("DELETE") {
				_delete_sector(_ctx.selected_sector_handle)
				_ctx.selected_sector_handle = _INVALID_SECTOR_HANDLE
				_ctx.selected_sector_window_open = false
			}
		}
		im.End()
	}

	if !_ctx.selected_sector_window_open {
		_ctx.selected_sector_handle = _INVALID_SECTOR_HANDLE
	}
}

@(private="file")
_tick_3d_view :: proc(input: INP_State, delta: f32) {
	if INP_is_key_pressed(input, .TAB) {
		@(static) lock_mouse := false
		lock_mouse = !lock_mouse
		WND_lock_mouse(lock_mouse)
	}

	mdelta := INP_get_mouse_delta(input)

	_ctx.cam.pitch += mdelta.y*DEFAULT_MOUSE_SENSITIVITY
	_ctx.cam.yaw += mdelta.x*DEFAULT_MOUSE_SENSITIVITY

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
}

@(private="file")
_draw_3d_view :: proc(alpha: f32) {
	GFX_begin_3d_renderer(&_ctx.ren3d, _ctx.cam)

	LVL_draw(_ctx.level_preview, &_ctx.ren3d)

	// for sector in _ctx.level.sectors {
	// 	if sector.is_deleted {
	// 		continue
	// 	}

	// 	x1 := f32(sector.position.x)*_UNIT_PER_GRID
	// 	z1 := f32(sector.position.y)*_UNIT_PER_GRID
	// 	x2 := f32(sector.position.x + sector.size.x)*_UNIT_PER_GRID
	// 	z2 := f32(sector.position.y + sector.size.y)*_UNIT_PER_GRID

	// 	// floor
	// 	GFX_draw_3d_rect(
	// 		&_ctx.ren3d,
	// 		{x1, sector.floor_y, z1}, {0.0, 1.0, 0.0}, {127, 127, 127, 255},
	// 		{x2, sector.floor_y, z1}, {0.0, 1.0, 0.0}, {127, 127, 127, 255},
	// 		{x2, sector.floor_y, z2}, {0.0, 1.0, 0.0}, {127, 127, 127, 255},
	// 		{x1, sector.floor_y, z2}, {0.0, 1.0, 0.0}, {127, 127, 127, 255},
	// 	)

	// 	// ceiling
	// 	GFX_draw_3d_rect(
	// 		&_ctx.ren3d,
	// 		{x1, sector.ceiling_y, z2}, {0.0, -1.0, 0.0}, {127, 127, 127, 255},
	// 		{x2, sector.ceiling_y, z2}, {0.0, -1.0, 0.0}, {127, 127, 127, 255},
	// 		{x2, sector.ceiling_y, z1}, {0.0, -1.0, 0.0}, {127, 127, 127, 255},
	// 		{x1, sector.ceiling_y, z1}, {0.0, -1.0, 0.0}, {127, 127, 127, 255},
	// 	)

	// 	// walls
	// }

	GFX_add_3d_light(&_ctx.ren3d, {
		position = _ctx.cam.position,
		intensity = 1.0,
		radius = 100.0,
		color = {1.0, 1.0, 1.0},
		falloff = 0.0,
	})

	GFX_end_3d_renderer(&_ctx.ren3d)

	GFX_begin_2d_renderer(&_ctx.ren2d)
	GFX_draw_post_fx(&_ctx.ren_fx, &_ctx.ren2d, &_ctx.ren3d)
	GFX_end_2d_renderer(&_ctx.ren2d)
}

@(private="file")
_do_3d_view_ui :: proc() {
	im.SetNextWindowPos(_MAIN_UI_WINDOW_POSITION + _UI_WINDOW_OPEN_OFFSET, .FirstUseEver)
	im.SetNextWindowSize({200.0, 400.0}, .FirstUseEver)
	im.Begin("3D_VIEW")
	{
		im.DragFloat("CAM_X", &_ctx.cam.position.x, 0.125)
		im.DragFloat("CAM_Y", &_ctx.cam.position.y, 0.125)
		im.DragFloat("CAM_Z", &_ctx.cam.position.z, 0.125)
		im.SliderFloat("CAM_PITCH", &_ctx.cam.pitch, -89.0, 89.0)
		im.SliderFloat("CAM_YAW", &_ctx.cam.yaw, 0.0, 360.0)
		im.SliderFloat("CAM_ROLL", &_ctx.cam.roll, -30.0, 30.0)
	}
	im.End()
}


///////////////////////////////////////////////////////////
// EDITOR LEVEL
///////////////////////////////////////////////////////////
@(private="file")
_Sector_Handle :: struct {
	index: int,
	generation: u32,
}
@(private="file") _INVALID_SECTOR_HANDLE :: _Sector_Handle{-1, 0}

@(private="file")
_Sector :: struct {
	handle: _Sector_Handle,
	is_deleted: bool,
	position: [2]int, // x, z
	size: [2]int,
	floor_y: f32,
	ceiling_y: f32,
	linked_sectors: [dynamic]_Sector_Handle,
}

@(private="file")
_Level :: struct {
	sectors: [dynamic]_Sector,
	free_sector_slots: [dynamic]_Sector_Handle,
}

@(private="file")
_append_sector :: proc(position, size: [2]int, floor_y, ceiling_y: f32) {
	sector := _Sector{
		position = position,
		size = size,
		floor_y = floor_y,
		ceiling_y = ceiling_y,
	}

	if len(_ctx.level.free_sector_slots) > 0 {
		handle := pop(&_ctx.level.free_sector_slots)
		sector.handle = {
			index = handle.index,
			generation = handle.generation + 1,
		}
		_ctx.level.sectors[handle.index] = sector
	} else {
		sector.handle = {
			index = len(_ctx.level.sectors),
			generation = 0,
		}
		append(&_ctx.level.sectors, sector)
	}
}

@(private="file")
_delete_sector :: proc(handle: _Sector_Handle) {
	sector := &_ctx.level.sectors[handle.index]
	if sector.handle.generation == handle.generation {
		sector.is_deleted = true

		for linked_handle in sector.linked_sectors {
			if linked_sector := _get_sector_ptr(linked_handle); linked_sector != nil {
				for h, i in linked_sector.linked_sectors {
					if h == handle {
						unordered_remove(&linked_sector.linked_sectors, i)
						break
					}
				}
			}
		}

		delete(sector.linked_sectors)
		append(&_ctx.level.free_sector_slots, handle)
	}
}

@(private="file")
_get_sector_ptr :: proc(handle: _Sector_Handle) -> (result: ^_Sector) {
	for &sector in _ctx.level.sectors {
		if sector.handle == handle {
			result = &sector
			break
		}
	}
	return
}

@(private="file")
_construct_level_preview :: proc() {
	_delete_level_preview()

	sectors := make([]LVL_Sector, len(_ctx.level.sectors))
	walls := make([dynamic]LVL_Wall, 0, 32)

	// sectors
	for sector, i in _ctx.level.sectors {
		sectors[i] = {
			position = {f32(sector.position.x)*_UNIT_PER_GRID, f32(sector.position.y)*_UNIT_PER_GRID},
			size = {f32(sector.size.x)*_UNIT_PER_GRID, f32(sector.size.y)*_UNIT_PER_GRID},
			floor_y = sector.floor_y,
			ceiling_y = sector.ceiling_y,
		}
	}
	_ctx.level_preview.sectors = sectors

	min_pos := +_INVALID_GRID_COORD
	max_pos := -_INVALID_GRID_COORD

	for sector in _ctx.level.sectors {
		min_pos.x = min(sector.position.x, min_pos.x)
		min_pos.y = min(sector.position.y, min_pos.y)
		max_pos.x = max(sector.position.x + sector.size.x, max_pos.x)
		max_pos.y = max(sector.position.y + sector.size.y, max_pos.y)
	}

	_Cell :: struct {
		sector_index: int,
		// if no floor_y and ceiling_y difference: always 0
		// otherwise: 0 = bottom wall, 1 = top wall
		wall_indices: [LVL_Wall_Direction][2]int,
	}
	_INVALID_CELL :: _Cell{
		sector_index = -1,
		wall_indices = {
			.North = {-1, -1},
			.East  = {-1, -1},
			.South = {-1, -1},
			.West  = {-1, -1},
		},
	}

	width := abs(max_pos.x - min_pos.x)
	height := abs(max_pos.y - min_pos.y)

	cells := make([]_Cell, width*height)
	defer delete(cells)

	for &cell in cells {
		cell = _INVALID_CELL
	}

	// set cells' data
	for y in min_pos.y..<max_pos.y {
		for x in min_pos.x..<max_pos.x {
			sector_index := -1
			sector_area := _MAX_SECTOR_GRID_COORD*_MAX_SECTOR_GRID_COORD

			// TODO: chunk optimization
			for sector in _ctx.level.sectors {
				if sector.is_deleted {
					continue
				}

				if (sector.position.x <= x && x < sector.position.x + sector.size.x) &&
					(sector.position.y <= y && y < sector.position.y + sector.size.y)
				{
					area := sector.size.x*sector.size.y
					if area < sector_area {
						sector_index = sector.handle.index
						sector_area = area
					}
				}
			}

			if sector_index != -1 {
				cells[(x - min_pos.x) + (y - min_pos.y)*width].sector_index = sector_index
			}
		}
	}

	_is_linked :: proc(index, suspected_link_index: int) -> bool {
		if index == -1 || suspected_link_index == -1 {
			return false
		}

		sector := _ctx.level.sectors[index]
		suspected_sector := _ctx.level.sectors[suspected_link_index]

		result := false
		for linked_sector_handle in sector.linked_sectors {
			if linked_sector_handle == suspected_sector.handle {
				result = true
				break
			}
		}
		return result
	}

	_get_floor_and_ceiling_y_diff :: proc(index1, index2: int) -> (f32, f32) {
		if index1 == -1 || index2 == -1 {
			return 0.0, 0.0
		}

		sector1 := _ctx.level.sectors[index1]
		sector2 := _ctx.level.sectors[index2]
		return sector1.floor_y - sector2.floor_y, sector1.ceiling_y - sector2.ceiling_y
	}

	_construct_wall :: proc(
		walls: ^[dynamic]LVL_Wall,
		x, y: int,
		curr_cell: ^_Cell,
		neighbor_cells: [LVL_Wall_Direction]_Cell,
		dir: LVL_Wall_Direction,
		wall_offset: M_Vec2f32,
	) {
		neighbor_cell := neighbor_cells[dir]

		// same sector = no wall
		if curr_cell.sector_index == neighbor_cell.sector_index {
			return
		}

		curr_sector := _ctx.level.sectors[curr_cell.sector_index]
		neighbor_linked := _is_linked(curr_cell.sector_index, neighbor_cell.sector_index)
		floor_y_diff, ceiling_y_diff := _get_floor_and_ceiling_y_diff(curr_cell.sector_index, neighbor_cell.sector_index)

		wall_offset := wall_offset
		wall_p2_offset: M_Vec2f32
		dir_to_extend: LVL_Wall_Direction
		facing_dir: LVL_Wall_Direction

		switch dir {
		case .North:
			wall_p2_offset.x = _UNIT_PER_GRID
			dir_to_extend = .West
			facing_dir = .South

		case .East:
			wall_offset.x += _UNIT_PER_GRID
			wall_p2_offset.y = _UNIT_PER_GRID
			dir_to_extend = .North
			facing_dir = .West

		case .South:
			wall_offset.y += _UNIT_PER_GRID
			wall_p2_offset.x = _UNIT_PER_GRID
			dir_to_extend = .West
			facing_dir = .North

		case .West:
			wall_p2_offset.y = _UNIT_PER_GRID
			dir_to_extend = .North
			facing_dir = .East
		}

		cell_to_extend := neighbor_cells[dir_to_extend]

		// cases where wall(s) have to be constructed:
		// #1 no neighboring cell
		// #2 neighboring cell is in another sector that is not linked
		// #3 neighboring cell is in another sector that is linked, but the floor is lower or the ceiling is higher

		if neighbor_cell.sector_index == -1 || !neighbor_linked {
			// CASE #1 and CASE #2
			desired_height := abs(curr_sector.ceiling_y - curr_sector.floor_y)

			// extend existing wall if possible
			if (cell_to_extend.sector_index != -1 && cell_to_extend.wall_indices[dir][0] != -1) &&
				walls[cell_to_extend.wall_indices[dir][0]].y == curr_sector.floor_y &&
				walls[cell_to_extend.wall_indices[dir][0]].height == desired_height
			{
				curr_cell.wall_indices[dir][0] = cell_to_extend.wall_indices[dir][0]
				walls[curr_cell.wall_indices[dir][0]].p2 += wall_p2_offset
			} else {
				curr_cell.wall_indices[dir][0] = len(walls)
				wall_p1 := M_Vec2f32{f32(x)*_UNIT_PER_GRID, f32(y)*_UNIT_PER_GRID}
				append(walls, LVL_Wall{
					p1 = wall_offset + wall_p1,
					p2 = wall_offset + wall_p1 + wall_p2_offset,
					facing = facing_dir,
					y = curr_sector.floor_y,
					height = desired_height,
				})
			}
		} else if neighbor_linked && (floor_y_diff < 0.0 || ceiling_y_diff > 0.0) {
			// CASE #3
			if floor_y_diff < 0.0 {
				desired_height := abs(floor_y_diff)

				if (cell_to_extend.sector_index != -1 && cell_to_extend.wall_indices[dir][0] != -1) &&
					walls[cell_to_extend.wall_indices[dir][0]].y == curr_sector.floor_y &&
					walls[cell_to_extend.wall_indices[dir][0]].height == desired_height
				{
					curr_cell.wall_indices[dir][0] = cell_to_extend.wall_indices[dir][0]
					walls[curr_cell.wall_indices[dir][0]].p2 += wall_p2_offset
				} else {
					curr_cell.wall_indices[dir][0] = len(walls)
					wall_p1 := M_Vec2f32{f32(x)*_UNIT_PER_GRID, f32(y)*_UNIT_PER_GRID}
					append(walls, LVL_Wall{
						p1 = wall_offset + wall_p1,
						p2 = wall_offset + wall_p1 + wall_p2_offset,
						facing = facing_dir,
						y = curr_sector.floor_y,
						height = desired_height,
					})
				}
			}

			if ceiling_y_diff > 0.0 {
				desired_y := curr_sector.ceiling_y - ceiling_y_diff
				desired_height := abs(ceiling_y_diff)

				if (cell_to_extend.sector_index != -1 && cell_to_extend.wall_indices[dir][1] != -1) &&
					walls[cell_to_extend.wall_indices[dir][1]].y == desired_y &&
					walls[cell_to_extend.wall_indices[dir][1]].height == desired_height
				{
					curr_cell.wall_indices[dir][1] = cell_to_extend.wall_indices[dir][1]
					walls[curr_cell.wall_indices[dir][1]].p2 += wall_p2_offset
				} else {
					curr_cell.wall_indices[dir][1] = len(walls)
					wall_p1 := M_Vec2f32{f32(x)*_UNIT_PER_GRID, f32(y)*_UNIT_PER_GRID}
					append(walls, LVL_Wall{
						p1 = wall_offset + wall_p1,
						p2 = wall_offset + wall_p1 + wall_p2_offset,
						facing = facing_dir,
						y = desired_y,
						height = desired_height,
					})
				}
			}
		}
	}

	// construct walls
	for y in 0..<height {
		for x in 0..<width {
			curr_cell := &cells[x + y*width]
			if curr_cell.sector_index == -1 {
				continue
			}

			n := cells[x + (y - 1)*width] if y > 0          else _INVALID_CELL
			s := cells[x + (y + 1)*width] if y < height - 1 else _INVALID_CELL
			w := cells[(x - 1) + y*width] if x > 0          else _INVALID_CELL
			e := cells[(x + 1) + y*width] if x < width - 1  else _INVALID_CELL

			neighbor_cells := [LVL_Wall_Direction]_Cell{
				.North = n,
				.East = e,
				.South = s,
				.West = w,
			}
			wall_offset := M_Vec2f32{
				f32(min_pos.x),
				f32(min_pos.y),
			}*_UNIT_PER_GRID

			_construct_wall(&walls, x, y, curr_cell, neighbor_cells, .North, wall_offset)
			_construct_wall(&walls, x, y, curr_cell, neighbor_cells, .East,  wall_offset)
			_construct_wall(&walls, x, y, curr_cell, neighbor_cells, .South, wall_offset)
			_construct_wall(&walls, x, y, curr_cell, neighbor_cells, .West,  wall_offset)
		}
	}
	_ctx.level_preview.walls = walls[:]
}

@(private="file")
_delete_level_preview :: proc() {
	if _ctx.level_preview.sectors != nil {
		delete(_ctx.level_preview.sectors)
	}

	if _ctx.level_preview.walls != nil {
		delete(_ctx.level_preview.walls)
	}

	_ctx.level_preview = {}
}

} // when DEV_BUILD
