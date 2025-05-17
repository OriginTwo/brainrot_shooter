package game

import "core:math"
import "core:math/rand"
import "core:strings"
import "core:strconv"

import rl "vendor:raylib"

import "core:fmt"

/*
#assert(false, "REMOVE RAYLIB")

TEXT_Origin :: enum {
	BEGIN,   // left/top
	CENTER,  // center
	END,     // right/bottom
}

TEXT_get_display_string :: proc(text: string, allocator := context.allocator) -> string {
	result := make([dynamic]byte, allocator)
	str := text
	for len(str) > 0 {
		char: byte
		str, char = TEXT__get_next_display_char(str, nil)
		append(&result, char)
	}
	return transmute(string)result[:]
}

// this (should) only works for single line string
// returns the number display characters rendered
TEXT_draw :: proc(
	font: rl.Font,
	text: string,
	position: Vec2f32,
	color: rl.Color,
	progress: int = -1,
	origin: [2]TEXT_Origin = {.BEGIN, .BEGIN},
	scale: f32 = 1.0,
	spacing: f32 = 0.0,
	options: ^TXT__Draw_Options = nil,
) -> int {
	if progress <= 0 {
		return 0
	}

	opts: TXT__Draw_Options
	opts.scale = 1.0
	if options != nil {
		opts = options^
	}

	display_str := strings.clone_to_cstring(
		TEXT_get_display_string(text, context.temp_allocator),
		context.temp_allocator,
	)
	text_size := rl.MeasureTextEx(
		font,
		display_str,
		f32(font.baseSize)*scale*opts.scale,
		spacing,
	)

	position := position
	for i in 0..<2 {
		switch origin[i] {
		case .BEGIN:
		case .CENTER: position[i] -= text_size[i]/2.0
		case .END:    position[i] -= text_size[i]
		}
	}
	pos := position

	str := text
	phase := f32(0.0)
	rendered_count := 0
	for len(str) > 0 {
		if progress > 0 && rendered_count >= progress {
			break
		}

		char: byte
		str, char = TEXT__get_next_display_char(str, &opts)
		if char == 0 {
			break
		}

		wave_offset := opts.wave_amp*math.sin(phase + opts.wave_freq*f32(rl.GetTime()))
		shake_offset := Vec2f32{
			rand.float32_range(-opts.shake_size, opts.shake_size),
			rand.float32_range(-opts.shake_size, opts.shake_size),
		}
		col := color if opts.color == {} else opts.color

		rl.DrawTextCodepoint(font, rune(char), pos + shake_offset + {0.0, wave_offset}, f32(font.baseSize)*scale*opts.scale, col)

		info := rl.GetGlyphInfo(font, rune(char))
		pos.x += f32(info.advanceX)*scale*opts.scale + spacing

		phase += opts.wave_phase
		rendered_count += 1
	}

	if options != nil {
		options^ = opts
	}

	return rendered_count
}

// returns the number display characters rendered
TEXT_draw_line_wrap :: proc(
	font: rl.Font,
	text: string,
	position: Vec2f32,
	width: f32,
	color: rl.Color,
	progress: int = -1,
	origin: [2]TEXT_Origin = {.BEGIN, .BEGIN},
	scale: f32 = 1.0,
	spacing: Vec2f32 = {0.0, 0.0},
) -> int {
	if progress <= 0 {
		return 0
	}

	opts: TXT__Draw_Options
	opts.scale = 1.0

	words := strings.split_multi(text, {"\t", "\n", "\v", "\f", "\r", " "}, context.temp_allocator)

	display_str := TEXT_get_display_string(text, context.temp_allocator)
	display_words := strings.split_multi(display_str, {"\t", "\n", "\v", "\f", "\r", " "}, context.temp_allocator)

	pos := position
	line_width: f32
	curr_progress := 0
	rendered_count := 0

	for word, i in display_words {
		if progress > 0 && curr_progress >= progress {
			break
		}

		word_width := rl.MeasureTextEx(
			font,
			fmt.ctprintf("%s ", word) if origin.x == .BEGIN else strings.clone_to_cstring(word, context.temp_allocator),
			f32(font.baseSize)*scale*opts.scale,
			spacing.x,
		).x

		if line_width + word_width >= width {
			pos.x = position.x
			pos.y += f32(font.baseSize)*scale*opts.scale + spacing.y
			line_width = 0.0
		}

		rendered_count += TEXT_draw(font, words[i], pos, color, progress - curr_progress, origin, scale, spacing.x, &opts)
		pos.x += word_width
		line_width += word_width
		curr_progress += len(word)
	}

	return rendered_count
}



/*
<wave;amp=1;freq=1;phase=1>wavey text</wave>
<shake;size=2>shakey text</shake>
<scale;scale=2.0>scaled text</scale>
<color;hex=rrggbbaa>colored text</color>

<wave><shake>adsf></wave>adsfsdf</shake>
*/

