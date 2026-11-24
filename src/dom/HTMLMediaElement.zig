//! HTMLMediaElement Web API interface shared by `<audio>` and `<video>` elements,
//! supporting URL playback as well as live `MediaStream` attachment (`srcObject`).
//! https://developer.mozilla.org/en-US/docs/Web/API/HTMLMediaElement

// 1. Imports
const std = @import("std");
const webapi = @import("../webapi.zig");
const Element = @import("Element.zig");

// 2. Shortcuts on imports
const HTMLMediaElement = @This();
const MediaStream = webapi.MediaStream;
const Promise = webapi.Promise;
const zjb = webapi.zjb;

// 3. File-level struct members
handle: zjb.Handle,
pub const @"null": HTMLMediaElement = .{ .handle = .null };

// 7. Public functions
/// Wraps a non-null JS `HTMLMediaElement` handle.
pub fn fromHandle(handle: zjb.Handle) HTMLMediaElement {
    std.debug.assert(!handle.isNull());
    std.debug.assert(@backingInt(handle) != 0);
    return .{ .handle = handle };
}

/// Views a generic DOM `Element` handle as an `HTMLMediaElement`.
pub fn fromElement(el: Element) HTMLMediaElement {
    return fromHandle(el.handle);
}

/// Views this `HTMLMediaElement` handle as a base `Element`.
pub fn asElement(self: HTMLMediaElement) Element {
    return Element.fromHandle(self.handle);
}

/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: HTMLMediaElement) bool {
    return self.handle.isNull();
}

/// Releases the underlying JS handle.
pub fn release(self: HTMLMediaElement) void {
    self.handle.release();
}

/// Assigns or detaches a live `MediaStream` (`element.srcObject = stream`).
/// Pass `null` to detach the stream from the media element.
/// https://developer.mozilla.org/en-US/docs/Web/API/HTMLMediaElement/srcObject
pub fn setSrcObject(self: HTMLMediaElement, stream: ?MediaStream) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    if (stream) |s| {
        std.debug.assert(!s.isNull());
        self.handle.set("srcObject", s.handle);
    } else {
        self.handle.set("srcObject", zjb.Handle.null);
    }
}

/// Returns an owned `MediaStream` currently assigned to `srcObject`, or `null`.
/// Caller must call `.release()` when non-null.
/// https://developer.mozilla.org/en-US/docs/Web/API/HTMLMediaElement/srcObject
pub fn srcObject(self: HTMLMediaElement) ?MediaStream {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const h = self.handle.get("srcObject", zjb.Handle);
    if (h.isNull()) {
        h.release();
        return null;
    }
    return MediaStream.fromHandle(h);
}

/// Sets `element.src` from a UTF-8 slice (`[]const u8`) or `zjb.Handle` (e.g. object URL).
/// https://developer.mozilla.org/en-US/docs/Web/API/HTMLMediaElement/src
pub fn setSrc(self: HTMLMediaElement, src: anytype) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const T = @TypeOf(src);
    if (T == zjb.Handle or T == zjb.ConstHandle) {
        self.handle.set("src", src);
    } else {
        const s = zjb.string(src);
        defer s.release();
        self.handle.set("src", s);
    }
}

/// Copies `element.src` into `buf`.
/// https://developer.mozilla.org/en-US/docs/Web/API/HTMLMediaElement/src
pub fn getSrc(self: HTMLMediaElement, buf: []u8) []u8 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(buf.len > 0);
    const h = self.handle.get("src", zjb.Handle);
    defer h.release();
    if (h.isNull()) return "";
    return webapi.stringFromHandle(h, buf);
}

/// Starts or resumes playback of the media resource.
/// Caller must `.release()` the returned `Promise`.
/// https://developer.mozilla.org/en-US/docs/Web/API/HTMLMediaElement/play
pub fn play(self: HTMLMediaElement) Promise.Typed(void) {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return .fromHandle(self.handle.call("play", .{}, zjb.Handle));
}

/// Pauses media playback.
/// https://developer.mozilla.org/en-US/docs/Web/API/HTMLMediaElement/pause
pub fn pause(self: HTMLMediaElement) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    self.handle.call("pause", .{}, void);
}

/// Resets the media element and reloads its media source.
/// https://developer.mozilla.org/en-US/docs/Web/API/HTMLMediaElement/load
pub fn load(self: HTMLMediaElement) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    self.handle.call("load", .{}, void);
}

/// Returns true if audio output is muted (`element.muted`).
/// https://developer.mozilla.org/en-US/docs/Web/API/HTMLMediaElement/muted
pub fn muted(self: HTMLMediaElement) bool {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return self.handle.get("muted", bool);
}

