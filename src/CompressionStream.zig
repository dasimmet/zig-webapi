//! Type-safe wrapper for the Compression Streams API `CompressionStream`.
//! https://developer.mozilla.org/en-US/docs/Web/API/CompressionStream

const std = @import("std");
const webapi = @import("webapi.zig");
const DecompressionStream = @import("DecompressionStream.zig");
const zjb = webapi.zjb;

const CompressionStream = @This();

pub const CompressionFormat = DecompressionStream.CompressionFormat;
pub const ReadableStream = DecompressionStream.ReadableStream;
pub const WritableStream = DecompressionStream.WritableStream;
pub const WritableStreamDefaultWriter =
    DecompressionStream.WritableStreamDefaultWriter;

/// Underlying JavaScript `CompressionStream` handle.
handle: zjb.Handle,
pub const @"null": CompressionStream = .{ .handle = .null };

/// Creates a new `CompressionStream` for the given `CompressionFormat`.
/// https://developer.mozilla.org/en-US/docs/Web/API/CompressionStream/CompressionStream
pub fn init(format: CompressionFormat) CompressionStream {
    const h = zjb.global("CompressionStream").new(.{
        webapi.constTagName(format),
    });
    std.debug.assert(!h.isNull());
    std.debug.assert(@backingInt(h) != 0);
    return .fromHandle(h);
}

/// Wraps an existing non-null JavaScript `CompressionStream` handle.
pub fn fromHandle(handle: zjb.Handle) CompressionStream {
    std.debug.assert(!handle.isNull());
    std.debug.assert(@backingInt(handle) != 0);
    return .{ .handle = handle };
}

/// Returns `true` if the underlying JS handle is null or undefined.
pub fn isNull(self: CompressionStream) bool {
    return self.handle.isNull();
}

/// Releases the underlying JavaScript `CompressionStream` handle.
pub fn release(self: CompressionStream) void {
    self.handle.release();
}

/// Returns the `ReadableStream` emitting compressed output chunks.
/// https://developer.mozilla.org/en-US/docs/Web/API/CompressionStream/readable
pub fn readable(self: CompressionStream) ReadableStream {
    std.debug.assert(!self.handle.isNull());
    const r = self.handle.get("readable", zjb.Handle);
    std.debug.assert(!r.isNull());
    return .fromHandle(r);
}

/// Returns the `WritableStream` accepting uncompressed input chunks.
/// https://developer.mozilla.org/en-US/docs/Web/API/CompressionStream/writable
pub fn writable(self: CompressionStream) WritableStream {
    std.debug.assert(!self.handle.isNull());
    const w = self.handle.get("writable", zjb.Handle);
    std.debug.assert(!w.isNull());
    return .fromHandle(w);
}

/// Compresses `bytes` using `format` and returns a `Fetch.Response`
/// whose `.arrayBuffer()` Promise yields the compressed bytes.
pub fn compress(
    format: CompressionFormat,
    bytes: []const u8,
) webapi.Fetch.Response {
    return DecompressionStream.transformBytes("CompressionStream", format, bytes);
}

/// Compresses a JS buffer/TypedArray handle using `format` and returns a
/// `Fetch.Response` whose `.arrayBuffer()` Promise yields the compressed bytes.
pub fn compressHandle(
    format: CompressionFormat,
    bytes_handle: zjb.Handle,
) webapi.Fetch.Response {
    return DecompressionStream.transformHandle(
        "CompressionStream",
        format,
        bytes_handle,
    );
}
