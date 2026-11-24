//! Navigator Web API interface representing user agent state and identity.
//! https://developer.mozilla.org/en-US/docs/Web/API/Navigator

// 1. Imports
const std = @import("std");
const webapi = @import("../webapi.zig");
const Clipboard = @import("Clipboard.zig");
const Geolocation = @import("Geolocation.zig");
const RelatedApplication = @import("RelatedApplication.zig");
const ServiceWorkerContainer = @import("ServiceWorkerContainer.zig");
const Share = @import("Share.zig");

// 2. Shortcuts on imports
const Navigator = @This();
const MediaDevices = webapi.MediaDevices;
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

/// Returns the Geolocation interface for querying device location, or `.null` if unsupported.
/// https://developer.mozilla.org/en-US/docs/Web/API/Navigator/geolocation
pub fn geolocation(self: Navigator) Geolocation {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const h = self.handle.get("geolocation", zjb.Handle);
    if (h.isNull()) return .null;
    return Geolocation.fromHandle(h);
}

/// Returns the `MediaDevices` interface for audio/video input capture and
/// device enumeration, or `.null` if unsupported (e.g. insecure context).
/// Caller must call `.release()` when non-null.
/// https://developer.mozilla.org/en-US/docs/Web/API/Navigator/mediaDevices
pub fn mediaDevices(self: Navigator) MediaDevices {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const h = self.handle.get("mediaDevices", zjb.Handle);
    if (h.isNull()) return .null;
    return MediaDevices.fromHandle(h);
}

/// Returns true if `navigator.share` is defined on this `Navigator`.
/// https://developer.mozilla.org/en-US/docs/Web/API/Navigator/share
pub fn isShareSupported(self: Navigator) bool {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const fn_h = self.handle.get("share", zjb.Handle);
    defer fn_h.release();
    return !fn_h.isNull();
}

/// Returns true if `navigator.canShare` is defined on this `Navigator`.
/// https://developer.mozilla.org/en-US/docs/Web/API/Navigator/canShare
pub fn isCanShareSupported(self: Navigator) bool {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const fn_h = self.handle.get("canShare", zjb.Handle);
    defer fn_h.release();
    return !fn_h.isNull();
}

/// Validates whether `data` would succeed if passed to `share()`.
/// Returns `false` if `navigator.canShare` is unavailable.
/// https://developer.mozilla.org/en-US/docs/Web/API/Navigator/canShare
pub fn canShare(self: Navigator, data: Share.Data) bool {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const fn_h = self.handle.get("canShare", zjb.Handle);
    defer fn_h.release();
    if (fn_h.isNull()) return false;
    const data_h = data.toHandle();
    defer data_h.release();
    return self.handle.call("canShare", .{data_h}, bool);
}

/// Invokes the native sharing mechanism with `data`, returning a
/// `Promise.Typed(void)` or `null` if `navigator.share` is unsupported.
/// https://developer.mozilla.org/en-US/docs/Web/API/Navigator/share
pub fn share(self: Navigator, data: Share.Data) ?webapi.Promise.Typed(void) {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const fn_h = self.handle.get("share", zjb.Handle);
    defer fn_h.release();
    if (fn_h.isNull()) return null;
    const data_h = data.toHandle();
    defer data_h.release();
    const p_h = self.handle.call("share", .{data_h}, zjb.Handle);
    if (p_h.isNull()) {
        p_h.release();
        return null;
    }
    return .fromHandle(p_h);
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
