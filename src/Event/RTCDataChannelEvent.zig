//! RTCDataChannelEvent Web API interface representing events sent when an RTCDataChannel
//! is added to an RTCPeerConnection.
//! Used by `"datachannel"` listeners (inherits from Event).
//! https://developer.mozilla.org/en-US/docs/Web/API/RTCDataChannelEvent

// 1. Imports
const std = @import("std");
const webapi = @import("../webapi.zig");
const Event = @import("../Event.zig");
const WebRTC = @import("../WebRTC.zig");

// 2. Shortcuts on imports
const RTCDataChannelEvent = @This();
const zjb = webapi.zjb;

// 3. File-level struct members
handle: zjb.Handle,
pub const @"null": RTCDataChannelEvent = .{ .handle = .null };

// 7. Public functions
/// Wraps a non-null JS RTCDataChannelEvent handle.
pub fn fromHandle(handle: zjb.Handle) RTCDataChannelEvent {
    std.debug.assert(!handle.isNull());
    std.debug.assert(@backingInt(handle) != 0);
    return .{ .handle = handle };
}

/// Views a base Event handle as an RTCDataChannelEvent.
pub fn fromEvent(ev: Event) RTCDataChannelEvent {
    std.debug.assert(!ev.isNull());
    std.debug.assert(@backingInt(ev.handle) != 0);
    return fromHandle(ev.handle);
}

/// Returns a base Event view over this RTCDataChannelEvent.
pub fn asEvent(self: RTCDataChannelEvent) Event {
    return Event.fromHandle(self.handle);
}

/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: RTCDataChannelEvent) bool {
    return self.handle.isNull();
}

/// Releases the underlying JS handle when owned.
pub fn release(self: RTCDataChannelEvent) void {
    self.handle.release();
}

/// Cancels default browser action if the event is cancelable.
/// https://developer.mozilla.org/en-US/docs/Web/API/Event/preventDefault
pub fn preventDefault(self: RTCDataChannelEvent) void {
    self.asEvent().preventDefault();
}

/// Prevents further propagation of the RTCDataChannelEvent.
/// https://developer.mozilla.org/en-US/docs/Web/API/Event/stopPropagation
pub fn stopPropagation(self: RTCDataChannelEvent) void {
    self.asEvent().stopPropagation();
}

/// Returns an owned RTCDataChannel wrapper for the channel associated with this event.
/// https://developer.mozilla.org/en-US/docs/Web/API/RTCDataChannelEvent/channel
pub fn channel(self: RTCDataChannelEvent) WebRTC.RTCDataChannel {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return WebRTC.RTCDataChannel.fromHandle(self.handle.get("channel", zjb.Handle));
}
