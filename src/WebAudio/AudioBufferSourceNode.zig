//! Playback source node for an `AudioBuffer`.
//! https://developer.mozilla.org/en-US/docs/Web/API/AudioBufferSourceNode

// 1. Imports
const std = @import("std");
const webapi = @import("../webapi.zig");
const WebAudio = @import("../WebAudio.zig");

// 2. Shortcuts on imports
const AudioBufferSourceNode = @This();
const AudioBuffer = WebAudio.AudioBuffer;
const Event = webapi.Event;
const zjb = webapi.zjb;

// 3. File-level struct members
handle: zjb.Handle,
pub const @"null": AudioBufferSourceNode = .{ .handle = .null };

// 7. Public functions
/// Wraps a non-null JS `AudioBufferSourceNode` handle.
pub fn fromHandle(handle: zjb.Handle) AudioBufferSourceNode {
    std.debug.assert(!handle.isNull());
    std.debug.assert(@backingInt(handle) != 0);
    return .{ .handle = handle };
}

/// Returns `true` if the underlying JS handle is null or undefined.
pub fn isNull(self: AudioBufferSourceNode) bool {
    return self.handle.isNull();
}

/// Releases the underlying JS handle.
pub fn release(self: AudioBufferSourceNode) void {
    self.handle.release();
}

/// Assigns the `AudioBuffer` to be played by this source node.
/// https://developer.mozilla.org/en-US/docs/Web/API/AudioBufferSourceNode/buffer
pub fn setBuffer(self: AudioBufferSourceNode, audio_buf: AudioBuffer) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(!audio_buf.isNull());
    self.handle.set("buffer", audio_buf.handle);
}

/// Connects this source node to an `AudioDestinationNode` or handle.
/// https://developer.mozilla.org/en-US/docs/Web/API/AudioNode/connect
pub fn connect(self: AudioBufferSourceNode, destination: anytype) void {
    std.debug.assert(!self.handle.isNull());
    const dst_h = WebAudio.handleOf(destination);
    self.handle.call("connect", .{dst_h}, void);
}

/// Starts buffer playback immediately from the beginning.
/// https://developer.mozilla.org/en-US/docs/Web/API/AudioBufferSourceNode/start
pub fn start(self: AudioBufferSourceNode) void {
    std.debug.assert(!self.handle.isNull());
    self.handle.call("start", .{}, void);
}

/// Attaches a typed listener (e.g. `"ended"`).
/// https://developer.mozilla.org/en-US/docs/Web/API/AudioScheduledSourceNode/ended_event
pub fn addEventListener(
    self: AudioBufferSourceNode,
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
