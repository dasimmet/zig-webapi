//! DedicatedWorkerGlobalScope Web API interface representing the global scope
//! inside a dedicated Web Worker (`self` / `globalThis`).
//! https://developer.mozilla.org/en-US/docs/Web/API/DedicatedWorkerGlobalScope

// 1. Imports
const std = @import("std");
const webapi = @import("../webapi.zig");
const Worker = @import("../Worker.zig");
const WorkerLocation = @import("WorkerLocation.zig");
const WorkerNavigator = @import("WorkerNavigator.zig");

// 2. Shortcuts on imports
const DedicatedWorkerGlobalScope = @This();
const zjb = webapi.zjb;

// 3. File-level struct members
handle: zjb.Handle,
pub const @"null": DedicatedWorkerGlobalScope = .{ .handle = .null };

// 7. Public functions
/// Returns a handle to the current `DedicatedWorkerGlobalScope` (`self`).
pub fn global() DedicatedWorkerGlobalScope {
    const h = zjb.ConstHandle.global.asHandle();
    return fromHandle(h);
}

/// Wraps a non-null JS DedicatedWorkerGlobalScope handle.
pub fn fromHandle(handle: zjb.Handle) DedicatedWorkerGlobalScope {
    std.debug.assert(!handle.isNull());
    std.debug.assert(@backingInt(handle) != 0);
    return .{ .handle = handle };
}

/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: DedicatedWorkerGlobalScope) bool {
    return self.handle.isNull();
}

/// Releases the underlying JS handle.
pub fn release(self: DedicatedWorkerGlobalScope) void {
    self.handle.release();
}

/// Copies the optional worker `name` (passed in `Worker` options) into `buf`.
/// https://developer.mozilla.org/en-US/docs/Web/API/DedicatedWorkerGlobalScope/name
pub fn name(self: DedicatedWorkerGlobalScope, buf: []u8) []u8 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(buf.len > 0);
    const name_h = self.handle.get("name", zjb.Handle);
    defer name_h.release();
    if (name_h.isNull()) return "";
    return webapi.stringFromHandle(name_h, buf);
}

/// Returns the `WorkerLocation` associated with this worker.
/// https://developer.mozilla.org/en-US/docs/Web/API/WorkerGlobalScope/location
pub fn location(self: DedicatedWorkerGlobalScope) WorkerLocation {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return WorkerLocation.fromHandle(self.handle.get("location", zjb.Handle));
}

/// Returns the `WorkerNavigator` associated with this worker.
/// https://developer.mozilla.org/en-US/docs/Web/API/WorkerGlobalScope/navigator
pub fn navigator(self: DedicatedWorkerGlobalScope) WorkerNavigator {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return WorkerNavigator.fromHandle(self.handle.get("navigator", zjb.Handle));
}

/// Sends a structured message handle back to the worker's parent thread.
/// https://developer.mozilla.org/en-US/docs/Web/API/DedicatedWorkerGlobalScope/postMessage
pub fn postMessage(
    self: DedicatedWorkerGlobalScope,
    message: zjb.Handle,
) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(!message.isNull());
    self.handle.call("postMessage", .{message}, void);
}

/// Sends a structured message handle along with a JS array of transferables.
/// https://developer.mozilla.org/en-US/docs/Web/API/DedicatedWorkerGlobalScope/postMessage
pub fn postMessageWithTransfer(
    self: DedicatedWorkerGlobalScope,
    message: zjb.Handle,
    transfer: zjb.Handle,
) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(!message.isNull());
    std.debug.assert(!transfer.isNull());
    self.handle.call("postMessage", .{ message, transfer }, void);
}

/// Sends a UTF-8 text message back to the worker's parent thread.
pub fn postText(self: DedicatedWorkerGlobalScope, text: []const u8) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@intFromPtr(text.ptr) != 0 or text.len == 0);
    const text_s = zjb.string(text);
    defer text_s.release();
    self.postMessage(text_s);
}

/// Sends raw bytes as a standalone `Uint8Array` copy back to the parent thread.
pub fn postBytes(self: DedicatedWorkerGlobalScope, data: []const u8) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@intFromPtr(data.ptr) != 0 or data.len == 0);
    const standalone = webapi.createStandaloneUint8Array(data);
    defer standalone.release();
    self.postMessage(standalone);
}

/// Synchronously imports a classic script URL into the worker scope.
/// https://developer.mozilla.org/en-US/docs/Web/API/WorkerGlobalScope/importScripts
pub fn importScript(
    self: DedicatedWorkerGlobalScope,
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
    self: DedicatedWorkerGlobalScope,
    script_urls: []const []const u8,
) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(script_urls.len > 0);
    for (script_urls) |url| {
        self.importScript(url);
    }
}

/// Discards any queued tasks in the worker event loop, closing this worker.
/// https://developer.mozilla.org/en-US/docs/Web/API/DedicatedWorkerGlobalScope/close
pub fn close(self: DedicatedWorkerGlobalScope) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    self.handle.call("close", .{}, void);
}

/// Attaches a context-bound listener receiving `Worker.EventFor(ev)`.
pub fn addEventListener(
    self: DedicatedWorkerGlobalScope,
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
    self: DedicatedWorkerGlobalScope,
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
