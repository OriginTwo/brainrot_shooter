package game

import "core:math"
import "core:math/linalg"

M_Vec2f32 :: [2]f32
M_Vec3f32 :: [3]f32
M_Vec4f32 :: [4]f32

M_Color :: distinct [4]u8
M_FColor :: distinct [4]f32

M_Rect :: struct {
	x: f32,
	y: f32,
	width: f32,
	height: f32,
}

M_COLOR_BLANK   :: M_Color{  0,   0,   0,   0}
M_COLOR_BLACK   :: M_Color{  0,   0,   0, 255}
M_COLOR_WHITE   :: M_Color{255, 255, 255, 255}
M_COLOR_RED     :: M_Color{255,   0,   0, 255}
M_COLOR_GREEN   :: M_Color{  0, 255,   0, 255}
M_COLOR_BLUE    :: M_Color{  0,   0, 255, 255}
M_COLOR_YELLOW  :: M_Color{255, 255,   0, 255}
M_COLOR_MAGENTA :: M_Color{255,   0, 255, 255}
M_COLOR_CYAN    :: M_Color{  0, 255, 255, 255}

M_FCOLOR_BLANK   :: M_FColor{0.0, 0.0, 0.0, 0.0}
M_FCOLOR_BLACK   :: M_FColor{0.0, 0.0, 0.0, 1.0}
M_FCOLOR_WHITE   :: M_FColor{1.0, 1.0, 1.0, 1.0}
M_FCOLOR_RED     :: M_FColor{1.0, 0.0, 0.0, 1.0}
M_FCOLOR_GREEN   :: M_FColor{0.0, 1.0, 0.0, 1.0}
M_FCOLOR_BLUE    :: M_FColor{0.0, 0.0, 1.0, 1.0}
M_FCOLOR_YELLOW  :: M_FColor{1.0, 1.0, 0.0, 1.0}
M_FCOLOR_MAGENTA :: M_FColor{1.0, 0.0, 1.0, 1.0}
M_FCOLOR_CYAN    :: M_FColor{0.0, 1.0, 1.0, 1.0}

M_make_vec4f32_from_vec2f32 :: #force_inline proc(v: M_Vec2f32, a, b: f32) -> M_Vec4f32 {
	return {v.x, v.y, a, b}
}

M_make_vec4f32_from_vec3f32 :: #force_inline proc(v: M_Vec3f32, a: f32) -> M_Vec4f32 {
	return {v.x, v.y, v.z, a}
}

M_make_vec4f32 :: proc {
	M_make_vec4f32_from_vec2f32,
	M_make_vec4f32_from_vec3f32,
}

M_is_equal_approx :: proc(a, b: f32, margin: f32 = math.F32_EPSILON) -> bool {
	return abs(a - b) <= margin
}

M_minmax :: proc(a, b: f32) -> (min_val, max_val: f32) {
	min_val = min(a, b)
	max_val = max(a, b)
	return
}

M_swap_minmax :: proc(min_val, max_val: ^f32) {
	if min_val^ > max_val^ {
		temp := min_val^
		min_val^ = max_val^
		max_val^ = temp
	}
}

// all components are [0, 1]
M_hsva_from_frgba :: proc(rgba: M_FColor) -> M_FColor {
	c_max := max(rgba.r, rgba.g, rgba.b)
	c_min := min(rgba.r, rgba.g, rgba.b)
	range := c_max - c_min
	hue :=
		0.0                                          if c_max == 0.0 else
		math.mod((rgba.g - rgba.b)/range + 6.0, 6.0) if c_max == rgba.r else
		(rgba.b - rgba.r)/range + 2.0                if c_max == rgba.g else
		(rgba.r - rgba.g)/range + 4.0                if c_max == rgba.b else
		0.0
	sat := 0.0 if c_max == 0.0 else range/c_max
	val := c_max
	return {hue/6.0, sat, val, rgba.a}
}

