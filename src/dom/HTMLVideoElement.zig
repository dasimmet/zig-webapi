//! HTMLVideoElement Web API interface representing a `<video>` element for
//! video playback and live camera/screen `MediaStream` preview.
//! https://developer.mozilla.org/en-US/docs/Web/API/HTMLVideoElement

// 1. Imports
const std = @import("std");
const webapi = @import("../webapi.zig");
const Element = @import("Element.zig");
const HTMLMediaElement = @import("HTMLMediaElement.zig");

// 2. Shortcuts on imports
const HTMLVideoElement = @This();
const MediaStream = webapi.MediaStream;
const Promise = webapi.Promise;
const zjb = webapi.zjb;

// 3. File-level struct members
handle: zjb.Handle,
pub const @"null": HTMLVideoElement = .{ .handle = .null };

// 7. Public functions
/// Wraps a non-null JS `HTMLVideoElement` handle.
pub fn fromHandle(handle: zjb.Handle) HTMLVideoElement {
    std.debug.assert(!handle.isNull());
    std.debug.assert(@backingInt(handle) != 0);
    return .{ .handle = handle };
}

/// Views a generic DOM `Element` handle as an `HTMLVideoElement`.
pub fn fromElement(el: Element) HTMLVideoElement {
    return fromHandle(el.handle);
}

/// Views this `HTMLVideoElement` handle as a base `Element`.
pub fn asElement(self: HTMLVideoElement) Element {
    return Element.fromHandle(self.handle);
}

/// Views this `HTMLVideoElement` handle as an `HTMLMediaElement`.
pub fn asMedia(self: HTMLVideoElement) HTMLMediaElement {
    return HTMLMediaElement.fromHandle(self.handle);
}

/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: HTMLVideoElement) bool {
    return self.handle.isNull();
}

/// Releases the underlying JS handle.
pub fn release(self: HTMLVideoElement) void {
    self.handle.release();
}

/// Returns the intrinsic width of the decoded video stream in CSS pixels (`0` until ready).
/// https://developer.mozilla.org/en-US/docs/Web/API/HTMLVideoElement/videoWidth
pub fn videoWidth(self: HTMLVideoElement) u32 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const raw = self.handle.get("videoWidth", i32);
    return if (raw > 0) @intCast(raw) else 0;
}

/// Returns the intrinsic height of the decoded video stream in CSS pixels (`0` until ready).
/// https://developer.mozilla.org/en-US/docs/Web/API/HTMLVideoElement/videoHeight
pub fn videoHeight(self: HTMLVideoElement) u32 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const raw = self.handle.get("videoHeight", i32);
    return if (raw > 0) @intCast(raw) else 0;
}

/// Returns the layout `width` attribute in CSS pixels.
/// https://developer.mozilla.org/en-US/docs/Web/API/HTMLVideoElement/width
pub fn width(self: HTMLVideoElement) u32 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const raw = self.handle.get("width", i32);
    return if (raw > 0) @intCast(raw) else 0;
}

/// Sets the layout `width` attribute in CSS pixels.
/// https://developer.mozilla.org/en-US/docs/Web/API/HTMLVideoElement/width
pub fn setWidth(self: HTMLVideoElement, w: u32) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    self.handle.set("width", @as(i32, @intCast(w)));
}

/// Returns the layout `height` attribute in CSS pixels.
/// https://developer.mozilla.org/en-US/docs/Web/API/HTMLVideoElement/height
pub fn height(self: HTMLVideoElement) u32 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const raw = self.handle.get("height", i32);
    return if (raw > 0) @intCast(raw) else 0;
}

/// Sets the layout `height` attribute in CSS pixels.
/// https://developer.mozilla.org/en-US/docs/Web/API/HTMLVideoElement/height
pub fn setHeight(self: HTMLVideoElement, h: u32) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    self.handle.set("height", @as(i32, @intCast(h)));
}

/// Returns whether inline (non-fullscreen) playback is enabled on mobile browsers.
/// https://developer.mozilla.org/en-US/docs/Web/API/HTMLVideoElement/playsInline
pub fn playsInline(self: HTMLVideoElement) bool {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return self.handle.get("playsInline", bool);
}

/// Enables or disables inline video playback (`video.playsInline = val`).
/// Recommended when previewing live camera streams on mobile browsers.
/// https://developer.mozilla.org/en-US/docs/Web/API/HTMLVideoElement/playsInline
pub fn setPlaysInline(self: HTMLVideoElement, val: bool) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    self.handle.set("playsInline", val);
}

/// Assigns or detaches a live `MediaStream` (`video.srcObject = stream`).
pub fn setSrcObject(self: HTMLVideoElement, stream: ?MediaStream) void {
    self.asMedia().setSrcObject(stream);
}

/// Returns an owned `MediaStream` assigned to `srcObject`, or `null`.
pub fn srcObject(self: HTMLVideoElement) ?MediaStream {
    return self.asMedia().srcObject();
}

/// Sets whether audio output on this `<video>` is muted.
pub fn setMuted(self: HTMLVideoElement, val: bool) void {
    self.asMedia().setMuted(val);
}

/// Sets whether playback starts automatically.
pub fn setAutoplay(self: HTMLVideoElement, val: bool) void {
    self.asMedia().setAutoplay(val);
}

/// Starts video playback. Caller must `.release()` the returned `Promise`.
pub fn play(self: HTMLVideoElement) Promise.Typed(void) {
    return self.asMedia().play();
}

/// Pauses video playback.
pub fn pause(self: HTMLVideoElement) void {
    self.asMedia().pause();
}

/// Attaches a context-bound listener (e.g. `"loadedmetadata"`, `"playing"`).
pub fn addEventListener(
    self: HTMLVideoElement,
    comptime event: []const u8,
    comptime Context: type,
    context: *Context,
    comptime f: *const fn (*Context, webapi.Event.EventFor(event)) void,
) void {
    self.asElement().addEventListener(event, Context, context, f);
}
