package stoyon
import "core:fmt"
import "core:strings"
import "core:strconv"
import "core:os"

is_numiric :: proc(str: string) -> bool {
	_, ok := strconv.parse_f32(str)
	return ok
}

convert :: proc(val: string) -> Types {
	if val == "true" || val == "false" {
		result, _ := strconv.parse_bool(val)
		return result
	}

	if is_numiric(val) {
		result, _ := strconv.parse_f32(val)
		return result
	}
	return val
}

is_line_skippable :: proc(line: string) -> bool {
	return len(line) == 0 || line[0] == '#'
}

trim_until_delim :: proc(line: string, delim: rune) -> (string, string) {
	pos: i32 = 0
	for line[pos] != u8(delim) do pos += 1
	if int(pos) < len(line) {
		return strings.trim_space(line[:pos]), strings.trim_space(line[pos+1:])
	}
	return line, line
}

parse_config_file :: proc(file_data: []u8) -> map[string]Types {
	data := string(file_data)
	lines := strings.split(data, "\n")
	file_map: map[string]Types

	for line, i in lines {
		if is_line_skippable(line) do continue
		var, val := trim_until_delim(line, '=')
		if val != line || var != line do file_map[var] = convert(val)
	}

	return file_map
}
