//! Type-safe wrapper for the browser `Blob` Web API.
//! https://developer.mozilla.org/en-US/docs/Web/API/Blob

// 1. Imports
const std = @import("std");
const webapi = @import("webapi.zig");

// 2. Shortcuts on imports
const Blob = @This();
const zjb = webapi.zjb;

// 3. File-level struct members
handle: zjb.Handle,
pub const @"null": Blob = .{ .handle = .null };

// 7. Public functions
/// Returns true if `Blob` is available in the current global scope.
pub fn isSupported() bool {
    const cls = zjb.ConstHandle.global.get("Blob", zjb.Handle);
    defer cls.release();
    return !cls.isNull();
}

/// Constructs a `Blob` from a JS array handle of parts and optional `Options`.
/// https://developer.mozilla.org/en-US/docs/Web/API/Blob/Blob
pub fn init(parts: zjb.Handle, options: ?Options) Blob {
    std.debug.assert(!parts.isNull());
    std.debug.assert(@backingInt(parts) != 0);

    const ctor = zjb.global("Blob");
    if (options) |opt| {
        const opts_h = opt.toHandle();
        defer opts_h.release();
        return fromHandle(ctor.new(.{ parts, opts_h }));
    }
    return fromHandle(ctor.new(.{parts}));
}

/// Constructs a `Blob` copying `data` bytes with optional `Options`.
/// https://developer.mozilla.org/en-US/docs/Web/API/Blob/Blob
pub fn fromBytes(data: []const u8, options: ?Options) Blob {
    std.debug.assert(@intFromPtr(data.ptr) != 0 or data.len == 0);
    std.debug.assert(data.len <= 1024 * 1024 * 512);

    const bytes_view = zjb.u8ArrayView(data);
    defer bytes_view.release();

    const parts = zjb.global("Array").new(.{bytes_view});
    defer parts.release();
    return init(parts, options);
}

/// Constructs a `Blob` from UTF-8 `data` with optional `Options`.
/// https://developer.mozilla.org/en-US/docs/Web/API/Blob/Blob
pub fn fromText(data: []const u8, options: ?Options) Blob {
    std.debug.assert(@intFromPtr(data.ptr) != 0 or data.len == 0);
    std.debug.assert(data.len <= 1024 * 1024 * 512);

    const text_s = zjb.string(data);
    defer text_s.release();

    const parts = zjb.global("Array").new(.{text_s});
    defer parts.release();
    return init(parts, options);
}

/// Wraps a non-null JS `Blob` handle.
pub fn fromHandle(handle: zjb.Handle) Blob {
    std.debug.assert(!handle.isNull());
    std.debug.assert(@backingInt(handle) != 0);
    return .{ .handle = handle };
}

/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: Blob) bool {
    return self.handle.isNull();
}

/// Releases the underlying JS handle.
pub fn release(self: Blob) void {
    self.handle.release();
}

/// Returns the size of the `Blob` data in bytes.
/// https://developer.mozilla.org/en-US/docs/Web/API/Blob/size
pub fn size(self: Blob) u64 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const raw = self.handle.get("size", f64);
    if (raw > 0.0 and raw < 1.8e19) {
        return @intFromFloat(raw);
    }
    return 0;
}

/// Copies the MIME type string (`blob.type`) into `buf`.
/// https://developer.mozilla.org/en-US/docs/Web/API/Blob/type
pub fn mimeType(self: Blob, buf: []u8) []u8 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(buf.len > 0);
    const type_h = self.handle.get("type", zjb.Handle);
    defer type_h.release();
    if (type_h.isNull()) return "";
    return webapi.stringFromHandle(type_h, buf);
}

/// Creates a new `Blob` containing the data in `[start, end)` of this blob.
/// https://developer.mozilla.org/en-US/docs/Web/API/Blob/slice
pub fn slice(
    self: Blob,
    start: ?i64,
    end: ?i64,
    content_type: ?[]const u8,
) Blob {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);

    if (content_type) |ct| {
        const ct_s = zjb.string(ct);
        defer ct_s.release();
        const start_f: f64 = @floatFromInt(start orelse 0);
        const end_f: f64 = if (end) |e|
            @floatFromInt(e)
        else
            @floatFromInt(self.size());
        return fromHandle(self.handle.call(
            "slice",
            .{ start_f, end_f, ct_s },
            zjb.Handle,
        ));
    }
    if (end) |e| {
        const start_f: f64 = @floatFromInt(start orelse 0);
        const end_f: f64 = @floatFromInt(e);
        return fromHandle(self.handle.call(
            "slice",
            .{ start_f, end_f },
            zjb.Handle,
        ));
    }
    if (start) |s| {
        const start_f: f64 = @floatFromInt(s);
        return fromHandle(self.handle.call("slice", .{start_f}, zjb.Handle));
    }
    return fromHandle(self.handle.call("slice", .{}, zjb.Handle));
}

/// Reads the `Blob` contents as a UTF-8 string into a `Promise`.
/// https://developer.mozilla.org/en-US/docs/Web/API/Blob/text
pub fn text(self: Blob) webapi.Promise {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const p = self.handle.call("text", .{}, zjb.Handle);
    std.debug.assert(!p.isNull());
    return .fromHandle(p);
}

/// Reads the `Blob` contents as an `ArrayBuffer` into a `Promise`.
/// https://developer.mozilla.org/en-US/docs/Web/API/Blob/arrayBuffer
pub fn arrayBuffer(self: Blob) webapi.Promise {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const p = self.handle.call("arrayBuffer", .{}, zjb.Handle);
    std.debug.assert(!p.isNull());
    return .fromHandle(p);
}

/// Reads the `Blob` contents as a `Uint8Array` into a `Promise`.
/// https://developer.mozilla.org/en-US/docs/Web/API/Blob/bytes
pub fn bytes(self: Blob) webapi.Promise {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const p = self.handle.call("bytes", .{}, zjb.Handle);
    std.debug.assert(!p.isNull());
    return .fromHandle(p);
}

/// Returns an owned JS handle to a `ReadableStream` for the `Blob` contents.
/// https://developer.mozilla.org/en-US/docs/Web/API/Blob/stream
pub fn stream(self: Blob) zjb.Handle {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return self.handle.call("stream", .{}, zjb.Handle);
}

// 8. Extra classes and constants

/// Line-ending conversion mode for `Blob` construction.
pub const Endings = enum {
    transparent,
    native,
};

/// Options object passed to `Blob.init`, `Blob.fromBytes`, and `Blob.fromText`.
pub const Options = struct {
    type: ?[]const u8 = null,
    endings: ?Endings = null,

    /// Converts these options into a JavaScript `BlobPropertyBag` object handle.
    pub fn toHandle(self: Options) zjb.Handle {
        const obj = zjb.global("Object").new(.{});
        std.debug.assert(!obj.isNull());
        std.debug.assert(@backingInt(obj) != 0);

        if (self.type) |mime| {
            const mime_s = zjb.string(mime);
            defer mime_s.release();
            obj.set("type", mime_s);
        }
        if (self.endings) |endings| {
            obj.set("endings", webapi.constTagName(endings));
        }
        return obj;
    }
};
