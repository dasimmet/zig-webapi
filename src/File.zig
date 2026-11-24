//! Type-safe wrapper for the browser `File` Web API (`File extends Blob`).
//! https://developer.mozilla.org/en-US/docs/Web/API/File

// 1. Imports
const std = @import("std");
const webapi = @import("webapi.zig");

// 2. Shortcuts on imports
const File = @This();
const Blob = webapi.Blob;
const zjb = webapi.zjb;

// 3. File-level struct members
handle: zjb.Handle,
pub const @"null": File = .{ .handle = .null };

// 6. Types
/// Options object (`FilePropertyBag`) passed to `File` constructors.
/// https://developer.mozilla.org/en-US/docs/Web/API/File/File#options
pub const Options = struct {
    type: ?[]const u8 = null,
    endings: ?Blob.Endings = null,
    last_modified: ?i64 = null,

    /// Converts these options into a JavaScript `FilePropertyBag` object handle.
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
        if (self.last_modified) |lm| {
            obj.set("lastModified", @as(f64, @floatFromInt(lm)));
        }
        return obj;
    }
};

// 7. Public functions
/// Returns true if `File` is available in the current global scope.
pub fn isSupported() bool {
    const cls = zjb.ConstHandle.global.get("File", zjb.Handle);
    defer cls.release();
    return !cls.isNull();
}

/// Constructs a `File` from a JS array handle of parts, `file_name`, and optional `Options`.
/// https://developer.mozilla.org/en-US/docs/Web/API/File/File
pub fn init(parts: zjb.Handle, file_name: []const u8, options: ?Options) File {
    std.debug.assert(!parts.isNull());
    std.debug.assert(@backingInt(parts) != 0);
    std.debug.assert(file_name.len > 0);

    const name_s = zjb.string(file_name);
    defer name_s.release();
    const ctor = zjb.global("File");
    if (options) |opt| {
        const opts_h = opt.toHandle();
        defer opts_h.release();
        return fromHandle(ctor.new(.{ parts, name_s, opts_h }));
    }
    return fromHandle(ctor.new(.{ parts, name_s }));
}

/// Constructs a `File` copying `data` bytes with `file_name` and optional `Options`.
/// https://developer.mozilla.org/en-US/docs/Web/API/File/File
pub fn fromBytes(
    data: []const u8,
    file_name: []const u8,
    options: ?Options,
) File {
    std.debug.assert(@intFromPtr(data.ptr) != 0 or data.len == 0);
    std.debug.assert(data.len <= 1024 * 1024 * 512);

    const bytes_view = zjb.u8ArrayView(data);
    defer bytes_view.release();
    const parts = zjb.global("Array").new(.{bytes_view});
    defer parts.release();
    return init(parts, file_name, options);
}

/// Constructs a `File` from UTF-8 `data` with `file_name` and optional `Options`.
/// https://developer.mozilla.org/en-US/docs/Web/API/File/File
pub fn fromText(
    data: []const u8,
    file_name: []const u8,
    options: ?Options,
) File {
    std.debug.assert(@intFromPtr(data.ptr) != 0 or data.len == 0);
    std.debug.assert(data.len <= 1024 * 1024 * 512);

    const text_s = zjb.string(data);
    defer text_s.release();
    const parts = zjb.global("Array").new(.{text_s});
    defer parts.release();
    return init(parts, file_name, options);
}

/// Constructs a `File` wrapping an existing `Blob` with `file_name` and optional `Options`.
/// https://developer.mozilla.org/en-US/docs/Web/API/File/File
pub fn fromBlob(
    blob: Blob,
    file_name: []const u8,
    options: ?Options,
) File {
    std.debug.assert(!blob.isNull());
    const parts = zjb.global("Array").new(.{blob.handle});
    defer parts.release();
    return init(parts, file_name, options);
}

/// Wraps a non-null JS `File` handle.
pub fn fromHandle(handle: zjb.Handle) File {
    std.debug.assert(!handle.isNull());
    std.debug.assert(@backingInt(handle) != 0);
    return .{ .handle = handle };
}

/// Returns a non-owning `Blob` view over this `File` (`File extends Blob`).
pub fn asBlob(self: File) Blob {
    return Blob.fromHandle(self.handle);
}

/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: File) bool {
    return self.handle.isNull();
}

/// Releases the underlying JS handle.
pub fn release(self: File) void {
    self.handle.release();
}

/// Copies the file name (`file.name`) into `buf`.
/// https://developer.mozilla.org/en-US/docs/Web/API/File/name
pub fn name(self: File, buf: []u8) []u8 {
    return readStringProp(self.handle, "name", buf);
}

/// Copies the relative path (`file.webkitRelativePath`) into `buf`.
/// https://developer.mozilla.org/en-US/docs/Web/API/File/webkitRelativePath
pub fn webkitRelativePath(self: File, buf: []u8) []u8 {
    return readStringProp(self.handle, "webkitRelativePath", buf);
}

/// Returns the last-modified timestamp in milliseconds since the Unix epoch.
/// https://developer.mozilla.org/en-US/docs/Web/API/File/lastModified
pub fn lastModified(self: File) i64 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const raw = self.handle.get("lastModified", f64);
    return @intFromFloat(raw);
}

/// Returns the file size in bytes (`Blob.size`).
/// https://developer.mozilla.org/en-US/docs/Web/API/Blob/size
pub fn size(self: File) u64 {
    return self.asBlob().size();
}

/// Copies the MIME type string (`Blob.type`) into `buf`.
/// https://developer.mozilla.org/en-US/docs/Web/API/Blob/type
pub fn mimeType(self: File, buf: []u8) []u8 {
    return self.asBlob().mimeType(buf);
}

/// Creates a `Blob` containing the data in `[start, end)` of this file.
/// https://developer.mozilla.org/en-US/docs/Web/API/Blob/slice
pub fn slice(
    self: File,
    start: ?i64,
    end: ?i64,
    content_type: ?[]const u8,
) Blob {
    return self.asBlob().slice(start, end, content_type);
}

/// Reads the `File` contents as a UTF-8 string into a `Promise`.
/// https://developer.mozilla.org/en-US/docs/Web/API/Blob/text
pub fn text(self: File) webapi.Promise {
    return self.asBlob().text();
}

/// Reads the `File` contents as an `ArrayBuffer` into a `Promise`.
/// https://developer.mozilla.org/en-US/docs/Web/API/Blob/arrayBuffer
pub fn arrayBuffer(self: File) webapi.Promise {
    return self.asBlob().arrayBuffer();
}

/// Reads the `File` contents as a `Uint8Array` into a `Promise`.
/// https://developer.mozilla.org/en-US/docs/Web/API/Blob/bytes
pub fn bytes(self: File) webapi.Promise {
    return self.asBlob().bytes();
}

/// Returns an owned JS handle to a `ReadableStream` for the `File` contents.
/// https://developer.mozilla.org/en-US/docs/Web/API/Blob/stream
pub fn stream(self: File) zjb.Handle {
    return self.asBlob().stream();
}

// 9. Private helpers
fn readStringProp(h: zjb.Handle, comptime prop: []const u8, buf: []u8) []u8 {
    std.debug.assert(!h.isNull());
    std.debug.assert(buf.len > 0);
    const val_h = h.get(prop, zjb.Handle);
    defer val_h.release();
    if (val_h.isNull()) return "";
    return webapi.stringFromHandle(val_h, buf);
}
