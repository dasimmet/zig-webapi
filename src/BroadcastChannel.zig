//! Type-safe wrapper for a browser `BroadcastChannel`.
//! https://developer.mozilla.org/en-US/docs/Web/API/BroadcastChannel
const std = @import("std");
const webapi = @import("webapi.zig");
const zjb = webapi.zjb;

const BroadcastChannel = @This();

handle: zjb.Handle,

pub const @"null": BroadcastChannel = .{ .handle = .null };

pub fn isSupported() bool {
    const window = zjb.global("window");
    const bc_class = window.get("BroadcastChannel", zjb.Handle);
    defer bc_class.release();
    return !bc_class.isNull();
}

pub fn init(name: []const u8) BroadcastChannel {
    const name_s = zjb.string(name);
    defer name_s.release();
    return fromHandle(zjb.global("BroadcastChannel").new(.{name_s}));
}

/// Wraps a non-null JS BroadcastChannel handle.
pub fn fromHandle(handle: zjb.Handle) BroadcastChannel {
    std.debug.assert(!handle.isNull());
    std.debug.assert(@backingInt(handle) != 0);
    return .{ .handle = handle };
}

/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: BroadcastChannel) bool {
    return self.handle.isNull();
}

/// Releases the underlying JS handle.
pub fn release(self: BroadcastChannel) void {
    self.handle.release();
}

pub fn postMessage(self: BroadcastChannel, message: []const u8) void {
    const view = zjb.u8ArrayView(message);
    defer view.release();
    self.handle.call("postMessage", .{view}, void);
}

pub fn close(self: BroadcastChannel) void {
    self.handle.call("close", .{}, void);
}

/// Attaches a context-bound listener receiving `webapi.Event.EventFor(event)`.
pub fn addEventListener(
    self: @This(),
    comptime event: []const u8,
    comptime T: type,
    ctx: *T,
    comptime f: *const fn (*T, webapi.Event.EventFor(event)) void,
) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(event.len > 0);
    webapi.boundEventListenerTyped(
        T,
        webapi.Event.EventFor(event),
        event,
        self.handle,
        f,
        ctx,
    );
}

/// Attaches an owned-handle typed listener receiving `webapi.Event.EventFor(event)`.
pub fn addEventListenerOwned(
    self: @This(),
    comptime event: []const u8,
    comptime T: type,
    ctx: *T,
    comptime f: *const fn (*T, webapi.Event.EventFor(event)) void,
) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(event.len > 0);
    webapi.boundEventListenerTypedOwned(
        T,
        webapi.Event.EventFor(event),
        event,
        self.handle,
        f,
        ctx,
    );
}
