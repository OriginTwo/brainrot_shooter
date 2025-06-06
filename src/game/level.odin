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
	height: f32,
	has_collision: bool,
}

// LVL_Chunk :: struct {
// 	// sector_indices: []int,
// 	// wall_indices: []int,
// }

LVL_Level :: struct {
	sectors: []LVL_Sector,
	walls: []LVL_Wall,
}

lvl_draw :: proc(lvl: ^LVL_Level) {
}
