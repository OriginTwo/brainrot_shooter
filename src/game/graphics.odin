package game

import "core:log"
import "core:os"
import "core:mem"
import "core:slice"
import "core:math"
import "core:math/linalg"

import sdl "vendor:sdl3"
import stbi "vendor:stb/image"

import slog "lib:sokol/log"
import sg "lib:sokol/gfx"

import im "lib:imgui"
import "lib:imgui/imgui_impl_sdl3"
import "lib:imgui/imgui_impl_opengl3"

import "shader"

@(private="file") GFX__SWAPCHAIN_COLOR_FORMAT :: sg.Pixel_Format.RGBA8
@(private="file") GFX__SWAPCHAIN_DEPTH_FORMAT :: sg.Pixel_Format.DEPTH
@(private="file") GFX__SWAPCHAIN_SAMPLE_COUNT :: 1

@(private="file")
GFX__ctx: struct {
	window: ^sdl.Window,
}


///////////////////////////////////////////////////////////
// CORE
///////////////////////////////////////////////////////////
GFX_init :: proc(window: ^sdl.Window, gl_ctx: sdl.GLContext) {
	GFX__ctx.window = window

	sg.setup({
		environment = {
			defaults = {
				color_format = GFX__SWAPCHAIN_COLOR_FORMAT,
				depth_format = GFX__SWAPCHAIN_DEPTH_FORMAT,
				sample_count = GFX__SWAPCHAIN_SAMPLE_COUNT,
			},
		},
		logger = {func = slog.func},
	})
	assert(sg.isvalid())

	when DEV_BUILD {
		im.CHECKVERSION()
		im.CreateContext()
		io := im.GetIO()
		io.ConfigFlags += {.NavEnableKeyboard, .DockingEnable}
		io.IniFilename = nil
		io.LogFilename = nil

		im.StyleColorsDark()

		imgui_impl_sdl3.InitForOpenGL(window, gl_ctx)
		imgui_impl_opengl3.Init(nil)
	}
}

GFX_uninit :: proc() {
	when DEV_BUILD {
		imgui_impl_opengl3.Shutdown()
		imgui_impl_sdl3.Shutdown()
		im.DestroyContext()
	}

	sg.shutdown()
	GFX__ctx = {}
}

GFX_begin_frame :: proc() {
	when DEV_BUILD {
		imgui_impl_opengl3.NewFrame()
		imgui_impl_sdl3.NewFrame()
		im.NewFrame()
	}
}

GFX_end_frame :: proc() {
	when DEV_BUILD {
		im.Render()
		imgui_impl_opengl3.RenderDrawData(im.GetDrawData())
	}

	sdl.GL_SwapWindow(GFX__ctx.window)
}

GFX_get_swapchain :: proc() -> sg.Swapchain {
	win_width: i32
	win_height: i32
	sdl.GetWindowSize(GFX__ctx.window, &win_width, &win_height)
	return {
		width = win_width,
		height = win_height,
		sample_count = GFX__SWAPCHAIN_SAMPLE_COUNT,
		color_format = GFX__SWAPCHAIN_COLOR_FORMAT,
		depth_format = GFX__SWAPCHAIN_DEPTH_FORMAT,
		gl = {
			framebuffer = 0,
		},
	}
}

GFX_clear_background :: proc(clear_color: M_FColor) {
	sg.begin_pass({
		action = {
			colors = {0 = {
				load_action = .CLEAR,
				clear_value = transmute(sg.Color)clear_color,
			}},
			depth = {
				load_action = .CLEAR,
				clear_value = 1.0,
			},
		},
		swapchain = GFX_get_swapchain(),
	})
	sg.end_pass()
}


///////////////////////////////////////////////////////////
// IMAGE
///////////////////////////////////////////////////////////
GFX_Image :: struct {
	pixels: []M_Color,
	width: int,
	height: int,
}

GFX_load_image_from_file :: proc(img: ^GFX_Image, path: string) {
	data, data_ok := os.read_entire_file_from_filename(path, context.temp_allocator)
	if !data_ok {
		log.warnf("IMG: failed to load image from file '%s'", path)
		return
	}
	GFX_load_image_from_memory(img, data)
}

GFX_load_image_from_memory :: proc(img: ^GFX_Image, data: []byte) {
	width: i32
	height: i32
	pixels := stbi.load_from_memory(raw_data(data), i32(len(data)), &width, &height, nil, 4)
	if pixels == nil {
		log.warnf("IMG: failed to load image from memory: '%s'", stbi.failure_reason())
		return
	}
	defer stbi.image_free(pixels)

	img.width = int(width)
	img.height = int(height)
	img.pixels = slice.clone(slice.from_ptr(transmute(^M_Color)pixels, img.width*img.height))
}

GFX_load_image_from_color :: proc(img: ^GFX_Image, width, height: int, color: M_Color) {
	img.width = width
	img.height = height
	img.pixels = make([]M_Color, width*height)
	for &pixel in img.pixels {
		pixel = color
	}
}

GFX_unload_image :: proc(img: ^GFX_Image) {
	delete(img.pixels)
	img^ = {}
}

GFX_clone_image :: proc(dest: ^GFX_Image, source: GFX_Image) {
	if source.width > 0 && source.height > 0 && source.pixels != nil {
		dest.width = source.width
		dest.height = source.height
		dest.pixels = make([]M_Color, dest.width*dest.height)
		copy(dest.pixels, source.pixels)
	}
}

GFX_set_image_color :: proc(img: GFX_Image, x, y: int, color: M_Color) {
	if x >= 0 && x < img.width && y >= 0 && y < img.height {
		img.pixels[y*img.width + x] = color
	}
}

GFX_get_image_color :: proc(img: GFX_Image, x, y: int) -> M_Color {
	result: M_Color
	if x >= 0 && x < img.width && y >= 0 && y < img.height {
		result = img.pixels[y*img.width + x]
	}
	return result
}

GFX_replace_image_color :: proc(img: GFX_Image, old, new: M_Color) {
	if old == new {
		return
	}

	for &pixel in img.pixels {
		if pixel == old {
			pixel = new
		}
	}
}


///////////////////////////////////////////////////////////
// FONT
///////////////////////////////////////////////////////////
GFX_Font_Glyph_Info :: struct {
	offset_x: f32,
	offset_y: f32,
	advance_x: f32,
}

GFX_Font :: struct {
	base_size: int,
	glyph_count: int,
	texture: sg.Image,
	sampler: sg.Sampler,
	sources: []M_Rect,
	glyphs: []GFX_Font_Glyph_Info,
}

GFX_load_font_from_image :: proc(font: ^GFX_Font, image: GFX_Image) {
	font.base_size = image.height
	font.glyph_count = 95

	{
		img_copy: GFX_Image
		GFX_clone_image(&img_copy, image)
		GFX_replace_image_color(img_copy, M_COLOR_MAGENTA, M_COLOR_BLANK)
		font.texture = sg.make_image({
			type = ._2D,
			width = i32(img_copy.width),
			height = i32(img_copy.height),
			num_slices = 1,
			num_mipmaps = 1,
			usage = .IMMUTABLE,
			pixel_format = .RGBA8,
			sample_count = 1,
			data = {subimage = {0 = {0 = {
				ptr = raw_data(img_copy.pixels),
				size = len(img_copy.pixels)*size_of(img_copy.pixels[0]),
			}}}},
		})
		font.sampler = sg.make_sampler({
			min_filter = .NEAREST,
			mag_filter = .NEAREST,
			mipmap_filter = .NEAREST,
			wrap_u = .CLAMP_TO_EDGE,
			wrap_v = .CLAMP_TO_EDGE,
		})
		GFX_unload_image(&img_copy)
	}

	font.sources = make([]M_Rect, font.glyph_count)
	font.glyphs = make([]GFX_Font_Glyph_Info, font.glyph_count)

	state: enum{SKIP, SCAN} = .SKIP
	x_start: int
	curr_glyph: int

	for x in 0..<image.width {
		c := GFX_get_image_color(image, x, 0)
		switch state {
		case .SKIP:
			if c != M_COLOR_MAGENTA {
				x_start = x
				state = .SCAN
			}

		case .SCAN:
			if c == M_COLOR_MAGENTA {
				width := x - x_start
				source := M_Rect{
					f32(x_start),
					0.0,
					f32(width),
					f32(image.height),
				}

				font.sources[curr_glyph] = source
				font.glyphs[curr_glyph] = {
					offset_x = 0,
					offset_y = 0,
					advance_x = f32(width),
				}
				curr_glyph += 1
				state = .SKIP
			}
		}
	}
}

GFX_unload_font :: proc(font: ^GFX_Font) {
	sg.destroy_sampler(font.sampler)
	sg.destroy_image(font.texture)
	delete(font.sources)
	delete(font.glyphs)
	font^ = {}
}


///////////////////////////////////////////////////////////
// CAMERA
///////////////////////////////////////////////////////////
GFX_Camera :: struct {
	position: M_Vec3f32,
	offset: M_Vec3f32,  // for head bobbing
	yaw: f32,
	pitch: f32,
	roll: f32,
	fovy: f32,
}

