//! JavaScript `Promise` wrapper with untyped and type-safe `.then()` helpers.
//! https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Promise

const std = @import("std");
const webapi = @import("webapi.zig");
const zjb = webapi.zjb;

const Promise = @This();

/// Underlying JavaScript `Promise` handle.
handle: zjb.Handle,
pub const @"null": Promise = .{ .handle = .null };

/// Options for attaching raw JS callback handles via `Promise.then`.
pub const ThenOptions = struct {
    /// JS function handle invoked when the promise fulfills (or `.null`).
    on_success: zjb.Handle,
    /// JS function handle invoked when the promise rejects (or `.null`).
    on_error: zjb.Handle,
    /// Optional JS `finally` handler passed as the third argument to `.then`.
    finally: zjb.Handle,
};

/// Wraps an existing non-null JavaScript `Promise` handle.
pub fn fromHandle(handle: zjb.Handle) Promise {
    std.debug.assert(!handle.isNull());
    std.debug.assert(@backingInt(handle) != 0);
    return .{ .handle = handle };
}

/// Creates an already-resolved `Promise` wrapping `val`.
/// https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Promise/resolve
pub fn resolve(val: anytype) Promise {
    const p = zjb.global("Promise").call("resolve", .{val}, zjb.Handle);
    std.debug.assert(!p.isNull());
    std.debug.assert(@backingInt(p) != 0);
    return fromHandle(p);
}

/// Returns `true` if the underlying JS handle is null or undefined.
pub fn isNull(self: @This()) bool {
    return self.handle.isNull();
}

/// Releases the underlying JavaScript `Promise` handle.
pub fn release(self: @This()) void {
    self.handle.release();
}

/// Attaches raw JS fulfillment/rejection handles via `.then(...)` and
/// releases the derived child `Promise` handle immediately.
/// https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Promise/then
pub fn then(
    self: @This(),
    options: ThenOptions,
) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    self.handle.call("then", .{
        options.on_success,
        options.on_error,
        options.finally,
    }, void);
}

/// Attaches Zig fulfillment and rejection callbacks bound to `ctx` via
/// `.then(ok, err)`. Payloads are released automatically after invocation.
/// https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Promise/then
pub inline fn thenFn(
    self: @This(),
    comptime Context: type,
    ctx: *Context,
    comptime on_ok: ?*const fn (*Context, zjb.Handle) void,
    comptime on_err: ?*const fn (*Context, zjb.Handle) void,
) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@intFromPtr(ctx) != 0);

    const cb_ok: zjb.Handle = if (on_ok) |ono|
        webapi.boundFunction(Context, ctx, ono)
    else
        .null;
    defer if (!cb_ok.isNull()) cb_ok.release();
    const cb_err: zjb.Handle = if (on_err) |one|
        webapi.boundFunction(Context, ctx, one)
    else
        .null;
    defer if (!cb_err.isNull()) cb_err.release();
    self.handle.call("then", .{ cb_ok, cb_err }, void);
}

/// Attaches Zig fulfillment and rejection callbacks bound to `ctx` via
/// `.then(ok, err)`. The callback owns the handle.
/// https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Promise/then
pub inline fn thenFnOwned(
    self: @This(),
    comptime Context: type,
    ctx: *Context,
    comptime on_ok: ?*const fn (*Context, zjb.Handle) void,
    comptime on_err: ?*const fn (*Context, zjb.Handle) void,
) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@intFromPtr(ctx) != 0);

    const cb_ok: zjb.Handle = if (on_ok) |ono|
        webapi.boundFunctionOwned(Context, ctx, ono)
    else
        .null;
    defer if (!cb_ok.isNull()) cb_ok.release();
    const cb_err: zjb.Handle = if (on_err) |one|
        webapi.boundFunctionOwned(Context, ctx, one)
    else
        .null;
    defer if (!cb_err.isNull()) cb_err.release();
    self.handle.call("then", .{ cb_ok, cb_err }, void);
}

