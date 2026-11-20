//! Type-safe wrapper for the Compression Streams API `DecompressionStream`
//! along with `ReadableStream`, `WritableStream`, and
//! `WritableStreamDefaultWriter`.
//! https://developer.mozilla.org/en-US/docs/Web/API/DecompressionStream

const std = @import("std");
const webapi = @import("webapi.zig");
const zjb = webapi.zjb;

const DecompressionStream = @This();

/// Underlying JavaScript `DecompressionStream` handle.
handle: zjb.Handle,
pub const @"null": DecompressionStream = .{ .handle = .null };

/// Compression algorithm formats supported by `DecompressionStream`.
/// https://developer.mozilla.org/en-US/docs/Web/API/DecompressionStream/DecompressionStream
pub const CompressionFormat = enum {
    brotli,
    gzip,
    deflate,
    @"deflate-raw",
    zstd,
};

/// Wrapper around a JavaScript `ReadableStream` instance.
/// https://developer.mozilla.org/en-US/docs/Web/API/ReadableStream
pub const ReadableStream = struct {
    handle: zjb.Handle,
    pub const @"null": ReadableStream = .{ .handle = .null };

    /// Wraps an existing non-null JavaScript `ReadableStream` handle.
    pub fn fromHandle(handle: zjb.Handle) ReadableStream {
        std.debug.assert(!handle.isNull());
        std.debug.assert(@backingInt(handle) != 0);
        return .{ .handle = handle };
    }

    /// Returns `true` if the underlying JS handle is null or undefined.
    pub fn isNull(self: ReadableStream) bool {
        return self.handle.isNull();
    }

    /// Releases the underlying JavaScript `ReadableStream` handle.
    pub fn release(self: ReadableStream) void {
        self.handle.release();
    }

    /// Returns whether the stream is currently locked to a reader.
    /// https://developer.mozilla.org/en-US/docs/Web/API/ReadableStream/locked
    pub fn locked(self: ReadableStream) bool {
        std.debug.assert(!self.handle.isNull());
        return self.handle.get("locked", bool);
    }

    /// Cancels the stream, returning a `Promise` that resolves when done.
    /// https://developer.mozilla.org/en-US/docs/Web/API/ReadableStream/cancel
    pub fn cancel(self: ReadableStream) webapi.Promise {
        std.debug.assert(!self.handle.isNull());
        const p = self.handle.call("cancel", .{}, zjb.Handle);
        std.debug.assert(!p.isNull());
        return .fromHandle(p);
    }

    /// Wraps this `ReadableStream` in a `Fetch.Response` (`new Response(stream)`)
    /// so its contents can be consumed via `.text()`, `.arrayBuffer()`, etc.
    pub fn toResponse(self: ReadableStream) webapi.Fetch.Response {
        std.debug.assert(!self.handle.isNull());
        std.debug.assert(@backingInt(self.handle) != 0);
        const resp = zjb.global("Response").new(.{self.handle});
        std.debug.assert(!resp.isNull());
        return .fromHandle(resp);
    }
};

