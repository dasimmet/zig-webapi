//! SharedWorkerGlobalScope Web API interface representing the global scope
//! inside a shared Web Worker (`self` / `globalThis`).
//! https://developer.mozilla.org/en-US/docs/Web/API/SharedWorkerGlobalScope

// 1. Imports
const std = @import("std");
const webapi = @import("../webapi.zig");
const Worker = @import("../Worker.zig");
const WorkerLocation = @import("WorkerLocation.zig");
const WorkerNavigator = @import("WorkerNavigator.zig");

// 2. Shortcuts on imports
const SharedWorkerGlobalScope = @This();
const zjb = webapi.zjb;

// 3. File-level struct members
handle: zjb.Handle = .null,

// 7. Public functions
/// Returns a handle to the current `SharedWorkerGlobalScope` (`self`).
pub fn global() SharedWorkerGlobalScope {
    const h = zjb.ConstHandle.global.asHandle();
    std.debug.assert(!h.isNull());
    std.debug.assert(@backingInt(h) != 0);
    return .{ .handle = h };
}

/// Wraps a non-null JS SharedWorkerGlobalScope handle.
pub fn fromHandle(handle: zjb.Handle) SharedWorkerGlobalScope {
    std.debug.assert(!handle.isNull());
    std.debug.assert(@backingInt(handle) != 0);
    return .{ .handle = handle };
}

/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: SharedWorkerGlobalScope) bool {
    return self.handle.isNull();
}

/// Releases the underlying JS handle.
pub fn release(self: SharedWorkerGlobalScope) void {
    self.handle.release();
}

/// Copies the optional shared worker `name` into `buf`.
/// https://developer.mozilla.org/en-US/docs/Web/API/SharedWorkerGlobalScope/name
pub fn name(self: SharedWorkerGlobalScope, buf: []u8) []u8 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(buf.len > 0);
    const name_h = self.handle.get("name", zjb.Handle);
    defer name_h.release();
    if (name_h.isNull()) return "";
    return webapi.stringFromHandle(name_h, buf);
}

/// Returns the `WorkerLocation` associated with this shared worker.
/// https://developer.mozilla.org/en-US/docs/Web/API/WorkerGlobalScope/location
pub fn location(self: SharedWorkerGlobalScope) WorkerLocation {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return .{ .handle = self.handle.get("location", zjb.Handle) };
}

/// Returns the `WorkerNavigator` associated with this shared worker.
/// https://developer.mozilla.org/en-US/docs/Web/API/WorkerGlobalScope/navigator
pub fn navigator(self: SharedWorkerGlobalScope) WorkerNavigator {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return .{ .handle = self.handle.get("navigator", zjb.Handle) };
}

/// Synchronously imports a classic script URL into the shared worker scope.
/// https://developer.mozilla.org/en-US/docs/Web/API/WorkerGlobalScope/importScripts
pub fn importScript(
    self: SharedWorkerGlobalScope,
    script_url: []const u8,
) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(script_url.len > 0);
    const url_s = zjb.string(script_url);
    defer url_s.release();
    self.handle.call("importScripts", .{url_s}, void);
}

/// Synchronously imports one or more classic script URLs sequentially.
/// https://developer.mozilla.org/en-US/docs/Web/API/WorkerGlobalScope/importScripts
pub fn importScripts(
    self: SharedWorkerGlobalScope,
    script_urls: []const []const u8,
) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(script_urls.len > 0);
    for (script_urls) |url| {
        self.importScript(url);
    }
}

/// Discards any queued tasks in the shared worker event loop, closing it.
/// https://developer.mozilla.org/en-US/docs/Web/API/SharedWorkerGlobalScope/close
pub fn close(self: SharedWorkerGlobalScope) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    self.handle.call("close", .{}, void);
}

/// Attaches a context-bound listener receiving `Worker.EventFor(ev)`
/// (e.g. `"connect"` receives `MessageEvent` with `.portAt(0)`).
pub fn addEventListener(
    self: SharedWorkerGlobalScope,
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
    self: SharedWorkerGlobalScope,
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

// 8. Extra classes and constants
pub const @"null": SharedWorkerGlobalScope = .{};
