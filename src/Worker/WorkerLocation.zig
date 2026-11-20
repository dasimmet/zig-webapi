//! WorkerLocation Web API interface representing the script URL inside a Worker.
//! https://developer.mozilla.org/en-US/docs/Web/API/WorkerLocation

// 1. Imports
const std = @import("std");
const webapi = @import("../webapi.zig");

// 2. Shortcuts on imports
const WorkerLocation = @This();
const zjb = webapi.zjb;

// 3. File-level struct members
handle: zjb.Handle,
pub const @"null": WorkerLocation = .{ .handle = .null };

// 7. Public functions
/// Wraps a non-null JS WorkerLocation handle.
pub fn fromHandle(handle: zjb.Handle) WorkerLocation {
    std.debug.assert(!handle.isNull());
    std.debug.assert(@backingInt(handle) != 0);
    return .{ .handle = handle };
}

/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: WorkerLocation) bool {
    return self.handle.isNull();
}

/// Releases the underlying JS handle.
pub fn release(self: WorkerLocation) void {
    self.handle.release();
}

/// Copies the full serialized worker script URL into `buf`.
/// https://developer.mozilla.org/en-US/docs/Web/API/WorkerLocation/href
pub fn getHref(self: WorkerLocation, buf: []u8) []u8 {
    return self.readStringProp("href", buf);
}

/// Copies the canonical origin of the worker script URL into `buf`.
/// https://developer.mozilla.org/en-US/docs/Web/API/WorkerLocation/origin
pub fn getOrigin(self: WorkerLocation, buf: []u8) []u8 {
    return self.readStringProp("origin", buf);
}

/// Copies the URL scheme (e.g. `"https:"`) into `buf`.
/// https://developer.mozilla.org/en-US/docs/Web/API/WorkerLocation/protocol
pub fn getProtocol(self: WorkerLocation, buf: []u8) []u8 {
    return self.readStringProp("protocol", buf);
}

/// Copies the host (hostname and optional port) into `buf`.
/// https://developer.mozilla.org/en-US/docs/Web/API/WorkerLocation/host
pub fn getHost(self: WorkerLocation, buf: []u8) []u8 {
    return self.readStringProp("host", buf);
}

/// Copies the domain name into `buf`.
/// https://developer.mozilla.org/en-US/docs/Web/API/WorkerLocation/hostname
pub fn getHostname(self: WorkerLocation, buf: []u8) []u8 {
    return self.readStringProp("hostname", buf);
}

/// Copies the port number string into `buf`.
/// https://developer.mozilla.org/en-US/docs/Web/API/WorkerLocation/port
pub fn getPort(self: WorkerLocation, buf: []u8) []u8 {
    return self.readStringProp("port", buf);
}

/// Copies the URL path component into `buf`.
/// https://developer.mozilla.org/en-US/docs/Web/API/WorkerLocation/pathname
pub fn getPathname(self: WorkerLocation, buf: []u8) []u8 {
    return self.readStringProp("pathname", buf);
}

/// Copies the URL query string (including leading `?`) into `buf`.
/// https://developer.mozilla.org/en-US/docs/Web/API/WorkerLocation/search
pub fn getSearch(self: WorkerLocation, buf: []u8) []u8 {
    return self.readStringProp("search", buf);
}

/// Copies the URL fragment identifier (including leading `#`) into `buf`.
/// https://developer.mozilla.org/en-US/docs/Web/API/WorkerLocation/hash
pub fn getHash(self: WorkerLocation, buf: []u8) []u8 {
    return self.readStringProp("hash", buf);
}

// 8. Extra classes and constants

// 9. Private declarations
fn readStringProp(
    self: WorkerLocation,
    comptime prop: []const u8,
    buf: []u8,
) []u8 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(buf.len > 0);
    const h = self.handle.get(prop, zjb.Handle);
    defer h.release();
    if (h.isNull()) return "";
    return webapi.stringFromHandle(h, buf);
}
