package game

import "core:os"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:math/ease"

import sdl "vendor:sdl3"

import im "lib:imgui"
import sg "lib:sokol/gfx"

SCN_GAME_HANDLE :: SCN_Handle(#hash("game", "fnv64a"))
SCN_GAME_CALLBACKS :: SCN_Callbacks{
	scn_game_init,
	scn_game_uninit,
	scn_game_tick,
	scn_game_draw,
}

@(private="file")
_ctx: struct {
	ren2d: GFX_2D_Renderer,
	ren3d: GFX_3D_Renderer,
	ren_fx: GFX_Post_FX_Renderer,
	font: GFX_Font,
	tex: sg.Image,
	smp: sg.Sampler,

	level: LVL_Level,

	cam: GFX_Camera,
	player: _Player,

	disable_bloom: bool,
}

@(private="file") _PLAYER_WIDTH :: 1.0
@(private="file") _PLAYER_HEIGHT :: 1.6
@(private="file") _PLAYER_SPEED :: 8.0
@(private="file") _PLAYER_WALL_CHECK_RADIUS :: _PLAYER_WIDTH*2.0
@(private="file") _PLAYER_LAND_ANIM_DURATION :: 0.4
@(private="file") _PLAYER_COYOTE_TIME :: 0.1

@(private="file")
_Player :: struct {
	hand_texture: GFX_Texture,

	desired_position: M_Vec3f32,
	position: M_Vec3f32,
	velocity_y: f32,
	prev_floor_y: f32,
	bob_t: f32,
	hand_bob_up_t: f32,
	hand_bob_down_t: f32,
	land_time: f32,
	play_land_anim: bool,
	land_anim_max_offset: f32,
	air_time: f32,
	jump_left: u8,
}

@(private="file")
_player_init :: proc() {
	ASST_load_texture(&_ctx.player.hand_texture, IMAGE_PLAYER_HAND_PNG)
}

@(private="file")
_player_uninit :: proc() {
	GFX_unload_texture(&_ctx.player.hand_texture)
}

@(private="file")
_player_tick :: proc(input: INP_State, delta: f32) {
	mouse_delta := INP_get_mouse_delta(input)

	_ctx.cam.pitch += mouse_delta.y*DEFAULT_MOUSE_SENSITIVITY
	_ctx.cam.yaw += mouse_delta.x*DEFAULT_MOUSE_SENSITIVITY

	_ctx.cam.pitch = clamp(_ctx.cam.pitch, -89.0, 89.0)
	_ctx.cam.yaw = math.mod(_ctx.cam.yaw, 360.0)

	forward, _, right := GFX_get_camera_forward_up_right(_ctx.cam)
	move_vec: M_Vec2f32
	if INP_is_key_down(input, .W) {move_vec -= forward.xz}
	if INP_is_key_down(input, .S) {move_vec += forward.xz}
	if INP_is_key_down(input, .D) {move_vec += right.xz}
	if INP_is_key_down(input, .A) {move_vec -= right.xz}
	move_vec = linalg.normalize0(move_vec)
	_ctx.player.desired_position.xz += move_vec*_PLAYER_SPEED*delta

	// wall collision
	min_chunk_coord, max_chunk_coord := LVL_get_chunk_coord_range(
		_ctx.player.position.xz - _PLAYER_WALL_CHECK_RADIUS/2.0,
		_PLAYER_WALL_CHECK_RADIUS,
	)
	for chunk_coord_y in min_chunk_coord.y..<max_chunk_coord.y {
		for chunk_coord_x in min_chunk_coord.x..<max_chunk_coord.x {
			chunk, chunk_ok := _ctx.level.chunks[{chunk_coord_x, chunk_coord_y}]
			if !chunk_ok {
				continue
			}

			for wall_index in chunk.wall_indices {
				wall := _ctx.level.walls[wall_index]
				relative_wall_height := (wall.y + wall.height) - _ctx.player.position.y
				if (0.0 <= relative_wall_height && relative_wall_height <= 0.55) || // 0.55 for rounding error
					wall.y + wall.height <= _ctx.player.position.y ||               // top of the wall is below player's feet
					wall.y >= _ctx.player.position.y + _PLAYER_HEIGHT               // bottom of the wall is above player's head
				{
					continue
				}

				player_range := M_Range2f32{
					min = _ctx.player.desired_position.xz - _PLAYER_WIDTH/2.0,
					max = _ctx.player.desired_position.xz + _PLAYER_WIDTH/2.0,
				}
				wall_range := M_Range2f32{wall.p1, wall.p2}
				overlap_dimension := M_range2f32_dimension(M_range2f32_intersect(player_range, wall_range))
				is_x_in_range := overlap_dimension.x > 0.0
				is_z_in_range := overlap_dimension.y > 0.0

				switch wall.facing {
				case .North:
					dist_y := wall.p1.y - _ctx.player.desired_position.z

					if is_x_in_range && (0.0 < dist_y && dist_y < _PLAYER_WIDTH/2.0) {
						_ctx.player.desired_position.z = wall.p1.y - _PLAYER_WIDTH/2.0
					}

				case .East:
					dist_x := wall.p1.x - _ctx.player.desired_position.x

					if is_z_in_range && (-_PLAYER_WIDTH/2.0 < dist_x && dist_x < 0.0) {
						_ctx.player.desired_position.x = wall.p1.x + _PLAYER_WIDTH/2.0
					}

				case .South:
					dist_y := wall.p1.y - _ctx.player.desired_position.z

					if is_x_in_range && (-_PLAYER_WIDTH/2.0 < dist_y && dist_y < 0.0) {
						_ctx.player.desired_position.z = wall.p1.y + _PLAYER_WIDTH/2.0
					}

				case .West:
					dist_x := wall.p1.x - _ctx.player.desired_position.x

					if is_z_in_range && (0.0 < dist_x && dist_x < _PLAYER_WIDTH/2.0) {
						_ctx.player.desired_position.x = wall.p1.x - _PLAYER_WIDTH/2.0
					}
				}
			}
		}
	}

	// sector collision
	{
		// should always be valid
		chunk_coord := LVL_get_chunk_coord(_ctx.player.position.xz)
		chunk := _ctx.level.chunks[chunk_coord]

		highest_floor_y := -math.INF_F32
		lowest_ceiling_y := math.INF_F32

		for sector_index in chunk.sector_indices {
			sector := _ctx.level.sectors[sector_index]

			player_range := M_Range2f32{
				min = _ctx.player.desired_position.xz - _PLAYER_WIDTH/2.0,
				max = _ctx.player.desired_position.xz + _PLAYER_WIDTH/2.0,
			}

			sector_range := M_Range2f32{
				min = sector.position,
				max = sector.position + sector.size,
			}

			overlap_amount := M_range2f32_dimension(M_range2f32_intersect(player_range, sector_range))

			if overlap_amount.x*overlap_amount.y > 0.0 {
				if sector.floor_y > highest_floor_y {
					highest_floor_y = sector.floor_y
				}
				if sector.ceiling_y < lowest_ceiling_y {
					lowest_ceiling_y = sector.ceiling_y
				}
			}
		}

		if _ctx.player.desired_position.y > highest_floor_y {
			_ctx.player.land_time = 0.0
			_ctx.player.play_land_anim = false

			_ctx.player.air_time += delta

			if _ctx.player.velocity_y >= 0.0 {
				_ctx.player.velocity_y -= 65.0*delta
			} else {
				_ctx.player.velocity_y -= 100.0*delta
			}
		} else {
			if _ctx.player.velocity_y < -20.0 {
				_ctx.player.play_land_anim = true
				_ctx.player.land_anim_max_offset = min(abs(_ctx.player.velocity_y)/80.0, 0.8)
			}

			_ctx.player.land_time += delta

			_ctx.player.air_time = 0.0
			_ctx.player.jump_left = 1

			_ctx.player.velocity_y = 0.0
			_ctx.player.desired_position.y = highest_floor_y
		}

		if INP_is_key_pressed(input, .SPACE) && _ctx.player.air_time < _PLAYER_COYOTE_TIME && _ctx.player.jump_left > 0 {
			_ctx.player.jump_left -= 1
			_ctx.player.velocity_y = 16.0
		}

		_ctx.player.prev_floor_y = highest_floor_y
		_ctx.player.desired_position.y += _ctx.player.velocity_y*delta
		if _ctx.player.desired_position.y + _PLAYER_HEIGHT > lowest_ceiling_y {
			_ctx.player.desired_position.y = lowest_ceiling_y - _PLAYER_HEIGHT
			_ctx.player.velocity_y = 0.0
		}
	}

	_ctx.player.position += (_ctx.player.desired_position - _ctx.player.position)*20.0*delta
	_ctx.cam.position = _ctx.player.position + {0.0, _PLAYER_HEIGHT, 0.0}

	if move_vec != {} {
		_ctx.player.bob_t += delta*4.0
	} else {
		_ctx.player.bob_t -= delta*4.0
	}
	_ctx.player.bob_t = clamp(_ctx.player.bob_t, 0.0, 1.0)
	_ctx.cam.offset.y = 0.1*_ctx.player.bob_t*math.sin(f32(TIME_now())*14.0)

	if _ctx.player.velocity_y > 0.0 {
		_ctx.player.hand_bob_up_t += delta*2.0
		_ctx.player.hand_bob_down_t -= delta*2.0
	} else if _ctx.player.velocity_y < -1.0 {
		_ctx.player.hand_bob_up_t -= delta*2.0
		_ctx.player.hand_bob_down_t += delta*2.0
	} else {
		_ctx.player.hand_bob_up_t -= delta*2.0
		_ctx.player.hand_bob_down_t -= delta*2.0
	}
	_ctx.player.hand_bob_up_t = clamp(_ctx.player.hand_bob_up_t, 0.0, 1.0)
	_ctx.player.hand_bob_down_t = clamp(_ctx.player.hand_bob_down_t, 0.0, 1.0)

	if _ctx.player.play_land_anim {
		if _ctx.player.land_time <= _PLAYER_LAND_ANIM_DURATION/2.0 {
			t := _ctx.player.land_time
			_ctx.cam.offset.y -= ease.cubic_out(t/(_PLAYER_LAND_ANIM_DURATION/2.0))*_ctx.player.land_anim_max_offset
		} else if _ctx.player.land_time <= _PLAYER_LAND_ANIM_DURATION {
			t := _PLAYER_LAND_ANIM_DURATION/2.0 - (_ctx.player.land_time - _PLAYER_LAND_ANIM_DURATION/2.0)
			_ctx.cam.offset.y -= ease.cubic_in(t/(_PLAYER_LAND_ANIM_DURATION/2.0))*_ctx.player.land_anim_max_offset
		} else {
			_ctx.player.play_land_anim = false
		}
	}
}

@(private="file")
_player_draw_hud :: proc() {
	window_width: f32
	window_height: f32
	{
		w: i32
		h: i32
		sdl.GetWindowSize(WND_get_handle(), &w, &h)
		window_width = f32(w)
		window_height = f32(h)
	}

	scale_x := window_width/WINDOW_WIDTH
	scale_y := window_height/WINDOW_HEIGHT

	// hand
	{
		rect: M_Rect
		rect.width = 330.0*scale_x
		rect.height = 330.0*scale_y
		rect.x = window_width*3.0/4.0 - rect.width/3.0
		rect.y = window_height - rect.height*2.0/3.0
		// move bob
		rect.x += 36.0*_ctx.player.bob_t*math.cos(f32(TIME_now())*6.0)
		rect.y += abs(24.0*_ctx.player.bob_t*math.sin(f32(TIME_now())*6.0))
		// in-air bob
		rect.y += 50.0*ease.back_out(_ctx.player.hand_bob_up_t)
		rect.y -= 50.0*ease.back_out(_ctx.player.hand_bob_down_t)
		// idle bob
		rect.y += 6.0*math.sin(f32(TIME_now()))
		GFX_draw_2d_texture(&_ctx.ren2d, _ctx.player.hand_texture, {0.0, 0.0, 48.0, 48.0}, rect, M_COLOR_WHITE)
	}

	// crosshair
	{
		center := M_Vec2f32{window_width, window_height}/2.0

		// top
		GFX_draw_2d_rect(
			&_ctx.ren2d,
			{
				center.x - DEFAULT_CROSSHAIR_THICKNESS/2.0,
				center.y - DEFAULT_CROSSHAIR_LENGTH - DEFAULT_CROSSHAIR_CENTER_GAP,
				DEFAULT_CROSSHAIR_THICKNESS,
				DEFAULT_CROSSHAIR_LENGTH,
			},
			DEFAULT_CROSSHAIR_COLOR,
		)

		// bottom
		GFX_draw_2d_rect(
			&_ctx.ren2d,
			{
				center.x - DEFAULT_CROSSHAIR_THICKNESS/2.0,
				center.y + DEFAULT_CROSSHAIR_CENTER_GAP,
				DEFAULT_CROSSHAIR_THICKNESS,
				DEFAULT_CROSSHAIR_LENGTH,
			},
			DEFAULT_CROSSHAIR_COLOR,
		)

		// left
		GFX_draw_2d_rect(
			&_ctx.ren2d,
			{
				center.x - DEFAULT_CROSSHAIR_LENGTH - DEFAULT_CROSSHAIR_CENTER_GAP,
				center.y - DEFAULT_CROSSHAIR_THICKNESS/2.0,
				DEFAULT_CROSSHAIR_LENGTH,
				DEFAULT_CROSSHAIR_THICKNESS,
			},
			DEFAULT_CROSSHAIR_COLOR,
		)

		// right
		GFX_draw_2d_rect(
			&_ctx.ren2d,
			{
				center.x + DEFAULT_CROSSHAIR_CENTER_GAP,
				center.y - DEFAULT_CROSSHAIR_THICKNESS/2.0,
				DEFAULT_CROSSHAIR_LENGTH,
				DEFAULT_CROSSHAIR_THICKNESS,
			},
			DEFAULT_CROSSHAIR_COLOR,
		)
	}
}

scn_game_init :: proc() {
	GFX_create_2d_renderer(&_ctx.ren2d)
	GFX_create_3d_renderer(&_ctx.ren3d, VIEWPORT_WIDTH, VIEWPORT_HEIGHT)
	GFX_create_post_fx_renderer(&_ctx.ren_fx, VIEWPORT_WIDTH, VIEWPORT_HEIGHT)

	{
		img: GFX_Image
		GFX_load_image_from_file(&img, "res/font/font_big.png")
		GFX_load_font_from_image(&_ctx.font, img)
		GFX_unload_image(&img)
	}

	{
		img: GFX_Image
		GFX_load_image_from_file(&img, "res/image/HBD_2021.png")
		_ctx.tex = sg.make_image({
			type = ._2D,
			width = i32(img.width),
			height = i32(img.height),
			num_slices = 1,
			num_mipmaps = 1,
			usage = .IMMUTABLE,
			pixel_format = .RGBA8,
			sample_count = 1,
			data = {
				subimage = {0 = {0 = {
					ptr = raw_data(img.pixels),
					size = len(img.pixels)*size_of(img.pixels[0]),
				}}},
			},
		})
		_ctx.smp = GFX_get_default_2d_sampler(_ctx.ren2d)
		GFX_unload_image(&img)
	}

	{
		LVL_init(&_ctx.level)

		data, data_ok := os.read_entire_file("exported_level.lvl")
		if data_ok {
			ser: SER_Serializer
			SER_init_reader(&ser, data)
			LVL_serialize(&_ctx.level, &ser)
			delete(data)
		}
	}

	_ctx.cam.position.y = 1.0
	_ctx.cam.fovy = math.PI/2.0

	_player_init()
}

scn_game_uninit :: proc() {
	_player_uninit()

	LVL_uninit(&_ctx.level)

	sg.destroy_image(_ctx.tex)
	GFX_unload_font(&_ctx.font)
	GFX_destroy_2d_renderer(&_ctx.ren2d)
	GFX_destroy_3d_renderer(&_ctx.ren3d)
	GFX_destroy_post_fx_renderer(&_ctx.ren_fx)
	_ctx = {}
}

scn_game_tick :: proc(input: INP_State, delta: f32) {
	when DEV_BUILD {
		if INP_is_key_pressed(input, .F1) {
			WND_lock_mouse(false)
			SCN_change(SCN_EDITOR_HANDLE)
		}
	}

	if INP_is_key_pressed(input, .ESCAPE) {
		WND_set_should_close(true)
	}

	if INP_is_key_pressed(input, .TAB) {
		@(static) lock_mouse := false
		lock_mouse = !lock_mouse
		WND_lock_mouse(lock_mouse)
	}

	_player_tick(input, delta)
}

scn_game_draw :: proc(alpha: f32) {
	GFX_begin_frame()
	GFX_clear_background(M_FCOLOR_BLACK)

	GFX_begin_3d_renderer(&_ctx.ren3d, _ctx.cam)

	LVL_draw(
		&_ctx.level,
		&_ctx.ren3d,
		{_ctx.cam.position.x, _ctx.cam.position.z},
	)

	GFX_add_3d_light(&_ctx.ren3d, {
		position = {-3.0, 1.5, -2.0},
		intensity = 7.0,
		radius = 9.0,
		color = {1.0, 0.4, 0.4},
		falloff = 1.0,
	})

	GFX_add_3d_light(&_ctx.ren3d, {
		position = {3.0, 1.5, -2.0},
		intensity = 7.0,
		radius = 9.0,
		color = {0.4, 0.4, 1.0},
		falloff = 1.0,
	})

	GFX_add_3d_light(&_ctx.ren3d, {
		position = _ctx.cam.position,
		intensity = 2.0,
		radius = 6.0,
		color = {1.0, 1.0, 1.0},
		falloff = 2.0,
	})

	GFX_end_3d_renderer(&_ctx.ren3d)

	GFX_begin_2d_renderer(&_ctx.ren2d)

	win_size: [2]i32
	sdl.GetWindowSize(WND_get_handle(), &win_size.x, &win_size.y)

	if _ctx.disable_bloom {
		w := f32(sg.query_image_width(_ctx.ren3d.color_texture))
		h := f32(sg.query_image_height(_ctx.ren3d.color_texture))
		GFX_draw_2d_texture(
			&_ctx.ren2d,
			{_ctx.ren3d.color_texture, GFX_get_default_2d_sampler(_ctx.ren2d)},
			{0.0, h, w, -h},
			{0.0, 0.0, f32(win_size.x), f32(win_size.y)},
			M_COLOR_WHITE,
		)
	} else {
		GFX_draw_post_fx(&_ctx.ren_fx, &_ctx.ren2d, &_ctx.ren3d)
	}

	GFX_set_2d_layer(&_ctx.ren2d, 10)

	GFX_draw_2d_string(
		&_ctx.ren2d,
		_ctx.font,
		"Hello World!",
		{200.0, 200.0},
		M_urgba_from_frgba(M_frgba_from_hsva({math.sin(f32(TIME_now()))*0.5 + 0.5, 1.0, 1.0, 1.0})),
		3.0,
	)

	_player_draw_hud()

	GFX_end_2d_renderer(&_ctx.ren2d)

	im.SetNextWindowSize({200.0, 400.0}, .Once)
	im.Begin("Debug")
	{
		im.SliderFloat("pos_x", &_ctx.cam.position.x, -10.0, 10.0)
		im.SliderFloat("pos_y", &_ctx.cam.position.y, -10.0, 10.0)
		im.SliderFloat("pos_z", &_ctx.cam.position.z, -10.0, 10.0)
		im.SliderFloat("pitch", &_ctx.cam.pitch, -89.0, 89.0)
		im.SliderFloat("yaw", &_ctx.cam.yaw, 0.0, 360.0)
		im.SliderFloat("roll", &_ctx.cam.roll, -30.0, 30.0)
		im.Checkbox("disable bloom", &_ctx.disable_bloom)
	}
	im.End()

	GFX_end_frame()

	sg.commit()
}
