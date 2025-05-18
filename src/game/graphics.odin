package game

import "core:log"
import "core:os"
import "core:mem"
import "core:slice"
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
// TODO: 3d camera


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
					0 = {stride = size_of(M_Vec2f32)},
					1 = {stride = size_of(M_Vec2f32)},
					2 = {stride = size_of(M_FColor)},
				},
				attrs = {
					shader.ATTR_generic_2d_A_position = {
						buffer_index = shader.ATTR_generic_2d_A_position,
						format = .FLOAT2,
					},
					shader.ATTR_generic_2d_A_uv = {
						buffer_index = shader.ATTR_generic_2d_A_uv,
						format = .FLOAT2,
					},
					shader.ATTR_generic_2d_A_color = {
						buffer_index = shader.ATTR_generic_2d_A_color,
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
	mem.set(raw_data(ren.batches), 0xff, len(ren.batches)*size_of(ren.batches[0]))
	ren.layer = 0

	// clear background
	sg.begin_pass({
		action = {colors = {0 = {
			load_action = .CLEAR,
			clear_value = {0.0, 0.0, 0.0, 1.0},
		}}},
		swapchain = GFX_get_swapchain(),
	})
	sg.end_pass()
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
		{raw_data(ren.vertex_positions), uint(ren.num_vertices)*size_of(M_Vec2f32)},
	)
	sg.update_buffer(
		ren.vertex_uv_buffer,
		{raw_data(ren.vertex_uvs), uint(ren.num_vertices)*size_of(M_Vec2f32)},
	)
	sg.update_buffer(
		ren.vertex_color_buffer,
		{raw_data(ren.vertex_colors), uint(ren.num_vertices)*size_of(M_FColor)},
	)
	sg.update_buffer(
		ren.index_buffer,
		{raw_data(ren.indices), uint(ren.num_indices)*size_of(GFX__2D_Index)},
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
				0 = ren.vertex_pos_buffer,
				1 = ren.vertex_uv_buffer,
				2 = ren.vertex_color_buffer,
			},
			index_buffer = ren.index_buffer,
			images = {shader.IMG_U_texture = batch.texture},
			samplers = {shader.SMP_U_sampler = batch.sampler},
		})
		uniform := shader.Vertex_Param{
			proj = linalg.matrix_flatten(proj),
		}
		sg.apply_uniforms(shader.UB_Vertex_Param, {&uniform, size_of(uniform)})
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
// RENDERER 3D
///////////////////////////////////////////////////////////
// TODO: implementation



// NOTE: OPENGL
/*
import "core:math"
import la "core:math/linalg"

import gl "vendor:OpenGL"

import "../log"

import shader "shader_generated"

// Function Suffixes:
//   v = vector
//   c = more color options
//   x = extended

@(private)
Vertex :: struct { x, y, u, v, r, g, b, a: f32 }
@(private)
Index :: u32

@(private="file")
SMOOTH_CIRCLE_ERROR_RATE :: 0.3

@(private="file")
MAX_VERTEX_COUNT :: 102400
@(private="file")
MAX_INDEX_COUNT :: 102400


begin :: proc(width, height: int)
{
	ctx.render_width = width
	ctx.render_height = height
}

end :: proc()
{
	flush_batch()
}

begin_render_texture :: proc(tex: ^Render_Texture)
{
	assert(tex != nil && ctx.active_render_texture == nil)
	flush_batch()
	ctx.active_render_texture = tex

	gl.BindFramebuffer(gl.FRAMEBUFFER, tex.id)
}

end_render_texture :: proc()
{
	assert(ctx.active_render_texture != nil)
	flush_batch()
	gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
	ctx.active_render_texture = nil
}

begin_camera :: #force_inline proc(scroll, offset: la.Vector2f32)
{
	ctx.camera.scroll = scroll
	ctx.camera.offset = offset
}

end_camera :: #force_inline proc()
{
	ctx.camera = {}
}

clear :: proc(color: Color)
{
	gl.ClearColor(color.r, color.g, color.b, color.a)
	gl.Clear(gl.COLOR_BUFFER_BIT)
}

draw_point :: proc(x, y: f32, color: Color, size: f32 = 1)
{
	begin_batch(true, ctx.basic_shader, ctx.white_texture)
	add_index(0, 1, 2, 0, 2, 3)
	add_vertex(math.floor(x) - size*0.5, math.floor(y) - size*0.5, 0, 0, color.r, color.g, color.b, color.a)
	add_vertex(math.floor(x) + size*0.5, math.floor(y) - size*0.5, 1, 0, color.r, color.g, color.b, color.a)
	add_vertex(math.floor(x) + size*0.5, math.floor(y) + size*0.5, 1, 1, color.r, color.g, color.b, color.a)
	add_vertex(math.floor(x) - size*0.5, math.floor(y) + size*0.5, 0, 1, color.r, color.g, color.b, color.a)
}

draw_point_v :: #force_inline proc(pos: la.Vector2f32, color: Color, size: f32 = 1)
{
	draw_point(pos.x, pos.y, color, size)
}

draw_points :: #force_inline proc(points: []la.Vector2f32, color: Color, size: f32 = 1)
{
	for point in points
	{
		draw_point(point.x, point.y, color, size)
	}
}

/*
NOTE: There is a problem with line drawing: if the line is too thin and is not aligned with the
screen pixel, it won't be visible. The solution would be to floor/ceil/round the vertex position,
but that causes weird artifacts when drawing other shape, such as gaps when drawing a ring
*/
draw_line :: proc(x1, y1, x2, y2: f32, color: Color, thick: f32 = 1)
{
	draw_line_c(x1, y1, x2, y2, color, color, thick)
}

