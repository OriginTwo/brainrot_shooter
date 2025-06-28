package game

import sg "lib:sokol/gfx"

LVL_GRID_PER_CHUNK :: 24
LVL_UNIT_PER_GRID :: 0.5
LVL_UNIT_PER_CHUNK :: LVL_UNIT_PER_GRID*LVL_GRID_PER_CHUNK
LVL_UNIT_PER_TILE :: 1.5
LVL_VISIBLE_CHUNK_RADIUS :: 2

LVL_Texture_ID :: enum {
	Nil,
	No_Tex,
	UV_Test,
	Brick,
}

LVL_Sector :: struct {
	position: M_Vec2f32,
	size: M_Vec2f32,
	floor_y: f32,
	ceiling_y: f32,
	floor_texture_id: LVL_Texture_ID,
	ceiling_texture_id: LVL_Texture_ID,
}

LVL_Wall_Direction :: enum {
	North,
	East,
	South,
	West,
}

LVL_Wall :: struct {
	p1: M_Vec2f32,
	p2: M_Vec2f32,
	facing: LVL_Wall_Direction,
	y: f32,  // bottom y
	height: f32,
	texture_id: LVL_Texture_ID,
}

/* TODO: implmenetation
LVL_Object_Player_Spawn :: struct {
}

LVL_Object :: union {
	LVL_Object_Player_Spawn,
}
*/

LVL_Chunk :: struct {
	sector_indices: []int,
	wall_indices: []int,
}

LVL_Level :: struct {
	texture: GFX_Texture,
	texture_num_cols: int,
	texture_num_rows: int,
	sectors: []LVL_Sector,
	walls: []LVL_Wall,
	chunks: map[[2]int]LVL_Chunk,

	// only use the key
	drawn_sector_indices: map[int]byte,
	drawn_wall_indices: map[int]byte,
}

@(rodata)
LVL_TEXTURE_SOURCES := [LVL_Texture_ID]M_Rect{
	.Nil     = {0.0, 0.0, 0.0, 0.0},
	.No_Tex  = {0*16.0, 0*16.0, 16.0, 16.0},
	.UV_Test = {1*16.0, 0*16.0, 16.0, 16.0},
	.Brick   = {0*16.0, 1*16.0, 16.0, 16.0},
}

LVL_init :: proc(lvl: ^LVL_Level) {
	ASST_load_texture(&lvl.texture, IMAGE_LEVEL_PNG)
	lvl.texture_num_cols = int(sg.query_image_width(lvl.texture.texture))/16
	lvl.texture_num_rows = int(sg.query_image_height(lvl.texture.texture))/16
}

LVL_uninit :: proc(lvl: ^LVL_Level) {
	GFX_unload_texture(&lvl.texture)
	delete(lvl.sectors)
	delete(lvl.walls)
	for _, &chunk in lvl.chunks {
		delete(chunk.sector_indices)
		delete(chunk.wall_indices)
	}
	delete(lvl.chunks)
	delete(lvl.drawn_sector_indices)
	delete(lvl.drawn_wall_indices)
	lvl^ = {}
}

LVL_serialize :: proc(lvl: ^LVL_Level, ser: ^SER_Serializer) {
	SER_serialize_custom_slice(ser, &lvl.sectors, LVL__serialize_sector)
	SER_serialize_custom_slice(ser, &lvl.walls, LVL__serialize_wall)
	SER_serialize_custom_map(ser, &lvl.chunks, LVL__serialize_chunk_coord, LVL__serialize_chunk)
}

LVL_draw :: proc(lvl: ^LVL_Level, ren3d: ^GFX_3D_Renderer, position: M_Vec2f32) {
	clear(&lvl.drawn_sector_indices)
	clear(&lvl.drawn_wall_indices)

	chunk_coord := LVL_get_chunk_coord(position)
	min_chunk_coord := chunk_coord - LVL_VISIBLE_CHUNK_RADIUS
	max_chunk_coord := chunk_coord + LVL_VISIBLE_CHUNK_RADIUS

	for y in min_chunk_coord.y..=max_chunk_coord.y {
		for x in min_chunk_coord.x..=max_chunk_coord.x {
			LVL_draw_chunk(lvl, ren3d, {x, y})
		}
	}
}

