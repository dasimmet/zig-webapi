//! Type-safe wrapper for a browser `WebSocket`.
//! https://developer.mozilla.org/en-US/docs/Web/API/WebSocket
//!
const std = @import("std");
const webapi = @import("webapi.zig");
const zjb = webapi.zjb;
const WebSocket = @This();

handle: zjb.Handle,

pub const @"null": WebSocket = .{ .handle = .null };

pub const ReadyState = enum(i32) {
    CONNECTING = 0,
    OPEN = 1,
    CLOSING = 2,
    CLOSED = 3,
    _,
};

pub fn init(url: []const u8) WebSocket {
    const url_s = zjb.string(url);
    defer url_s.release();
    return fromHandle(zjb.global("WebSocket").new(.{url_s}));
}

/// Wraps a non-null JS WebSocket handle.
pub fn fromHandle(handle: zjb.Handle) WebSocket {
    std.debug.assert(!handle.isNull());
    std.debug.assert(@backingInt(handle) != 0);
    return .{ .handle = handle };
}

/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: WebSocket) bool {
    return self.handle.isNull();
}

/// Releases the underlying JS handle.
pub fn release(self: WebSocket) void {
    self.handle.release();
}

pub fn send(self: WebSocket, data: []const u8) void {
    const view = zjb.u8ArrayView(data);
    defer view.release();
    self.handle.call("send", .{view}, void);
}

pub fn close(self: WebSocket) void {
    self.handle.call("close", .{}, void);
}

pub fn readyState(self: WebSocket) ReadyState {
    return @fromBackingInt(self.handle.get("readyState", i32));
}

pub fn isOpen(self: WebSocket) bool {
    return !self.isNull() and self.readyState() == .OPEN;
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
