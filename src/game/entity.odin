package game

import rl "vendor:raylib"

/*
#assert(false, "REMOVE RAYLIB")

ENT_Entity_Kind :: enum {
	Player,
	Tree,
	Mushroom,
}

ENT_Entity_Data :: union {
}

ENT_Entity :: struct {
	kind: ENT_Entity_Kind,
	data: ENT_Entity_Data,  // entity specific data

	pos: Vec2f32,
	texture: rl.Texture2D,
	texture_source: rl.Rectangle,
}

// TODO: should probably get dear imgui working for this, so that it's easier to do UI stuff

/* TODO: ENTITY SYSTEM REWORK IMPLEMENTATION
- 'Entity' edit mode
	- toggle component flags
	- set component values (such as sprite, animation)
	- save/load created entities from file
	- export created entities
- 'Place_Entity' edit mode
	- place the created entity


// NOTE: this is basic pseudo implementation, could use sparse array if memory is concerned
Entity :: int  // index

Entity_Set :: struct {
	flags: []Component_Flags,
	position_component: []Position_Component,
	sprite_component: []Sprite_Component,
	animation_component: []Animation_Component,
}
*/

// TODO: this is temporary code to get things on the screen
// TODO: rewrite the game entity api
ENT_init :: proc() {
	{
		tex: rl.Texture2D
		ASST_load_texture(&tex, IMAGE_ENTITY_TREE)
		ENT__ctx.textures[.Tree] = tex
		ENT__ctx.sources[.Tree] = {0.0, 0.0, f32(tex.width), f32(tex.height)}
	}

	{
		tex: rl.Texture2D
		ASST_load_texture(&tex, IMAGE_ENTITY_MUSHROOM)
		ENT__ctx.textures[.Mushroom] = tex
		ENT__ctx.sources[.Mushroom] = {0.0, 0.0, f32(tex.width), f32(tex.height)}
	}
}

ENT_uninit :: proc() {
	for kind in ENT_Entity_Kind {
		rl.UnloadTexture(ENT__ctx.textures[kind])
	}
}

ENT_get_texture :: proc(kind: ENT_Entity_Kind) -> rl.Texture2D {
	return ENT__ctx.textures[kind]
}

ENT_get_source :: proc(kind: ENT_Entity_Kind) -> rl.Rectangle {
	return ENT__ctx.sources[kind]
}



//:internal
@(private="file")
ENT__ctx: struct {
	textures: [ENT_Entity_Kind]rl.Texture2D,
	sources: [ENT_Entity_Kind]rl.Rectangle,
}



//:editor
when DEV_BUILD {

ENT_load_editor_visual :: proc() {
	img := rl.LoadImage("res/image/editor_entities.png")
	defer rl.UnloadImage(img)

	ENT__editor_ctx.texture = rl.LoadTextureFromImage(img)

	scanning: bool
	index: int
	start: [2]i32
	size: [2]i32

	for y: i32 = 0; y < img.height; {
		y_advance: i32 = 1

		for x in 0..<img.width {
			c := rl.GetImageColor(img, x, y)

			if c == ENT__ENTITY_BEGIN_COLOR {
				scanning = true
				start = {x + 1, y + 1}

				for yy in start.y..<img.height {
					cy := rl.GetImageColor(img, x, yy)
					if cy == ENT__ENTITY_END_COLOR {
						size.y = yy - start.y
						y_advance = max(y_advance, size.y)
						break
					}
				}
			}

			if scanning {
				if c == ENT__ENTITY_END_COLOR {
					scanning = false
					size.x = x - start.x

					append(
						&ENT__editor_ctx.source,
						rl.Rectangle{f32(start.x), f32(start.y), f32(size.x), f32(size.y)},
					)
				}
			}
		}

		y += y_advance
	}
}

ENT_unload_editor_visual :: proc() {
	rl.UnloadTexture(ENT__editor_ctx.texture)
	delete(ENT__editor_ctx.source)
}

ENT_get_editor_texture :: proc() -> rl.Texture2D {
	return ENT__editor_ctx.texture
}

ENT_get_editor_source :: proc(kind: ENT_Entity_Kind) -> rl.Rectangle {
	return ENT__editor_ctx.source[ENT__ENTITY_SOURCE_INDEX[kind]],
}

@(private="file")
ENT__editor_ctx: struct {
	texture: rl.Texture2D,
	source: [dynamic]rl.Rectangle,
}

@(private="file", rodata)
ENT__ENTITY_SOURCE_INDEX := [ENT_Entity_Kind]int{
	.Player   = 0,
	.Tree     = 1,
	.Mushroom = 2,
}

}



//:internal
@(private="file") ENT__ENTITY_BEGIN_COLOR  :: rl.Color{255,   0, 255, 255}
@(private="file") ENT__ENTITY_END_COLOR    :: rl.Color{  0, 255, 255, 255}
*/