GFX_get_camera_matrix :: proc(cam: GFX_Camera) -> linalg.Matrix4f32 {
	// // https://en.wikipedia.org/wiki/Rotation_matrix#General_3D_rotations
	// // extrinsics rotation

	// view = [
	// 	[  right.x,   right.y,   right.z, -dot(  right, pos)]
	// 	[     up.x,      up.y,      up.z, -dot(     up, pos)]
	// 	[forward.x, forward.y, forward.z, -dot(forward, pos)]
	// 	[        0,         0,         0,          1        ]
	// ]

	pos := cam.position + cam.offset

	// view = [pos][roll][yaw][pitch]
	mat := linalg.MATRIX4F32_IDENTITY
	mat *= linalg.matrix4_rotate_f32(cam.pitch*math.RAD_PER_DEG, {1.0, 0.0, 0.0})
	mat *= linalg.matrix4_rotate_f32(cam.yaw*math.RAD_PER_DEG, {0.0, 1.0, 0.0})
	mat *= linalg.matrix4_rotate_f32(cam.roll*math.RAD_PER_DEG, {0.0, 0.0, 1.0})
	mat *= linalg.matrix4_translate_f32(-pos)

	return mat
}

GFX_get_camera_forward_up_right :: proc(cam: GFX_Camera) -> (forward, up, right: M_Vec3f32) {
	mat := GFX_get_camera_matrix(cam)
	forward = {mat[2, 0], mat[2, 1], mat[2, 2]}
	up = {mat[1, 0], mat[1, 1], mat[1, 2]}
	right = {mat[0, 0], mat[0, 1], mat[0, 2]}
	return
}

GFX_get_camera_forward_up_right_from_matrix :: proc(mat: linalg.Matrix4f32) -> (forward, up, right: M_Vec3f32) {
	forward = {mat[2, 0], mat[2, 1], mat[2, 2]}
	up = {mat[1, 0], mat[1, 1], mat[1, 2]}
	right = {mat[0, 0], mat[0, 1], mat[0, 2]}
	return
}


///////////////////////////////////////////////////////////
// GENERIC RENDERER 2D
///////////////////////////////////////////////////////////
GFX_2D_Renderer :: struct {
	vertex_pos_buffer: sg.Buffer,
	vertex_uv_buffer: sg.Buffer,
	vertex_color_buffer: sg.Buffer,
	index_buffer: sg.Buffer,
	shader: sg.Shader,
	pipeline: sg.Pipeline,

	white_texture: sg.Image,
	default_sampler: sg.Sampler,

	num_vertices: u32,
	vertex_positions: []M_Vec2f32,
	vertex_uvs: []M_Vec2f32,
	vertex_colors: []M_FColor,

	num_indices: u32,
	indices: []GFX__2D_Index,

	num_batches: int,
	batches: []GFX__2D_Batch,

	layer: int,
}

GFX_create_2d_renderer :: proc(
	ren: ^GFX_2D_Renderer,
	max_vertex: uint = 32000,
	max_index: uint = 48000,
	max_batch: uint = 128,
) {
	// buffers
	{
		ren.vertex_pos_buffer = sg.make_buffer({
			size = max_vertex*size_of(M_Vec2f32),
			type = .VERTEXBUFFER,
			usage = .STREAM,
		})

		ren.vertex_uv_buffer = sg.make_buffer({
			size = max_vertex*size_of(M_Vec2f32),
			type = .VERTEXBUFFER,
			usage = .STREAM,
		})

		ren.vertex_color_buffer = sg.make_buffer({
			size = max_vertex*size_of(M_FColor),
			type = .VERTEXBUFFER,
			usage = .STREAM,
		})

		ren.index_buffer = sg.make_buffer({
			size = max_index*size_of(GFX__2D_Index),
			type = .INDEXBUFFER,
			usage = .STREAM,
		})
	}

	// pipeline
	{
		ren.shader = sg.make_shader(shader.generic_2d_shader_desc(sg.query_backend()))

		ren.pipeline = sg.make_pipeline({
			shader = ren.shader,
			layout = {
				buffers = {
					shader.ATTR_generic_2d_generic_2d_A_position = {stride = size_of(M_Vec2f32)},
					shader.ATTR_generic_2d_generic_2d_A_uv = {stride = size_of(M_Vec2f32)},
					shader.ATTR_generic_2d_generic_2d_A_color = {stride = size_of(M_FColor)},
				},
				attrs = {
					shader.ATTR_generic_2d_generic_2d_A_position = {
						buffer_index = shader.ATTR_generic_2d_generic_2d_A_position,
						format = .FLOAT2,
					},
					shader.ATTR_generic_2d_generic_2d_A_uv = {
						buffer_index = shader.ATTR_generic_2d_generic_2d_A_uv,
						format = .FLOAT2,
					},
					shader.ATTR_generic_2d_generic_2d_A_color = {
						buffer_index = shader.ATTR_generic_2d_generic_2d_A_color,
						format = .FLOAT4,
					},
				},
			},
			color_count = 1,
			colors = {0 = {blend = {
				enabled = true,
				src_factor_rgb = .SRC_ALPHA,
				dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
				op_rgb = .ADD,
			}}},
			primitive_type = .TRIANGLES,
			index_type = .UINT16 when size_of(GFX__2D_Index) == 2 else .UINT32,
			sample_count = 1,
		})
	}

	// white texture
	{
		white: u32 = 0xffffffff
		ren.white_texture = sg.make_image({
			type = ._2D,
			width = 1,
			height = 1,
			num_slices = 1,
			num_mipmaps = 1,
			usage = .IMMUTABLE,
			pixel_format = .RGBA8,
			sample_count = 1,
			data = {
				subimage = {0 = {0 = {
					ptr = &white,
					size = size_of(white),
				}}},
			},
		})
		ren.default_sampler = sg.make_sampler({
			min_filter = .NEAREST,
			mag_filter = .NEAREST,
			wrap_u = .CLAMP_TO_EDGE,
			wrap_v = .CLAMP_TO_EDGE,
		})
	}

	ren.vertex_positions = make([]M_Vec2f32, max_vertex)
	ren.vertex_uvs = make([]M_Vec2f32, max_vertex)
	ren.vertex_colors = make([]M_FColor, max_vertex)
	ren.indices = make([]GFX__2D_Index, max_index)

	ren.batches = make([]GFX__2D_Batch, max_batch)
}

GFX_destroy_2d_renderer :: proc(ren: ^GFX_2D_Renderer) {
	sg.destroy_buffer(ren.vertex_pos_buffer)
	sg.destroy_buffer(ren.vertex_uv_buffer)
	sg.destroy_buffer(ren.vertex_color_buffer)
	sg.destroy_buffer(ren.index_buffer)
	sg.destroy_shader(ren.shader)
	sg.destroy_pipeline(ren.pipeline)
	sg.destroy_image(ren.white_texture)
	sg.destroy_sampler(ren.default_sampler)

	delete(ren.vertex_positions)
	delete(ren.vertex_uvs)
	delete(ren.vertex_colors)
	delete(ren.indices)
	delete(ren.batches)

	ren^ = {}
}

GFX_begin_2d_renderer :: proc(ren: ^GFX_2D_Renderer) {
	ren.num_vertices = 0
	ren.num_indices = 0
	ren.num_batches = 0
	ren.batches[0] = {}
	ren.layer = 0
}

GFX_end_2d_renderer :: proc(ren: ^GFX_2D_Renderer) {
	ren.batches[ren.num_batches].num_indices = ren.num_indices - ren.batches[ren.num_batches].first_index
	ren.num_batches += 1

	win_width: i32
	win_height: i32
	sdl.GetWindowSize(GFX__ctx.window, &win_width, &win_height)
	proj := linalg.matrix_ortho3d(0.0, f32(win_width), f32(win_height), 0.0, -1.0, 1.0)

	sg.update_buffer(
		ren.vertex_pos_buffer,
		{raw_data(ren.vertex_positions), uint(ren.num_vertices)*size_of(ren.vertex_positions[0])},
	)
	sg.update_buffer(
		ren.vertex_uv_buffer,
		{raw_data(ren.vertex_uvs), uint(ren.num_vertices)*size_of(ren.vertex_uvs[0])},
	)
	sg.update_buffer(
		ren.vertex_color_buffer,
		{raw_data(ren.vertex_colors), uint(ren.num_vertices)*size_of(ren.vertex_colors[0])},
	)
	sg.update_buffer(
		ren.index_buffer,
		{raw_data(ren.indices), uint(ren.num_indices)*size_of(ren.indices[0])},
	)

	sg.begin_pass({
		action = {colors = {0 = {
			load_action = .DONTCARE,
		}}},
		swapchain = GFX_get_swapchain(),
	})
	sg.apply_pipeline(ren.pipeline)

	batches := ren.batches[1:ren.num_batches]
	slice.sort_by_cmp(batches, proc(i, j: GFX__2D_Batch) -> slice.Ordering {
		if i.layer < j.layer {
			return .Less
		} else if i.layer == j.layer {
			return .Equal
		} else {
			return .Greater
		}
	})

	// first batch is always empty
	for batch in batches {
		sg.apply_bindings({
			vertex_buffers = {
				shader.ATTR_generic_2d_generic_2d_A_position = ren.vertex_pos_buffer,
				shader.ATTR_generic_2d_generic_2d_A_uv = ren.vertex_uv_buffer,
				shader.ATTR_generic_2d_generic_2d_A_color = ren.vertex_color_buffer,
			},
			index_buffer = ren.index_buffer,
			images = {shader.IMG_generic_2d_U_texture = batch.texture},
			samplers = {shader.SMP_generic_2d_U_sampler = batch.sampler},
		})
		uniform := shader.Generic_2d_Vertex_Param{
			proj = linalg.matrix_flatten(proj),
		}
		sg.apply_uniforms(shader.UB_generic_2d_Vertex_Param, {&uniform, size_of(uniform)})
		sg.draw(batch.first_index, batch.num_indices, 1)
	}

	sg.end_pass()
}

