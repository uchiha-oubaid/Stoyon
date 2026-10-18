package stoyon
import "core:fmt"
import "core:os"
import "core:log"
import "core:time"
import "core:strings"
import "core:math"
import "core:math/rand"
import rl "vendor:raylib"

BACKGROUND_COLOR			:: 0x181818FF
TOOLTIP_BACKGROUND_COLOR	:: 0x242424FF
TEXT_COLOR					:: 0xE4E4E4FF
PAUSED_TEXT_COLOR			:: 0xA0A0A0FF
FONT_PATH					:: "./res/fonts/JetBrainsMonoNLNerdFont-Bold.ttf"
FONT_BASE_SIZE				:: 128
TIMER_ATLAS_WIDTH			:: 1890
TIMER_ATLAS_HEIGHT			:: 340
TIMER_CELL_WIDTH			:: TIMER_ATLAS_WIDTH/11
DEFAULT_CONFIG_PATH			:: "~/.config/stoyon/"
TIMER_CHARACTER_COUNT       :: 8

task_message: strings.Builder;
is_editing_task := false;
task_color: rl.Color = rl.GetColor(PAUSED_TEXT_COLOR);
task_row: f32 = 0;
cursor_col, cursor_row: f32 = 0, 0;

Types :: union {
	f32,
	string,
	bool
}

is_dir_here :: proc() -> bool {
	result := run_command("mkdir", DEFAULT_CONFIG_PATH)
	return result
}

make_config :: proc(){
	if !is_dir_here() do run_command("mkdir", "-p", DEFAULT_CONFIG_PATH)
}

show_tooltip :: proc(font: rl.Font, message: cstring, pos: rl.Vector2) {
    text_margin: f32 = 30
    margined_pos: rl.Vector2 = pos + text_margin
    message_size := rl.MeasureTextEx(font, message, 20, 2)

    tooltip_rec: rl.Rectangle = {
        x = pos.x,
        y = pos.y,
        width = message_size.x + text_margin*2,
        height = message_size.y + text_margin*2,
    }

    roundness: f32 = 0.2
    segments : i32 = 1
    rl.DrawRectangleRounded(tooltip_rec, roundness, segments, rl.GetColor(TOOLTIP_BACKGROUND_COLOR))
    rl.DrawRectangleRoundedLinesEx(tooltip_rec, roundness, segments, 3, rl.WHITE)
    rl.DrawTextEx(font, message, margined_pos, 20, 2, rl.GetColor(TEXT_COLOR))
}

run_command :: proc(commands: ..string) -> bool {
    state, stdout, stderr, err := os.process_exec({command = commands}, context.allocator)
    defer delete(stderr)
    defer delete(stdout)

    if err != nil do return false
    return true
}

search_args :: proc(args: []string, arg: string) -> int {
    i := 0
    for i < len(args) - 1 && args[i] != arg do i += 1
    if i < len(args) - 1 do return i
    return len(args) - 1
}

