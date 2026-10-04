package stoyon
import "core:fmt"
import rl "vendor:raylib"
import "core:os"
import "core:time"
import "core:math"
import "core:math/rand"

BACKGROUND_COLOR	:: 0x181818FF
TEXT_COLOR			:: 0xE4E4E4FF
DEFAULT_FONT_SIZE   :: 50

Types :: union {
	f32,
	string,
	bool
}

get_next_icon_bounds :: proc(xx, yy, s: f32) -> rl.Rectangle {
	return rl.Rectangle {
		x = xx,
		y = yy,
		width = s,
		height = s
	}
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

    rl.DrawRectangleRec(tooltip_rec, rl.BLACK)
    rl.DrawRectangleLinesEx(tooltip_rec, 3, rl.PURPLE) // outline for the tooltip box
    rl.DrawTextEx(font, message, margined_pos, 20, 2, rl.GetColor(TEXT_COLOR))
}

main :: proc() {
	input_file := "config.mini"
	file_data, open_err := os.read_entire_file(input_file, context.temp_allocator)
	if open_err != nil {
		fmt.eprintf("Error: File \"%v\" not found!\n", input_file)
		os.exit(1)
	}

	file_map := parse_config_file(file_data)
	s_width, s_height := i32(file_map["width"].(f32)), i32(file_map["height"].(f32))
    rl.InitWindow(s_width, s_height, "Stowon")
    rl.SetWindowState({.WINDOW_RESIZABLE, .MSAA_4X_HINT, .WINDOW_HIGHDPI})
    defer rl.CloseWindow()
	rl.InitAudioDevice()

    camera: rl.Camera2D
	camera.rotation = 0
	camera.zoom = 1 // Default value

	fps := i32(file_map["fps"].(f32))
	rl.SetTargetFPS(fps)

	//seed := time.time_to_unix(time.now())
	//rand.reset(u64(seed))

    font_path: cstring = "./fonts/JetBrainsMonoNLNerdFont-Regular.ttf"
	font := rl.LoadFontEx(font_path, DEFAULT_FONT_SIZE, nil, 0)
	defer rl.UnloadFont(font)
	assert(rl.IsFontValid(font), "Error: Font is not valid\n")
	rl.SetTextureFilter(font.texture, .BILINEAR)

	music_image := rl.LoadTexture("./res/music_icon_1.png")
	defer rl.UnloadTexture(music_image)

	music_image_src: rl.Rectangle = {
		x		= 0,
		y		= 0,
		width	= f32(music_image.width),
		height	= f32(music_image.height)
	}
	
	time_text_size: f32 = 18
	time_text_spacing: f32 = 5
	battery_percentage: f32 = 0.5 // Between 0..1

	test_music := rl.LoadMusicStream("./res/echoes_of_lumen-pixel-art-game.mp3")
	defer rl.UnloadMusicStream(test_music)
	
    zoom_in_out: f32 = 0.25

    for !rl.WindowShouldClose() {
		rl.UpdateMusicStream(test_music)
		rl.SetMusicVolume(test_music, 0.1)
		if rl.IsKeyPressed(.SPACE) && !rl.IsMusicStreamPlaying(test_music) do rl.PlayMusicStream(test_music)

		width := f32(rl.GetScreenWidth())
		height := f32(rl.GetScreenHeight())
        mouse := rl.GetMousePosition()
		dt := rl.GetFrameTime()
		margin: f32 = 20

        camera.offset = {width/2, height/2}
        camera.target = {width/2, height/2}

        if rl.IsKeyDown(.LEFT_CONTROL) && rl.IsKeyPressed(.EQUAL) {
            camera.zoom += zoom_in_out
        } else if rl.IsKeyDown(.LEFT_CONTROL) && rl.IsKeyPressed(.SIX) { // for french keyboard (I use it)
            camera.zoom -= zoom_in_out
        }

        hours, mins, _ := time.clock_from_time(time.now())
		time_text := fmt.ctprintf("%02v:%02v", hours + 1, mins)
		time_dimensions := rl.MeasureTextEx(font, time_text, time_text_size, time_text_spacing)
		
		music_image_size := width*0.25
		music_image_dest: rl.Rectangle = {
			x = 100,
			y = 100,
			width  = music_image_size,
			height = music_image_size
		}
		
        rl.BeginDrawing()
        rl.BeginMode2D(camera)
        rl.ClearBackground(rl.GetColor(BACKGROUND_COLOR))
		
		time_pos: rl.Vector2 = {
			width - time_dimensions.x - margin,
			margin
		}

        rl.DrawTexturePro(music_image, music_image_src, music_image_dest, {0, 0}, 0, rl.WHITE)
        rl.DrawTextEx(font, time_text, time_pos, time_text_size, time_text_spacing, rl.WHITE)

		music_title := fmt.ctprintf("|%v|", rl.GetFileNameWithoutExt("./res/echoes_of_lumen-pixel-art-game.mp3"))
        title_size := rl.MeasureTextEx(font, music_title, music_image_dest.width*0.05, time_text_spacing)

		rl.DrawTextEx(font, music_title,
					  {music_image_dest.x + (music_image_dest.width - title_size.x)*0.5,
					   music_image_dest.y + music_image_dest.height + margin*2},
					   music_image_dest.width*0.05, time_text_spacing, rl.GetColor(TEXT_COLOR))

		music_time_line_thickness: f32 = 5
		music_time_percentage: f32 = rl.GetMusicTimePlayed(test_music) / rl.GetMusicTimeLength(test_music)
		music_time_line_bounds: rl.Rectangle = {
			x = music_image_dest.x,
			y = music_image_dest.y + music_image_dest.height + margin*0.5,
			width = math.clamp(0, margin*0.5 + music_time_percentage*music_image_dest.width, music_image_dest.width),
			height = music_time_line_thickness
		}
		
		rl.DrawRectangleRec(music_time_line_bounds, rl.WHITE)

        // tooltips must be last thing to render
        if rl.CheckCollisionPointRec(mouse, music_image_dest) {
            show_tooltip(font, "<left>&<right> to move between tracks", mouse)
        }

        rl.EndMode2D()
		rl.EndDrawing()
        free_all(context.temp_allocator)
    }
}

