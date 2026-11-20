//! Type-safe wrapper for the browser `URL` and `URLSearchParams` Web APIs.
//! https://developer.mozilla.org/en-US/docs/Web/API/URL

// 1. Imports
const std = @import("std");
const webapi = @import("webapi.zig");

// 2. Shortcuts on imports
const URL = @This();
const zjb = webapi.zjb;

// 3. File-level struct members
handle: zjb.Handle,
pub const @"null": URL = .{ .handle = .null };

// 7. Public functions
/// Returns true if `URL` is available in the current global scope.
pub fn isSupported() bool {
    const cls = zjb.ConstHandle.global.get("URL", zjb.Handle);
    defer cls.release();
    return !cls.isNull();
}

/// Constructs a `URL` object from `url` and optional `base` URL string.
/// https://developer.mozilla.org/en-US/docs/Web/API/URL/URL
pub fn init(url: []const u8, base: ?[]const u8) URL {
    std.debug.assert(url.len > 0);
    const url_s = zjb.string(url);
    defer url_s.release();

    const ctor = zjb.global("URL");
    if (base) |b| {
        std.debug.assert(b.len > 0);
        const base_s = zjb.string(b);
        defer base_s.release();
        return fromHandle(ctor.new(.{ url_s, base_s }));
    }
    return fromHandle(ctor.new(.{url_s}));
}

/// Validates whether `url` (resolved against optional `base`) is a valid URL.
/// https://developer.mozilla.org/en-US/docs/Web/API/URL/canParse_static
pub fn canParse(url: []const u8, base: ?[]const u8) bool {
    std.debug.assert(@intFromPtr(url.ptr) != 0 or url.len == 0);
    const url_s = zjb.string(url);
    defer url_s.release();

    const ctor = zjb.global("URL");
    if (base) |b| {
        const base_s = zjb.string(b);
        defer base_s.release();
        return ctor.call("canParse", .{ url_s, base_s }, bool);
    }
    return ctor.call("canParse", .{url_s}, bool);
}

/// Parses `url` (with optional `base`), returning `null` if invalid.
/// https://developer.mozilla.org/en-US/docs/Web/API/URL/parse_static
pub fn parse(url: []const u8, base: ?[]const u8) ?URL {
    std.debug.assert(@intFromPtr(url.ptr) != 0 or url.len == 0);
    const ctor = zjb.global("URL");
    const parse_fn = ctor.get("parse", zjb.Handle);
    defer parse_fn.release();
    if (parse_fn.isNull()) {
        if (url.len == 0 or !canParse(url, base)) return null;
        const parsed = init(url, base);
        if (parsed.isNull()) return null;
        return parsed;
    }

    const url_s = zjb.string(url);
    defer url_s.release();
    const h = if (base) |b| blk: {
        const base_s = zjb.string(b);
        defer base_s.release();
        break :blk ctor.call("parse", .{ url_s, base_s }, zjb.Handle);
    } else ctor.call("parse", .{url_s}, zjb.Handle);

    if (h.isNull()) {
        h.release();
        return null;
    }
    return fromHandle(h);
}

/// Creates a `blob:` object URL string handle referencing `obj` (`Blob`,
/// `File`, `MediaSource`, or raw `zjb.Handle`).
/// https://developer.mozilla.org/en-US/docs/Web/API/URL/createObjectURL_static
pub fn createObjectURL(obj: anytype) zjb.Handle {
    const obj_h = unwrapHandle(obj);
    std.debug.assert(!obj_h.isNull());
    std.debug.assert(@backingInt(obj_h) != 0);
    return zjb.global("URL").call("createObjectURL", .{obj_h}, zjb.Handle);
}

/// Releases an object URL previously created with `createObjectURL`.
/// Accepts a string slice (`[]const u8`), `zjb.Handle`, `zjb.ConstHandle`, or
/// a wrapper struct with `.handle`.
/// https://developer.mozilla.org/en-US/docs/Web/API/URL/revokeObjectURL_static
pub fn revokeObjectURL(url: anytype) void {
    if (comptime isStringLike(@TypeOf(url))) {
        const s: []const u8 = url;
        std.debug.assert(s.len > 0);
        const url_s = zjb.string(s);
        defer url_s.release();
        zjb.global("URL").call("revokeObjectURL", .{url_s}, void);
        return;
    }
    const url_h = unwrapHandle(url);
    std.debug.assert(!url_h.isNull());
    zjb.global("URL").call("revokeObjectURL", .{url_h}, void);
}