GFX_get_default_2d_sampler :: proc(ren: GFX_2D_Renderer) -> sg.Sampler {
	return ren.default_sampler
}

GFX_set_2d_layer :: proc(ren: ^GFX_2D_Renderer, layer: int) {
	ren.layer = layer
}

GFX_draw_2d_triangle :: proc(
	ren: ^GFX_2D_Renderer,
	p1: M_Vec2f32, c1: M_Color,
	p2: M_Vec2f32, c2: M_Color,
	p3: M_Vec2f32, c3: M_Color,
) {
	GFX__new_2d_batch_if_needed(ren, ren.white_texture, ren.default_sampler)

	ren.vertex_positions[ren.num_vertices] = p1
	ren.vertex_uvs[ren.num_vertices] = {0.0, 0.0}
	ren.vertex_colors[ren.num_vertices] = M_frgba_from_urgba(c1)
	ren.indices[ren.num_indices] = GFX__2D_Index(ren.num_vertices)
	ren.num_vertices += 1
	ren.num_indices += 1

	ren.vertex_positions[ren.num_vertices] = p2
	ren.vertex_uvs[ren.num_vertices] = {1.0, 0.0}
	ren.vertex_colors[ren.num_vertices] = M_frgba_from_urgba(c2)
	ren.indices[ren.num_indices] = GFX__2D_Index(ren.num_vertices)
	ren.num_vertices += 1
	ren.num_indices += 1

	ren.vertex_positions[ren.num_vertices] = p3
	ren.vertex_uvs[ren.num_vertices] = {1.0, 1.0}
	ren.vertex_colors[ren.num_vertices] = M_frgba_from_urgba(c3)
	ren.indices[ren.num_indices] = GFX__2D_Index(ren.num_vertices)
	ren.num_vertices += 1
	ren.num_indices += 1
}

GFX_draw_2d_rect :: proc(
	ren: ^GFX_2D_Renderer,
	rect: M_Rect,
	color: M_Color,
) {
	GFX__new_2d_batch_if_needed(ren, ren.white_texture, ren.default_sampler)

	col := M_frgba_from_urgba(color)
	start_index := GFX__2D_Index(ren.num_vertices)

	ren.vertex_positions[ren.num_vertices] = {rect.x, rect.y}
	ren.vertex_uvs[ren.num_vertices] = {0.0, 0.0}
	ren.vertex_colors[ren.num_vertices] = col
	ren.num_vertices += 1

	ren.vertex_positions[ren.num_vertices] = {rect.x + rect.width, rect.y}
	ren.vertex_uvs[ren.num_vertices] = {1.0, 0.0}
	ren.vertex_colors[ren.num_vertices] = col
	ren.num_vertices += 1

	ren.vertex_positions[ren.num_vertices] = {rect.x + rect.width, rect.y + rect.height}
	ren.vertex_uvs[ren.num_vertices] = {1.0, 1.0}
	ren.vertex_colors[ren.num_vertices] = col
	ren.num_vertices += 1

	ren.vertex_positions[ren.num_vertices] = {rect.x, rect.y + rect.height}
	ren.vertex_uvs[ren.num_vertices] = {0.0, 1.0}
	ren.vertex_colors[ren.num_vertices] = col
	ren.num_vertices += 1

	ren.indices[ren.num_indices + 0] = start_index + 0
	ren.indices[ren.num_indices + 1] = start_index + 1
	ren.indices[ren.num_indices + 2] = start_index + 2
	ren.indices[ren.num_indices + 3] = start_index + 0
	ren.indices[ren.num_indices + 4] = start_index + 2
	ren.indices[ren.num_indices + 5] = start_index + 3
	ren.num_indices += 6
}

GFX_draw_2d_rect_line :: proc(
	ren: ^GFX_2D_Renderer,
	rect: M_Rect,
	color: M_Color,
	thick: f32 = 2.0,
) {
	GFX_draw_2d_rect(ren, {rect.x - thick/2.0, rect.y - thick/2.0, rect.width + thick, thick}, color)
	GFX_draw_2d_rect(ren, {rect.x - thick/2.0, rect.y + rect.height - thick/2.0, rect.width + thick, thick}, color)
	GFX_draw_2d_rect(ren, {rect.x - thick/2.0, rect.y + thick/2.0, thick, rect.height - thick}, color)
	GFX_draw_2d_rect(ren, {rect.x + rect.width - thick/2.0, rect.y + thick/2.0, thick, rect.height - thick}, color)
}

GFX_draw_2d_texture :: proc(
	ren: ^GFX_2D_Renderer,
	texture: sg.Image,
	sampler: sg.Sampler,
	source: M_Rect,
	dest: M_Rect,
	tint: M_Color,
) {
	GFX__new_2d_batch_if_needed(ren, texture, sampler)

	col := M_frgba_from_urgba(tint)
	start_index := GFX__2D_Index(ren.num_vertices)

	tex_width := f32(sg.query_image_width(texture))
	tex_height := f32(sg.query_image_height(texture))

	src_min := M_Vec2f32{
		source.x/tex_width,
		source.y/tex_height,
	}
	src_max := M_Vec2f32{
		(source.x + source.width)/tex_width,
		(source.y + source.height)/tex_height,
	}

	ren.vertex_positions[ren.num_vertices] = {dest.x, dest.y}
	ren.vertex_uvs[ren.num_vertices] = {src_min.x, src_min.y}
	ren.vertex_colors[ren.num_vertices] = col
	ren.num_vertices += 1

	ren.vertex_positions[ren.num_vertices] = {dest.x + dest.width, dest.y}
	ren.vertex_uvs[ren.num_vertices] = {src_max.x, src_min.y}
	ren.vertex_colors[ren.num_vertices] = col
	ren.num_vertices += 1

	ren.vertex_positions[ren.num_vertices] = {dest.x + dest.width, dest.y + dest.height}
	ren.vertex_uvs[ren.num_vertices] = {src_max.x, src_max.y}
	ren.vertex_colors[ren.num_vertices] = col
	ren.num_vertices += 1

	ren.vertex_positions[ren.num_vertices] = {dest.x, dest.y + dest.height}
	ren.vertex_uvs[ren.num_vertices] = {src_min.x, src_max.y}
	ren.vertex_colors[ren.num_vertices] = col
	ren.num_vertices += 1

	ren.indices[ren.num_indices + 0] = start_index + 0
	ren.indices[ren.num_indices + 1] = start_index + 1
	ren.indices[ren.num_indices + 2] = start_index + 2
	ren.indices[ren.num_indices + 3] = start_index + 0
	ren.indices[ren.num_indices + 4] = start_index + 2
	ren.indices[ren.num_indices + 5] = start_index + 3
	ren.num_indices += 6
}

GFX_draw_2d_string :: proc(
	ren: ^GFX_2D_Renderer,
	font: GFX_Font,
	str: string,
	pos: M_Vec2f32,
	color: M_Color,
	scale: f32,
) {
	x := pos.x
	y := pos.y

	for i in 0..<len(str) {
		ch := str[i]
		src := font.sources[ch - 32]
		info := font.glyphs[ch - 32]

		dst := M_Rect{
			x + info.offset_x*scale,
			y + info.offset_y*scale,
			src.width*scale,
			src.height*scale,
		}

		GFX_draw_2d_texture(ren, font.texture, font.sampler, src, dst, color)
		x += info.advance_x*scale
	}
}



@(private="file")
GFX__2D_Index :: u16

@(private="file")
GFX__2D_Batch :: struct {
	first_index: u32,
	num_indices: u32,
	texture: sg.Image,
	sampler: sg.Sampler,
	layer: int,
}

