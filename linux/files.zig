const std = @import("std");
const fs = std.fs;
const mem = std.mem;

// Create a file with the passed name in the current working directory
// Return the name of the created file
pub fn create_file(file_name: []const u8) ![]const u8 {
    const output_file = try fs.cwd().createFile(file_name, fs.File.CreateFlags{});
    output_file.close();

    return file_name;
}

// Find and return the suffix of the event file that contains keyboard events
pub fn get_event_path(allocator: *mem.Allocator) ![]const u8 {
    // Usefull source for detecting which event file is used on the device
    // https://stackoverflow.com/questions/29678011/determine-linux-keyboard-events-device
    const source_file = try fs.openFileAbsolute("/proc/bus/input/devices", fs.File.OpenFlags{});
    var source_reader = source_file.reader();
    defer source_file.close();

    var event_lines = std.ArrayList(u8).init(allocator.*);
    const line_writer = event_lines.writer();
    defer event_lines.deinit();

    var suffix: *[]const u8 = try allocator.create([]const u8);
    defer allocator.destroy(suffix);

    // var ev_number: *[]const u8 = try allocator.create([]const u8);
    // defer allocator.destroy(ev_number);

    // Idea here is that we iterate through the file /proc/bus/input/devices
    // and return the suffix of the handler which is related to the id 120013

    var n: u8 = 0;
    while (n < 25) {
        source_reader.streamUntilDelimiter(line_writer, '\n', undefined) catch break;
        const line = try event_lines.toOwnedSlice();
        defer allocator.free(line);

        if (mem.startsWith(u8, line, "H: Handlers=")) {
            suffix.* = try allocator.dupe(u8, line[12..]);
            continue;
        }

        if (mem.startsWith(u8, line, "B: EV=")) {
            // ev_number.* = line[6..];

            // 120013 is the event number for keyboard inputs
            if (mem.eql(u8, line[6..], "120013")) {
                return try get_handler_suffix(suffix.*);
            }

            continue;
        }
    }

    unreachable;
}

// Single out the eventN word in the passed handler line and return it
fn get_handler_suffix(handler: []const u8) ![]const u8 {
    var iterator = mem.tokenizeSequence(u8, handler, " ");

    while (iterator.next()) |word| {
        if (mem.startsWith(u8, word, "event")) {
            return word;
        }
    }

    unreachable;
}