main :: proc() {
    // TODO: make the "music-dir" & "music-covers-dir" customizable
    // TODO: (2) add a mechanism of downloading covers and music with a link (Linux only for now)
	make_config()
    music_cover_dir: cstring = "./res/covers/"
    music_covers := rl.LoadDirectoryFilesEx(music_cover_dir, "png", true)
    last_music_cover_index := u32(music_covers.count)
    current_music_cover_index := rand.uint32_range(0, u32(music_covers.count))

    default_music_folder: cstring = "/home/oubaid/Music/chiptunes/"
    music_list := rl.LoadDirectoryFiles(default_music_folder)
    current_music_index := rand.uint32_range(0, music_list.count)

    // (2) -> almost
    if len(os.args) > 1 {
		if os.args[1] == "-h" || os.args[1] == "--help" {
			print_help()
			return
		}
        cover_index := search_args(os.args, "-cover")
        music_index := search_args(os.args, "-music")
        if cover_index < len(os.args) - 1 {
            output_path := fmt.tprintf("%v%v%v", music_cover_dir, last_music_cover_index+1,
                             rl.GetFileExtension(strings.clone_to_cstring(os.args[cover_index+1])))
            run_command("aria2c", os.args[cover_index+1], "-o", output_path)

            // convert it to png and delete the jpg because raylib does support jpgs
            // or any other image file type
            // just use png
            // it filters them only in line 66

            png_output_path := fmt.tprintf("%v%v.png", music_cover_dir, rl.GetFileNameWithoutExt(strings.clone_to_cstring(output_path)))
            run_command("magick", output_path, png_output_path)
            run_command("rm", "-rf", output_path)
        } else if music_index < len(os.args) - 1 {
            run_command("aria2c", os.args[music_index+1]) // TODO: finish this
        } else {
            fmt.println("Error: invalid arguments")
        }
        return
    }

	input_file := "config.mini"
	file_data, open_err := os.read_entire_file(input_file, context.temp_allocator)
	if open_err != nil {
		fmt.eprintf("Error: File \"%v\" not found!\n", input_file)
		os.exit(1)
	}

	file_map := parse_config_file(file_data)
	s_width, s_height := i32(file_map["width"].(f32)), i32(file_map["height"].(f32))
    rl.SetConfigFlags({.MSAA_4X_HINT, .WINDOW_RESIZABLE, .WINDOW_ALWAYS_RUN, .VSYNC_HINT})
    rl.InitWindow(s_width, s_height, "Stoyon")
    defer rl.CloseWindow()
	rl.SetExitKey(.KEY_NULL)
	rl.InitAudioDevice()

    camera: rl.Camera2D
	camera.rotation = 0
	camera.zoom = 1
    camera.offset = {0, 0}
    camera.target = {0, 0}

	fps := i32(file_map["fps"].(f32))
	rl.SetTargetFPS(fps)

    // generate random stuff
	seed := time.time_to_unix(time.now())
	r := rand.create(u64(seed))
    context.random_generator = rand.default_random_generator(&r)

    // Load smooth font
    fileSize: i32 = 0
    fileData := rl.LoadFileData(FONT_PATH, &fileSize)
    if fileData == nil {
        fmt.eprintf("Error: Font not valid\n")
        os.exit(1)
    }

    font: rl.Font = {}
    font.baseSize = FONT_BASE_SIZE
    font.glyphCount = 95
    font.glyphPadding = 0
    font.glyphs = rl.LoadFontData(fileData, fileSize, FONT_BASE_SIZE, nil, 0, .SDF, &font.glyphCount)
    rl.UnloadFileData(fileData)

    if font.glyphs == nil {
        fmt.eprintf("Error: glyphs == nil\n")
        os.exit(1)
    }

    atlas := rl.GenImageFontAtlas(font.glyphs, &font.recs, font.glyphCount, font.baseSize, 0, 0)
    font.texture = rl.LoadTextureFromImage(atlas)
    rl.UnloadImage(atlas)
    rl.SetTextureFilter(font.texture, .BILINEAR)

	music_image := rl.LoadTexture(music_covers.paths[current_music_cover_index])
	defer rl.UnloadTexture(music_image)

	// the message
	strings.builder_init(&task_message)
	defer strings.builder_destroy(&task_message)

	music_image_src: rl.Rectangle = {
		x		= 0,
		y		= 0,
		width	= f32(music_image.width),
		height	= f32(music_image.height)
	}
	
    time_text_spacing: f32 = 5
    curren_music_path := music_list.paths[current_music_index]
	current_music := rl.LoadMusicStream(curren_music_path)
	defer rl.UnloadMusicStream(current_music)

    zoom_in_out: f32 = 0.25
    volume: f32 = 0.5
    max_volume, min_volume: f32 = 1, 0

    timer_atlas := rl.LoadTexture("./res/timer_atlas.png")
    defer rl.UnloadTexture(timer_atlas)
    rl.SetTextureFilter(timer_atlas, .BILINEAR)
    text_color := rl.GetColor(PAUSED_TEXT_COLOR)

    // TEST
    stopwatch: time.Stopwatch

    for !rl.WindowShouldClose() {
        free_all(context.temp_allocator)

        width := f32(rl.GetScreenWidth())
		height := f32(rl.GetScreenHeight())
        mouse := rl.GetMousePosition()
		dt := rl.GetFrameTime()
		margin: f32 = 20
        time_text_size: f32 = height*0.03

        f :: proc(x: f32) -> f32 {
            return math.sqrt(1 - math.pow(x - 1, 2))
        }
        if is_zooming() do camera.target = math.lerp(camera.target,
            camera.target-rl.GetMouseDelta(), f(dt*15))

        if rl.IsKeyPressed(.D) {
            camera.target = {0, 0}
            camera.zoom = 1
        }

        if rl.IsMusicStreamPlaying(current_music) {
            text_color = rl.GetColor(TEXT_COLOR)
        } else {
            text_color = rl.GetColor(PAUSED_TEXT_COLOR)
        }

        rl.UpdateMusicStream(current_music)
        rl.SetMusicVolume(current_music, volume)
        music_time_percentage: f32 = rl.GetMusicTimePlayed(current_music) / rl.GetMusicTimeLength(current_music)

        if rl.IsKeyPressed(.R) && !is_editing_task do rl.StopMusicStream(current_music)

		if rl.IsKeyPressed(.SPACE) && !is_editing_task {
            if !rl.IsMusicStreamPlaying(current_music) {
                if music_time_percentage == 0 do rl.PlayMusicStream(current_music)
                rl.ResumeMusicStream(current_music)
                time.stopwatch_start(&stopwatch)
            } else {
                rl.PauseMusicStream(current_music)
                time.stopwatch_stop(&stopwatch)
            }
        }

        if (rl.IsKeyPressed(.UP) || rl.IsKeyPressed(.K)) && !is_editing_task {
            volume += 0.25
            if volume > max_volume do volume = max_volume
        }

        if (rl.IsKeyPressed(.DOWN) || rl.IsKeyPressed(.J)) && !is_editing_task {
            volume -= 0.25
            if volume < min_volume do volume = min_volume
        }

        // change between the tracks
        if (rl.IsKeyPressed(.LEFT) || rl.IsKeyPressed(.H)) && !is_editing_task {
            if current_music_index == 0 {
                current_music_index = u32(music_list.count) - 1
            } else {
                current_music_index -= 1
            }

            // reload the music
            rl.UnloadMusicStream(current_music)
            curren_music_path = music_list.paths[current_music_index]
            current_music = rl.LoadMusicStream(curren_music_path)

            // reload the music cover
            if current_music_cover_index == 0 {
                current_music_cover_index = u32(music_covers.count) - 1
            }
            else {
                current_music_cover_index -= 1
            }

            rl.UnloadTexture(music_image)
            music_image = rl.LoadTexture(music_covers.paths[current_music_cover_index])
            music_image_src = {
                x		= 0,
                y		= 0,
                width	= f32(music_image.width),
                height	= f32(music_image.height)
            }
            
            if rl.IsMusicValid(current_music) && music_time_percentage > 0 do rl.PlayMusicStream(current_music)
        }

        if (rl.IsKeyPressed(.RIGHT) || rl.IsKeyPressed(.L)) && !is_editing_task {
            if current_music_index == u32(music_list.count) - 1 {
                current_music_index = 0
            } else {
                current_music_index += 1
            }

            // reload the music
            rl.UnloadMusicStream(current_music)
            curren_music_path = music_list.paths[current_music_index]
            current_music = rl.LoadMusicStream(curren_music_path)

            // reload the music cover
            if current_music_cover_index == u32(music_covers.count) - 1 {
                current_music_cover_index = 0
            }
            else {
                current_music_cover_index += 1
            }

            rl.UnloadTexture(music_image)
            music_image = rl.LoadTexture(music_covers.paths[current_music_cover_index])
            music_image_src = {
                x		= 0,
                y		= 0,
                width	= f32(music_image.width),
                height	= f32(music_image.height)
            }

            if rl.IsMusicValid(current_music) && music_time_percentage > 0 do rl.PlayMusicStream(current_music)
        }


        if rl.IsKeyDown(.LEFT_CONTROL) && rl.IsKeyPressed(.EQUAL) {
            camera.zoom += zoom_in_out
        } else if rl.IsKeyDown(.LEFT_CONTROL) && rl.IsKeyPressed(.SIX) { // for french keyboard (I use it)
            camera.zoom -= zoom_in_out
        }

        hours, mins, _ := time.clock_from_time(time.now())
		time_text := fmt.ctprintf("%02d:%02d", hours + 1, mins)
		time_dimensions := rl.MeasureTextEx(font, time_text, time_text_size, time_text_spacing)
        year, month, day := time.date(time.now())

        date := fmt.ctprintf("%02v/%02d/%v", day, month, year)
		date_dimensions := rl.MeasureTextEx(font, date, time_text_size, time_text_spacing)

		music_image_size := width*0.25
		music_image_dest: rl.Rectangle = {
			x = width*0.1,
			y = height*0.1,
			width  = music_image_size,
			height = music_image_size
		}

        timer_margin: f32 = width*0.1
        timer_scale: f32 = width*0.00037
        timer_dest: rl.Rectangle = {
            x = music_image_dest.x + music_image_dest.width + timer_margin,
            y = music_image_dest.y + (music_image_dest.height - TIMER_ATLAS_HEIGHT*timer_scale)/2,
            width = TIMER_CELL_WIDTH*timer_scale,
            height = TIMER_ATLAS_HEIGHT*timer_scale
        }

		task_width := timer_dest.width*TIMER_CHARACTER_COUNT*0.5
		task_bounds: rl.Rectangle = {
			x = timer_dest.x + (timer_dest.width*TIMER_CHARACTER_COUNT - task_width)*0.5,
			y = timer_dest.y + timer_dest.height + margin,
			width = task_width,
			height = timer_dest.height*0.75
		}


		if rl.IsKeyPressed(.I) && !is_editing_task {
			is_editing_task = true
			task_color = rl.GetColor(TEXT_COLOR)
		}

		if !rl.CheckCollisionPointRec(mouse, task_bounds) {
			if rl.IsMouseButtonDown(.LEFT) {
				is_editing_task = false
				task_color = rl.GetColor(PAUSED_TEXT_COLOR)
			}
		}

		is_typable :: proc(char: rune) -> bool {
			return u32(char) >= 32 && u32(char) <= 125;
		}

		cursor_width  := task_bounds.width*0.05
		cursor_height := task_bounds.height*0.25
		cursor_bounds: rl.Rectangle = {
			x = (task_bounds.x + margin*0.5) + cursor_col*cursor_width,
			y = (task_bounds.y + margin*0.5) + cursor_row*cursor_height,
			width = cursor_width,
			height = cursor_height
		}

		// TODO: Add a cursor
		if is_editing_task {
			char := rl.GetCharPressed();
			key := rl.GetKeyPressed();

			if rl.IsKeyPressed(.ESCAPE) {
				is_editing_task = false
				task_color = rl.GetColor(PAUSED_TEXT_COLOR)
			}
			
			if u32(char) > 0 || key != .KEY_NULL {
				if u32(char) >= 32 && u32(char) <= 125 {
					cursor_col += 1
					strings.write_rune(&task_message, char);
				}

				if key == .BACKSPACE {
					if cursor_col > 0 do cursor_col -= 1
					strings.pop_rune(&task_message);
				} else if key == .ENTER {
					cursor_row += 1
					cursor_col = 0
					strings.write_rune(&task_message, '\n');
					strings.write_rune(&task_message, '\t');
				}
			}
		}

        rl.BeginDrawing()
        rl.BeginMode2D(camera)
        rl.ClearBackground(rl.GetColor(BACKGROUND_COLOR))
		time_pos: rl.Vector2 = {
			width - time_dimensions.x - margin,
			margin
		}

        rl.DrawTexturePro(music_image, music_image_src, music_image_dest, {0, 0}, 0, rl.WHITE)
        rl.DrawTextEx(font, time_text, time_pos, time_text_size, time_text_spacing, text_color)
        rl.DrawTextEx(font, date, {time_pos.x - date_dimensions.x - margin,
                                   time_pos.y}, time_text_size, time_text_spacing, text_color)

        music_title_font_size := music_image_dest.width*0.08
		music_title := fmt.ctprintf("* %v *", rl.GetFileNameWithoutExt(curren_music_path))
        title_size := rl.MeasureTextEx(font, music_title, music_title_font_size, time_text_spacing)

		rl.DrawTextEx(font, music_title,
					  {music_image_dest.x + (music_image_dest.width - title_size.x)*0.5,
					   music_image_dest.y + music_image_dest.height + margin*2},
					   music_title_font_size, time_text_spacing, text_color)

		music_time_line_thickness: f32 = title_size.y*0.125
		music_time_line_bounds: rl.Rectangle = {
			x = music_image_dest.x,
			y = music_image_dest.y + music_image_dest.height + margin*0.5,
			width = math.clamp(f32(0), margin*0.5 + music_time_percentage*music_image_dest.width, music_image_dest.width),
			height = music_time_line_thickness
		}
		
		rl.DrawRectangleRec(music_time_line_bounds, rl.WHITE)
		// if is_editing_task do rl.DrawRectangleLinesEx(task_bounds, 2, task_color)

		rl.DrawTextEx(font, strings.to_cstring(&task_message),
					  {task_bounds.x + margin*0.5, (task_bounds.y + margin*0.5) + task_bounds.height*task_row},
					  task_bounds.height*0.25,
					  2,
					  task_color)

		if is_editing_task do rl.DrawRectangleRec(cursor_bounds, task_color);

        // Timer
        // TODO: add a correct stopwatch logic
        s_hours, s_mins, s_secs := time.clock_from_stopwatch(stopwatch)
        timer_text := fmt.tprintf("%02d:%02d:%02d", s_hours, s_mins, s_secs)
        render_timer(timer_text, timer_atlas, timer_dest, text_color)

        // tooltips must be last thing to render
        if rl.CheckCollisionPointRec(mouse, music_image_dest) {
            if !is_zooming() do show_tooltip(
                font, 
                "* <left>&<right> to move between tracks.\n* <space> to pause/unpause the current track.\n* <up>&<down> to increase/decrease tracks sound.",
                mouse
            )
        }

        rl.EndMode2D()
		rl.EndDrawing()

		if rl.IsKeyPressed(.A) && !is_editing_task {
			log.infof("Window Closed.\n");
			os.exit(0);
		}
    }
}

