const xkb = @cImport({
    @cInclude("xkbcommon/xkbcommon.h"); // -lxkbcommon
});

const wc = @cImport({
    @cInclude("wayland-client.h"); // -lwayland-client
});

const mman = @cImport({
    @cInclude("sys/mman.h"); // -lc
});

const unistd = @cImport({
    @cInclude("unistd.h"); // -lc
});

const std = @import("std");
const mem = std.mem;

const Client_state = struct { wl_display: *wc.wl_display, wl_registry: *wc.wl_registry, wl_shm: *wc.wl_shm, wl_seat: *wc.wl_seat, wl_keyboard: *wc.wl_keyboard, xkb_state: *xkb.xkb_state, xkb_context: *xkb.xkb_context, xkb_keymap: *xkb.xkb_keymap };

const wl_keyboard_listener: wc.wl_keyboard_listener = .{ .keymap = wl_keyboard_keymap, .enter = wl_keyboard_enter, .leave = wl_keyboard_leave, .key = wl_keyboard_key, .modifiers = wl_keymap_modifiers, .repeat_info = wl_keyboard_repeat_info };
const wl_seat_listener: wc.wl_seat_listener = .{ .capabilities = wl_seat_capabilities, .name = wl_seat_name };
const wl_registry_listener: wc.wl_registry_listener = .{ .global = registry_global, .global_remove = registry_global_remove };

pub var global_keymap: *xkb.xkb_keymap = undefined;
pub var global_state: *xkb.xkb_state = undefined;
var keymap_found = false;

pub fn scan() !void {
    // Initialize wayland state
    var state: Client_state = .{ .wl_display = undefined, .wl_registry = undefined, .wl_shm = undefined, .wl_seat = undefined, .wl_keyboard = undefined, .xkb_state = undefined, .xkb_context = undefined, .xkb_keymap = undefined };
    if (xkb.xkb_context_new(xkb.XKB_CONTEXT_NO_FLAGS)) |xkb_ctx_ptr| {
        state.xkb_context = xkb_ctx_ptr;
    }

    // Establish the connection to the wayland server
    if (wc.wl_display_connect(null)) |display_ptr| {
        state.wl_display = display_ptr;
    }

    // End the connection with the wayland server
    defer wc.wl_display_disconnect(state.wl_display);

    // Get registry pointer
    if (wc.wl_display_get_registry(state.wl_display)) |registry_ptr| {
        state.wl_registry = registry_ptr;
    }

    _ = wc.wl_registry_add_listener(state.wl_registry, &wl_registry_listener, &state);

    var x: u32 = 50000;
    while (!keymap_found and x > 0) {
        _ = wc.wl_display_roundtrip(state.wl_display);
        x -= 1;
    }
}

fn registry_global(my_state: ?*anyopaque, wl_registry: ?*wc.wl_registry, name: u32, interface: [*c]const u8, version: u32) callconv(.C) void {
    _ = version;

    var state: *Client_state = undefined;
    if (my_state) |state_ptr| {
        state = @ptrCast(@alignCast(state_ptr));
    }

    if (mem.eql(u8, mem.span(interface), mem.span(wc.wl_seat_interface.name))) {
        if (wc.wl_registry_bind(wl_registry, name, &wc.wl_seat_interface, 7)) |seat_ptr| {
            state.wl_seat = @ptrCast(@alignCast(seat_ptr));
        }
        _ = wc.wl_seat_add_listener(state.wl_seat, &wl_seat_listener, state);
    }
}

fn registry_global_remove(state: ?*anyopaque, wl_registry: ?*wc.wl_registry, name: u32) callconv(.C) void {
    _ = name;
    _ = wl_registry;
    _ = state;
}

fn wl_seat_capabilities(my_state: ?*anyopaque, wl_seat: ?*wc.wl_seat, capabilities: u32) callconv(.C) void {
    _ = wl_seat;

    var state: *Client_state = undefined;
    if (my_state) |state_ptr| {
        state = @ptrCast(@alignCast(state_ptr));
    }

    const have_keyboard: bool = (capabilities > 0) and (wc.WL_SEAT_CAPABILITY_KEYBOARD > 0);
    if (have_keyboard) {
        if (wc.wl_seat_get_keyboard(state.wl_seat)) |keyboard_ptr| {
            state.wl_keyboard = keyboard_ptr;
        }

        _ = wc.wl_keyboard_add_listener(state.wl_keyboard, &wl_keyboard_listener, state);
    } else if (!have_keyboard) {
        wc.wl_keyboard_release(state.wl_keyboard);
        state.wl_keyboard = undefined;
    }
}