/*
Draws a rectangle with a width of the length of the line, and height of
line thickness and then rotate that rectangle
*/
draw_line_c :: proc(x1, y1, x2, y2: f32, color1, color2: Color, thick: f32 = 1)
{
	width := abs(x2 - x1)
	height := abs(y2 - y1)
	length := math.sqrt(width*width + height*height)
	angle := math.atan2(y2 - y1, x2 - x1)

	top_left: la.Vector2f32
	top_right: la.Vector2f32
	bottom_right: la.Vector2f32
	bottom_left: la.Vector2f32

	// Only calculate rotation if needed
	if angle < 0.0001
	{
		y := y1 - thick*0.5
		top_left     = { x1,          y }
		top_right    = { x1 + length, y }
		bottom_right = { x1 + length, y + thick }
		bottom_left  = { x1,          y + thick }
	}
	else if math.abs(angle - math.PI*0.5) < 0.0001
	{
		top_left     = { x1 - thick*0.5, y1 }
		top_right    = { x1 - thick*0.5, y2 }
		bottom_right = { x1 + thick*0.5, y2 }
		bottom_left  = { x1 + thick*0.5, y1 }
	}
	else
	{
		sin := math.sin(angle)
		cos := math.cos(angle)
		dy := -thick*0.5

		top_left.x = x1 - dy*sin
		top_left.y = y1 + dy*cos

		top_right.x = x1 + length*cos - dy*sin
		top_right.y = y1 + length*sin + dy*cos

		bottom_right.x = x1 + length*cos - (dy + thick)*sin
		bottom_right.y = y1 + length*sin + (dy + thick)*cos

		bottom_left.x = x1 - (dy + thick)*sin
		bottom_left.y = y1 + (dy + thick)*cos
	}

	begin_batch(true, ctx.basic_shader, ctx.white_texture)
	add_index(0, 1, 2, 0, 2, 3)
	add_vertex(math.floor(    top_left.x), math.floor(    top_left.y), 0, 0, color1.r, color1.g, color1.b, color1.a)
	add_vertex(math.floor(   top_right.x), math.floor(   top_right.y), 1, 0, color2.r, color2.g, color2.b, color2.a)
	add_vertex(math.floor(bottom_right.x), math.floor(bottom_right.y), 1, 1, color2.r, color2.g, color2.b, color2.a)
	add_vertex(math.floor( bottom_left.x), math.floor( bottom_left.y), 0, 1, color1.r, color1.g, color1.b, color1.a)
}

draw_line_v :: #force_inline proc(p1, p2: la.Vector2f32, color: Color, thick: f32 = 1)
{
	draw_line_c(p1.x, p1.y, p2.x, p2.y, color, color, thick)
}

draw_line_vc :: #force_inline proc(p1, p2: la.Vector2f32, color1, color2: Color, thick: f32 = 1)
{
	draw_line_c(p1.x, p1.y, p2.x, p2.y, color1, color2, thick)
}

draw_line_strip :: proc(points: []la.Vector2f32, color: Color, thick: f32 = 1)
{
	assert(len(points) > 1)

	for i in 1..<len(points)
	{
		p1 := points[i - 1]
		p2 := points[i]
		draw_line(p1.x, p1.y, p2.x, p2.y, color, thick)
	}
}

draw_line_loop :: proc(points: []la.Vector2f32, color: Color, thick: f32 = 1)
{
	assert(len(points) > 1)

	for i in 1..<len(points)
	{
		p1 := points[i - 1]
		p2 := points[i]
		draw_line(p1.x, p1.y, p2.x, p2.y, color, thick)
	}

	p_start := points[0]
	p_final := points[len(points) - 1]
	draw_line(p_final.x, p_final.y, p_start.x, p_start.y, color, thick)
}

draw_circle :: #force_inline proc(center_x, center_y, radius: f32, color: Color)
{
	draw_circle_sector(center_x, center_y, radius, 0.0, 360.0, color)
}

draw_circle_v :: #force_inline proc(center: la.Vector2f32, radius: f32, color: Color)
{
	draw_circle(center.x, center.y, radius, color)
}

draw_circle_line :: #force_inline proc(center_x, center_y, radius: f32, color: Color, thick: f32 = 1)
{
	draw_circle_sector_line(center_x, center_y, radius, 0, 360, color, thick)
}

draw_circle_line_v :: #force_inline proc(center: la.Vector2f32, radius: f32, color: Color, thick: f32 = 1)
{
	draw_circle_line(center.x, center.y, radius, color, thick)
}

draw_circle_sector :: proc(center_x, center_y, radius, start_angle, end_angle: f32, color: Color, segment_count: int = 0)
{
	radius := radius
	start_angle := start_angle
	end_angle := end_angle
	segment_count := segment_count

	// Avoid dividing by zero
	if radius <= 0.0 do radius = 0.1

	if end_angle < start_angle
	{
		tmp := start_angle
		start_angle = end_angle
		end_angle = tmp
	}

	min_segment_count := int(math.ceil((end_angle - start_angle)/90.0))
	if segment_count < min_segment_count
	{
		th := math.acos(2.0*math.pow(1.0 - SMOOTH_CIRCLE_ERROR_RATE/radius, 2) - 1)
		segment_count = int((end_angle - start_angle)*math.ceil(2.0*math.PI/th)/360.0)
		if segment_count <= 0 do segment_count = min_segment_count
	}

	angle_step_amount := (end_angle - start_angle)/f32(segment_count)
	angle := start_angle

	begin_batch(true, ctx.basic_shader, ctx.white_texture)

	cx := math.floor(center_x)
	cy := math.floor(center_y)

	for i in 0..<segment_count/2
	{
		add_index(0, 1, 2, 0, 2, 3)
		add_vertex(cx, cy, 0, 0, color.r, color.g, color.b, color.a)
		add_vertex(cx + math.cos(math.to_radians(angle))*radius, cy + math.sin(math.to_radians(angle))*radius, 1, 0, color.r, color.g, color.b, color.a)
		angle += angle_step_amount
		add_vertex(cx + math.cos(math.to_radians(angle))*radius, cy + math.sin(math.to_radians(angle))*radius, 1, 1, color.r, color.g, color.b, color.a)
		angle += angle_step_amount
		add_vertex(cx + math.cos(math.to_radians(angle))*radius, cy + math.sin(math.to_radians(angle))*radius, 0, 1, color.r, color.g, color.b, color.a)
	}

	// In case the segment count is odd, the last piece needs to be added to complete the sector
	if segment_count%2 == 1
	{
		add_index(0, 1, 2, 0, 2, 3)
		add_vertex(cx, cy, 0, 0, color.r, color.g, color.b, color.a)
		add_vertex(cx + math.cos(math.to_radians(angle))*radius, cy + math.sin(math.to_radians(angle))*radius, 1, 0, color.r, color.g, color.b, color.a)
		angle += angle_step_amount
		add_vertex(cx + math.cos(math.to_radians(angle))*radius, cy + math.sin(math.to_radians(angle))*radius, 1, 1, color.r, color.g, color.b, color.a)
		add_vertex(cx, cy, 0, 1, color.r, color.g, color.b, color.a)
	}
}

