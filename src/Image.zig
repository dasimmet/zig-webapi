//! Type-safe wrapper for the browser `Image` (`HTMLImageElement`) Web API.
//! https://developer.mozilla.org/en-US/docs/Web/API/HTMLImageElement/Image

// 1. Imports
const std = @import("std");
const webapi = @import("webapi.zig");

// 2. Shortcuts on imports
const Image = @This();
const Event = webapi.Event;
const Promise = webapi.Promise;
const zjb = webapi.zjb;

// 3. File-level struct members
handle: zjb.Handle,
pub const @"null": Image = .{ .handle = .null };

// 5. init
/// Constructs an empty `Image` (`new Image()`).
/// https://developer.mozilla.org/en-US/docs/Web/API/HTMLImageElement/Image
pub fn init() Image {
    const h = zjb.global("Image").new(.{});
    return fromHandle(h);
}

/// Constructs an `Image` with explicit layout `width` and `height` attributes.
/// https://developer.mozilla.org/en-US/docs/Web/API/HTMLImageElement/Image
pub fn initWithSize(width_px: i32, height_px: i32) Image {
    std.debug.assert(width_px >= 0);
    std.debug.assert(height_px >= 0);
    const h = zjb.global("Image").new(.{ width_px, height_px });
    return fromHandle(h);
}

// 7. Public functions
/// Returns true if `Image` is available in the current global scope.
pub fn isSupported() bool {
    const cls = zjb.ConstHandle.global.get("Image", zjb.Handle);
    defer cls.release();
    return !cls.isNull();
}

/// Wraps a non-null JS `HTMLImageElement` handle.
pub fn fromHandle(handle: zjb.Handle) Image {
    std.debug.assert(!handle.isNull());
    std.debug.assert(@backingInt(handle) != 0);
    return .{ .handle = handle };
}

/// Returns `true` if the underlying JS handle is null or undefined.
pub fn isNull(self: Image) bool {
    return self.handle.isNull();
}

/// Releases the underlying JS handle.
pub fn release(self: Image) void {
    self.handle.release();
}

/// Sets `image.src` from a string slice (`[]const u8`) or `zjb.Handle`
/// (such as an object URL returned by `URL.createObjectURL`).
/// https://developer.mozilla.org/en-US/docs/Web/API/HTMLImageElement/src
pub fn setSrc(self: Image, src: anytype) void {
    std.debug.assert(!self.handle.isNull());
    const T = @TypeOf(src);
    if (T == zjb.Handle or T == zjb.ConstHandle) {
        self.handle.set("src", src);
    } else {
        const s = zjb.string(src);
        defer s.release();
        self.handle.set("src", s);
    }
}

/// Copies `image.src` into `buf`.
/// https://developer.mozilla.org/en-US/docs/Web/API/HTMLImageElement/src
pub fn getSrc(self: Image, buf: []u8) []u8 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(buf.len > 0);
    const h = self.handle.get("src", zjb.Handle);
    defer h.release();
    if (h.isNull()) return "";
    return webapi.stringFromHandle(h, buf);
}

/// Copies `image.alt` into `buf`.
/// https://developer.mozilla.org/en-US/docs/Web/API/HTMLImageElement/alt
pub fn alt(self: Image, buf: []u8) []u8 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(buf.len > 0);
    const h = self.handle.get("alt", zjb.Handle);
    defer h.release();
    if (h.isNull()) return "";
    return webapi.stringFromHandle(h, buf);
}

/// Sets `image.alt`.
/// https://developer.mozilla.org/en-US/docs/Web/API/HTMLImageElement/alt
pub fn setAlt(self: Image, text: []const u8) void {
    std.debug.assert(!self.handle.isNull());
    const s = zjb.string(text);
    defer s.release();
    self.handle.set("alt", s);
}

/// Returns the rendered CSS layout `width` attribute in pixels.
/// https://developer.mozilla.org/en-US/docs/Web/API/HTMLImageElement/width
pub fn width(self: Image) i32 {
    std.debug.assert(!self.handle.isNull());
    return self.handle.get("width", i32);
}

