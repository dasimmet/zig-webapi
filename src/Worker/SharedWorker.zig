//! SharedWorker Web API interface representing a worker shared across browsing
//! contexts on the same origin.
//! https://developer.mozilla.org/en-US/docs/Web/API/SharedWorker

// 1. Imports
const std = @import("std");
const webapi = @import("../webapi.zig");
const Worker = @import("../Worker.zig");
const MessagePort = @import("MessagePort.zig");

// 2. Shortcuts on imports
const SharedWorker = @This();
const zjb = webapi.zjb;

// 3. File-level struct members
handle: zjb.Handle,
pub const @"null": SharedWorker = .{ .handle = .null };

// 7. Public functions
/// Returns true if `SharedWorker` is available in the current global scope.
pub fn isSupported() bool {
    const cls = zjb.ConstHandle.global.get("SharedWorker", zjb.Handle);
    defer cls.release();
    return !cls.isNull();
}

/// Spawns or connects to a shared worker running `script_url`.
/// https://developer.mozilla.org/en-US/docs/Web/API/SharedWorker/SharedWorker
pub fn init(script_url: []const u8, options: ?Worker.Options) SharedWorker {
    std.debug.assert(script_url.len > 0);
    const url_s = zjb.string(script_url);
    defer url_s.release();

    const ctor = zjb.global("SharedWorker");
    if (options) |opt| {
        const opts_h = opt.toHandle();
        defer opts_h.release();
        return fromHandle(ctor.new(.{ url_s, opts_h }));
    }
    return fromHandle(ctor.new(.{url_s}));
}

/// Wraps a non-null JS SharedWorker handle.
pub fn fromHandle(handle: zjb.Handle) SharedWorker {
    std.debug.assert(!handle.isNull());
    std.debug.assert(@backingInt(handle) != 0);
    return .{ .handle = handle };
}

/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: SharedWorker) bool {
    return self.handle.isNull();
}

/// Releases the underlying JS handle.
pub fn release(self: SharedWorker) void {
    self.handle.release();
}

/// Returns an owned handle to the `MessagePort` used to communicate with this
/// shared worker.
/// https://developer.mozilla.org/en-US/docs/Web/API/SharedWorker/port
pub fn port(self: SharedWorker) MessagePort {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return MessagePort.fromHandle(self.handle.get("port", zjb.Handle));
}

/// Attaches a context-bound listener receiving `Worker.EventFor(ev)`.
pub fn addEventListener(
    self: SharedWorker,
    comptime ev: []const u8,
    comptime Context: type,
    ctx: *Context,
    comptime f: *const fn (*Context, Worker.EventFor(ev)) void,
) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(ev.len > 0);
    webapi.boundEventListenerTyped(
        Context,
        Worker.EventFor(ev),
        ev,
        self.handle,
        f,
        ctx,
    );
}

/// Attaches an owned-handle typed listener receiving `Worker.EventFor(ev)`.
pub fn addEventListenerOwned(
    self: SharedWorker,
    comptime ev: []const u8,
    comptime Context: type,
    ctx: *Context,
    comptime f: *const fn (*Context, Worker.EventFor(ev)) void,
) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(ev.len > 0);
    webapi.boundEventListenerTypedOwned(
        Context,
        Worker.EventFor(ev),
        ev,
        self.handle,
        f,
        ctx,
    );
}
