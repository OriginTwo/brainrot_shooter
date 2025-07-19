package game_main

import "core:fmt"
import "core:log"
import "core:mem"
import "core:time"
import "core:math/rand"

import sdl "vendor:sdl3"

import game ".."

main :: proc() {
	when game.DEV_BUILD {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)
		context.logger = log.create_console_logger(
			.Info,
			{.Level, .Terminal_Color, .Short_File_Path, .Line},
		)

		defer {
			log.destroy_console_logger(context.logger)
			for _, leak in track.allocation_map {
				fmt.printfln("%v leaked %m", leak.location, leak.size)
			}
			for bad_free in track.bad_free_array {
				fmt.printfln("%v allocation %p was freed badly\n", bad_free.location, bad_free.memory)
			}
			mem.tracking_allocator_destroy(&track)
		}
	}

	rand.reset(u64(time.time_to_unix_nano(time.now())))

	game.WND_create(game.WINDOW_TITLE, {game.WINDOW_WIDTH, game.WINDOW_HEIGHT}, flags = {.RESIZABLE})
	defer game.WND_destroy()

	sdl.SetWindowMinimumSize(game.WND_get_handle(), 640, 360)

	game.GFX_init(game.WND_get_handle(), game.WND_get_gl())
	defer game.GFX_uninit()

	game.AUD_init()
	defer game.AUD_uninit()

	game.RES_init()
	defer game.RES_uninit()

	// PART_init()
	// defer PART_uninit()

	game.SCN_init()
	defer game.SCN_uninit()
	game.SCN_register(game.SCN_GAME_HANDLE, game.SCN_GAME_CALLBACKS)
	when game.DEV_BUILD {
		game.SCN_register(game.SCN_EDITOR_HANDLE, game.SCN_EDITOR_CALLBACKS)
	}
	game.SCN_set_initial(game.SCN_GAME_HANDLE)

	frame_input_state: game.INP_State
	tick_input_state: game.INP_State

	curr_time := game.TIME_now()
	accumulator := f64(game.SECONDS_PER_TICK)  // so that it updates before drawing first frame

	for !game.WND_should_close() {
		free_all(context.temp_allocator)

		new_time := game.TIME_now()
		frame_time := new_time - curr_time
		curr_time = new_time
		accumulator += frame_time

		// handle events
		{
			frame_input_state.mouse_delta = {}
			frame_input_state.mouse_wheel = {}

			ev: sdl.Event
			for sdl.PollEvent(&ev) {
				game.WND_handle_event(&ev)
				game.INP_handle_event(&frame_input_state, &ev)
			}
		}

		// tick
		{
			for accumulator >= game.SECONDS_PER_TICK {
				accumulator -= game.SECONDS_PER_TICK
				game.TIME_tick_timers(game.SECONDS_PER_TICK)
				game.INP_copy(&tick_input_state, frame_input_state)
				game.SCN_tick(tick_input_state, game.SECONDS_PER_TICK)
			}
		}

		game.SCN_draw(f32(accumulator*game.TICKS_PER_SECOND))

		game.SCN_process_pending()
	}
}