/// Sets the layout `width` attribute in pixels.
/// https://developer.mozilla.org/en-US/docs/Web/API/HTMLImageElement/width
pub fn setWidth(self: Image, w: i32) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(w >= 0);
    self.handle.set("width", w);
}

/// Returns the rendered CSS layout `height` attribute in pixels.
/// https://developer.mozilla.org/en-US/docs/Web/API/HTMLImageElement/height
pub fn height(self: Image) i32 {
    std.debug.assert(!self.handle.isNull());
    return self.handle.get("height", i32);
}

/// Sets the layout `height` attribute in pixels.
/// https://developer.mozilla.org/en-US/docs/Web/API/HTMLImageElement/height
pub fn setHeight(self: Image, h: i32) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(h >= 0);
    self.handle.set("height", h);
}

/// Returns the intrinsic width of the decoded image in CSS pixels.
/// https://developer.mozilla.org/en-US/docs/Web/API/HTMLImageElement/naturalWidth
pub fn naturalWidth(self: Image) i32 {
    std.debug.assert(!self.handle.isNull());
    return self.handle.get("naturalWidth", i32);
}

/// Returns the intrinsic height of the decoded image in CSS pixels.
/// https://developer.mozilla.org/en-US/docs/Web/API/HTMLImageElement/naturalHeight
pub fn naturalHeight(self: Image) i32 {
    std.debug.assert(!self.handle.isNull());
    return self.handle.get("naturalHeight", i32);
}

/// Returns `true` if the browser has finished fetching the image resource.
/// https://developer.mozilla.org/en-US/docs/Web/API/HTMLImageElement/complete
pub fn complete(self: Image) bool {
    std.debug.assert(!self.handle.isNull());
    return self.handle.get("complete", bool);
}

/// Sets the CORS mode (`anonymous`, `"use-credentials"`, or `null`).
/// https://developer.mozilla.org/en-US/docs/Web/API/HTMLImageElement/crossOrigin
pub fn setCrossOrigin(self: Image, mode: ?CrossOrigin) void {
    std.debug.assert(!self.handle.isNull());
    if (mode) |m| {
        switch (m) {
            .anonymous => self.handle.set(
                "crossOrigin",
                zjb.constString("anonymous"),
            ),
            .@"use-credentials" => self.handle.set(
                "crossOrigin",
                zjb.constString("use-credentials"),
            ),
        }
    } else {
        self.handle.set("crossOrigin", zjb.Handle.null);
    }
}

/// Sets the decoding hint (`sync`, `async`, or `auto`).
/// https://developer.mozilla.org/en-US/docs/Web/API/HTMLImageElement/decoding
pub fn setDecoding(self: Image, mode: Decoding) void {
    std.debug.assert(!self.handle.isNull());
    switch (mode) {
        .sync => self.handle.set("decoding", zjb.constString("sync")),
        .async => self.handle.set("decoding", zjb.constString("async")),
        .auto => self.handle.set("decoding", zjb.constString("auto")),
    }
}

/// Asynchronously decodes the image so it is safe to draw or upload immediately.
/// Caller must `.release()` the returned `Promise`.
/// https://developer.mozilla.org/en-US/docs/Web/API/HTMLImageElement/decode
pub fn decode(self: Image) Promise.Typed(void) {
    std.debug.assert(!self.handle.isNull());
    return .fromHandle(self.handle.call("decode", .{}, zjb.Handle));
}

/// Attaches a typed event listener (e.g. `"load"`, `"error"`).
pub fn addEventListener(
    self: Image,
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

// 8. Extra classes

/// CORS mode values accepted by `HTMLImageElement.crossOrigin`.
pub const CrossOrigin = enum {
    anonymous,
    @"use-credentials",
};

/// Image decoding hint values accepted by `HTMLImageElement.decoding`.
pub const Decoding = enum {
    sync,
    async,
    auto,
};
