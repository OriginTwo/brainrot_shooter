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

	cam: GFX_Camera,
	player: _Player,

	enemy: _Enemy,
	tung_tung_tex: GFX_Texture,

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
	knockback_vel: M_Vec2f32,
	bob_t: f32,
}

@(private="file")
_player_init :: proc() {
	RES_load_texture(&_ctx.player.hand_texture, RES_ID_IMAGE_PLAYER_HAND_PNG)
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

	_ctx.player.desired_position.xz += _ctx.player.knockback_vel*delta
	{
		rate := 1 - math.pow(2.0, -15.0*delta)
		_ctx.player.knockback_vel += (M_Vec2f32{0.0, 0.0} - _ctx.player.knockback_vel)*rate
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

@(private="file")
_Enemy :: struct {
	position: M_Vec3f32,
	hp: int,
	hitbox_offset: f32,
	hitbox_radius: f32,
	attack_timer: TIME_Timer,
}

@(private="file")
_enemy_tick :: proc(e: ^_Enemy, delta: f32) {
	if !TIME_is_timer_timeout(e.attack_timer) {
		return
	}

	target := _ctx.player.position
	dir := linalg.normalize0(target - e.position)

	if linalg.length2(target - e.position) > e.hitbox_radius*e.hitbox_radius {
		e.position += dir*2.0*delta
	} else {
		_ctx.player.knockback_vel = dir.xz*10.0
		TIME_set_timer(&e.attack_timer, 1.0)
	}
}

@(private="file")
_enemy_draw :: proc(e: _Enemy) {
	GFX_draw_3d_billboard_texture(
		&_ctx.ren3d,
		_ctx.tung_tung_tex.texture,
		_ctx.tung_tung_tex.sampler,
		e.position + {0.0, e.hitbox_offset, 0.0},
		{e.hitbox_radius, e.hitbox_radius}*2.0,
		{0.0, 0.0, 91.0, 211.0},
		M_COLOR_WHITE,
		true,
	)
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

	_ctx.cam.position.y = 1.0
	_ctx.cam.fovy = math.PI/2.0

	_player_init()

	_ctx.enemy.hp = 10
	_ctx.enemy.hitbox_offset = 1.0
	_ctx.enemy.hitbox_radius = 0.8

	RES_load_texture(&_ctx.tung_tung_tex, RES_ID_IMAGE_TUNG_TUNG_PNG)
}

scn_game_uninit :: proc() {
	_player_uninit()

	sg.destroy_image(_ctx.tex)
	GFX_unload_font(&_ctx.font)
	GFX_destroy_2d_renderer(&_ctx.ren2d)
	GFX_destroy_3d_renderer(&_ctx.ren3d)
	GFX_destroy_post_fx_renderer(&_ctx.ren_fx)
	_ctx = {}
}

scn_game_tick :: proc(input: INP_State, delta: f32) {
	if INP_is_key_pressed(input, .ESCAPE) {
		WND_set_should_close(true)
	}

	if INP_is_key_pressed(input, .TAB) {
		@(static) lock_mouse := false
		lock_mouse = !lock_mouse
		WND_lock_mouse(lock_mouse)
	}

	_player_tick(input, delta)

	_enemy_tick(&_ctx.enemy, delta)

	if INP_is_mouse_pressed(input, .Left) {
		ray_origin := _ctx.cam.position
		ray_direction, _, _ := GFX_get_camera_forward_up_right(_ctx.cam)
		ray_sphere_vector := (_ctx.enemy.position + {0.0, _ctx.enemy.hitbox_offset, 0.0}) - ray_origin
		dot := linalg.dot(ray_sphere_vector, ray_direction)
		distance := linalg.length(ray_sphere_vector)
		d := (_ctx.enemy.hitbox_radius*_ctx.enemy.hitbox_radius - (distance*distance - dot*dot))
		hit := d >= 0.0
		if hit && distance <= 20.0 {
			_ctx.enemy.hp -= 1
			if _ctx.enemy.hp <= 0 {
				// fmt.println("enemy dead")
			}
			fmt.println("hit! now enemy has", _ctx.enemy.hp, "hp")
		}
	}
}

scn_game_draw :: proc(alpha: f32) {
	GFX_begin_frame()
	GFX_clear_background(M_FCOLOR_BLACK)

	GFX_begin_3d_renderer(&_ctx.ren3d, _ctx.cam)

	GFX_draw_3d_rect(
		&_ctx.ren3d,
		{-10.0, 0.0, -10.0}, {0.0, 1.0, 0.0}, {127, 127, 127, 255},
		{ 10.0, 0.0, -10.0}, {0.0, 1.0, 0.0}, {127, 127, 127, 255},
		{ 10.0, 0.0,  10.0}, {0.0, 1.0, 0.0}, {127, 127, 127, 255},
		{-10.0, 0.0,  10.0}, {0.0, 1.0, 0.0}, {127, 127, 127, 255},
	)

	_enemy_draw(_ctx.enemy)

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

	when DEV_BUILD {
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
	}

	GFX_end_frame()

	sg.commit()
}
