package game

import "core:log"
import "core:os"
import "core:mem"
import "core:slice"
import "core:math"
import "core:math/linalg"
import "core:encoding/json"

import sdl "vendor:sdl3"
import stbi "vendor:stb/image"

@(private="file") GFX__SMOOTH_CIRCLE_ERROR_RATE :: 0.4
@(private="file") GFX__DEFAULT_MAX_VERTEX :: 32000
@(private="file") GFX__DEFAULT_MAX_INDEX  :: GFX__DEFAULT_MAX_VERTEX/4*6
@(private="file") GFX__DEFAULT_MAX_2D_BATCH :: 256
@(private="file") GFX__DEPTH_TEXTURE_FORMAT :: sdl.GPUTextureFormat.D16_UNORM

@(private="file")
GFX__Index :: u32

@(private="file")
GFX__ctx: struct {
	window: ^sdl.Window,
	gpu: ^sdl.GPUDevice,
	cmd_buf: ^sdl.GPUCommandBuffer,
	swapchain_tex: ^sdl.GPUTexture,
}


///////////////////////////////////////////////////////////
// CORE
///////////////////////////////////////////////////////////
GFX_init :: proc(window: ^sdl.Window) {
	when DEV_BUILD {
		sdl.SetLogPriorities(.VERBOSE)
	}

	GFX__ctx.window = window

	GFX__ctx.gpu = sdl.CreateGPUDevice({.SPIRV}, true, nil)
	assert(GFX__ctx.gpu != nil)

	if !sdl.ClaimWindowForGPUDevice(GFX__ctx.gpu, GFX__ctx.window) {
		log.fatalf("GFX: failed to claim window for GPU: %s", sdl.GetError())
	}
}

GFX_uninit :: proc() {
	sdl.DestroyGPUDevice(GFX__ctx.gpu)
}

GFX_begin_frame :: proc() {
	GFX__ctx.cmd_buf = sdl.AcquireGPUCommandBuffer(GFX__ctx.gpu)
	assert(sdl.WaitAndAcquireGPUSwapchainTexture(GFX__ctx.cmd_buf, GFX__ctx.window, &GFX__ctx.swapchain_tex, nil, nil))
}

GFX_end_frame :: proc() {
	assert(sdl.SubmitGPUCommandBuffer(GFX__ctx.cmd_buf))
	GFX__ctx.swapchain_tex = nil
	GFX__ctx.cmd_buf = nil
}


///////////////////////////////////////////////////////////
// SHADER
///////////////////////////////////////////////////////////
GFX_Shader_Metadata :: struct {
	num_samplers: u32 `json:"samplers"`,
	num_storage_textures: u32 `json:"storage_textures"`,
	num_storage_buffers: u32 `json:"storage_buffers"`,
	num_uniform_buffers: u32 `json:"uniform_buffers"`,
}

GFX_Shader :: struct {
	handle: ^sdl.GPUShader,
}

GFX_load_shader_metadata :: proc(metadata: ^GFX_Shader_Metadata, data: []byte) {
	json.unmarshal(data, metadata)
}

GFX_load_shader :: proc(
	shader: ^GFX_Shader,
	code: []byte,
	metadata_data: []byte,
	stage: sdl.GPUShaderStage,
) {
	metadata: GFX_Shader_Metadata
	json.unmarshal(metadata_data, &metadata)
	shader.handle = sdl.CreateGPUShader(GFX__ctx.gpu, {
		code_size = len(code),
		code = raw_data(code),
		entrypoint = "main",
		format = {.SPIRV},
		stage = stage,
		num_samplers = metadata.num_samplers,
		num_storage_textures = metadata.num_storage_textures,
		num_storage_buffers = metadata.num_storage_buffers,
		num_uniform_buffers = metadata.num_uniform_buffers,
	})
}

