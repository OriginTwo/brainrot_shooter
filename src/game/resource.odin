package game

import "core:os"

RES_ID :: distinct u64

RES_init :: proc() {
	RES__provider_init(&RES__ctx.provider)
}

RES_uninit :: proc() {
	RES__provider_uninit(&RES__ctx.provider)
	// delete(RES__ctx.entries)
	RES__ctx = {}
}

RES_load_byte :: proc(res: ^[]byte, id: RES_ID) {
	res := RES__provider_load(&RES__ctx.provider, id)
}

RES_load_image :: proc(res: ^GFX_Image, id: RES_ID) {
	data := RES__provider_load(&RES__ctx.provider, id)
	defer delete(data)
	GFX_load_image_from_memory(res, data)
}

RES_load_texture :: proc(res: ^GFX_Texture, id: RES_ID) {
	data := RES__provider_load(&RES__ctx.provider, id)
	defer delete(data)
	img: GFX_Image
	GFX_load_image_from_memory(&img, data)
	defer GFX_unload_image(&img)
	GFX_load_texture_from_image(res, img)
}

RES_load_sound :: proc(res: ^AUD_Sound, id: RES_ID) {
	data := RES__provider_load(&RES__ctx.provider, id)
	AUD_load_sound_from_memory(res, data)
}

RES_load_music :: proc(res: ^AUD_Music, id: RES_ID) {
	data := RES__provider_load(&RES__ctx.provider, id)
	AUD_load_music_from_memory(res, data)
}

// RES_acquire_byte :: proc(id: RES_ID) -> []byte {
// 	entry, entry_ok := &RES__ctx.entries[id]
// 	if !entry_ok {
// 		data := RES__provider_load(&RES__ctx.provider, id)
// 		RES__ctx.entries[id] = {
// 			num_refs = 1,
// 			variant = data,
// 		}
// 	} else {
// 		entry.num_refs += 1
// 	}
// 	return entry.variant.([]byte)
// }

// @(deferred_in=RES_release_byte)
// RES_acquire_byte_temp :: proc(id: RES_ID) -> []byte {
// 	return RES_acquire_byte(id)
// }

// RES_release_byte :: proc(id: RES_ID) {
// 	entry, entry_ok := &RES__ctx.entries[id]
// 	if !entry_ok {
// 		return
// 	}
// 	entry.num_refs -= 1
// 	if entry.num_refs <= 0 {
// 		delete(entry.variant.([]byte))
// 		delete_key(&RES__ctx.entries, id)
// 	}
// }

// RES_acquire_image :: proc(id: RES_ID) -> GFX_Image {
// 	entry, entry_ok := &RES__ctx.entries[id]
// 	if !entry_ok {
// 		data := RES__provider_load(&RES__ctx.provider, id)
// 		defer delete(data)
// 		img: GFX_Image
// 		GFX_load_image_from_memory(&img, data)
// 		RES__ctx.entries[id] = {
// 			num_refs = 1,
// 			variant = img,
// 		}
// 	} else {
// 		entry.num_refs += 1
// 	}
// 	return entry.variant.(GFX_Image)
// }

// @(deferred_in=RES_release_image)
// RES_acquire_image_temp :: proc(id: RES_ID) -> GFX_Image {
// 	return RES_acquire_image(id)
// }

// RES_release_image :: proc(id: RES_ID) {
// 	entry, entry_ok := &RES__ctx.entries[id]
// 	if !entry_ok {
// 		return
// 	}
// 	entry.num_refs -= 1
// 	if entry.num_refs <= 0 {
// 		GFX_unload_image(&entry.variant.(GFX_Image))
// 		delete_key(&RES__ctx.entries, id)
// 	}
// }

// RES_acquire_texture :: proc(id: RES_ID) -> GFX_Texture {
// 	entry, entry_ok := &RES__ctx.entries[id]
// 	if !entry_ok {
// 		data := RES__provider_load(&RES__ctx.provider, id)
// 		defer delete(data)
// 		img: GFX_Image
// 		tex: GFX_Texture
// 		GFX_load_image_from_memory(&img, data)
// 		defer GFX_unload_image(&img)
// 		GFX_load_texture_from_image(&tex, img)
// 		RES__ctx.entries[id] = {
// 			num_refs = 1,
// 			variant = tex,
// 		}
// 	} else {
// 		entry.num_refs += 1
// 	}
// 	return entry.variant.(GFX_Texture)
// }

