//! MessageEvent Web API interface representing a message received by a target object.
//! Used by `"message"` and `"messageerror"` listeners on `WebSocket`, `BroadcastChannel`,
//! and `RTCDataChannel` (inherits from Event).
//! https://developer.mozilla.org/en-US/docs/Web/API/MessageEvent

// 1. Imports
const std = @import("std");
const webapi = @import("../webapi.zig");
const Event = @import("../Event.zig");

// 2. Shortcuts on imports
const MessageEvent = @This();
const zjb = webapi.zjb;

// 3. File-level struct members
handle: zjb.Handle,

// 7. Public functions
/// Wraps a non-null JS MessageEvent handle.
pub fn fromHandle(handle: zjb.Handle) MessageEvent {
    std.debug.assert(!handle.isNull());
    std.debug.assert(@backingInt(handle) != 0);
    return .{ .handle = handle };
}

/// Views a base Event handle as a MessageEvent.
pub fn fromEvent(ev: Event) MessageEvent {
    std.debug.assert(!ev.isNull());
    std.debug.assert(@backingInt(ev.handle) != 0);
    return .{ .handle = ev.handle };
}

/// Returns a base Event view over this MessageEvent.
pub fn asEvent(self: MessageEvent) Event {
    return Event.fromHandle(self.handle);
}

/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: MessageEvent) bool {
    return self.handle.isNull();
}

/// Releases the underlying JS handle when owned.
pub fn release(self: MessageEvent) void {
    self.handle.release();
}

/// Cancels default browser action if the event is cancelable.
/// https://developer.mozilla.org/en-US/docs/Web/API/Event/preventDefault
pub fn preventDefault(self: MessageEvent) void {
    self.asEvent().preventDefault();
}

/// Prevents further propagation of the MessageEvent.
/// https://developer.mozilla.org/en-US/docs/Web/API/Event/stopPropagation
pub fn stopPropagation(self: MessageEvent) void {
    self.asEvent().stopPropagation();
}

/// Returns an owned JS handle to the data sent by the message emitter.
/// https://developer.mozilla.org/en-US/docs/Web/API/MessageEvent/data
pub fn data(self: MessageEvent) zjb.Handle {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return self.handle.get("data", zjb.Handle);
}

/// Copies the origin of the message emitter into `buf`.
/// https://developer.mozilla.org/en-US/docs/Web/API/MessageEvent/origin
pub fn origin(self: MessageEvent, buf: []u8) []const u8 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(buf.len > 0);
    const origin_h = self.handle.get("origin", zjb.Handle);
    defer origin_h.release();
    return webapi.stringFromHandle(origin_h, buf);
}

/// Copies the unique ID for the event into `buf`.
/// https://developer.mozilla.org/en-US/docs/Web/API/MessageEvent/lastEventId
pub fn lastEventId(self: MessageEvent, buf: []u8) []const u8 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(buf.len > 0);
    const id_h = self.handle.get("lastEventId", zjb.Handle);
    defer id_h.release();
    return webapi.stringFromHandle(id_h, buf);
}

/// Returns an owned JS handle to the `MessageEventSource` that sent the message.
/// https://developer.mozilla.org/en-US/docs/Web/API/MessageEvent/source
pub fn source(self: MessageEvent) zjb.Handle {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return self.handle.get("source", zjb.Handle);
}

/// Returns an owned JS handle to the array of transferred `MessagePort` objects.
/// https://developer.mozilla.org/en-US/docs/Web/API/MessageEvent/ports
pub fn ports(self: MessageEvent) zjb.Handle {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return self.handle.get("ports", zjb.Handle);
}

/// Returns the `MessagePort` at `idx` in `event.ports`, or null if out of bounds.
/// https://developer.mozilla.org/en-US/docs/Web/API/MessageEvent/ports
pub fn portAt(self: MessageEvent, idx: usize) ?webapi.Worker.MessagePort {
    std.debug.assert(!self.handle.isNull());
    const ports_h = self.ports();
    if (ports_h.isNull()) return null;
    defer ports_h.release();

    const raw_len = ports_h.get("length", i32);
    if (raw_len <= 0 or idx >= @as(usize, @intCast(raw_len))) return null;

    const port_h = ports_h.indexGet(@as(i32, @intCast(idx)), zjb.Handle);
    if (port_h.isNull()) {
        port_h.release();
        return null;
    }
    return .{ .handle = port_h };
}
