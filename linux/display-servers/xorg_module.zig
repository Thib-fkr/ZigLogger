const x11 = @cImport({
    @cInclude("xkbcommon/xkbcommon-x11.h"); // -lxkbcommon -lxcb -lxkbcommon-x11
});

const std = @import("std");

pub var global_keymap: *x11.xkb_keymap = undefined;
pub var global_state: *x11.xkb_state = undefined;

pub fn scan() !void {
    var xkb_context: *x11.xkb_context = undefined;
    if (x11.xkb_context_new(x11.XKB_CONTEXT_NO_FLAGS)) |xkb_ctx_ptr| {
        xkb_context = xkb_ctx_ptr;
    } else {
        std.debug.print("(xorg_module - scan) Error while creating context", .{});
        return;
    }

    var conn: *x11.xcb_connection_t = undefined;
    if (x11.xcb_connect(null, null)) |conn_ptr| {
        conn = conn_ptr;
    } else {
        std.debug.print("(xorg_module - scan) Error while connecting to display", .{});
        return;
    }

    var id: i32 = x11.xkb_x11_get_core_keyboard_device_id(conn);
    if (id == -1) {
        std.debug.print("(xorg_module - scan) Error while retrieving device id", .{});
        return;
    }

    if (x11.xkb_x11_keymap_new_from_device(xkb_context, conn, id, x11.XKB_CONTEXT_NO_FLAGS)) |keymap_ptr| {
        global_keymap = keymap_ptr;
    } else {
        std.debug.print("(xorg_module - scan) Error while retrieving keymap", .{});
        return;
    }

    if (x11.xkb_x11_state_new_from_device(global_keymap, conn, id)) |state_ptr| {
        global_state = state_ptr;
    } else {
        std.debug.print("(xorg_module - scan) Error while retrieving state", .{});
        return;
    }
}
