//! Context-bound JavaScript callback and DOM event listener trampolines.
//!
//! Exports at most two C-ABI dispatcher entry points (`webapi_callback` and
//! `webapi_callback_owned`) via `zjb.fnHandle`, memoizes the bound function
//! trampoline per `(Context, owned, f)` as a `zjb.ConstHandle`, and binds the
//! runtime context pointer into a releasable `zjb.Handle`.

const std = @import("std");
const webapi = @import("webapi.zig");
const zjb = webapi.zjb;

const JsPtrInt = @Int(.signed, @bitSizeOf(usize));

/// Memoizes a `zjb.ConstHandle` binding the per-function trampoline onto the
/// shared JS callback dispatcher (`owned` controls automatic payload release).
pub fn memoizeCallback(
    comptime Context: type,
    comptime owned: bool,
    comptime f: *const fn (*Context, zjb.Handle) void,
) zjb.ConstHandle {
    std.debug.assert(@intFromPtr(f) != 0);

    return struct {
        var handle: ?zjb.ConstHandle = null;
        fn get() zjb.ConstHandle {
            if (handle) |h| return h;

            const tramp_ptr: JsPtrInt = @bitCast(
                @intFromPtr(fnTrampoline(Context, f)),
            );
            const h = callback(owned).call(
                "bind",
                .{ zjb.Handle.null, tramp_ptr },
                zjb.ConstHandle,
            );
            std.debug.assert(!h.isNull());
            handle = h;
            return h;
        }
    }.get();
}

/// Binds runtime `ctx` onto the memoized dispatcher handle for `(Context,
/// owned, f)`, returning a `zjb.Handle` that the caller must release.
pub fn bindCallback(
    comptime Context: type,
    comptime owned: bool,
    ctx: *Context,
    comptime f: *const fn (*Context, zjb.Handle) void,
) zjb.Handle {
    std.debug.assert(@intFromPtr(ctx) != 0 or @sizeOf(Context) == 0);
    std.debug.assert(@intFromPtr(f) != 0);

    const ctx_ptr: JsPtrInt = @bitCast(@intFromPtr(ctx));
    return memoizeCallback(Context, owned, f).call(
        "bind",
        .{ zjb.Handle.null, ctx_ptr },
        zjb.Handle,
    );
}

/// Type-erased internal trampoline signature invoked by `callback`.
const CallbackTrampoline = *const fn (*anyopaque, zjb.Handle) void;

/// Wraps `f` to construct `ReturnType` from `zjb.Handle` and attaches the
/// listener onto JS object `h` (`owned` controls automatic payload release).
pub fn attachTypedListener(
    comptime Context: type,
    comptime ReturnType: type,
    comptime owned: bool,
    comptime event_name: []const u8,
    h: anytype,
    comptime f: *const fn (*Context, ReturnType) void,
    ctx: *Context,
) void {
    const TypeWrapper = struct {
        fn wrap_f(inner_ctx: *Context, handle: zjb.Handle) void {
            f(inner_ctx, .{ .handle = handle });
        }
    };
    attachBoundListener(
        Context,
        owned,
        event_name,
        h,
        &TypeWrapper.wrap_f,
        ctx,
    );
}

/// Binds a callback and registers it via `h.addEventListener(event_name, ...)`,
/// immediately releasing the intermediate JS bound function handle.
pub fn attachBoundListener(
    comptime Context: type,
    comptime owned: bool,
    comptime event_name: []const u8,
    h: anytype,
    comptime f: *const fn (*Context, zjb.Handle) void,
    ctx: *Context,
) void {
    if (@TypeOf(h) != zjb.Handle and @TypeOf(h) != zjb.ConstHandle) {
        @compileError("expected a Handle or ConstHandle");
    }
    std.debug.assert(event_name.len > 0);
    std.debug.assert(!h.isNull());

    const bound_f = bindCallback(Context, owned, ctx, f);
    defer bound_f.release();
    h.call("addEventListener", .{
        zjb.constString(event_name),
        bound_f,
    }, void);
}

/// Returns an internal trampoline that recovers `*Context` before invoking
/// `f(ctx, payload)`.
fn fnTrampoline(
    comptime Context: type,
    comptime f: *const fn (*Context, zjb.Handle) void,
) CallbackTrampoline {
    const Helper = struct {
        fn call(ctx_raw: *anyopaque, payload: zjb.Handle) void {
            std.debug.assert(
                @intFromPtr(ctx_raw) != 0 or @sizeOf(Context) == 0,
            );
            const ctx: *Context = @ptrCast(@alignCast(ctx_raw));
            f(ctx, payload);
        }
    };
    return &Helper.call;
}

/// Shared callback dispatcher across all context types.
/// Exports at most two C-ABI entry points total (`webapi_callback` and
/// `webapi_callback_owned`), delegating type recovery to `fnTrampoline`.
fn callback(comptime owned: bool) zjb.ConstHandle {
    const Dispatcher = struct {
        fn call(
            tramp_i: JsPtrInt,
            ctxptr_i: JsPtrInt,
            payload: zjb.Handle,
        ) callconv(.c) void {
            defer if (!owned) payload.release();
            std.debug.assert(tramp_i != 0);

            const tramp: CallbackTrampoline = @ptrFromInt(
                @as(usize, @bitCast(tramp_i)),
            );
            const ctx_raw: *anyopaque = @ptrFromInt(
                @as(usize, @bitCast(ctxptr_i)),
            );
            tramp(ctx_raw, payload);
        }
    };

    return zjb.fnHandle(
        if (owned) "webapi_callback_owned" else "webapi_callback",
        &Dispatcher.call,
    );
}