/// Returns a type-safe `Promise` wrapper converting fulfilled JS handles
/// into `T` (`void`, `i32`, or a handle-backed wrapper struct).
pub fn Typed(comptime T: type) type {
    return struct {
        /// Underlying untyped `Promise` wrapper.
        promise: Promise,

        /// Callback signature expected for a fulfilled `Promise` of `T`.
        pub fn OkFn(comptime Context: type) type {
            return if (T == void)
                fn (*Context) void
            else
                fn (*Context, T) void;
        }

        /// Wraps an existing non-null JavaScript `Promise` handle.
        pub fn fromHandle(handle: zjb.Handle) @This() {
            std.debug.assert(!handle.isNull());
            std.debug.assert(@backingInt(handle) != 0);
            return .{ .promise = Promise.fromHandle(handle) };
        }

        /// Reports whether the underlying `Promise` handle is null.
        pub fn isNull(self: @This()) bool {
            std.debug.assert(@sizeOf(@This()) == @sizeOf(Promise));
            std.debug.assert(
                T == void or T == i32 or @hasField(T, "handle"),
            );
            return self.promise.isNull();
        }

        /// Attaches typed fulfillment (`on_ok`) and raw-handle rejection
        /// (`on_err`) callbacks bound to `ctx`.
        /// https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Promise/then
        pub inline fn thenFn(
            self: @This(),
            comptime Context: type,
            ctx: *Context,
            comptime on_ok: ?*const OkFn(Context),
            comptime on_err: ?*const fn (*Context, zjb.Handle) void,
        ) void {
            self.thenFnWithOwnership(Context, false, ctx, on_ok, on_err);
        }

        /// Attaches typed fulfillment (`on_ok`) and raw-handle rejection
        /// (`on_err`) callbacks bound to `ctx`. Handle-backed `T` values
        /// passed to `on_ok` and rejection handles passed to `on_err` are
        /// owned by the callback and must be released when no longer needed.
        /// https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Promise/then
        pub inline fn thenFnOwned(
            self: @This(),
            comptime Context: type,
            ctx: *Context,
            comptime on_ok: ?*const OkFn(Context),
            comptime on_err: ?*const fn (*Context, zjb.Handle) void,
        ) void {
            self.thenFnWithOwnership(Context, true, ctx, on_ok, on_err);
        }

        inline fn thenFnWithOwnership(
            self: @This(),
            comptime Context: type,
            comptime owned: bool,
            ctx: *Context,
            comptime on_ok: ?*const OkFn(Context),
            comptime on_err: ?*const fn (*Context, zjb.Handle) void,
        ) void {
            std.debug.assert(!self.promise.isNull());
            std.debug.assert(@intFromPtr(ctx) != 0);

            const TypeWrapper = struct {
                fn okWrapper(inner_ctx: *Context, handle: zjb.Handle) void {
                    const okh = on_ok orelse {
                        if (owned and !handle.isNull()) handle.release();
                        return;
                    };
                    if (T == void) {
                        defer if (owned and !handle.isNull()) handle.release();
                        okh(inner_ctx);
                    } else if (T == i32 or T == i64 or T == f32 or T == f64) {
                        defer if (owned and !handle.isNull()) handle.release();
                        const num_fn = zjb.global("Number");
                        const code = num_fn.call(
                            "call",
                            .{ zjb.Handle.null, handle },
                            T,
                        );
                        okh(inner_ctx, code);
                    } else {
                        okh(inner_ctx, .fromHandle(handle));
                    }
                }
            };

            const ok_cb = if (on_ok != null) &TypeWrapper.okWrapper else null;
            if (owned) {
                self.promise.thenFnOwned(Context, ctx, ok_cb, on_err);
            } else {
                self.promise.thenFn(Context, ctx, ok_cb, on_err);
            }
        }

        /// Releases the underlying JavaScript `Promise` handle.
        pub fn release(self: @This()) void {
            std.debug.assert(@sizeOf(@This()) == @sizeOf(Promise));
            std.debug.assert(
                T == void or T == i32 or @hasField(T, "handle"),
            );
            self.promise.release();
        }
    };
}
