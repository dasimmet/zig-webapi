//! Minimal Web Audio API wrapper for playing decoded audio and PCM buffers.
//! https://developer.mozilla.org/en-US/docs/Web/API/Web_Audio_API

// 1. Imports
const std = @import("std");
const webapi = @import("webapi.zig");

pub const AudioBuffer = @import("WebAudio/AudioBuffer.zig");
pub const AudioBufferSourceNode = @import("WebAudio/AudioBufferSourceNode.zig");
pub const AudioContext = @import("WebAudio/AudioContext.zig");

// 2. Shortcuts on imports
const zjb = webapi.zjb;

// 8. Extra classes
/// Playback lifecycle state of an `AudioContext`.
/// https://developer.mozilla.org/en-US/docs/Web/API/BaseAudioContext/state
pub const ContextState = enum {
    suspended,
    running,
    closed,
};

/// End destination of an audio graph (speakers).
/// https://developer.mozilla.org/en-US/docs/Web/API/AudioDestinationNode
pub const AudioDestinationNode = struct {
    handle: zjb.Handle,
    pub const @"null": AudioDestinationNode = .{ .handle = .null };

    /// Wraps a non-null JS `AudioDestinationNode` handle.
    pub fn fromHandle(handle: zjb.Handle) AudioDestinationNode {
        std.debug.assert(!handle.isNull());
        std.debug.assert(@backingInt(handle) != 0);
        return .{ .handle = handle };
    }

    /// Returns `true` if the underlying JS handle is null or undefined.
    pub fn isNull(self: AudioDestinationNode) bool {
        return self.handle.isNull();
    }

    /// Releases the underlying JS handle.
    pub fn release(self: AudioDestinationNode) void {
        self.handle.release();
    }
};

// 7. Public helpers
/// Extracts a non-null `zjb.Handle` from a handle or wrapper with `.handle`.
pub fn handleOf(dest: anytype) zjb.Handle {
    const T = @TypeOf(dest);
    if (T == zjb.Handle) {
        std.debug.assert(!dest.isNull());
        return dest;
    }
    if (@hasField(T, "handle")) {
        std.debug.assert(!dest.handle.isNull());
        return dest.handle;
    }
    @compileError("expected zjb.Handle or WebAudio wrapper struct with .handle field");
}

/// Creates a temporary JS `Float32Array` view over WASM linear memory for
/// synchronous Web Audio API calls. Caller must `.release()` the handle.
pub fn float32ViewFromSlice(samples: []const f32) zjb.Handle {
    std.debug.assert(samples.len > 0);
    const dv = zjb.dataView(samples);
    defer dv.release();
    const buf_h = dv.get("buffer", zjb.Handle);
    defer buf_h.release();
    const byte_offset = dv.get("byteOffset", i32);
    const arr = zjb.global("Float32Array").new(.{
        buf_h,
        byte_offset,
        @as(i32, @intCast(samples.len)),
    });
    std.debug.assert(!arr.isNull());
    return arr;
}
