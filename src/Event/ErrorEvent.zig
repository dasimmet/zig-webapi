//! ErrorEvent Web API interface providing information about runtime or script errors.
//! Used by `"error"` listeners on `Window`, `Worker`, and `SharedWorker` (inherits from Event).
//! https://developer.mozilla.org/en-US/docs/Web/API/ErrorEvent

// 1. Imports
const std = @import("std");
const webapi = @import("../webapi.zig");
const Event = @import("../Event.zig");

// 2. Shortcuts on imports
const ErrorEvent = @This();
const zjb = webapi.zjb;

// 3. File-level struct members
handle: zjb.Handle,
pub const @"null": ErrorEvent = .{ .handle = .null };

// 7. Public functions
/// Wraps a non-null JS ErrorEvent handle.
pub fn fromHandle(handle: zjb.Handle) ErrorEvent {
    std.debug.assert(!handle.isNull());
    std.debug.assert(@backingInt(handle) != 0);
    return .{ .handle = handle };
}

/// Views a base Event handle as an ErrorEvent.
pub fn fromEvent(ev: Event) ErrorEvent {
    std.debug.assert(!ev.isNull());
    std.debug.assert(@backingInt(ev.handle) != 0);
    return fromHandle(ev.handle);
}

/// Returns a base Event view over this ErrorEvent.
pub fn asEvent(self: ErrorEvent) Event {
    return Event.fromHandle(self.handle);
}

/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: ErrorEvent) bool {
    return self.handle.isNull();
}

/// Releases the underlying JS handle when owned.
pub fn release(self: ErrorEvent) void {
    self.handle.release();
}

/// Cancels default browser action if the event is cancelable.
/// https://developer.mozilla.org/en-US/docs/Web/API/Event/preventDefault
pub fn preventDefault(self: ErrorEvent) void {
    self.asEvent().preventDefault();
}

/// Prevents further propagation of the ErrorEvent.
/// https://developer.mozilla.org/en-US/docs/Web/API/Event/stopPropagation
pub fn stopPropagation(self: ErrorEvent) void {
    self.asEvent().stopPropagation();
}

/// Copies the human-readable error message into `buf`.
/// https://developer.mozilla.org/en-US/docs/Web/API/ErrorEvent/message
pub fn message(self: ErrorEvent, buf: []u8) []const u8 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(buf.len > 0);
    const msg_h = self.handle.get("message", zjb.Handle);
    defer msg_h.release();
    return webapi.stringFromHandle(msg_h, buf);
}

/// Copies the URL of the script in which the error occurred into `buf`.
/// https://developer.mozilla.org/en-US/docs/Web/API/ErrorEvent/filename
pub fn filename(self: ErrorEvent, buf: []u8) []const u8 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(buf.len > 0);
    const file_h = self.handle.get("filename", zjb.Handle);
    defer file_h.release();
    return webapi.stringFromHandle(file_h, buf);
}

/// Returns the line number of the script file on which the error occurred.
/// https://developer.mozilla.org/en-US/docs/Web/API/ErrorEvent/lineno
pub fn lineno(self: ErrorEvent) u32 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const raw = self.handle.get("lineno", i32);
    return if (raw > 0) @intCast(raw) else 0;
}

/// Returns the column number of the line on which the error occurred.
/// https://developer.mozilla.org/en-US/docs/Web/API/ErrorEvent/colno
pub fn colno(self: ErrorEvent) u32 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const raw = self.handle.get("colno", i32);
    return if (raw > 0) @intCast(raw) else 0;
}

/// Returns an owned JS handle to `event.error` (may be null).
/// https://developer.mozilla.org/en-US/docs/Web/API/ErrorEvent/error
pub fn errorValue(self: ErrorEvent) zjb.Handle {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return self.handle.get("error", zjb.Handle);
}
