//! WorkerNavigator Web API interface representing navigator subset in Workers.
//! https://developer.mozilla.org/en-US/docs/Web/API/WorkerNavigator

// 1. Imports
const std = @import("std");
const webapi = @import("../webapi.zig");

// 2. Shortcuts on imports
const WorkerNavigator = @This();
const zjb = webapi.zjb;

// 3. File-level struct members
handle: zjb.Handle = .null,

// 7. Public functions
/// Wraps a non-null JS WorkerNavigator handle.
pub fn fromHandle(handle: zjb.Handle) WorkerNavigator {
    std.debug.assert(!handle.isNull());
    std.debug.assert(@backingInt(handle) != 0);
    return .{ .handle = handle };
}

/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: WorkerNavigator) bool {
    return self.handle.isNull();
}

/// Releases the underlying JS handle.
pub fn release(self: WorkerNavigator) void {
    self.handle.release();
}

/// Returns the number of logical processors available to run threads.
/// https://developer.mozilla.org/en-US/docs/Web/API/WorkerNavigator/hardwareConcurrency
pub fn hardwareConcurrency(self: WorkerNavigator) u32 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const raw = self.handle.get("hardwareConcurrency", i32);
    return if (raw > 0) @intCast(raw) else 0;
}

/// Returns true if the browser reports network connectivity.
/// https://developer.mozilla.org/en-US/docs/Web/API/WorkerNavigator/onLine
pub fn onLine(self: WorkerNavigator) bool {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return self.handle.get("onLine", bool);
}

/// Copies the user agent string into `buf`.
/// https://developer.mozilla.org/en-US/docs/Web/API/WorkerNavigator/userAgent
pub fn userAgent(self: WorkerNavigator, buf: []u8) []u8 {
    return self.readStringProp("userAgent", buf);
}

/// Copies the preferred UI language string into `buf`.
/// https://developer.mozilla.org/en-US/docs/Web/API/WorkerNavigator/language
pub fn language(self: WorkerNavigator, buf: []u8) []u8 {
    return self.readStringProp("language", buf);
}

/// Copies the platform identifier string into `buf`.
/// https://developer.mozilla.org/en-US/docs/Web/API/WorkerNavigator/platform
pub fn platform(self: WorkerNavigator, buf: []u8) []u8 {
    return self.readStringProp("platform", buf);
}

/// Returns an owned JS handle to `navigator.storage` (StorageManager).
/// https://developer.mozilla.org/en-US/docs/Web/API/WorkerNavigator/storage
pub fn storage(self: WorkerNavigator) zjb.Handle {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return self.handle.get("storage", zjb.Handle);
}

/// Returns an owned JS handle to `navigator.locks` (LockManager).
/// https://developer.mozilla.org/en-US/docs/Web/API/WorkerNavigator/locks
pub fn locks(self: WorkerNavigator) zjb.Handle {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return self.handle.get("locks", zjb.Handle);
}

// 8. Extra classes and constants
pub const @"null": WorkerNavigator = .{};

// 9. Private declarations
fn readStringProp(
    self: WorkerNavigator,
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
