//! MediaStreamTrackEvent Web API interface fired when a `MediaStreamTrack` is
//! added to (`"addtrack"`) or removed from (`"removetrack"`) a `MediaStream`.
//! https://developer.mozilla.org/en-US/docs/Web/API/MediaStreamTrackEvent

// 1. Imports
const std = @import("std");
const webapi = @import("../webapi.zig");
const Event = @import("../Event.zig");
const MediaStreamTrack = @import("../MediaStream/MediaStreamTrack.zig");

// 2. Shortcuts on imports
const MediaStreamTrackEvent = @This();
const zjb = webapi.zjb;

// 3. File-level struct members
handle: zjb.Handle,
pub const @"null": MediaStreamTrackEvent = .{ .handle = .null };

// 7. Public functions
/// Wraps a non-null JS `MediaStreamTrackEvent` handle.
pub fn fromHandle(handle: zjb.Handle) MediaStreamTrackEvent {
    std.debug.assert(!handle.isNull());
    std.debug.assert(@backingInt(handle) != 0);
    return .{ .handle = handle };
}

/// Views a base `Event` handle as a `MediaStreamTrackEvent`.
pub fn fromEvent(ev: Event) MediaStreamTrackEvent {
    std.debug.assert(!ev.isNull());
    std.debug.assert(@backingInt(ev.handle) != 0);
    return fromHandle(ev.handle);
}

/// Returns a base `Event` view over this `MediaStreamTrackEvent`.
pub fn asEvent(self: MediaStreamTrackEvent) Event {
    return Event.fromHandle(self.handle);
}

/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: MediaStreamTrackEvent) bool {
    return self.handle.isNull();
}

/// Releases the underlying JS handle when owned.
pub fn release(self: MediaStreamTrackEvent) void {
    self.handle.release();
}

/// Returns an owned `MediaStreamTrack` associated with this event (`ev.track`).
/// Caller must call `.release()`.
/// https://developer.mozilla.org/en-US/docs/Web/API/MediaStreamTrackEvent/track
pub fn track(self: MediaStreamTrackEvent) MediaStreamTrack {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const h = self.handle.get("track", zjb.Handle);
    if (h.isNull()) return .null;
    return MediaStreamTrack.fromHandle(h);
}