draw_circle_sector_v :: #force_inline proc(center: la.Vector2f32, radius, start_angle, end_angle: f32, color: Color, segment_count: int = 0)
{
	draw_circle_sector(center.x, center.y, radius, start_angle, end_angle, color, segment_count)
}

draw_circle_sector_line :: #force_inline proc(center_x, center_y, radius, start_angle, end_angle: f32, color: Color, thick: f32 = 1, segment_count: int = 0)
{
	draw_ring_sector(center_x, center_y, radius - thick, radius, start_angle, end_angle, color, segment_count)
}

draw_circle_sector_line_v :: #force_inline proc(center: la.Vector2f32, radius, start_angle, end_angle: f32, color: Color, thick: f32 = 1, segment_count: int = 0)
{
	draw_circle_sector_line(center.x, center.y, radius, start_angle, end_angle, color, thick, segment_count)
}

draw_ring :: #force_inline proc(center_x, center_y, inner_radius, outer_radius: f32, color: Color)
{
	draw_ring_sector(center_x, center_y, inner_radius, outer_radius, 0.0, 360.0, color)
}

draw_ring_v :: #force_inline proc(center: la.Vector2f32, inner_radius, outer_radius: f32, color: Color)
{
	draw_ring(center.x, center.y, inner_radius, outer_radius, color)
}

draw_ring_line :: #force_inline proc(center_x, center_y, inner_radius, outer_radius: f32, color: Color, thick: f32 = 1)
{
	draw_ring_sector_line(center_x, center_y, inner_radius, outer_radius, 0, 360, color, thick)
}

draw_ring_line_v :: #force_inline proc(center: la.Vector2f32, inner_radius, outer_radius: f32, color: Color, thick: f32 = 1)
{
	draw_ring_line(center.x, center.y, inner_radius, outer_radius, color, thick)
}

draw_ring_sector :: proc(center_x, center_y, inner_radius, outer_radius, start_angle, end_angle: f32, color: Color, segment_count: int = 0)
{
	inner_radius := inner_radius
	outer_radius := outer_radius
	start_angle := start_angle
	end_angle := end_angle
	segment_count := segment_count

	inner_radius = abs(inner_radius)
	outer_radius = abs(outer_radius)

	if outer_radius < inner_radius
	{
		tmp := outer_radius
		outer_radius = inner_radius
		inner_radius = tmp

		// Avoid dividing by zero
		if outer_radius <= 0.0 do outer_radius = 0.1
	}

	if end_angle < start_angle
	{
		tmp := start_angle
		start_angle = end_angle
		end_angle = tmp
	}

	min_segment_count := int(math.ceil((end_angle - start_angle)/90.0))
	if segment_count < min_segment_count
	{
		th := math.acos(2.0*math.pow(1.0 - SMOOTH_CIRCLE_ERROR_RATE/outer_radius, 2) - 1)
		segment_count = int((end_angle - start_angle)*math.ceil(2.0*math.PI/th)/360.0)
		if segment_count <= 0 do segment_count = min_segment_count
	}

	// A circle, not a ring
	if inner_radius <= 0.0
	{
		draw_circle_sector(center_x, center_y, outer_radius, start_angle, end_angle, color, segment_count)
	}

	angle_step_amount := (end_angle - start_angle)/f32(segment_count)
	angle := start_angle

	begin_batch(true, ctx.basic_shader, ctx.white_texture)

	cx := math.floor(center_x)
	cy := math.floor(center_y)

	for _ in 0..<segment_count
	{
		add_index(0, 1, 2, 0, 2, 3)
		// NOTE: Multiply 1.001 to fix weird gaps that sometimes occur
		add_vertex(cx + math.cos(math.to_radians(angle))*outer_radius*1.001, cy + math.sin(math.to_radians(angle))*outer_radius, 0, 0, color.r, color.g, color.b, color.a)
		add_vertex(cx + math.cos(math.to_radians(angle))*inner_radius*1.001, cy + math.sin(math.to_radians(angle))*inner_radius, 1, 0, color.r, color.g, color.b, color.a)
		angle += angle_step_amount
		add_vertex(cx + math.cos(math.to_radians(angle))*inner_radius*1.001, cy + math.sin(math.to_radians(angle))*inner_radius, 0, 1, color.r, color.g, color.b, color.a)
		add_vertex(cx + math.cos(math.to_radians(angle))*outer_radius*1.001, cy + math.sin(math.to_radians(angle))*outer_radius, 1, 1, color.r, color.g, color.b, color.a)
	}
}

draw_ring_sector_v :: #force_inline proc(center: la.Vector2f32, inner_radius, outer_radius, start_angle, end_angle: f32, color: Color, segment_count: int = 0)
{
	draw_ring_sector(center.x, center.y, inner_radius, outer_radius, start_angle, end_angle, color, segment_count)
}

