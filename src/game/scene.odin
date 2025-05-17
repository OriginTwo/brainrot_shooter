package game

import "core:log"

SCN_Handle :: distinct u64
SCN_INVALID_HANDLE :: SCN_Handle(0)

SCN_Callbacks :: struct {
	on_enter: proc(),
	on_leave: proc(),
	on_tick: proc(input_state: INP_State, delta: f32),
	on_draw: proc(alpha: f32),
}

SCN_init :: proc() {
}

SCN_uninit :: proc() {
	cb := SCN__ctx.registered_scenes[SCN__ctx.current_handle]
	if cb.on_leave != nil {
		cb.on_leave()
	}
	delete(SCN__ctx.registered_scenes)
}

SCN_register :: proc(handle: SCN_Handle, callbacks: SCN_Callbacks) {
	when DEV_BUILD {
		if handle in SCN__ctx.registered_scenes {
			log.warnf("SCN: scene %d is being re-registered", handle)
		}
	}
	SCN__ctx.registered_scenes[handle] = callbacks
}

SCN_set_initial :: proc(handle: SCN_Handle) {
	when DEV_BUILD {
		if SCN__ctx.current_handle != SCN_INVALID_HANDLE {
			log.warnf("SCN: attempting to set initial scene again")
			return
		}

		if handle not_in SCN__ctx.registered_scenes {
			log.errorf("SCN: setting initial scene to unregistered scene")
			return
		}
	}

	SCN__ctx.current_handle = handle
	cb := SCN__ctx.registered_scenes[SCN__ctx.current_handle]
	if cb.on_enter != nil {
		cb.on_enter()
	}
}

SCN_change :: proc(handle: SCN_Handle) {
	SCN__ctx.pending_handle = handle
}

SCN_tick :: proc(input_state: INP_State, delta: f32) {
	when DEV_BUILD {
		if SCN__ctx.current_handle == SCN_INVALID_HANDLE {
			log.warnf("SCN: trying to tick invalid scene")
			return
		}
	}
	cb := SCN__ctx.registered_scenes[SCN__ctx.current_handle]
	if cb.on_tick != nil {
		cb.on_tick(input_state, delta)
	}
}

SCN_draw :: proc(alpha: f32) {
	when DEV_BUILD {
		if SCN__ctx.current_handle == SCN_INVALID_HANDLE {
			log.warnf("SCN: trying to draw invalid scene")
			return
		}
	}
	cb := SCN__ctx.registered_scenes[SCN__ctx.current_handle]
	if cb.on_draw != nil {
		cb.on_draw(alpha)
	}
}

SCN_process_pending :: proc() {
	if SCN__ctx.pending_handle != SCN_INVALID_HANDLE {
		cb := SCN__ctx.registered_scenes[SCN__ctx.current_handle]
		if cb.on_leave != nil {
			cb.on_leave()
		}

		SCN__ctx.current_handle = SCN__ctx.pending_handle
		cb = SCN__ctx.registered_scenes[SCN__ctx.current_handle]
		if cb.on_enter != nil {
			cb.on_enter()
		}

		SCN__ctx.pending_handle = SCN_INVALID_HANDLE
	}
}



@(private="file")
SCN__ctx: struct {
	registered_scenes: map[SCN_Handle]SCN_Callbacks,
	current_handle: SCN_Handle,
	pending_handle: SCN_Handle,
}
