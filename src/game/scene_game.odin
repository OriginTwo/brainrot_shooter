package game

import "core:os"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:math/ease"
import "core:math/rand"

import sdl "vendor:sdl3"
import ma "vendor:miniaudio"

import sg "lib:sokol/gfx"

SCN_GAME_HANDLE :: SCN_Handle(#hash("game", "fnv64a"))
SCN_GAME_CALLBACKS :: SCN_Callbacks{
	scn_game_init,
	scn_game_uninit,
	scn_game_tick,
	scn_game_draw,
}

@(private="file") _UI_TEXT_SCALE :: 3.0
@(private="file") _UI_PADDING :: 8.0
@(private="file") _DIFFICULTY_INCREASE_INTERVAL :: 30.0

@(private="file")
_ctx: struct {
	ren2d: GFX_2D_Renderer,
	ren3d: GFX_3D_Renderer,
	ren_fx: GFX_Post_FX_Renderer,
	font: GFX_Font,

	is_paused: bool,

	cam: GFX_Camera,
	player: _Player,

	max_enemies: int,
	max_enemies_timer: TIME_Timer,

	kill: [_Enemy_Kind]int,

	enemies: [dynamic]_Enemy,
	pickups: [dynamic]_Pickup,

	hp_pickup_tex: GFX_Texture,
	ammo_pickup_tex: GFX_Texture,

	game_start_sound: AUD_Sound,
	player_footstep_sound: AUD_Sound,
	player_hit_sound: AUD_Sound,
	player_shoot_sound: AUD_Sound,
	player_shoot_no_ammo_sound: AUD_Sound,
	enemy_hit_sound: AUD_Sound,
	pickup_sound: AUD_Sound,

	hovered_sound: AUD_Sound,

	music: AUD_Music,

	enemy_hit_particle_emitter: PART_Emitter,
}

@(private="file")
_Button :: struct {
	text: string,
	hot_t: f32,
	was_hovered: bool,
	click_proc: proc(),
}

@(private="file")
_buttons := [?]_Button{
	{
		text = "Resume",
		click_proc = _resume_button_proc,
	},
	{
		text = "Surrender",
		click_proc = _game_over,
	},
}

@(private="file")
_resume_button_proc :: proc() {
	_ctx.is_paused = false
	WND_lock_mouse(true)
}


@(private="file") _PLAYER_MAX_HP :: 100
@(private="file") _PLAYER_MAX_AMMO :: 999
@(private="file") _PLAYER_WIDTH :: 1.0
@(private="file") _PLAYER_HEIGHT :: 1.6
@(private="file") _PLAYER_SPEED :: 6.0
@(private="file") _PLAYER_SHOT_DISTANCE :: 30.0
@(private="file") _PLAYER_SHOOT_ANIM_TICK_DURATION :: 3
@(private="file") _PLAYER_FOOTSTEP_SOUND_INTERVAL :: 0.4
@(private="file") _PLAYER_MINIMAP_PIXELS_PER_UNIT :: 2.5

@(private="file")
_Player :: struct {
	hand_texture: GFX_Texture,
	hand_shoot_texture: GFX_Texture,

	hp: int,
	ammo: int,

	desired_position: M_Vec3f32,
	position: M_Vec3f32,
	knockback_vel: M_Vec2f32,
	bob_t: f32,

	tick_since_last_hit: u32,
	tick_since_last_shot: u32,
	tick_since_last_no_ammo_shot: u32,

	was_moving: bool,
	footstep_sound_timer: TIME_Timer,
}

@(private="file")
_player_init :: proc() {
	p := &_ctx.player

	RES_load_texture(&p.hand_texture, RES_ID_IMAGE_PLAYER_HAND_PNG)
	RES_load_texture(&p.hand_shoot_texture, RES_ID_IMAGE_PLAYER_HAND_SHOOT_PNG)

	p.hp = _PLAYER_MAX_HP
	p.ammo = 30

	p.tick_since_last_shot = _PLAYER_SHOOT_ANIM_TICK_DURATION
}

@(private="file")
_player_uninit :: proc() {
	p := &_ctx.player

	GFX_unload_texture(&p.hand_texture)
	GFX_unload_texture(&p.hand_shoot_texture)
	p^ = {}
}

@(private="file")
_player_tick :: proc(input: INP_State, delta: f32) {
	p := &_ctx.player

	p.tick_since_last_hit += 1
	p.tick_since_last_shot += 1
	p.tick_since_last_no_ammo_shot += 1

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
	p.desired_position.xz += move_vec*_PLAYER_SPEED*delta

	p.desired_position.xz += p.knockback_vel*delta
	{
		rate := 1 - math.pow(2.0, -15.0*delta)
		p.knockback_vel += (M_Vec2f32{0.0, 0.0} - p.knockback_vel)*rate
	}

	p.position += (p.desired_position - p.position)*20.0*delta
	_ctx.cam.position = p.position + {0.0, _PLAYER_HEIGHT, 0.0}

	is_moving := move_vec != {}

	if is_moving {
		p.bob_t += delta*4.0
		if !p.was_moving {
			TIME_set_timer(&p.footstep_sound_timer, _PLAYER_FOOTSTEP_SOUND_INTERVAL)
		}
		if TIME_is_timer_timeout(p.footstep_sound_timer) {
			AUD_play_sound(&_ctx.player_footstep_sound)
			TIME_set_timer(&p.footstep_sound_timer, _PLAYER_FOOTSTEP_SOUND_INTERVAL)
		}
	} else {
		p.bob_t -= delta*4.0
	}
	p.bob_t = clamp(p.bob_t, 0.0, 1.0)
	_ctx.cam.offset.y = 0.1*p.bob_t*math.sin(f32(TIME_now())*14.0)

	p.was_moving = is_moving
}

@(private="file")
_player_draw_hud :: proc() {
	p := &_ctx.player

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
	scale := min(scale_x, scale_y)

	// hand
	{
		rect: M_Rect
		rect.width = 350.0*scale_x
		rect.height = 400.0*scale_y
		rect.x = window_width*3.0/4.0 - rect.width/3.0
		rect.y = window_height - rect.height*2.0/3.0
		// move bob
		rect.x += 36.0*p.bob_t*math.cos(f32(TIME_now())*6.0)
		rect.y += abs(24.0*p.bob_t*math.sin(f32(TIME_now())*6.0))
		// idle bob
		rect.y += 6.0*math.sin(f32(TIME_now()))

		texture := (
			p.hand_texture if p.tick_since_last_shot > _PLAYER_SHOOT_ANIM_TICK_DURATION
			else p.hand_shoot_texture
		)

		GFX_draw_2d_texture(&_ctx.ren2d, texture, {0.0, 0.0, 174.0, 203.0}, rect, M_COLOR_WHITE)
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

	// minimap
	{
		rect := M_Rect{16.0, 16.0, 160.0*scale, 160.0*scale}
		rect_center := M_Vec2f32{rect.x + rect.width/2.0, rect.y + rect.height/2.0}

		GFX_draw_2d_rect(
			&_ctx.ren2d,
			rect,
			{0, 0, 0, 127},
		)

		GFX_draw_2d_rect_line(
			&_ctx.ren2d,
			rect,
			M_COLOR_WHITE,
			4.0*scale,
		)

		GFX_draw_2d_triangle(
			&_ctx.ren2d,
			{rect_center.x, rect_center.y - 8.0*scale},             M_COLOR_WHITE,
			{rect_center.x - 5.0*scale, rect_center.y + 8.0*scale}, M_COLOR_WHITE,
			{rect_center.x + 5.0*scale, rect_center.y + 8.0*scale}, M_COLOR_WHITE,
		)

		dot_size := 6.0*scale

		for enemy in _ctx.enemies {
			rel_pos := (p.position.xz - enemy.position.xz)*_PLAYER_MINIMAP_PIXELS_PER_UNIT
			dist_sqr := linalg.length2(rel_pos)
			if dist_sqr >= (rect.width/2.0)*(rect.width/2.0) {
				continue
			}

			rel_pos = (
				linalg.matrix3_rotate_f32(
					-_ctx.cam.yaw*math.RAD_PER_DEG,
					{0.0, 0.0, 1.0},
				)*M_Vec3f32{rel_pos.x, rel_pos.y, 1.0}
			).xy

			GFX_draw_2d_rect(
				&_ctx.ren2d,
				{rect_center.x - rel_pos.x - dot_size/2.0, rect_center.y - rel_pos.y - dot_size/2.0, dot_size, dot_size},
				M_COLOR_RED,
			)
		}

		for pickup in _ctx.pickups {
			rel_pos := (p.position.xz - pickup.position.xz)*_PLAYER_MINIMAP_PIXELS_PER_UNIT
			dist_sqr := linalg.length2(rel_pos)
			if dist_sqr >= (rect.width/2.0)*(rect.width/2.0) {
				continue
			}

			rel_pos = (
				linalg.matrix3_rotate_f32(
					-_ctx.cam.yaw*math.RAD_PER_DEG,
					{0.0, 0.0, 1.0},
				)*M_Vec3f32{rel_pos.x, rel_pos.y, 1.0}
			).xy

			GFX_draw_2d_rect(
				&_ctx.ren2d,
				{rect_center.x - rel_pos.x - dot_size/2.0, rect_center.y - rel_pos.y - dot_size/2.0, dot_size, dot_size},
				M_COLOR_CYAN,
			)
		}
	}

	// text
	{
		TEXT_SCALE :: 3.0

		font_height := f32(_ctx.font.base_size)*TEXT_SCALE*scale
		line_height := font_height*0.75
		y := window_height - font_height

		GFX_draw_2d_string(
			&_ctx.ren2d,
			_ctx.font,
			fmt.tprintf("AMMO: %d", p.ammo),
			{8.0*scale, y},
			M_COLOR_RED if _ctx.player.tick_since_last_no_ammo_shot < 6 else M_COLOR_WHITE,
			TEXT_SCALE*scale,
		)

		y -= line_height

		GFX_draw_2d_string(
			&_ctx.ren2d,
			_ctx.font,
			fmt.tprintf("HP: %d", p.hp),
			{8.0*scale, y},
			M_COLOR_RED if _ctx.player.tick_since_last_hit < 6 else M_COLOR_WHITE,
			TEXT_SCALE*scale,
		)
	}
}

@(private="file")
_Enemy_Kind :: enum {
	Tung_Tung_Sahur,
	Trallalero_Trallalla,
	Brr_Brr_Patapim,
	Chimpanzini_Bananini,
	Assassino_Cappuccino,
}

@(private="file")
_Enemy :: struct {
	kind: _Enemy_Kind,
	hp: int,
	position: M_Vec3f32,
	attack_timer: TIME_Timer,
}

@(private="file")
_ENEMY_DATABASE := [_Enemy_Kind]struct{
	texture: GFX_Texture,
	max_hp: int,
	speed: f32,
	hitbox_offset: f32,
	hitbox_radius: f32,
	attack_damage: int,
	attack_knockback: f32,
	attack_radius: f32,
	attack_cooldown: TIME_Timer,
}{
	.Tung_Tung_Sahur = {
		max_hp = 4,
		speed = 4.5,
		hitbox_offset = 1.2,
		hitbox_radius = 1.0,
		attack_damage = 8,
		attack_knockback = 10.0,
		attack_radius = 1.0,
		attack_cooldown = 1.0,
	},
	.Trallalero_Trallalla = {
		max_hp = 3,
		speed = 5.0,
		hitbox_offset = 1.0,
		hitbox_radius = 1.0,
		attack_damage = 5,
		attack_knockback = 12.0,
		attack_radius = 0.85,
		attack_cooldown = 1.0,
	},
	.Brr_Brr_Patapim = {
		max_hp = 6,
		speed = 3.5,
		hitbox_offset = 1.4,
		hitbox_radius = 1.2,
		attack_damage = 15,
		attack_knockback = 18.0,
		attack_radius = 1.2,
		attack_cooldown = 1.4,
	},
	.Chimpanzini_Bananini = {
		max_hp = 4,
		speed = 4.5,
		hitbox_offset = 1.0,
		hitbox_radius = 0.8,
		attack_damage = 8,
		attack_knockback = 10.0,
		attack_radius = 1.0,
		attack_cooldown = 1.1,
	},
	.Assassino_Cappuccino = {
		max_hp = 3,
		speed = 5.0,
		hitbox_offset = 0.8,
		hitbox_radius = 0.8,
		attack_damage = 5,
		attack_knockback = 8.0,
		attack_radius = 1.0,
		attack_cooldown = 0.9,
	},
}

@(private="file")
_get_enemy_kind_string :: proc(kind: _Enemy_Kind) -> string {
	result: string
	switch kind {
	case .Tung_Tung_Sahur:      result = "Tung Tung Tung Sahur"
	case .Trallalero_Trallalla: result = "Trallalero Trallalla"
	case .Brr_Brr_Patapim:      result = "Brr Brr Patapim"
	case .Chimpanzini_Bananini: result = "Chimpanzini Bananini"
	case .Assassino_Cappuccino: result = "Assassino Cappuccino"
	}
	return result
}

@(private="file")
_enemy_tick :: proc(e: ^_Enemy, delta: f32) {
	if !TIME_is_timer_timeout(e.attack_timer) {
		return
	}

	target := _ctx.player.position
	dir := linalg.normalize0(target - e.position)

	data := _ENEMY_DATABASE[e.kind]

	if linalg.length2(target - e.position) > data.attack_radius*data.attack_radius {
		e.position += dir*data.speed*delta
	} else {
		AUD_play_sound(&_ctx.player_hit_sound)
		_ctx.player.hp -= data.attack_damage
		_ctx.player.knockback_vel = dir.xz*data.attack_knockback
		_ctx.player.tick_since_last_hit = 0
		TIME_set_timer(&e.attack_timer, data.attack_cooldown)
	}
}

@(private="file")
_enemy_draw :: proc(e: _Enemy) {
	data := _ENEMY_DATABASE[e.kind]
	tex_width := sg.query_image_width(data.texture.texture)
	tex_height := sg.query_image_height(data.texture.texture)
	GFX_draw_3d_billboard_texture(
		&_ctx.ren3d,
		data.texture.texture,
		data.texture.sampler,
		e.position + {0.0, data.hitbox_offset, 0.0},
		{data.hitbox_radius, data.hitbox_radius}*2.0,
		{0.0, 0.0, f32(tex_width), f32(tex_height)},
		M_COLOR_WHITE,
		true,
	)
}

@(private="file") _MAX_PICKUP :: 100
@(private="file") _PICKUP_VISIBILITY_RADIUS :: 100.0
@(private="file") _PICKUP_RADIUS :: 2.0
@(private="file") _PICKUP_SPRITE_SIZE :: 1.0
@(private="file") _PICKUP_GRAVITY :: 20.0

@(private="file")
_Pickup_Kind :: enum {
	Hp,
	Ammo,
}

@(private="file")
_Pickup :: struct {
	kind: _Pickup_Kind,
	position: M_Vec3f32,
	vel: M_Vec3f32,
}

@(private="file")
_pickup_tick :: proc(p: ^_Pickup, delta: f32) -> bool {
	if p.position.y > 0.0 {
		p.vel.y -= _PICKUP_GRAVITY*delta
		p.position += p.vel*delta
	} else {
		p.position.y = 0.0
	}

	dist_sqr := linalg.length2(_ctx.player.position - p.position)
	if dist_sqr <= _PICKUP_RADIUS*_PICKUP_RADIUS {
		return true
	}
	return false
}

@(private="file")
_pickup_draw :: proc(p: _Pickup) {
	if linalg.length2(_ctx.player.position - p.position) > _PICKUP_VISIBILITY_RADIUS*_PICKUP_VISIBILITY_RADIUS {
		return
	}

	tex: GFX_Texture
	switch p.kind {
	case .Hp:   tex = _ctx.hp_pickup_tex
	case .Ammo: tex = _ctx.ammo_pickup_tex
	}

	tex_width := sg.query_image_width(tex.texture)
	tex_height := sg.query_image_height(tex.texture)

	center := p.position + {0.0, _PICKUP_SPRITE_SIZE/2.0, 0.0}

	GFX_draw_3d_billboard_texture(
		&_ctx.ren3d,
		tex.texture,
		tex.sampler,
		center,
		{_PICKUP_SPRITE_SIZE, _PICKUP_SPRITE_SIZE},
		{0.0, 0.0, f32(tex_width), f32(tex_height)},
		M_COLOR_WHITE,
		true,
	)

	GFX_add_3d_light(&_ctx.ren3d, {
		position = center,
		intensity = 1.0,
		radius = 4.0,
		color = {0.0, 1.0, 1.0},
		falloff = 2.5,
	})
}

scn_game_init :: proc() {
	WND_lock_mouse(true)

	GFX_create_2d_renderer(&_ctx.ren2d)
	GFX_create_3d_renderer(&_ctx.ren3d, VIEWPORT_WIDTH, VIEWPORT_HEIGHT)
	GFX_create_post_fx_renderer(&_ctx.ren_fx, VIEWPORT_WIDTH, VIEWPORT_HEIGHT)

	{
		img: GFX_Image
		GFX_load_image_from_file(&img, "res/font/font_big.png")
		GFX_load_font_from_image(&_ctx.font, img)
		GFX_unload_image(&img)
	}

	_ctx.cam.position.y = 1.0
	_ctx.cam.fovy = math.PI/2.0

	_player_init()

	_ctx.max_enemies = 4
	TIME_set_timer(&_ctx.max_enemies_timer, _DIFFICULTY_INCREASE_INTERVAL)

	RES_load_texture(&_ctx.hp_pickup_tex, RES_ID_IMAGE_HP_PICKUP_PNG)
	RES_load_texture(&_ctx.ammo_pickup_tex, RES_ID_IMAGE_AMMO_PICKUP_PNG)

	RES_load_texture(&_ENEMY_DATABASE[.Tung_Tung_Sahur].texture, RES_ID_IMAGE_TUNG_TUNG_SAHUR_PNG)
	RES_load_texture(&_ENEMY_DATABASE[.Trallalero_Trallalla].texture, RES_ID_IMAGE_TRALLALERO_TRALLALLA_PNG)
	RES_load_texture(&_ENEMY_DATABASE[.Brr_Brr_Patapim].texture, RES_ID_IMAGE_BRR_BRR_PATAPIM_PNG)
	RES_load_texture(&_ENEMY_DATABASE[.Chimpanzini_Bananini].texture, RES_ID_IMAGE_CHIMPANZINI_BANANINI_PNG)
	RES_load_texture(&_ENEMY_DATABASE[.Assassino_Cappuccino].texture, RES_ID_IMAGE_ASSASSINO_CAPPUCCINO_PNG)

	RES_load_sound(&_ctx.game_start_sound, RES_ID_SOUND_GAME_START_WAV)
	RES_load_sound(&_ctx.player_footstep_sound, RES_ID_SOUND_PLAYER_FOOTSTEP_WAV)
	RES_load_sound(&_ctx.player_hit_sound, RES_ID_SOUND_PLAYER_HIT_WAV)
	RES_load_sound(&_ctx.player_shoot_sound, RES_ID_SOUND_PLAYER_SHOOT_WAV)
	RES_load_sound(&_ctx.player_shoot_no_ammo_sound, RES_ID_SOUND_PLAYER_SHOOT_NO_AMMO_WAV)
	RES_load_sound(&_ctx.enemy_hit_sound, RES_ID_SOUND_ENEMY_HIT_WAV)
	RES_load_sound(&_ctx.pickup_sound, RES_ID_SOUND_PICKUP_WAV)

	RES_load_sound(&_ctx.hovered_sound, RES_ID_SOUND_UI_HOVERED_WAV)

	RES_load_music(&_ctx.music, RES_ID_MUSIC_COSMIC_STAR_OGG)

	_ctx.enemy_hit_particle_emitter = {
		particles_per_emission = 16,
		min_lifetime = 0.3,
		max_lifetime = 0.7,
		min_size = 0.3,
		max_size = 0.6,
		min_vel = 4.0,
		max_vel = 7.0,
		color = {255, 0, 0, 255},
	}

	AUD_play_sound(&_ctx.game_start_sound)

	ma.sound_set_looping(&_ctx.music.sound, true)
	ma.sound_set_volume(&_ctx.music.sound, 0.7)
	ma.sound_start(&_ctx.music.sound)
}

scn_game_uninit :: proc() {
	PART_destroy_emitter(&_ctx.enemy_hit_particle_emitter)

	delete(_ctx.enemies)
	delete(_ctx.pickups)

	_player_uninit()

	AUD_unload_sound(&_ctx.game_start_sound)
	AUD_unload_sound(&_ctx.player_footstep_sound)
	AUD_unload_sound(&_ctx.player_hit_sound)
	AUD_unload_sound(&_ctx.player_shoot_sound)
	AUD_unload_sound(&_ctx.player_shoot_no_ammo_sound)
	AUD_unload_sound(&_ctx.enemy_hit_sound)
	AUD_unload_sound(&_ctx.pickup_sound)

	AUD_unload_sound(&_ctx.hovered_sound)

	AUD_unload_music(&_ctx.music)

	for &data in _ENEMY_DATABASE {
		GFX_unload_texture(&data.texture)
	}

	GFX_unload_texture(&_ctx.hp_pickup_tex)
	GFX_unload_texture(&_ctx.ammo_pickup_tex)

	GFX_unload_font(&_ctx.font)
	GFX_destroy_2d_renderer(&_ctx.ren2d)
	GFX_destroy_3d_renderer(&_ctx.ren3d)
	GFX_destroy_post_fx_renderer(&_ctx.ren_fx)
	_ctx = {}

	WND_lock_mouse(false)
}

scn_game_tick :: proc(input: INP_State, delta: f32) {
	if INP_is_key_pressed(input, .ESCAPE) {
		AUD_play_sound(&_ctx.hovered_sound)
		_ctx.is_paused = !_ctx.is_paused
		WND_lock_mouse(!_ctx.is_paused)
	}

	if _ctx.is_paused {
		_game_tick_paused(input, delta)

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
		scale := min(scale_x, scale_y)

		font_height := f32(_ctx.font.base_size)*_UI_TEXT_SCALE*scale
		line_height := font_height*1.2

		y := window_height/2.0 - (line_height*len(_buttons))/2.0 - (_UI_PADDING*(len(_buttons) - 1))/2.0
		mouse := INP_get_mouse_pos(input)
		rate := 1.0 - math.pow(2.0, -25.0*delta)

		for &button in _buttons {
			rect := M_Rect{44.0*scale, y, window_width/4.0, line_height}
			target: f32 = 0.0
			is_hovered := M_is_point_in_rect(mouse, rect)

			if is_hovered {
				target = 1.0

				if !button.was_hovered {
					AUD_play_sound(&_ctx.hovered_sound)
				}

				if INP_is_mouse_pressed(input, .Left) {
					button.click_proc()
				}
			}

			button.was_hovered = is_hovered

			button.hot_t += (target - button.hot_t)*rate
			y += line_height + _UI_PADDING
		}
	} else {
		_game_tick(input, delta)
	}
}

scn_game_draw :: proc(alpha: f32) {
	GFX_begin_frame()
	GFX_clear_background(M_FCOLOR_BLACK)

	GFX_begin_3d_renderer(&_ctx.ren3d, _ctx.cam)

	GFX_add_3d_light(&_ctx.ren3d, {
		position = _ctx.cam.position,
		intensity = 1.6,
		radius = 12.0,
		color = {1.0, 1.0, 1.0},
		falloff = 2.0,
	})

	if _ctx.player.tick_since_last_shot < _PLAYER_SHOOT_ANIM_TICK_DURATION {
		GFX_add_3d_light(&_ctx.ren3d, {
			position = _ctx.cam.position,
			intensity = 2.0,
			radius = 5.0,
			color = {0.9, 0.75, 0.15},
			falloff = 2.0,
		})
	}

	GFX_draw_3d_rect(
		&_ctx.ren3d,
		{-10000.0, 0.0, -10000.0}, {0.0, 1.0, 0.0}, {127, 127, 127, 255},
		{ 10000.0, 0.0, -10000.0}, {0.0, 1.0, 0.0}, {127, 127, 127, 255},
		{ 10000.0, 0.0,  10000.0}, {0.0, 1.0, 0.0}, {127, 127, 127, 255},
		{-10000.0, 0.0,  10000.0}, {0.0, 1.0, 0.0}, {127, 127, 127, 255},
	)

	for &enemy in _ctx.enemies {
		_enemy_draw(enemy)
	}

	for &pickup in _ctx.pickups {
		_pickup_draw(pickup)
	}

	PART_draw_emitter(&_ctx.enemy_hit_particle_emitter, &_ctx.ren3d)

	GFX_end_3d_renderer(&_ctx.ren3d)

	GFX_begin_2d_renderer(&_ctx.ren2d)

	GFX_draw_post_fx(&_ctx.ren_fx, &_ctx.ren2d, &_ctx.ren3d)

	GFX_set_2d_layer(&_ctx.ren2d, 10)

	_player_draw_hud()

	if _ctx.is_paused {
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
		scale := min(scale_x, scale_y)

		GFX_set_2d_layer(&_ctx.ren2d, 100)
		GFX_draw_2d_rect(&_ctx.ren2d, {0.0, 0.0, window_width, window_height}, {0, 0, 0, 127})

		font_height := f32(_ctx.font.base_size)*_UI_TEXT_SCALE*scale
		line_height := font_height*1.2

		GFX_draw_2d_string(
			&_ctx.ren2d,
			_ctx.font,
			"PAUSED",
			{44.0*scale, 40.0*scale},
			M_COLOR_WHITE,
			(_UI_TEXT_SCALE + 3.0)*scale,
		)

		y := window_height/2.0 - (line_height*len(_buttons))/2.0 - (_UI_PADDING*(len(_buttons) - 1))/2.0

		for &button in _buttons {
			rect := M_Rect{44.0*scale, y, window_width/4.0, line_height}

			GFX_draw_2d_string(
				&_ctx.ren2d,
				_ctx.font,
				button.text,
				{rect.x*scale, y},
				M_COLOR_WHITE,
				_UI_TEXT_SCALE*scale,
			)

			GFX_draw_2d_line(
				&_ctx.ren2d,
				{rect.x*scale, y + line_height},
				{rect.x*scale + rect.width*button.hot_t, y + line_height},
				M_COLOR_WHITE,
				6.0*scale,
			)

			y += line_height + _UI_PADDING
		}
	}

	GFX_end_2d_renderer(&_ctx.ren2d)

	GFX_end_frame()
	sg.commit()
}

@(private="file")
_game_tick_paused :: proc(input: INP_State, delta: f32) {
}

@(private="file")
_game_tick :: proc(input: INP_State, delta: f32) {
	_player_tick(input, delta)

	for &enemy in _ctx.enemies {
		_enemy_tick(&enemy, delta)
	}

	#reverse for &pickup, i in _ctx.pickups {
		if _pickup_tick(&pickup, delta) {
			AUD_play_sound(&_ctx.pickup_sound)

			switch pickup.kind {
			case .Hp: _ctx.player.hp = min(_ctx.player.hp + 10, _PLAYER_MAX_HP)
			case .Ammo:
				amount := 5 + rand.int_max(4)
				_ctx.player.ammo = min(_ctx.player.ammo + amount, _PLAYER_MAX_AMMO)
			}

			ordered_remove(&_ctx.pickups, i)
		}
	}

	if INP_is_mouse_pressed(input, .Left) {
		if _ctx.player.ammo > 0 {
			_ctx.player.ammo -= 1
			_ctx.player.tick_since_last_shot = 0

			AUD_play_sound(&_ctx.player_shoot_sound)

			ray_origin := _ctx.cam.position
			ray_direction, _, _ := GFX_get_camera_forward_up_right(_ctx.cam)

			closest_enemy_distance: f32 = 99999.0
			closest_enemy_index := -1

			for enemy, i in _ctx.enemies {
				data := _ENEMY_DATABASE[enemy.kind]
				ray_sphere_vector := (enemy.position + {0.0, data.hitbox_offset, 0.0}) - ray_origin
				dot := linalg.dot(ray_sphere_vector, ray_direction)
				distance := linalg.length(ray_sphere_vector)
				d := (data.hitbox_radius*data.hitbox_radius - (distance*distance - dot*dot))
				hit := d >= 0.0
				if hit && distance <= _PLAYER_SHOT_DISTANCE && distance < closest_enemy_distance {
					closest_enemy_distance = distance
					closest_enemy_index = i
				}
			}

			if closest_enemy_index != -1 {
				enemy := &_ctx.enemies[closest_enemy_index]
				enemy_center := enemy.position + {0.0, _ENEMY_DATABASE[enemy.kind].hitbox_offset, 0.0}
				PART_emit_particle(
					&_ctx.enemy_hit_particle_emitter,
					enemy_center,
					ray_direction,
				)
				enemy.hp -= 1
				AUD_play_sound(&_ctx.enemy_hit_sound)
				if enemy.hp <= 0 {
					rand_num := rand.float32()

					_spawn_pickup :: proc(kind: _Pickup_Kind, position: M_Vec3f32) {
						if len(_ctx.pickups) >= _MAX_PICKUP {
							pop_front(&_ctx.pickups)
						}

						pickup: _Pickup
						pickup.kind = kind
						pickup.position = position
						pickup.vel = linalg.normalize0(M_Vec3f32{
							rand.float32_range(-1.0, 1.0),
							rand.float32_range(-1.0, 1.0),
							rand.float32_range(-1.0, 1.0),
						})*rand.float32_range(2.0, 5.0)
						append(&_ctx.pickups, pickup)
					}

					switch rand_num {
					case 0.00..<0.80: _spawn_pickup(.Ammo, enemy_center)
					case 0.80..<0.95: _spawn_pickup(.Hp, enemy_center)
					case 0.95..<1.00:
						_spawn_pickup(.Ammo, enemy_center)
						_spawn_pickup(.Hp, enemy_center)
					}

					_ctx.kill[enemy.kind] += 1

					unordered_remove(&_ctx.enemies, closest_enemy_index)
				}
			}
		} else {
			AUD_play_sound(&_ctx.player_shoot_no_ammo_sound)
			_ctx.player.tick_since_last_no_ammo_shot = 0
		}
	}

	if TIME_is_timer_timeout(_ctx.max_enemies_timer) {
		TIME_set_timer(&_ctx.max_enemies_timer, _DIFFICULTY_INCREASE_INTERVAL)
		_ctx.max_enemies += 2
	}

	if len(_ctx.enemies) < _ctx.max_enemies {
		enemy: _Enemy
		enemy.kind = rand.choice_enum(_Enemy_Kind)
		enemy.hp = _ENEMY_DATABASE[enemy.kind].max_hp

		dir := linalg.normalize0(M_Vec2f32{rand.float32(), rand.float32()}*2.0 - 1.0)
		enemy.position.xz = _ctx.player.position.xz + dir*40.0

		append(&_ctx.enemies, enemy)
	}

	PART_tick_emitter(&_ctx.enemy_hit_particle_emitter, delta)

	if _ctx.player.hp <= 0 {
		_game_over()
	}
}

@(private="file")
_game_over :: proc() {
	total_kill: int
	for kind in _Enemy_Kind {
		scn_game_over_add_kill_count(_get_enemy_kind_string(kind), _ctx.kill[kind])
		total_kill += _ctx.kill[kind]
	}
	scn_game_over_add_kill_count("TOTAL", total_kill)
	SCN_change(SCN_GAME_OVER_HANDLE)
}
