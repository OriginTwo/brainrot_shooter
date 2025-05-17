package game

import "core:os"
import "core:log"
import "core:slice"
import "core:strings"
import "core:hash/xxhash"
import "core:math/rand"
import "core:encoding/json"

/*
ASST_Handle :: struct {
	index: int,
	generation: int,
}

ASST_init :: proc() {
when DEV_BUILD {

	ASST__ctx.seed = rand.uint64()

} else {

	pack_file_err: os.Error
	ASST__ctx.pack_file, pack_file_err = os.open("resource.dat", os.O_RDONLY)
	assert(pack_file_err == os.ERROR_NONE)

	pack_version: u32
	os.read_ptr(ASST__ctx.pack_file, &pack_version, size_of(pack_version))

	resource_count: u64
	os.read_ptr(ASST__ctx.pack_file, &resource_count, size_of(resource_count))
	for i in 0..<resource_count {
		handle: u64
		packed_offset: i64
		packed_size: i64
		os.read_ptr(ASST__ctx.pack_file, &handle, size_of(handle))
		os.read_ptr(ASST__ctx.pack_file, &packed_offset, size_of(packed_offset))
		os.read_ptr(ASST__ctx.pack_file, &packed_size, size_of(packed_size))
		ASST__ctx.resource_map[handle] = {
			packed_offset = packed_offset,
			packed_size = packed_size,
		}
	}
	seek_amount, seek_err := os.seek(ASST__ctx.pack_file, 0, os.SEEK_CUR)
	ASST__ctx.binary_blob_offset = seek_amount

}

	ASST__init_storage()
}

ASST_uninit :: proc() {
when DEV_BUILD {

	data, data_err := json.marshal(
		ASST__ctx.registry,
		{
			spec = json.DEFAULT_SPECIFICATION,
			pretty = true,
			use_spaces = false,
		},
		context.temp_allocator,
	)
	if data_err != {} {
		log.warnf("ASST: failed to encode json data: %v", data_err)
		log.infof("ASST: registry: '%v'", ASST__ctx.registry)
		return
	}

	if !os.write_entire_file("res/asset_registry.json", data) {
		log.warnf("ASST: failed to write registry to file")
	}

	delete(ASST__ctx.registry)

} else {

	os.close(ASST__ctx.pack_file)
	delete(ASST__ctx.resource_map)

}

	ASST__uninit_storage()
}

when DEV_BUILD {
	ASST_load_file :: proc(data: ^[]byte, path: string) {
		data_ok: bool
		data^, data_ok = os.read_entire_file(path)
		if !data_ok {
			log.warnf("ASST: failed to load file '%s'", path)
			return
		}
		ASST__write_to_registry(path)
	}

	ASST_load_image :: proc(img: ^GFX_Image, path: string) {
		GFX_load_image_from_file(img, path)
		ASST__write_to_registry(path)
	}

	ASST_load_texture :: proc(tex: ^GFX_Texture, path: string) {
		GFX_load_texture_from_file(tex, path)
		ASST__write_to_registry(path)
	}

	ASST_load_sound :: proc(snd: ^AUD_Sound, path: string) {
		if !AUD_load_sound_from_file(snd, path) {
			log.warnf("ASST: failed to load sound '%s'", path)
			return
		}
		ASST__write_to_registry(path)
	}

	ASST_load_music :: proc(msc: ^AUD_Music, path: string) {
		if !AUD_load_music_from_file(msc, path) {
			log.warnf("ASST: failed to load music '%s'", path)
			return
		}
		ASST__write_to_registry(path)
	}



	@(private="file")
	ASST__write_to_registry :: proc(path: string) {
		handle := xxhash.XXH3_64_with_seed(transmute([]byte)path, ASST__ctx.seed)
		ASST__ctx.registry[handle] = path
	}
} else {
	ASST_load_file :: proc(data: ^[]byte, id: u64) {
		data^ = slice.clone(ASST__get_resource_data(id))
	}

	ASST_load_image :: proc(img: ^GFX_Image, id: u64) {
		data := ASST__get_resource_data(id)
		GFX_load_image_from_memory(img, data)
		delete(data)
	}

	ASST_load_texture :: proc(tex: ^GFX_Texture, id: u64) {
		data := ASST__get_resource_data(id)
		GFX_load_texture_from_memory(tex, data)
		delete(data)
	}

	ASST_load_sound :: proc(snd: ^AUD_Sound, id: u64) {
		data := ASST__get_resource_data(id)
		AUD_load_sound_from_memory(snd, data)
	}

	ASST_load_music :: proc(msc: ^AUD_Music, id: u64) {
		data := ASST__get_resource_data(id)
		AUD_load_music_from_memory(msc, data)
	}



	@(private="file")
	ASST__get_resource_data :: proc(id: u64) -> []byte {
		info := ASST__ctx.resource_map[id]
		data := make([]byte, info.packed_size)
		os.read_at(
			ASST__ctx.pack_file,
			data,
			ASST__ctx.binary_blob_offset + info.packed_offset,
		)
		return data
	}
}

when DEV_BUILD {
	@(private="file")
	ASST__ctx: struct {
		seed: u64,
		registry: map[u64]string,
		storage: ASST__Storage,
	}
} else {
	@(private="file")
	ASST__ctx: struct {
		pack_file: os.Handle,
		resource_map: map[u64]struct{packed_offset, packed_size: i64},
		binary_blob_offset: i64,
		storage: ASST__Storage,
	}
}



@(private="file")
ASST__Asset_Variant :: union {
	[]byte,
	GFX_Image,
	GFX_Texture,
	AUD_Sound,
	AUD_Music,
}

@(private="file")
ASST__Asset :: struct {
	handle: ASST_Handle,
	variant: ASST__Asset_Variant,
}

@(private="file")
ASST__Storage :: struct {
	assets: [dynamic]ASST__Asset,
	free_indices: [dynamic]int,
}

@(private="file")
ASST__init_storage :: proc() {
	reserve(&ASST__ctx.storage.assets, 32)
	reserve(&ASST__ctx.storage.free_indices, 32)
}

@(private="file")
ASST__uninit_storage :: proc() {
	delete(ASST__ctx.storage.assets)
	delete(ASST__ctx.storage.free_indices)
}

@(private="file")
ASST__add_to_storage :: proc() {
	// TODO: implementation
	assert(false)
}

@(private="file")
ASST__remove_from_storage :: proc() {
	// TODO: implementation
	assert(false)
}

@(private="file")
ASST__get_from_storage :: proc() {
	// TODO: implementation
	assert(false)
}
*/
