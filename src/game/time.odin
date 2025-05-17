package game

import sdl "vendor:sdl3"

TIME_Timer :: f64

TIME_now :: #force_inline proc() -> f64 {
	return f64(sdl.GetTicks())/1000.0
}

TIME_tick_timers :: proc(delta: f64) {
	TIME__ctx.curr_timer_time += delta
}

TIME_is_timer_timeout :: proc(t: TIME_Timer) -> bool {
	return TIME__ctx.curr_timer_time >= t
}

TIME_set_timer :: proc(t: ^TIME_Timer, second: f64) {
	t^ = TIME__ctx.curr_timer_time + second
}



@(private="file")
TIME__ctx: struct {
	curr_timer_time: f64,
}
