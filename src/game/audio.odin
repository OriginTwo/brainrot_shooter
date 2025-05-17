package game

import "core:os"
import "core:log"
import "core:strings"

import ma "vendor:miniaudio"

AUD_PLAYBACK_FORMAT :: ma.format.f32
AUD_PLAYBACK_CHANNELS :: 2
AUD_PLAYBACK_SAMPLE_RATE :: 44100

AUD_Sound :: struct {
	data: []byte,
	sound: ma.sound,
	decoder: ma.decoder,
}

AUD_Music :: struct {
	data: []byte,
	sound: ma.sound,
	decoder: ma.decoder,
}

AUD_init :: proc() {
	{
		config := ma.resource_manager_config_init()
		config.decodedFormat = AUD_PLAYBACK_FORMAT
		config.decodedChannels = 0
		config.decodedSampleRate = AUD_PLAYBACK_SAMPLE_RATE
		result := ma.resource_manager_init(&config, &AUD__ctx.resman)
		if result != .SUCCESS {
			log.fatalf("AUD: failed to initialize miniaudio resource manager: %v", result)
		}
	}

	{
		config := ma.device_config_init(.playback)
		config.playback.format = AUD_PLAYBACK_FORMAT
		config.playback.channels = AUD_PLAYBACK_CHANNELS
		config.sampleRate = AUD_PLAYBACK_SAMPLE_RATE
		config.dataCallback = AUD__ma_data_callback
		result := ma.device_init(nil, &config, &AUD__ctx.device)
		if result != .SUCCESS {
			ma.resource_manager_uninit(&AUD__ctx.resman)
			log.fatalf("AUD: failed to initialize miniaudio device: %v", result)
		}
	}

	{
		config := ma.engine_config_init()
		config.pResourceManager = &AUD__ctx.resman
		config.pDevice = &AUD__ctx.device
		result := ma.engine_init(&config, &AUD__ctx.engine)
		if result != .SUCCESS {
			ma.resource_manager_uninit(&AUD__ctx.resman)
			ma.device_uninit(&AUD__ctx.device)
			log.fatalf("AUD: failed to initialize miniaudio engine: %v", result)
		}
	}
}

AUD_uninit :: proc() {
	ma.resource_manager_uninit(&AUD__ctx.resman)
	ma.device_uninit(&AUD__ctx.device)
	ma.engine_uninit(&AUD__ctx.engine)
}

AUD_load_sound_from_file :: proc(sound: ^AUD_Sound, path: string) -> bool {
	data, data_ok := os.read_entire_file(path)
	if !data_ok {
		log.warnf("AUD: failed to open sound file: %s", path)
		return false
	}
	sound.data = data
	AUD_load_sound_from_memory(sound, data)
	return true
}

AUD_load_sound_from_memory :: proc(sound: ^AUD_Sound, data: []byte) -> bool {
	result: ma.result

	decoder_config := ma.decoder_config_init(
		AUD_PLAYBACK_FORMAT,
		AUD_PLAYBACK_CHANNELS,
		AUD_PLAYBACK_SAMPLE_RATE,
	)
	result = ma.decoder_init_memory(
		raw_data(data),
		len(data),
		&decoder_config,
		&sound.decoder,
	)
	if result != .SUCCESS {
		log.warnf("AUD: failed to initialize sound decoder: %v", result)
		return false
	}

	flags := ma.sound_flags{.DECODE}
	result = ma.sound_init_from_data_source(
		&AUD__ctx.engine,
		cast(^ma.data_source)&sound.decoder,
		flags,
		nil,
		&sound.sound,
	)
	if result != .SUCCESS {
		log.warnf("AUD: failed to initialize sound: %v", result)
		return false
	}

	return true
}

AUD_unload_sound :: proc(sound: ^AUD_Sound) {
	if sound.decoder != {} {
		ma.decoder_uninit(&sound.decoder)
	}
	ma.sound_uninit(&sound.sound)
	if sound.data != nil {
		delete(sound.data)
	}
}

AUD_load_music_from_file :: proc(music: ^AUD_Music, path: string) -> bool {
	data, data_ok := os.read_entire_file(path)
	if !data_ok {
		log.warnf("AUD: failed to open music file: %s", path)
		return false
	}
	music.data = data
	AUD_load_music_from_memory(music, data)
	return true
}

AUD_load_music_from_memory :: proc(music: ^AUD_Music, data: []byte) -> bool {
	result: ma.result

	decoder_config := ma.decoder_config_init(
		AUD_PLAYBACK_FORMAT,
		AUD_PLAYBACK_CHANNELS,
		AUD_PLAYBACK_SAMPLE_RATE,
	)
	result = ma.decoder_init_memory(
		raw_data(data),
		len(data),
		&decoder_config,
		&music.decoder,
	)
	if result != .SUCCESS {
		log.warnf("AUD: failed to initialize music decoder: %v", result)
		return false
	}

	flags := ma.sound_flags{.STREAM, .NO_SPATIALIZATION}
	result = ma.sound_init_from_data_source(
		&AUD__ctx.engine,
		cast(^ma.data_source)&music.decoder,
		flags,
		nil,
		&music.sound,
	)
	if result != .SUCCESS {
		log.warnf("AUD: failed to initialize music: %v", result)
		return false
	}

	return true
}

AUD_unload_music :: proc(music: ^AUD_Music) {
	if music.decoder != {} {
		ma.decoder_uninit(&music.decoder)
	}
	ma.sound_uninit(&music.sound)
	if music.data != nil {
		delete(music.data)
	}
}



@(private="file")
AUD__ctx: struct {
	resman: ma.resource_manager,
	device: ma.device,
	engine: ma.engine,
}

@(private="file")
AUD__ma_data_callback :: proc "c" (pDevice: ^ma.device, pOut, pIn: rawptr, frameCount: u32) {
	ma.engine_read_pcm_frames(&AUD__ctx.engine, pOut, u64(frameCount), nil)
}