@(private="file")
GFX__new_2d_batch_if_needed :: proc(ren: ^GFX_2D_Renderer, tex: sg.Image, smp: sg.Sampler) {
	curr_batch := &ren.batches[ren.num_batches]
	if curr_batch.texture != tex || curr_batch.sampler != smp || curr_batch.layer != ren.layer {
		curr_batch.num_indices = ren.num_indices - curr_batch.first_index
		ren.num_batches += 1
		curr_batch = &ren.batches[ren.num_batches]
		curr_batch.first_index = ren.num_indices
		curr_batch.texture = tex
		curr_batch.sampler = smp
		curr_batch.layer = ren.layer
	}
}


///////////////////////////////////////////////////////////
// 3D RENDERER
///////////////////////////////////////////////////////////
GFX_3D_Renderer :: struct {
	vertex_pos_buffer: sg.Buffer,
	vertex_normal_buffer: sg.Buffer,
	vertex_uv_buffer: sg.Buffer,
	vertex_color_buffer: sg.Buffer,
	index_buffer: sg.Buffer,
	shader: sg.Shader,
	color_texture: sg.Image,
	bright_color_texture: sg.Image,
	depth_texture: sg.Image,
	attachments: sg.Attachments,
	normal_pipeline: sg.Pipeline,
	decal_pipeline: sg.Pipeline,

	white_texture: sg.Image,
	default_sampler: sg.Sampler,

	num_vertices: u32,
	vertex_positions: []M_Vec3f32,
	vertex_normals: []M_Vec3f32,
	vertex_uvs: []M_Vec2f32,
	vertex_colors: []M_FColor,

	num_indices: u32,
	indices: []GFX__3D_Index,

	num_batches: int,
	batches: []GFX__3D_Batch,

	fog_density: f32,
	fog_gradient: f32,
	fog_color: M_Vec3f32,

	num_lights: int,
	lights: [GFX__MAX_3D_LIGHT]GFX_3D_Light,

	camera: GFX_Camera,
	view_mat: linalg.Matrix4f32,
	proj_mat: linalg.Matrix4f32,
}

GFX_3D_Light :: struct {
	position: M_Vec3f32,
	intensity: f32,
	radius: f32,
	color: M_Vec3f32,
	falloff: f32,
}

GFX_3D_DEFAULT_LIGHT :: GFX_3D_Light{
	intensity = 1.0,
	radius = 1.0,
	color = {1.0, 1.0, 1.0},
	falloff = 1.0,
}

GFX_create_3d_renderer :: proc(
	ren: ^GFX_3D_Renderer,
	width: int,
	height: int,
	max_vertex: uint = 32000,
	max_index: uint = 48000,
	max_batch: uint = 128,
) {
	// buffers
	{
		ren.vertex_pos_buffer = sg.make_buffer({
			size = max_vertex*size_of(M_Vec3f32),
			type = .VERTEXBUFFER,
			usage = .STREAM,
		})

		ren.vertex_normal_buffer = sg.make_buffer({
			size = max_vertex*size_of(M_Vec3f32),
			type = .VERTEXBUFFER,
			usage = .STREAM,
		})

		ren.vertex_uv_buffer = sg.make_buffer({
			size = max_vertex*size_of(M_Vec2f32),
			type = .VERTEXBUFFER,
			usage = .STREAM,
		})

		ren.vertex_color_buffer = sg.make_buffer({
			size = max_vertex*size_of(M_FColor),
			type = .VERTEXBUFFER,
			usage = .STREAM,
		})

		ren.index_buffer = sg.make_buffer({
			size = max_index*size_of(GFX__3D_Index),
			type = .INDEXBUFFER,
			usage = .STREAM,
		})
	}

	// attachments
	{
		ren.color_texture = sg.make_image({
			render_target = true,
			width = i32(width),
			height = i32(height),
			pixel_format = .RG11B10F,
			sample_count = 1,
		})
		ren.bright_color_texture = sg.make_image({
			render_target = true,
			width = i32(width),
			height = i32(height),
			pixel_format = .RG11B10F,
			sample_count = 1,
		})
		ren.depth_texture = sg.make_image({
			render_target = true,
			width = i32(width),
			height = i32(height),
			pixel_format = .DEPTH,
			sample_count = 1,
		})
		ren.attachments = sg.make_attachments({
			colors = {
				0 = {image = ren.color_texture},
				1 = {image = ren.bright_color_texture},
			},
			depth_stencil = {
				image = ren.depth_texture,
			},
		})
	}

	// pipeline
	{
		ren.shader = sg.make_shader(shader.generic_3d_shader_desc(sg.query_backend()))

		ren.normal_pipeline = sg.make_pipeline({
			shader = ren.shader,
			layout = {
				buffers = {
					0 = {stride = size_of(M_Vec3f32)},
					1 = {stride = size_of(M_Vec3f32)},
					2 = {stride = size_of(M_Vec2f32)},
					3 = {stride = size_of(M_FColor)},
				},
				attrs = {
					shader.ATTR_generic_3d_generic_3d_A_position = {
						buffer_index = shader.ATTR_generic_3d_generic_3d_A_position,
						format = .FLOAT3,
					},
					shader.ATTR_generic_3d_generic_3d_A_normal = {
						buffer_index = shader.ATTR_generic_3d_generic_3d_A_normal,
						format = .FLOAT3,
					},
					shader.ATTR_generic_3d_generic_3d_A_uv = {
						buffer_index = shader.ATTR_generic_3d_generic_3d_A_uv,
						format = .FLOAT2,
					},
					shader.ATTR_generic_3d_generic_3d_A_color = {
						buffer_index = shader.ATTR_generic_3d_generic_3d_A_color,
						format = .FLOAT4,
					},
				},
			},
			depth = {
				pixel_format = sg.query_image_pixelformat(ren.depth_texture),
				compare = .LESS,
				write_enabled = true,
			},
			color_count = 2,
			colors = {
				0 = {
					pixel_format = sg.query_image_pixelformat(ren.color_texture),
					blend = {
						enabled = true,
						src_factor_rgb = .SRC_ALPHA,
						dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
						op_rgb = .ADD,
					},
				},
				1 = {
					pixel_format = sg.query_image_pixelformat(ren.bright_color_texture),
					blend = {
						enabled = true,
						src_factor_rgb = .SRC_ALPHA,
						dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
						op_rgb = .ADD,
					},
				},
			},
			primitive_type = .TRIANGLES,
			index_type = .UINT16 when size_of(GFX__3D_Index) == 2 else .UINT32,
			cull_mode = .BACK,
			face_winding = .CW,
			sample_count = 1,
		})

		ren.decal_pipeline = sg.make_pipeline({
			shader = ren.shader,
			layout = {
				buffers = {
					shader.ATTR_generic_3d_generic_3d_A_position = {stride = size_of(M_Vec3f32)},
					shader.ATTR_generic_3d_generic_3d_A_normal = {stride = size_of(M_Vec3f32)},
					shader.ATTR_generic_3d_generic_3d_A_uv = {stride = size_of(M_Vec2f32)},
					shader.ATTR_generic_3d_generic_3d_A_color = {stride = size_of(M_FColor)},
				},
				attrs = {
					shader.ATTR_generic_3d_generic_3d_A_position = {
						buffer_index = shader.ATTR_generic_3d_generic_3d_A_position,
						format = .FLOAT3,
					},
					shader.ATTR_generic_3d_generic_3d_A_normal = {
						buffer_index = shader.ATTR_generic_3d_generic_3d_A_normal,
						format = .FLOAT3,
					},
					shader.ATTR_generic_3d_generic_3d_A_uv = {
						buffer_index = shader.ATTR_generic_3d_generic_3d_A_uv,
						format = .FLOAT2,
					},
					shader.ATTR_generic_3d_generic_3d_A_color = {
						buffer_index = shader.ATTR_generic_3d_generic_3d_A_color,
						format = .FLOAT4,
					},
				},
			},
			depth = {
				pixel_format = sg.query_image_pixelformat(ren.depth_texture),
				compare = .LESS_EQUAL,
				write_enabled = false,
				bias = -1.0,
				bias_slope_scale = -1.0,
			},
			color_count = 2,
			colors = {
				0 = {
					pixel_format = sg.query_image_pixelformat(ren.color_texture),
					blend = {
						enabled = true,
						src_factor_rgb = .SRC_ALPHA,
						dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
						op_rgb = .ADD,
					},
				},
				1 = {
					pixel_format = sg.query_image_pixelformat(ren.bright_color_texture),
					blend = {
						enabled = true,
						src_factor_rgb = .SRC_ALPHA,
						dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
						op_rgb = .ADD,
					},
				},
			},
			primitive_type = .TRIANGLES,
			index_type = .UINT16 when size_of(GFX__3D_Index) == 2 else .UINT32,
			cull_mode = .BACK,
			face_winding = .CW,
			sample_count = 1,
		})
	}

	// white texture
	{
		white: u32 = 0xffffffff
		ren.white_texture = sg.make_image({
			type = ._2D,
			width = 1,
			height = 1,
			num_slices = 1,
			num_mipmaps = 1,
			usage = .IMMUTABLE,
			pixel_format = .RGBA8,
			sample_count = 1,
			data = {
				subimage = {0 = {0 = {
					ptr = &white,
					size = size_of(white),
				}}},
			},
		})
		ren.default_sampler = sg.make_sampler({
			min_filter = .NEAREST,
			mag_filter = .NEAREST,
			wrap_u = .CLAMP_TO_EDGE,
			wrap_v = .CLAMP_TO_EDGE,
		})
	}

	ren.vertex_positions = make([]M_Vec3f32, max_vertex)
	ren.vertex_normals = make([]M_Vec3f32, max_vertex)
	ren.vertex_uvs = make([]M_Vec2f32, max_vertex)
	ren.vertex_colors = make([]M_FColor, max_vertex)
	ren.indices = make([]GFX__3D_Index, max_index)
	ren.batches = make([]GFX__3D_Batch, max_batch)

	// default fog
	ren.fog_density = 0.025
	ren.fog_gradient = 2.0
	ren.fog_color = {0.0, 0.0, 0.0}
}