M_frgba_from_hsva :: proc(hsva: M_FColor) -> M_FColor {
	hue := math.mod(hsva.x*360.0, 360.0)
	sat := hsva.y
	val := hsva.z

	c := val*sat
	x := c*(1.0 - abs(math.mod(hue/60.0, 2.0) - 1.0))

	r: f32
	g: f32
	b: f32

	switch hue {
	case 0.0..<60.0, 360.0:
		r = c
		g = x
		b = 0.0
	case 60.0..<120.0:
		r = x
		g = c
		b = 0.0
	case 120.0..<180.0:
		r = 0.0
		g = c
		b = x
	case 180.0..<240.0:
		r = 0.0
		g = x
		b = c
	case 240.0..<300.0:
		r = x
		g = 0.0
		b = c
	case 300.0..<360.0:
		r = c
		g = 0.0
		b = x
	}

	m := val - c
	return {r + m, g + m, b + m, hsva.a}
}

M_frgba_from_urgba :: proc(rgba: M_Color) -> M_FColor {
	return {
		f32(rgba.r)/255.0,
		f32(rgba.g)/255.0,
		f32(rgba.b)/255.0,
		f32(rgba.a)/255.0,
	}
}

M_frgba_from_hex :: proc(hex: u32) -> M_FColor {
	return {
		f32((hex >> 24) & 0xff)/255.0,
		f32((hex >> 16) & 0xff)/255.0,
		f32((hex >>  8) & 0xff)/255.0,
		f32((hex >>  0) & 0xff)/255.0,
	}
}

M_hex_from_frgba :: proc(rgba: M_FColor) -> u32 {
	return (
		u32(rgba.r*255.0) << 24 |
		u32(rgba.r*255.0) << 16 |
		u32(rgba.r*255.0) <<  8 |
		u32(rgba.r*255.0) <<  0
	)
}

M_urgba_from_frgba :: proc(rgba: M_FColor) -> M_Color {
	return {
		u8(rgba.r*255.0),
		u8(rgba.g*255.0),
		u8(rgba.b*255.0),
		u8(rgba.a*255.0),
	}
}

M_urgba_from_hex :: proc(hex: u32) -> M_Color {
	return {
		u8((hex >> 24) & 0xff),
		u8((hex >> 16) & 0xff),
		u8((hex >>  8) & 0xff),
		u8((hex >>  0) & 0xff),
	}
}

M_lerp_colors :: proc(colors: [][5]f32, t: f32) -> M_FColor {
	if len(colors) < 2 {
		return {}
	}

	color_x: f32
	segment_range: f32
	segment_index := len(colors) - 1
	#reverse for c in colors {
		if t >= c[0] {
			if segment_index == len(colors) - 1 {
				segment_range = 1.0 - c[0]
			} else {
				segment_range = colors[segment_index + 1][0] - c[0]
			}
			color_x = c[0]
			break
		}
		segment_index -= 1
	}

	local_t := clamp((t - color_x)/segment_range, 0.0, 1.0)

	result: M_FColor
	if segment_index == len(colors) - 1 {
		result = swizzle(colors[segment_index], 1, 2, 3, 4)
	} else {
		result = swizzle(math.lerp(
			colors[segment_index + 0],
			colors[segment_index + 1],
			local_t,
		), 1, 2, 3, 4)
	}
	return result
}

M_sample_spline :: proc(points: []M_Vec2f32, t: f32) -> (M_Vec2f32, bool) #optional_ok {
	if (len(points) - 1) % 3 != 0 {
		return {}, false
	}

	segment_count := (len(points) - 1)/3

	global_t := t*f32(segment_count)
	segment_index := int(global_t)
	local_t := global_t - f32(segment_index)

	if segment_index >= segment_count {
		segment_index = segment_count - 1
		local_t = 1.0
	}

	return linalg.cubic(
		points[segment_index*3 + 0], // start
		points[segment_index*3 + 1], // control 1
		points[segment_index*3 + 2], // control 2
		points[segment_index*3 + 3], // end
		local_t,
	), true
}

M_bake_spline :: proc(points: []M_Vec2f32, sample_per_segment: int = 16) -> []M_Vec2f32 {
	segment_count := len(points) - 1
	total_sample := segment_count*sample_per_segment
	t_step := 1.0/f32(total_sample)

	result := make([]M_Vec2f32, total_sample + 1)

	for i in 0..=total_sample {
		result[i] = M_sample_spline(points, f32(i)/f32(total_sample))
	}

	return result
}
