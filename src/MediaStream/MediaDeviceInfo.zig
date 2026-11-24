//! Type-safe wrapper for `MediaDeviceInfo`, describing a single media input
//! or output device returned by `MediaDevices.enumerateDevices()`.
//! https://developer.mozilla.org/en-US/docs/Web/API/MediaDeviceInfo

// 1. Imports
const std = @import("std");
const webapi = @import("../webapi.zig");

// 2. Shortcuts on imports
const MediaDeviceInfo = @This();
const zjb = webapi.zjb;

// 3. File-level struct members
handle: zjb.Handle,
pub const @"null": MediaDeviceInfo = .{ .handle = .null };

// 7. Public functions
/// Wraps a non-null JS `MediaDeviceInfo` handle.
pub fn fromHandle(handle: zjb.Handle) MediaDeviceInfo {
    std.debug.assert(!handle.isNull());
    std.debug.assert(@backingInt(handle) != 0);
    return .{ .handle = handle };
}

/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: MediaDeviceInfo) bool {
    return self.handle.isNull();
}

/// Releases the underlying JS handle.
pub fn release(self: MediaDeviceInfo) void {
    self.handle.release();
}

/// Copies the origin-unique device identifier (`deviceInfo.deviceId`) into `buf`.
/// https://developer.mozilla.org/en-US/docs/Web/API/MediaDeviceInfo/deviceId
pub fn deviceId(self: MediaDeviceInfo, buf: []u8) []u8 {
    return readStringProp(self.handle, "deviceId", buf);
}

/// Copies the physical hardware group identifier (`deviceInfo.groupId`) into `buf`.
/// https://developer.mozilla.org/en-US/docs/Web/API/MediaDeviceInfo/groupId
pub fn groupId(self: MediaDeviceInfo, buf: []u8) []u8 {
    return readStringProp(self.handle, "groupId", buf);
}

/// Copies the human-readable device name (`deviceInfo.label`) into `buf`.
/// Note: empty unless media capture permission has been granted in this origin.
/// https://developer.mozilla.org/en-US/docs/Web/API/MediaDeviceInfo/label
pub fn label(self: MediaDeviceInfo, buf: []u8) []u8 {
    return readStringProp(self.handle, "label", buf);
}

/// Returns the device category (`audioinput`, `audiooutput`, or `videoinput`).
/// https://developer.mozilla.org/en-US/docs/Web/API/MediaDeviceInfo/kind
pub fn kind(self: MediaDeviceInfo) Kind {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    var buf: [24]u8 = undefined;
    return Kind.fromString(readStringProp(self.handle, "kind", &buf));
}

// 8. Extra classes
/// Hardware device category reported by `MediaDeviceInfo.kind`.
pub const Kind = enum {
    audioinput,
    audiooutput,
    videoinput,
    unknown,

    pub fn fromString(s: []const u8) Kind {
        if (std.mem.eql(u8, s, "audioinput")) return .audioinput;
        if (std.mem.eql(u8, s, "audiooutput")) return .audiooutput;
        if (std.mem.eql(u8, s, "videoinput")) return .videoinput;
        return .unknown;
    }
};

/// Typed view/iterator over `Array<MediaDeviceInfo>` resolved by
/// `MediaDevices.enumerateDevices()`.
pub const List = struct {
    handle: zjb.Handle,
    pos: usize = 0,

    pub const @"null": List = .{ .handle = .null };

    /// Wraps a non-null JS `Array<MediaDeviceInfo>` handle.
    pub fn fromHandle(handle: zjb.Handle) List {
        std.debug.assert(!handle.isNull());
        std.debug.assert(@backingInt(handle) != 0);
        return .{ .handle = handle };
    }

    /// Returns true if the underlying JS handle is null or undefined.
    pub fn isNull(self: List) bool {
        return self.handle.isNull();
    }

    /// Releases the underlying JS array handle.
    pub fn release(self: List) void {
        self.handle.release();
    }

    /// Returns the number of devices in the list.
    pub fn len(self: List) usize {
        if (self.handle.isNull()) return 0;
        const raw = self.handle.get("length", i32);
        return if (raw > 0) @intCast(raw) else 0;
    }

    /// Returns an owned `MediaDeviceInfo` at `idx`, or `null` if out of bounds.
    pub fn get(self: List, idx: usize) ?MediaDeviceInfo {
        if (idx >= self.len()) return null;
        const item = self.handle.indexGet(@as(i32, @intCast(idx)), zjb.Handle);
        if (item.isNull()) {
            item.release();
            return null;
        }
        return MediaDeviceInfo.fromHandle(item);
    }

    /// Returns the next owned `MediaDeviceInfo`, or `null` when exhausted.
    pub fn next(self: *List) ?MediaDeviceInfo {
        const cur = self.pos;
        if (cur >= self.len()) return null;
        self.pos += 1;
        return self.get(cur);
    }
};

// 9. Private declarations
fn readStringProp(h: zjb.Handle, comptime prop: []const u8, buf: []u8) []u8 {
    std.debug.assert(!h.isNull());
    std.debug.assert(buf.len > 0);
    const val_h = h.get(prop, zjb.Handle);
    defer val_h.release();
    if (val_h.isNull()) return "";
    return webapi.stringFromHandle(val_h, buf);
}