GFX_destroy_3d_renderer :: proc(ren: ^GFX_3D_Renderer) {
	sg.destroy_buffer(ren.vertex_pos_buffer)
	sg.destroy_buffer(ren.vertex_uv_buffer)
	sg.destroy_buffer(ren.vertex_color_buffer)
	sg.destroy_buffer(ren.index_buffer)
	sg.destroy_shader(ren.shader)
	sg.destroy_image(ren.color_texture)
	sg.destroy_image(ren.bright_color_texture)
	sg.destroy_image(ren.depth_texture)
	sg.destroy_attachments(ren.attachments)
	sg.destroy_pipeline(ren.normal_pipeline)
	sg.destroy_pipeline(ren.decal_pipeline)
	sg.destroy_image(ren.white_texture)
	sg.destroy_sampler(ren.default_sampler)

	delete(ren.vertex_positions)
	delete(ren.vertex_normals)
	delete(ren.vertex_uvs)
	delete(ren.vertex_colors)
	delete(ren.indices)
	delete(ren.batches)

	ren^ = {}
}

GFX_begin_3d_renderer :: proc(ren: ^GFX_3D_Renderer, cam: GFX_Camera) {
	ren.num_vertices = 0
	ren.num_indices = 0
	ren.num_batches = 0
	ren.batches[0] = {}
	ren.num_lights = 0
	ren.camera = cam
	ren.view_mat = GFX_get_camera_matrix(ren.camera)
	// TODO: unhard-code aspect ratio
	ren.proj_mat = linalg.matrix4_perspective_f32(ren.camera.fovy, 16.0/9.0, 0.3, 100.0)
}

GFX_end_3d_renderer :: proc(ren: ^GFX_3D_Renderer) {
	ren.batches[ren.num_batches].num_indices = ren.num_indices - ren.batches[ren.num_batches].first_index
	ren.num_batches += 1

	close_lights: [GFX__MAX_3D_LIGHT_IN_SHADER]GFX_3D_Light
	{
		temp_lights := make([]GFX_3D_Light, ren.num_lights, context.temp_allocator)
		copy(temp_lights, ren.lights[:ren.num_lights])
		for &light in temp_lights {
			light.position -= ren.camera.position
		}

		slice.sort_by_cmp(temp_lights, proc(i, j: GFX_3D_Light) -> slice.Ordering {
			dist_i_sqr := linalg.length2(i.position)
			dist_j_sqr := linalg.length2(j.position)
			if dist_i_sqr < dist_j_sqr {
				return .Less
			} else if dist_i_sqr == dist_j_sqr {
				return .Equal
			} else {
				return.Greater
			}
		})

		for i in 0..<min(len(close_lights), len(temp_lights)) {
			close_lights[i] = temp_lights[i]
			close_lights[i].position += ren.camera.position
		}
	}

	vertex_param := shader.Generic_3d_Vertex_Param{
		view = linalg.matrix_flatten(ren.view_mat),
		proj = linalg.matrix_flatten(ren.proj_mat),
	}

	for i in 0..<ren.num_lights {
		light := close_lights[i]
		vertex_param.light_data[i] = {light.position.x, light.position.y, light.position.z, 0.0}
	}

	fragment_param := shader.Generic_3d_Fragment_Param{
		fog_density = ren.fog_density,
		fog_gradient = ren.fog_gradient,
		fog_color = ren.fog_color,
		light_count = i32(ren.num_lights),
	}

	for i in 0..<ren.num_lights {
		light := close_lights[i]
		fragment_param.light_data1[i] = {light.color.r, light.color.g, light.color.b, light.radius}
		fragment_param.light_data2[i] = {light.intensity, light.falloff, 0.0, 0.0}
	}

	sg.update_buffer(
		ren.vertex_pos_buffer,
		{raw_data(ren.vertex_positions), uint(ren.num_vertices)*size_of(ren.vertex_positions[0])},
	)
	sg.update_buffer(
		ren.vertex_normal_buffer,
		{raw_data(ren.vertex_normals), uint(ren.num_vertices)*size_of(ren.vertex_normals[0])},
	)
	sg.update_buffer(
		ren.vertex_uv_buffer,
		{raw_data(ren.vertex_uvs), uint(ren.num_vertices)*size_of(ren.vertex_uvs[0])},
	)
	sg.update_buffer(
		ren.vertex_color_buffer,
		{raw_data(ren.vertex_colors), uint(ren.num_vertices)*size_of(ren.vertex_colors[0])},
	)
	sg.update_buffer(
		ren.index_buffer,
		{raw_data(ren.indices), uint(ren.num_indices)*size_of(ren.indices[0])},
	)

	sg.begin_pass({
		action = {
			colors = {
				0 = {
					load_action = .CLEAR,
					clear_value = {0.0, 0.0, 0.0, 1.0},
				},
				1 = {
					load_action = .CLEAR,
					clear_value = {0.0, 0.0, 0.0, 1.0},
				},
			},
			depth = {
				load_action = .CLEAR,
				clear_value = 1.0,
			},
		},
		attachments = ren.attachments,
	})

	// first batch is always empty
	// first pass: normal
	sg.apply_pipeline(ren.normal_pipeline)
	for batch in ren.batches[1:ren.num_batches] {
		if batch.kind != .Normal {
			continue
		}

		sg.apply_bindings({
			vertex_buffers = {
				shader.ATTR_generic_3d_generic_3d_A_position = ren.vertex_pos_buffer,
				shader.ATTR_generic_3d_generic_3d_A_normal = ren.vertex_normal_buffer,
				shader.ATTR_generic_3d_generic_3d_A_uv = ren.vertex_uv_buffer,
				shader.ATTR_generic_3d_generic_3d_A_color = ren.vertex_color_buffer,
			},
			index_buffer = ren.index_buffer,
			images = {shader.IMG_generic_3d_U_texture = batch.texture},
			samplers = {shader.SMP_generic_3d_U_sampler = batch.sampler},
		})
		sg.apply_uniforms(shader.UB_generic_3d_Vertex_Param, {&vertex_param, size_of(vertex_param)})
		sg.apply_uniforms(shader.UB_generic_3d_Fragment_Param, {&fragment_param, size_of(fragment_param)})
		sg.draw(batch.first_index, batch.num_indices, 1)
	}

	// second pass: decal
	sg.apply_pipeline(ren.decal_pipeline)
	for batch in ren.batches[1:ren.num_batches] {
		if batch.kind != .Decal {
			continue
		}

		sg.apply_bindings({
			vertex_buffers = {
				0 = ren.vertex_pos_buffer,
				1 = ren.vertex_normal_buffer,
				2 = ren.vertex_uv_buffer,
				3 = ren.vertex_color_buffer,
			},
			index_buffer = ren.index_buffer,
			images = {shader.IMG_generic_3d_U_texture = batch.texture},
			samplers = {shader.SMP_generic_3d_U_sampler = batch.sampler},
		})
		sg.apply_uniforms(shader.UB_generic_3d_Vertex_Param, {&vertex_param, size_of(vertex_param)})
		sg.apply_uniforms(shader.UB_generic_3d_Fragment_Param, {&fragment_param, size_of(fragment_param)})
		sg.draw(batch.first_index, batch.num_indices, 1)
	}

	sg.end_pass()
}

GFX_get_default_3d_sampler :: proc(ren: GFX_3D_Renderer) -> sg.Sampler {
	return ren.default_sampler
}

GFX_set_3d_fog_params :: proc(ren: ^GFX_3D_Renderer, density, gradient: f32, color: M_Color) {
	ren.fog_density = 0.025
	ren.fog_gradient = 2.0
	ren.fog_color = M_frgba_from_urgba(color).rgb
}

GFX_add_3d_light :: proc(ren: ^GFX_3D_Renderer, light: GFX_3D_Light) {
	if ren.num_lights < GFX__MAX_3D_LIGHT {
		ren.lights[ren.num_lights] = light
		ren.num_lights += 1
	}
}