draw_ring_sector_line :: #force_inline proc(center_x, center_y, inner_radius, outer_radius, start_angle, end_angle: f32, color: Color, thick: f32 = 1, segment_count: int = 0)
{
	draw_ring_sector(center_x, center_y, inner_radius - thick, inner_radius, start_angle, end_angle, color, segment_count)
	draw_ring_sector(center_x, center_y, outer_radius - thick, outer_radius, start_angle, end_angle, color, segment_count)
}

draw_ring_sector_line_v :: #force_inline proc(center: la.Vector2f32, inner_radius, outer_radius, start_angle, end_angle: f32, color: Color, thick: f32 = 1, segment_count: int = 0)
{
	draw_ring_sector_line(center.x, center.y, inner_radius, outer_radius, start_angle, end_angle, color, thick, segment_count)
}

draw_triangle :: #force_inline proc(x1, y1, x2, y2, x3, y3: f32, color: Color)
{
	points := [3]la.Vector2f32{ { x1, y1 }, { x2, y2 }, { x3, y3 } }
	draw_triangle_strip(points[:], color)
}

draw_triangle_c :: #force_inline proc(x1, y1, x2, y2, x3, y3: f32, color1, color2, color3: Color)
{
	points := [3]la.Vector2f32{ { x1, y1 }, { x2, y2 }, { x3, y3 } }
	colors := [3]Color{ color1, color2, color3 }
	draw_triangle_strip_c(points[:], colors[:])
}

draw_triangle_v :: #force_inline proc(p1, p2, p3: la.Vector2f32, color: Color)
{
	points := [3]la.Vector2f32{ p1, p2, p3 }
	draw_triangle_strip(points[:], color)
}

draw_triangle_vc :: #force_inline proc(p1, p2, p3: la.Vector2f32, color1, color2, color3: Color)
{
	points := [3]la.Vector2f32{ p1, p2, p3 }
	colors := [3]Color{ color1, color2, color3 }
	draw_triangle_strip_c(points[:], colors[:])
}

draw_triangle_line :: #force_inline proc(x1, y1, x2, y2, x3, y3: f32, color: Color, thick: f32 = 1)
{
	points := [3]la.Vector2f32{ { x1, y1 }, { x2, y2 }, { x3, y3 } }
	draw_line_loop(points[:], color, thick)
}

draw_triangle_line_v :: #force_inline proc(p1, p2, p3: la.Vector2f32, color: Color, thick: f32 = 1)
{
	points := [3]la.Vector2f32{ p1, p2, p3 }
	draw_line_loop(points[:], color, thick)
}

draw_triangle_strip :: proc(points: []la.Vector2f32, color: Color)
{
	assert(len(points) >= 3)

	begin_batch(false, ctx.basic_shader, ctx.white_texture)

	min_x := math.inf_f32(+1)
	max_x := math.inf_f32(-1)
	min_y := math.inf_f32(+1)
	max_y := math.inf_f32(-1)
	for point in points
	{
		min_x = min(min_x, point.x)
		max_x = max(max_x, point.x)
		min_y = min(min_y, point.y)
		max_y = max(max_y, point.y)
	}
	inv_width := 1.0/(max_x - min_x)
	inv_height := 1.0/(max_y - min_y)

	for point in points
	{
		add_vertex(point.x, point.y, (point.x - min_x)*inv_width, (point.y - min_y)*inv_height, color.r, color.g, color.b, color.a)
	}
}

draw_triangle_strip_c :: proc(points: []la.Vector2f32, colors: []Color)
{
	assert(len(points) >= 3)
	assert(len(points) == len(colors))

	begin_batch(false, ctx.basic_shader, ctx.white_texture)

	min_x := math.inf_f32(+1)
	max_x := math.inf_f32(-1)
	min_y := math.inf_f32(+1)
	max_y := math.inf_f32(-1)
	for point in points
	{
		min_x = min(min_x, point.x)
		max_x = max(max_x, point.x)
		min_y = min(min_y, point.y)
		max_y = max(max_y, point.y)
	}
	inv_width := 1.0/(max_x - min_x)
	inv_height := 1.0/(max_y - min_y)

	for i in 0..<len(points)
	{
		p := points[i]
		c := colors[i]
		add_vertex(p.x, p.y, (p.x - min_x)*inv_width, (p.y - min_y)*inv_height, c.r, c.g, c.b, c.a)
	}
}

// TODO: Textured triangle???
// TODO: Textured triangle???
// TODO: Textured triangle???
// TODO: Textured triangle???
// TODO: Textured triangle???

draw_rect :: #force_inline proc(x, y, w, h: f32, color: Color)
{
	draw_rect_c(x, y, w, h, color, color, color, color)
}

draw_rect_c :: proc(x, y, w, h: f32, color_tl, color_tr, color_br, color_bl: Color)
{
	begin_batch(true, ctx.basic_shader, ctx.white_texture)
	add_index(0, 1, 2, 0, 2, 3)
	add_vertex(x,     y,     0, 0, color_tl.r, color_tl.g, color_tl.b, color_tl.a)
	add_vertex(x + w, y,     1, 0, color_tr.r, color_tr.g, color_tr.b, color_tr.a)
	add_vertex(x + w, y + h, 1, 1, color_br.r, color_br.g, color_br.b, color_br.a)
	add_vertex(x,     y + h, 0, 1, color_bl.r, color_bl.g, color_bl.b, color_bl.a)
}

draw_rect_v :: #force_inline proc(pos, size: la.Vector2f32, color: Color)
{
	draw_rect_c(pos.x, pos.y, size.x, size.y, color, color, color, color)
}

draw_rect_vc :: #force_inline proc(pos, size: la.Vector2f32, color_tl, color_tr, color_br, color_bl: Color)
{
	draw_rect_c(pos.x, pos.y, size.x, size.y, color_tl, color_tr, color_br, color_bl)
}

draw_rect_line :: #force_inline proc(x, y, w, h: f32, color: Color, thick: f32 = 1)
{
	draw_rect_line_c(x, y, w, h, color, color, color, color, thick)
}

