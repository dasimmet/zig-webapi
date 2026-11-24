//! Audio source node routing a live `MediaStream` (e.g. microphone input from
//! `MediaDevices.getUserMedia`) into an `AudioContext` processing graph.
//! https://developer.mozilla.org/en-US/docs/Web/API/MediaStreamAudioSourceNode

// 1. Imports
const std = @import("std");
const webapi = @import("../webapi.zig");
const WebAudio = @import("../WebAudio.zig");

// 2. Shortcuts on imports
const MediaStreamAudioSourceNode = @This();
const MediaStream = webapi.MediaStream;
const zjb = webapi.zjb;

// 3. File-level struct members
handle: zjb.Handle,
pub const @"null": MediaStreamAudioSourceNode = .{ .handle = .null };

// 7. Public functions
/// Wraps a non-null JS `MediaStreamAudioSourceNode` handle.
pub fn fromHandle(handle: zjb.Handle) MediaStreamAudioSourceNode {
    std.debug.assert(!handle.isNull());
    std.debug.assert(@backingInt(handle) != 0);
    return .{ .handle = handle };
}

/// Returns `true` if the underlying JS handle is null or undefined.
pub fn isNull(self: MediaStreamAudioSourceNode) bool {
    return self.handle.isNull();
}

/// Releases the underlying JS handle.
pub fn release(self: MediaStreamAudioSourceNode) void {
    self.handle.release();
}

/// Returns an owned handle to the underlying `MediaStream` (`node.mediaStream`).
/// Caller must call `.release()`.
/// https://developer.mozilla.org/en-US/docs/Web/API/MediaStreamAudioSourceNode/mediaStream
pub fn mediaStream(self: MediaStreamAudioSourceNode) MediaStream {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const h = self.handle.get("mediaStream", zjb.Handle);
    if (h.isNull()) return .null;
    return MediaStream.fromHandle(h);
}

/// Connects this source node to downstream `AnalyserNode`, `AudioDestinationNode`,
/// or any WebAudio node wrapper / handle.
/// https://developer.mozilla.org/en-US/docs/Web/API/AudioNode/connect
pub fn connect(self: MediaStreamAudioSourceNode, destination: anytype) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const dst_h = WebAudio.handleOf(destination);
    self.handle.call("connect", .{dst_h}, void);
}

/// Disconnects all outgoing connections from this audio source node.
/// https://developer.mozilla.org/en-US/docs/Web/API/AudioNode/disconnect
pub fn disconnect(self: MediaStreamAudioSourceNode) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    self.handle.call("disconnect", .{}, void);
}