/// Sets whether audio output is muted (`element.muted = val`).
/// https://developer.mozilla.org/en-US/docs/Web/API/HTMLMediaElement/muted
pub fn setMuted(self: HTMLMediaElement, val: bool) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    self.handle.set("muted", val);
}

/// Returns true if playback begins automatically (`element.autoplay`).
/// https://developer.mozilla.org/en-US/docs/Web/API/HTMLMediaElement/autoplay
pub fn autoplay(self: HTMLMediaElement) bool {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return self.handle.get("autoplay", bool);
}

/// Sets whether playback begins automatically (`element.autoplay = val`).
/// https://developer.mozilla.org/en-US/docs/Web/API/HTMLMediaElement/autoplay
pub fn setAutoplay(self: HTMLMediaElement, val: bool) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    self.handle.set("autoplay", val);
}

/// Returns true if browser playback controls are shown (`element.controls`).
/// https://developer.mozilla.org/en-US/docs/Web/API/HTMLMediaElement/controls
pub fn controls(self: HTMLMediaElement) bool {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return self.handle.get("controls", bool);
}

/// Sets whether browser playback controls are shown (`element.controls = val`).
/// https://developer.mozilla.org/en-US/docs/Web/API/HTMLMediaElement/controls
pub fn setControls(self: HTMLMediaElement, val: bool) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    self.handle.set("controls", val);
}

/// Returns true if media loops upon reaching the end (`element.loop`).
/// https://developer.mozilla.org/en-US/docs/Web/API/HTMLMediaElement/loop
pub fn loop(self: HTMLMediaElement) bool {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return self.handle.get("loop", bool);
}

/// Sets whether media loops upon reaching the end (`element.loop = val`).
/// https://developer.mozilla.org/en-US/docs/Web/API/HTMLMediaElement/loop
pub fn setLoop(self: HTMLMediaElement, val: bool) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    self.handle.set("loop", val);
}

/// Returns true if playback is currently paused (`element.paused`).
/// https://developer.mozilla.org/en-US/docs/Web/API/HTMLMediaElement/paused
pub fn paused(self: HTMLMediaElement) bool {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return self.handle.get("paused", bool);
}

/// Returns true if playback has reached the end (`element.ended`).
/// https://developer.mozilla.org/en-US/docs/Web/API/HTMLMediaElement/ended
pub fn ended(self: HTMLMediaElement) bool {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return self.handle.get("ended", bool);
}

/// Returns the audio playback volume in `[0.0, 1.0]`.
/// https://developer.mozilla.org/en-US/docs/Web/API/HTMLMediaElement/volume
pub fn volume(self: HTMLMediaElement) f64 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return self.handle.get("volume", f64);
}

/// Sets the audio playback volume (`val` in `[0.0, 1.0]`).
/// https://developer.mozilla.org/en-US/docs/Web/API/HTMLMediaElement/volume
pub fn setVolume(self: HTMLMediaElement, val: f64) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(val >= 0.0 and val <= 1.0);
    self.handle.set("volume", val);
}

/// Returns the current playback time in seconds (`element.currentTime`).
/// https://developer.mozilla.org/en-US/docs/Web/API/HTMLMediaElement/currentTime
pub fn currentTime(self: HTMLMediaElement) f64 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return self.handle.get("currentTime", f64);
}

/// Seeks to `seconds` (`element.currentTime = seconds`).
/// https://developer.mozilla.org/en-US/docs/Web/API/HTMLMediaElement/currentTime
pub fn setCurrentTime(self: HTMLMediaElement, seconds: f64) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(std.math.isFinite(seconds) and seconds >= 0.0);
    self.handle.set("currentTime", seconds);
}

/// Returns the media duration in seconds (`NaN` if unknown, `+Inf` for live streams).
/// https://developer.mozilla.org/en-US/docs/Web/API/HTMLMediaElement/duration
pub fn duration(self: HTMLMediaElement) f64 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return self.handle.get("duration", f64);
}

/// Returns the readiness state (`0 = HAVE_NOTHING .. 4 = HAVE_ENOUGH_DATA`).
/// https://developer.mozilla.org/en-US/docs/Web/API/HTMLMediaElement/readyState
pub fn readyState(self: HTMLMediaElement) u16 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const raw = self.handle.get("readyState", i32);
    return if (raw > 0) @intCast(raw) else 0;
}

/// Attaches a context-bound listener (e.g. `"loadedmetadata"`, `"playing"`, `"ended"`).
pub fn addEventListener(
    self: HTMLMediaElement,
    comptime event: []const u8,
    comptime Context: type,
    context: *Context,
    comptime f: *const fn (*Context, webapi.Event.EventFor(event)) void,
) void {
    self.asElement().addEventListener(event, Context, context, f);
}
