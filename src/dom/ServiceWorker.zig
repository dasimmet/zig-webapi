//! ServiceWorker Web API interface representing a service worker instance.
//! https://developer.mozilla.org/en-US/docs/Web/API/ServiceWorker

// 1. Imports
const std = @import("std");
const webapi = @import("../webapi.zig");

// 2. Shortcuts on imports
const ServiceWorker = @This();
const dom = webapi.dom;
const zjb = webapi.zjb;

// 3. File-level struct members
handle: zjb.Handle,
pub const @"null": ServiceWorker = .{ .handle = .null };

// 7. Public functions
/// Wraps a non-null JS `ServiceWorker` handle.
pub fn fromHandle(handle: zjb.Handle) ServiceWorker {
    std.debug.assert(!handle.isNull());
    std.debug.assert(@backingInt(handle) != 0);
    return .{ .handle = handle };
}

/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: ServiceWorker) bool {
    return self.handle.isNull();
}

/// Releases the underlying JS handle.
pub fn release(self: ServiceWorker) void {
    self.handle.release();
}

/// Reads JS property `field` as `RetType`.
pub fn get(
    self: ServiceWorker,
    comptime field: []const u8,
    RetType: type,
) RetType {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(field.len > 0);
    return self.handle.get(field, RetType);
}

/// Sends a structured message to the service worker.
/// https://developer.mozilla.org/en-US/docs/Web/API/ServiceWorker/postMessage
pub fn postMessage(self: ServiceWorker, message: zjb.Handle) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(!message.isNull());
    self.handle.call("postMessage", .{message}, void);
}

/// Attaches a context-bound listener receiving `webapi.Event.EventFor(ev)`.
pub fn addEventListener(
    self: ServiceWorker,
    comptime ev: []const u8,
    comptime Context: type,
    ctx: *Context,
    comptime f: *const fn (*Context, webapi.Event.EventFor(ev)) void,
) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(ev.len > 0);
    webapi.boundEventListenerTyped(
        Context,
        webapi.Event.EventFor(ev),
        ev,
        self.handle,
        f,
        ctx,
    );
}
