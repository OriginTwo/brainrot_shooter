package game

LVL_Sector :: struct {
	position: M_Vec2f32,
	size: M_Vec2f32,
	floor_y: f32,
	ceiling_y: f32,
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
	y: f32,
	height: f32,
}

// LVL_Chunk :: struct {
// 	// sector_indices: []int,
// 	// wall_indices: []int,
// }

LVL_Level :: struct {
	sectors: []LVL_Sector,
	walls: []LVL_Wall,
}

import "core:fmt"

LVL_draw :: proc(lvl: LVL_Level, ren3d: ^GFX_3D_Renderer) {
	// fmt.println(len(lvl.sectors), len(lvl.walls))
	for sector in lvl.sectors {

		x1 := sector.position.x
		z1 := sector.position.y
		x2 := sector.position.x + sector.size.x
		z2 := sector.position.y + sector.size.y

		// floor
		GFX_draw_3d_rect(
			ren3d,
			{x1, sector.floor_y, z1}, {0.0, 1.0, 0.0}, {127, 127, 127, 255},
			{x2, sector.floor_y, z1}, {0.0, 1.0, 0.0}, {127, 127, 127, 255},
			{x2, sector.floor_y, z2}, {0.0, 1.0, 0.0}, {127, 127, 127, 255},
			{x1, sector.floor_y, z2}, {0.0, 1.0, 0.0}, {127, 127, 127, 255},
		)

		// ceiling
		GFX_draw_3d_rect(
			ren3d,
			{x1, sector.ceiling_y, z2}, {0.0, -1.0, 0.0}, {127, 127, 127, 255},
			{x2, sector.ceiling_y, z2}, {0.0, -1.0, 0.0}, {127, 127, 127, 255},
			{x2, sector.ceiling_y, z1}, {0.0, -1.0, 0.0}, {127, 127, 127, 255},
			{x1, sector.ceiling_y, z1}, {0.0, -1.0, 0.0}, {127, 127, 127, 255},
		)
	}

	for wall in lvl.walls {
		switch wall.facing {
		case .North:

		case .East:

		case .South:
			GFX_draw_3d_rect(
				ren3d,
				{wall.p1.x, wall.y + wall.height, wall.p2.y}, {0.0, 0.0, 1.0}, {127, 127, 127, 255},
				{wall.p2.x, wall.y + wall.height, wall.p2.y}, {0.0, 0.0, 1.0}, {127, 127, 127, 255},
				{wall.p2.x, wall.y,               wall.p1.y}, {0.0, 0.0, 1.0}, {127, 127, 127, 255},
				{wall.p1.x, wall.y,               wall.p1.y}, {0.0, 0.0, 1.0}, {127, 127, 127, 255},
			)

		case .West:
		}
	}
}
