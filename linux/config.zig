const std = @import("std");
const fs = std.fs;
const Allocator = std.mem.Allocator;

pub const Config = struct { keymap: []const u8, event: []const u8, output: []const u8 };
pub const ConfigError = error{ ConfigFileNotFound, KeymapLineNotFound, EventLineNotFound, OutputLineNotFound };

// Read the lines of the config file line by line until either :
//  - Every information has been found, in which case it returns normally
//  - An empty line is reached while expecting an information, in which case an error is returned
//
// Expected information are :
//  - Name of the keymap file
//  - Name of the eventN file
//  - Name of the output file
pub fn read_config(path: []const u8, allocator: *Allocator, config: *Config) !void {
    var config_file: fs.File = undefined;
    if (fs.cwd().openFile(path, fs.File.OpenFlags{})) |config_file_open| {
        config_file = config_file_open;
    } else |_| {
        return ConfigError.ConfigFileNotFound;
    }
    const config_reader = config_file.reader();
    defer config_file.close();

    var config_lines = std.ArrayList(u8).init(allocator.*);
    const config_writer = config_lines.writer();
    defer config_lines.deinit();

    // First line
    if (config_reader.streamUntilDelimiter(config_writer, '\n', undefined)) |_| {
        config.keymap = try config_lines.toOwnedSlice();
    } else |_| {
        return ConfigError.KeymapLineNotFound;
    }

    // Second line
    if (config_reader.streamUntilDelimiter(config_writer, '\n', undefined)) |_| {
        config.event = try config_lines.toOwnedSlice();
    } else |_| {
        return ConfigError.EventLineNotFound;
    }

    // Third line
    if (config_reader.streamUntilDelimiter(config_writer, '\n', undefined)) |_| {
        config.output = try config_lines.toOwnedSlice();
    } else |_| {
        return ConfigError.OutputLineNotFound;
    }
}

// Write the content of config into the file passed in path
//
// The function expect the path to exist and be writeable
pub fn update_config(path: []const u8, config: Config) !void {
    const config_output = try fs.cwd().openFile(path, fs.File.OpenFlags{ .mode = fs.File.OpenMode.write_only });
    defer config_output.close();

    const writer = config_output.writer();
    try writer.print("{s}\n{s}\n{s}\n", .{ config.keymap, config.event, config.output });
}