/// Wraps a non-null JS `URL` handle.
pub fn fromHandle(handle: zjb.Handle) URL {
    std.debug.assert(!handle.isNull());
    std.debug.assert(@backingInt(handle) != 0);
    return .{ .handle = handle };
}

/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: URL) bool {
    return self.handle.isNull();
}

/// Releases the underlying JS handle.
pub fn release(self: URL) void {
    self.handle.release();
}

/// Copies `url.href` into `buf`.
/// https://developer.mozilla.org/en-US/docs/Web/API/URL/href
pub fn getHref(self: URL, buf: []u8) []u8 {
    return self.readStringProp("href", buf);
}

/// Sets `url.href` to `value`.
/// https://developer.mozilla.org/en-US/docs/Web/API/URL/href
pub fn setHref(self: URL, value: []const u8) void {
    self.writeStringProp("href", value);
}

/// Copies `url.origin` into `buf`.
/// https://developer.mozilla.org/en-US/docs/Web/API/URL/origin
pub fn getOrigin(self: URL, buf: []u8) []u8 {
    return self.readStringProp("origin", buf);
}

/// Copies `url.protocol` into `buf`.
/// https://developer.mozilla.org/en-US/docs/Web/API/URL/protocol
pub fn getProtocol(self: URL, buf: []u8) []u8 {
    return self.readStringProp("protocol", buf);
}

/// Sets `url.protocol` to `value`.
/// https://developer.mozilla.org/en-US/docs/Web/API/URL/protocol
pub fn setProtocol(self: URL, value: []const u8) void {
    self.writeStringProp("protocol", value);
}

/// Copies `url.username` into `buf`.
/// https://developer.mozilla.org/en-US/docs/Web/API/URL/username
pub fn getUsername(self: URL, buf: []u8) []u8 {
    return self.readStringProp("username", buf);
}

/// Sets `url.username` to `value`.
/// https://developer.mozilla.org/en-US/docs/Web/API/URL/username
pub fn setUsername(self: URL, value: []const u8) void {
    self.writeStringProp("username", value);
}

/// Copies `url.password` into `buf`.
/// https://developer.mozilla.org/en-US/docs/Web/API/URL/password
pub fn getPassword(self: URL, buf: []u8) []u8 {
    return self.readStringProp("password", buf);
}

/// Sets `url.password` to `value`.
/// https://developer.mozilla.org/en-US/docs/Web/API/URL/password
pub fn setPassword(self: URL, value: []const u8) void {
    self.writeStringProp("password", value);
}

/// Copies `url.host` into `buf`.
/// https://developer.mozilla.org/en-US/docs/Web/API/URL/host
pub fn getHost(self: URL, buf: []u8) []u8 {
    return self.readStringProp("host", buf);
}

/// Sets `url.host` to `value`.
/// https://developer.mozilla.org/en-US/docs/Web/API/URL/host
pub fn setHost(self: URL, value: []const u8) void {
    self.writeStringProp("host", value);
}

/// Copies `url.hostname` into `buf`.
/// https://developer.mozilla.org/en-US/docs/Web/API/URL/hostname
pub fn getHostname(self: URL, buf: []u8) []u8 {
    return self.readStringProp("hostname", buf);
}

/// Sets `url.hostname` to `value`.
/// https://developer.mozilla.org/en-US/docs/Web/API/URL/hostname
pub fn setHostname(self: URL, value: []const u8) void {
    self.writeStringProp("hostname", value);
}

/// Copies `url.port` into `buf`.
/// https://developer.mozilla.org/en-US/docs/Web/API/URL/port
pub fn getPort(self: URL, buf: []u8) []u8 {
    return self.readStringProp("port", buf);
}