LVL_draw_chunk :: proc(lvl: ^LVL_Level, ren3d: ^GFX_3D_Renderer, chunk_coord: [2]int) {
	chunk, chunk_ok := lvl.chunks[chunk_coord]
	if !chunk_ok {
		return
	}

	for sector_index in chunk.sector_indices {
		if sector_index in lvl.drawn_sector_indices {
			continue
		}

		lvl.drawn_sector_indices[sector_index] = 0

		sector := lvl.sectors[sector_index]

		x1 := sector.position.x
		z1 := sector.position.y
		x2 := sector.position.x + sector.size.x
		z2 := sector.position.y + sector.size.y

		// floor
		floor_col, floor_row := LVL__get_texture_column_and_row_from_id(sector.floor_texture_id)
		GFX_draw_3d_texture_tiled(
			ren3d,
			lvl.texture.texture, lvl.texture.sampler,
			LVL_UNIT_PER_TILE,
			lvl.texture_num_cols, lvl.texture_num_rows,
			floor_col, floor_row,
			.Pos_Y,
			{x1, sector.floor_y, z1}, M_COLOR_WHITE,
			{x2, sector.floor_y, z1}, M_COLOR_WHITE,
			{x2, sector.floor_y, z2}, M_COLOR_WHITE,
			{x1, sector.floor_y, z2}, M_COLOR_WHITE,
		)

		// ceiling
		ceiling_col, ceiling_row := LVL__get_texture_column_and_row_from_id(sector.ceiling_texture_id)
		GFX_draw_3d_texture_tiled(
			ren3d,
			lvl.texture.texture, lvl.texture.sampler,
			LVL_UNIT_PER_TILE,
			lvl.texture_num_cols, lvl.texture_num_rows,
			ceiling_col, ceiling_row,
			.Neg_Y,
			{x1, sector.ceiling_y, z2}, M_COLOR_WHITE,
			{x2, sector.ceiling_y, z2}, M_COLOR_WHITE,
			{x2, sector.ceiling_y, z1}, M_COLOR_WHITE,
			{x1, sector.ceiling_y, z1}, M_COLOR_WHITE,
		)
	}

	for wall_index in chunk.wall_indices {
		if wall_index in lvl.drawn_wall_indices {
			continue
		}
		lvl.drawn_wall_indices[wall_index] = 0

		wall := lvl.walls[wall_index]

		p1, p2, p3, p4: M_Vec3f32
		facing: GFX_3D_Tile_Normal

		switch wall.facing {
		case .North:
			p1 = {wall.p2.x, wall.y + wall.height, wall.p2.y}
			p2 = {wall.p1.x, wall.y + wall.height, wall.p1.y}
			p3 = {wall.p1.x, wall.y,               wall.p1.y}
			p4 = {wall.p2.x, wall.y,               wall.p2.y}
			facing = .Neg_Z

		case .East:
			p1 = {wall.p2.x, wall.y + wall.height, wall.p2.y}
			p2 = {wall.p1.x, wall.y + wall.height, wall.p1.y}
			p3 = {wall.p1.x, wall.y,               wall.p1.y}
			p4 = {wall.p2.x, wall.y,               wall.p2.y}
			facing = .Pos_X

		case .South:
			p1 = {wall.p1.x, wall.y + wall.height, wall.p1.y}
			p2 = {wall.p2.x, wall.y + wall.height, wall.p2.y}
			p3 = {wall.p2.x, wall.y,               wall.p2.y}
			p4 = {wall.p1.x, wall.y,               wall.p1.y}
			facing = .Pos_Z

		case .West:
			p1 = {wall.p1.x, wall.y + wall.height, wall.p1.y}
			p2 = {wall.p2.x, wall.y + wall.height, wall.p2.y}
			p3 = {wall.p2.x, wall.y,               wall.p2.y}
			p4 = {wall.p1.x, wall.y,               wall.p1.y}
			facing = .Neg_X
		}

		col, row := LVL__get_texture_column_and_row_from_id(wall.texture_id)
		GFX_draw_3d_texture_tiled(
			ren3d,
			lvl.texture.texture, lvl.texture.sampler,
			LVL_UNIT_PER_TILE,
			lvl.texture_num_cols, lvl.texture_num_rows,
			col, row,
			facing,
			p1, M_COLOR_WHITE,
			p2, M_COLOR_WHITE,
			p3, M_COLOR_WHITE,
			p4, M_COLOR_WHITE,
		)
	}
}