Num :: enum i32 {
    ZERO = 0,
    ONE,
    TWO,
    THREE,
    FOUR,
    FIVE,
    SIX,
    SEVEN,
    EIGHT,
    NINE,
    TWO_POINTS
}

is_zooming :: proc() -> bool {
    return rl.IsMouseButtonDown(.LEFT) && rl.IsKeyDown(.LEFT_CONTROL)
}

render_timer :: proc(time_text: string, timer_atlas: rl.Texture2D, timer_dest: rl.Rectangle, color: rl.Color) {
    for char, i in time_text {
        dest: rl.Rectangle = {
            x = timer_dest.x + f32(i)*timer_dest.width,
            y = timer_dest.y,
            width = timer_dest.width,
            height = timer_dest.height
        }

        index: i32
        if u32(char) == u32(':') {
            index = 10
        } else {
            index = i32(char) - i32('0')
        }

        render_number(timer_atlas, Num(index), dest, color)
    }
}

render_number :: proc(texture: rl.Texture2D, num: Num, dest: rl.Rectangle, color: rl.Color) {
    src_result: rl.Rectangle = {
        x = f32(num)*TIMER_CELL_WIDTH,
        y = 0,
        width = TIMER_CELL_WIDTH,
        height = TIMER_ATLAS_HEIGHT
    }

    rl.DrawTexturePro(texture, src_result, dest, {0, 0}, 0, color)
}

print_help :: proc() {
	fmt.println("Usage: stoyon [OPTIONAL_FLAGS..]")
	fmt.println("\"-h || --help\": Prints this message")
	fmt.println("\"-cover [LINKS..]\": Downloads a list of covers to the used directory by stoyon")
	fmt.println("\"-music [LINKS..]\": Downloads a list of music to the used directory by stoyon")
}