fn wl_seat_name(state: ?*anyopaque, wl_seat: ?*wc.wl_seat, name: [*c]const u8) callconv(.C) void {
    _ = name;
    _ = wl_seat;
    _ = state;
}

fn wl_keyboard_keymap(my_state: ?*anyopaque, wl_keyboard: ?*wc.wl_keyboard, format: u32, fd: i32, size: u32) callconv(.C) void {
    std.debug.assert(format == wc.WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1);
    _ = wl_keyboard;

    var state: *Client_state = undefined;
    if (my_state) |state_ptr| {
        state = @ptrCast(@alignCast(state_ptr));
    }

    // Retrieve the keymap pointer with mmap
    var keymap_str: [*]const u8 = undefined;
    if (mman.mmap(null, size, mman.PROT_READ, mman.MAP_SHARED, fd, 0)) |map_shm| {
        keymap_str = @ptrCast(@alignCast(map_shm));
    }
    // Unmap the map
    defer _ = mman.munmap(@constCast(keymap_str), size);

    // Get the keymap from xkb using keymap_ptr
    var keymap: *xkb.xkb_keymap = undefined;
    if (xkb.xkb_keymap_new_from_string(state.xkb_context, keymap_str, xkb.XKB_KEYMAP_FORMAT_TEXT_V1, xkb.XKB_KEYMAP_COMPILE_NO_FLAGS)) |keymap_ptr| {
        keymap = keymap_ptr;
    }

    var xkb_state: *xkb.xkb_state = undefined;
    if (xkb.xkb_state_new(keymap)) |state_ptr| {
        xkb_state = state_ptr;
    }
    xkb.xkb_keymap_unref(state.xkb_keymap);
    xkb.xkb_state_unref(state.xkb_state);

    state.xkb_keymap = keymap;
    global_keymap = keymap;
    state.xkb_state = xkb_state;
    global_state = xkb_state;

    // Close the file descriptor
    _ = unistd.close(fd);
}

fn wl_keymap_modifiers(my_state: ?*anyopaque, wl_keyboard: ?*wc.wl_keyboard, serial: u32, depressed: u32, latched: u32, locked: u32, group: u32) callconv(.C) void {
    _ = serial;
    _ = wl_keyboard;

    var state: *Client_state = undefined;
    if (my_state) |state_ptr| {
        state = @ptrCast(@alignCast(state_ptr));
    }

    _ = xkb.xkb_state_update_mask(state.xkb_state, depressed, latched, locked, 0, 0, group);
}

fn wl_keyboard_enter(my_state: ?*anyopaque, wl_keyboard: ?*wc.wl_keyboard, serial: u32, wl_surface: ?*wc.wl_surface, keys: ?*wc.wl_array) callconv(.C) void {
    _ = my_state;
    _ = keys;
    _ = wl_surface;
    _ = serial;
    _ = wl_keyboard;
}

fn wl_keyboard_leave(my_state: ?*anyopaque, wl_keyboard: ?*wc.wl_keyboard, serial: u32, wl_surface: ?*wc.wl_surface) callconv(.C) void {
    _ = my_state;
    _ = wl_surface;
    _ = serial;
    _ = wl_keyboard;
}

fn wl_keyboard_repeat_info(my_state: ?*anyopaque, wl_keyboard: ?*wc.wl_keyboard, rate: i32, delay: i32) callconv(.C) void {
    _ = my_state;
    _ = delay;
    _ = rate;
    _ = wl_keyboard;
}

fn wl_keyboard_key(my_state: ?*anyopaque, wl_keyboard: ?*wc.wl_keyboard, serial: u32, time: u32, key: u32, key_state: u32) callconv(.C) void {
    _ = my_state;
    _ = key_state;
    _ = key;
    _ = time;
    _ = serial;
    _ = wl_keyboard;
}
