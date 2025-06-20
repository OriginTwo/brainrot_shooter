package asset_packer

import "core:os"
import "core:fmt"
import "core:time"
import "core:flags"
import "core:bytes"
import "core:strings"
import "core:strconv"
import "core:path/filepath"
import "core:encoding/json"

Options :: struct {
	input_dir: string `args:"required,name=dir" usage:"Input directory"`,
	packed: bool `args:"name=packed" usage:"Whether to pack or not"`,
	pkg_name: string `args:"required,name=pkg_name" usage:"Name of the package"`,
	output_def: os.Handle `args:"required,name=out_def,file=wct" usage:"Generated output definition file"`,
	output_packed: os.Handle `args:"required,name=out_packed,file=wct" usage:"Generated output packed file"`,
}

main :: proc() {
	opt: Options
	flags.parse_or_exit(&opt, os.args)
	defer os.close(opt.output_def)

	fmt.fprintfln(opt.output_def, "package %s\n", opt.pkg_name)
	if opt.packed {
		generate_packed(opt)
	} else {
		generate_not_packed(opt)
	}
}

generate_not_packed :: proc(opt: Options) {
	input_dir, input_dir_err := os.open(opt.input_dir)
	if input_dir_err != os.ERROR_NONE {
		fmt.printfln(
			"failed to open input directory: %s (%d)",
			opt.input_dir, input_dir_err,
		)
		return
	}
	defer os.close(input_dir)

	input_dir_entries, input_dir_entries_err := os.read_dir(input_dir, 0)
	if input_dir_entries_err != os.ERROR_NONE {
		fmt.printfln(
			"failed to read directory: %s (%d)",
			opt.input_dir, input_dir_entries_err,
		)
		return
	}
	defer os.file_info_slice_delete(input_dir_entries)

	for &input_dir_entry in input_dir_entries {
		if input_dir_entry.is_dir {
			_generate(opt, input_dir_entry.fullpath, input_dir_entry.name)
		}
	}

	_generate :: proc(opt: Options, fullpath, name: string) {
		dir, dir_err := os.open(fullpath)
		if dir_err != os.ERROR_NONE {
			fmt.printfln("failed to open input directory: %s (%d)", fullpath, dir_err)
			return
		}
		defer os.close(dir)

		dir_entries, dir_entries_err := os.read_dir(dir, 0)
		if dir_entries_err != os.ERROR_NONE {
			fmt.printfln("failed to read directory: %s (%d)", fullpath, dir_entries_err)
			return
		}
		defer os.file_info_slice_delete(dir_entries)

		cwd := os.get_current_directory(context.temp_allocator)
		input_dir_abs_path, _ := filepath.abs(opt.input_dir, context.temp_allocator)

		for &entry in dir_entries {
			entry_rel_path, _ := filepath.rel(
				input_dir_abs_path,
				entry.fullpath,
				context.temp_allocator,
			)

			dir_only, name_only := filepath.split(entry_rel_path)
			dir_only = filepath.base(dir_only)    // remove unwanted stuff
			name_only, _ = strings.replace_all(name_only, ".", "_", context.temp_allocator)
			entry_name := strings.join({dir_only, name_only}, " ", context.temp_allocator)
			entry_name = strings.to_upper_snake_case(entry_name, context.temp_allocator)

			entry_path, _ := filepath.rel(cwd, entry.fullpath)

			fmt.fprintfln(opt.output_def, "%s :: `%s`", entry_name, entry_path)
		}
	}
}

generate_packed :: proc(opt: Options) {
	file_data, file_data_err := os.read_entire_file_or_err(
		filepath.join(
			{opt.input_dir, "asset_registry.json"},
			context.temp_allocator,
		),
	)
	if file_data_err != {} {
		fmt.printfln("failed to open asset registry file: %v", file_data_err)
		return
	}
	defer delete(file_data)

	json_root, json_root_err := json.parse(file_data, .JSON)
	defer json.destroy_value(json_root)

	registry, registry_ok := json_root.(json.Object)
	if !registry_ok {
		fmt.printfln("invalid asset registry")
		return
	}

	resource_map: map[u64]struct{packed_offset, packed_size: i64}
	binary_blob: bytes.Buffer

	bytes.buffer_init(&binary_blob, {0, 0, 0, 0})
	defer bytes.buffer_destroy(&binary_blob)

	for handle_str, path_val in registry {
		handle, handle_ok := strconv.parse_u64(handle_str)
		if !handle_ok {
			fmt.printfln("failed to parse handle: %s", handle_str)
			continue
		}

		path, path_ok := path_val.(json.String)
		if !path_ok {
			fmt.printfln("invalid path for handle %d", handle)
			continue
		}

		dir_only, name_only := filepath.split(path)
		dir_only = filepath.base(dir_only)    // remove unwanted stuff
		name_only, _ = strings.replace_all(name_only, ".", "_", context.temp_allocator)
		entry_name := strings.join({dir_only, name_only}, " ", context.temp_allocator)
		entry_name = strings.to_upper_snake_case(entry_name, context.temp_allocator)
		fmt.fprintfln(opt.output_def, "%s :: %d", entry_name, handle)

		binary_data, binary_data_err := os.read_entire_file_or_err(path)
		if binary_data_err != os.ERROR_NONE {
			fmt.printfln("failed to read file: %s", path)
			continue
		}
		defer delete(binary_data)

		resource_map[handle] = {
			packed_offset = i64(bytes.buffer_length(&binary_blob)),
			packed_size = i64(len(binary_data)),
		}
		bytes.buffer_write(&binary_blob, binary_data)
	}

	pack_year, pack_month, pack_date := time.date(time.now())
	pack_version := u32(pack_year*10000 + int(pack_month)*100 + pack_date)
	os.write_ptr(opt.output_packed, &pack_version, size_of(pack_version))

	resource_map_len := i64(len(resource_map))
	os.write_ptr(opt.output_packed, &resource_map_len, size_of(resource_map_len))

	for hnd, &res in resource_map {
		handle := hnd
		os.write_ptr(opt.output_packed, &handle, size_of(handle))
		os.write_ptr(opt.output_packed, &res.packed_offset, size_of(res.packed_offset))
		os.write_ptr(opt.output_packed, &res.packed_size, size_of(res.packed_size))
	}

	os.write(opt.output_packed, bytes.buffer_to_bytes(&binary_blob))
}