/// Wrapper around a JavaScript `WritableStreamDefaultWriter` instance.
/// https://developer.mozilla.org/en-US/docs/Web/API/WritableStreamDefaultWriter
pub const WritableStreamDefaultWriter = struct {
    handle: zjb.Handle,
    pub const @"null": WritableStreamDefaultWriter = .{ .handle = .null };

    /// Wraps an existing non-null `WritableStreamDefaultWriter` handle.
    pub fn fromHandle(handle: zjb.Handle) WritableStreamDefaultWriter {
        std.debug.assert(!handle.isNull());
        std.debug.assert(@backingInt(handle) != 0);
        return .{ .handle = handle };
    }

    /// Returns `true` if the underlying JS handle is null or undefined.
    pub fn isNull(self: WritableStreamDefaultWriter) bool {
        return self.handle.isNull();
    }

    /// Releases the underlying JavaScript handle.
    pub fn release(self: WritableStreamDefaultWriter) void {
        self.handle.release();
    }

    /// Writes a chunk (e.g. `Uint8Array`) to the stream.
    /// https://developer.mozilla.org/en-US/docs/Web/API/WritableStreamDefaultWriter/write
    pub fn write(self: WritableStreamDefaultWriter, chunk: zjb.Handle) webapi.Promise {
        std.debug.assert(!self.handle.isNull());
        std.debug.assert(!chunk.isNull());
        const p = self.handle.call("write", .{chunk}, zjb.Handle);
        std.debug.assert(!p.isNull());
        return .fromHandle(p);
    }

    /// Copies `bytes` into a standalone `Uint8Array` and writes it to the stream.
    /// https://developer.mozilla.org/en-US/docs/Web/API/WritableStreamDefaultWriter/write
    pub fn writeBytes(self: WritableStreamDefaultWriter, bytes: []const u8) webapi.Promise {
        std.debug.assert(!self.handle.isNull());
        const view = zjb.u8ArrayView(bytes);
        defer view.release();
        const copy = zjb.global("Uint8Array").new(.{view});
        defer copy.release();
        return self.write(copy);
    }

    /// Closes the associated writable stream.
    /// https://developer.mozilla.org/en-US/docs/Web/API/WritableStreamDefaultWriter/close
    pub fn close(self: WritableStreamDefaultWriter) webapi.Promise {
        std.debug.assert(!self.handle.isNull());
        const p = self.handle.call("close", .{}, zjb.Handle);
        std.debug.assert(!p.isNull());
        return .fromHandle(p);
    }

    /// Releases the writer's lock on the corresponding stream.
    /// https://developer.mozilla.org/en-US/docs/Web/API/WritableStreamDefaultWriter/releaseLock
    pub fn releaseLock(self: WritableStreamDefaultWriter) void {
        std.debug.assert(!self.handle.isNull());
        self.handle.call("releaseLock", .{}, void);
    }
};

/// Wrapper around a JavaScript `WritableStream` instance.
/// https://developer.mozilla.org/en-US/docs/Web/API/WritableStream
pub const WritableStream = struct {
    handle: zjb.Handle,
    pub const @"null": WritableStream = .{ .handle = .null };

    /// Wraps an existing non-null JavaScript `WritableStream` handle.
    pub fn fromHandle(handle: zjb.Handle) WritableStream {
        std.debug.assert(!handle.isNull());
        std.debug.assert(@backingInt(handle) != 0);
        return .{ .handle = handle };
    }

    /// Returns `true` if the underlying JS handle is null or undefined.
    pub fn isNull(self: WritableStream) bool {
        return self.handle.isNull();
    }

    /// Releases the underlying JavaScript `WritableStream` handle.
    pub fn release(self: WritableStream) void {
        self.handle.release();
    }

    /// Returns whether the stream is currently locked to a writer.
    /// https://developer.mozilla.org/en-US/docs/Web/API/WritableStream/locked
    pub fn locked(self: WritableStream) bool {
        std.debug.assert(!self.handle.isNull());
        return self.handle.get("locked", bool);
    }

    /// Acquires a `WritableStreamDefaultWriter` locked to this stream.
    /// https://developer.mozilla.org/en-US/docs/Web/API/WritableStream/getWriter
    pub fn getWriter(self: WritableStream) WritableStreamDefaultWriter {
        std.debug.assert(!self.handle.isNull());
        const w = self.handle.call("getWriter", .{}, zjb.Handle);
        std.debug.assert(!w.isNull());
        return .fromHandle(w);
    }

    /// Closes the stream, returning a `Promise` that resolves when flushed.
    /// https://developer.mozilla.org/en-US/docs/Web/API/WritableStream/close
    pub fn close(self: WritableStream) webapi.Promise {
        std.debug.assert(!self.handle.isNull());
        const p = self.handle.call("close", .{}, zjb.Handle);
        std.debug.assert(!p.isNull());
        return .fromHandle(p);
    }
};

/// Creates a new `DecompressionStream` for the given `CompressionFormat`.
/// https://developer.mozilla.org/en-US/docs/Web/API/DecompressionStream/DecompressionStream
pub fn init(format: CompressionFormat) DecompressionStream {
    const h = zjb.global("DecompressionStream").new(.{
        webapi.constTagName(format),
    });
    std.debug.assert(!h.isNull());
    std.debug.assert(@backingInt(h) != 0);
    return .fromHandle(h);
}

