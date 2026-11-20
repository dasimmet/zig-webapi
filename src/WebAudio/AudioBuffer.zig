//! Short decoded or synthesized PCM audio asset stored in memory.
//! https://developer.mozilla.org/en-US/docs/Web/API/AudioBuffer

// 1. Imports
const std = @import("std");
const webapi = @import("../webapi.zig");
const WebAudio = @import("../WebAudio.zig");

// 2. Shortcuts on imports
const AudioBuffer = @This();
const zjb = webapi.zjb;

// 3. File-level struct members
handle: zjb.Handle,
pub const @"null": AudioBuffer = .{ .handle = .null };

// 7. Public functions
/// Wraps a non-null JS `AudioBuffer` handle.
pub fn fromHandle(handle: zjb.Handle) AudioBuffer {
    std.debug.assert(!handle.isNull());
    std.debug.assert(@backingInt(handle) != 0);
    return .{ .handle = handle };
}

/// Returns `true` if the underlying JS handle is null or undefined.
pub fn isNull(self: AudioBuffer) bool {
    return self.handle.isNull();
}

/// Releases the underlying JS handle.
pub fn release(self: AudioBuffer) void {
    self.handle.release();
}

/// Returns the buffer sample rate in Hz.
/// https://developer.mozilla.org/en-US/docs/Web/API/AudioBuffer/sampleRate
pub fn sampleRate(self: AudioBuffer) f32 {
    std.debug.assert(!self.handle.isNull());
    return self.handle.get("sampleRate", f32);
}

/// Returns the buffer duration in seconds.
/// https://developer.mozilla.org/en-US/docs/Web/API/AudioBuffer/duration
pub fn duration(self: AudioBuffer) f64 {
    std.debug.assert(!self.handle.isNull());
    return self.handle.get("duration", f64);
}

/// Returns the number of discrete audio channels.
/// https://developer.mozilla.org/en-US/docs/Web/API/AudioBuffer/numberOfChannels
pub fn numberOfChannels(self: AudioBuffer) u32 {
    std.debug.assert(!self.handle.isNull());
    const n = self.handle.get("numberOfChannels", i32);
    return if (n > 0) @intCast(n) else 0;
}

/// Copies PCM `f32` samples from Zig memory into `channel_number` starting
/// at `buffer_offset` sample-frames.
/// https://developer.mozilla.org/en-US/docs/Web/API/AudioBuffer/copyToChannel
pub fn copyToChannel(
    self: AudioBuffer,
    source: []const f32,
    channel_number: u32,
    buffer_offset: u32,
) void {
    std.debug.assert(!self.handle.isNull());
    if (source.len == 0) return;
    const src_arr = WebAudio.float32ViewFromSlice(source);
    defer src_arr.release();
    self.handle.call(
        "copyToChannel",
        .{
            src_arr,
            @as(i32, @intCast(channel_number)),
            @as(i32, @intCast(buffer_offset)),
        },
        void,
    );
}
