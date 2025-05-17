package game

import "base:runtime"
import "base:intrinsics"

import "core:mem"
import "core:slice"

SER_Serializer :: struct {
	is_writing: bool,
	read_offset: int,
	buffer: [dynamic]byte,
}

SER_init_writer :: proc(s: ^SER_Serializer, cap: int) {
	s^ = {
		is_writing = true,
		buffer = make([dynamic]byte, 0, cap),
	}
}

// NOTE: doesn't clone the data
SER_init_reader :: proc(s: ^SER_Serializer, data: []byte) {
	s^ = {
		is_writing = false,
		buffer = transmute([dynamic]byte)runtime.Raw_Dynamic_Array{
			data = raw_data(data),
			len = len(data),
			cap = len(data),
			allocator = runtime.nil_allocator(),
		},
	}
}

// NOTE: reader doesn't need to be destroyed since it doesn't own the memory
SER_destroy_writer :: proc(s: ^SER_Serializer) {
	if s.is_writing {
		delete(s.buffer)
		s^ = {}
	}
}

SER_clear :: proc(s: ^SER_Serializer) {
	s.read_offset = 0
	clear(&s.buffer)
}

SER_to_bytes :: proc(s: ^SER_Serializer) -> []byte {
	return s.buffer[:]
}

SER_serialize_bytes :: proc(s: ^SER_Serializer, data: []byte) {
	if len(data) == 0 {
		return
	}

	if s.is_writing {
		append(&s.buffer, ..data)
	} else {
		if len(s.buffer) >= s.read_offset + len(data) {
			copy(data, s.buffer[s.read_offset:][:len(data)])
			s.read_offset += len(data)
		}
	}
}

SER_serialize_opaque :: proc(s: ^SER_Serializer, data: ^$T) {
	SER_serialize_bytes(s, mem.ptr_to_bytes(data))
}

SER_serialize_slice_info :: proc(s: ^SER_Serializer, data: ^$T/[]$E) {
	length := len(data)
	SER_serialize_opaque(s, &length)
	if !s.is_writing {
		data^ = make([]E, length)
	}
}

SER_serialize_opaque_slice :: proc(s: ^SER_Serializer, data: ^$T/[]$E) {
	SER_serialize_slice_info(s, data)
	SER_serialize_bytes(s, slice.to_bytes(data^))
}

SER_serialize_dynamic_array_info :: proc(s: ^SER_Serializer, data: ^$T/[dynamic]$E) {
	length := len(data)
	SER_serialize_opaque(s, &length)
	if !s.is_writing {
		data^ = make([dynamic]E, length, length)
	}
}

SER_serialize_opaque_dynamic_array :: proc(s: ^SER_Serializer, data: ^$T/[dynamic]$E) {
	SER_serialize_dynamic_array_info(s, data)
	SER_serialize_bytes(s, slice.to_bytes(data[:]))
}

SER_serialize_basic :: proc(s: ^SER_Serializer, data: ^$T)
where intrinsics.type_is_numeric(T) ||
	intrinsics.type_is_boolean(T) ||
	intrinsics.type_is_rune(T) ||
	intrinsics.type_is_bit_set(T)
{
	SER_serialize_opaque(s, data)
}

SER_serialize_array :: proc(s: ^SER_Serializer, data: ^$T/[$N]$E) {
	when intrinsics.type_is_numeric(E) {
		SER_serialize_opaque(s, data)
	} else {
		for &v in data {
			SER_serialize(s, &v)
		}
	}
}

SER_serialize_dynamic_array :: proc(s: ^SER_Serializer, data: ^$T/[dynamic]$E) {
	SER_serialize_dynamic_array_info(s, data)
	for &v in data {
		SER_serialize(s, data)
	}
}

SER_serialize_slice :: proc(s: ^SER_Serializer, data: ^$T/[]$E) {
	SER_serialize_slice_info(s, data)
	for &v in data {
		SER_serialize(s, &v)
	}
}

SER_serialize_string :: proc(s: ^SER_Serializer, data: ^string) {
	SER_serialize_opaque_slice(s, transmute(^[]byte)data)
}

SER_serialize_map :: proc(s: ^SER_Serializer, data: ^$T/map[$K]$V) {
	length := len(data)
	SER_serialize_opaque(s, &length)

	if s.is_writing {
		for &k, &v in data {
			SER_serialize(s, &k)
			SER_serialize(s, &v)
		}
	} else {
		data^ = make(map[K]V, length)
		for _ in 0..<length {
			k: K
			v: V
			SER_serialize(s, &k)
			SER_serialize(s, &v)
			data[k] = v
		}
	}
}

SER_serialize :: proc {
	SER_serialize_basic,
	SER_serialize_array,
	SER_serialize_dynamic_array,
	SER_serialize_slice,
	SER_serialize_string,
	SER_serialize_map,
}
