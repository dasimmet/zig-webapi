//! Real-time audio context for decoding and playing `AudioBuffer` assets.
//! https://developer.mozilla.org/en-US/docs/Web/API/AudioContext

// 1. Imports
const std = @import("std");
const webapi = @import("../webapi.zig");
const WebAudio = @import("../WebAudio.zig");

// 2. Shortcuts on imports
const AudioContext = @This();
const AudioBuffer = WebAudio.AudioBuffer;
const AudioBufferSourceNode = WebAudio.AudioBufferSourceNode;
const AudioDestinationNode = WebAudio.AudioDestinationNode;
const ContextState = WebAudio.ContextState;
const Promise = webapi.Promise;
const zjb = webapi.zjb;

// 3. File-level struct members
handle: zjb.Handle,
pub const @"null": AudioContext = .{ .handle = .null };

// 5. init
/// Constructs a new `AudioContext`.
/// https://developer.mozilla.org/en-US/docs/Web/API/AudioContext/AudioContext
pub fn init() AudioContext {
    const h = zjb.global("AudioContext").new(.{});
    return fromHandle(h);
}

// 7. Public functions
/// Returns `true` if `AudioContext` is available in the current global scope.
pub fn isSupported() bool {
    const cls = zjb.ConstHandle.global.get("AudioContext", zjb.Handle);
    defer cls.release();
    return !cls.isNull();
}

/// Wraps a non-null JS `AudioContext` handle.
pub fn fromHandle(handle: zjb.Handle) AudioContext {
    std.debug.assert(!handle.isNull());
    std.debug.assert(@backingInt(handle) != 0);
    return .{ .handle = handle };
}

/// Returns `true` if the underlying JS handle is null or undefined.
pub fn isNull(self: AudioContext) bool {
    return self.handle.isNull();
}

/// Releases the underlying JS handle.
pub fn release(self: AudioContext) void {
    self.handle.release();
}

/// Returns the current playback state (`suspended`, `running`, `closed`).
/// https://developer.mozilla.org/en-US/docs/Web/API/BaseAudioContext/state
pub fn state(self: AudioContext) ContextState {
    std.debug.assert(!self.handle.isNull());
    const s_h = self.handle.get("state", zjb.Handle);
    defer s_h.release();
    var buf: [32]u8 = undefined;
    return std.meta.stringToEnum(
        ContextState,
        webapi.stringFromHandle(s_h, &buf),
    ) orelse .suspended;
}

/// Resumes progression of time in a suspended `AudioContext`.
/// Caller must `.release()` the returned `Promise`.
/// https://developer.mozilla.org/en-US/docs/Web/API/AudioContext/resume
pub fn @"resume"(self: AudioContext) Promise.Typed(void) {
    std.debug.assert(!self.handle.isNull());
    return .fromHandle(self.handle.call("resume", .{}, zjb.Handle));
}

/// Returns the context sample rate in samples per second (Hz).
/// https://developer.mozilla.org/en-US/docs/Web/API/BaseAudioContext/sampleRate
pub fn sampleRate(self: AudioContext) f32 {
    std.debug.assert(!self.handle.isNull());
    return self.handle.get("sampleRate", f32);
}

/// Returns an owned wrapper for the context's final `AudioDestinationNode`.
/// Caller must call `.release()` when done.
/// https://developer.mozilla.org/en-US/docs/Web/API/BaseAudioContext/destination
pub fn destination(self: AudioContext) AudioDestinationNode {
    std.debug.assert(!self.handle.isNull());
    const dest_h = self.handle.get("destination", zjb.Handle);
    std.debug.assert(!dest_h.isNull());
    return AudioDestinationNode.fromHandle(dest_h);
}

/// Creates an empty `AudioBuffer`. Caller must `.release()` when done.
/// https://developer.mozilla.org/en-US/docs/Web/API/BaseAudioContext/createBuffer
pub fn createBuffer(
    self: AudioContext,
    number_of_channels: u32,
    length: u32,
    sample_rate: f32,
) AudioBuffer {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(number_of_channels > 0);
    std.debug.assert(length > 0);
    std.debug.assert(sample_rate > 0.0);
    return AudioBuffer.fromHandle(self.handle.call(
        "createBuffer",
        .{
            @as(i32, @intCast(number_of_channels)),
            @as(i32, @intCast(length)),
            sample_rate,
        },
        zjb.Handle,
    ));
}

/// Creates an `AudioBufferSourceNode`. Caller must `.release()` when done.
/// https://developer.mozilla.org/en-US/docs/Web/API/BaseAudioContext/createBufferSource
pub fn createBufferSource(self: AudioContext) AudioBufferSourceNode {
    std.debug.assert(!self.handle.isNull());
    return AudioBufferSourceNode.fromHandle(
        self.handle.call("createBufferSource", .{}, zjb.Handle),
    );
}

/// Asynchronously decodes encoded audio data from a JS `ArrayBuffer` handle.
/// Caller must `.release()` the returned `Promise`.
/// https://developer.mozilla.org/en-US/docs/Web/API/BaseAudioContext/decodeAudioData
pub fn decodeAudioData(
    self: AudioContext,
    array_buffer: zjb.Handle,
) Promise.Typed(AudioBuffer) {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(!array_buffer.isNull());
    const p = self.handle.call("decodeAudioData", .{array_buffer}, zjb.Handle);
    return .fromHandle(p);
}
