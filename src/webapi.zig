//! High-performance WebAssembly JavaScript bridge utilities and zero-global
//! callback helpers.
//!
//! Provides zero-allocation string extraction, compile-time tag name
//! resolution, cryptographically secure pseudo-random number generator
//! initialization via Web Crypto, singleton TextEncoder/TextDecoder caches,
//! and context-bound callback wrappers (`boundFunction`, `boundEventListener`)
//! allowing asynchronous JavaScript callbacks and DOM event listeners to
//! dispatch directly to Zig struct pointers without global singleton
//! variables.

const std = @import("std");
const builtin = @import("builtin");
const is_wasm = builtin.target.cpu.arch.isWasm();

pub const zjb = if (is_wasm) @import("zjb") else @import("testing/zjb.zig");

const JsPtrInt = @Int(.signed, @bitSizeOf(usize));

pub const BroadcastChannel = @import("BroadcastChannel.zig");
pub const Blob = @import("Blob.zig");
const callback = @import("callback.zig");
pub const codec = @import("codec.zig");
pub const CompressionStream = @import("CompressionStream.zig");
pub const console = @import("console.zig");
pub const Crypto = @import("Crypto.zig");
pub const DecompressionStream = @import("DecompressionStream.zig");
pub const dom = @import("dom.zig");
pub const download = @import("download.zig");
pub const Event = @import("Event.zig");
pub const Fetch = @import("Fetch.zig");
pub const IndexedDb = @import("IndexedDb.zig");
pub const Promise = @import("Promise.zig");
pub const testing = @import("testing.zig");
pub const URL = @import("URL.zig");
pub const Wasi = @import("Wasi.zig");
pub const WebAssembly = @import("WebAssembly.zig");
pub const WebGL = @import("WebGL.zig");
pub const WebRTC = @import("WebRTC.zig");
pub const WebSocket = @import("WebSocket.zig");
pub const Worker = @import("Worker.zig");

pub const fetch = Fetch.fetch;
pub const crypto = Crypto.global;

/// Retrieves cryptographically random 64-bit entropy from
/// `window.crypto.getRandomValues` and initializes a `std.Random.DefaultPrng`
/// with it.
pub fn PseudoRandomNumberGenerator() std.Random.DefaultPrng {
    var rng = std.Random.DefaultPrng.init(123456789);
    const useed = Crypto.global().random(u64);

    std.log.debug("PseudoRandomNumberGenerator() Seed: {d}", .{useed});
    rng.seed(useed);
    return rng;
}

/// Returns a compile-time `zjb.ConstHandle` representing the string name of an
/// enum value, active union tag, or error name.
pub fn constTagName(arg: anytype) zjb.ConstHandle {
    const info = @typeInfo(@TypeOf(arg));
    switch (info) {
        .@"enum" => |en| {
            inline for (en.field_names, en.field_values) |name, val| {
                const s = zjb.constString(name);
                if (@backingInt(arg) == val) return s;
            }
        },
        .@"union" => {
            return constTagName(std.meta.activeTag(arg));
        },
        .error_set => |es| {
            if (es.error_names) |names| {
                inline for (names) |name| {
                    const s = zjb.constString(name);
                    if (std.mem.eql(u8, @errorName(arg), name)) return s;
                }
            }
        },
        else => @compileError(
            "expected enum, union or error union, got: " ++ @tagName(info),
        ),
    }
    unreachable;
}

/// Retrieves the current `window.location.href` into a newly allocated UTF-8
/// slice owned by the caller.
pub fn getUri(allocator: std.mem.Allocator) ![]u8 {
    const location = zjb.global("window").get("location", zjb.Handle);
    defer location.release();

    const href = location.get("href", zjb.Handle);
    defer href.release();

    return try stringFromHandleAlloc(allocator, href);
}

/// Encodes a JavaScript string handle `h` to UTF-8 using `TextEncoder` and
/// copies the bytes directly into the caller-provided buffer `buf` without
/// heap allocations. Returns the sliced slice.
pub fn stringFromHandle(h: zjb.Handle, buf: []u8) []u8 {
    if (h.isNull()) return "";
    const encoded = codec.encode(h);
    defer encoded.release();

    const len = encoded.get("length", JsPtrInt);
    if (len <= 0) return "";
    const ulen: usize = @intCast(len);
    if (buf.len < ulen) {
        std.log.err(
            "handleToString cannot fit {d} into a buffer sized {d}",
            .{ ulen, buf.len },
        );
        @panic("handleToString buffer overflow");
    }
    const view = zjb.u8ArrayView(buf);
    defer view.release();
    view.call("set", .{encoded}, void);

    return buf[0..ulen];
}

/// Encodes a JavaScript string handle `h` to UTF-8 and allocates a fresh slice
/// sized to the exact string length using `allocator`.
pub fn stringFromHandleAlloc(
    allocator: std.mem.Allocator,
    h: zjb.Handle,
) ![]u8 {
    if (h.isNull()) return error.NullHandle;
    const encoded = codec.encode(h);
    defer encoded.release();
    const len = encoded.get("length", JsPtrInt);
    if (len <= 0) return "";
    const ulen: usize = @intCast(len);
    const buf = try allocator.alloc(u8, ulen);
    errdefer allocator.free(buf);
    return stringFromHandle(h, buf);
}

