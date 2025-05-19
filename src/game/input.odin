package game

import sdl "vendor:sdl3"

INP_State :: struct {
	curr_key_down: #sparse [sdl.Scancode]bool,
	prev_key_down: #sparse [sdl.Scancode]bool,
	key_repeat: #sparse [sdl.Scancode]bool,

	curr_mouse_down: [INP_Mouse_Button]bool,
	prev_mouse_down: [INP_Mouse_Button]bool,

	mouse_pos: M_Vec2f32,
	mouse_delta: M_Vec2f32,
	mouse_wheel: M_Vec2f32,
}

INP_Mouse_Button :: enum {
	Left = sdl.BUTTON_LEFT,
	Middle = sdl.BUTTON_MIDDLE,
	Right = sdl.BUTTON_RIGHT,
	X1 = sdl.BUTTON_X1,
	X2 = sdl.BUTTON_X2,
}

INP_copy :: proc(dst: ^INP_State, src: INP_State) {
	for key in sdl.Scancode {
		dst.prev_key_down[key] = dst.curr_key_down[key]
		dst.curr_key_down[key] = src.curr_key_down[key]
	}

	for button in INP_Mouse_Button {
		dst.prev_mouse_down[button] = dst.curr_mouse_down[button]
		dst.curr_mouse_down[button] = src.curr_mouse_down[button]
	}

	dst.mouse_pos = src.mouse_pos
	dst.mouse_delta = src.mouse_delta
	dst.mouse_wheel = src.mouse_wheel
}

INP_handle_event :: proc(state: ^INP_State, ev: ^sdl.Event) {
	state.mouse_delta = {}
	state.mouse_wheel = {}

	#partial switch ev.type {
	case .KEY_DOWN, .KEY_UP:
		state.curr_key_down[ev.key.scancode] = ev.key.down
		state.key_repeat[ev.key.scancode] = ev.key.repeat

	case .MOUSE_BUTTON_DOWN, .MOUSE_BUTTON_UP:
		state.curr_mouse_down[INP_Mouse_Button(ev.button.button)] = ev.button.down

	case .MOUSE_MOTION:
		state.mouse_pos = {ev.motion.x, ev.motion.y}
		state.mouse_delta = {ev.motion.xrel, ev.motion.yrel}

	case .MOUSE_WHEEL:
		state.mouse_wheel = {ev.wheel.x, ev.wheel.y}
	}
}

INP_is_key_pressed :: proc(state: INP_State, key: sdl.Scancode) -> bool {
	return state.curr_key_down[key] && !state.prev_key_down[key]
}

INP_is_key_released :: proc(state: INP_State, key: sdl.Scancode) -> bool {
	return !state.curr_key_down[key] && state.prev_key_down[key]
}

INP_is_key_down :: proc(state: INP_State, key: sdl.Scancode) -> bool {
	return state.curr_key_down[key]
}

INP_is_key_repeat :: proc(state: INP_State, key: sdl.Scancode) -> bool {
	return state.key_repeat[key]
}

INP_is_mouse_pressed :: proc(state: INP_State, button: INP_Mouse_Button) -> bool {
	return state.curr_mouse_down[button] && !state.prev_mouse_down[button]
}

INP_is_mouse_released :: proc(state: INP_State, button: INP_Mouse_Button) -> bool {
	return !state.curr_mouse_down[button] && state.prev_mouse_down[button]
}

INP_is_mouse_down :: proc(state: INP_State, button: INP_Mouse_Button) -> bool {
	return state.curr_mouse_down[button]
}

INP_get_mouse_pos :: proc(state: INP_State) -> M_Vec2f32 {
	return state.mouse_pos
}

INP_get_mouse_delta :: proc(state: INP_State) -> M_Vec2f32 {
	return state.mouse_delta
}
