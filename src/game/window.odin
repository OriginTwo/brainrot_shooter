package game

import "core:log"

import sdl "vendor:sdl3"

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
		sdl.Quit()
		log.fatalf("WND: failed to create window: %s", sdl.GetError())
	}

	sdl.SetWindowPosition(WND__ctx.window, pos.x, pos.y)

	WND__ctx.width = int(size.x)
	WND__ctx.height = int(size.y)
}

WND_destroy :: proc() {
	sdl.DestroyWindow(WND__ctx.window)
	sdl.Quit()
}

WND_get_handle :: #force_inline proc() -> ^sdl.Window {
	return WND__ctx.window
}

WND_should_close :: #force_inline proc() -> bool {
	return WND__ctx.should_quit
}

WND_set_should_close :: #force_inline proc(val: bool) {
	WND__ctx.should_quit = val
}

WND_handle_event :: proc(ev: ^sdl.Event) {
	#partial switch ev.type {
	case .QUIT:
		WND__ctx.should_quit = true

	case .WINDOW_RESIZED:
		WND__ctx.width = int(ev.window.data1)
		WND__ctx.height = int(ev.window.data2)
	}
}



@(private="file")
WND__ctx: struct {
	window: ^sdl.Window,
	should_quit: bool,
	width: int,
	height: int,
}
