//! ServiceWorkerContainer Web API interface for managing service workers.
//! https://developer.mozilla.org/en-US/docs/Web/API/ServiceWorkerContainer

// 1. Imports
const std = @import("std");
const webapi = @import("../webapi.zig");

// 2. Shortcuts on imports
const ServiceWorkerContainer = @This();
const dom = webapi.dom;
const zjb = webapi.zjb;

// 3. File-level struct members
handle: zjb.Handle,
pub const @"null": ServiceWorkerContainer = .{ .handle = .null };

// 7. Public functions
/// Wraps a non-null JS `ServiceWorkerContainer` handle.
pub fn fromHandle(handle: zjb.Handle) ServiceWorkerContainer {
    std.debug.assert(!handle.isNull());
    std.debug.assert(@backingInt(handle) != 0);
    return .{ .handle = handle };
}

/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: ServiceWorkerContainer) bool {
    return self.handle.isNull();
}

/// Releases the underlying JS handle.
pub fn release(self: ServiceWorkerContainer) void {
    self.handle.release();
}

/// Registers a service worker script at `script_url` and returns a Promise.
/// https://developer.mozilla.org/en-US/docs/Web/API/ServiceWorkerContainer
pub fn register(
    self: ServiceWorkerContainer,
    script_url: []const u8,
) zjb.Handle {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(script_url.len > 0);
    const url_s = zjb.string(script_url);
    defer url_s.release();
    return self.handle.call("register", .{url_s}, zjb.Handle);
}

/// Attaches a context-bound listener receiving `webapi.Event.EventFor(ev)`.
pub fn addEventListener(
    self: ServiceWorkerContainer,
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
