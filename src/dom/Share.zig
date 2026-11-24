//! Type-safe wrapper for the browser Web Share API (`navigator.share` / `navigator.canShare`).
//! https://developer.mozilla.org/en-US/docs/Web/API/Web_Share_API
//! https://developer.mozilla.org/en-US/docs/Web/API/Navigator/share
//! https://developer.mozilla.org/en-US/docs/Web/API/Navigator/canShare

// 1. Imports
const std = @import("std");
const webapi = @import("../webapi.zig");
const Navigator = @import("Navigator.zig");

// 2. Shortcuts on imports
const Share = @This();
const zjb = webapi.zjb;

// 6. Types
/// Payload dictionary accepted by `navigator.share()` and `navigator.canShare()`.
/// At least one field must be set.
/// https://developer.mozilla.org/en-US/docs/Web/API/Navigator/share#parameters
pub const Data = struct {
    title: ?[]const u8 = null,
    text: ?[]const u8 = null,
    url: ?[]const u8 = null,
    files: []const webapi.File = &.{},

    /// Returns true if no shareable properties or files are populated.
    pub fn isEmpty(self: Data) bool {
        return self.title == null and
            self.text == null and
            self.url == null and
            self.files.len == 0;
    }

    /// Serializes this `ShareData` into a newly allocated JS object handle.
    pub fn toHandle(self: Data) zjb.Handle {
        std.debug.assert(!self.isEmpty());
        const obj = zjb.global("Object").new(.{});
        std.debug.assert(!obj.isNull());

        if (self.title) |t| {
            const s = zjb.string(t);
            defer s.release();
            obj.set("title", s);
        }
        if (self.text) |t| {
            const s = zjb.string(t);
            defer s.release();
            obj.set("text", s);
        }
        if (self.url) |u| {
            const s = zjb.string(u);
            defer s.release();
            obj.set("url", s);
        }
        if (self.files.len > 0) {
            const arr = zjb.global("Array").new(.{});
            defer arr.release();
            for (self.files) |file| {
                std.debug.assert(!file.isNull());
                arr.call("push", .{file.handle}, void);
            }
            obj.set("files", arr);
        }
        return obj;
    }
};

// 7. Public functions
/// Returns true if `navigator.share` is available in this environment.
/// https://developer.mozilla.org/en-US/docs/Web/API/Navigator/share
pub fn isSupported() bool {
    const nav = Navigator.fromHandle(zjb.global("navigator").asHandle());
    return nav.isShareSupported();
}

/// Returns true if `navigator.canShare` is available in this environment.
/// https://developer.mozilla.org/en-US/docs/Web/API/Navigator/canShare
pub fn isCanShareSupported() bool {
    const nav = Navigator.fromHandle(zjb.global("navigator").asHandle());
    return nav.isCanShareSupported();
}

/// Returns true if `navigator.canShare(data)` validates that `data` can be shared.
/// https://developer.mozilla.org/en-US/docs/Web/API/Navigator/canShare
pub fn canShare(data: Data) bool {
    const nav = Navigator.fromHandle(zjb.global("navigator").asHandle());
    return nav.canShare(data);
}

/// Invokes the native sharing mechanism with `data` via `navigator.share(data)`,
/// returning a `Promise.Typed(void)` or `null` if `navigator.share` is unsupported.
/// https://developer.mozilla.org/en-US/docs/Web/API/Navigator/share
pub fn share(data: Data) ?webapi.Promise.Typed(void) {
    const nav = Navigator.fromHandle(zjb.global("navigator").asHandle());
    return nav.share(data);
}
