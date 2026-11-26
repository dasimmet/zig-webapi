//! CloseEvent Web API interface sent to clients using WebSockets when the connection is closed.
//! Used by `"close"` listeners (inherits from Event).
//! https://developer.mozilla.org/en-US/docs/Web/API/CloseEvent

// 1. Imports
const std = @import("std");
const webapi = @import("../webapi.zig");
const Event = @import("../Event.zig");

// 2. Shortcuts on imports
const CloseEvent = @This();
const zjb = webapi.zjb;

// 3. File-level struct members
handle: zjb.Handle,
pub const @"null": CloseEvent = .{ .handle = .null };

// 7. Public functions
/// Wraps a non-null JS CloseEvent handle.
pub fn fromHandle(handle: zjb.Handle) CloseEvent {
    std.debug.assert(!handle.isNull());
    std.debug.assert(@backingInt(handle) != 0);
    return .{ .handle = handle };
}

/// Views a base Event handle as a CloseEvent.
pub fn fromEvent(ev: Event) CloseEvent {
    std.debug.assert(!ev.isNull());
    std.debug.assert(@backingInt(ev.handle) != 0);
    return fromHandle(ev.handle);
}

/// Returns a base Event view over this CloseEvent.
pub fn asEvent(self: CloseEvent) Event {
    return Event.fromHandle(self.handle);
}

/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: CloseEvent) bool {
    return self.handle.isNull();
}

/// Releases the underlying JS handle when owned.
pub fn release(self: CloseEvent) void {
    self.handle.release();
}

/// Cancels default browser action if the event is cancelable.
/// https://developer.mozilla.org/en-US/docs/Web/API/Event/preventDefault
pub fn preventDefault(self: CloseEvent) void {
    self.asEvent().preventDefault();
}

/// Prevents further propagation of the CloseEvent.
/// https://developer.mozilla.org/en-US/docs/Web/API/Event/stopPropagation
pub fn stopPropagation(self: CloseEvent) void {
    self.asEvent().stopPropagation();
}

/// Returns the WebSocket connection close code provided by the server.
/// https://developer.mozilla.org/en-US/docs/Web/API/CloseEvent/code
pub fn code(self: CloseEvent) i32 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return self.handle.get("code", i32);
}

/// Returns `CloseEvent.code` as a typed `WebSocket.CloseCode` enum.
/// https://developer.mozilla.org/en-US/docs/Web/API/CloseEvent/code
pub fn closeCode(self: CloseEvent) webapi.WebSocket.CloseCode {
    const raw = self.code();
    const clamped: u16 = if (raw >= 0 and raw <= std.math.maxInt(u16))
        @intCast(raw)
    else
        0;
    return @fromBackingInt(@intCast(clamped));
}

/// Copies the string indicating the reason the server closed the connection into `buf`.
/// https://developer.mozilla.org/en-US/docs/Web/API/CloseEvent/reason
pub fn reason(self: CloseEvent, buf: []u8) []const u8 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(buf.len > 0);
    const reason_h = self.handle.get("reason", zjb.Handle);
    defer reason_h.release();
    return webapi.stringFromHandle(reason_h, buf);
}

/// Allocates and returns the UTF-8 close reason string (`CloseEvent.reason`).
/// https://developer.mozilla.org/en-US/docs/Web/API/CloseEvent/reason
pub fn reasonAlloc(
    self: CloseEvent,
    allocator: std.mem.Allocator,
) ![]u8 {
    std.debug.assert(!self.handle.isNull());
    const reason_h = self.handle.get("reason", zjb.Handle);
    defer reason_h.release();
    if (reason_h.isNull()) return "";
    return try webapi.stringFromHandleAlloc(allocator, reason_h);
}

/// Returns true if the connection closed cleanly.
/// https://developer.mozilla.org/en-US/docs/Web/API/CloseEvent/wasClean
pub fn wasClean(self: CloseEvent) bool {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return self.handle.get("wasClean", bool);
}
