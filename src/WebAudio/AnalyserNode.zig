//! Real-time time-domain waveform and FFT frequency analyser node (`AnalyserNode`).
//! https://developer.mozilla.org/en-US/docs/Web/API/AnalyserNode

// 1. Imports
const std = @import("std");
const webapi = @import("../webapi.zig");
const WebAudio = @import("../WebAudio.zig");

// 2. Shortcuts on imports
const AnalyserNode = @This();
const zjb = webapi.zjb;

// 3. File-level struct members
handle: zjb.Handle,
pub const @"null": AnalyserNode = .{ .handle = .null };

// 7. Public functions
/// Wraps a non-null JS `AnalyserNode` handle.
pub fn fromHandle(handle: zjb.Handle) AnalyserNode {
    std.debug.assert(!handle.isNull());
    std.debug.assert(@backingInt(handle) != 0);
    return .{ .handle = handle };
}

/// Returns `true` if the underlying JS handle is null or undefined.
pub fn isNull(self: AnalyserNode) bool {
    return self.handle.isNull();
}

/// Releases the underlying JS handle.
pub fn release(self: AnalyserNode) void {
    self.handle.release();
}

/// Returns the current FFT window size (`32..32768`, power of two).
/// https://developer.mozilla.org/en-US/docs/Web/API/AnalyserNode/fftSize
pub fn fftSize(self: AnalyserNode) u32 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const raw = self.handle.get("fftSize", i32);
    return if (raw > 0) @intCast(raw) else 0;
}

/// Sets the FFT window size (`size` must be a power of two in `[32, 32768]`).
/// https://developer.mozilla.org/en-US/docs/Web/API/AnalyserNode/fftSize
pub fn setFftSize(self: AnalyserNode, size: u32) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(size >= 32 and size <= 32768);
    std.debug.assert(std.math.isPowerOfTwo(size));
    self.handle.set("fftSize", @as(i32, @intCast(size)));
}

/// Returns the number of frequency data bins (`fftSize / 2`).
/// https://developer.mozilla.org/en-US/docs/Web/API/AnalyserNode/frequencyBinCount
pub fn frequencyBinCount(self: AnalyserNode) u32 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const raw = self.handle.get("frequencyBinCount", i32);
    return if (raw > 0) @intCast(raw) else 0;
}

/// Returns the minimum decibel value for unsigned byte FFT scaling.
/// https://developer.mozilla.org/en-US/docs/Web/API/AnalyserNode/minDecibels
pub fn minDecibels(self: AnalyserNode) f32 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return self.handle.get("minDecibels", f32);
}

/// Returns the maximum decibel value for unsigned byte FFT scaling.
/// https://developer.mozilla.org/en-US/docs/Web/API/AnalyserNode/maxDecibels
pub fn maxDecibels(self: AnalyserNode) f32 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return self.handle.get("maxDecibels", f32);
}

/// Returns the averaging constant `[0.0, 1.0]` with the previous analysis frame.
/// https://developer.mozilla.org/en-US/docs/Web/API/AnalyserNode/smoothingTimeConstant
pub fn smoothingTimeConstant(self: AnalyserNode) f64 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return self.handle.get("smoothingTimeConstant", f64);
}

/// Sets the averaging constant (`val` in `[0.0, 1.0]`).
/// https://developer.mozilla.org/en-US/docs/Web/API/AnalyserNode/smoothingTimeConstant
pub fn setSmoothingTimeConstant(self: AnalyserNode, val: f64) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(val >= 0.0 and val <= 1.0);
    self.handle.set("smoothingTimeConstant", val);
}

/// Copies the current 8-bit time-domain waveform (`128` = silence) into `dest`.
/// https://developer.mozilla.org/en-US/docs/Web/API/AnalyserNode/getByteTimeDomainData
pub fn getByteTimeDomainData(self: AnalyserNode, dest: []u8) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(dest.len > 0);
    const view = zjb.u8ArrayView(dest);
    defer view.release();
    self.handle.call("getByteTimeDomainData", .{view}, void);
}

/// Copies the current 8-bit FFT frequency spectrum magnitudes into `dest`.
/// https://developer.mozilla.org/en-US/docs/Web/API/AnalyserNode/getByteFrequencyData
pub fn getByteFrequencyData(self: AnalyserNode, dest: []u8) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(dest.len > 0);
    const view = zjb.u8ArrayView(dest);
    defer view.release();
    self.handle.call("getByteFrequencyData", .{view}, void);
}

/// Copies the current 32-bit float time-domain PCM waveform into `dest`.
/// https://developer.mozilla.org/en-US/docs/Web/API/AnalyserNode/getFloatTimeDomainData
pub fn getFloatTimeDomainData(self: AnalyserNode, dest: []f32) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(dest.len > 0);
    const view = WebAudio.float32ViewFromSlice(dest);
    defer view.release();
    self.handle.call("getFloatTimeDomainData", .{view}, void);
}

/// Copies the current 32-bit float FFT frequency magnitudes (in dB) into `dest`.
/// https://developer.mozilla.org/en-US/docs/Web/API/AnalyserNode/getFloatFrequencyData
pub fn getFloatFrequencyData(self: AnalyserNode, dest: []f32) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(dest.len > 0);
    const view = WebAudio.float32ViewFromSlice(dest);
    defer view.release();
    self.handle.call("getFloatFrequencyData", .{view}, void);
}

/// Connects this analyser node to a downstream WebAudio node or destination.
/// https://developer.mozilla.org/en-US/docs/Web/API/AudioNode/connect
pub fn connect(self: AnalyserNode, destination: anytype) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const dst_h = WebAudio.handleOf(destination);
    self.handle.call("connect", .{dst_h}, void);
}

/// Disconnects all outgoing connections from this analyser node.
/// https://developer.mozilla.org/en-US/docs/Web/API/AudioNode/disconnect
pub fn disconnect(self: AnalyserNode) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    self.handle.call("disconnect", .{}, void);
}
