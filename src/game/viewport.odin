package game

/*
#assert(false, "REMOVE RAYLIB")

VPRT_Viewport :: struct {
	fb: IMG_Framebuffer,
	og_window_width: f32,
	og_window_height: f32,
	inv_scale: f32,
}

VPRT_make :: proc(viewport_width, viewport_height, window_width, window_height: f32) -> VPRT_Viewport {
	v: VPRT_Viewport
	IMG_make_framebuffer(&v.fb, viewport_width, viewport_height)
	v.og_window_width = window_width
	v.og_window_height = window_height
	v.inv_scale = viewport_height/window_height
	return v
}

VPRT_destroy :: proc(viewport: ^VPRT_Viewport) {
	IMG_destroy_framebuffer(&viewport.fb)
}

VPRT_get_mouse_position :: proc(viewport: VPRT_Viewport) -> Vec2f32 {
	window_width := f32(rl.GetScreenWidth())
	window_height := f32(rl.GetScreenHeight())
	scale_x := window_width/viewport.og_window_width
	scale_y := window_height/viewport.og_window_height
	scale := min(scale_x, scale_y)
	scaled_width := viewport.og_window_width*scale
	scaled_height := viewport.og_window_height*scale
	return (rl.GetMousePosition() - {
		(window_width - scaled_width)/2.0,
		(window_height - scaled_height)/2.0,
	})*viewport.inv_scale/scale
}

VPRT_draw :: proc(viewport: VPRT_Viewport) {
	window_width := f32(rl.GetScreenWidth())
	window_height := f32(rl.GetScreenHeight())
	scale_x := window_width/viewport.og_window_width
	scale_y := window_height/viewport.og_window_height
	scale := min(scale_x, scale_y)
	scaled_width := viewport.og_window_width*scale
	scaled_height := viewport.og_window_height*scale
	rl.DrawTexturePro(
		viewport.target.texture,
		{0.0, f32(viewport.target.texture.height), f32(viewport.target.texture.width), -f32(viewport.target.texture.height)},
		{(window_width - scaled_width)/2.0, (window_height - scaled_height)/2.0, scaled_width, scaled_height},
		{0.0, 0.0},
		0.0,
		rl.WHITE,
	)
}
*/
