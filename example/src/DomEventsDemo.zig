//! DOM input echo and global keyboard event demo, wired to update the WebGL
//! 2D canvas banner text on input changes.

// 1. Imports
const std = @import("std");
const webapi = @import("webapi");
const WebGLDemo = @import("WebGLDemo.zig");

// 2. Shortcuts on imports
const DomEventsDemo = @This();
const dom = webapi.dom;
const Event = webapi.Event;

// 3. File-level struct members
allocator: std.mem.Allocator,
webgl: ?*WebGLDemo = null,

// 7. Public functions
/// Attaches `#text-input` and `window` `keydown` listeners.
pub fn bind(self: *DomEventsDemo, webgl: *WebGLDemo) void {
    self.webgl = webgl;
    if (dom.document().getElementById("text-input")) |input| {
        defer input.release();
        input.addEventListener("input", DomEventsDemo, self, onTextInput);
    }
    dom.window().addEventListener("keydown", DomEventsDemo, self, onWindowKeydown);
}

/// Reads `#text-input`'s current value if non-empty, otherwise returns `fallback`.
pub fn readInputOrFallback(
    allocator: std.mem.Allocator,
    fallback: []const u8,
) InputValue {
    if (dom.document().getElementById("text-input")) |el| {
        defer el.release();
        if (el.getValueAlloc(allocator) catch null) |val| {
            return .{
                .text = if (val.len > 0) val else fallback,
                .owned = val,
            };
        }
    }
    return .{ .text = fallback, .owned = null };
}

// 8. Extra classes
pub const InputValue = struct {
    text: []const u8,
    owned: ?[]u8,

    pub fn deinit(self: InputValue, allocator: std.mem.Allocator) void {
        if (self.owned) |buf| allocator.free(buf);
    }
};

// 9. Private declarations
fn onTextInput(self: *DomEventsDemo, ev: Event.InputEvent) void {
    const target_h = ev.asEvent().target();
    if (target_h.isNull()) return;
    defer target_h.release();

    const target_el = dom.Element.fromHandle(target_h);
    const val = (target_el.getValueAlloc(self.allocator) catch return) orelse
        return;
    defer self.allocator.free(val);

    dom.document().setElemText(
        "echo-output",
        if (val.len > 0) val else "(empty)",
    );
    if (self.webgl) |wgl| {
        wgl.updateBannerText(val);
    }
}

fn onWindowKeydown(_: *DomEventsDemo, ev: Event.KeyboardEvent) void {
    var key_buf: [64]u8 = undefined;
    const key_name = ev.key(&key_buf);
    dom.document().setElemText("key-output", key_name);
}