@(private="file")
TXT__Draw_Options :: struct {
	wave_amp: f32,
	wave_freq: f32,
	wave_phase: f32,
	shake_size: f32,
	scale: f32,
	color: rl.Color,
}

@(private="file")
TEXT__get_next_display_char :: proc(text: string, opt: ^TXT__Draw_Options) -> (string, byte) {
	next_char_pos := 0
	str := text

	// loop in case command in chained with nothing in between
	for _ in 0..<8 {
		if len(str) == 0 {
			break
		}

		if str[0] != '<' {
			break
		}

		opt_str: string
		for i := 1; i < len(str); i += 1 {
			ch := str[i]
			if ch == '>' {
				next_char_pos = i + 1
				opt_str = str[1:i]
				break
			}
		}


		if opt != nil {
			opt_args := strings.split(opt_str, ";", context.temp_allocator)
			switch opt_args[0] {
			case "wave":
				if len(opt_args) == 4 {
					for i in 1..<4 {
						split_pos := strings.index_byte(opt_args[i], '=')
						arg_name := opt_args[i][:split_pos]
						arg_val := opt_args[i][split_pos + 1:]
						if val, val_ok := strconv.parse_f32(arg_val); val_ok {
							switch arg_name {
							case "amp":   opt.wave_amp = val
							case "freq":  opt.wave_freq = val
							case "phase": opt.wave_phase = val
							}
						}
					}
				}

			case "/wave":
				opt.wave_amp = 0.0
				opt.wave_freq = 0.0
				opt.wave_phase = 0.0

			case "shake":
				if len(opt_args) == 2 {
					split_pos := strings.index_byte(opt_args[1], '=')
					arg_name := opt_args[1][:split_pos]
					arg_val := opt_args[1][split_pos + 1:]
					if val, val_ok := strconv.parse_f32(arg_val); val_ok {
						switch arg_name {
						case "size": opt.shake_size = val
						}
					}
				}

			case "/shake":
				opt.shake_size = 0.0

			case "scale":
				if len(opt_args) == 2 {
					split_pos := strings.index_byte(opt_args[1], '=')
					arg_name := opt_args[1][:split_pos]
					arg_val := opt_args[1][split_pos + 1:]
					if val, val_ok := strconv.parse_f32(arg_val); val_ok {
						switch arg_name {
						case "scale": opt.scale = val
						}
					}
				}

			case "/scale":
				opt.scale = 1.0

			case "color":
				if len(opt_args) == 2 {
					split_pos := strings.index_byte(opt_args[1], '=')
					arg_name := opt_args[1][:split_pos]
					arg_val := opt_args[1][split_pos + 1:]
					if val, val_ok := strconv.parse_uint(arg_val, 16); val_ok {
						switch arg_name {
						case "hex": opt.color = transmute(rl.Color)rgba8_from_hex(u32(val))
						}
					}
				}

			case "/color":
				opt.color = rl.WHITE
			}
		}

		str = str[next_char_pos:]
	}

	if len(str) == 0 {
		return "", 0
	}

	return str[1:], str[0]
}
*/
