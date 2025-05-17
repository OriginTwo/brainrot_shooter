package game

import "core:fmt"
import "core:math"
import "core:bytes"
import "core:unicode/utf16"
import "core:path/filepath"
import win32 "core:sys/windows"

import rl "vendor:raylib"

/*
#assert(false, "REMOVE RAYLIB")

when DEV_BUILD {

SCN_EDITOR_HANDLE :: SCN_Handle(#hash("editor", "fnv64a"))
SCN_EDITOR_CALLBACKS :: SCN_Callbacks{scn_editor_init, scn_editor_uninit, nil, scn_editor_draw}

FONT_SIZE :: 20
BUTTON_HEIGHT :: 30

GRID_SIZE :: 16
CAMERA_SPEED :: 400.0

DEFAULT_LEVEL_WIDTH :: 64
DEFAULT_LEVEL_HEIGHT :: 36

@(private="file")
_Tool_Kind :: enum {
	Select,
	Brush,
	Eraser,
	Bucket,
}

@(private="file")
_Edit_Mode :: enum {
	Place_Tile,
	Place_Rect,
	Place_Entity,
}

@(private="file")
_ctx: struct {
	font: rl.Font,
	camera: rl.Camera2D,

	level: LVL_Editor_Level,

	mouse_pos: [2]int,

	curr_tool: _Tool_Kind,
	curr_tile_id: int,
	curr_entity_kind: ENT_Entity_Kind,

	edit_mode: _Edit_Mode,
	curr_layer: i8,

	is_selecting: bool,
	is_selected: bool,
	select_p1: [2]int,
	select_p2: [2]int,
	is_moving_selected: bool,
	selected_move_p1: [2]int,
	selected_move_p2: [2]int,
	selected_tiles: [dynamic]u16,    // for drawing preview
	selected_rects: [dynamic]bool,   // for drawing preview
	selected_entities: [dynamic]int, // for drawing preview

	is_resize_hovered: bool,
	is_resizing: bool,
	resize_amount: [2]int,

	highlight_layer: bool,
	show_grid: bool,
	show_rect: bool,

	is_file_dropdown_open: bool,
	is_edit_dropdown_open: bool,
	is_view_dropdown_open: bool,
	is_help_dropdown_open: bool,

	tile_set_panel_offset: f32,
	entity_kind_panel_offset: f32,
}

scn_editor_init :: proc() {
	{
		image := rl.LoadImage("res/font/font_big.png")
		FONT_load_from_image(&_ctx.font, image)
		rl.UnloadImage(image)
	}

	IMUI_set_font(_ctx.font, 20.0)

	ENT_load_editor_visual()

	LVL_init_editor_level(&_ctx.level, DEFAULT_LEVEL_WIDTH, DEFAULT_LEVEL_HEIGHT)

	_ctx.camera.target = -{f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}/2.0
	_ctx.camera.zoom = 1.0

	_ctx.curr_tile_id = 1

	_ctx.selected_tiles = make([dynamic]u16, 256)
	_ctx.selected_rects = make([dynamic]bool, 256)
	_ctx.selected_entities = make([dynamic]int, 0, 256)

	_ctx.show_grid = true
}

scn_editor_uninit :: proc() {
	delete(_ctx.selected_tiles)
	delete(_ctx.selected_rects)
	delete(_ctx.selected_entities)

	LVL_uninit_editor_level(&_ctx.level)

	ENT_unload_editor_visual()

	rl.UnloadFont(_ctx.font)
}

scn_editor_draw :: proc(alpha: f32) {
	if rl.IsKeyPressed(.F1) {
		SCN_change(SCN_GAME_HANDLE)
	}

	delta := rl.GetFrameTime()

	if !IMUI_is_interacting() {
		// camera movement
		{
			vel := Vec2f32{
				f32(i32(rl.IsKeyDown(.D)) - i32(rl.IsKeyDown(.A))),
				f32(i32(rl.IsKeyDown(.S)) - i32(rl.IsKeyDown(.W))),
			}*CAMERA_SPEED
			if rl.IsKeyDown(.LEFT_SHIFT) {
				vel *= 3.0
			}
			_ctx.camera.target += vel*delta
		}

		// zoom
		{
			wheel_move := rl.GetMouseWheelMove()
			if wheel_move != 0.0 {
				// zoom in/out around the mouse position
				mouse_pos_before := rl.GetScreenToWorld2D(rl.GetMousePosition(), _ctx.camera)
				_ctx.camera.zoom = clamp(_ctx.camera.zoom + 0.25*math.sign(wheel_move), 0.75, 10.0)
				mouse_pos_after := rl.GetScreenToWorld2D(rl.GetMousePosition(), _ctx.camera)
				_ctx.camera.target += mouse_pos_before - mouse_pos_after
			}
		}

		// tool keybind
		{
			if rl.IsKeyPressed(.M) do _ctx.curr_tool = .Select
			if rl.IsKeyPressed(.B) do _ctx.curr_tool = .Brush
			if rl.IsKeyPressed(.E) do _ctx.curr_tool = .Eraser
			if rl.IsKeyPressed(.G) do _ctx.curr_tool = .Bucket
		}
	}

	actual_mouse_pos := rl.GetScreenToWorld2D(rl.GetMousePosition(), _ctx.camera)
	if _ctx.edit_mode == .Place_Tile || _ctx.edit_mode == .Place_Rect {
		_ctx.mouse_pos.x = int(math.floor(actual_mouse_pos.x/GRID_SIZE))*GRID_SIZE
		_ctx.mouse_pos.y = int(math.floor(actual_mouse_pos.y/GRID_SIZE))*GRID_SIZE
	} else {
		_ctx.mouse_pos = {int(actual_mouse_pos.x), int(actual_mouse_pos.y)}
	}

	if !IMUI_is_interacting() {
		_do_editor_logic()
	}

	rl.BeginDrawing()
	rl.ClearBackground({0, 34, 64, 255})

	rl.BeginMode2D(_ctx.camera)

	// level area
	rl.DrawRectangle(0, 0, i32(_ctx.level.width*GRID_SIZE), i32(_ctx.level.height*GRID_SIZE), rl.BLACK)

	// draw tiles and entities
	{
		tile_layer := _ctx.level.tile_layers
		entity_layer := _ctx.level.entity_layers
		entity_texture := ENT_get_editor_texture()

		minimum := rl.GetScreenToWorld2D({0.0, 0.0}, _ctx.camera)
		maximum := rl.GetScreenToWorld2D({f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}, _ctx.camera)
		view_rect := rl.Rectangle{
			minimum.x,
			minimum.y,
			maximum.x - minimum.x,
			maximum.y - minimum.y,
		}

		start_x := clamp(int(minimum.x)/GRID_SIZE, 0, _ctx.level.width)
		start_y := clamp(int(minimum.y)/GRID_SIZE, 0, _ctx.level.height)
		end_x := clamp(int(maximum.x)/GRID_SIZE + 1, 0, _ctx.level.width)
		end_y := clamp(int(maximum.y)/GRID_SIZE + 1, 0, _ctx.level.height)

		for layer := i8(-128); layer < 127; layer += 1 {
			if tile_layer != nil {
				if layer == tile_layer.layer {
					for y in start_y..<end_y {
						for x in start_x..<end_x {
							id := tile_layer.tiles[y*_ctx.level.width + x]
							if id == 0 {
								continue
							}

							source := _ctx.level.tile_set.sources[id]
							offset := _ctx.level.tile_set.offsets[id]
							tint := rl.Color{255, 255, 255, 120} if _ctx.highlight_layer && _ctx.curr_layer != tile_layer.layer else rl.WHITE
							rl.DrawTexturePro(
								_ctx.level.tile_set.texture,
								source,
								{
									f32(x*GRID_SIZE) - offset.x,
									f32(y*GRID_SIZE) - offset.y,
									source.width,
									source.height,
								},
								{0.0, 0.0},
								0.0,
								tint,
							)
						}
					}

					tile_layer = tile_layer.next
				}
			}

			if entity_layer != nil {
				if layer == entity_layer.layer {
					for entity in entity_layer.entities {
						source := ENT_get_editor_source(entity.kind)
						dest := rl.Rectangle{
							f32(entity.pos.x),
							f32(entity.pos.y),
							source.width,
							source.height,
						}
						if rl.CheckCollisionRecs(view_rect, dest) {
							tint := rl.Color{255, 255, 255, 120} if _ctx.highlight_layer && _ctx.curr_layer != entity_layer.layer else rl.WHITE
							rl.DrawTexturePro(
								entity_texture,
								source,
								dest,
								{0.0, 0.0},
								0.0,
								tint,
							)
						}
					}

					entity_layer = entity_layer.next
				}
			}
		}
	}

	// draw rects
	if _ctx.edit_mode == .Place_Rect || _ctx.show_rect {
		minimum := rl.GetScreenToWorld2D({0.0, 0.0}, _ctx.camera)
		maximum := rl.GetScreenToWorld2D({f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}, _ctx.camera)

		start_x := clamp(int(minimum.x)/GRID_SIZE, 0, _ctx.level.width)
		start_y := clamp(int(minimum.y)/GRID_SIZE, 0, _ctx.level.height)
		end_x := clamp(int(maximum.x)/GRID_SIZE + 1, 0, _ctx.level.width)
		end_y := clamp(int(maximum.y)/GRID_SIZE + 1, 0, _ctx.level.height)

		for y in start_y..<end_y {
			for x in start_x..<end_x {
				if _ctx.level.rects[y*_ctx.level.width + x] {
					rl.DrawRectangle(
						i32(x*GRID_SIZE),
						i32(y*GRID_SIZE),
						GRID_SIZE,
						GRID_SIZE,
						{255, 0, 0, 120},
					)
				}
			}
		}
	}

	// draw selected moving tiles
	if _ctx.is_moving_selected && _ctx.edit_mode == .Place_Tile {
		minimum, maximum := _get_select_range()
		move_offset := (_ctx.selected_move_p2 - _ctx.selected_move_p1)/GRID_SIZE

		index := 0
		for y in minimum.y..<maximum.y {
			for x in minimum.x..<maximum.x {
				id := _ctx.selected_tiles[index]
				index += 1
				if id == 0 {
					continue
				}

				lerp_t := math.sin(5.0*f32(rl.GetTime()))*0.5 + 0.5

				rl.DrawRectangle(
					i32(x*GRID_SIZE),
					i32(y*GRID_SIZE),
					GRID_SIZE,
					GRID_SIZE,
					rl_color_from_rgba(
						math.lerp(Vec4f32{0.0, 0.0, 0.0, 0.0},Vec4f32{1.0, 0.2, 0.2, 0.8}, lerp_t),
					),
				)

				source := _ctx.level.tile_set.sources[id]
				offset := _ctx.level.tile_set.offsets[id]
				tint := math.lerp(
					Vec3f32{1.0, 1.0, 1.0},
					Vec3f32{0.2, 1.0, 1.0},
					lerp_t,
				)
				rl.DrawTexturePro(
					_ctx.level.tile_set.texture,
					source,
					{
						f32((x + move_offset.x)*GRID_SIZE) - offset.x,
						f32((y + move_offset.y)*GRID_SIZE) - offset.y,
						source.width,
						source.height,
					},
					{0.0, 0.0},
					0.0,
					rl_color_from_rgba({tint.r, tint.g, tint.b, 0.8}),
				)
			}
		}
	}

	// draw selected moving rects
	if _ctx.is_moving_selected && _ctx.edit_mode == .Place_Rect {
		minimum, maximum := _get_select_range()
		move_offset := (_ctx.selected_move_p2 - _ctx.selected_move_p1)/GRID_SIZE

		index := 0
		for y in minimum.y..<maximum.y {
			for x in minimum.x..<maximum.x {
				if _ctx.selected_rects[index] {
					lerp_t := math.sin(5.0*f32(rl.GetTime()))*0.5 + 0.5

					rl.DrawRectangle(
						i32(x*GRID_SIZE),
						i32(y*GRID_SIZE),
						GRID_SIZE,
						GRID_SIZE,
						rl_color_from_rgba(
							math.lerp(Vec4f32{0.0, 0.0, 0.0, 0.0},Vec4f32{1.0, 1.0, 0.2, 0.5}, lerp_t),
						),
					)

					tint := math.lerp(
						Vec3f32{1.0, 0.2, 0.2},
						Vec3f32{1.0, 1.0, 1.0},
						lerp_t,
					)
					rl.DrawRectangle(
						i32((x + move_offset.x)*GRID_SIZE),
						i32((y + move_offset.y)*GRID_SIZE),
						GRID_SIZE,
						GRID_SIZE,
						rl_color_from_rgba({tint.r, tint.g, tint.b, 0.8}),
					)
				}
				index += 1
			}
		}
	}

	// draw selected entity
	if (_ctx.is_selecting || _ctx.is_selected) && _ctx.edit_mode == .Place_Entity {
		move_offset := _ctx.selected_move_p2 - _ctx.selected_move_p1
		texture := ENT_get_editor_texture()
		for index in _ctx.selected_entities {
			entity := _ctx.level.curr_entity_layer.entities[index]
			source := ENT_get_editor_source(entity.kind)

			if _ctx.is_moving_selected {
				lerp_t := math.sin(5.0*f32(rl.GetTime()))*0.5 + 0.5

				rl.DrawRectangle(
					i32(entity.pos.x),
					i32(entity.pos.y),
					i32(source.width),
					i32(source.height),
					rl_color_from_rgba(
						math.lerp(Vec4f32{0.0, 0.0, 0.0, 0.0},Vec4f32{1.0, 0.2, 0.2, 0.8}, lerp_t),
					),
				)

				tint := math.lerp(
					Vec3f32{1.0, 1.0, 1.0},
					Vec3f32{0.2, 1.0, 1.0},
					lerp_t,
				)

				rl.DrawTexturePro(
					texture,
					source,
					{
						f32(entity.pos.x + move_offset.x),
						f32(entity.pos.y + move_offset.y),
						source.width,
						source.height,
					},
					{0.0, 0.0},
					0.0,
					rl_color_from_rgba({tint.r, tint.g, tint.b, 0.8}),
				)
			}

			rl.DrawRectangleLines(
				i32(entity.pos.x + move_offset.x),
				i32(entity.pos.y + move_offset.y),
				i32(source.width),
				i32(source.height),
				rl.MAGENTA,
			)
		}
	}

	// border
	{
		rl.DrawLineEx({0.0, 0.0}, {f32(_ctx.level.width*GRID_SIZE), 0.0}, 2.0, {173, 151, 59, 255})
		rl.DrawLineEx({0.0, 0.0}, {0.0, f32(_ctx.level.height*GRID_SIZE)}, 2.0, {173, 151, 59, 255})
		rl.DrawLineEx(
			{f32(_ctx.level.width*GRID_SIZE), 0.0},
			{f32(_ctx.level.width*GRID_SIZE), f32(_ctx.level.height*GRID_SIZE)},
			2.0,
			{173, 151, 59, 255},
		)
		rl.DrawLineEx(
			{0.0, f32(_ctx.level.height*GRID_SIZE)},
			{f32(_ctx.level.width*GRID_SIZE), f32(_ctx.level.height*GRID_SIZE)},
			2.0,
			{173, 151, 59, 255},
		)
	}

	// grid
	if _ctx.show_grid {
		minimum := rl.GetScreenToWorld2D({0.0, 0.0}, _ctx.camera)
		maximum := rl.GetScreenToWorld2D({f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}, _ctx.camera)

		start_x := i32(minimum.x)/GRID_SIZE - 1
		start_y := i32(minimum.y)/GRID_SIZE - 1
		end_x := i32(maximum.x)/GRID_SIZE + 1
		end_y := i32(maximum.y)/GRID_SIZE + 1

		// vertical line
		for x := start_x; x <= end_x; x += 1 {
			rl.DrawLine(x*GRID_SIZE, start_y*GRID_SIZE, x*GRID_SIZE, end_y*GRID_SIZE, {255, 255, 255, 50})
		}

		// horizontal line
		for y := start_y; y <= end_y; y += 1 {
			rl.DrawLine(start_x*GRID_SIZE, y*GRID_SIZE, end_x*GRID_SIZE, y*GRID_SIZE, {255, 255, 255, 50})
		}
	}

	// resize visual
	{
		x_end := (_ctx.level.width + _ctx.resize_amount.x)*GRID_SIZE
		y_end := (_ctx.level.height + _ctx.resize_amount.y)*GRID_SIZE

		radius: f32 = 8.0
		if _ctx.camera.zoom < 1.5 {
			radius = 12.0
		}

		_ctx.is_resize_hovered = rl.CheckCollisionPointCircle(actual_mouse_pos, {f32(x_end), f32(y_end)}, radius)

		if _ctx.is_resizing {
			rl.DrawLineEx({0.0, 0.0}, {f32(x_end), 0.0}, 2.0, {255, 255, 255, 200})
			rl.DrawLineEx({0.0, 0.0}, {0.0, f32(y_end)}, 2.0, {255, 255, 255, 200})
			rl.DrawLineEx({f32(x_end), 0.0}, {f32(x_end), f32(y_end)}, 2.0, {255, 255, 255, 200})
			rl.DrawLineEx({0.0, f32(y_end)}, {f32(x_end), f32(y_end)}, 2.0, {255, 255, 255, 200})
		}

		rl.DrawRing(
			{f32(x_end), f32(y_end)},
			radius - 2.0 if !_ctx.is_resize_hovered && !_ctx.is_resizing else radius + 1.0,
			radius if !_ctx.is_resize_hovered && !_ctx.is_resizing else radius + 3.0,
			0.0, 360.0, 10,
			{173, 151, 59, 255},
		)
	}

	// preview
	if !_ctx.is_resize_hovered && !_ctx.is_resizing && _ctx.curr_tool == .Brush {
		switch _ctx.edit_mode {
		case .Place_Tile:
			source := _ctx.level.tile_set.sources[_ctx.curr_tile_id]
			rl.DrawTexturePro(
				_ctx.level.tile_set.texture,
				source,
				{
					f32(_ctx.mouse_pos.x) - _ctx.level.tile_set.offsets[_ctx.curr_tile_id].x,
					f32(_ctx.mouse_pos.y) - _ctx.level.tile_set.offsets[_ctx.curr_tile_id].y,
					source.width,
					source.height,
				},
				{0.0, 0.0},
				0.0,
				{255, 255, 255, 200},
			)

		case .Place_Rect:
			rl.DrawRectangle(
				i32(_ctx.mouse_pos.x),
				i32(_ctx.mouse_pos.y),
				GRID_SIZE,
				GRID_SIZE,
				{255, 0, 255, 120},
			)

		case .Place_Entity:
			source := ENT_get_editor_source(_ctx.curr_entity_kind)
			rl.DrawTexturePro(
				ENT_get_editor_texture(),
				source,
				{
					f32(_ctx.mouse_pos.x),
					f32(_ctx.mouse_pos.y),
					source.width,
					source.height,
				},
				{0.0, 0.0},
				0.0,
				{255, 255, 255, 200},
			)
		}
	}

	// outline
	if !_ctx.is_resize_hovered && !_ctx.is_resizing && !_ctx.is_selecting && !_ctx.is_moving_selected {
		if _ctx.edit_mode != .Place_Entity {
			rl.DrawRectangleLines(
				i32(_ctx.mouse_pos.x),
				i32(_ctx.mouse_pos.y),
				GRID_SIZE,
				GRID_SIZE,
				rl.WHITE,
			)
		} else if _ctx.curr_tool == .Eraser {
			index := LVL_get_editor_entity_index(&_ctx.level, _ctx.curr_layer, _ctx.mouse_pos)
			if index != -1 {
				entity := _ctx.level.curr_entity_layer.entities[index]
				source := ENT_get_editor_source(entity.kind)
				rl.DrawRectangleLines(
					i32(entity.pos.x),
					i32(entity.pos.y),
					i32(source.width),
					i32(source.height),
					rl.WHITE,
				)
			}
		}
	}

	// select rect
	if _ctx.is_selecting || _ctx.is_selected {
		offset := _ctx.selected_move_p2 - _ctx.selected_move_p1
		p1 := _ctx.select_p1 + offset
		p2 := _ctx.select_p2 + offset
		min_x := f32(min(p1.x, p2.x))
		min_y := f32(min(p1.y, p2.y))
		max_x := f32(max(p1.x, p2.x))
		max_y := f32(max(p1.y, p2.y))
		rect := rl.Rectangle{min_x, min_y, max_x - min_x, max_y - min_y}
		rl.DrawRectangleLinesEx(rect, 2.0, rl.MAGENTA)
	}

	rl.EndMode2D()

	// ui -------------------------------------------------
	IMUI_frame()

	screen_rect := rl.Rectangle{
		x = 0.0,
		y = 0.0,
		width = f32(rl.GetScreenWidth()),
		height = f32(rl.GetScreenHeight()),
	}

	menu_bar_rect := RECT_cut_top(&screen_rect, BUTTON_HEIGHT)

	status_bar_rect := RECT_cut_bottom(&screen_rect, 20.0)
	rl.DrawRectangleRec(status_bar_rect, IMUI_BG_COLOR_DARK)
	{
		rect := RECT_cut_left(&status_bar_rect, 150.0)
		IMUI_label(rect, fmt.tprintf("Mouse: (%d, %d)", _ctx.mouse_pos.x, _ctx.mouse_pos.y))

		rect = RECT_cut_left(&status_bar_rect, 8.0)
		IMUI_label(rect, "|")

		rect = RECT_cut_left(&status_bar_rect, 150.0)
		IMUI_label(rect, fmt.tprintf("Zoom: %.2f", _ctx.camera.zoom))

		rect = RECT_cut_left(&status_bar_rect, 8.0)
		IMUI_label(rect, "|")

		rect = RECT_cut_left(&status_bar_rect, 150.0)
		IMUI_label(rect, fmt.tprintf("Size: (%d, %d)", _ctx.level.width + _ctx.resize_amount.x, _ctx.level.height + _ctx.resize_amount.y))

		rect = RECT_cut_left(&status_bar_rect, 8.0)
		IMUI_label(rect, "|")

		rect = RECT_cut_left(&status_bar_rect, 150.0)
		IMUI_label(rect, "Status Bar")

		rect = RECT_cut_left(&status_bar_rect, 8.0)
		IMUI_label(rect, "|")

		rect = RECT_cut_left(&status_bar_rect, 150.0)
		IMUI_label(rect, "Status Bar")

		rect = RECT_cut_left(&status_bar_rect, 8.0)
		IMUI_label(rect, "|")

		rect = RECT_cut_left(&status_bar_rect, 150.0)
		IMUI_label(rect, "Status Bar")

		rect = RECT_cut_left(&status_bar_rect, 8.0)
		IMUI_label(rect, "|")

		rect = RECT_cut_left(&status_bar_rect, 150.0)
		IMUI_label(rect, "Status Bar")

		rect = RECT_cut_left(&status_bar_rect, 8.0)
		IMUI_label(rect, "|")

		rect = RECT_cut_left(&status_bar_rect, 150.0)
		IMUI_label(rect, "Status Bar")

		rect = RECT_cut_left(&status_bar_rect, 8.0)
		IMUI_label(rect, "|")
	}

	panel_rect := RECT_cut_left(&screen_rect, 200.0)
	rl.DrawRectangleRec(panel_rect, {32, 32, 32, 255})
	#partial switch _ctx.edit_mode {
	case .Place_Tile:
		IMUI_begin_scroll_view(RECT_pad_all(panel_rect, 6.0), {0.0, 1000.0}, &_ctx.tile_set_panel_offset)
		{
			rect := RECT_cut_top(&panel_rect, 60.0)
			for i in 1..<len(_ctx.level.tile_set.sources) {
				sub_rect := rect
				tex_rect := RECT_cut_left(&sub_rect, 60.0)
				tex_rect.y -= _ctx.tile_set_panel_offset
				rl.DrawTexturePro(
					_ctx.level.tile_set.texture,
					_ctx.level.tile_set.sources[i],
					tex_rect,
					{0.0, 0.0},
					0.0,
					rl.WHITE,
				)

				IMUI_radio_button(sub_rect, fmt.tprintf("ID: #%d", i), i, &_ctx.curr_tile_id)

				rect = RECT_add_bottom(rect, 60.0)
				rect.y += 6.0
			}
		}
		IMUI_end_scroll_view()

	case .Place_Entity:
		IMUI_begin_scroll_view(RECT_pad_all(panel_rect, 6.0), {0.0, 1000.0}, &_ctx.entity_kind_panel_offset)
		{
			rect := RECT_cut_top(&panel_rect, 60.0)
			for kind in ENT_Entity_Kind {
				sub_rect := rect
				tex_rect := RECT_cut_left(&sub_rect, 60.0)
				tex_rect.y -= _ctx.entity_kind_panel_offset
				rl.DrawTexturePro(
					ENT_get_editor_texture(),
					ENT_get_editor_source(kind),
					tex_rect,
					{0.0, 0.0},
					0.0,
					rl.WHITE,
				)

				temp_kind := int(_ctx.curr_entity_kind)
				IMUI_radio_button(sub_rect, fmt.tprintf("%s", kind), int(kind), &temp_kind)
				_ctx.curr_entity_kind = ENT_Entity_Kind(temp_kind)

				rect = RECT_add_bottom(rect, 60.0)
				rect.y += 6.0
			}
		}
		IMUI_end_scroll_view()
	}

	// tool select
	tool_rect := RECT_cut_right(&screen_rect, 80.0)
	{
		selected_id := int(_ctx.curr_tool)

		rect := RECT_cut_top(&tool_rect, BUTTON_HEIGHT)
		IMUI_radio_button(rect, "[M] Select", int(_Tool_Kind.Select), &selected_id)
		rect = RECT_cut_top(&tool_rect, BUTTON_HEIGHT)
		IMUI_radio_button(rect, "[B] Brush", int(_Tool_Kind.Brush), &selected_id)
		rect = RECT_cut_top(&tool_rect, BUTTON_HEIGHT)
		IMUI_radio_button(rect, "[E] Eraser", int(_Tool_Kind.Eraser), &selected_id)
		rect = RECT_cut_top(&tool_rect, BUTTON_HEIGHT)
		IMUI_radio_button(rect, "[G] Bucket", int(_Tool_Kind.Bucket), &selected_id)

		_ctx.curr_tool = _Tool_Kind(selected_id)
	}

	// menu bar
	rl.DrawRectangleRec(menu_bar_rect, IMUI_BG_COLOR_DARK)
	{
		file_button_rect := RECT_cut_left(&menu_bar_rect, 80.0)
		if IMUI_button(file_button_rect, "File") {
			_ctx.is_file_dropdown_open = !_ctx.is_file_dropdown_open
			_ctx.is_edit_dropdown_open = false
			_ctx.is_view_dropdown_open = false
			_ctx.is_help_dropdown_open = false
		}

		if _ctx.is_file_dropdown_open {
			rect := file_button_rect
			rect.y += 4.0

			rect = RECT_add_bottom(rect, BUTTON_HEIGHT)
			if IMUI_button(rect, "New") {
				LVL_uninit_editor_level(&_ctx.level)
				LVL_init_editor_level(&_ctx.level, DEFAULT_LEVEL_WIDTH, DEFAULT_LEVEL_HEIGHT)
				_ctx.camera.target = -{f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}/2.0
				_ctx.camera.zoom = 1.0
				_ctx.curr_tile_id = 1
				_ctx.curr_layer = 0
			}

			rect = RECT_add_bottom(rect, BUTTON_HEIGHT)
			if IMUI_button(rect, "Open") {
				str: [512]u16
				filter: [512]u16
				utf16.encode_string(filter[:], "Level (*.lvl)\x00*.lvl\x00")
				opts: win32.OPENFILENAMEW
				opts.lStructSize = size_of(win32.OPENFILENAMEW)
				opts.hwndOwner = win32.HWND(rl.GetWindowHandle())
				opts.lpstrFile = raw_data(str[:])
				opts.nMaxFile = len(str)
				opts.lpstrFilter = raw_data(filter[:])
				opts.nFilterIndex = 1
				opts.Flags = win32.OFN_PATHMUSTEXIST | win32.OFN_FILEMUSTEXIST | win32.OFN_NOCHANGEDIR
				if win32.GetOpenFileNameW(&opts) {
					path_u8: [1024]u8
					utf16.decode_to_utf8(path_u8[:], str[:])

					path_len := bytes.index_byte(path_u8[:], 0)

					if path_len != 0 {
						path := transmute(string)path_u8[:path_len]

						if filepath.ext(path) != ".lvl" {
							path_u8[path_len + 0] = '.'
							path_u8[path_len + 1] = 'l'
							path_u8[path_len + 2] = 'v'
							path_u8[path_len + 3] = 'l'
							path = transmute(string)path_u8[:path_len + 4]
						}

						LVL_uninit_editor_level(&_ctx.level)
						_ctx.camera.target = -{f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}/2.0
						_ctx.camera.zoom = 1.0
						_ctx.curr_tile_id = 1
						_ctx.curr_layer = 0

						if LVL_load_editor_level(&_ctx.level, path) {
							fmt.printfln("level loaded from '%s'", path)
						} else {
							fmt.printfln("failed to load level from '%s'", path)
						}
					}
				}
			}

			rect = RECT_add_bottom(rect, BUTTON_HEIGHT)
			if IMUI_button(rect, "Save") {
				str: [512]u16
				filter: [512]u16
				utf16.encode_string(filter[:], "Level (*.lvl)\x00*.lvl\x00")
				opts: win32.OPENFILENAMEW
				opts.lStructSize = size_of(win32.OPENFILENAMEW)
				opts.hwndOwner = win32.HWND(rl.GetWindowHandle())
				opts.lpstrFile = raw_data(str[:])
				opts.nMaxFile = len(str)
				opts.lpstrFilter = raw_data(filter[:])
				opts.nFilterIndex = 1
				opts.Flags = win32.OFN_PATHMUSTEXIST | win32.OFN_FILEMUSTEXIST | win32.OFN_NOCHANGEDIR
				if win32.GetSaveFileNameW(&opts) {
					path_u8: [1024]u8
					utf16.decode_to_utf8(path_u8[:], str[:])

					path_len := bytes.index_byte(path_u8[:], 0)

					if path_len != 0 {
						path := transmute(string)path_u8[:path_len]

						if filepath.ext(path) != ".lvl" {
							path_u8[path_len + 0] = '.'
							path_u8[path_len + 1] = 'l'
							path_u8[path_len + 2] = 'v'
							path_u8[path_len + 3] = 'l'
							path = transmute(string)path_u8[:path_len + 4]
						}

						if LVL_save_editor_level(&_ctx.level, path) {
							fmt.printfln("level saved to '%s'", path)
						} else {
							fmt.printfln("failed to save level to '%s'", path)
						}
					}
				}
			}

			rect = RECT_add_bottom(rect, BUTTON_HEIGHT)
			if IMUI_button(rect, "Export") {
				str: [512]u16
				filter: [512]u16
				utf16.encode_string(filter[:], "Exported Level (*.dat)\x00*.dat\x00")
				opts: win32.OPENFILENAMEW
				opts.lStructSize = size_of(win32.OPENFILENAMEW)
				opts.hwndOwner = win32.HWND(rl.GetWindowHandle())
				opts.lpstrFile = raw_data(str[:])
				opts.nMaxFile = len(str)
				opts.lpstrFilter = raw_data(filter[:])
				opts.nFilterIndex = 1
				opts.Flags = win32.OFN_PATHMUSTEXIST | win32.OFN_FILEMUSTEXIST | win32.OFN_NOCHANGEDIR
				if win32.GetSaveFileNameW(&opts) {
					path_u8: [1024]u8
					utf16.decode_to_utf8(path_u8[:], str[:])

					path_len := bytes.index_byte(path_u8[:], 0)

					if path_len != 0 {
						path := transmute(string)path_u8[:path_len]

						if filepath.ext(path) != ".dat" {
							path_u8[path_len + 0] = '.'
							path_u8[path_len + 1] = 'd'
							path_u8[path_len + 2] = 'a'
							path_u8[path_len + 3] = 't'
							path = transmute(string)path_u8[:path_len + 4]
						}

						if LVL_export_editor_level(&_ctx.level, path) {
							fmt.printfln("level exported to '%s'", path)
						} else {
							fmt.printfln("failed to export level to '%s'", path)
						}
					}
				}
			}
		}

		edit_button_rect := RECT_cut_left(&menu_bar_rect, 80.0)
		if IMUI_button(edit_button_rect, "Edit") {
			_ctx.is_file_dropdown_open = false
			_ctx.is_edit_dropdown_open = !_ctx.is_edit_dropdown_open
			_ctx.is_view_dropdown_open = false
			_ctx.is_help_dropdown_open = false
		}

		if _ctx.is_edit_dropdown_open {
			rect := edit_button_rect
			rect.y += 4.0
			rect.width += 100.0

			rect = RECT_add_bottom(rect, BUTTON_HEIGHT)
			if IMUI_button(rect, fmt.tprintf("Edit Mode: %s", _ctx.edit_mode)) {
				curr_mode := int(_ctx.edit_mode)
				curr_mode = (curr_mode + 1) % len(type_of(_ctx.edit_mode))
				_ctx.edit_mode = cast(type_of(_ctx.edit_mode))curr_mode

				if _ctx.is_selected && (_ctx.edit_mode == .Place_Tile || _ctx.edit_mode == .Place_Rect) {
					_ctx.select_p1 = _ctx.select_p1/GRID_SIZE*GRID_SIZE
					_ctx.select_p2 = _ctx.select_p2/GRID_SIZE*GRID_SIZE
				}
			}

			rect = RECT_add_bottom(rect, BUTTON_HEIGHT)
			{
				sub_rect := rect
				IMUI_label_rect(RECT_cut_left(&sub_rect, rect.width - BUTTON_HEIGHT*2.0), fmt.tprintf("Layer: %d", _ctx.curr_layer))

				if IMUI_button(RECT_cut_left(&sub_rect, BUTTON_HEIGHT), "-") {
					if !_ctx.is_selected && _ctx.curr_layer > -128 {
						_ctx.curr_layer -= 1
					}
				}

				if IMUI_button(RECT_cut_left(&sub_rect, BUTTON_HEIGHT), "+") {
					if !_ctx.is_selected && _ctx.curr_layer < 127 {
						_ctx.curr_layer += 1
					}
				}
			}
		}

		view_button_rect := RECT_cut_left(&menu_bar_rect, 80.0)
		if IMUI_button(view_button_rect, "View") {
			_ctx.is_file_dropdown_open = false
			_ctx.is_edit_dropdown_open = false
			_ctx.is_view_dropdown_open = !_ctx.is_view_dropdown_open
			_ctx.is_help_dropdown_open = false
		}

		if _ctx.is_view_dropdown_open {
			rect := view_button_rect
			rect.y += 4.0
			rect.width += 40.0

			rect = RECT_add_bottom(rect, BUTTON_HEIGHT)
			IMUI_toggle_button(rect, "Highlight Layer", &_ctx.highlight_layer)
			rect = RECT_add_bottom(rect, BUTTON_HEIGHT)
			IMUI_toggle_button(rect, "Show Grid", &_ctx.show_grid)
			rect = RECT_add_bottom(rect, BUTTON_HEIGHT)
			IMUI_toggle_button(rect, "Show Rect", &_ctx.show_rect)
		}

		help_button_rect := RECT_cut_left(&menu_bar_rect, 80.0)
		if IMUI_button(help_button_rect, "Help") {
			_ctx.is_file_dropdown_open = false
			_ctx.is_edit_dropdown_open = false
			_ctx.is_view_dropdown_open = false
			_ctx.is_help_dropdown_open = !_ctx.is_help_dropdown_open
		}

		if _ctx.is_help_dropdown_open {
			rect := help_button_rect
			rect.y += 4.0
			rect.width += 200.0

			rect = RECT_add_bottom(rect, BUTTON_HEIGHT)
			IMUI_label_rect(rect, "WASD --- move around")
			rect = RECT_add_bottom(rect, BUTTON_HEIGHT)
			IMUI_label_rect(rect, "WASD + LSHIFT --- move around fast")
			rect = RECT_add_bottom(rect, BUTTON_HEIGHT)
			IMUI_label_rect(rect, "SCROLL --- zoom")
			rect = RECT_add_bottom(rect, BUTTON_HEIGHT)
			IMUI_label_rect(rect, "RMB --- deselect")
		}
	}

	rl.EndDrawing()
}



@(private="file")
_do_editor_logic :: proc() {
	if _ctx.is_resize_hovered && rl.IsMouseButtonPressed(.LEFT) {
		_ctx.is_resizing = true
	}

	if _ctx.is_resizing {
		_ctx.resize_amount.x = max(0, _ctx.mouse_pos.x)/GRID_SIZE - _ctx.level.width
		_ctx.resize_amount.y = max(0, _ctx.mouse_pos.y)/GRID_SIZE - _ctx.level.height

		if rl.IsMouseButtonReleased(.LEFT) {
			LVL_resize_editor_level(&_ctx.level, _ctx.level.width + _ctx.resize_amount.x, _ctx.level.height + _ctx.resize_amount.y)
			_ctx.is_resizing = false
			_ctx.resize_amount = {}
		}
	}

	if !_ctx.is_resize_hovered && !_ctx.is_resizing {
		switch _ctx.curr_tool {
		case .Select: _do_select_tool()
		case .Brush:  _do_place_tool(false)
		case .Eraser: _do_place_tool(true)
		case .Bucket: _do_bucket_tool()
		}
	}
}

@(private="file")
_do_select_tool :: proc() {
	if rl.IsMouseButtonPressed(.LEFT) {
		_ctx.is_selecting = true
		_ctx.select_p1 = _ctx.mouse_pos
	}

	if _ctx.is_selecting {
		_ctx.select_p2 = _ctx.mouse_pos
		if _ctx.edit_mode == .Place_Tile || _ctx.edit_mode == .Place_Rect {
			if _ctx.select_p1.x <= _ctx.select_p2.x {
				_ctx.select_p2.x += GRID_SIZE
			}
			if _ctx.select_p1.y <= _ctx.select_p2.y {
				_ctx.select_p2.y += GRID_SIZE
			}
		}

		{
			bound_min := [2]int{
				min(_ctx.select_p1.x, _ctx.select_p2.x),
				min(_ctx.select_p1.y, _ctx.select_p2.y),
			}
			bound_max := [2]int{
				max(_ctx.select_p1.x, _ctx.select_p2.x),
				max(_ctx.select_p1.y, _ctx.select_p2.y),
			}
			LVL_get_editor_entity_index_in_area(
				&_ctx.level,
				_ctx.curr_layer,
				bound_min,
				bound_max,
				&_ctx.selected_entities,
			)
		}

		if rl.IsMouseButtonReleased(.LEFT) {
			_ctx.is_selecting = false
			_ctx.is_selected = true
		}
	}

	if _ctx.is_selected {
		select_min, select_max := _get_select_range()

		// move
		if rl.IsMouseButtonPressed(.MIDDLE) {
			_ctx.is_moving_selected = true
			_ctx.selected_move_p1 = _ctx.mouse_pos

			width := select_max.x - select_min.x
			height := select_max.y - select_min.y

			if len(_ctx.selected_tiles) < width*height {
				resize(&_ctx.selected_tiles, width*height)
				resize(&_ctx.selected_rects, width*height)
			}
			index := 0
			for y in select_min.y..<select_max.y {
				for x in select_min.x..<select_max.x {
					switch _ctx.edit_mode {
					case .Place_Tile:
						_ctx.selected_tiles[index] = LVL_get_editor_tile(
							&_ctx.level,
							_ctx.curr_layer,
							{x, y},
						)

					case .Place_Rect:
						_ctx.selected_rects[index] = LVL_get_editor_rect(&_ctx.level, {x, y})

					case .Place_Entity: // do nothing
					}

					index += 1
				}
			}
		}

		if _ctx.is_moving_selected {
			_ctx.selected_move_p2 = _ctx.mouse_pos

			if rl.IsMouseButtonReleased(.MIDDLE) {
				move_offset := _ctx.selected_move_p2 - _ctx.selected_move_p1
				_ctx.select_p1 += move_offset
				_ctx.select_p2 += move_offset

				_ctx.is_moving_selected = false
				_ctx.selected_move_p1 = {}
				_ctx.selected_move_p2 = {}

				switch _ctx.edit_mode {
				case .Place_Tile:
					LVL_move_editor_tile(
						&_ctx.level,
						_ctx.curr_layer,
						_ctx.selected_tiles[:],
						select_min,
						select_max,
						move_offset/GRID_SIZE,
					)

				case .Place_Rect:
					LVL_move_editor_rect(
						&_ctx.level,
						_ctx.selected_rects[:],
						select_min,
						select_max,
						move_offset/GRID_SIZE,
					)

				case .Place_Entity:
					LVL_move_editor_entity(
						&_ctx.level,
						_ctx.curr_layer,
						_ctx.selected_entities[:],
						move_offset,
					)

					// get new indices in case some got removed
					bound_min := [2]int{
						min(_ctx.select_p1.x, _ctx.select_p2.x),
						min(_ctx.select_p1.y, _ctx.select_p2.y),
					}
					bound_max := [2]int{
						max(_ctx.select_p1.x, _ctx.select_p2.x),
						max(_ctx.select_p1.y, _ctx.select_p2.y),
					}
					LVL_get_editor_entity_index_in_area(
						&_ctx.level,
						_ctx.curr_layer,
						bound_min,
						bound_max,
						&_ctx.selected_entities,
					)
				}
			}
		}

		// delete
		if rl.IsKeyPressed(.DELETE) {
			switch _ctx.edit_mode {
			case .Place_Tile:
				for y in select_min.y..<select_max.y {
					for x in select_min.x..<select_max.x {
						LVL_remove_editor_tile(&_ctx.level, _ctx.curr_layer, {x, y}, select_min, select_max)
					}
				}

			case .Place_Rect:
				for y in select_min.y..<select_max.y {
					for x in select_min.x..<select_max.x {
						LVL_remove_editor_rect(&_ctx.level, {x, y}, select_min, select_max)
					}
				}

			case .Place_Entity:
				#reverse for index in _ctx.selected_entities {
					LVL_remove_editor_entity(&_ctx.level, _ctx.curr_layer, index)
				}

				LVL_get_editor_entity_index_in_area(
					&_ctx.level,
					_ctx.curr_layer,
					select_min,
					select_max,
					&_ctx.selected_entities,
				)
			}
		}

		// deselect
		if rl.IsMouseButtonPressed(.RIGHT) {
			_ctx.is_selected = false
			_ctx.select_p1 = {}
			_ctx.select_p2 = {}
		}
	}
}

@(private="file")
_do_place_tool :: proc(is_remove: bool) {
	if rl.IsMouseButtonUp(.LEFT) {
		return
	}

	select_min, select_max := _get_select_range()

	switch _ctx.edit_mode {
	case .Place_Tile:
		if !is_remove {
			LVL_place_editor_tile(
				&_ctx.level,
				_ctx.curr_layer,
				u16(_ctx.curr_tile_id),
				_ctx.mouse_pos/GRID_SIZE,
				select_min,
				select_max,
			)
		} else {
			LVL_remove_editor_tile(
				&_ctx.level,
				_ctx.curr_layer,
				_ctx.mouse_pos/GRID_SIZE,
				select_min,
				select_max,
			)
		}

	case .Place_Rect:
		if !is_remove {
			LVL_place_editor_rect(&_ctx.level, _ctx.mouse_pos/GRID_SIZE, select_min, select_max)
		} else {
			LVL_remove_editor_rect(&_ctx.level, _ctx.mouse_pos/GRID_SIZE, select_min, select_max)
		}

	case .Place_Entity:
		if rl.IsMouseButtonPressed(.LEFT) {
			if !is_remove {
				LVL_place_editor_entity(
					&_ctx.level,
					_ctx.curr_layer,
					_ctx.curr_entity_kind,
					_ctx.mouse_pos,
				)
			} else {
				index := LVL_get_editor_entity_index(&_ctx.level, _ctx.curr_layer, _ctx.mouse_pos)
				LVL_remove_editor_entity(&_ctx.level, _ctx.curr_layer, index)
			}
		}
	}
}

@(private="file")
_do_bucket_tool :: proc() {
	select_min, select_max := _get_select_range()

	switch _ctx.edit_mode {
	case .Place_Tile:
		if rl.IsMouseButtonPressed(.LEFT) {
			LVL_fill_editor_tile(
				&_ctx.level,
				_ctx.curr_layer,
				u16(_ctx.curr_tile_id),
				_ctx.mouse_pos/GRID_SIZE,
				select_min,
				select_max,
			)
		} else if rl.IsMouseButtonPressed(.RIGHT) {
			LVL_fill_editor_tile(
				&_ctx.level,
				_ctx.curr_layer,
				0,
				_ctx.mouse_pos/GRID_SIZE,
				select_min,
				select_max,
			)
		}

	case .Place_Rect:
		if rl.IsMouseButtonPressed(.LEFT) {
			LVL_fill_editor_rect(
				&_ctx.level,
				true,
				_ctx.mouse_pos/GRID_SIZE,
				select_min,
				select_max,
			)
		} else if rl.IsMouseButtonPressed(.RIGHT) {
			LVL_fill_editor_rect(
				&_ctx.level,
				false,
				_ctx.mouse_pos/GRID_SIZE,
				select_min,
				select_max,
			)
		}

	case .Place_Entity: // do nothing
	}
}

@(private="file")
_get_select_range :: proc() -> (minimum, maximum: [2]int) {
	maximum = {_ctx.level.width, _ctx.level.height}
	if _ctx.is_selected {
		minimum = {
			min(_ctx.select_p1.x, _ctx.select_p2.x),
			min(_ctx.select_p1.y, _ctx.select_p2.y),
		}/GRID_SIZE
		maximum = {
			max(_ctx.select_p1.x, _ctx.select_p2.x),
			max(_ctx.select_p1.y, _ctx.select_p2.y),
		}/GRID_SIZE
	}
	return
}

}
*/
