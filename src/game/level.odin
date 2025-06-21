package game

import sg "lib:sokol/gfx"

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

LVL_Texture_ID :: enum {
	Nil,
	No_Tex,
	UV_Test,
	Brick,
}

// LVL_Chunk :: struct {
// 	// sector_indices: []int,
// 	// wall_indices: []int,
// }

LVL_Level :: struct {
	texture: GFX_Texture,
	sectors: []LVL_Sector,
	walls: []LVL_Wall,
}

@(rodata)
LVL_TEXTURE_SOURCES := [LVL_Texture_ID]M_Rect{
	.Nil     = {0.0, 0.0, 0.0, 0.0},
	.No_Tex  = {0*16.0, 0*16.0, 16.0, 16.0},
	.UV_Test = {1*16.0, 0*16.0, 16.0, 16.0},
	.Brick   = {0*16.0, 1*16.0, 16.0, 16.0},
}

LVL_load_texture :: proc(lvl: ^LVL_Level) {
	ASST_load_texture(&lvl.texture, IMAGE_LEVEL_PNG)
}

LVL_draw :: proc(lvl: LVL_Level, ren3d: ^GFX_3D_Renderer) {
	WORLD_UNIT_PER_TILE :: 1.5
	NUM_COLUMNS :: 8
	NUM_ROWS :: 8

	for sector in lvl.sectors {
		x1 := sector.position.x
		z1 := sector.position.y
		x2 := sector.position.x + sector.size.x
		z2 := sector.position.y + sector.size.y

		// floor
		floor_col, floor_row := LVL__get_texture_column_and_row_from_id(sector.floor_texture_id)
		GFX_draw_3d_texture_tiled(
			ren3d,
			lvl.texture.texture, lvl.texture.sampler,
			WORLD_UNIT_PER_TILE,
			NUM_COLUMNS, NUM_ROWS,
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
			WORLD_UNIT_PER_TILE,
			NUM_COLUMNS, NUM_ROWS,
			ceiling_col, ceiling_row,
			.Neg_Y,
			{x1, sector.ceiling_y, z2}, M_COLOR_WHITE,
			{x2, sector.ceiling_y, z2}, M_COLOR_WHITE,
			{x2, sector.ceiling_y, z1}, M_COLOR_WHITE,
			{x1, sector.ceiling_y, z1}, M_COLOR_WHITE,
		)
	}

	for wall in lvl.walls {
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
			WORLD_UNIT_PER_TILE,
			NUM_COLUMNS, NUM_ROWS,
			col, row,
			facing,
			p1, M_COLOR_WHITE,
			p2, M_COLOR_WHITE,
			p3, M_COLOR_WHITE,
			p4, M_COLOR_WHITE,
		)
	}
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