LVL_get_chunk_coord :: proc(position: M_Vec2f32) -> [2]int {
	position := position
	if position.x < 0.0 {
		position.x -= LVL_UNIT_PER_CHUNK
	}
	if position.y < 0.0 {
		position.y -= LVL_UNIT_PER_CHUNK
	}
	chunk_f := position/LVL_UNIT_PER_CHUNK
	return {int(chunk_f.x), int(chunk_f.y)}
}

LVL_get_chunk_coord_range :: proc(position, size: M_Vec2f32) -> (min, max: [2]int) {
	min_coord := position
	if min_coord.x < -LVL_UNIT_PER_GRID {
		min_coord.x += LVL_UNIT_PER_GRID
	}
	if min_coord.y < -LVL_UNIT_PER_GRID {
		min_coord.y += LVL_UNIT_PER_GRID
	}
	min = LVL_get_chunk_coord(min_coord)

	max_coord := position + size
	if max_coord.x >= 0.0 {
		max_coord.x -= LVL_UNIT_PER_GRID
	}
	if max_coord.y >= 0.0 {
		max_coord.y -= LVL_UNIT_PER_GRID
	}
	max = LVL_get_chunk_coord(max_coord) + 1

	return
}



@(private="file")
LVL__get_texture_column_and_row_from_id :: proc(id: LVL_Texture_ID) -> (col, row: int) {
	switch id {
	case .Nil:     row = -1; col = -1
	case .No_Tex:  row = 0; col = 0
	case .UV_Test: row = 0; col = 1
	case .Brick:   row = 1; col = 0
	}
	return
}

@(private="file")
LVL__serialize_sector :: proc(s: ^SER_Serializer, data: rawptr, loc := #caller_location) {
	sector := cast(^LVL_Sector)data
	SER_serialize(s, &sector.position, loc)
	SER_serialize(s, &sector.size, loc)
	SER_serialize(s, &sector.floor_y, loc)
	SER_serialize(s, &sector.ceiling_y, loc)
	SER_serialize(s, &sector.floor_texture_id, loc)
	SER_serialize(s, &sector.ceiling_texture_id, loc)
}

@(private="file")
LVL__serialize_wall :: proc(s: ^SER_Serializer, data: rawptr, loc := #caller_location) {
	wall := cast(^LVL_Wall)data
	SER_serialize(s, &wall.p1, loc)
	SER_serialize(s, &wall.p2, loc)
	SER_serialize(s, &wall.facing, loc)
	SER_serialize(s, &wall.y, loc)
	SER_serialize(s, &wall.height, loc)
	SER_serialize(s, &wall.texture_id, loc)
}

@(private="file")
LVL__serialize_chunk_coord :: proc(s: ^SER_Serializer, data: rawptr, loc := #caller_location) {
	coord := cast(^[2]int)data
	SER_serialize(s, coord, loc)
}

@(private="file")
LVL__serialize_chunk :: proc(s: ^SER_Serializer, data: rawptr, loc := #caller_location) {
	chunk := cast(^LVL_Chunk)data
	SER_serialize(s, &chunk.sector_indices, loc)
	SER_serialize(s, &chunk.wall_indices, loc)
}
