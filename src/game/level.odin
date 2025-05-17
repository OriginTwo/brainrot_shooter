package game

import "core:os"
import "core:slice"
import "core:bytes"
import "core:encoding/json"
import "core:container/queue"

import rl "vendor:raylib"

/*
#assert(false, "REMOVE RAYLIB")

LVL_Tile_Set :: struct {
	texture: rl.Texture,
	offsets: []Vec2f32,
	sources: []rl.Rectangle,
}

LVL_Tile_Layer :: struct {
	layer: i8,
	tiles: []u16,
}

LVL_Entity :: struct {
	pos: [2]int,
	kind: ENT_Entity_Kind,
}

LVL_Entity_Layer :: struct {
	layer: i8,
	entities: []LVL_Entity,
}

LVL_Level :: struct {
	width: int,
	height: int,

	tile_set: LVL_Tile_Set,
	tile_layers: []LVL_Tile_Layer,
	entity_layers: []LVL_Entity_Layer,
	rects: []bool,
}

LVL_unload_tile_set :: proc(set: ^LVL_Tile_Set) {
	rl.UnloadTexture(set.texture)
	delete(set.offsets)
	delete(set.sources)
	set^ = {}
}

LVL_load_level :: proc(level: ^LVL_Level, data: []byte) {
	s: SER_Serializer
	SER_init_reader(&s, data)
	LVL__serialize_level(level, &s)
	ASST_load_texture(&level.tile_set.texture, IMAGE_TILES)
}

LVL_unload_level :: proc(level: ^LVL_Level) {
	rl.UnloadTexture(level.tile_set.texture)
	delete(level.tile_set.offsets)
	delete(level.tile_set.sources)

	for l in level.tile_layers {
		delete(l.tiles)
	}
	delete(level.tile_layers)

	for l in level.entity_layers {
		delete(l.entities)
	}
	delete(level.entity_layers)

	delete(level.rects)

	level^ = {}
}

LVL_get_nearby_rect :: proc(
	level: ^LVL_Level,
	rect: rl.Rectangle,
	allocator := context.temp_allocator
) -> (width, height: int, rects: []bool) {
	// TODO: implementation
	assert(false, "NOT IMPLEMENTED")
	return 0, 0, nil
}

LVL_draw_level :: proc(level: ^LVL_Level, camera: rl.Camera2D, max_view: Vec2f32) {
	tile_layer_index := 0
	entity_layer_index := 0

	minimum := rl.GetScreenToWorld2D({0.0, 0.0}, camera)
	maximum := rl.GetScreenToWorld2D(max_view, camera)
	view_rect := rl.Rectangle{
		minimum.x,
		minimum.y,
		maximum.x - minimum.x,
		maximum.y - minimum.y,
	}

	start_x := clamp(int(minimum.x)/GRID_SIZE, 0, level.width)
	start_y := clamp(int(minimum.y)/GRID_SIZE, 0, level.height)
	end_x := clamp(int(maximum.x)/GRID_SIZE + 1, 0, level.width)
	end_y := clamp(int(maximum.y)/GRID_SIZE + 1, 0, level.height)

	for layer := i8(-128); layer < 127; layer += 1 {
		if tile_layer_index < len(level.tile_layers) {
			tile_layer := level.tile_layers[tile_layer_index]
			if tile_layer.layer == layer {
				tile_layer_index += 1

				for y in start_y..<end_y {
					for x in start_x..<end_x {
						id := tile_layer.tiles[y*level.width + x]
						if id == 0 {
							continue
						}

						source := level.tile_set.sources[id]
						offset := level.tile_set.offsets[id]
						rl.DrawTexturePro(
							level.tile_set.texture,
							source,
							{
								f32(x*GRID_SIZE) - offset.x,
								f32(y*GRID_SIZE) - offset.y,
								source.width,
								source.height,
							},
							{0.0, 0.0},
							0.0,
							rl.WHITE,
						)
					}
				}
			}
		}

		if entity_layer_index < len(level.entity_layers) {
			entity_layer := level.entity_layers[entity_layer_index]
			if entity_layer.layer == layer {
				entity_layer_index += 1

				for entity in entity_layer.entities {
					texture := ENT_get_texture(entity.kind)
					source := ENT_get_source(entity.kind)
					dest := rl.Rectangle{
						f32(entity.pos.x),
						f32(entity.pos.y),
						source.width,
						source.height,
					}
					if rl.CheckCollisionRecs(view_rect, dest) {
						rl.DrawTexturePro(
							texture,
							source,
							dest,
							{0.0, 0.0},
							0.0,
							rl.WHITE,
						)
					}
				}
			}
		}
	}
}



//:internal
@(private="file") LVL__TILE_BEGIN_COLOR  :: rl.Color{255,   0, 255, 255}
@(private="file") LVL__TILE_END_COLOR    :: rl.Color{  0, 255, 255, 255}
@(private="file") LVL__TILE_OFFSET_COLOR :: rl.Color{255,   0,   0, 255}

// NOTE: 'data' is for reading
@(private="file")
LVL__serialize_level :: proc(level: ^LVL_Level, s: ^SER_Serializer) {
	SER_serialize(s, &level.width)
	SER_serialize(s, &level.height)

	SER_serialize_opaque_slice(s, &level.tile_set.offsets)
	SER_serialize_opaque_slice(s, &level.tile_set.sources)

	SER_serialize_slice_info(s, &level.tile_layers)
	for &l in level.tile_layers {
		SER_serialize(s, &l.layer)
		SER_serialize_opaque_slice(s, &l.tiles)
	}

	SER_serialize_slice_info(s, &level.entity_layers)
	for &l in level.entity_layers {
		SER_serialize(s, &l.layer)
		SER_serialize_opaque_slice(s, &l.entities)
	}

	SER_serialize_opaque_slice(s, &level.rects)
}



//:editor
when DEV_BUILD {

LVL_Editor_Tile_Layer :: struct {
	next: ^LVL_Editor_Tile_Layer,
	prev: ^LVL_Editor_Tile_Layer,
	layer: i8,
	tiles: []u16,
}

LVL_Editor_Entity_Layer :: struct {
	next: ^LVL_Editor_Entity_Layer,
	prev: ^LVL_Editor_Entity_Layer,
	layer: i8,
	entities: [dynamic]LVL_Entity,
}

LVL_Editor_Level :: struct {
	width: int,
	height: int,

	tile_set: LVL_Tile_Set,
	tile_layers: ^LVL_Editor_Tile_Layer,
	entity_layers: ^LVL_Editor_Entity_Layer,
	rects: []bool,

	curr_tile_layer: ^LVL_Editor_Tile_Layer,
	curr_entity_layer: ^LVL_Editor_Entity_Layer,

	tile_fill_queue: queue.Queue([2]int),
	rect_fill_queue: queue.Queue([2]int),
}

LVL_load_editor_tile_set :: proc(set: ^LVL_Tile_Set, img: rl.Image) {
	set.texture = rl.LoadTextureFromImage(img)

	scanning: bool
	index: int
	start: [2]i32
	size: [2]i32
	offset: [2]i32

	// space for nil tile
	offsets := make([dynamic]Vec2f32, 1)
	sources := make([dynamic]rl.Rectangle, 1)

	for y: i32 = 0; y < img.height; {
		y_advance: i32 = 1

		for x in 0..<img.width {
			c := rl.GetImageColor(img, x, y)

			if c == LVL__TILE_BEGIN_COLOR {
				scanning = true
				start = {x + 1, y + 1}

				for yy in start.y..<img.height {
					cy := rl.GetImageColor(img, x, yy)
					if cy == LVL__TILE_OFFSET_COLOR {
						offset.y = yy - start.y
					} else if cy == LVL__TILE_END_COLOR {
						size.y = yy - start.y
						y_advance = max(y_advance, size.y)
						break
					}
				}
			}

			if scanning {
				if c == LVL__TILE_OFFSET_COLOR {
					offset.x = x - start.x
				} else if c == LVL__TILE_END_COLOR {
					scanning = false
					size.x = x - start.x

					append(&offsets, Vec2f32{f32(offset.x), f32(offset.y)})
					append(&sources, rl.Rectangle{f32(start.x), f32(start.y), f32(size.x), f32(size.y)})
				}
			}
		}

		y += y_advance
	}

	set.offsets = offsets[:]
	set.sources = sources[:]
}

LVL_init_editor_level :: proc(level: ^LVL_Editor_Level, width, height: int) {
	level.width = width
	level.height = height
	level.rects = make([]bool, level.width*level.height)
	queue.init(&level.tile_fill_queue, level.width*level.height)
	queue.init(&level.rect_fill_queue, level.width*level.height)

	{
		img := rl.LoadImage("res/image/tiles.png")
		LVL_load_editor_tile_set(&level.tile_set, img)
		rl.UnloadImage(img)
	}
}

LVL_uninit_editor_level :: proc(level: ^LVL_Editor_Level) {
	LVL_unload_tile_set(&level.tile_set)

	for l := level.tile_layers; l != nil; {
		to_free := l
		l = l.next
		delete(to_free.tiles)
		free(to_free)
	}

	for l := level.entity_layers; l != nil; {
		to_free := l
		l = l.next
		delete(to_free.entities)
		free(to_free)
	}

	delete(level.rects)

	queue.destroy(&level.tile_fill_queue)
	queue.destroy(&level.rect_fill_queue)

	level^ = {}
}

LVL_save_editor_level :: proc(level: ^LVL_Editor_Level, path: string) -> bool {
	SER_lvl := LVL_Level{
		width = level.width,
		height = level.height,
		rects = level.rects,
	}

	tile_layers: [dynamic]LVL_Tile_Layer
	entity_layers: [dynamic]LVL_Entity_Layer
	defer delete(tile_layers)
	defer delete(entity_layers)

	for l := level.tile_layers; l != nil; l = l.next {
		empty := true

		for tile in l.tiles {
			if tile != 0 {
				empty = false
				break
			}
		}

		if !empty {
			append(&tile_layers, LVL_Tile_Layer{
				layer = l.layer,
				tiles = l.tiles,
			})
		}
	}

	for l := level.entity_layers; l != nil; l = l.next {
		if len(l.entities) > 0 {
			append(&entity_layers, LVL_Entity_Layer{
				layer = l.layer,
				entities = l.entities[:],
			})
		}
	}

	SER_lvl.tile_layers = tile_layers[:]
	SER_lvl.entity_layers = entity_layers[:]

	data, data_err := json.marshal(SER_lvl, LVL__JSON_OPTIONS, context.temp_allocator)
	if data_err != nil {
		return false
	}

	if !os.write_entire_file(path, data) {
		return false
	}

	return true
}

LVL_load_editor_level :: proc(level: ^LVL_Editor_Level, path: string) -> bool {
	SER_lvl: LVL_Level

	data, data_ok := os.read_entire_file(path, context.temp_allocator)
	if !data_ok {
		return false
	}

	json_err := json.unmarshal(data, &SER_lvl, LVL__JSON_OPTIONS.spec, context.temp_allocator)
	if json_err != nil {
		return false
	}

	LVL_init_editor_level(level, SER_lvl.width, SER_lvl.height)

	for rect, i in SER_lvl.rects {
		level.rects[i] = rect
	}

	for l, i in SER_lvl.tile_layers {
		layer := LVL__new_editor_tile_layer(level, l.layer)
		copy(layer.tiles, l.tiles)

		if i == 0 {
			level.tile_layers = layer
		}

		if layer.layer == 0 {
			level.curr_tile_layer = layer
		}
	}

	for l, i in SER_lvl.entity_layers {
		layer := LVL__new_editor_entity_layer(level, l.layer)
		for entity in l.entities {
			append(&layer.entities, entity)
		}

		if i == 0 {
			level.entity_layers = layer
		}

		if layer.layer == 0 {
			level.curr_entity_layer = layer
		}
	}

	return true
}

LVL_export_editor_level :: proc(level: ^LVL_Editor_Level, path: string) -> bool {
	tile_layers: [dynamic]LVL_Tile_Layer
	entity_layers: [dynamic]LVL_Entity_Layer
	defer delete(tile_layers)
	defer delete(entity_layers)

	for l := level.tile_layers; l != nil; l = l.next {
		empty := true

		for tile in l.tiles {
			if tile != 0 {
				empty = false
				break
			}
		}

		if !empty {
			append(&tile_layers, LVL_Tile_Layer{
				layer = l.layer,
				tiles = l.tiles,
			})
		}
	}

	for l := level.entity_layers; l != nil; l = l.next {
		if len(l.entities) > 0 {
			append(&entity_layers, LVL_Entity_Layer{
				layer = l.layer,
				entities = l.entities[:],
			})
		}
	}

	SER_lvl := LVL_Level{
		width = level.width,
		height = level.height,
		tile_set = level.tile_set,
		tile_layers = tile_layers[:],
		entity_layers = entity_layers[:],
		rects = level.rects,
	}

	s: SER_Serializer
	SER_init_writer(&s, 2048)
	defer SER_destroy_writer(&s)
	LVL__serialize_level(&SER_lvl, &s)

	return os.write_entire_file(path, SER_to_bytes(&s))
}

LVL_resize_editor_level :: proc(level: ^LVL_Editor_Level, new_width, new_height: int) {
	if new_width == level.width && new_height == level.height {
		return
	}

	// tile
	for l := level.tile_layers; l != nil; l = l.next {
		new_tiles := make([]u16, new_width*new_height)

		for y in 0..<min(new_height, level.height) {
			for x in 0..<min(new_width, level.width) {
				new_tiles[y*new_width + x] = l.tiles[y*level.width + x]
			}
		}

		delete(l.tiles)
		l.tiles = new_tiles
	}

	// rect
	{
		new_rects := make([]bool, new_width*new_height)

		for y in 0..<min(new_height, level.height) {
			for x in 0..<min(new_width, level.width) {
				new_rects[y*new_width + x] = level.rects[y*level.width + x]
			}
		}

		delete(level.rects)
		level.rects = new_rects
	}

	// entity
	for l := level.entity_layers; l != nil; l = l.next {
		#reverse for entity, i in l.entities {
			if entity.pos.x >= level.width*GRID_SIZE || entity.pos.y >= level.height*GRID_SIZE {
				ordered_remove(&l.entities, i)
			}
		}
	}

	// fill queue
	{
		queue.reserve(&level.tile_fill_queue, new_width*new_height)
		queue.reserve(&level.rect_fill_queue, new_width*new_height)
	}

	level.width = new_width
	level.height = new_height
}

LVL_place_editor_tile :: proc(
	level: ^LVL_Editor_Level,
	layer: i8,
	tile_id: u16,
	pos: [2]int,
	bound_min: [2]int,
	bound_max: [2]int,
) {
	if !LVL__is_editor_pos_in_bound(level, pos, bound_min, bound_max) {
		return
	}

	if level.curr_tile_layer == nil {
		level.tile_layers = new(LVL_Editor_Tile_Layer)
		level.curr_tile_layer = level.tile_layers
		level.curr_tile_layer.layer = layer
		level.curr_tile_layer.tiles = make([]u16, level.width*level.height)
	} else if !LVL__try_set_editor_tile_layer(level, layer) {
		level.curr_tile_layer = LVL__new_editor_tile_layer(level, layer)
	}

	level.curr_tile_layer.tiles[pos.y*level.width + pos.x] = tile_id
}

LVL_remove_editor_tile :: proc(
	level: ^LVL_Editor_Level,
	layer: i8,
	pos: [2]int,
	bound_min: [2]int,
	bound_max: [2]int,
) {
	if !LVL__is_editor_pos_in_bound(level, pos, bound_min, bound_max) || level.curr_tile_layer == nil {
		return
	}

	if LVL__try_set_editor_tile_layer(level, layer) {
		level.curr_tile_layer.tiles[pos.y*level.width + pos.x] = 0
	}
}

LVL_get_editor_tile :: proc(level: ^LVL_Editor_Level, layer: i8, pos: [2]int) -> u16 {
	if !LVL__is_editor_pos_valid(level, pos) || level.curr_tile_layer == nil {
		return 0
	}

	result: u16

	if LVL__try_set_editor_tile_layer(level, layer) {
		result = level.curr_tile_layer.tiles[pos.y*level.width + pos.x]
	}

	return result
}

LVL_move_editor_tile :: proc(
	level: ^LVL_Editor_Level,
	layer: i8,
	new_tiles: []u16,
	bound_min: [2]int,
	bound_max: [2]int,
	move_offset: [2]int,
) {
	if level.curr_tile_layer == nil || move_offset == {} {
		return
	}

	if LVL__try_set_editor_tile_layer(level, layer) {
		// clear the original
		for y in bound_min.y..<bound_max.y {
			for x in bound_min.x..<bound_max.x {
				if !LVL__is_editor_pos_valid(level, {x, y}) {
					continue
				}
				level.curr_tile_layer.tiles[y*level.width + x] = 0
			}
		}

		// set new tiles
		index := 0
		for y in bound_min.y..<bound_max.y {
			for x in bound_min.x..<bound_max.x {
				new_pos := move_offset + {x, y}

				tile := new_tiles[index]
				index += 1

				if !LVL__is_editor_pos_valid(level, new_pos) {
					continue
				}

				level.curr_tile_layer.tiles[new_pos.y*level.width + new_pos.x] = tile
			}
		}
	}
}

LVL_fill_editor_tile :: proc(
	level: ^LVL_Editor_Level,
	layer: i8,
	tile_id: u16,
	start_pos: [2]int,
	bound_min: [2]int,
	bound_max: [2]int,
) {
	if !LVL__is_editor_pos_in_bound(level, start_pos, bound_min, bound_max) {
		return
	}

	if level.curr_tile_layer == nil {
		level.tile_layers = new(LVL_Editor_Tile_Layer)
		level.curr_tile_layer = level.tile_layers
		level.curr_tile_layer.layer = layer
		level.curr_tile_layer.tiles = make([]u16, level.width*level.height)
	} else if !LVL__try_set_editor_tile_layer(level, layer) {
		level.curr_tile_layer = LVL__new_editor_tile_layer(level, layer)
	}

	start_pos_tile_id := level.curr_tile_layer.tiles[start_pos.y*level.width + start_pos.x]
	if start_pos_tile_id == tile_id {
		return
	}

	queue.clear(&level.tile_fill_queue)
	queue.append(&level.tile_fill_queue, start_pos)

	for queue.len(level.tile_fill_queue) > 0 {
		p := queue.pop_front(&level.tile_fill_queue)

		if !LVL__is_editor_pos_in_bound(level, p, bound_min, bound_max) {
			continue
		}

		curr_tile := level.curr_tile_layer.tiles[p.y*level.width + p.x]
		if curr_tile == tile_id || curr_tile != start_pos_tile_id {
			continue
		}

		level.curr_tile_layer.tiles[p.y*level.width + p.x] = tile_id

		queue.append(&level.tile_fill_queue, [2]int{p.x + 1, p.y})
		queue.append(&level.tile_fill_queue, [2]int{p.x - 1, p.y})
		queue.append(&level.tile_fill_queue, [2]int{p.x, p.y + 1})
		queue.append(&level.tile_fill_queue, [2]int{p.x, p.y - 1})
	}
}

LVL_place_editor_rect :: proc(level: ^LVL_Editor_Level, pos, bound_min, bound_max: [2]int) {
	if !LVL__is_editor_pos_in_bound(level, pos, bound_min, bound_max) {
		return
	}

	level.rects[pos.y*level.width + pos.x] = true
}

LVL_remove_editor_rect :: proc(level: ^LVL_Editor_Level, pos, bound_min, bound_max: [2]int) {
	if !LVL__is_editor_pos_in_bound(level, pos, bound_min, bound_max) {
		return
	}

	level.rects[pos.y*level.width + pos.x] = false
}

LVL_get_editor_rect :: proc(level: ^LVL_Editor_Level, pos: [2]int) -> bool {
	if !LVL__is_editor_pos_valid(level, pos) {
		return false
	}

	return level.rects[pos.y*level.width + pos.x]
}

LVL_move_editor_rect :: proc(
	level: ^LVL_Editor_Level,
	new_rects: []bool,
	bound_min: [2]int,
	bound_max: [2]int,
	move_offset: [2]int,
) {
	if move_offset == {} {
		return
	}

	// clear the original
	for y in bound_min.y..<bound_max.y {
		for x in bound_min.x..<bound_max.x {
			if !LVL__is_editor_pos_valid(level, {x, y}) {
				continue
			}
			level.rects[y*level.width + x] = false
		}
	}

	// set new tiles
	index := 0
	for y in bound_min.y..<bound_max.y {
		for x in bound_min.x..<bound_max.x {
			new_pos := move_offset + {x, y}

			rect := new_rects[index]
			index += 1

			if !LVL__is_editor_pos_valid(level, new_pos) {
				continue
			}

			level.rects[new_pos.y*level.width + new_pos.x] = rect
		}
	}
}

LVL_fill_editor_rect :: proc(
	level: ^LVL_Editor_Level,
	rect: bool,
	start_pos: [2]int,
	bound_min: [2]int,
	bound_max: [2]int,
) {
	if !LVL__is_editor_pos_in_bound(level, start_pos, bound_min, bound_max) {
		return
	}

	start_pos_rect := level.rects[start_pos.y*level.width + start_pos.x]
	if start_pos_rect == rect {
		return
	}

	queue.clear(&level.rect_fill_queue)
	queue.append(&level.rect_fill_queue, start_pos)

	for queue.len(level.rect_fill_queue) > 0 {
		p := queue.pop_front(&level.rect_fill_queue)

		if !LVL__is_editor_pos_in_bound(level, p, bound_min, bound_max) {
			continue
		}

		curr_rect := level.rects[p.y*level.width + p.x]
		if curr_rect == rect || curr_rect != start_pos_rect {
			continue
		}

		level.rects[p.y*level.width + p.x] = rect

		queue.append(&level.rect_fill_queue, [2]int{p.x + 1, p.y})
		queue.append(&level.rect_fill_queue, [2]int{p.x - 1, p.y})
		queue.append(&level.rect_fill_queue, [2]int{p.x, p.y + 1})
		queue.append(&level.rect_fill_queue, [2]int{p.x, p.y - 1})
	}
}

LVL_place_editor_entity :: proc(
	level: ^LVL_Editor_Level,
	layer: i8,
	entity_kind: ENT_Entity_Kind,
	pos: [2]int,
) {
	if pos.x < 0 || pos.x >= level.width*GRID_SIZE || pos.y < 0 || pos.y >= level.height*GRID_SIZE {
		return
	}

	if level.curr_entity_layer == nil {
		level.entity_layers = new(LVL_Editor_Entity_Layer)
		level.curr_entity_layer = level.entity_layers
		level.curr_entity_layer.layer = layer
		level.curr_entity_layer.entities = make([dynamic]LVL_Entity, 0, 8)
	} else if !LVL__try_set_editor_entity_layer(level, layer) {
		level.curr_entity_layer = LVL__new_editor_entity_layer(level, layer)
	}

	append(&level.curr_entity_layer.entities, LVL_Entity{pos = pos, kind = entity_kind})
}

LVL_remove_editor_entity :: proc(
	level: ^LVL_Editor_Level,
	layer: i8,
	index: int,
) {
	if index < 0 {
		return
	}

	if LVL__try_set_editor_entity_layer(level, layer) {
		if index >= len(level.curr_entity_layer.entities) {
			return
		}

		ordered_remove(&level.curr_entity_layer.entities, index)
	}
}

LVL_get_editor_entity_index :: proc(level: ^LVL_Editor_Level, layer: i8, pos: [2]int) -> int {
	result := -1

	if pos.x < 0 || pos.x >= level.width*GRID_SIZE || pos.y < 0 || pos.y >= level.height*GRID_SIZE ||
		level.curr_entity_layer == nil
	{
		return result
	}

	if LVL__try_set_editor_entity_layer(level, layer) {
		#reverse for entity, i in level.curr_entity_layer.entities {
			source := ENT_get_editor_source(entity.kind)
			if rl.CheckCollisionPointRec(
				{f32(pos.x), f32(pos.y)},
				{f32(entity.pos.x), f32(entity.pos.y), source.width, source.height},
			) {
				result = i
				break
			}
		}
	}

	return result
}

LVL_get_editor_entity_index_in_area :: proc(
	level: ^LVL_Editor_Level,
	layer: i8,
	bound_min: [2]int,
	bound_max: [2]int,
	out: ^[dynamic]int,
) {
	if level.curr_entity_layer == nil {
		return
	}

	if LVL__try_set_editor_entity_layer(level, layer) {
		clear(out)

		bound_rect := rl.Rectangle{
			f32(bound_min.x),
			f32(bound_min.y),
			f32(bound_max.x - bound_min.x),
			f32(bound_max.y - bound_min.y),
		}

		for entity, i in level.curr_entity_layer.entities {
			source := ENT_get_editor_source(entity.kind)
			if rl.CheckCollisionRecs(
				bound_rect,
				{f32(entity.pos.x), f32(entity.pos.y), source.width, source.height},
			) {
				append(out, i)
			}
		}
	}
}

LVL_move_editor_entity :: proc(
	level: ^LVL_Editor_Level,
	layer: i8,
	indices: []int,
	move_offset: [2]int,
) {
	if level.curr_entity_layer == nil || move_offset == {} {
		return
	}

	if LVL__try_set_editor_entity_layer(level, layer) {
		indices_to_remove: [dynamic]int
		defer delete(indices_to_remove)

		for i in indices {
			new_pos := level.curr_entity_layer.entities[i].pos + move_offset

			if new_pos.x < 0 || new_pos.x >= level.width*GRID_SIZE ||
				new_pos.y < 0 || new_pos.y >= level.height*GRID_SIZE
			{
				append(&indices_to_remove, i)
				continue
			}

			level.curr_entity_layer.entities[i].pos = new_pos
		}

		// this works because it's sorted (should be at least)
		indices_removed := 0
		for i in indices_to_remove {
			ordered_remove(&level.curr_entity_layer.entities, i - indices_removed)
			indices_removed += 1
		}
	}
}



//:internal_editor
@(private="file")
LVL__JSON_OPTIONS :: json.Marshal_Options{
	spec = json.DEFAULT_SPECIFICATION,
	pretty = true,
	use_spaces = false,
	sort_maps_by_key = true,
	use_enum_names = true,
}

@(private="file")
LVL__is_editor_pos_valid :: proc(level: ^LVL_Editor_Level, pos: [2]int) -> bool {
	return pos.x >= 0 && pos.x < level.width && pos.y >= 0 && pos.y < level.height
}

@(private="file")
LVL__is_editor_pos_in_bound :: proc(level: ^LVL_Editor_Level, pos, bound_min, bound_max: [2]int) -> bool {
	return pos.x >= 0 && pos.x < level.width && pos.x >= bound_min.x && pos.x < bound_max.x &&
		pos.y >= 0 && pos.y < level.height && pos.y >= bound_min.y && pos.y < bound_max.y
}

@(private="file")
LVL__new_editor_tile_layer :: proc(level: ^LVL_Editor_Level, layer: i8) -> ^LVL_Editor_Tile_Layer {
	new_layer := new(LVL_Editor_Tile_Layer)
	new_layer.layer = layer
	new_layer.tiles = make([]u16, level.width*level.height)
	prev_of_new_layer: ^LVL_Editor_Tile_Layer
	next_of_new_layer: ^LVL_Editor_Tile_Layer

	for l := level.tile_layers; l != nil; l = l.next {
		if l.layer < layer {
			prev_of_new_layer = l
		} else if l.layer > layer {
			next_of_new_layer = l
			level.tile_layers = new_layer
			break
		}
	}

	if prev_of_new_layer != nil {
		new_layer.prev = prev_of_new_layer
		prev_of_new_layer.next = new_layer
	}
	if next_of_new_layer != nil {
		new_layer.next = next_of_new_layer
		next_of_new_layer.prev = new_layer
	}

	return new_layer
}

@(private="file")
LVL__try_set_editor_tile_layer :: proc(level: ^LVL_Editor_Level, layer: i8) -> bool {
	success := true

	if level.curr_tile_layer.layer != layer {
		success = false
		for l := level.tile_layers; l != nil; l = l.next {
			if l.layer == layer {
				level.curr_tile_layer = l
				success = true
				break
			}
		}
	}

	return success
}

@(private="file")
LVL__new_editor_entity_layer :: proc(level: ^LVL_Editor_Level, layer: i8) -> ^LVL_Editor_Entity_Layer {
	new_layer := new(LVL_Editor_Entity_Layer)
	new_layer.layer = layer
	new_layer.entities = make([dynamic]LVL_Entity, 0, 8)
	prev_of_new_layer: ^LVL_Editor_Entity_Layer
	next_of_new_layer: ^LVL_Editor_Entity_Layer

	for l := level.entity_layers; l != nil; l = l.next {
		if l.layer < layer {
			prev_of_new_layer = l
		} else if l.layer > layer {
			next_of_new_layer = l
			level.entity_layers = new_layer
			break
		}
	}

	if prev_of_new_layer != nil {
		new_layer.prev = prev_of_new_layer
		prev_of_new_layer.next = new_layer
	}
	if next_of_new_layer != nil {
		new_layer.next = next_of_new_layer
		next_of_new_layer.prev = new_layer
	}

	return new_layer
}

@(private="file")
LVL__try_set_editor_entity_layer :: proc(level: ^LVL_Editor_Level, layer: i8) -> bool {
	success := true

	if level.curr_entity_layer.layer != layer {
		success = false
		for l := level.entity_layers; l != nil; l = l.next {
			if l.layer == layer {
				level.curr_entity_layer = l
				success = true
				break
			}
		}
	}

	return success
}

}
*/
