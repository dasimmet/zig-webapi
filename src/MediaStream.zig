//! Type-safe wrapper for the browser `MediaStream` Web API, representing a
//! stream of media content (`audio` and/or `video` `MediaStreamTrack` items).
//! https://developer.mozilla.org/en-US/docs/Web/API/MediaStream

// 1. Imports
const std = @import("std");
const webapi = @import("webapi.zig");

pub const MediaDeviceInfo = @import("MediaStream/MediaDeviceInfo.zig");
pub const MediaDevices = @import("MediaStream/MediaDevices.zig");
pub const MediaStreamTrack = @import("MediaStream/MediaStreamTrack.zig");

// 2. Shortcuts on imports
const MediaStream = @This();
const Event = webapi.Event;
const zjb = webapi.zjb;

// 3. File-level struct members
handle: zjb.Handle,
pub const @"null": MediaStream = .{ .handle = .null };

// 5. init
/// Constructs an empty `MediaStream` (`new MediaStream()`).
/// https://developer.mozilla.org/en-US/docs/Web/API/MediaStream/MediaStream
pub fn init() MediaStream {
    const h = zjb.global("MediaStream").new(.{});
    return fromHandle(h);
}

/// Constructs a `MediaStream` populated with the given `tracks`.
/// https://developer.mozilla.org/en-US/docs/Web/API/MediaStream/MediaStream
pub fn fromTracks(tracks: []const MediaStreamTrack) MediaStream {
    std.debug.assert(@intFromPtr(tracks.ptr) != 0 or tracks.len == 0);
    std.debug.assert(tracks.len <= 1024);
    const arr = zjb.global("Array").new(.{});
    defer arr.release();
    for (tracks) |track| {
        std.debug.assert(!track.isNull());
        arr.call("push", .{track.handle}, void);
    }
    return fromHandle(zjb.global("MediaStream").new(.{arr}));
}

// 7. Public functions
/// Returns true if `MediaStream` is available in the current global scope.
pub fn isSupported() bool {
    const cls = zjb.ConstHandle.global.get("MediaStream", zjb.Handle);
    defer cls.release();
    return !cls.isNull();
}

/// Wraps a non-null JS `MediaStream` handle.
pub fn fromHandle(handle: zjb.Handle) MediaStream {
    std.debug.assert(!handle.isNull());
    std.debug.assert(@backingInt(handle) != 0);
    return .{ .handle = handle };
}

/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: MediaStream) bool {
    return self.handle.isNull();
}

/// Releases the underlying JS handle.
pub fn release(self: MediaStream) void {
    self.handle.release();
}

/// Copies the stream's unique 36-character UUID (`stream.id`) into `buf`.
/// https://developer.mozilla.org/en-US/docs/Web/API/MediaStream/id
pub fn id(self: MediaStream, buf: []u8) []u8 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(buf.len > 0);
    const h = self.handle.get("id", zjb.Handle);
    defer h.release();
    if (h.isNull()) return "";
    return webapi.stringFromHandle(h, buf);
}

/// Returns true if any `MediaStreamTrack` in this stream is still `live`.
/// https://developer.mozilla.org/en-US/docs/Web/API/MediaStream/active
pub fn active(self: MediaStream) bool {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return self.handle.get("active", bool);
}

/// Returns an owned list of all `MediaStreamTrack` objects in this stream.
/// Caller must call `.release()` on the returned `List`.
/// https://developer.mozilla.org/en-US/docs/Web/API/MediaStream/getTracks
pub fn getTracks(self: MediaStream) MediaStreamTrack.List {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const h = self.handle.call("getTracks", .{}, zjb.Handle);
    if (h.isNull()) return .null;
    return MediaStreamTrack.List.fromHandle(h);
}

/// Returns an owned list of audio `MediaStreamTrack` objects in this stream.
/// Caller must call `.release()` on the returned `List`.
/// https://developer.mozilla.org/en-US/docs/Web/API/MediaStream/getAudioTracks
pub fn getAudioTracks(self: MediaStream) MediaStreamTrack.List {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const h = self.handle.call("getAudioTracks", .{}, zjb.Handle);
    if (h.isNull()) return .null;
    return MediaStreamTrack.List.fromHandle(h);
}

/// Returns an owned list of video `MediaStreamTrack` objects in this stream.
/// Caller must call `.release()` on the returned `List`.
/// https://developer.mozilla.org/en-US/docs/Web/API/MediaStream/getVideoTracks
pub fn getVideoTracks(self: MediaStream) MediaStreamTrack.List {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const h = self.handle.call("getVideoTracks", .{}, zjb.Handle);
    if (h.isNull()) return .null;
    return MediaStreamTrack.List.fromHandle(h);
}

/// Adds `track` to this `MediaStream`.
/// https://developer.mozilla.org/en-US/docs/Web/API/MediaStream/addTrack
pub fn addTrack(self: MediaStream, track: MediaStreamTrack) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(!track.isNull());
    self.handle.call("addTrack", .{track.handle}, void);
}

/// Removes `track` from this `MediaStream`.
/// https://developer.mozilla.org/en-US/docs/Web/API/MediaStream/removeTrack
pub fn removeTrack(self: MediaStream, track: MediaStreamTrack) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(!track.isNull());
    self.handle.call("removeTrack", .{track.handle}, void);
}

/// Clones this `MediaStream` with new track instances. Caller must `.release()`.
/// https://developer.mozilla.org/en-US/docs/Web/API/MediaStream/clone
pub fn clone(self: MediaStream) MediaStream {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return fromHandle(self.handle.call("clone", .{}, zjb.Handle));
}

/// Stops every audio and video `MediaStreamTrack` in this stream, releasing
/// hardware capture indicators (camera/microphone) and intermediate handles.
pub fn stopAllTracks(self: MediaStream) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    var tracks = self.getTracks();
    if (tracks.isNull()) return;
    defer tracks.release();
    while (tracks.next()) |track| {
        defer track.release();
        track.stop();
    }
}

/// Attaches a context-bound listener (e.g. `"addtrack"`, `"removetrack"`).
pub fn addEventListener(
    self: MediaStream,
    comptime event: []const u8,
    comptime T: type,
    ctx: *T,
    comptime f: *const fn (*T, Event.EventFor(event)) void,
) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(event.len > 0);
    webapi.boundEventListenerTyped(
        T,
        Event.EventFor(event),
        event,
        self.handle,
        f,
        ctx,
    );
}
