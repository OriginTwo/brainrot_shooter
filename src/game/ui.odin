package game

import "core:math"
import "core:math/ease"
import "core:strings"

import rl "vendor:raylib"

/*
#assert(false, "REMOVE RAYLIB")

UI_Axis :: distinct int
UI_AXIS_X :: UI_Axis(0)
UI_AXIS_Y :: UI_Axis(1)
UI_AXIS_COUNT :: UI_Axis(2)

UI_Alignment :: enum {
	Begin,
	Center,
	End,
}

UI_Constraint_Variant_Kind :: enum {
	Pixel,
	Percent,
	Center,
}

UI_Constraint_Variant :: struct {
	kind: UI_Constraint_Variant_Kind,
	value: f32,
}

UI_Constraint :: struct {
	pos: [2]UI_Constraint_Variant,
	size: [2]UI_Constraint_Variant,
}

UI_Animation_Flag :: enum {
	X,
	Y,
	Width,
	Height,
	Color,
	Alpha,
}
UI_Animation_Flags :: distinct bit_set[UI_Animation_Flag; u8]

UI_Animation_Target_Kind :: enum {
	Pixel,
	Relative,
}

UI_Animation_Target :: struct {
	kind: UI_Animation_Target_Kind,
	range: Vec2f32,
}

UI_Animation :: struct {
	ease: ease.Ease,
	delay: f32,
	duration: f32,

	flags: UI_Animation_Flags,
	target_x: UI_Animation_Target,
	target_y: UI_Animation_Target,
	target_width: UI_Animation_Target,
	target_height: UI_Animation_Target,
	target_color: Vec3f32,
	target_alpha: Vec2f32,

	_is_playing: bool,
	_time: f32,
	_progress: f32,
}


UI_Box_Config :: struct {
	is_hidden: bool,
	color: rl.Color,
	show_anim: UI_Animation,
	hide_anim: UI_Animation,
}

UI_Box :: struct {
	next: ^UI_Box,
	prev: ^UI_Box,

	parent: ^UI_Box,
	next_sibling: ^UI_Box,
	prev_sibling: ^UI_Box,
	first_child: ^UI_Box,
	last_child: ^UI_Box,
	child_count: int,

	is_hidden: bool,
	was_hidden: bool,

	constraint: UI_Constraint,

	colors: [2]Vec4f32,
	color_progress: f32,

	text: string,
	text_pos: Vec2f32,
	text_size: Vec2f32,
	text_pivot: [2]UI_Alignment,
	text_constraint: [2]UI_Constraint_Variant,
	text_color: rl.Color,

	show_anim: UI_Animation,
	hide_anim: UI_Animation,

	pos: Vec2f32,
	size: Vec2f32,
	rect: rl.Rectangle,
}

UI_init :: proc(width, height: f32) {
	UI__ctx.root = UI_make_box({})
	UI__ctx.root.pos = {0.0, 0.0}
	UI__ctx.root.size = {width, height}
}

UI_uninit :: proc() {
	for b := UI__ctx.first_box; b != nil; {
		to_free := b
		b = b.next
		UI_destroy_box(to_free)
	}

	UI__ctx = {}
}

UI_set_font :: proc(font: rl.Font, size: f32) {
	UI__ctx.font = font
	UI__ctx.font_size = size
}

UI_resize :: proc(new_width, new_height: f32) {
	UI__ctx.root.size = {new_width, new_height}

	for b := UI__ctx.root.first_child; b != nil; b = b.next_sibling {
		UI__resize(b)
	}
}

UI_get_root :: proc() -> ^UI_Box {
	return UI__ctx.root
}

UI_update :: proc(mouse_pos: Vec2f32) {
	mouse_down := rl.IsMouseButtonDown(.LEFT) | rl.IsMouseButtonDown(.RIGHT) | rl.IsMouseButtonDown(.MIDDLE)
	for b := UI__ctx.root.first_child; b != nil; b = b.next_sibling {
		UI__update_box(b, mouse_pos, mouse_down)
	}

	UI__ctx.prev_active_box = UI__ctx.active_box
	UI__ctx.active_box = UI__ctx.next_active_box
	UI__ctx.next_active_box = nil

	UI__ctx.prev_hot_box = UI__ctx.hot_box
	UI__ctx.hot_box = UI__ctx.next_hot_box
	UI__ctx.next_hot_box = nil
}

UI_draw :: proc() {
	if UI__ctx.root.first_child != nil {
		UI__draw_box(UI__ctx.root.first_child)
	}
}

UI_make_box :: proc(config: UI_Box_Config) -> ^UI_Box {
	box := new(UI_Box)
	box.is_hidden = config.is_hidden
	box.was_hidden = config.is_hidden  // so the hide animation doesn't play
	box.colors[1] = rgba_from_rl_color(config.color)
	box.color_progress = 1.0
	box.show_anim = config.show_anim
	box.hide_anim = config.hide_anim

	if UI__ctx.last_box != nil {
		UI__ctx.last_box.next = box
		box.prev = UI__ctx.last_box
	}

	if UI__ctx.first_box == nil {
		UI__ctx.first_box = box
	}

	UI__ctx.last_box = box

	return box
}

UI_destroy_box :: proc(box: ^UI_Box) {
	if box.text != "" {
		delete(box.text)
	}

	free(box)
}

UI_set_hot_box :: proc(box: ^UI_Box) {
	UI__ctx.next_hot_box = box
}

UI_set_active_box :: proc(box: ^UI_Box) {
	UI__ctx.next_active_box = box
}

UI_is_box_hot :: proc(box: ^UI_Box) -> bool {
	return UI__ctx.hot_box == box
}

UI_is_box_just_hot :: proc(box: ^UI_Box) -> bool {
	return UI__ctx.hot_box == box && UI__ctx.prev_hot_box != box
}

UI_is_box_just_not_hot :: proc(box: ^UI_Box) -> bool {
	return UI__ctx.hot_box != box && UI__ctx.prev_hot_box == box
}

UI_is_box_active :: proc(box: ^UI_Box) -> bool {
	return UI__ctx.active_box == box
}

UI_is_box_just_active :: proc(box: ^UI_Box) -> bool {
	return UI__ctx.active_box == box && UI__ctx.prev_active_box != box
}

UI_is_box_just_not_active :: proc(box: ^UI_Box) -> bool {
	return UI__ctx.active_box != box && UI__ctx.prev_active_box == box
}

UI_box_add_text :: proc(
	box: ^UI_Box,
	text: string,
	pivot: [2]UI_Alignment,
	pos_constraint: [2]UI_Constraint_Variant,
	color: rl.Color,
) {
	if box.text != "" {
		delete(box.text)
	}

	box.text = strings.clone(text)
	box.text_size = rl.MeasureTextEx(
		UI__ctx.font,
		strings.clone_to_cstring(box.text, context.temp_allocator),
		UI__ctx.font_size,
		0.0,
	)
	box.text_pivot = pivot
	box.text_constraint = pos_constraint
	box.text_color = color

	UI__resolve_text_constraint(box)
}

UI_show_box :: proc(box: ^UI_Box) {
	box.is_hidden = false
	for b := box.first_child; b != nil; b = b.next_sibling {
		UI_show_box(b)
	}
}

UI_hide_box :: proc(box: ^UI_Box) {
	box.is_hidden = true
	for b := box.first_child; b != nil; b = b.next_sibling {
		UI_hide_box(b)
	}
}

UI_set_box_color :: proc(box: ^UI_Box, color: rl.Color, animated: bool) {
	box.colors[0] = box.colors[1]
	box.colors[1] = rgba_from_rl_color(color)
	box.color_progress = 0.0 if animated else 1.0
}

UI_add_child :: proc(parent, child: ^UI_Box, constraint: UI_Constraint) {
	if parent == nil || child == nil || parent == child {
		return
	}

	child.parent = parent

	if parent.is_hidden {
		child.is_hidden = true
	}

	parent.child_count += 1

	if parent.last_child != nil {
		parent.last_child.next_sibling = child
		child.prev_sibling = parent.last_child
	}

	if parent.first_child == nil {
		parent.first_child = child
	}

	parent.last_child = child

	child.constraint = constraint

	UI__resolve_box_constraint(child)
}

UI_play_animation :: proc(anim: ^UI_Animation) {
	anim._is_playing = true
	anim._time = 0.0
	anim._progress = 0.0
}

UI_stop_animation :: proc(anim: ^UI_Animation) {
	anim._is_playing = false
	anim._time = 0.0
	anim._progress = 0.0
}



//:internal
@(private="file")
UI__ctx: struct {
	first_box: ^UI_Box,
	last_box: ^UI_Box,

	root: ^UI_Box,

	hot_box: ^UI_Box,
	next_hot_box: ^UI_Box,
	prev_hot_box: ^UI_Box,
	active_box: ^UI_Box,
	next_active_box: ^UI_Box,
	prev_active_box: ^UI_Box,

	font: rl.Font,
	font_size: f32,
}

@(private="file")
UI__resize :: proc(box: ^UI_Box) {
	UI__resolve_box_constraint(box)
	for b := box.first_child; b != nil; b = b.next_sibling {
		UI__resize(b)
	}
}

@(private="file")
UI__update_box :: proc(box: ^UI_Box, mouse_pos: Vec2f32, mouse_down: bool) {
	if rl.CheckCollisionPointRec(mouse_pos, box.rect) &&
		!box.is_hidden &&
		(!mouse_down || UI__ctx.active_box != box)
	{
		UI__ctx.next_hot_box = box
	}

	delta := rl.GetFrameTime()
	animation_rate := 1.0 - math.pow(2.0, -30.0*delta)
	box.color_progress += (1.0 - box.color_progress)*animation_rate

	if !box.is_hidden && box.was_hidden {
		UI_play_animation(&box.show_anim)
		UI_stop_animation(&box.hide_anim)
	} else if box.is_hidden && !box.was_hidden {
		UI_stop_animation(&box.show_anim)
		UI_play_animation(&box.hide_anim)
	}

	UI__update_animation(box)

	box.was_hidden = box.is_hidden

	for child := box.first_child; child != nil; child = child.next_sibling {
		UI__update_box(child, mouse_pos, mouse_down)
	}
}

@(private="file")
UI__draw_box :: proc(box: ^UI_Box) {
	if box.is_hidden && !box.show_anim._is_playing && !box.hide_anim._is_playing {
		return
	}

	color := math.lerp(box.colors[0], box.colors[1], box.color_progress)

	anim_target_pos: Vec2f32
	anim_target_size: Vec2f32
	anim_target_color := color.rgb
	anim_color_progress: f32
	anim_target_alpha := color.a

	if box.show_anim._is_playing {
		target_pos: Vec2f32
		target_size: Vec2f32
		target_color: Vec3f32
		color_progress: f32
		target_alpha: f32 = 1.0
		UI__get_anim_value(
			box,
			&target_pos,
			&target_size,
			&target_color,
			&color_progress,
			&target_alpha,
			box.show_anim,
		)

		anim_target_pos += target_pos
		anim_target_size += target_size
		anim_target_color = math.lerp(anim_target_color, target_color, color_progress)
		anim_target_alpha *= target_alpha
	}

	if box.hide_anim._is_playing {
		target_pos: Vec2f32
		target_size: Vec2f32
		target_color: Vec3f32
		color_progress: f32
		target_alpha: f32 = 1.0
		UI__get_anim_value(
			box,
			&target_pos,
			&target_size,
			&target_color,
			&color_progress,
			&target_alpha,
			box.hide_anim,
		)

		anim_target_pos += target_pos
		anim_target_size += target_size
		anim_target_color = math.lerp(anim_target_color, target_color, color_progress)
		anim_target_alpha *= target_alpha
	}

	anim_target_alpha = clamp(anim_target_alpha, 0.0, 1.0)

	rect := box.rect
	rect.x += anim_target_pos.x
	rect.y += anim_target_pos.y
	rect.width += anim_target_size.x
	rect.height += anim_target_size.y

	rect_color := anim_target_color
	rl.DrawRectangleRec(rect, rl_color_from_rgba({rect_color.r, rect_color.g, rect_color.b, anim_target_alpha}))

	if box.text != "" {
		text_pos := box.text_pos + anim_target_pos

		switch box.text_pivot.x {
		case .Begin:
		case .Center: text_pos.x -= (box.text_size.x - anim_target_size.x)/2.0
		case .End:    text_pos.x -= box.text_size.x - anim_target_size.x
		}

		switch box.text_pivot.y {
		case .Begin:
		case .Center: text_pos.y -= (box.text_size.y - anim_target_size.y)/2.0
		case .End:    text_pos.y -= box.text_size.y - anim_target_size.y
		}

		text_pos.x = math.floor(text_pos.x)
		text_pos.y = math.floor(text_pos.y)

		rl.DrawTextEx(
			UI__ctx.font,
			strings.clone_to_cstring(box.text, context.temp_allocator),
			text_pos,
			UI__ctx.font_size,
			0.0,
			rl.Fade(box.text_color, anim_target_alpha),
		)
	}

	for child := box.first_child; child != nil; child = child.next_sibling {
		UI__draw_box(child)
	}
}

@(private="file")
UI__resolve_box_constraint :: proc(box: ^UI_Box) {
	parent := box.parent
	constraint := box.constraint

	for axis in 0..<UI_AXIS_COUNT {
		switch constraint.size[axis].kind {
		case .Pixel:   box.size[axis] = constraint.size[axis].value
		case .Percent: box.size[axis] = parent.size[axis]*constraint.size[axis].value
		case .Center:  // ignored for size
		}

		switch constraint.pos[axis].kind {
		case .Pixel:   box.pos[axis] = parent.pos[axis] + constraint.pos[axis].value
		case .Percent: box.pos[axis] = parent.pos[axis] + parent.size[axis]*constraint.pos[axis].value
		case .Center:  box.pos[axis] = parent.pos[axis] + (parent.size[axis] - box.size[axis])/2.0
		}
	}

	box.rect.x = box.pos.x
	box.rect.y = box.pos.y
	box.rect.width = box.size.x
	box.rect.height = box.size.y

	UI__resolve_text_constraint(box)
}

@(private="file")
UI__resolve_text_constraint :: proc(box: ^UI_Box) {
	constraint := box.text_constraint

	for axis in 0..<UI_AXIS_COUNT {
		switch constraint[axis].kind {
		case .Pixel:   box.text_pos[axis] = box.pos[axis] + constraint[axis].value
		case .Percent: box.text_pos[axis] = box.pos[axis] + box.size[axis]*constraint[axis].value
		case .Center:  box.text_pos[axis] = box.pos[axis] + (box.size[axis] - box.text_size[axis])/2.0
		}
	}
}

@(private="file")
UI__update_animation :: proc(box: ^UI_Box) {
	update_anim :: proc(anim: ^UI_Animation, delta: f32) {
		if !anim._is_playing {
			return
		}

		anim._time += delta
		if anim._time >= anim.delay {
			t := clamp((anim._time - anim.delay)/anim.duration, 0.0, 1.0)
			anim._progress = ease.ease(anim.ease, t)

			if anim._progress == 1.0 {
				anim._is_playing = false
			}
		}
	}

	delta := rl.GetFrameTime()

	update_anim(&box.show_anim, delta)
	update_anim(&box.hide_anim, delta)
}

@(private="file")
UI__get_anim_value :: proc(
	box: ^UI_Box,
	pos, size: ^Vec2f32,
	color: ^Vec3f32,
	color_progress: ^f32,
	alpha: ^f32,
	anim: UI_Animation,
) {
	if .X in anim.flags {
		range: Vec2f32

		switch anim.target_x.kind {
		case .Pixel:
			range[0] = anim.target_x.range[0]
			range[1] = anim.target_x.range[1]
		case .Relative:
			range[0] = box.size.x*anim.target_x.range[0]
			range[1] = box.size.x*anim.target_x.range[1]
		}

		pos.x = math.lerp(range[0], range[1], anim._progress)
	}

	if .Y in anim.flags {
		range: Vec2f32

		switch anim.target_y.kind {
		case .Pixel:
			range[0] = anim.target_y.range[0]
			range[1] = anim.target_y.range[1]
		case .Relative:
			range[0] = box.size.y*anim.target_y.range[0]
			range[1] = box.size.y*anim.target_y.range[1]
		}

		pos.y = math.lerp(range[0], range[1], anim._progress)
	}

	if .Width in anim.flags {
		range: Vec2f32

		switch anim.target_width.kind {
		case .Pixel:
			range[0] = anim.target_width.range[0]
			range[1] = anim.target_width.range[1]
		case .Relative:
			range[0] = -box.size.x*(1.0 - anim.target_width.range[0])
			range[1] = -box.size.x*(1.0 - anim.target_width.range[1])
		}

		size.x = math.lerp(range[0], range[1], anim._progress)
	}

	if .Height in anim.flags {
		range: Vec2f32

		switch anim.target_height.kind {
		case .Pixel:
			range[0] = anim.target_height.range[0]
			range[1] = anim.target_height.range[1]
		case .Relative:
			range[0] = -box.size.y*(1.0 - anim.target_height.range[0])
			range[1] = -box.size.y*(1.0 - anim.target_height.range[1])
		}

		size.y = math.lerp(range[0], range[1], anim._progress)
	}

	if .Color in anim.flags {
		color^ = anim.target_color
		color_progress^ = anim._progress
	} else {
		color_progress^ = 0.0
	}

	if .Alpha in anim.flags {
		alpha^ = math.lerp(anim.target_alpha[0], anim.target_alpha[1], anim._progress)
	} else {
		alpha^ = 1.0
	}
}
*/