draw_rect_line_c :: #force_inline proc(x, y, w, h: f32, color_tl, color_tr, color_br, color_bl: Color, thick: f32 = 1)
{
	draw_line_c(x     - thick*0.5, y,     x + w + thick*0.5, y,     color_tl, color_tr, thick)
	draw_line_c(x + w,             y,     x + w,             y + h, color_tr, color_br, thick)
	draw_line_c(x     - thick*0.5, y + h, x + w + thick*0.5, y + h, color_br, color_bl, thick)
	draw_line_c(x,                 y,     x,                 y + h, color_bl, color_tl, thick)
}

draw_rect_line_v :: #force_inline proc(pos, size: la.Vector2f32, color: Color, thick: f32 = 1)
{
	draw_rect_line_c(pos.x, pos.y, size.x, size.y, color, color, color, color, thick)
}

draw_rect_line_vc :: #force_inline proc(pos, size: la.Vector2f32, color_tl, color_tr, color_br, color_bl: Color, thick: f32 = 1)
{
	draw_rect_line_c(pos.x, pos.y, size.x, size.y, color_tl, color_tr, color_br, color_bl, thick)
}

// NOTE: The angle is in radians
draw_rotated_rect :: #force_inline proc(x, y, w, h, angle: f32, color: Color)
{
	draw_rotated_rect_xc(x, y, w, h, 0.5, 0.5, angle, color, color, color, color)
}

draw_rotated_rect_x :: #force_inline proc(x, y, w, h, origin_x, origin_y, angle: f32, color: Color)
{
	draw_rotated_rect_xc(x, y, w, h, origin_x, origin_y, angle, color, color, color, color)
}

draw_rotated_rect_c :: #force_inline proc(x, y, w, h, angle: f32, color_tl, color_tr, color_br, color_bl: Color)
{
	draw_rotated_rect_xc(x, y, w, h, 0.5, 0.5, angle, color_tl, color_tr, color_br, color_bl)
}

// NOTE: Origin is a percentage (0 to 1)
draw_rotated_rect_xc :: proc(x, y, w, h, origin_x, origin_y, angle: f32, color_tl, color_tr, color_br, color_bl: Color)
{
	top_left: la.Vector2f32
	top_right: la.Vector2f32
	bottom_right: la.Vector2f32
	bottom_left: la.Vector2f32

	// Only calculate rotation if needed
	if angle == 0.0
	{
		nx := x - origin_x*f32(w)
		ny := y - origin_y*f32(h)
		top_left     = { nx,     ny }
		top_right    = { nx + w, ny }
		bottom_right = { nx + w, ny + h }
		bottom_left  = { nx,     ny + h }
	}
	else
	{
		sin := math.sin(angle)
		cos := math.cos(angle)
		dx := -origin_x*f32(w)
		dy := -origin_y*f32(h)

		top_left.x = math.floor(x + dx*cos - dy*sin)
		top_left.y = math.floor(y + dx*sin + dy*cos)

		top_right.x = math.floor(x + (dx + w)*cos - dy*sin)
		top_right.y = math.floor(y + (dx + w)*sin + dy*cos)

		bottom_right.x = math.floor(x + (dx + w)*cos - (dy + h)*sin)
		bottom_right.y = math.floor(y + (dx + w)*sin + (dy + h)*cos)

		bottom_left.x = math.floor(x + dx*cos - (dy + h)*sin)
		bottom_left.y = math.floor(y + dx*sin + (dy + h)*cos)
	}

	begin_batch(true, ctx.basic_shader, ctx.white_texture)
	add_index(0, 1, 2, 0, 2, 3)
	add_vertex(    top_left.x,     top_left.y, 0, 0, color_tl.r, color_tl.g, color_tl.b, color_tl.a)
	add_vertex(   top_right.x,    top_right.y, 1, 0, color_tr.r, color_tr.g, color_tr.b, color_tr.a)
	add_vertex(bottom_right.x, bottom_right.y, 1, 1, color_br.r, color_br.g, color_br.b, color_br.a)
	add_vertex( bottom_left.x,  bottom_left.y, 0, 1, color_bl.r, color_bl.g, color_bl.b, color_bl.a)
}

draw_rotated_rect_v :: #force_inline proc(pos, size: la.Vector2f32, angle: f32, color: Color)
{
	draw_rotated_rect_xc(pos.x, pos.y, size.x, size.y, 0.5, 0.5, angle, color, color, color, color)
}

draw_rotated_rect_vx :: #force_inline proc(pos, size, origin: la.Vector2f32, angle: f32, color: Color)
{
	draw_rotated_rect_xc(pos.x, pos.y, size.x, size.y, origin.x, origin.y, angle, color, color, color, color)
}

draw_rotated_rect_vc :: #force_inline proc(pos, size: la.Vector2f32, angle: f32, color_tl, color_tr, color_br, color_bl: Color)
{
	draw_rotated_rect_xc(pos.x, pos.y, size.x, size.y, 0.5, 0.5, angle, color_tl, color_tr, color_br, color_bl)
}

draw_rotated_rect_vxc :: #force_inline proc(pos, size, origin: la.Vector2f32, angle: f32, color_tl, color_tr, color_br, color_bl: Color)
{
	draw_rotated_rect_xc(pos.x, pos.y, size.x, size.y, origin.x, origin.y, angle, color_tl, color_tr, color_br, color_bl)
}

draw_rotated_rect_line :: #force_inline proc(x, y, w, h, angle: f32, color: Color, thick: f32 = 1)
{
	draw_rotated_rect_line_x(x, y, w, h, 0.5, 0.5, angle, color, thick)
}

