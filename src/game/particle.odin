package game

import "core:math"
import "core:math/rand"
import "core:math/linalg"
import "core:slice"

import rl "vendor:raylib"

/*
#assert(false, "REMOVE RAYLIB")

PART_Handle :: distinct u64

PART_Particle_Shape_Square :: struct {
	min_length: f32,
	max_length: f32,
}

PART_Particle_Shape_Circle :: struct {
	min_radius: f32,
	max_radius: f32,
}

PART_Particle_Shape_Triangle :: struct {
	min_length: f32, // distance to vertex
	max_length: f32, // distance to vertex
}

PART_Particle_Shape_Texture :: struct {
	texture: rl.Texture2D,
	is_align_y: bool, // align texture y with velocity
	is_animation_enable: bool,
	frame_count: int,
	min_initial_frame: int,
	max_initial_frame: int,
	min_scale: f32,
	max_scale: f32,
}

PART_Particle_Shape_Spark :: struct {
	min_half_width: f32,
	max_half_width: f32,
	min_head_length: f32,
	max_head_length: f32,
	min_tail_length: f32,
	max_tail_length: f32,
}

PART_Particle_Shape :: union {
	PART_Particle_Shape_Square,
	PART_Particle_Shape_Circle,
	PART_Particle_Shape_Triangle,
	PART_Particle_Shape_Texture,
	PART_Particle_Shape_Spark,
}

PART_Emission_Shape_Point :: struct {
}

PART_Emission_Shape_Rectangle :: struct {
	width: f32,
	height: f32,
}

PART_Emission_Shape_Circle :: struct {
	radius: f32,
}

PART_Emission_Shape_Ring :: struct {
	outer_radius: f32,
	inner_radius: f32,
}

PART_Emission_Shape :: union {
	PART_Emission_Shape_Point,
	PART_Emission_Shape_Rectangle,
	PART_Emission_Shape_Circle,
	PART_Emission_Shape_Ring,
}

PART_Emitter_Config :: struct {
	is_one_shot: bool,

	particle_count: int,
	particle_shape: PART_Particle_Shape,

	emission_shape: PART_Emission_Shape,
	emission_spread: f32,

	gravity: f32,
	min_lifetime: f32,
	max_lifetime: f32,
	min_initial_rotation: f32,
	max_initial_rotation: f32,
	min_initial_linear_vel: f32,
	max_initial_linear_vel: f32,
	min_initial_angular_vel: f32,
	max_initial_angular_vel: f32,
	min_initial_radial_vel: f32,
	max_initial_radial_vel: f32,
	min_initial_tangential_vel: f32,
	max_initial_tangential_vel: f32,
	min_linear_accel: f32,
	max_linear_accel: f32,
	min_angular_accel: f32,
	max_angular_accel: f32,
	min_radial_accel: f32,
	max_radial_accel: f32,
	min_tangential_accel: f32,
	max_tangential_accel: f32,
	min_damping: f32,
	max_damping: f32,

	scale_curve: []Vec2f32, // cubic bezier spline
	color_curve: [][5]f32,  // linear interpolation, [0] = x, [1:] = color

	sub_emitter: PART_Handle,
}

PART_Emitter :: struct {
	config: PART_Emitter_Config,
	is_emitting: bool,
	particle_count: int,
	position: Vec2f32,
	direction: Vec2f32,
	spawn_cooldown: f32, // time to wait to spawn new particle
	spawn_timer: f32,    // when to spawn new particle
}

PART_init :: proc() {
}

PART_uninit :: proc() {
	for handle in PART__ctx.emitters {
		PART_emitter_destroy(handle)
	}
	delete(PART__ctx.emitters)
	delete(PART__ctx.particles)
}

PART_destroy_all :: proc() {
	clear(&PART__ctx.emitters)
	clear(&PART__ctx.particles)
}

PART_tick :: proc(delta: f32) {
	for handle, &emitter in PART__ctx.emitters {
		if emitter.is_emitting && !emitter.config.is_one_shot {
			emitter.spawn_timer += delta
			if emitter.spawn_timer >= emitter.spawn_cooldown {
				emitter.spawn_timer -= emitter.spawn_cooldown
				PART__spawn_particle(handle)
			}
		}
	}

	#reverse for &particle, i in PART__ctx.particles {
		emitter := PART__ctx.emitters[particle.emitter_handle]

		particle.prev_time_alive = particle.time_alive
		particle.time_alive += delta

		if particle.time_alive >= particle.lifetime {
			ordered_remove(&PART__ctx.particles, i)
			emitter.particle_count -= 1
			continue
		}

		particle.linear_vel += particle.linear_accel*delta
		particle.angular_vel += particle.angular_accel*delta
		particle.radial_vel += particle.radial_accel*delta
		particle.tangential_vel += particle.tangential_accel*delta

		if abs(particle.linear_vel) > particle.damping*delta {
			particle.linear_vel -= math.sign(particle.linear_vel)*particle.damping*delta
		}

		particle.prev_rotation = particle.curr_rotation
		particle.curr_rotation += particle.angular_vel*delta

		dir_from_emitter := linalg.normalize0(particle.curr_pos - emitter.position)
		particle.total_vel =
			particle.linear_vel*particle.direction +
			particle.radial_vel*dir_from_emitter +
			particle.tangential_vel*linalg.orthogonal(dir_from_emitter) +
			emitter.config.gravity*Vec2f32{0.0, 1.0}

		particle.prev_pos = particle.curr_pos
		particle.curr_pos += particle.total_vel*delta

		if texture_shape, ok := &particle.shape_data.(PART__Particle_Shape_Texture_Data); ok {
			shape := emitter.config.particle_shape.(PART_Particle_Shape_Texture)
			if shape.is_animation_enable {
				texture_shape.frame = int(particle.time_alive/particle.lifetime*f32(shape.frame_count))
			}
		}

		if emitter.config.is_one_shot && emitter.particle_count == 0 {
			emitter.is_emitting = false
		}
	}
}

PART_draw :: proc(alpha: f32) {
	for &particle in PART__ctx.particles {
		emitter := PART__ctx.emitters[particle.emitter_handle]

		time_alive := math.lerp(particle.prev_time_alive, particle.time_alive, alpha)
		position := math.lerp(particle.prev_pos, particle.curr_pos, alpha)
		rotation := math.lerp(particle.prev_rotation, particle.curr_rotation, alpha)

		progress := time_alive/particle.lifetime
		scale := f32(1.0)
		if s, ok := SPLN_sample(emitter.config.scale_curve, progress); ok {
			scale = s.y
		}

		color: rl.Color
		{
			c: Vec4f32
			switch len(emitter.config.color_curve) {
			case 0: c = {1.0, 1.0, 1.0, 1.0}
			case 1: c = swizzle(emitter.config.color_curve[0], 1, 2, 3, 4)
			case:   c = color_lerp(emitter.config.color_curve, progress)
			}
			color = rl.ColorFromNormalized(c)
		}

		switch shape_data in particle.shape_data {
		case PART__Particle_Shape_Square_Data:
			length := Vec2f32{shape_data.length, shape_data.length}*scale
			rect := rl.Rectangle{position.x, position.y, length.x, length.y}
			rl.DrawRectanglePro(rect, length/2.0, rotation, color)

		case PART__Particle_Shape_Circle_Data:
			rl.DrawCircleV(position, shape_data.radius*scale, color)

		case PART__Particle_Shape_Triangle_Data:
			length := Vec2f32{shape_data.length, shape_data.length}*scale
			rad := rotation*math.RAD_PER_DEG
			rl.DrawTriangle(
				position + length*{
					math.cos_f32(rad),
					math.sin_f32(rad),
				},
				position + length*{
					math.cos_f32(rad - math.TAU/3.0),
					math.sin_f32(rad - math.TAU/3.0),
				},
				position + length*{
					math.cos_f32(rad + math.TAU/3.0),
					math.sin_f32(rad + math.TAU/3.0),
				},
				color,
			)

		case PART__Particle_Shape_Texture_Data:
			shape := emitter.config.particle_shape.(PART_Particle_Shape_Texture)
			texture := shape.texture
			frame_width := f32(texture.width)/f32(shape.frame_count)
			source := rl.Rectangle{
				f32(shape_data.frame)*frame_width,
				0.0,
				frame_width,
				f32(texture.height),
			}
			dest := rl.Rectangle{
				position.x,
				position.y,
				source.width*shape_data.scale,
				source.height*shape_data.scale,
			}
			rot := rotation
			if shape.is_align_y {
				rot = math.atan2(particle.total_vel.y, particle.total_vel.x)*math.DEG_PER_RAD + 90.0
			}
			rl.DrawTexturePro(texture, source, dest, {dest.width, dest.height}/2.0, rot, color)

		case PART__Particle_Shape_Spark_Data:
			dir := particle.direction
			perp_dir := linalg.orthogonal(dir)
			head := position + dir*shape_data.head_length*scale
			tail := position - dir*shape_data.tail_length*scale
			side_l := position - perp_dir*shape_data.half_width*scale
			side_r := position + perp_dir*shape_data.half_width*scale
			rl.DrawTriangle(head, side_l, tail, color) // left half
			rl.DrawTriangle(tail, side_r, head, color) // right half
		}
	}
}

PART_emitter_create :: proc(config: PART_Emitter_Config) -> PART_Handle {
	cfg := config
	if cfg.particle_count < 1 {
		cfg.particle_count = 8
	}

	// ensure min & max
	swap_minmax(&cfg.min_lifetime, &cfg.max_lifetime)
	swap_minmax(&cfg.min_initial_rotation, &cfg.max_initial_rotation)
	swap_minmax(&cfg.min_initial_linear_vel, &cfg.max_initial_linear_vel)
	swap_minmax(&cfg.min_initial_angular_vel, &cfg.max_initial_angular_vel)
	swap_minmax(&cfg.min_initial_radial_vel, &cfg.max_initial_radial_vel)
	swap_minmax(&cfg.min_initial_tangential_vel, &cfg.max_initial_tangential_vel)
	swap_minmax(&cfg.min_linear_accel, &cfg.max_linear_accel)
	swap_minmax(&cfg.min_angular_accel, &cfg.max_angular_accel)
	swap_minmax(&cfg.min_radial_accel, &cfg.max_radial_accel)
	swap_minmax(&cfg.min_tangential_accel, &cfg.max_tangential_accel)
	swap_minmax(&cfg.min_damping, &cfg.max_damping)

	cfg.scale_curve = slice.clone(config.scale_curve)
	cfg.color_curve = slice.clone(config.color_curve)

	handle := PART_Handle(rand.uint64())
	PART__ctx.emitters[handle] = {
		config = cfg,
	}
	return handle
}

PART_emitter_destroy :: proc(handle: PART_Handle) {
	delete(PART__ctx.emitters[handle].config.scale_curve)
	delete(PART__ctx.emitters[handle].config.color_curve)
	delete_key(&PART__ctx.emitters, handle)
}

PART_emitter_start :: proc(handle: PART_Handle) {
	emitter := &PART__ctx.emitters[handle]
	if emitter.is_emitting {
		return
	}

	emitter.is_emitting = true
	emitter.spawn_cooldown =
		(emitter.config.min_lifetime + emitter.config.max_lifetime)/2.0/
		f32(emitter.config.particle_count)
	emitter.spawn_timer = 0.0

	if emitter.config.is_one_shot {
		for i in 0..<emitter.config.particle_count {
			PART__spawn_particle(handle)
		}
	}
}

PART_emitter_stop :: proc(handle: PART_Handle) {
	emitter := &PART__ctx.emitters[handle]
	emitter.is_emitting = false
}

PART_emitter_set_position :: proc(handle: PART_Handle, position: Vec2f32) {
	emitter := &PART__ctx.emitters[handle]
	emitter.position = position
}

PART_emitter_set_direction :: proc(handle: PART_Handle, direction: Vec2f32) {
	emitter := &PART__ctx.emitters[handle]
	emitter.direction = direction
}



@(private="file")
PART__ctx: struct {
	emitters: map[PART_Handle]PART_Emitter,
	particles: [dynamic]PART__Particle,
}

@(private="file")
PART__Particle_Shape_Square_Data :: struct {
	length: f32,
}

@(private="file")
PART__Particle_Shape_Circle_Data :: struct {
	radius: f32,
}

@(private="file")
PART__Particle_Shape_Triangle_Data :: struct {
	length: f32,
}

@(private="file")
PART__Particle_Shape_Texture_Data :: struct {
	frame: int,
	scale: f32,
}

@(private="file")
PART__Particle_Shape_Spark_Data :: struct {
	half_width: f32,
	head_length: f32,
	tail_length: f32,
}

@(private="file")
PART__Particle_Shape_Data :: union {
	PART__Particle_Shape_Square_Data,
	PART__Particle_Shape_Circle_Data,
	PART__Particle_Shape_Triangle_Data,
	PART__Particle_Shape_Texture_Data,
	PART__Particle_Shape_Spark_Data,
}

@(private="file")
PART__Particle :: struct {
	emitter_handle: PART_Handle,
	shape_data: PART__Particle_Shape_Data,

	lifetime: f32,
	time_alive: f32,
	prev_time_alive: f32,

	curr_pos: Vec2f32,
	prev_pos: Vec2f32,
	direction: Vec2f32,

	curr_rotation: f32,
	prev_rotation: f32,
	linear_vel: f32,
	linear_accel: f32,
	angular_vel: f32,
	angular_accel: f32,
	radial_vel: f32,
	radial_accel: f32,
	tangential_vel: f32,
	tangential_accel: f32,
	damping: f32,

	total_vel: Vec2f32,
}

@(private="file")
PART__spawn_particle :: proc(handle: PART_Handle) {
	emitter := &PART__ctx.emitters[handle]
	cfg := emitter.config

	spread := rand.float32_range(
		-cfg.emission_spread,
		cfg.emission_spread,
	)*math.RAD_PER_DEG
	s, c := math.sincos(spread)

	particle: PART__Particle
	particle.emitter_handle = handle
	particle.lifetime = rand.float32_range(cfg.min_lifetime, cfg.max_lifetime)
	particle.direction = {
		emitter.direction.x*c - emitter.direction.y*s,
		emitter.direction.x*s + emitter.direction.y*c,
	}
	particle.curr_rotation = rand.float32_range(cfg.min_initial_rotation, cfg.max_initial_rotation)
	particle.linear_vel = rand.float32_range(cfg.min_initial_linear_vel, cfg.max_initial_linear_vel)
	particle.linear_accel = rand.float32_range(cfg.min_linear_accel, cfg.max_linear_accel)
	particle.angular_vel = rand.float32_range(cfg.min_initial_angular_vel, cfg.max_initial_angular_vel)
	particle.angular_accel = rand.float32_range(cfg.min_angular_accel, cfg.max_angular_accel)
	particle.radial_vel = rand.float32_range(cfg.min_initial_radial_vel, cfg.max_initial_radial_vel)
	particle.radial_accel = rand.float32_range(cfg.min_radial_accel, cfg.max_radial_accel)
	particle.tangential_vel = rand.float32_range(cfg.min_initial_tangential_vel, cfg.max_initial_tangential_vel)
	particle.tangential_accel = rand.float32_range(cfg.min_tangential_accel, cfg.max_tangential_accel)
	particle.damping = rand.float32_range(cfg.min_damping, cfg.max_damping)

	switch shape in cfg.particle_shape {
	case PART_Particle_Shape_Square:
		particle.shape_data = PART__Particle_Shape_Square_Data{
			length = rand.float32_range(shape.max_length, shape.max_length),
		}

	case PART_Particle_Shape_Circle:
		particle.shape_data = PART__Particle_Shape_Circle_Data{
			radius = rand.float32_range(shape.min_radius, shape.max_radius),
		}

	case PART_Particle_Shape_Triangle:
		particle.shape_data = PART__Particle_Shape_Triangle_Data{
			length = rand.float32_range(shape.min_length, shape.max_length),
		}

	case PART_Particle_Shape_Texture:
		initial_frame := 0
		if frame_range := shape.max_initial_frame - shape.min_initial_frame; frame_range > 0 {
			initial_frame = shape.min_initial_frame + rand.int_max(frame_range)
		}
		particle.shape_data = PART__Particle_Shape_Texture_Data{
			frame = initial_frame,
			scale = rand.float32_range(shape.min_scale, shape.max_scale),
		}

	case PART_Particle_Shape_Spark:
		particle.shape_data = PART__Particle_Shape_Spark_Data{
			half_width = rand.float32_range(shape.min_half_width, shape.max_half_width),
			head_length = rand.float32_range(shape.min_head_length, shape.max_head_length),
			tail_length = rand.float32_range(shape.min_tail_length, shape.max_tail_length),
		}
	}

	switch shape in cfg.emission_shape {
	case PART_Emission_Shape_Point:
		particle.curr_pos = emitter.position

	case PART_Emission_Shape_Rectangle:
		particle.curr_pos.x = rand.float32_range(
			emitter.position.x - shape.width/2.0,
			emitter.position.x + shape.width/2.0,
		)
		particle.curr_pos.y = rand.float32_range(
			emitter.position.y - shape.height/2.0,
			emitter.position.y + shape.height/2.0,
		)

	case PART_Emission_Shape_Circle:
		position := Vec2f32{
			rand.float32()*2.0 - 1.0,
			rand.float32()*2.0 - 1.0,
		}
		if linalg.length2(position) > 1.0 {
			position = linalg.normalize(position)
		}
		particle.curr_pos = emitter.position + position*shape.radius

	case PART_Emission_Shape_Ring:
		position := Vec2f32{
			rand.float32()*2.0 - 1.0,
			rand.float32()*2.0 - 1.0,
		}
		if linalg.length2(position) > 1.0 {
			position = linalg.normalize(position)
		}
		particle.curr_pos = emitter.position + position*rand.float32_range(
			shape.inner_radius,
			shape.outer_radius,
		)
	}

	append(&PART__ctx.particles, particle)
	emitter.particle_count += 1
}
*/