GFX_draw_3d_triangle :: proc(
	ren: ^GFX_3D_Renderer,
	p1: M_Vec3f32, n1: M_Vec3f32, c1: M_Color,
	p2: M_Vec3f32, n2: M_Vec3f32, c2: M_Color,
	p3: M_Vec3f32, n3: M_Vec3f32, c3: M_Color,
) {
	GFX__new_3d_batch_if_needed(ren, .Normal, ren.white_texture, ren.default_sampler)

	ren.vertex_positions[ren.num_vertices] = p1
	ren.vertex_normals[ren.num_vertices] = n1
	ren.vertex_uvs[ren.num_vertices] = {0.0, 0.0}
	ren.vertex_colors[ren.num_vertices] = M_frgba_from_urgba(c1)
	ren.indices[ren.num_indices] = GFX__3D_Index(ren.num_vertices)
	ren.num_vertices += 1
	ren.num_indices += 1

	ren.vertex_positions[ren.num_vertices] = p2
	ren.vertex_normals[ren.num_vertices] = n2
	ren.vertex_uvs[ren.num_vertices] = {1.0, 0.0}
	ren.vertex_colors[ren.num_vertices] = M_frgba_from_urgba(c2)
	ren.indices[ren.num_indices] = GFX__3D_Index(ren.num_vertices)
	ren.num_vertices += 1
	ren.num_indices += 1

	ren.vertex_positions[ren.num_vertices] = p3
	ren.vertex_normals[ren.num_vertices] = n3
	ren.vertex_uvs[ren.num_vertices] = {1.0, 1.0}
	ren.vertex_colors[ren.num_vertices] = M_frgba_from_urgba(c3)
	ren.indices[ren.num_indices] = GFX__3D_Index(ren.num_vertices)
	ren.num_vertices += 1
	ren.num_indices += 1
}

GFX_draw_3d_billboard_triangle :: proc(
	ren: ^GFX_3D_Renderer,
	p1: M_Vec3f32, c1: M_Color,
	p2: M_Vec3f32, c2: M_Color,
	p3: M_Vec3f32, c3: M_Color,
	y_only := false
) {
	center := (p1 + p2 + p3)/3.0

	local_p1 := p1 - center
	local_p2 := p2 - center
	local_p3 := p3 - center

	final_p1: M_Vec3f32
	final_p2: M_Vec3f32
	final_p3: M_Vec3f32

	normal: M_Vec3f32

	if y_only {
		face_dir := ren.camera.position - center
		face_dir.y = 0.0  // project onto xz-plane
		face_dir = linalg.normalize0(face_dir)
		angle := math.atan2(face_dir.x, face_dir.z)
		mat := linalg.matrix4_rotate_f32(angle, {0.0, 1.0, 0.0})

		final_p1 = center + (mat*M_make_vec4f32(local_p1, 1.0)).xyz
		final_p2 = center + (mat*M_make_vec4f32(local_p2, 1.0)).xyz
		final_p3 = center + (mat*M_make_vec4f32(local_p3, 1.0)).xyz

		normal = face_dir
	} else {
		_, up, right := GFX_get_camera_forward_up_right_from_matrix(ren.view_mat)

		final_p1 = center + (right*local_p1.x + up*local_p1.y)
		final_p2 = center + (right*local_p2.x + up*local_p2.y)
		final_p3 = center + (right*local_p3.x + up*local_p3.y)

		normal = linalg.normalize0(ren.camera.position - center)
	}

	GFX_draw_3d_triangle(
		ren,
		final_p1, normal, c1,
		final_p2, normal, c2,
		final_p3, normal, c3,
	)
}

GFX_draw_3d_rect :: proc(
	ren: ^GFX_3D_Renderer,
	p1: M_Vec3f32, n1: M_Vec3f32, c1: M_Color,
	p2: M_Vec3f32, n2: M_Vec3f32, c2: M_Color,
	p3: M_Vec3f32, n3: M_Vec3f32, c3: M_Color,
	p4: M_Vec3f32, n4: M_Vec3f32, c4: M_Color,
) {
	GFX_draw_3d_texture(
		ren,
		ren.white_texture,
		ren.default_sampler,
		{0.0, 0.0, 1.0, 1.0},
		p1, n1, c1,
		p2, n2, c2,
		p3, n3, c3,
		p4, n4, c4,
	)
}

GFX_draw_3d_billboard_rect :: proc(
	ren: ^GFX_3D_Renderer,
	center: M_Vec3f32,
	size: M_Vec2f32,
	color: M_Color,
	y_only := false,
) {
	GFX_draw_3d_billboard_texture(
		ren,
		ren.white_texture,
		ren.default_sampler,
		center,
		size,
		{0.0, 0.0, 1.0, 1.0},
		color,
		y_only,
	)
}

GFX_draw_3d_texture :: proc(
	ren: ^GFX_3D_Renderer,
	tex: sg.Image,
	smp: sg.Sampler,
	source: M_Rect,
	p1: M_Vec3f32, n1: M_Vec3f32, c1: M_Color,
	p2: M_Vec3f32, n2: M_Vec3f32, c2: M_Color,
	p3: M_Vec3f32, n3: M_Vec3f32, c3: M_Color,
	p4: M_Vec3f32, n4: M_Vec3f32, c4: M_Color,
) {
	GFX__new_3d_batch_if_needed(ren, .Normal, tex, smp)

	start_index := GFX__3D_Index(ren.num_vertices)

	tex_width := f32(sg.query_image_width(tex))
	tex_height := f32(sg.query_image_height(tex))

	src_min := M_Vec2f32{
		source.x/tex_width,
		source.y/tex_height,
	}
	src_max := M_Vec2f32{
		(source.x + source.width)/tex_width,
		(source.y + source.height)/tex_height,
	}

	ren.vertex_positions[ren.num_vertices] = p1
	ren.vertex_normals[ren.num_vertices] = n1
	ren.vertex_uvs[ren.num_vertices] = {src_min.x, src_min.y}
	ren.vertex_colors[ren.num_vertices] = M_frgba_from_urgba(c1)
	ren.num_vertices += 1

	ren.vertex_positions[ren.num_vertices] = p2
	ren.vertex_normals[ren.num_vertices] = n2
	ren.vertex_uvs[ren.num_vertices] = {src_max.x, src_min.y}
	ren.vertex_colors[ren.num_vertices] = M_frgba_from_urgba(c2)
	ren.num_vertices += 1

	ren.vertex_positions[ren.num_vertices] = p3
	ren.vertex_normals[ren.num_vertices] = n3
	ren.vertex_uvs[ren.num_vertices] = {src_max.x, src_max.y}
	ren.vertex_colors[ren.num_vertices] = M_frgba_from_urgba(c3)
	ren.num_vertices += 1

	ren.vertex_positions[ren.num_vertices] = p4
	ren.vertex_normals[ren.num_vertices] = n4
	ren.vertex_uvs[ren.num_vertices] = {src_min.x, src_max.y}
	ren.vertex_colors[ren.num_vertices] = M_frgba_from_urgba(c4)
	ren.num_vertices += 1

	ren.indices[ren.num_indices + 0] = start_index + 0
	ren.indices[ren.num_indices + 1] = start_index + 1
	ren.indices[ren.num_indices + 2] = start_index + 2
	ren.indices[ren.num_indices + 3] = start_index + 0
	ren.indices[ren.num_indices + 4] = start_index + 2
	ren.indices[ren.num_indices + 5] = start_index + 3
	ren.num_indices += 6
}

GFX_draw_3d_billboard_texture :: proc(
	ren: ^GFX_3D_Renderer,
	tex: sg.Image,
	smp: sg.Sampler,
	center: M_Vec3f32,
	size: M_Vec2f32,
	source: M_Rect,
	color: M_Color,
	y_only := false,
) {
	local_p1 := M_Vec3f32{-size.x,  size.y, 0.0}/2.0
	local_p2 := M_Vec3f32{ size.x,  size.y, 0.0}/2.0
	local_p3 := M_Vec3f32{ size.x, -size.y, 0.0}/2.0
	local_p4 := M_Vec3f32{-size.x, -size.y, 0.0}/2.0

	final_p1: M_Vec3f32
	final_p2: M_Vec3f32
	final_p3: M_Vec3f32
	final_p4: M_Vec3f32

	normal: M_Vec3f32

	if y_only {
		face_dir := ren.camera.position - center
		face_dir.y = 0.0  // project onto xz-plane
		face_dir = linalg.normalize0(face_dir)
		angle := math.atan2(face_dir.x, face_dir.z)
		mat := linalg.matrix4_rotate_f32(angle, {0.0, 1.0, 0.0})

		final_p1 = center + (mat*M_make_vec4f32(local_p1, 1.0)).xyz
		final_p2 = center + (mat*M_make_vec4f32(local_p2, 1.0)).xyz
		final_p3 = center + (mat*M_make_vec4f32(local_p3, 1.0)).xyz
		final_p4 = center + (mat*M_make_vec4f32(local_p4, 1.0)).xyz

		normal = face_dir
	} else {
		_, up, right := GFX_get_camera_forward_up_right_from_matrix(ren.view_mat)

		final_p1 = center + (right*local_p1.x + up*local_p1.y)
		final_p2 = center + (right*local_p2.x + up*local_p2.y)
		final_p3 = center + (right*local_p3.x + up*local_p3.y)
		final_p4 = center + (right*local_p4.x + up*local_p4.y)

		normal = linalg.normalize0(ren.camera.position - center)
	}

	GFX_draw_3d_texture(
		ren,
		tex,
		smp,
		source,
		final_p1, normal, color,
		final_p2, normal, color,
		final_p3, normal, color,
		final_p4, normal, color,
	)
}