draw_rotated_rect_line_x :: proc(x, y, w, h, origin_x, origin_y, angle: f32, color: Color, thick: f32 = 1)
{
	top_left: la.Vector2f32
	top_right: la.Vector2f32
	bottom_right: la.Vector2f32
	bottom_left: la.Vector2f32

	sin := math.sin(angle)
	cos := math.cos(angle)

	// Only calculate rotation if needed
	if angle == 0.0
	{
		nx := x - origin_x*f32(w)
		ny := y - origin_y*f32(h)
		top_left     = { nx,     ny }
		top_right    = { nx + w, ny }
		bottom_right = { nx + w, ny + h }
		bottom_left  = { nx,     ny + h }
	}
	else
	{
		dx := -origin_x*f32(w)
		dy := -origin_y*f32(h)

		top_left.x = math.floor(x + dx*cos - dy*sin)
		top_left.y = math.floor(y + dx*sin + dy*cos)

		top_right.x = math.floor(x + (dx + w)*cos - dy*sin)
		top_right.y = math.floor(y + (dx + w)*sin + dy*cos)

		bottom_right.x = math.floor(x + (dx + w)*cos - (dy + h)*sin)
		bottom_right.y = math.floor(y + (dx + w)*sin + (dy + h)*cos)

		bottom_left.x = math.floor(x + dx*cos - (dy + h)*sin)
		bottom_left.y = math.floor(y + dx*sin + (dy + h)*cos)
	}

	draw_line(    top_left.x - thick*0.5*cos,     top_left.y,    top_right.x + thick*0.5*cos,    top_right.y, color, thick)
	draw_line(   top_right.x,                    top_right.y, bottom_right.x,                 bottom_right.y, color, thick)
	draw_line(bottom_right.x + thick*0.5*cos, bottom_right.y,  bottom_left.x - thick*0.5*cos,  bottom_left.y, color, thick)
	draw_line( bottom_left.x,                  bottom_left.y,     top_left.x,                     top_left.y, color, thick)
}

draw_rotated_rect_line_v :: #force_inline proc(pos, size: la.Vector2f32, angle: f32, color: Color, thick: f32 = 1)
{
	draw_rotated_rect_line_x(pos.x, pos.y, size.x, size.y, 0.5, 0.5, angle, color, thick)
}

draw_rotated_rect_line_vx :: #force_inline proc(pos, size, origin: la.Vector2f32, angle: f32, color: Color, thick: f32 = 1)
{
	draw_rotated_rect_line_x(pos.x, pos.y, size.x, size.y, origin.x, origin.y, angle, color, thick)
}

draw_texture :: #force_inline proc(texture: Texture, x, y: f32, tint: Color)
{
	draw_texture_xc(texture, 0, 0, f32(texture.width), f32(texture.height), x, y, f32(texture.width), f32(texture.height), tint, tint, tint, tint)
}

draw_texture_c :: #force_inline proc(texture: Texture, x, y: f32, tint_tl, tint_tr, tint_br, tint_bl: Color)
{
	draw_texture_xc(texture, 0, 0, f32(texture.width), f32(texture.height), x, y, f32(texture.width), f32(texture.height), tint_tl, tint_tr, tint_br, tint_bl)
}

draw_texture_x :: #force_inline proc(texture: Texture, src_x, src_y, src_w, src_h, dst_x, dst_y, dst_w, dst_h: f32, tint: Color)
{
	draw_texture_xc(texture, src_x, src_y, src_w, src_h, dst_x, dst_y, dst_w, dst_h, tint, tint, tint, tint)
}

draw_texture_xc :: proc(texture: Texture, src_x, src_y, src_w, src_h, dst_x, dst_y, dst_w, dst_h: f32, tint_tl, tint_tr, tint_br, tint_bl: Color)
{
	inv_w := 1.0/f32(texture.width)
	inv_h := 1.0/f32(texture.height)

	begin_batch(true, ctx.basic_shader, texture)
	add_index(0, 1, 2, 0, 2, 3)
	add_vertex(math.floor(dst_x),         math.floor(dst_y),         (src_x)        *inv_w, (src_y)        *inv_h, tint_tl.r, tint_tl.g, tint_tl.b, tint_tl.a)
	add_vertex(math.floor(dst_x + dst_w), math.floor(dst_y),         (src_x + src_w)*inv_w, (src_y)        *inv_h, tint_tr.r, tint_tr.g, tint_tr.b, tint_tr.a)
	add_vertex(math.floor(dst_x + dst_w), math.floor(dst_y + dst_h), (src_x + src_w)*inv_w, (src_y + src_h)*inv_h, tint_br.r, tint_br.g, tint_br.b, tint_br.a)
	add_vertex(math.floor(dst_x),         math.floor(dst_y + dst_h), (src_x)        *inv_w, (src_y + src_h)*inv_h, tint_bl.r, tint_bl.g, tint_bl.b, tint_bl.a)
}

draw_texture_v :: #force_inline proc(texture: Texture, pos: la.Vector2f32, tint: Color)
{
	draw_texture_xc(texture, 0, 0, f32(texture.width), f32(texture.height), pos.x, pos.y, f32(texture.width), f32(texture.height), tint, tint, tint, tint)
}

draw_texture_vc :: #force_inline proc(texture: Texture, pos: la.Vector2f32, tint_tl, tint_tr, tint_br, tint_bl: Color)
{
	draw_texture_xc(texture, 0, 0, f32(texture.width), f32(texture.height), pos.x, pos.y, f32(texture.width), f32(texture.height), tint_tl, tint_tr, tint_br, tint_bl)
}

draw_texture_vx :: #force_inline proc(texture: Texture, src_pos, src_size, dst_pos, dst_size: la.Vector2f32, tint: Color)
{
	draw_texture_xc(texture, src_pos.x, src_pos.y, src_size.x, src_size.y, dst_pos.x, dst_pos.y, dst_size.x, dst_size.y, tint, tint, tint, tint)
}

draw_texture_vxc :: #force_inline proc(texture: Texture, src_pos, src_size, dst_pos, dst_size: la.Vector2f32, tint_tl, tint_tr, tint_br, tint_bl: Color)
{
	draw_texture_xc(texture, src_pos.x, src_pos.y, src_size.x, src_size.y, dst_pos.x, dst_pos.y, dst_size.x, dst_size.y, tint_tl, tint_tr, tint_br, tint_bl)
}

