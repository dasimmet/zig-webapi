//! LaunchQueue Web API interface for handling PWA launch parameters.
//! Exposed on `window.launchQueue` in browsers supporting Launch Handler API.
//! https://developer.mozilla.org/en-US/docs/Web/API/LaunchQueue

// 1. Imports
const std = @import("std");
const webapi = @import("../webapi.zig");
const LaunchParams = @import("LaunchParams.zig");

// 2. Shortcuts on imports
const LaunchQueue = @This();
const zjb = webapi.zjb;

// 3. File-level struct members
handle: zjb.Handle = .null,

// 7. Public functions
/// Wraps a non-null JS LaunchQueue handle.
pub fn fromHandle(handle: zjb.Handle) LaunchQueue {
    std.debug.assert(!handle.isNull());
    std.debug.assert(@backingInt(handle) != 0);
    return .{ .handle = handle };
}

/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: LaunchQueue) bool {
    return self.handle.isNull();
}

/// Releases the underlying JS handle.
pub fn release(self: LaunchQueue) void {
    self.handle.release();
}

/// Registers a context-bound consumer callback invoked with `LaunchParams`
/// whenever the PWA is launched with queued launch parameters.
/// https://developer.mozilla.org/en-US/docs/Web/API/LaunchQueue/setConsumer
pub fn setConsumer(
    self: LaunchQueue,
    comptime Context: type,
    ctx: *Context,
    comptime consumer: *const fn (*Context, LaunchParams) void,
) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    std.debug.assert(@intFromPtr(ctx) != 0 or @sizeOf(Context) == 0);

    const Wrapper = struct {
        fn call(inner_ctx: *Context, params_h: zjb.Handle) void {
            consumer(inner_ctx, LaunchParams.fromHandle(params_h));
        }
    };
    const cb = webapi.boundFunction(Context, ctx, &Wrapper.call);
    defer cb.release();
    self.handle.call("setConsumer", .{cb}, void);
}

// 8. Extra classes and constants
pub const Params = LaunchParams;
pub const @"null": LaunchQueue = .{};
