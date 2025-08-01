package game

import "core:math/rand"
import "core:math/linalg"

PART_GRAVITY :: 20.0

PART_Emitter :: struct {
	particles_per_emission: int,
	min_lifetime: f32,
	max_lifetime: f32,
	min_size: f32,
	max_size: f32,
	min_vel: f32,
	max_vel: f32,
	color: M_Color,

	particles: [dynamic]PART__Particle,
}

PART_destroy_emitter :: proc(e: ^PART_Emitter) {
	delete(e.particles)
	e^ = {}
}

PART_emit_particle :: proc(e: ^PART_Emitter, position, direction: M_Vec3f32) {
	for i in 0..<e.particles_per_emission {
		PART__spawn_particle(e, position, direction)
	}
}

PART_tick_emitter :: proc(e: ^PART_Emitter, delta: f32) {
	#reverse for &p, i in e.particles {
		p.time_alive += delta

		if p.time_alive >= p.lifetime {
			ordered_remove(&e.particles, i)
			continue
		}

		p.vel.y -= PART_GRAVITY*delta
		p.position += p.vel*delta
	}
}

PART_draw_emitter :: proc(e: ^PART_Emitter, ren: ^GFX_3D_Renderer) {
	for p in e.particles {
		scale := 1.0 - p.time_alive/p.lifetime
		GFX_draw_3d_billboard_rect(ren, p.position, {p.size, p.size}*scale, e.color)
	}
}



@(private="file")
PART__Particle :: struct {
	lifetime: f32,
	time_alive: f32,
	size: f32,
	position: M_Vec3f32,
	vel: M_Vec3f32,
}

@(private="file")
PART__spawn_particle :: proc(e: ^PART_Emitter, position, direction: M_Vec3f32) {
	p: PART__Particle
	p.lifetime = rand.float32_range(e.min_lifetime, e.max_lifetime)
	p.size = rand.float32_range(e.min_size, e.max_size)
	p.position = position
	p.vel = linalg.normalize0(direction + {
		rand.float32_range(-1.0, 1.0),
		rand.float32_range(-1.0, 1.0),
		rand.float32_range(-1.0, 1.0),
	})*rand.float32_range(e.min_vel, e.max_vel)
	append(&e.particles, p)
}
