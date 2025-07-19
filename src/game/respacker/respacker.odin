package resource_packer

import "core:os"
import "core:fmt"
import "core:time"
import "core:flags"
import "core:strings"
import "core:path/filepath"
import "core:hash/xxhash"

SIGNATURE :: [4]byte{'R','P','A','K'}
ID_NAME_PREFIX :: "RES_ID"
ID_TYPE :: "RES_ID"

opt: struct {
	resource_dir: string `args:"required,name=dir" usage:"Resource directory"`,
	pkg_name: string `args:"required,name=pkg_name" usage:"Name of the package of the generated .odin file"`,
	out_odin: os.Handle `args:"required,name=out_odin,file=wct" usage:"Output path of generated output .odin file"`,
	out_pak: os.Handle `args:"name=out_pak,file=wct" usage:"Output path of generated output .pak file"`,
}

root_path: string
paths: [dynamic]string
processed_paths: [dynamic]string

main :: proc() {
	flags.parse_or_exit(&opt, os.args)

	root_path, _ = filepath.abs(opt.resource_dir)

	get_paths(root_path)
	generate_odin()
	generate_pak()
}

get_paths :: proc(path: string) {
	dir, dir_err := os.open(path)
	if dir_err != os.ERROR_NONE {
		fmt.printfln("Failed to open resource directory: %s", os.error_string(dir_err))
		return
	}
	defer os.close(dir)

	entries, entries_err := os.read_dir(dir, 0)
	if entries_err != os.ERROR_NONE {
		fmt.printfln("Failed to read resource directory: %s", os.error_string(entries_err))
		return
	}
	defer os.file_info_slice_delete(entries)

	for entry in entries {
		if entry.is_dir {
			get_paths(entry.fullpath)
		} else {
			rel_path, _ := filepath.rel(root_path, entry.fullpath, context.temp_allocator)
			processed_path_bytes := make([]byte, len(rel_path))
			for i in 0..<len(rel_path) {
				switch rel_path[i] {
				case '-', '.', '/', '\\', ' ':
					processed_path_bytes[i] = '_'
				case:
					processed_path_bytes[i] = rel_path[i]
				}
			}
			rel_path_with_root, _ := filepath.to_slash(filepath.join({opt.resource_dir, rel_path}, context.temp_allocator))
			processed_path := strings.clone_from_bytes(processed_path_bytes)
			append(&paths, rel_path_with_root)
			append(&processed_paths, processed_path)
		}
	}
}

generate_odin :: proc() {
	fmt.fprintfln(opt.out_odin, "package %s\n", opt.pkg_name)

	for path in processed_paths {
		upper_path := strings.to_upper(path, context.temp_allocator)
		id := xxhash.XXH64(transmute([]byte)upper_path)
		fmt.fprintfln(opt.out_odin, "%s_%s :: %s(%d)", ID_NAME_PREFIX, upper_path, ID_TYPE, id)
	}

	fmt.fprintln(opt.out_odin, "\nwhen DEV_BUILD {")
	fmt.fprintln(opt.out_odin, "\t@(private=\"file\", rodata)")
	fmt.fprintfln(opt.out_odin, "\tRES__PATHS := [?]struct{{id: %s, path: string}}{{", ID_TYPE)

	for i in 0..<len(processed_paths) {
		upper_path := strings.to_upper(processed_paths[i], context.temp_allocator)
		id := xxhash.XXH64(transmute([]byte)upper_path)
		fmt.fprintfln(opt.out_odin, "\t\t{{%s_%s, \"%s\"}},", ID_NAME_PREFIX, upper_path, paths[i])
	}

	fmt.fprintln(opt.out_odin, "\t}")
	fmt.fprintfln(opt.out_odin, "\tRES__get_file_path :: proc(id: %s) -> string {{", ID_TYPE)
	fmt.fprintln(opt.out_odin, "\t\tfor desc in RES__PATHS {")
	fmt.fprintln(opt.out_odin, "\t\t\tif desc.id == id {")
	fmt.fprintln(opt.out_odin, "\t\t\t\treturn desc.path")
	fmt.fprintln(opt.out_odin, "\t\t\t}")
	fmt.fprintln(opt.out_odin, "\t\t}")
	fmt.fprintln(opt.out_odin, "\t\treturn \"\"")
	fmt.fprintln(opt.out_odin, "\t}")
	fmt.fprintln(opt.out_odin, "}")

	os.close(opt.out_odin)
}

generate_pak :: proc() {
	if opt.out_pak == 0 {
		return
	}

	num_files := len(processed_paths)
	ids := make([]u64, num_files, context.temp_allocator)
	offsets := make([]i64, num_files, context.temp_allocator)
	sizes := make([]i64, num_files, context.temp_allocator)

	// resource data
	for i in 0..<num_files {
		upper_path := strings.to_upper(processed_paths[i], context.temp_allocator)
		ids[i] = xxhash.XXH64(transmute([]byte)upper_path)

		offsets[i], _ = os.seek(opt.out_pak, 0, os.SEEK_CUR)

		data, _ := os.read_entire_file(paths[i])
		os.write(opt.out_pak, data)

		sizes[i] = i64(len(data))
	}

	// resource map
	resource_map_offset, _ := os.seek(opt.out_pak, 0, os.SEEK_CUR)
	for i in 0..<num_files {
		os.write_ptr(opt.out_pak, &ids[i], size_of(ids[i]))
		os.write_ptr(opt.out_pak, &offsets[i], size_of(offsets[i]))
		os.write_ptr(opt.out_pak, &sizes[i], size_of(sizes[i]))
	}

	// footer
	signature := SIGNATURE
	os.write(opt.out_pak, signature[:])
	year, month, day := time.date(time.Time{ODIN_COMPILE_TIMESTAMP})
	packer_version: u32 = u32(year)*10000 + u32(month)*100 + u32(day)
	os.write_ptr(opt.out_pak, &packer_version, size_of(packer_version))
	os.write_ptr(opt.out_pak, &resource_map_offset, size_of(resource_map_offset))
	num_resource_map_entries := u32(num_files)
	os.write_ptr(opt.out_pak, &num_resource_map_entries, size_of(num_resource_map_entries))

	os.close(opt.out_pak)
}
