//! ServiceWorkerRegistration Web API interface representing a registration.
//! https://developer.mozilla.org/en-US/docs/Web/API/ServiceWorkerRegistration

// 1. Imports
const std = @import("std");
const webapi = @import("../webapi.zig");
const ServiceWorker = @import("ServiceWorker.zig");

// 2. Shortcuts on imports
const ServiceWorkerRegistration = @This();
const dom = webapi.dom;
const zjb = webapi.zjb;

// 3. File-level struct members
handle: zjb.Handle,
pub const @"null": ServiceWorkerRegistration = .{ .handle = .null };

// 7. Public functions
/// Wraps a non-null JS `ServiceWorkerRegistration` handle.
pub fn fromHandle(handle: zjb.Handle) ServiceWorkerRegistration {
    std.debug.assert(!handle.isNull());
    std.debug.assert(@backingInt(handle) != 0);
    return .{ .handle = handle };
}

/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: ServiceWorkerRegistration) bool {
    return self.handle.isNull();
}

/// Releases the underlying JS handle.
pub fn release(self: ServiceWorkerRegistration) void {
    self.handle.release();
}

/// Returns the ServiceWorker currently installing for this registration.
pub fn installing(self: ServiceWorkerRegistration) ServiceWorker {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const h = self.handle.get("installing", zjb.Handle);
    if (h.isNull()) return .null;
    return ServiceWorker.fromHandle(h);
}

/// Attaches a context-bound listener receiving `webapi.Event.EventFor(ev)`.
pub fn addEventListener(
    self: ServiceWorkerRegistration,
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
