//! CSSStyleDeclaration Web API interface for inline element styles.
//! https://developer.mozilla.org/en-US/docs/Web/API/CSSStyleDeclaration

// 1. Imports
const std = @import("std");
const webapi = @import("../webapi.zig");

// 2. Shortcuts on imports
const CSSStyleDeclaration = @This();
const zjb = webapi.zjb;

// 3. File-level struct members
handle: zjb.Handle,
pub const @"null": CSSStyleDeclaration = .{ .handle = .null };

// 7. Public functions
/// Wraps a non-null JS `CSSStyleDeclaration` handle.
pub fn fromHandle(handle: zjb.Handle) CSSStyleDeclaration {
    std.debug.assert(!handle.isNull());
    std.debug.assert(@backingInt(handle) != 0);
    return .{ .handle = handle };
}

/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: CSSStyleDeclaration) bool {
    return self.handle.isNull();
}

/// Releases the underlying JS handle.
pub fn release(self: CSSStyleDeclaration) void {
    self.handle.release();
}

/// Sets CSS style property `prop` on this declaration to `value`.
pub fn setProperty(
    self: CSSStyleDeclaration,
    comptime prop: []const u8,
    value: []const u8,
) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(prop.len > 0);
    const val_s = zjb.string(value);
    defer val_s.release();
    self.handle.set(prop, val_s);
}

/// Copies the value of CSS property `prop` (e.g. `"font-size"`) into `buf`.
/// https://developer.mozilla.org/en-US/docs/Web/API/CSSStyleDeclaration/getPropertyValue
pub fn getPropertyValue(
    self: CSSStyleDeclaration,
    prop: []const u8,
    buf: []u8,
) []u8 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(prop.len > 0);
    std.debug.assert(buf.len > 0);
    const prop_s = zjb.string(prop);
    defer prop_s.release();
    const val_h = self.handle.call("getPropertyValue", .{prop_s}, zjb.Handle);
    defer val_h.release();
    if (val_h.isNull()) return "";
    return webapi.stringFromHandle(val_h, buf);
}

/// Allocates and returns the value of CSS property `prop`.
/// https://developer.mozilla.org/en-US/docs/Web/API/CSSStyleDeclaration/getPropertyValue
pub fn getPropertyValueAlloc(
    self: CSSStyleDeclaration,
    allocator: std.mem.Allocator,
    prop: []const u8,
) ![]u8 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(prop.len > 0);
    const prop_s = zjb.string(prop);
    defer prop_s.release();
    const val_h = self.handle.call("getPropertyValue", .{prop_s}, zjb.Handle);
    defer val_h.release();
    return webapi.stringFromHandleAlloc(allocator, val_h);
}