GFX_unload_shader :: proc(shader: ^GFX_Shader) {
	sdl.ReleaseGPUShader(GFX__ctx.gpu, shader.handle)
	shader^ = {}
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
// TEXTURE
///////////////////////////////////////////////////////////
GFX_Texture :: struct {
	handle: ^sdl.GPUTexture,
	sampler: ^sdl.GPUSampler,
	width: int,
	height: int,
}

GFX_load_texture_from_file :: proc(tex: ^GFX_Texture, path: string) {
	img: GFX_Image
	GFX_load_image_from_file(&img, path)
	GFX_load_texture_from_image(tex, img)
	GFX_unload_image(&img)
}

GFX_load_texture_from_memory :: proc(tex: ^GFX_Texture, data: []byte) {
	img: GFX_Image
	GFX_load_image_from_memory(&img, data)
	GFX_load_texture_from_image(tex, img)
	GFX_unload_image(&img)
}

GFX_load_texture_from_image :: proc(tex: ^GFX_Texture, img: GFX_Image) {
	tex.width = img.width
	tex.height = img.height
	tex.handle = sdl.CreateGPUTexture(GFX__ctx.gpu, {
		format = .R8G8B8A8_UNORM,
		usage = {.SAMPLER},
		width = u32(img.width),
		height = u32(img.height),
		layer_count_or_depth = 1,
		num_levels = 1,
	})
	tex.sampler = sdl.CreateGPUSampler(GFX__ctx.gpu, {
		min_filter = .NEAREST,
		mag_filter = .NEAREST,
		address_mode_u = .CLAMP_TO_EDGE,
		address_mode_v = .CLAMP_TO_EDGE,
	})

	// upload image data to texture
	{
		copy_cmd_buf := sdl.AcquireGPUCommandBuffer(GFX__ctx.gpu)
		copy_pass := sdl.BeginGPUCopyPass(copy_cmd_buf)

		pixels_byte_size := img.width*img.height*size_of(M_Color)

		transfer_buf := sdl.CreateGPUTransferBuffer(GFX__ctx.gpu, {
			usage = .UPLOAD,
			size = u32(pixels_byte_size),
		})
		defer sdl.ReleaseGPUTransferBuffer(GFX__ctx.gpu, transfer_buf)

		// copy the data into the buffers
		transfer_mem := sdl.MapGPUTransferBuffer(GFX__ctx.gpu, transfer_buf, true)
		mem.copy(transfer_mem, raw_data(img.pixels), pixels_byte_size)
		sdl.UnmapGPUTransferBuffer(GFX__ctx.gpu, transfer_buf)

		// invoke upload command
		sdl.UploadToGPUTexture(
			copy_pass,
			{transfer_buffer = transfer_buf},
			{texture = tex.handle, w = u32(img.width), h = u32(img.height), d = 1},
			false,
		)

		sdl.EndGPUCopyPass(copy_pass)
		assert(sdl.SubmitGPUCommandBuffer(copy_cmd_buf))
	}
}

GFX_unload_texture :: proc(tex: ^GFX_Texture) {
	sdl.ReleaseGPUTexture(GFX__ctx.gpu, tex.handle)
	sdl.ReleaseGPUSampler(GFX__ctx.gpu, tex.sampler)
	tex^ = {}
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
	texture: GFX_Texture,
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
		GFX_load_texture_from_image(&font.texture, img_copy)
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
	GFX_unload_texture(&font.texture)
	delete(font.sources)
	delete(font.glyphs)
	font^ = {}
}


///////////////////////////////////////////////////////////
// CAMERA
///////////////////////////////////////////////////////////
GFX_Camera :: struct {
	offset: M_Vec2f32,
	target: M_Vec2f32,
	rotation: f32,  // in degrees
	scale: f32,
}

GFX_get_camera_matrix :: proc(cam: GFX_Camera) -> linalg.Matrix4f32 {
	view := linalg.MATRIX4F32_IDENTITY
	view *= linalg.matrix4_translate_f32({cam.offset.x, cam.offset.y, 0.0})
	view *= linalg.matrix4_scale_f32({cam.scale, cam.scale, 1.0})
	view *= linalg.matrix4_rotate_f32(-cam.rotation*math.RAD_PER_DEG, {0.0, 0.0, 1.0})
	view *= linalg.matrix4_translate_f32({-cam.target.x, -cam.target.y, 0.0})
	return view
}

GFX_camera_screen_to_world :: proc(cam: GFX_Camera, p: M_Vec2f32) -> M_Vec2f32 {
	view_inv := linalg.matrix4_inverse(GFX_get_camera_matrix(cam))
	screen_vec := M_Vec4f32{p.x, p.y, 0.0, 1.0}
	world_vec := view_inv*screen_vec
	return world_vec.xy
}

GFX_camera_world_to_screen :: proc(cam: GFX_Camera, p: M_Vec2f32) -> M_Vec2f32 {
	view := GFX_get_camera_matrix(cam)
	world_vec := M_Vec4f32{p.x, p.y, 0.0, 1.0}
	screen_vec := view*world_vec
	return screen_vec.xy
}


///////////////////////////////////////////////////////////
// RENDERER 2D
///////////////////////////////////////////////////////////
GFX_Vertex_2D :: struct {
	pos: M_Vec3f32,
	uv: M_Vec2f32,
	color: M_FColor,
}

GFX_Renderer_2D :: struct {
	vertex_buf: ^sdl.GPUBuffer,
	index_buf: ^sdl.GPUBuffer,
	transfer_buf: ^sdl.GPUTransferBuffer,
	depth_texture: ^sdl.GPUTexture,
	pipeline: ^sdl.GPUGraphicsPipeline,

	white_texture: GFX_Texture,

	num_vertices: u32,
	vertices: []GFX_Vertex_2D,
	num_indices: u32,
	indices: []GFX__Index,

	num_batches: int,
	batches: []GFX__Renderer_2D_Batch,

	layer: f32,
}

GFX_Text :: struct {
	chunks: []GFX__Text_Chunk,
}

GFX_create_renderer_2d :: proc(ren: ^GFX_Renderer_2D, width, height: int) {
	// buffers
	{
		vertex_buf_size := u32(size_of(GFX_Vertex_2D)*GFX__DEFAULT_MAX_VERTEX)
		ren.vertex_buf = sdl.CreateGPUBuffer(GFX__ctx.gpu, {
			usage = {.VERTEX},
			size = vertex_buf_size,
		})

		index_buf_size := u32(size_of(GFX__Index)*GFX__DEFAULT_MAX_INDEX)
		ren.index_buf = sdl.CreateGPUBuffer(GFX__ctx.gpu, {
			usage = {.INDEX},
			size = index_buf_size,
		})

		ren.transfer_buf = sdl.CreateGPUTransferBuffer(GFX__ctx.gpu, {
			usage = .UPLOAD,
			size = vertex_buf_size + index_buf_size,
		})
	}

	// depth texture
	{
		ren.depth_texture = sdl.CreateGPUTexture(GFX__ctx.gpu, {
			format = GFX__DEPTH_TEXTURE_FORMAT,
			usage = {.DEPTH_STENCIL_TARGET},
			width = u32(width),
			height = u32(height),
			layer_count_or_depth = 1,
			num_levels = 1,
		})
	}

	// pipeline
	{
		vert_shader: GFX_Shader
		frag_shader: GFX_Shader

		// load shader
		{
			code: []byte
			metadata_data: []byte

			ASST_load_file(&code, SHADER_2D_VERT_SPV)
			ASST_load_file(&metadata_data, SHADER_2D_VERT_META)
			GFX_load_shader(&vert_shader, code, metadata_data, .VERTEX)
			delete(code)
			delete(metadata_data)

			ASST_load_file(&code, SHADER_2D_FRAG_SPV)
			ASST_load_file(&metadata_data, SHADER_2D_FRAG_META)
			GFX_load_shader(&frag_shader, code, metadata_data, .FRAGMENT)
			delete(code)
			delete(metadata_data)
		}

		vertex_attrs := []sdl.GPUVertexAttribute{
			{
				location = 0,
				format = .FLOAT3,
				offset = u32(offset_of(GFX_Vertex_2D, pos)),
			},
			{
				location = 1,
				format = .FLOAT2,
				offset = u32(offset_of(GFX_Vertex_2D, uv)),
			},
			{
				location = 2,
				format = .FLOAT4,
				offset = u32(offset_of(GFX_Vertex_2D, color)),
			},
		}

		ren.pipeline = sdl.CreateGPUGraphicsPipeline(GFX__ctx.gpu, {
			vertex_shader = vert_shader.handle,
			fragment_shader = frag_shader.handle,
			vertex_input_state = {
				num_vertex_buffers = 1,
				vertex_buffer_descriptions = &sdl.GPUVertexBufferDescription{
					slot = 0,
					pitch = size_of(GFX_Vertex_2D), // vertex stride
				},
				num_vertex_attributes = u32(len(vertex_attrs)),
				vertex_attributes = raw_data(vertex_attrs),
			},
			primitive_type = .TRIANGLELIST,
			depth_stencil_state = {
				compare_op = .LESS,
				enable_depth_test = true,
				enable_depth_write = true,
			},
			target_info = {
				num_color_targets = 1,
				color_target_descriptions = &sdl.GPUColorTargetDescription{
					format = sdl.GetGPUSwapchainTextureFormat(GFX__ctx.gpu, GFX__ctx.window),
					blend_state = {
						src_color_blendfactor = .SRC_ALPHA,
						dst_color_blendfactor = .ONE_MINUS_SRC_ALPHA,
						color_blend_op = .ADD,
						src_alpha_blendfactor = .ONE,
						dst_alpha_blendfactor = .ONE,
						alpha_blend_op = .ADD,
						enable_blend = true,

					},
				},
				has_depth_stencil_target = true,
				depth_stencil_format = GFX__DEPTH_TEXTURE_FORMAT,
			},
		})


		// pipeline is created, shaders are not needed anymore
		GFX_unload_shader(&vert_shader)
		GFX_unload_shader(&frag_shader)
	}

	// white texture
	{
		img: GFX_Image
		GFX_load_image_from_color(&img, 1, 1, M_COLOR_WHITE)
		GFX_load_texture_from_image(&ren.white_texture, img)
		GFX_unload_image(&img)
	}

	ren.vertices = make([]GFX_Vertex_2D, GFX__DEFAULT_MAX_VERTEX)
	ren.indices = make([]GFX__Index, GFX__DEFAULT_MAX_INDEX)

	ren.batches = make([]GFX__Renderer_2D_Batch, GFX__DEFAULT_MAX_2D_BATCH)

	ren.layer = 0.1  // because 0.0 doesn't work
}

GFX_destroy_renderer_2d :: proc(ren: ^GFX_Renderer_2D) {
	delete(ren.batches)

	delete(ren.indices)
	delete(ren.vertices)

	sdl.ReleaseGPUTransferBuffer(GFX__ctx.gpu, ren.transfer_buf)
	sdl.ReleaseGPUBuffer(GFX__ctx.gpu, ren.index_buf)
	sdl.ReleaseGPUBuffer(GFX__ctx.gpu, ren.vertex_buf)
	sdl.ReleaseGPUTexture(GFX__ctx.gpu, ren.depth_texture)
	sdl.ReleaseGPUGraphicsPipeline(GFX__ctx.gpu, ren.pipeline)

	GFX_unload_texture(&ren.white_texture)

	ren^ = {}
}

GFX_begin_renderer_2d :: proc(ren: ^GFX_Renderer_2D) {
	ren.num_vertices = 0
	ren.num_indices = 0
	ren.num_batches = 0
	ren.batches[0] = {texture = ren.white_texture}
	ren.layer = 0.1
}

GFX_end_renderer_2d :: proc(ren: ^GFX_Renderer_2D) {
	if GFX__ctx.swapchain_tex == nil {
		return
	}

	ren.batches[ren.num_batches].num_indices = ren.num_indices - ren.batches[ren.num_batches].first_index

	win_size: [2]i32
	sdl.GetWindowSize(GFX__ctx.window, &win_size.x, &win_size.y)
	proj := linalg.matrix_ortho3d(0.0, f32(win_size.x), f32(win_size.y), 0.0, -500.0, 400.0, true)
	ubo := GFX__Renderer_2D_UBO{proj = proj}

	copy_cmd_buf := sdl.AcquireGPUCommandBuffer(GFX__ctx.gpu)
	copy_pass := sdl.BeginGPUCopyPass(copy_cmd_buf)
	// upload data to the buffers
	{
		vertices_byte_size := ren.num_vertices*size_of(GFX_Vertex_2D)
		indices_byte_size := ren.num_indices*size_of(GFX__Index)

		// copy the data into the transfer buffer
		transfer_mem := transmute([^]byte)sdl.MapGPUTransferBuffer(GFX__ctx.gpu, ren.transfer_buf, true)
		mem.copy(transfer_mem, raw_data(ren.vertices), int(vertices_byte_size))
		mem.copy(transfer_mem[vertices_byte_size:], raw_data(ren.indices), int(indices_byte_size))
		sdl.UnmapGPUTransferBuffer(GFX__ctx.gpu, ren.transfer_buf)

		// upload vertices to vertex buffer
		sdl.UploadToGPUBuffer(
			copy_pass,
			{transfer_buffer = ren.transfer_buf, offset = 0},
			{buffer = ren.vertex_buf, offset = 0, size = vertices_byte_size},
			true,
		)

		// upload vertices to index buffer
		sdl.UploadToGPUBuffer(
			copy_pass,
			{transfer_buffer = ren.transfer_buf, offset = vertices_byte_size},
			{buffer = ren.index_buf, offset = 0, size = indices_byte_size},
			true,
		)
	}
	sdl.EndGPUCopyPass(copy_pass)
	ok := sdl.SubmitGPUCommandBuffer(copy_cmd_buf)
	assert(ok)

	color_target := sdl.GPUColorTargetInfo{
		texture = GFX__ctx.swapchain_tex,
		clear_color = {0.1, 0.2, 0.4, 1.0},
		load_op = .CLEAR,
		store_op = .STORE,
	}
	depth_target := sdl.GPUDepthStencilTargetInfo{
		texture = ren.depth_texture,
		clear_depth = 1.0,
		load_op = .CLEAR,
		store_op = .DONT_CARE,
	}
	render_pass := sdl.BeginGPURenderPass(GFX__ctx.cmd_buf, &color_target, 1, &depth_target)
	sdl.BindGPUGraphicsPipeline(render_pass, ren.pipeline)
	sdl.BindGPUVertexBuffers(render_pass, 0, &sdl.GPUBufferBinding{buffer = ren.vertex_buf, offset = 0}, 1)
	sdl.BindGPUIndexBuffer(render_pass, {buffer = ren.index_buf}, ._32BIT)
	sdl.PushGPUVertexUniformData(GFX__ctx.cmd_buf, 0, &ubo, size_of(ubo))

	for batch, i in ren.batches[:ren.num_batches + 1] {
		sdl.BindGPUFragmentSamplers(
			render_pass,
			0,
			&sdl.GPUTextureSamplerBinding{
				texture = batch.texture.handle,
				sampler = batch.texture.sampler,
			},
			1,
		)
		sdl.DrawGPUIndexedPrimitives(render_pass, batch.num_indices, 1, batch.first_index, 0, 0)
	}

	sdl.EndGPURenderPass(render_pass)
}

GFX_set_renderer_2d_layer :: proc(ren: ^GFX_Renderer_2D, layer: f32) {
	ren.layer = layer + 0.1
	if ren.layer == 0.0 {
		ren.layer = 0.1
	}
}

GFX_draw_2d_triangle :: proc(
	ren: ^GFX_Renderer_2D,
	p1: M_Vec2f32, c1: M_Color,
	p2: M_Vec2f32, c2: M_Color,
	p3: M_Vec2f32, c3: M_Color,
) {
	ren.vertices[ren.num_vertices] = {
		{p1.x, p1.y, ren.layer},
		{0.0, 0.0},
		M_frgba_from_urgba(c1),
	}
	ren.indices[ren.num_indices] = ren.num_vertices
	ren.num_vertices += 1
	ren.num_indices += 1

	ren.vertices[ren.num_vertices] = {
		{p2.x, p2.y, ren.layer},
		{1.0, 0.0},
		M_frgba_from_urgba(c2),
	}
	ren.indices[ren.num_indices] = ren.num_vertices
	ren.num_vertices += 1
	ren.num_indices += 1

	ren.vertices[ren.num_vertices] = {
		{p3.x, p3.y, ren.layer},
		{1.0, 1.0},
		M_frgba_from_urgba(c3),
	}
	ren.indices[ren.num_indices] = ren.num_vertices
	ren.num_vertices += 1
	ren.num_indices += 1
}

GFX_draw_2d_rect :: proc(
	ren: ^GFX_Renderer_2D,
	rect: M_Rect,
	color: M_Color,
) {
	GFX__new_2d_batch_if_needed(ren, ren.white_texture)

	col := M_frgba_from_urgba(color)
	start_index := ren.num_vertices

	ren.vertices[ren.num_vertices] = {
		{rect.x, rect.y, ren.layer},
		{0.0, 0.0},
		col,
	}
	ren.num_vertices += 1

	ren.vertices[ren.num_vertices] = {
		{rect.x + rect.width, rect.y, ren.layer},
		{1.0, 0.0},
		col,
	}
	ren.num_vertices += 1

	ren.vertices[ren.num_vertices] = {
		{rect.x + rect.width, rect.y + rect.height, ren.layer},
		{1.0, 1.0},
		col,
	}
	ren.num_vertices += 1

	ren.vertices[ren.num_vertices] = {
		{rect.x, rect.y + rect.height, ren.layer},
		{0.0, 1.0},
		col,
	}
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
	ren: ^GFX_Renderer_2D,
	texture: GFX_Texture,
	source: M_Rect,
	dest: M_Rect,
	tint: M_Color,
) {
	GFX__new_2d_batch_if_needed(ren, texture)

	col := M_frgba_from_urgba(tint)
	start_index := ren.num_vertices

	src_min := M_Vec2f32{
		source.x/f32(texture.width),
		source.y/f32(texture.height),
	}
	src_max := M_Vec2f32{
		(source.x + source.width)/f32(texture.width),
		(source.y + source.height)/f32(texture.height),
	}

	ren.vertices[ren.num_vertices] = {
		{dest.x, dest.y, ren.layer},
		{src_min.x, src_min.y},
		col,
	}
	ren.num_vertices += 1

	ren.vertices[ren.num_vertices] = {
		{dest.x + dest.width, dest.y, ren.layer},
		{src_max.x, src_min.y},
		col,
	}
	ren.num_vertices += 1

	ren.vertices[ren.num_vertices] = {
		{dest.x + dest.width, dest.y + dest.height, ren.layer},
		{src_max.x, src_max.y},
		col,
	}
	ren.num_vertices += 1

	ren.vertices[ren.num_vertices] = {
		{dest.x, dest.y + dest.height, ren.layer},
		{src_min.x, src_max.y},
		col,
	}
	ren.num_vertices += 1

	ren.indices[ren.num_indices + 0] = start_index + 0
	ren.indices[ren.num_indices + 1] = start_index + 1
	ren.indices[ren.num_indices + 2] = start_index + 2
	ren.indices[ren.num_indices + 3] = start_index + 0
	ren.indices[ren.num_indices + 4] = start_index + 2
	ren.indices[ren.num_indices + 5] = start_index + 3
	ren.num_indices += 6
}

GFX_create_text :: proc(text: ^GFX_Text, encoded_text: string) {
	// #assert(false, "IMPLEMENTATION")
}



@(private="file")
GFX__Renderer_2D_Batch :: struct {
	first_index: u32,
	num_indices: u32,
	texture: GFX_Texture,
}

@(private="file")
GFX__Renderer_2D_UBO :: struct {
	proj: linalg.Matrix4f32,
}

@(private="file")
GFX__Text_Chunk :: struct {
	options: GFX__Text_Chunk_Options,
	text: string,
}

@(private="file")
GFX__Text_Chunk_Options :: struct {
	color: M_Color,
}

@(private="file")
GFX__new_2d_batch_if_needed :: proc(ren: ^GFX_Renderer_2D, tex: GFX_Texture) {
	if ren.batches[ren.num_batches].texture != tex {
		ren.batches[ren.num_batches].num_indices = ren.num_indices - ren.batches[ren.num_batches].first_index
		ren.num_batches += 1
		ren.batches[ren.num_batches].first_index = ren.num_indices
		ren.batches[ren.num_batches].texture = tex
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