/// Sets `url.port` to `value`.
/// https://developer.mozilla.org/en-US/docs/Web/API/URL/port
pub fn setPort(self: URL, value: []const u8) void {
    self.writeStringProp("port", value);
}

/// Copies `url.pathname` into `buf`.
/// https://developer.mozilla.org/en-US/docs/Web/API/URL/pathname
pub fn getPathname(self: URL, buf: []u8) []u8 {
    return self.readStringProp("pathname", buf);
}

/// Sets `url.pathname` to `value`.
/// https://developer.mozilla.org/en-US/docs/Web/API/URL/pathname
pub fn setPathname(self: URL, value: []const u8) void {
    self.writeStringProp("pathname", value);
}

/// Copies `url.search` into `buf`.
/// https://developer.mozilla.org/en-US/docs/Web/API/URL/search
pub fn getSearch(self: URL, buf: []u8) []u8 {
    return self.readStringProp("search", buf);
}

/// Sets `url.search` to `value`.
/// https://developer.mozilla.org/en-US/docs/Web/API/URL/search
pub fn setSearch(self: URL, value: []const u8) void {
    self.writeStringProp("search", value);
}

/// Copies `url.hash` into `buf`.
/// https://developer.mozilla.org/en-US/docs/Web/API/URL/hash
pub fn getHash(self: URL, buf: []u8) []u8 {
    return self.readStringProp("hash", buf);
}

/// Sets `url.hash` to `value`.
/// https://developer.mozilla.org/en-US/docs/Web/API/URL/hash
pub fn setHash(self: URL, value: []const u8) void {
    self.writeStringProp("hash", value);
}

/// Returns an owned `SearchParams` view over `url.searchParams`.
/// https://developer.mozilla.org/en-US/docs/Web/API/URL/searchParams
pub fn searchParams(self: URL) SearchParams {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return SearchParams.fromHandle(self.handle.get("searchParams", zjb.Handle));
}

/// Serializes the URL string via `url.toString()` into `buf`.
/// https://developer.mozilla.org/en-US/docs/Web/API/URL/toString
pub fn toString(self: URL, buf: []u8) []u8 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(buf.len > 0);
    const s_h = self.handle.call("toString", .{}, zjb.Handle);
    defer s_h.release();
    if (s_h.isNull()) return "";
    return webapi.stringFromHandle(s_h, buf);
}

/// Serializes the URL string via `url.toJSON()` into `buf`.
/// https://developer.mozilla.org/en-US/docs/Web/API/URL/toJSON
pub fn toJSON(self: URL, buf: []u8) []u8 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(buf.len > 0);
    const s_h = self.handle.call("toJSON", .{}, zjb.Handle);
    defer s_h.release();
    if (s_h.isNull()) return "";
    return webapi.stringFromHandle(s_h, buf);
}

// 8. Extra classes and constants