/// Concatenates multiple JavaScript string handles in `h_arr` into a single
/// caller-provided buffer `buf` without heap allocations. Returns the slice.
pub fn stringFromHandles(h_arr: []const zjb.Handle, buf: []u8) []u8 {
    var size: usize = 0;
    for (h_arr) |h| {
        const s = stringFromHandle(h, buf[size..]);
        size += s.len;
    }
    return buf[0..size];
}

/// Allocates an independent JavaScript `Uint8Array` of exact size `data.len`
/// and copies bytes into it. This detaches the stored buffer from the
/// WebAssembly linear memory buffer, preventing Structured Clone or async APIs
/// from holding views across memory growth.
pub fn createStandaloneUint8Array(data: []const u8) zjb.Handle {
    std.debug.assert(@intFromPtr(data.ptr) != 0 or data.len == 0);
    std.debug.assert(data.len <= 1024 * 1024 * 512);

    const uint8_ctor = zjb.global("Uint8Array");
    const standalone = uint8_ctor.new(.{@as(i32, @intCast(data.len))});
    std.debug.assert(!standalone.isNull());

    if (data.len > 0) {
        const view = zjb.u8ArrayView(data);
        defer view.release();
        standalone.call("set", .{view}, void);
    }
    return standalone;
}

/// Extracts raw bytes from a binary `ArrayBuffer`/`Uint8Array` or string
/// without encoding into allocated slice.
pub fn bytesFromHandleAlloc(
    allocator: std.mem.Allocator,
    data_h: zjb.Handle,
) ![]u8 {
    if (data_h.isNull()) return error.NullHandle;

    const byte_len = data_h.get("byteLength", JsPtrInt);
    if (byte_len > 0) {
        const ulen: usize = @intCast(byte_len);
        const buf = try allocator.alloc(u8, ulen);

        try bytesFromHandle(buf, data_h);
        return buf;
    }
    return try allocator.alloc(u8, 0);
}

/// Extracts raw bytes from a binary `ArrayBuffer`/`Uint8Array` or string
/// without encoding into buffer.
pub fn bytesFromHandle(
    buf: []u8,
    data_h: zjb.Handle,
) !void {
    if (buf.len == 0) return;
    const uint8_cls = zjb.global("Uint8Array");
    const src_view = uint8_cls.new(.{data_h});
    defer src_view.release();

    const dst_view = zjb.u8ArrayView(buf);
    defer dst_view.release();

    dst_view.call("set", .{src_view}, void);
}

/// Creates a JavaScript callback function bound to a specific context pointer
/// `ctx`. When called from JavaScript, the shared callback dispatcher invokes
/// an internal per-type trampoline that unpacks `ctx` and calls `f`, releasing
/// the payload handle automatically.
pub fn boundFunction(
    comptime Context: type,
    ctx: *Context,
    comptime f: *const fn (*Context, zjb.Handle) void,
) zjb.Handle {
    return callback.bindCallback(Context, false, ctx, f);
}

/// Like boundFunction but caller owns the Handle parameter.
pub fn boundFunctionOwned(
    comptime Context: type,
    ctx: *Context,
    comptime f: *const fn (*Context, zjb.Handle) void,
) zjb.Handle {
    return callback.bindCallback(Context, true, ctx, f);
}

/// Attaches a DOM event listener for `event_name` onto JS object `h`,
/// bound to context pointer `ctx`. Unpacks `ctx` and invokes `f` when
/// triggered, releasing the event handle automatically.
pub fn boundEventListener(
    Context: type,
    comptime event_name: []const u8,
    h: anytype,
    comptime f: *const fn (*Context, zjb.Handle) void,
    ctx: *Context,
) void {
    callback.attachBoundListener(Context, false, event_name, h, f, ctx);
}

/// Like boundEventListener but wraps the callback into a function converting
/// the handle to a `ReturnType`.
pub fn boundEventListenerTyped(
    Context: type,
    ReturnType: type,
    comptime event_name: []const u8,
    h: anytype,
    comptime f: *const fn (*Context, ReturnType) void,
    ctx: *Context,
) void {
    callback.attachTypedListener(
        Context,
        ReturnType,
        false,
        event_name,
        h,
        f,
        ctx,
    );
}

/// Like boundEventListener but caller owns the Handle parameter.
pub fn boundEventListenerOwned(
    Context: type,
    comptime event_name: []const u8,
    h: anytype,
    comptime f: *const fn (*Context, zjb.Handle) void,
    ctx: *Context,
) void {
    callback.attachBoundListener(Context, true, event_name, h, f, ctx);
}

/// Like `boundEventListenerTyped` but caller owns the event handle inside
/// `ReturnType` and must release it (e.g. via `ev.handle.release()`).
pub fn boundEventListenerTypedOwned(
    Context: type,
    ReturnType: type,
    comptime event_name: []const u8,
    h: anytype,
    comptime f: *const fn (*Context, ReturnType) void,
    ctx: *Context,
) void {
    callback.attachTypedListener(
        Context,
        ReturnType,
        true,
        event_name,
        h,
        f,
        ctx,
    );
}

/// Creates an independent `zjb.Handle` referencing the same JS value.
pub fn retainHandle(h: zjb.Handle) zjb.Handle {
    std.debug.assert(!h.isNull());
    std.debug.assert(@backingInt(h) != 0);

    const arr = zjb.global("Array").call("of", .{h}, zjb.Handle);
    defer arr.release();
    const dup = arr.call("pop", .{}, zjb.Handle);
    std.debug.assert(!dup.isNull());
    return dup;
}

test {
    _ = testing;
}
