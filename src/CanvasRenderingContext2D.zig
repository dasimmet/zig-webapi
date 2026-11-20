//! Type-safe wrapper for the HTML5 2D canvas rendering context (`CanvasRenderingContext2D`).
//! https://developer.mozilla.org/en-US/docs/Web/API/CanvasRenderingContext2D

// 1. Imports
const std = @import("std");
const webapi = @import("webapi.zig");

// 2. Shortcuts on imports
const CanvasRenderingContext2D = @This();
const Element = webapi.dom.Element;
const zjb = webapi.zjb;

// 3. File-level struct members
handle: zjb.Handle,
pub const @"null": CanvasRenderingContext2D = .{ .handle = .null };

// 5. init
/// Acquires a `"2d"` rendering context from a `<canvas>` DOM `Element`.
/// Returns `error.Canvas2DNotSupported` if unavailable.
/// Caller owns the returned handle and must call `.release()`.
/// https://developer.mozilla.org/en-US/docs/Web/API/HTMLCanvasElement/getContext
pub fn fromCanvas(canvas: Element) !CanvasRenderingContext2D {
    std.debug.assert(!canvas.isNull());
    const ctx_h = canvas.handle.call(
        "getContext",
        .{zjb.constString("2d")},
        zjb.Handle,
    );
    if (ctx_h.isNull()) {
        return error.Canvas2DNotSupported;
    }
    return fromHandle(ctx_h);
}

// 7. Public functions
/// Wraps a non-null JS `CanvasRenderingContext2D` handle.
pub fn fromHandle(handle: zjb.Handle) CanvasRenderingContext2D {
    std.debug.assert(!handle.isNull());
    std.debug.assert(@backingInt(handle) != 0);
    return .{ .handle = handle };
}

/// Returns `true` if the underlying JS handle is null or undefined.
pub fn isNull(self: CanvasRenderingContext2D) bool {
    return self.handle.isNull();
}

/// Releases the underlying JS handle.
pub fn release(self: CanvasRenderingContext2D) void {
    self.handle.release();
}

/// Draws `source` (`webapi.Image`, `dom.Element`, or `zjb.Handle`) onto the
/// canvas at destination coordinates `(dx, dy)`.
/// https://developer.mozilla.org/en-US/docs/Web/API/CanvasRenderingContext2D/drawImage
pub fn drawImage(
    self: CanvasRenderingContext2D,
    source: anytype,
    dx: f64,
    dy: f64,
) void {
    std.debug.assert(!self.handle.isNull());
    const src_h = handleOf(source);
    self.handle.call("drawImage", .{ src_h, dx, dy }, void);
}

/// Draws `source` scaled into the destination rectangle `(dx, dy, dw, dh)`.
/// https://developer.mozilla.org/en-US/docs/Web/API/CanvasRenderingContext2D/drawImage
pub fn drawImageScaled(
    self: CanvasRenderingContext2D,
    source: anytype,
    dx: f64,
    dy: f64,
    dw: f64,
    dh: f64,
) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(dw >= 0.0 and dh >= 0.0);
    const src_h = handleOf(source);
    self.handle.call("drawImage", .{ src_h, dx, dy, dw, dh }, void);
}

/// Draws source sub-rectangle `(sx, sy, sw, sh)` of `source` into
/// destination rectangle `(dx, dy, dw, dh)`.
/// https://developer.mozilla.org/en-US/docs/Web/API/CanvasRenderingContext2D/drawImage
pub fn drawImageRect(
    self: CanvasRenderingContext2D,
    source: anytype,
    sx: f64,
    sy: f64,
    sw: f64,
    sh: f64,
    dx: f64,
    dy: f64,
    dw: f64,
    dh: f64,
) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(sw >= 0.0 and sh >= 0.0);
    std.debug.assert(dw >= 0.0 and dh >= 0.0);
    const src_h = handleOf(source);
    self.handle.call(
        "drawImage",
        .{ src_h, sx, sy, sw, sh, dx, dy, dw, dh },
        void,
    );
}

/// Clears the pixels in the specified rectangle to transparent black.
/// https://developer.mozilla.org/en-US/docs/Web/API/CanvasRenderingContext2D/clearRect
pub fn clearRect(
    self: CanvasRenderingContext2D,
    x: f64,
    y: f64,
    w: f64,
    h: f64,
) void {
    std.debug.assert(!self.handle.isNull());
    self.handle.call("clearRect", .{ x, y, w, h }, void);
}

// 8. Extra classes

// 9. Private helper functions
fn handleOf(source: anytype) zjb.Handle {
    const T = @TypeOf(source);
    if (T == zjb.Handle) {
        std.debug.assert(!source.isNull());
        return source;
    }
    if (@hasField(T, "handle")) {
        std.debug.assert(!source.handle.isNull());
        return source.handle;
    }
    @compileError("expected zjb.Handle or wrapper struct with .handle field");
}