/// Type-safe wrapper for `URLSearchParams`.
/// https://developer.mozilla.org/en-US/docs/Web/API/URLSearchParams
pub const SearchParams = struct {
    handle: zjb.Handle,

    pub const @"null": SearchParams = .{ .handle = .null };

    /// Constructs a new `URLSearchParams` from an optional query string.
    pub fn init(query: ?[]const u8) SearchParams {
        const ctor = zjb.global("URLSearchParams");
        if (query) |q| {
            const q_s = zjb.string(q);
            defer q_s.release();
            return SearchParams.fromHandle(ctor.new(.{q_s}));
        }
        return SearchParams.fromHandle(ctor.new(.{}));
    }

    /// Wraps a non-null JS `URLSearchParams` handle.
    pub fn fromHandle(handle: zjb.Handle) SearchParams {
        std.debug.assert(!handle.isNull());
        std.debug.assert(@backingInt(handle) != 0);
        return .{ .handle = handle };
    }

    /// Returns true if the underlying JS handle is null or undefined.
    pub fn isNull(self: SearchParams) bool {
        return self.handle.isNull();
    }

    /// Releases the underlying JS handle.
    pub fn release(self: SearchParams) void {
        self.handle.release();
    }

    /// Returns the total number of search parameter entries.
    pub fn size(self: SearchParams) usize {
        std.debug.assert(!self.handle.isNull());
        std.debug.assert(@backingInt(self.handle) != 0);
        const raw = self.handle.get("size", i32);
        return if (raw > 0) @intCast(raw) else 0;
    }

    /// Appends a new `name=value` pair.
    pub fn append(self: SearchParams, name: []const u8, value: []const u8) void {
        std.debug.assert(!self.handle.isNull());
        std.debug.assert(name.len > 0);
        const name_s = zjb.string(name);
        defer name_s.release();
        const val_s = zjb.string(value);
        defer val_s.release();
        self.handle.call("append", .{ name_s, val_s }, void);
    }

    /// Deletes all entries matching `name`.
    pub fn delete(self: SearchParams, name: []const u8) void {
        std.debug.assert(!self.handle.isNull());
        std.debug.assert(name.len > 0);
        const name_s = zjb.string(name);
        defer name_s.release();
        self.handle.call("delete", .{name_s}, void);
    }

    /// Returns the first value associated with `name`, or null if missing.
    pub fn get(self: SearchParams, name: []const u8, buf: []u8) ?[]u8 {
        std.debug.assert(!self.handle.isNull());
        std.debug.assert(buf.len > 0);
        const name_s = zjb.string(name);
        defer name_s.release();
        const val_h = self.handle.call("get", .{name_s}, zjb.Handle);
        defer val_h.release();
        if (val_h.isNull()) return null;
        return webapi.stringFromHandle(val_h, buf);
    }

    /// Returns true if a parameter with `name` exists.
    pub fn has(self: SearchParams, name: []const u8) bool {
        std.debug.assert(!self.handle.isNull());
        std.debug.assert(name.len > 0);
        const name_s = zjb.string(name);
        defer name_s.release();
        return self.handle.call("has", .{name_s}, bool);
    }

    /// Sets `name` to `value`, removing any other values for `name`.
    pub fn set(self: SearchParams, name: []const u8, value: []const u8) void {
        std.debug.assert(!self.handle.isNull());
        std.debug.assert(name.len > 0);
        const name_s = zjb.string(name);
        defer name_s.release();
        const val_s = zjb.string(value);
        defer val_s.release();
        self.handle.call("set", .{ name_s, val_s }, void);
    }

    /// Sorts all key/value pairs in-place by key.
    pub fn sort(self: SearchParams) void {
        std.debug.assert(!self.handle.isNull());
        std.debug.assert(@backingInt(self.handle) != 0);
        self.handle.call("sort", .{}, void);
    }

    /// Serializes the query parameters into `buf`.
    pub fn toString(self: SearchParams, buf: []u8) []u8 {
        std.debug.assert(!self.handle.isNull());
        std.debug.assert(buf.len > 0);
        const s_h = self.handle.call("toString", .{}, zjb.Handle);
        defer s_h.release();
        if (s_h.isNull()) return "";
        return webapi.stringFromHandle(s_h, buf);
    }
};

// 9. Private declarations
fn isStringLike(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .pointer => |ptr| switch (ptr.size) {
            .slice => ptr.child == u8,
            .one => switch (@typeInfo(ptr.child)) {
                .array => |arr| arr.child == u8,
                else => false,
            },
            else => false,
        },
        else => false,
    };
}

fn unwrapHandle(val: anytype) zjb.Handle {
    const T = @TypeOf(val);
    if (T == zjb.Handle) return val;
    if (T == zjb.ConstHandle) return val.asHandle();
    if (@typeInfo(T) == .@"struct" and @hasField(T, "handle")) return val.handle;
    @compileError("expected Handle, ConstHandle, or struct with .handle");
}

fn readStringProp(self: URL, comptime prop: []const u8, buf: []u8) []u8 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(buf.len > 0);
    const h = self.handle.get(prop, zjb.Handle);
    defer h.release();
    if (h.isNull()) return "";
    return webapi.stringFromHandle(h, buf);
}

fn writeStringProp(self: URL, comptime prop: []const u8, value: []const u8) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@intFromPtr(value.ptr) != 0 or value.len == 0);
    const val_s = zjb.string(value);
    defer val_s.release();
    self.handle.set(prop, val_s);
}