GFX_draw_3d_decal_texture :: proc(
	ren: ^GFX_3D_Renderer,
	tex: sg.Image,
	smp: sg.Sampler,
	p1: M_Vec3f32,
	p2: M_Vec3f32,
	p3: M_Vec3f32,
	p4: M_Vec3f32,
	normal: M_Vec3f32,
	source: M_Rect,
	color: M_Color,
) {
	GFX__new_3d_batch_if_needed(ren, .Decal, tex, smp)

	start_index := GFX__3D_Index(ren.num_vertices)

	tex_width := f32(sg.query_image_width(tex))
	tex_height := f32(sg.query_image_height(tex))

	src_min := M_Vec2f32{
		source.x/tex_width,
		source.y/tex_height,
	}
	src_max := M_Vec2f32{
		(source.x + source.width)/tex_width,
		(source.y + source.height)/tex_height,
	}

	col := M_frgba_from_urgba(color)

	ren.vertex_positions[ren.num_vertices] = p1
	ren.vertex_normals[ren.num_vertices] = normal
	ren.vertex_uvs[ren.num_vertices] = {src_min.x, src_min.y}
	ren.vertex_colors[ren.num_vertices] = col
	ren.num_vertices += 1

	ren.vertex_positions[ren.num_vertices] = p2
	ren.vertex_normals[ren.num_vertices] = normal
	ren.vertex_uvs[ren.num_vertices] = {src_max.x, src_min.y}
	ren.vertex_colors[ren.num_vertices] = col
	ren.num_vertices += 1

	ren.vertex_positions[ren.num_vertices] = p3
	ren.vertex_normals[ren.num_vertices] = normal
	ren.vertex_uvs[ren.num_vertices] = {src_max.x, src_max.y}
	ren.vertex_colors[ren.num_vertices] = col
	ren.num_vertices += 1

	ren.vertex_positions[ren.num_vertices] = p4
	ren.vertex_normals[ren.num_vertices] = normal
	ren.vertex_uvs[ren.num_vertices] = {src_min.x, src_max.y}
	ren.vertex_colors[ren.num_vertices] = col
	ren.num_vertices += 1

	ren.indices[ren.num_indices + 0] = start_index + 0
	ren.indices[ren.num_indices + 1] = start_index + 1
	ren.indices[ren.num_indices + 2] = start_index + 2
	ren.indices[ren.num_indices + 3] = start_index + 0
	ren.indices[ren.num_indices + 4] = start_index + 2
	ren.indices[ren.num_indices + 5] = start_index + 3
	ren.num_indices += 6
}



@(private="file") GFX__MAX_3D_LIGHT :: 200
@(private="file") GFX__MAX_3D_LIGHT_IN_SHADER :: 16

@(private="file")
GFX__3D_Index :: u32

@(private="file")
GFX__3D_Batch_Kind :: enum {
	Normal,
	Decal,
}

@(private="file")
GFX__3D_Batch :: struct {
	kind: GFX__3D_Batch_Kind,
	first_index: u32,
	num_indices: u32,
	texture: sg.Image,
	sampler: sg.Sampler,
}

@(private="file")
GFX__new_3d_batch_if_needed :: proc(
	ren: ^GFX_3D_Renderer,
	kind: GFX__3D_Batch_Kind,
	tex: sg.Image,
	smp: sg.Sampler,
) {
	curr_batch := &ren.batches[ren.num_batches]
	if curr_batch.kind != kind || curr_batch.texture != tex || curr_batch.sampler != smp {
		curr_batch.num_indices = ren.num_indices - curr_batch.first_index
		ren.num_batches += 1
		curr_batch = &ren.batches[ren.num_batches]
		curr_batch.kind = kind
		curr_batch.first_index = ren.num_indices
		curr_batch.texture = tex
		curr_batch.sampler = smp
	}
}


///////////////////////////////////////////////////////////
// POST-PROCESSING EFFECT RENDERER
///////////////////////////////////////////////////////////
GFX_BLOOM_MIP_CHAIN_LENGTH :: 7

GFX_Bloom_Mip :: struct {
	width: int,
	height: int,
	texture: sg.Image,
	attachments: sg.Attachments,
}

GFX_Post_FX_Renderer :: struct {
	vertex_buffer: sg.Buffer,
	index_buffer: sg.Buffer,

	bloom_sampler: sg.Sampler,
	bloom_downsample_shader: sg.Shader,
	bloom_downsample_pipeline: sg.Pipeline,
	bloom_upsample_shader: sg.Shader,
	bloom_upsample_pipeline: sg.Pipeline,
	bloom_mip_chain: [GFX_BLOOM_MIP_CHAIN_LENGTH]GFX_Bloom_Mip,

	additive_texture: sg.Image,
	additive_attachments: sg.Attachments,
	additive_shader: sg.Shader,
	additive_pipeline: sg.Pipeline,

	tonemap_sampler: sg.Sampler,
	tonemap_shader: sg.Shader,
	tonemap_texture: sg.Image,
	tonemap_attachments: sg.Attachments,
	tonemap_pipeline: sg.Pipeline,
}

GFX_create_post_fx_renderer :: proc(ren: ^GFX_Post_FX_Renderer, width, height: int) {
	// buffers
	{
		vertices := []struct{pos, uv: M_Vec2f32}{
			{{-1.0,  1.0}, {0.0, 0.0}}, // 0
			{{ 1.0,  1.0}, {1.0, 0.0}}, // 1
			{{ 1.0, -1.0}, {1.0, 1.0}}, // 2
			{{-1.0, -1.0}, {0.0, 1.0}}, // 3
		}
		vertices_byte_size := uint(len(vertices)*size_of(vertices[0]))
		ren.vertex_buffer = sg.make_buffer({
			size = vertices_byte_size,
			type = .VERTEXBUFFER,
			usage = .IMMUTABLE,
			data = {ptr = raw_data(vertices), size = vertices_byte_size},
		})

		indices := []u16{
			0, 1, 2,
			0, 2, 3,
		}
		indices_byte_size := uint(len(indices)*size_of(indices[0]))
		ren.index_buffer = sg.make_buffer({
			size = indices_byte_size,
			type = .INDEXBUFFER,
			usage = .IMMUTABLE,
			data = {ptr = raw_data(indices), size = indices_byte_size},
		})
	}

	// bloom
	{
		ren.bloom_sampler = sg.make_sampler({
			min_filter = .LINEAR,
			mag_filter = .LINEAR,
			wrap_u = .CLAMP_TO_EDGE,
			wrap_v = .CLAMP_TO_EDGE,
		})

		ren.bloom_downsample_shader = sg.make_shader(shader.bloom_downsample_shader_desc(sg.query_backend()))
		ren.bloom_downsample_pipeline = sg.make_pipeline({
			shader = ren.bloom_downsample_shader,
			layout = {
				attrs = {
					shader.ATTR_bloom_bloom_downsample_A_position = {
						format = .FLOAT2,
					},
					shader.ATTR_bloom_bloom_downsample_A_uv = {
						format = .FLOAT2,
					},
				},
			},
			depth = {
				pixel_format = .NONE,
			},
			color_count = 1,
			colors = {0 = {
				pixel_format = .RG11B10F,
				blend = {
					enabled = true,
					src_factor_rgb = .SRC_ALPHA,
					dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
					op_rgb = .ADD,
				},
			}},
			primitive_type = .TRIANGLES,
			index_type = .UINT16,
			sample_count = 1,
		})

		ren.bloom_upsample_shader = sg.make_shader(shader.bloom_upsample_shader_desc(sg.query_backend()))
		ren.bloom_upsample_pipeline = sg.make_pipeline({
			shader = ren.bloom_upsample_shader,
			layout = {
				attrs = {
					shader.ATTR_bloom_bloom_upsample_A_position = {
						format = .FLOAT2,
					},
					shader.ATTR_bloom_bloom_upsample_A_uv = {
						format = .FLOAT2,
					},
				},
			},
			depth = {
				pixel_format = .NONE,
			},
			color_count = 1,
			colors = {0 = {
				pixel_format = .RG11B10F,
				blend = {
					enabled = true,
					src_factor_rgb = .SRC_ALPHA,
					dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
					op_rgb = .ADD,
				},
			}},
			primitive_type = .TRIANGLES,
			index_type = .UINT16,
			sample_count = 1,
		})

		mip_width := width
		mip_height := height

		for &mip in ren.bloom_mip_chain {
			mip_width /= 2
			mip_height /= 2

			mip.width = mip_width
			mip.height = mip_height
			mip.texture = sg.make_image({
				render_target = true,
				width = i32(mip_width),
				height = i32(mip_height),
				pixel_format = .RG11B10F,
			})
			mip.attachments = sg.make_attachments({
				colors = {0 = {
					image = mip.texture,
				}},
			})
		}
	}

	// additive
	{
		ren.additive_texture = sg.make_image({
			render_target = true,
			width = i32(width),
			height = i32(height),
			pixel_format = .RG11B10F,
		})
		ren.additive_attachments = sg.make_attachments({
			colors = {0 = {
				image = ren.additive_texture,
			}},
		})
		ren.additive_shader = sg.make_shader(shader.additive_shader_desc(sg.query_backend()))
		ren.additive_pipeline = sg.make_pipeline({
			shader = ren.additive_shader,
			layout = {
				attrs = {
					shader.ATTR_additive_additive_A_position = {
						format = .FLOAT2,
					},
					shader.ATTR_additive_additive_A_uv = {
						format = .FLOAT2,
					},
				},
			},
			depth = {
				pixel_format = .NONE,
			},
			color_count = 1,
			colors = {0 = {
				pixel_format = sg.query_image_pixelformat(ren.additive_texture),
				blend = {
					enabled = true,
					src_factor_rgb = .SRC_ALPHA,
					dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
					op_rgb = .ADD,
				},
			}},
			primitive_type = .TRIANGLES,
			index_type = .UINT16,
			sample_count = 1,
		})
	}

	// tonemap
	{
		ren.tonemap_sampler = sg.make_sampler({
			min_filter = .NEAREST,
			mag_filter = .NEAREST,
			wrap_u = .CLAMP_TO_EDGE,
			wrap_v = .CLAMP_TO_EDGE,
		})

		ren.tonemap_shader = sg.make_shader(shader.tonemap_shader_desc(sg.query_backend()))

		ren.tonemap_texture = sg.make_image({
			render_target = true,
			width = i32(width),
			height = i32(height),
			pixel_format = .RGBA8,
		})

		ren.tonemap_attachments = sg.make_attachments({
			colors = {0 = {
				image = ren.tonemap_texture,
			}},
		})

		ren.tonemap_pipeline = sg.make_pipeline({
			shader = ren.tonemap_shader,
			layout = {
				attrs = {
					shader.ATTR_tonemap_tonemap_A_position = {
						format = .FLOAT2,
					},
					shader.ATTR_tonemap_tonemap_A_uv = {
						format = .FLOAT2,
					},
				},
			},
			depth = {
				pixel_format = .NONE,
			},
			color_count = 1,
			colors = {0 = {
				pixel_format = sg.query_image_pixelformat(ren.tonemap_texture),
				blend = {
					enabled = true,
					src_factor_rgb = .SRC_ALPHA,
					dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
					op_rgb = .ADD,
				},
			}},
			primitive_type = .TRIANGLES,
			index_type = .UINT16,
			sample_count = 1,
		})
	}
}

