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

/// Draws a filled rectangle at `(x, y)` with dimensions `(w, h)`.
/// https://developer.mozilla.org/en-US/docs/Web/API/CanvasRenderingContext2D/fillRect
pub fn fillRect(
    self: CanvasRenderingContext2D,
    x: f64,
    y: f64,
    w: f64,
    h: f64,
) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(std.math.isFinite(x) and std.math.isFinite(y));
    std.debug.assert(std.math.isFinite(w) and std.math.isFinite(h));
    self.handle.call("fillRect", .{ x, y, w, h }, void);
}

/// Outlines a rectangle at `(x, y)` with dimensions `(w, h)`.
/// https://developer.mozilla.org/en-US/docs/Web/API/CanvasRenderingContext2D/strokeRect
pub fn strokeRect(
    self: CanvasRenderingContext2D,
    x: f64,
    y: f64,
    w: f64,
    h: f64,
) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(std.math.isFinite(x) and std.math.isFinite(y));
    std.debug.assert(std.math.isFinite(w) and std.math.isFinite(h));
    self.handle.call("strokeRect", .{ x, y, w, h }, void);
}

/// Saves the current drawing state onto the context state stack.
/// https://developer.mozilla.org/en-US/docs/Web/API/CanvasRenderingContext2D/save
pub fn save(self: CanvasRenderingContext2D) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    self.handle.call("save", .{}, void);
}

/// Restores the most recently saved drawing state from the state stack.
/// https://developer.mozilla.org/en-US/docs/Web/API/CanvasRenderingContext2D/restore
pub fn restore(self: CanvasRenderingContext2D) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    self.handle.call("restore", .{}, void);
}

/// Sets the CSS color string used to fill shapes and text (`fillStyle`).
/// https://developer.mozilla.org/en-US/docs/Web/API/CanvasRenderingContext2D/fillStyle
pub fn setFillStyle(self: CanvasRenderingContext2D, style: []const u8) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(style.len > 0);
    const s = zjb.string(style);
    defer s.release();
    self.handle.set("fillStyle", s);
}

/// Sets the CSS color string used to stroke shapes and text (`strokeStyle`).
/// https://developer.mozilla.org/en-US/docs/Web/API/CanvasRenderingContext2D/strokeStyle
pub fn setStrokeStyle(self: CanvasRenderingContext2D, style: []const u8) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(style.len > 0);
    const s = zjb.string(style);
    defer s.release();
    self.handle.set("strokeStyle", s);
}

/// Sets the stroke thickness in coordinate space units (`lineWidth`).
/// https://developer.mozilla.org/en-US/docs/Web/API/CanvasRenderingContext2D/lineWidth
pub fn setLineWidth(self: CanvasRenderingContext2D, width: f64) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(std.math.isFinite(width) and width > 0.0);
    self.handle.set("lineWidth", width);
}

/// Sets the CSS font specification string used when drawing text (`font`).
/// https://developer.mozilla.org/en-US/docs/Web/API/CanvasRenderingContext2D/font
pub fn setFont(self: CanvasRenderingContext2D, font: []const u8) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(font.len > 0);
    const s = zjb.string(font);
    defer s.release();
    self.handle.set("font", s);
}

/// Copies the current CSS `font` string into `buf`.
/// https://developer.mozilla.org/en-US/docs/Web/API/CanvasRenderingContext2D/font
pub fn getFont(self: CanvasRenderingContext2D, buf: []u8) []u8 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(buf.len > 0);
    const h = self.handle.get("font", zjb.Handle);
    defer h.release();
    if (h.isNull()) return "";
    return webapi.stringFromHandle(h, buf);
}

/// Sets the horizontal alignment used when drawing text (`textAlign`).
/// https://developer.mozilla.org/en-US/docs/Web/API/CanvasRenderingContext2D/textAlign
pub fn setTextAlign(
    self: CanvasRenderingContext2D,
    text_align: TextAlign,
) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    self.handle.set("textAlign", webapi.constTagName(text_align));
}

/// Sets the vertical text baseline used when drawing text (`textBaseline`).
/// https://developer.mozilla.org/en-US/docs/Web/API/CanvasRenderingContext2D/textBaseline
pub fn setTextBaseline(
    self: CanvasRenderingContext2D,
    baseline: TextBaseline,
) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    self.handle.set("textBaseline", webapi.constTagName(baseline));
}

/// Sets the text direction used when drawing text (`direction`).
/// https://developer.mozilla.org/en-US/docs/Web/API/CanvasRenderingContext2D/direction
pub fn setDirection(
    self: CanvasRenderingContext2D,
    dir: TextDirection,
) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    self.handle.set("direction", webapi.constTagName(dir));
}

/// Draws filled `text` at `(x, y)` using the current font and fill style.
/// https://developer.mozilla.org/en-US/docs/Web/API/CanvasRenderingContext2D/fillText
pub fn fillText(
    self: CanvasRenderingContext2D,
    text: []const u8,
    x: f64,
    y: f64,
) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(std.math.isFinite(x) and std.math.isFinite(y));
    const s = zjb.string(text);
    defer s.release();
    self.handle.call("fillText", .{ s, x, y }, void);
}

