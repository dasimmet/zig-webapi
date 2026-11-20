//! Navigator Web API interface representing user agent state and identity.
//! https://developer.mozilla.org/en-US/docs/Web/API/Navigator

// 1. Imports
const std = @import("std");
const webapi = @import("../webapi.zig");
const Clipboard = @import("Clipboard.zig");
const RelatedApplication = @import("RelatedApplication.zig");
const ServiceWorkerContainer = @import("ServiceWorkerContainer.zig");

// 2. Shortcuts on imports
const Navigator = @This();
const zjb = webapi.zjb;

// 3. File-level struct members
handle: zjb.Handle,
pub const @"null": Navigator = .{ .handle = .null };

// 7. Public functions
/// Wraps a non-null JS `Navigator` handle.
pub fn fromHandle(handle: zjb.Handle) Navigator {
    std.debug.assert(!handle.isNull());
    std.debug.assert(@backingInt(handle) != 0);
    return .{ .handle = handle };
}

/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: Navigator) bool {
    return self.handle.isNull();
}

/// Releases the underlying JS handle.
pub fn release(self: Navigator) void {
    self.handle.release();
}

/// Reads JS property `field` as `RetType`.
pub fn get(
    self: Navigator,
    comptime field: []const u8,
    RetType: type,
) RetType {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(field.len > 0);
    return self.handle.get(field, RetType);
}

/// Returns the Clipboard interface for reading/writing system clipboard data.
/// https://developer.mozilla.org/en-US/docs/Web/API/Navigator/clipboard
pub fn clipboard(self: Navigator) Clipboard {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const h = self.handle.get("clipboard", zjb.Handle);
    if (h.isNull()) return .null;
    return Clipboard.fromHandle(h);
}

/// Returns the ServiceWorkerContainer for registering/controlling workers.
/// https://developer.mozilla.org/en-US/docs/Web/API/Navigator/serviceWorker
pub fn serviceWorker(self: Navigator) ServiceWorkerContainer {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const h = self.handle.get("serviceWorker", zjb.Handle);
    if (h.isNull()) return .null;
    return ServiceWorkerContainer.fromHandle(h);
}

/// Checks whether related apps are installed and returns a typed Promise
/// resolving to `RelatedApplication.List`, or null if unsupported.
/// https://developer.mozilla.org/en-US/docs/Web/API/Navigator/getInstalledRelatedApps
pub fn getInstalledRelatedApps(
    self: Navigator,
) ?webapi.Promise.Typed(RelatedApplication.List) {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const fn_h = self.handle.get("getInstalledRelatedApps", zjb.Handle);
    defer fn_h.release();
    if (fn_h.isNull()) {
        return null;
    }
    const p_h = self.handle.call("getInstalledRelatedApps", .{}, zjb.Handle);
    if (p_h.isNull()) {
        p_h.release();
        return null;
    }
    return .fromHandle(p_h);
}