/// Wraps an existing non-null JavaScript `DecompressionStream` handle.
pub fn fromHandle(handle: zjb.Handle) DecompressionStream {
    std.debug.assert(!handle.isNull());
    std.debug.assert(@backingInt(handle) != 0);
    return .{ .handle = handle };
}

/// Returns `true` if the underlying JS handle is null or undefined.
pub fn isNull(self: DecompressionStream) bool {
    return self.handle.isNull();
}

/// Releases the underlying JavaScript `DecompressionStream` handle.
pub fn release(self: DecompressionStream) void {
    self.handle.release();
}

/// Returns the `ReadableStream` emitting decompressed output chunks.
/// https://developer.mozilla.org/en-US/docs/Web/API/DecompressionStream/readable
pub fn readable(self: DecompressionStream) ReadableStream {
    std.debug.assert(!self.handle.isNull());
    const r = self.handle.get("readable", zjb.Handle);
    std.debug.assert(!r.isNull());
    return .fromHandle(r);
}

/// Returns the `WritableStream` accepting compressed input chunks.
/// https://developer.mozilla.org/en-US/docs/Web/API/DecompressionStream/writable
pub fn writable(self: DecompressionStream) WritableStream {
    std.debug.assert(!self.handle.isNull());
    const w = self.handle.get("writable", zjb.Handle);
    std.debug.assert(!w.isNull());
    return .fromHandle(w);
}

/// Decompresses `bytes` using `format` and returns a `Fetch.Response`
/// whose `.text()` or `.arrayBuffer()` Promise yields the decoded payload.
pub fn decompress(
    format: CompressionFormat,
    bytes: []const u8,
) webapi.Fetch.Response {
    return transformBytes("DecompressionStream", format, bytes);
}

/// Decompresses a JS buffer/TypedArray handle using `format` and returns a
/// `Fetch.Response` whose `.text()` or `.arrayBuffer()` Promise yields the
/// decoded payload.
pub fn decompressHandle(
    format: CompressionFormat,
    bytes_handle: zjb.Handle,
) webapi.Fetch.Response {
    return transformHandle("DecompressionStream", format, bytes_handle);
}

/// Shared helper for `CompressionStream` and `DecompressionStream` to pipe
/// `bytes` through a transform stream and wrap its readable side in a Response.
pub fn transformBytes(
    comptime ctor_name: []const u8,
    format: CompressionFormat,
    bytes: []const u8,
) webapi.Fetch.Response {
    const view = zjb.u8ArrayView(bytes);
    defer view.release();
    const copy = zjb.global("Uint8Array").new(.{view});
    defer copy.release();
    return transformHandle(ctor_name, format, copy);
}

/// Shared helper for `CompressionStream` and `DecompressionStream` to pipe
/// a JS buffer/TypedArray handle through a transform stream and wrap its
/// readable side in a `Fetch.Response`.
pub fn transformHandle(
    comptime ctor_name: []const u8,
    format: CompressionFormat,
    bytes_handle: zjb.Handle,
) webapi.Fetch.Response {
    std.debug.assert(!bytes_handle.isNull());
    std.debug.assert(@backingInt(bytes_handle) != 0);

    const stream = zjb.global(ctor_name).new(.{
        webapi.constTagName(format),
    });
    std.debug.assert(!stream.isNull());
    defer stream.release();

    const w_h = stream.get("writable", zjb.Handle);
    std.debug.assert(!w_h.isNull());
    const w_stream = WritableStream.fromHandle(w_h);
    defer w_stream.release();

    const writer = w_stream.getWriter();
    defer writer.release();

    writer.write(bytes_handle).release();
    writer.close().release();

    const r_h = stream.get("readable", zjb.Handle);
    std.debug.assert(!r_h.isNull());
    const r_stream = ReadableStream.fromHandle(r_h);
    defer r_stream.release();
    return r_stream.toResponse();
}
