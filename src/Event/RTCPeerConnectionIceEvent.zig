//! RTCPeerConnectionIceEvent Web API interface representing events occurring in relation
//! to ICE candidates with the target, typically an RTCPeerConnection.
//! Used by `"icecandidate"` listeners (inherits from Event).
//! https://developer.mozilla.org/en-US/docs/Web/API/RTCPeerConnectionIceEvent

// 1. Imports
const std = @import("std");
const webapi = @import("../webapi.zig");
const Event = @import("../Event.zig");
const WebRTC = @import("../WebRTC.zig");

// 2. Shortcuts on imports
const RTCPeerConnectionIceEvent = @This();
const zjb = webapi.zjb;

// 3. File-level struct members
handle: zjb.Handle,
pub const @"null": RTCPeerConnectionIceEvent = .{ .handle = .null };

// 7. Public functions
/// Wraps a non-null JS RTCPeerConnectionIceEvent handle.
pub fn fromHandle(handle: zjb.Handle) RTCPeerConnectionIceEvent {
    std.debug.assert(!handle.isNull());
    std.debug.assert(@backingInt(handle) != 0);
    return .{ .handle = handle };
}

/// Views a base Event handle as an RTCPeerConnectionIceEvent.
pub fn fromEvent(ev: Event) RTCPeerConnectionIceEvent {
    std.debug.assert(!ev.isNull());
    std.debug.assert(@backingInt(ev.handle) != 0);
    return fromHandle(ev.handle);
}

/// Returns a base Event view over this RTCPeerConnectionIceEvent.
pub fn asEvent(self: RTCPeerConnectionIceEvent) Event {
    return Event.fromHandle(self.handle);
}

/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: RTCPeerConnectionIceEvent) bool {
    return self.handle.isNull();
}

/// Releases the underlying JS handle when owned.
pub fn release(self: RTCPeerConnectionIceEvent) void {
    self.handle.release();
}

/// Cancels default browser action if the event is cancelable.
/// https://developer.mozilla.org/en-US/docs/Web/API/Event/preventDefault
pub fn preventDefault(self: RTCPeerConnectionIceEvent) void {
    self.asEvent().preventDefault();
}

/// Prevents further propagation of the RTCPeerConnectionIceEvent.
/// https://developer.mozilla.org/en-US/docs/Web/API/Event/stopPropagation
pub fn stopPropagation(self: RTCPeerConnectionIceEvent) void {
    self.asEvent().stopPropagation();
}

/// Returns the RTCIceCandidate associated with this event, or null when
/// ICE candidate gathering has finished.
/// https://developer.mozilla.org/en-US/docs/Web/API/RTCPeerConnectionIceEvent/candidate
pub fn candidate(self: RTCPeerConnectionIceEvent) ?WebRTC.RTCIceCandidate {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const cand_h = self.handle.get("candidate", zjb.Handle);
    if (cand_h.isNull()) {
        cand_h.release();
        return null;
    }
    return WebRTC.RTCIceCandidate.fromHandle(cand_h);
}

/// Copies the STUN or TURN server URL used to gather the candidate into `buf`,
/// or returns null if the candidate came from a host interface.
/// https://developer.mozilla.org/en-US/docs/Web/API/RTCPeerConnectionIceEvent/url
pub fn url(self: RTCPeerConnectionIceEvent, buf: []u8) ?[]const u8 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(buf.len > 0);
    const url_h = self.handle.get("url", zjb.Handle);
    defer url_h.release();
    if (url_h.isNull()) return null;
    return webapi.stringFromHandle(url_h, buf);
}