/// Draws filled `text` at `(x, y)`, scaling horizontally to fit `max_width`.
/// https://developer.mozilla.org/en-US/docs/Web/API/CanvasRenderingContext2D/fillText
pub fn fillTextMaxWidth(
    self: CanvasRenderingContext2D,
    text: []const u8,
    x: f64,
    y: f64,
    max_width: f64,
) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(std.math.isFinite(x) and std.math.isFinite(y));
    std.debug.assert(std.math.isFinite(max_width) and max_width >= 0.0);
    const s = zjb.string(text);
    defer s.release();
    self.handle.call("fillText", .{ s, x, y, max_width }, void);
}

/// Draws stroked `text` outlines at `(x, y)` using the current stroke style.
/// https://developer.mozilla.org/en-US/docs/Web/API/CanvasRenderingContext2D/strokeText
pub fn strokeText(
    self: CanvasRenderingContext2D,
    text: []const u8,
    x: f64,
    y: f64,
) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(std.math.isFinite(x) and std.math.isFinite(y));
    const s = zjb.string(text);
    defer s.release();
    self.handle.call("strokeText", .{ s, x, y }, void);
}

/// Draws stroked `text` at `(x, y)`, scaling horizontally to fit `max_width`.
/// https://developer.mozilla.org/en-US/docs/Web/API/CanvasRenderingContext2D/strokeText
pub fn strokeTextMaxWidth(
    self: CanvasRenderingContext2D,
    text: []const u8,
    x: f64,
    y: f64,
    max_width: f64,
) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(std.math.isFinite(x) and std.math.isFinite(y));
    std.debug.assert(std.math.isFinite(max_width) and max_width >= 0.0);
    const s = zjb.string(text);
    defer s.release();
    self.handle.call("strokeText", .{ s, x, y, max_width }, void);
}

/// Measures `text` using the current font and returns a `TextMetrics` wrapper.
/// Caller owns the returned handle and must call `.release()`.
/// https://developer.mozilla.org/en-US/docs/Web/API/CanvasRenderingContext2D/measureText
pub fn measureText(
    self: CanvasRenderingContext2D,
    text: []const u8,
) TextMetrics {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const s = zjb.string(text);
    defer s.release();
    const h = self.handle.call("measureText", .{s}, zjb.Handle);
    return TextMetrics.fromHandle(h);
}

// 8. Extra classes
/// Horizontal alignment values accepted by `CanvasRenderingContext2D.textAlign`.
/// https://developer.mozilla.org/en-US/docs/Web/API/CanvasRenderingContext2D/textAlign
pub const TextAlign = enum {
    left,
    right,
    center,
    start,
    end,
};

/// Vertical baseline values accepted by `CanvasRenderingContext2D.textBaseline`.
/// https://developer.mozilla.org/en-US/docs/Web/API/CanvasRenderingContext2D/textBaseline
pub const TextBaseline = enum {
    top,
    hanging,
    middle,
    alphabetic,
    ideographic,
    bottom,
};

/// Text direction values accepted by `CanvasRenderingContext2D.direction`.
/// https://developer.mozilla.org/en-US/docs/Web/API/CanvasRenderingContext2D/direction
pub const TextDirection = enum {
    ltr,
    rtl,
    inherit,
};

/// Dimensions of a text run returned by `CanvasRenderingContext2D.measureText`.
/// Caller owns the underlying JS handle and must call `.release()`.
/// https://developer.mozilla.org/en-US/docs/Web/API/TextMetrics
pub const TextMetrics = struct {
    handle: zjb.Handle,
    pub const @"null": TextMetrics = .{ .handle = .null };

    /// Wraps a non-null JS `TextMetrics` handle.
    pub fn fromHandle(handle: zjb.Handle) TextMetrics {
        std.debug.assert(!handle.isNull());
        std.debug.assert(@backingInt(handle) != 0);
        return .{ .handle = handle };
    }

    /// Returns `true` if the underlying JS handle is null or undefined.
    pub fn isNull(self: TextMetrics) bool {
        return self.handle.isNull();
    }

    /// Releases the underlying JS handle.
    pub fn release(self: TextMetrics) void {
        self.handle.release();
    }

    /// Returns the advance width of the measured text in CSS pixels.
    pub fn width(self: TextMetrics) f64 {
        std.debug.assert(!self.handle.isNull());
        std.debug.assert(@backingInt(self.handle) != 0);
        return self.handle.get("width", f64);
    }

    /// Distance from the alignment point to the left bounding box edge.
    pub fn actualBoundingBoxLeft(self: TextMetrics) f64 {
        std.debug.assert(!self.handle.isNull());
        std.debug.assert(@backingInt(self.handle) != 0);
        return self.handle.get("actualBoundingBoxLeft", f64);
    }

    /// Distance from the alignment point to the right bounding box edge.
    pub fn actualBoundingBoxRight(self: TextMetrics) f64 {
        std.debug.assert(!self.handle.isNull());
        std.debug.assert(@backingInt(self.handle) != 0);
        return self.handle.get("actualBoundingBoxRight", f64);
    }

    /// Distance from the baseline to the top bounding box edge.
    pub fn actualBoundingBoxAscent(self: TextMetrics) f64 {
        std.debug.assert(!self.handle.isNull());
        std.debug.assert(@backingInt(self.handle) != 0);
        return self.handle.get("actualBoundingBoxAscent", f64);
    }

    /// Distance from the baseline to the bottom bounding box edge.
    pub fn actualBoundingBoxDescent(self: TextMetrics) f64 {
        std.debug.assert(!self.handle.isNull());
        std.debug.assert(@backingInt(self.handle) != 0);
        return self.handle.get("actualBoundingBoxDescent", f64);
    }
};

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
