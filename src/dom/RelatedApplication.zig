//! RelatedApplication Web API interface representing an installed related app.
//! Returned in the array resolved by `Navigator.getInstalledRelatedApps()`.
//! https://developer.mozilla.org/en-US/docs/Web/API/RelatedApplication
//! https://developer.mozilla.org/en-US/docs/Web/API/Navigator/getInstalledRelatedApps

// 1. Imports
const std = @import("std");
const webapi = @import("../webapi.zig");

// 2. Shortcuts on imports
const RelatedApplication = @This();
const zjb = webapi.zjb;

// 3. File-level struct members
handle: zjb.Handle,
pub const @"null": RelatedApplication = .{ .handle = .null };

// 7. Public functions
/// Wraps a non-null JS RelatedApplication handle.
pub fn fromHandle(handle: zjb.Handle) RelatedApplication {
    std.debug.assert(!handle.isNull());
    std.debug.assert(@backingInt(handle) != 0);
    return .{ .handle = handle };
}

/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: RelatedApplication) bool {
    return self.handle.isNull();
}

/// Releases the underlying JS handle.
pub fn release(self: RelatedApplication) void {
    self.handle.release();
}

/// Copies the related application's `platform` identifier into `buf`.
/// https://developer.mozilla.org/en-US/docs/Web/API/RelatedApplication/platform
pub fn platform(self: RelatedApplication, buf: []u8) []const u8 {
    return readOptionalString(self.handle, "platform", buf) orelse "";
}

/// Copies the related application's `id` into `buf`, or returns null if unset.
/// https://developer.mozilla.org/en-US/docs/Web/API/RelatedApplication/id
pub fn id(self: RelatedApplication, buf: []u8) ?[]const u8 {
    return readOptionalString(self.handle, "id", buf);
}

/// Copies the related application's `url` into `buf`, or returns null if unset.
/// https://developer.mozilla.org/en-US/docs/Web/API/RelatedApplication/url
pub fn url(self: RelatedApplication, buf: []u8) ?[]const u8 {
    return readOptionalString(self.handle, "url", buf);
}

/// Copies the related application's `version` into `buf`, or returns null if unset.
/// https://developer.mozilla.org/en-US/docs/Web/API/RelatedApplication/version
pub fn version(self: RelatedApplication, buf: []u8) ?[]const u8 {
    return readOptionalString(self.handle, "version", buf);
}

// 8. Extra classes and constants

/// Typed view/iterator over the `Array<RelatedApplication>` resolved by
/// `Navigator.getInstalledRelatedApps()`.
pub const List = struct {
    handle: zjb.Handle,
    pos: usize = 0,

    pub const @"null": List = .{ .handle = .null };

    /// Wraps a non-null JS `Array<RelatedApplication>` handle.
    pub fn fromHandle(handle: zjb.Handle) List {
        std.debug.assert(!handle.isNull());
        std.debug.assert(@backingInt(handle) != 0);
        return .{ .handle = handle };
    }

    /// Returns true if the underlying JS handle is null or undefined.
    pub fn isNull(self: List) bool {
        return self.handle.isNull();
    }

    /// Releases the underlying JS handle when owned.
    pub fn release(self: List) void {
        self.handle.release();
    }

    /// Returns the number of related applications in the list.
    pub fn len(self: List) usize {
        if (self.handle.isNull()) return 0;
        const raw = self.handle.get("length", i32);
        return if (raw > 0) @intCast(raw) else 0;
    }

    /// Returns an owned `RelatedApplication` at `idx`, or null if out of bounds.
    pub fn get(self: List, idx: usize) ?RelatedApplication {
        if (idx >= self.len()) return null;
        const item = self.handle.indexGet(@as(i32, @intCast(idx)), zjb.Handle);
        if (item.isNull()) {
            item.release();
            return null;
        }
        return RelatedApplication.fromHandle(item);
    }

    /// Returns the next owned `RelatedApplication` or null when exhausted.
    pub fn next(self: *List) ?RelatedApplication {
        const cur = self.pos;
        if (cur >= self.len()) return null;
        self.pos += 1;
        return self.get(cur);
    }
};

// 9. Private helpers
fn readOptionalString(
    h: zjb.Handle,
    comptime prop: []const u8,
    buf: []u8,
) ?[]const u8 {
    std.debug.assert(!h.isNull());
    std.debug.assert(buf.len > 0);
    const val_h = h.get(prop, zjb.Handle);
    defer val_h.release();
    if (val_h.isNull()) return null;
    return webapi.stringFromHandle(val_h, buf);
}