draw_rotated_texture :: #force_inline proc(texture: Texture, x, y, angle: f32, tint: Color)
{
	draw_rotated_texture_xc(texture, 0, 0, f32(texture.width), f32(texture.height), x, y, f32(texture.width), f32(texture.height), 0.5, 0.5, angle, tint, tint, tint, tint)
}

draw_rotated_texture_c :: #force_inline proc(texture: Texture, x, y, angle: f32, tint_tl, tint_tr, tint_br, tint_bl: Color)
{
	draw_rotated_texture_xc(texture, 0, 0, f32(texture.width), f32(texture.height), x, y, f32(texture.width), f32(texture.height), 0.5, 0.5, angle, tint_tl, tint_tr, tint_br, tint_bl)
}

draw_rotated_texture_x :: #force_inline proc(texture: Texture, src_x, src_y, src_w, src_h, dst_x, dst_y, dst_w, dst_h, origin_x, origin_y, angle: f32, tint: Color)
{
	draw_rotated_texture_xc(texture, src_x, src_y, src_w, src_h, dst_x, dst_y, dst_w, dst_h, origin_x, origin_y, angle, tint, tint, tint, tint)
}

draw_rotated_texture_xc :: proc(texture: Texture, src_x, src_y, src_w, src_h, dst_x, dst_y, dst_w, dst_h, origin_x, origin_y, angle: f32, tint_tl, tint_tr, tint_br, tint_bl: Color)
{
	inv_w := 1.0/f32(texture.width)
	inv_h := 1.0/f32(texture.height)

	top_left: la.Vector2f32
	top_right: la.Vector2f32
	bottom_right: la.Vector2f32
	bottom_left: la.Vector2f32

	// Only calculate rotation if needed
	if angle == 0.0
	{
		x := dst_x - origin_x*f32(texture.width)
		y := dst_y - origin_y*f32(texture.height)
		top_left     = { x,         y }
		top_right    = { x + dst_w, y }
		bottom_right = { x + dst_w, y + dst_h }
		bottom_left  = { x,         y + dst_h }
	}
	else
	{
		sin := math.sin(angle)
		cos := math.cos(angle)
		x := dst_x
		y := dst_y
		dx := -origin_x*f32(texture.width)
		dy := -origin_y*f32(texture.height)

		top_left.x = math.floor(x + dx*cos - dy*sin)
		top_left.y = math.floor(y + dx*sin + dy*cos)

		top_right.x = math.floor(x + (dx + dst_w)*cos - dy*sin)
		top_right.y = math.floor(y + (dx + dst_w)*sin + dy*cos)

		bottom_right.x = math.floor(x + (dx + dst_w)*cos - (dy + dst_h)*sin)
		bottom_right.y = math.floor(y + (dx + dst_w)*sin + (dy + dst_h)*cos)

		bottom_left.x = math.floor(x + dx*cos - (dy + dst_h)*sin)
		bottom_left.y = math.floor(y + dx*sin + (dy + dst_h)*cos)
	}

	begin_batch(true, ctx.basic_shader, texture)
	add_index(0, 1, 2, 0, 2, 3)
	add_vertex(    top_left.x,     top_left.y, (src_x)        *inv_w, (src_y)        *inv_h, tint_tl.r, tint_tl.g, tint_tl.b, tint_tl.a)
	add_vertex(   top_right.x,    top_right.y, (src_x + src_w)*inv_w, (src_y)        *inv_h, tint_tr.r, tint_tr.g, tint_tr.b, tint_tr.a)
	add_vertex(bottom_right.x, bottom_right.y, (src_x + src_w)*inv_w, (src_y + src_h)*inv_h, tint_br.r, tint_br.g, tint_br.b, tint_br.a)
	add_vertex( bottom_left.x,  bottom_left.y, (src_x)        *inv_w, (src_y + src_h)*inv_h, tint_bl.r, tint_bl.g, tint_bl.b, tint_bl.a)
}

draw_rotated_texture_v :: #force_inline proc(texture: Texture, pos: la.Vector2f32, angle: f32, tint: Color)
{
	draw_rotated_texture_xc(texture, 0, 0, f32(texture.width), f32(texture.height), pos.x, pos.y, f32(texture.width), f32(texture.height), 0.5, 0.5, angle, tint, tint, tint, tint)
}

draw_rotated_texture_vc :: #force_inline proc(texture: Texture, pos: la.Vector2f32, angle: f32, tint_tl, tint_tr, tint_br, tint_bl: Color)
{
	draw_rotated_texture_xc(texture, 0, 0, f32(texture.width), f32(texture.height), pos.x, pos.y, f32(texture.width), f32(texture.height), 0.5, 0.5, angle, tint_tl, tint_tr, tint_br, tint_bl)
}

draw_rotated_texture_vx :: #force_inline proc(texture: Texture, src_pos, src_size, dst_pos, dst_size, origin: la.Vector2f32, angle: f32, tint: Color)
{
	draw_rotated_texture_xc(texture, src_pos.x, src_pos.y, src_size.x, src_size.y, dst_pos.x, dst_pos.y, dst_size.x, dst_size.y, origin.x, origin.y, angle, tint, tint, tint, tint)
}

draw_rotated_texture_vxc :: #force_inline proc(texture: Texture, src_pos, src_size, dst_pos, dst_size, origin: la.Vector2f32, angle: f32, tint_tl, tint_tr, tint_br, tint_bl: Color)
{
	draw_rotated_texture_xc(texture, src_pos.x, src_pos.y, src_size.x, src_size.y, dst_pos.x, dst_pos.y, dst_size.x, dst_size.y, origin.x, origin.y, angle, tint_tl, tint_tr, tint_br, tint_bl)
}

