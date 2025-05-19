package game

import "core:fmt"
import "core:log"
import "core:mem"
import "core:time"
import "core:math/rand"

import sdl "vendor:sdl3"

main :: proc() {
	when DEV_BUILD {
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

	WND_create(WINDOW_TITLE, {WINDOW_WIDTH, WINDOW_HEIGHT}, flags = {.RESIZABLE})
	defer WND_destroy()

	GFX_init(WND_get_handle(), WND_get_gl())
	defer GFX_uninit()

	AUD_init()
	defer AUD_uninit()

	// ASST_init()
	// defer ASST_uninit()

	// PART_init()
	// defer PART_uninit()

	SCN_init()
	defer SCN_uninit()
	SCN_register(SCN_GAME_HANDLE, SCN_GAME_CALLBACKS)
	// when DEV_BUILD {
	// 	SCN_register(SCN_EDITOR_HANDLE, SCN_EDITOR_CALLBACKS)
	// }
	SCN_set_initial(SCN_GAME_HANDLE)

	frame_input_state: INP_State
	tick_input_state: INP_State

	curr_time := TIME_now()
	accumulator := f64(SECONDS_PER_TICK)  // so that it updates before drawing first frame

	for !WND_should_close() {
		free_all(context.temp_allocator)

		new_time := TIME_now()
		frame_time := new_time - curr_time
		curr_time = new_time
		accumulator += frame_time

		// handle events
		{
			ev: sdl.Event
			for sdl.PollEvent(&ev) {
				WND_handle_event(&ev)
				INP_handle_event(&frame_input_state, &ev)
			}
		}

		// tick
		{
			for accumulator >= SECONDS_PER_TICK {
				accumulator -= SECONDS_PER_TICK
				TIME_tick_timers(SECONDS_PER_TICK)
				INP_copy(&tick_input_state, frame_input_state)
				SCN_tick(tick_input_state, SECONDS_PER_TICK)
			}
		}

		SCN_draw(f32(accumulator*TICKS_PER_SECOND))

		SCN_process_pending()
	}
}
