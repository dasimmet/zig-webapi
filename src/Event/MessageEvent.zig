//! MessageEvent Web API interface representing a message received by a target object.
//! Used by `"message"` and `"messageerror"` listeners on `WebSocket`, `BroadcastChannel`,
//! `Worker`, and `RTCDataChannel` (inherits from Event).
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
pub const @"null": MessageEvent = .{ .handle = .null };

// 6. Types
/// Payload runtime kind reported for `MessageEvent.data`.
pub const DataKind = enum {
    text,
    array_buffer,
    blob,
    unknown,
};

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
    return fromHandle(ev.handle);
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

/// Inspects the runtime JavaScript type of `event.data` via `Object.prototype.toString`.
pub fn dataKind(self: MessageEvent) DataKind {
    const data_h = self.data();
    if (data_h.isNull()) return .unknown;
    defer data_h.release();

    const obj_proto = zjb.global("Object").get("prototype", zjb.Handle);
    defer obj_proto.release();
    const to_str = obj_proto.get("toString", zjb.Handle);
    defer to_str.release();
    const tag_h = to_str.call("call", .{data_h}, zjb.Handle);
    defer tag_h.release();

    var tag_buf: [32]u8 = undefined;
    const tag = webapi.stringFromHandle(tag_h, &tag_buf);
    if (std.mem.eql(u8, tag, "[object String]")) return .text;
    if (std.mem.eql(u8, tag, "[object ArrayBuffer]")) return .array_buffer;
    if (std.mem.eql(u8, tag, "[object Blob]") or std.mem.eql(u8, tag, "[object File]")) return .blob;
    return .unknown;
}

/// Copies a string `event.data` payload into `buf`.
/// https://developer.mozilla.org/en-US/docs/Web/API/MessageEvent/data
pub fn dataText(self: MessageEvent, buf: []u8) []u8 {
    std.debug.assert(buf.len > 0);
    const data_h = self.data();
    if (data_h.isNull()) return "";
    defer data_h.release();
    return webapi.stringFromHandle(data_h, buf);
}

/// Alias for `dataText`.
pub const dataString = dataText;

/// Encodes a string `event.data` payload into a newly allocated UTF-8 slice.
/// https://developer.mozilla.org/en-US/docs/Web/API/MessageEvent/data
pub fn dataTextAlloc(self: MessageEvent, allocator: std.mem.Allocator) ![]u8 {
    const data_h = self.data();
    if (data_h.isNull()) return "";
    defer data_h.release();
    return try webapi.stringFromHandleAlloc(allocator, data_h);
}

/// Alias for `dataTextAlloc`.
pub const dataStringAlloc = dataTextAlloc;

/// Copies a binary `ArrayBuffer`/`Uint8Array` `event.data` payload into `buf`,
/// returning the number of bytes copied.
pub fn dataBytes(self: MessageEvent, buf: []u8) !usize {
    const d = self.data();
    if (d.isNull()) return 0;
    defer d.release();
    const raw_len = d.get("byteLength", i32);
    if (raw_len <= 0) return 0;
    const copy_len = @min(buf.len, @as(usize, @intCast(raw_len)));
    try webapi.bytesFromHandle(buf[0..copy_len], d);
    return copy_len;
}

/// Copies binary `ArrayBuffer`/`Uint8Array` `event.data` bytes into an allocated slice.
pub fn dataBytesAlloc(self: MessageEvent, allocator: std.mem.Allocator) ![]u8 {
    const data_h = self.data();
    if (data_h.isNull()) return try allocator.alloc(u8, 0);
    defer data_h.release();
    return try webapi.bytesFromHandleAlloc(allocator, data_h);
}

/// Wraps `event.data` as a `webapi.Blob` (or `.null` if null/undefined).
pub fn dataBlob(self: MessageEvent) webapi.Blob {
    const data_h = self.data();
    if (data_h.isNull()) return .null;
    return webapi.Blob.fromHandle(data_h);
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
    return webapi.Worker.MessagePort.fromHandle(port_h);
}