draw_text_char :: proc(font: Font, char: rune, x, y, scale_factor: f32, color: Color)
{
	rect := font.rects[char - 32]
	offset := font.glyphs[char - 32].offset

	dst_x := x + f32(offset.x)*scale_factor
	dst_y := y + f32(offset.y)*scale_factor
	dst_w := rect.width*scale_factor
	dst_h := rect.height*scale_factor

	inv_w := 1.0/f32(font.texture.width)
	inv_h := 1.0/f32(font.texture.height)

	begin_batch(true, ctx.text_shader, font.texture)
	add_index(0, 1, 2, 0, 2, 3)
	add_vertex(math.floor(dst_x),         math.floor(dst_y),         (rect.x)             *inv_w, (rect.y)              *inv_h, color.r, color.g, color.b, color.a)
	add_vertex(math.floor(dst_x + dst_w), math.floor(dst_y),         (rect.x + rect.width)*inv_w, (rect.y)              *inv_h, color.r, color.g, color.b, color.a)
	add_vertex(math.floor(dst_x + dst_w), math.floor(dst_y + dst_h), (rect.x + rect.width)*inv_w, (rect.y + rect.height)*inv_h, color.r, color.g, color.b, color.a)
	add_vertex(math.floor(dst_x),         math.floor(dst_y + dst_h), (rect.x)             *inv_w, (rect.y + rect.height)*inv_h, color.r, color.g, color.b, color.a)
}

draw_text_char_v :: #force_inline proc(font: Font, char: rune, pos: la.Vector2f32, scale_factor: f32, color: Color)
{
	draw_text_char(font, char, pos.x, pos.y, scale_factor, color)
}

draw_text :: #force_inline proc(font: Font, text: string, x, y, font_size: f32, color: Color)
{
	draw_text_x(font, text, x, y, font_size, 0, color)
}

draw_text_x :: proc(font: Font, text: string, x, y, font_size, spacing: f32, color: Color)
{
	scale_factor := font_size/f32(font.size)

	gl.ProgramUniform1f(ctx.text_shader.id, gl.GetUniformLocation(ctx.text_shader.id, "u_screen_px_range"), scale_factor*2.0)

	xx := x
	yy := y

	// TODO: Newline???
	// TODO: Newline???

	for ch in text
	{
		draw_text_char(font, ch, xx, yy, scale_factor, color)
		xx += f32(font.glyphs[ch - 32].advance_x)*scale_factor + spacing
	}
}

draw_text_v :: #force_inline proc(font: Font, text: string, pos: la.Vector2f32, font_size: f32, color: Color)
{
	draw_text_x(font, text, pos.x, pos.y, font_size, 0, color)
}

draw_text_vx :: #force_inline proc(font: Font, text: string, pos: la.Vector2f32, font_size, spacing: f32, color: Color)
{
	draw_text_x(font, text, pos.x, pos.y, font_size, spacing, color)
}

@(private)
init_renderer :: proc()
{
	gl.Enable(gl.BLEND)
	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

}

@(private="file")
begin_batch :: proc(indexed: bool, shader: Shader, texture: Texture)
{
	if ctx.active_draw_cmd.indexed != indexed ||
		ctx.active_draw_cmd.shader.id != shader.id ||
		!match_texture(ctx.active_draw_cmd.texture, texture)
	{
		flush_batch()
	}

	ctx.active_draw_cmd = { indexed = indexed, shader = shader, texture = texture }
}

@(private="file")
flush_batch :: proc()
{
	if ctx.vertex_count + ctx.index_count == 0
	{
		return
	}

	render_width := ctx.render_width
	render_height := ctx.render_height
	if ctx.active_render_texture != nil
	{
		render_width = ctx.active_render_texture.tex.width
		render_height = ctx.active_render_texture.tex.height
	}

	gl.Viewport(0, 0, i32(render_width), i32(render_height))

	gl.UseProgram(ctx.active_draw_cmd.shader.id)
	gl.BindVertexArray(ctx.vertex_array)
	gl.BindTextureUnit(0, ctx.active_draw_cmd.texture.id)

	gl.NamedBufferSubData(ctx.vertex_buffer, 0, ctx.vertex_count*size_of(Vertex), raw_data(ctx.vertices))

	if ctx.active_draw_cmd.indexed
	{
		gl.NamedBufferSubData(ctx.index_buffer, 0, ctx.index_count*size_of(Index), raw_data(ctx.indices))
	}

	proj := matrix_flatten(la.matrix_ortho3d_f32(0, f32(render_width), f32(render_height), 0, -1, 1))
	gl.UniformMatrix4fv(gl.GetUniformLocation(ctx.active_draw_cmd.shader.id, "u_proj"), 1, false, raw_data(proj[:]))

	if ctx.active_draw_cmd.indexed
	{
		gl.DrawElements(gl.TRIANGLES, i32(ctx.index_count), gl.UNSIGNED_INT, nil)
	}
	else
	{
		gl.DrawArrays(gl.TRIANGLES, 0, i32(ctx.vertex_count))
	}

	gl.BindTextureUnit(0, 0)
	gl.BindVertexArray(0)
	gl.UseProgram(0)

	ctx.vertex_count = 0
	ctx.index_count = 0
}

@(private="file")
add_vertex :: #force_inline proc(x, y, u, v, r, g, b, a: f32)
{
	assert(ctx.vertex_count < MAX_VERTEX_COUNT)
	ctx.vertices[ctx.vertex_count] = { x - ctx.camera.scroll.x + ctx.camera.offset.x, y - ctx.camera.scroll.y + ctx.camera.offset.y, u, v, r, g, b, a }
	ctx.vertex_count += 1
}

// NOTE: Indices must be added before adding vertices
@(private="file")
add_index :: #force_inline proc(indices: ..Index)
{
	assert(ctx.index_count + len(indices) < MAX_INDEX_COUNT)

	for index in indices
	{
		ctx.indices[ctx.index_count] = cast(Index)ctx.vertex_count + index
		ctx.index_count += 1
	}
}

*/
