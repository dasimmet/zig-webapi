//! LaunchParams Web API interface containing the parameters of a PWA launch.
//! Passed to the consumer callback registered via `LaunchQueue.setConsumer`.
//! https://developer.mozilla.org/en-US/docs/Web/API/LaunchParams

// 1. Imports
const std = @import("std");
const webapi = @import("../webapi.zig");

// 2. Shortcuts on imports
const LaunchParams = @This();
const zjb = webapi.zjb;

// 3. File-level struct members
handle: zjb.Handle = .null,

// 7. Public functions
/// Wraps a non-null JS LaunchParams handle.
pub fn fromHandle(handle: zjb.Handle) LaunchParams {
    std.debug.assert(!handle.isNull());
    std.debug.assert(@backingInt(handle) != 0);
    return .{ .handle = handle };
}

/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: LaunchParams) bool {
    return self.handle.isNull();
}

/// Releases the underlying JS handle when owned.
pub fn release(self: LaunchParams) void {
    self.handle.release();
}

/// Copies `launchParams.targetURL` into `buf`, or returns null if unset.
/// https://developer.mozilla.org/en-US/docs/Web/API/LaunchParams/targetURL
pub fn targetURL(self: LaunchParams, buf: []u8) ?[]const u8 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(buf.len > 0);
    const url_h = self.handle.get("targetURL", zjb.Handle);
    defer url_h.release();
    if (url_h.isNull()) return null;
    return webapi.stringFromHandle(url_h, buf);
}

/// Allocates and returns `launchParams.targetURL`, or null if unset.
/// https://developer.mozilla.org/en-US/docs/Web/API/LaunchParams/targetURL
pub fn targetURLAlloc(
    self: LaunchParams,
    allocator: std.mem.Allocator,
) !?[]u8 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const url_h = self.handle.get("targetURL", zjb.Handle);
    defer url_h.release();
    if (url_h.isNull()) return null;
    return try webapi.stringFromHandleAlloc(allocator, url_h);
}

/// Returns an owned JS handle to the `FileSystemHandle` array in `files`.
/// https://developer.mozilla.org/en-US/docs/Web/API/LaunchParams/files
pub fn files(self: LaunchParams) zjb.Handle {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return self.handle.get("files", zjb.Handle);
}

// 8. Extra classes and constants
pub const @"null": LaunchParams = .{};