GFX_destroy_post_fx_renderer :: proc(ren: ^GFX_Post_FX_Renderer) {
	sg.destroy_buffer(ren.vertex_buffer)
	sg.destroy_buffer(ren.index_buffer)

	sg.destroy_sampler(ren.bloom_sampler)
	sg.destroy_shader(ren.bloom_downsample_shader)
	sg.destroy_pipeline(ren.bloom_downsample_pipeline)
	sg.destroy_shader(ren.bloom_upsample_shader)
	sg.destroy_pipeline(ren.bloom_upsample_pipeline)
	for &mip in ren.bloom_mip_chain {
		sg.destroy_image(mip.texture)
		sg.destroy_attachments(mip.attachments)
	}
	sg.destroy_image(ren.additive_texture)
	sg.destroy_attachments(ren.additive_attachments)
	sg.destroy_shader(ren.additive_shader)
	sg.destroy_pipeline(ren.additive_pipeline)

	sg.destroy_sampler(ren.tonemap_sampler)
	sg.destroy_shader(ren.tonemap_shader)
	sg.destroy_pipeline(ren.tonemap_pipeline)
}

GFX_do_post_fx_bloom :: proc(
	ren: ^GFX_Post_FX_Renderer,
	src_texture: sg.Image,
	filter_radius: f32,
) {
	mip_texture := src_texture
	mip_resolution := M_Vec2f32{
		f32(sg.query_image_width(src_texture)),
		f32(sg.query_image_height(src_texture)),
	}

	// downsample
	for mip in ren.bloom_mip_chain {
		sg.begin_pass({
			action = {colors = {0 = {
				load_action = .CLEAR,
				clear_value = {0.0, 0.0, 0.0, 1.0},
			}}},
			attachments = mip.attachments,
		})
		sg.apply_pipeline(ren.bloom_downsample_pipeline)
		sg.apply_bindings({
			vertex_buffers = {0 = ren.vertex_buffer},
			index_buffer = ren.index_buffer,
			images = {shader.IMG_bloom_U_src_texture = mip_texture},
			samplers = {shader.SMP_bloom_U_src_sampler = ren.bloom_sampler},
		})
		uniform := shader.Bloom_Downsample_Fragment_Param{
			src_resolution = mip_resolution,
		}
		sg.apply_uniforms(shader.UB_bloom_Downsample_Fragment_Param, {&uniform, size_of(uniform)})
		sg.apply_viewport(0, 0, i32(mip.width), i32(mip.height), false)
		sg.draw(0, 6, 1)
		sg.end_pass()

		mip_texture = mip.texture
		mip_resolution = {f32(mip.width), f32(mip.height)}
	}

	// upsample
	for i := len(ren.bloom_mip_chain) - 1; i > 0; i -= 1 {
		mip := ren.bloom_mip_chain[i]
		next_mip := ren.bloom_mip_chain[i - 1]

		sg.begin_pass({
			action = {colors = {0 = {
				load_action = .CLEAR,
				clear_value = {0.0, 0.0, 0.0, 1.0},
			}}},
			attachments = next_mip.attachments,
		})
		sg.apply_pipeline(ren.bloom_upsample_pipeline)
		sg.apply_bindings({
			vertex_buffers = {0 = ren.vertex_buffer},
			index_buffer = ren.index_buffer,
			images = {shader.IMG_bloom_U_src_texture = mip.texture},
			samplers = {shader.SMP_bloom_U_src_sampler = ren.bloom_sampler},
		})
		uniform := shader.Bloom_Upsample_Fragment_Param{
			filter_radius = filter_radius,
		}
		sg.apply_uniforms(shader.UB_bloom_Upsample_Fragment_Param, {&uniform, size_of(uniform)})
		sg.apply_viewport(0, 0, i32(next_mip.width), i32(next_mip.height), false)
		sg.draw(0, 6, 1)
		sg.end_pass()
	}
}

GFX_do_post_fx_additive :: proc(
	ren: ^GFX_Post_FX_Renderer,
	texture0: sg.Image,
	texture1: sg.Image,
	sampler0: sg.Sampler,
	sampler1: sg.Sampler,
){
	sg.begin_pass({
		action = {colors = {0 = {
			load_action = .CLEAR,
			clear_value = {0.0, 0.0, 0.0, 1.0},
		}}},
		attachments = ren.additive_attachments,
	})
	sg.apply_pipeline(ren.additive_pipeline)
	sg.apply_bindings({
		vertex_buffers = {0 = ren.vertex_buffer},
		index_buffer = ren.index_buffer,
		images = {
			shader.IMG_additive_U_texture0 = texture0,
			shader.IMG_additive_U_texture1 = texture1,
		},
		samplers = {
			shader.SMP_additive_U_sampler0 = sampler0,
			shader.SMP_additive_U_sampler1 = sampler1,
		},
	})
	sg.draw(0, 6, 1)
	sg.end_pass()

}

GFX_do_post_fx_tonemap :: proc(
	ren: ^GFX_Post_FX_Renderer,
	src_texture: sg.Image,
	exposure: f32,
	gamma: f32,
) {
	sg.begin_pass({
		action = {colors = {0 = {
			load_action = .CLEAR,
			clear_value = {0.0, 0.0, 0.0, 1.0},
		}}},
		attachments = ren.tonemap_attachments,
	})
	sg.apply_pipeline(ren.tonemap_pipeline)
	sg.apply_bindings({
		vertex_buffers = {0 = ren.vertex_buffer},
		index_buffer = ren.index_buffer,
		images = {shader.IMG_tonemap_U_texture = src_texture},
		samplers = {shader.SMP_tonemap_U_sampler = ren.tonemap_sampler},
	})
	uniform := shader.Tonemap_Fragment_Param{
		exposure = exposure,
		gamma = gamma,
	}
	sg.apply_uniforms(shader.UB_tonemap_Fragment_Param, {&uniform, size_of(uniform)})
	sg.draw(0, 6, 1)
	sg.end_pass()
}



/*
- level mesh
- objects (entities, projectiles, etc.)
- particles
- decals (quad with depth test func set to EQUAL)
*/

/*
- normal pipeline
- decal pipeline
- player's hand pipeline (depth test = ALWAYS)
*/