// @(deferred_in=RES_release_texture)
// RES_acquire_texture_temp :: proc(id: RES_ID) -> GFX_Texture {
// 	return RES_acquire_texture(id)
// }

// RES_release_texture :: proc(id: RES_ID) {
// 	entry, entry_ok := &RES__ctx.entries[id]
// 	if !entry_ok {
// 		return
// 	}
// 	entry.num_refs -= 1
// 	if entry.num_refs <= 0 {
// 		GFX_unload_texture(&entry.variant.(GFX_Texture))
// 		delete_key(&RES__ctx.entries, id)
// 	}
// }



@(private="file")
RES__ctx: struct {
	provider: RES__Provider,
	// entries: map[RES_ID]RES__Loaded_Entry,
}

// @(private="file")
// RES__Loaded_Entry :: struct {
// 	num_refs: int,
// 	variant: union {
// 		[]byte,
// 		GFX_Image,
// 		GFX_Texture,
// 		AUD_Sound,
// 		AUD_Music,
// 	},
// }


///////////////////////////////////////////////////////////
// PROVIDER INTERFACE
///////////////////////////////////////////////////////////
@(private="file")
RES__Provider :: RES__File_Provider when DEV_BUILD else RES__Pak_Provider

@(private="file")
RES__provider_init :: proc {
	RES__file_provider_init,
	RES__pak_provider_init,
}

@(private="file")
RES__provider_uninit :: proc {
	RES__file_provider_uninit,
	RES__pak_provider_uninit,
}

@(private="file")
RES__provider_load :: proc {
	RES__file_provider_load,
	RES__pak_provider_load,
}


///////////////////////////////////////////////////////////
// FILE PROVIDER
///////////////////////////////////////////////////////////
@(private="file")
RES__File_Provider :: struct {}

@(private="file")
RES__file_provider_init :: proc(provider: ^RES__File_Provider) {
}

@(private="file")
RES__file_provider_uninit :: proc(provider: ^RES__File_Provider) {
}

@(private="file")
RES__file_provider_load :: proc(provider: ^RES__File_Provider, id: RES_ID) -> []byte {
	when DEV_BUILD {
		data, _ := os.read_entire_file(RES__get_file_path(id))
		return data
	} else {
		return nil
	}
}


///////////////////////////////////////////////////////////
// PAK PROVIDER
///////////////////////////////////////////////////////////
@(private="file")
RES__Pak_Provider :: struct {
	pak_file: os.Handle,
	resource_entries: map[RES_ID]RES__Pak_Resource_Entry,
}

@(private="file")
RES__Pak_Resource_Entry :: struct {
	packed_offset: i64,
	packed_size: i64,
}

@(private="file")
RES__Pak_Footer :: struct #packed {
	signature: [4]byte,
	packer_version: u32,
	resource_map_offset: i64,
	num_resource_map_entries: u32,
}

@(private="file")
RES__pak_provider_init :: proc(provider: ^RES__Pak_Provider) {
	file_err: os.Error
	provider.pak_file, file_err = os.open("resource.pak", os.O_RDONLY)
	if file_err != os.ERROR_NONE {
		os.exit(1)
	}

	footer: RES__Pak_Footer
	os.seek(provider.pak_file, -size_of(RES__Pak_Footer), os.SEEK_END)
	os.read_ptr(provider.pak_file, &footer, size_of(footer))

	os.seek(provider.pak_file, footer.resource_map_offset, os.SEEK_SET)
	for i in 0..<footer.num_resource_map_entries {
		id: RES_ID
		entry: RES__Pak_Resource_Entry
		os.read_ptr(provider.pak_file, &id, size_of(id))
		os.read_ptr(provider.pak_file, &entry.packed_offset, size_of(entry.packed_offset))
		os.read_ptr(provider.pak_file, &entry.packed_size, size_of(entry.packed_size))
		provider.resource_entries[id] = entry
	}
}

@(private="file")
RES__pak_provider_uninit :: proc(provider: ^RES__Pak_Provider) {
	os.close(provider.pak_file)
	delete(provider.resource_entries)
}

@(private="file")
RES__pak_provider_load :: proc(provider: ^RES__Pak_Provider, id: RES_ID) -> []byte {
	entry, entry_ok := provider.resource_entries[id]
	if !entry_ok {
		return nil
	}
	os.seek(provider.pak_file, entry.packed_offset, os.SEEK_SET)
	data := make([]byte, entry.packed_offset)
	os.read(provider.pak_file, data)
	return data
}
