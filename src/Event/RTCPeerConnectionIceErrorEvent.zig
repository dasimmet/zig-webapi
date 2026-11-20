//! RTCPeerConnectionIceErrorEvent Web API interface providing details about an error
//! that occurred while gathering ICE candidates.
//! Used by `"icecandidateerror"` listeners (inherits from Event).
//! https://developer.mozilla.org/en-US/docs/Web/API/RTCPeerConnectionIceErrorEvent

// 1. Imports
const std = @import("std");
const webapi = @import("../webapi.zig");
const Event = @import("../Event.zig");

// 2. Shortcuts on imports
const RTCPeerConnectionIceErrorEvent = @This();
const zjb = webapi.zjb;

// 3. File-level struct members
handle: zjb.Handle,
pub const @"null": RTCPeerConnectionIceErrorEvent = .{ .handle = .null };

// 7. Public functions
/// Wraps a non-null JS RTCPeerConnectionIceErrorEvent handle.
pub fn fromHandle(handle: zjb.Handle) RTCPeerConnectionIceErrorEvent {
    std.debug.assert(!handle.isNull());
    std.debug.assert(@backingInt(handle) != 0);
    return .{ .handle = handle };
}

/// Views a base Event handle as an RTCPeerConnectionIceErrorEvent.
pub fn fromEvent(ev: Event) RTCPeerConnectionIceErrorEvent {
    std.debug.assert(!ev.isNull());
    std.debug.assert(@backingInt(ev.handle) != 0);
    return fromHandle(ev.handle);
}

/// Returns a base Event view over this RTCPeerConnectionIceErrorEvent.
pub fn asEvent(self: RTCPeerConnectionIceErrorEvent) Event {
    return Event.fromHandle(self.handle);
}

/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: RTCPeerConnectionIceErrorEvent) bool {
    return self.handle.isNull();
}

/// Releases the underlying JS handle when owned.
pub fn release(self: RTCPeerConnectionIceErrorEvent) void {
    self.handle.release();
}

/// Cancels default browser action if the event is cancelable.
/// https://developer.mozilla.org/en-US/docs/Web/API/Event/preventDefault
pub fn preventDefault(self: RTCPeerConnectionIceErrorEvent) void {
    self.asEvent().preventDefault();
}

/// Prevents further propagation of the RTCPeerConnectionIceErrorEvent.
/// https://developer.mozilla.org/en-US/docs/Web/API/Event/stopPropagation
pub fn stopPropagation(self: RTCPeerConnectionIceErrorEvent) void {
    self.asEvent().stopPropagation();
}

/// Copies the local IP address used to communicate with the STUN or TURN server into `buf`.
/// https://developer.mozilla.org/en-US/docs/Web/API/RTCPeerConnectionIceErrorEvent/address
pub fn address(self: RTCPeerConnectionIceErrorEvent, buf: []u8) []const u8 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(buf.len > 0);
    const addr_h = self.handle.get("address", zjb.Handle);
    defer addr_h.release();
    return webapi.stringFromHandle(addr_h, buf);
}

/// Returns the port number over which the connection attempt was made.
/// https://developer.mozilla.org/en-US/docs/Web/API/RTCPeerConnectionIceErrorEvent/port
pub fn port(self: RTCPeerConnectionIceErrorEvent) i32 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return self.handle.get("port", i32);
}

/// Copies the URL of the STUN or TURN server that failed into `buf`.
/// https://developer.mozilla.org/en-US/docs/Web/API/RTCPeerConnectionIceErrorEvent/url
pub fn url(self: RTCPeerConnectionIceErrorEvent, buf: []u8) []const u8 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(buf.len > 0);
    const url_h = self.handle.get("url", zjb.Handle);
    defer url_h.release();
    return webapi.stringFromHandle(url_h, buf);
}

/// Returns the numeric STUN or TURN error code associated with the failure.
/// https://developer.mozilla.org/en-US/docs/Web/API/RTCPeerConnectionIceErrorEvent/errorCode
pub fn errorCode(self: RTCPeerConnectionIceErrorEvent) i32 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return self.handle.get("errorCode", i32);
}

/// Copies the human-readable STUN/TURN error text into `buf`.
/// https://developer.mozilla.org/en-US/docs/Web/API/RTCPeerConnectionIceErrorEvent/errorText
pub fn errorText(self: RTCPeerConnectionIceErrorEvent, buf: []u8) []const u8 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(buf.len > 0);
    const text_h = self.handle.get("errorText", zjb.Handle);
    defer text_h.release();
    return webapi.stringFromHandle(text_h, buf);
}
