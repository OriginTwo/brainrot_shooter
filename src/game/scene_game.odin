package game

import "core:os"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:math/ease"
import "core:math/rand"

import sdl "vendor:sdl3"
import ma "vendor:miniaudio"

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

	cam: GFX_Camera,
	player: _Player,

	enemies: [dynamic]_Enemy,
	pickups: [dynamic]_Pickup,

	hp_pickup_tex: GFX_Texture,
	ammo_pickup_tex: GFX_Texture,

	player_hit_sound: AUD_Sound,
	player_shoot_sound: AUD_Sound,
	player_shoot_no_ammo_sound: AUD_Sound,
	enemy_die_sound: AUD_Sound,
	pickup_sound: AUD_Sound,

	enemy_hit_particle_emitter: PART_Emitter,

	disable_bloom: bool,
}

@(private="file") _PLAYER_MAX_HP :: 100
@(private="file") _PLAYER_MAX_AMMO :: 999
@(private="file") _PLAYER_WIDTH :: 1.0
@(private="file") _PLAYER_HEIGHT :: 1.6
@(private="file") _PLAYER_SPEED :: 6.0
@(private="file") _PLAYER_SHOT_DISTANCE :: 30.0
@(private="file") _PLAYER_SHOOT_ANIM_TICK_DURATION :: 3

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

	tick_since_last_shot: u32,
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

	if move_vec != {} {
		p.bob_t += delta*4.0
	} else {
		p.bob_t -= delta*4.0
	}
	p.bob_t = clamp(p.bob_t, 0.0, 1.0)
	_ctx.cam.offset.y = 0.1*p.bob_t*math.sin(f32(TIME_now())*14.0)
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
			M_COLOR_WHITE,
			TEXT_SCALE*scale,
		)

		y -= line_height

		GFX_draw_2d_string(
			&_ctx.ren2d,
			_ctx.font,
			fmt.tprintf("HP: %d", p.hp),
			{8.0*scale, y},
			M_COLOR_WHITE,
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

	RES_load_texture(&_ctx.hp_pickup_tex, RES_ID_IMAGE_HP_PICKUP_PNG)
	RES_load_texture(&_ctx.ammo_pickup_tex, RES_ID_IMAGE_AMMO_PICKUP_PNG)

	RES_load_texture(&_ENEMY_DATABASE[.Tung_Tung_Sahur].texture, RES_ID_IMAGE_TUNG_TUNG_SAHUR_PNG)
	RES_load_texture(&_ENEMY_DATABASE[.Trallalero_Trallalla].texture, RES_ID_IMAGE_TRALLALERO_TRALLALLA_PNG)
	RES_load_texture(&_ENEMY_DATABASE[.Brr_Brr_Patapim].texture, RES_ID_IMAGE_BRR_BRR_PATAPIM_PNG)
	RES_load_texture(&_ENEMY_DATABASE[.Chimpanzini_Bananini].texture, RES_ID_IMAGE_CHIMPANZINI_BANANINI_PNG)
	RES_load_texture(&_ENEMY_DATABASE[.Assassino_Cappuccino].texture, RES_ID_IMAGE_ASSASSINO_CAPPUCCINO_PNG)

	RES_load_sound(&_ctx.player_hit_sound, RES_ID_SOUND_PLAYER_HIT_WAV)
	RES_load_sound(&_ctx.player_shoot_sound, RES_ID_SOUND_PLAYER_SHOOT_WAV)
	RES_load_sound(&_ctx.player_shoot_no_ammo_sound, RES_ID_SOUND_PLAYER_SHOOT_NO_AMMO_WAV)
	RES_load_sound(&_ctx.enemy_die_sound, RES_ID_SOUND_ENEMY_DIE_WAV)
	RES_load_sound(&_ctx.pickup_sound, RES_ID_SOUND_PICKUP_WAV)

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
}

scn_game_uninit :: proc() {
	PART_destroy_emitter(&_ctx.enemy_hit_particle_emitter)

	delete(_ctx.enemies)
	delete(_ctx.pickups)

	_player_uninit()

	AUD_unload_sound(&_ctx.player_hit_sound)
	AUD_unload_sound(&_ctx.player_shoot_sound)
	AUD_unload_sound(&_ctx.player_shoot_no_ammo_sound)
	AUD_unload_sound(&_ctx.enemy_die_sound)
	AUD_unload_sound(&_ctx.pickup_sound)

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

	_ctx.player.tick_since_last_shot += 1
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
				if enemy.hp <= 0 {
					AUD_play_sound(&_ctx.enemy_die_sound)

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

					unordered_remove(&_ctx.enemies, closest_enemy_index)
				}
			}
		} else {
			AUD_play_sound(&_ctx.player_shoot_no_ammo_sound)
		}
	}

	if len(_ctx.enemies) < 5 {
		enemy: _Enemy
		enemy.kind = rand.choice_enum(_Enemy_Kind)
		enemy.hp = _ENEMY_DATABASE[enemy.kind].max_hp

		dir := linalg.normalize0(M_Vec2f32{rand.float32(), rand.float32()}*2.0 - 1.0)
		enemy.position.xz = _ctx.player.position.xz + dir*30.0

		append(&_ctx.enemies, enemy)
	}

	PART_tick_emitter(&_ctx.enemy_hit_particle_emitter, delta)
}

scn_game_draw :: proc(alpha: f32) {
	GFX_begin_frame()
	GFX_clear_background(M_FCOLOR_BLACK)

	GFX_begin_3d_renderer(&_ctx.ren3d, _ctx.cam)

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

	_player_draw_hud()

	GFX_end_2d_renderer(&_ctx.ren2d)

	GFX_end_frame()

	sg.commit()
}
