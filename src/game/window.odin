package game

import "core:log"

import sdl "vendor:sdl3"

import "lib:imgui/imgui_impl_sdl3"

WND_create :: proc(
	title: cstring,
	size: [2]i32,
	pos: [2]i32 = {sdl.WINDOWPOS_CENTERED, sdl.WINDOWPOS_CENTERED},
	flags: sdl.WindowFlags = {},
) {
	if !sdl.Init({.VIDEO}) {
		log.fatalf("WND: failed to initialize SDL: %s", sdl.GetError())
	}

	WND__ctx.window = sdl.CreateWindow(title, size.x, size.y, {.OPENGL} + flags)
	if WND__ctx.window == nil {
		log.fatalf("WND: failed to create window: %s", sdl.GetError())
	}

	sdl.SetWindowPosition(WND__ctx.window, pos.x, pos.y)

	sdl.GL_SetAttribute(.CONTEXT_PROFILE_MASK, i32(sdl.GL_CONTEXT_PROFILE_CORE))
	sdl.GL_SetAttribute(.CONTEXT_MAJOR_VERSION, 4)
	sdl.GL_SetAttribute(.CONTEXT_MAJOR_VERSION, 3)
	WND__ctx.gl_ctx = sdl.GL_CreateContext(WND__ctx.window)
	if WND__ctx.gl_ctx == nil {
		log.fatalf("WND: failed to create opengl context: %s", sdl.GetError())
	}

	sdl.GL_MakeCurrent(WND__ctx.window, WND__ctx.gl_ctx)
	sdl.GL_SetSwapInterval(1)
}

WND_destroy :: proc() {
	sdl.GL_DestroyContext(WND__ctx.gl_ctx)
	sdl.DestroyWindow(WND__ctx.window)
	sdl.Quit()
	WND__ctx = {}
}

WND_get_handle :: #force_inline proc() -> ^sdl.Window {
	return WND__ctx.window
}

WND_get_gl :: #force_inline proc() -> sdl.GLContext {
	return WND__ctx.gl_ctx
}

WND_should_close :: #force_inline proc() -> bool {
	return WND__ctx.should_quit
}

WND_set_should_close :: #force_inline proc(val: bool) {
	WND__ctx.should_quit = val
}

WND_handle_event :: proc(ev: ^sdl.Event) {
	when DEV_BUILD {
		imgui_impl_sdl3.ProcessEvent(ev)
	}

	#partial switch ev.type {
	case .QUIT:
		WND__ctx.should_quit = true
	}
}

WND_lock_mouse :: proc(val: bool) {
	_ = sdl.SetWindowRelativeMouseMode(WND__ctx.window, val)
	if WND__ctx.mouse_locked && !val {
		win_size: [2]i32
		sdl.GetWindowSize(WND__ctx.window, &win_size.x, &win_size.y)
		sdl.WarpMouseInWindow(WND__ctx.window, f32(win_size.x/2), f32(win_size.y/2))
	}
	WND__ctx.mouse_locked = val
}



@(private="file")
WND__ctx: struct {
	window: ^sdl.Window,
	gl_ctx: sdl.GLContext,
	should_quit: bool,
	mouse_locked: bool,
}
