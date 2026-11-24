//! DataTransfer Web API interface used by clipboard and drag-and-drop events.
//! Integrates with `webapi.File` and `webapi.File.List` via `files()`, `items()`,
//! `addFile()`, and `Item.getAsFile()`.
//! https://developer.mozilla.org/en-US/docs/Web/API/DataTransfer

// 1. Imports
const std = @import("std");
const webapi = @import("../webapi.zig");

// 2. Shortcuts on imports
const DataTransfer = @This();
const File = webapi.File;
const zjb = webapi.zjb;

// 3. File-level struct members
handle: zjb.Handle,
pub const @"null": DataTransfer = .{ .handle = .null };

// 6. Types
/// Visual feedback / operation type for drag-and-drop (`dataTransfer.dropEffect`).
/// https://developer.mozilla.org/en-US/docs/Web/API/DataTransfer/dropEffect
pub const DropEffect = enum {
    none,
    copy,
    link,
    move,
};

/// Operations allowed for a drag source (`dataTransfer.effectAllowed`).
/// https://developer.mozilla.org/en-US/docs/Web/API/DataTransfer/effectAllowed
pub const EffectAllowed = enum {
    none,
    copy,
    copyLink,
    copyMove,
    link,
    linkMove,
    move,
    all,
    uninitialized,
};

/// Discriminator for a `DataTransferItem` (`item.kind`).
pub const ItemKind = enum {
    string,
    file,
};

/// Type-safe wrapper for a single `DataTransferItem` entry.
/// https://developer.mozilla.org/en-US/docs/Web/API/DataTransferItem
pub const Item = struct {
    handle: zjb.Handle,
    pub const @"null": Item = .{ .handle = .null };

    /// Wraps a non-null JS `DataTransferItem` handle.
    pub fn fromHandle(handle: zjb.Handle) Item {
        std.debug.assert(!handle.isNull());
        std.debug.assert(@backingInt(handle) != 0);
        return .{ .handle = handle };
    }

    /// Returns true if the underlying JS handle is null or undefined.
    pub fn isNull(self: Item) bool {
        return self.handle.isNull();
    }

    /// Releases the underlying JS handle.
    pub fn release(self: Item) void {
        self.handle.release();
    }

    /// Returns the item kind (`string` or `file`), or `null` if unknown.
    /// https://developer.mozilla.org/en-US/docs/Web/API/DataTransferItem/kind
    pub fn kind(self: Item) ?ItemKind {
        std.debug.assert(!self.handle.isNull());
        var buf: [16]u8 = undefined;
        const s = readStringProp(self.handle, "kind", &buf);
        return std.meta.stringToEnum(ItemKind, s);
    }

    /// Copies the MIME type string (`item.type`) into `buf`.
    /// https://developer.mozilla.org/en-US/docs/Web/API/DataTransferItem/type
    pub fn mimeType(self: Item, buf: []u8) []u8 {
        return readStringProp(self.handle, "type", buf);
    }

    /// Returns the item's `File` object if `kind == .file`, or `null` otherwise.
    /// https://developer.mozilla.org/en-US/docs/Web/API/DataTransferItem/getAsFile
    pub fn getAsFile(self: Item) ?File {
        std.debug.assert(!self.handle.isNull());
        std.debug.assert(@backingInt(self.handle) != 0);
        const f_h = self.handle.call("getAsFile", .{}, zjb.Handle);
        if (f_h.isNull()) {
            f_h.release();
            return null;
        }
        return File.fromHandle(f_h);
    }

    /// Invokes `callback` with the string payload when `kind == .string`.
    /// https://developer.mozilla.org/en-US/docs/Web/API/DataTransferItem/getAsString
    pub fn getAsString(
        self: Item,
        comptime Context: type,
        ctx: *Context,
        comptime on_string: *const fn (*Context, zjb.Handle) void,
    ) void {
        std.debug.assert(!self.handle.isNull());
        std.debug.assert(@backingInt(self.handle) != 0);
        const cb = webapi.boundFunction(Context, ctx, on_string);
        defer cb.release();
        self.handle.call("getAsString", .{cb}, void);
    }
};

/// Typed view/iterator over `DataTransferItemList` (`dataTransfer.items`).
/// https://developer.mozilla.org/en-US/docs/Web/API/DataTransferItemList
pub const ItemList = struct {
    handle: zjb.Handle,
    pos: usize = 0,
    pub const @"null": ItemList = .{ .handle = .null };

    /// Wraps a non-null JS `DataTransferItemList` handle.
    pub fn fromHandle(handle: zjb.Handle) ItemList {
        std.debug.assert(!handle.isNull());
        std.debug.assert(@backingInt(handle) != 0);
        return .{ .handle = handle };
    }

    /// Returns true if the underlying JS handle is null or undefined.
    pub fn isNull(self: ItemList) bool {
        return self.handle.isNull();
    }

    /// Releases the underlying JS handle.
    pub fn release(self: ItemList) void {
        self.handle.release();
    }

    /// Returns the number of items in the list (`items.length`).
    pub fn len(self: ItemList) usize {
        if (self.handle.isNull()) return 0;
        const raw = self.handle.get("length", i32);
        return if (raw > 0) @intCast(raw) else 0;
    }

    /// Returns an owned `Item` at `idx`, or `null` if out of bounds.
    pub fn get(self: ItemList, idx: usize) ?Item {
        if (idx >= self.len()) return null;
        const item_h = self.handle.indexGet(@as(i32, @intCast(idx)), zjb.Handle);
        if (item_h.isNull()) {
            item_h.release();
            return null;
        }
        return Item.fromHandle(item_h);
    }

    /// Returns the next owned `Item` or `null` when exhausted.
    pub fn next(self: *ItemList) ?Item {
        const cur = self.pos;
        if (cur >= self.len()) return null;
        self.pos += 1;
        return self.get(cur);
    }

    /// Adds a `File` to the drag/transfer item list and returns the created `Item` (or `null`).
    /// https://developer.mozilla.org/en-US/docs/Web/API/DataTransferItemList/add
    pub fn addFile(self: ItemList, file: File) ?Item {
        std.debug.assert(!self.handle.isNull());
        std.debug.assert(!file.isNull());
        const item_h = self.handle.call("add", .{file.handle}, zjb.Handle);
        if (item_h.isNull()) {
            item_h.release();
            return null;
        }
        return Item.fromHandle(item_h);
    }

    /// Adds a string item with the given `mime_type` and returns the created `Item` (or `null`).
    /// https://developer.mozilla.org/en-US/docs/Web/API/DataTransferItemList/add
    pub fn addText(self: ItemList, data: []const u8, mime_type: []const u8) ?Item {
        std.debug.assert(!self.handle.isNull());
        std.debug.assert(mime_type.len > 0);
        const data_s = zjb.string(data);
        defer data_s.release();
        const type_s = zjb.string(mime_type);
        defer type_s.release();
        const item_h = self.handle.call("add", .{ data_s, type_s }, zjb.Handle);
        if (item_h.isNull()) {
            item_h.release();
            return null;
        }
        return Item.fromHandle(item_h);
    }

    /// Removes the item at `idx` from the list.
    /// https://developer.mozilla.org/en-US/docs/Web/API/DataTransferItemList/remove
    pub fn remove(self: ItemList, idx: usize) void {
        std.debug.assert(!self.handle.isNull());
        self.handle.call("remove", .{@as(i32, @intCast(idx))}, void);
    }

    /// Removes all items from the list.
    /// https://developer.mozilla.org/en-US/docs/Web/API/DataTransferItemList/clear
    pub fn clear(self: ItemList) void {
        std.debug.assert(!self.handle.isNull());
        self.handle.call("clear", .{}, void);
    }
};

// 7. Public functions
/// Returns true if the `DataTransfer` constructor is available in the global scope.
pub fn isSupported() bool {
    const cls = zjb.ConstHandle.global.get("DataTransfer", zjb.Handle);
    defer cls.release();
    return !cls.isNull();
}

/// Creates a new empty `DataTransfer` instance (`new DataTransfer()`).
/// https://developer.mozilla.org/en-US/docs/Web/API/DataTransfer/DataTransfer
pub fn init() DataTransfer {
    const h = zjb.global("DataTransfer").new(.{});
    return fromHandle(h);
}

/// Wraps a non-null JS `DataTransfer` handle.
pub fn fromHandle(handle: zjb.Handle) DataTransfer {
    std.debug.assert(!handle.isNull());
    std.debug.assert(@backingInt(handle) != 0);
    return .{ .handle = handle };
}

/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: DataTransfer) bool {
    return self.handle.isNull();
}

/// Releases the underlying JS handle.
pub fn release(self: DataTransfer) void {
    self.handle.release();
}

/// Returns a `File.List` of all local files available on this `DataTransfer`.
/// https://developer.mozilla.org/en-US/docs/Web/API/DataTransfer/files
pub fn files(self: DataTransfer) File.List {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const list_h = self.handle.get("files", zjb.Handle);
    if (list_h.isNull()) {
        list_h.release();
        return .null;
    }
    return File.List.fromHandle(list_h);
}

/// Returns the `ItemList` (`dataTransfer.items`) for inspecting or adding drag items and files.
/// https://developer.mozilla.org/en-US/docs/Web/API/DataTransfer/items
pub fn items(self: DataTransfer) ItemList {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const list_h = self.handle.get("items", zjb.Handle);
    if (list_h.isNull()) {
        list_h.release();
        return .null;
    }
    return ItemList.fromHandle(list_h);
}

/// Convenience helper that appends `file` to `dataTransfer.items` and returns
/// the resulting `Item` (or `null` if unavailable).
pub fn addFile(self: DataTransfer, file: File) ?Item {
    const item_list = self.items();
    if (item_list.isNull()) return null;
    defer item_list.release();
    return item_list.addFile(file);
}

/// Returns the current `dropEffect`, or `null` if unrecognized.
/// https://developer.mozilla.org/en-US/docs/Web/API/DataTransfer/dropEffect
pub fn dropEffect(self: DataTransfer) ?DropEffect {
    std.debug.assert(!self.handle.isNull());
    var buf: [16]u8 = undefined;
    const s = readStringProp(self.handle, "dropEffect", &buf);
    return std.meta.stringToEnum(DropEffect, s);
}

/// Sets `dataTransfer.dropEffect`.
/// https://developer.mozilla.org/en-US/docs/Web/API/DataTransfer/dropEffect
pub fn setDropEffect(self: DataTransfer, effect: DropEffect) void {
    std.debug.assert(!self.handle.isNull());
    self.handle.set("dropEffect", webapi.constTagName(effect));
}

/// Returns the current `effectAllowed`, or `null` if unrecognized.
/// https://developer.mozilla.org/en-US/docs/Web/API/DataTransfer/effectAllowed
pub fn effectAllowed(self: DataTransfer) ?EffectAllowed {
    std.debug.assert(!self.handle.isNull());
    var buf: [24]u8 = undefined;
    const s = readStringProp(self.handle, "effectAllowed", &buf);
    return std.meta.stringToEnum(EffectAllowed, s);
}

/// Sets `dataTransfer.effectAllowed`.
/// https://developer.mozilla.org/en-US/docs/Web/API/DataTransfer/effectAllowed
pub fn setEffectAllowed(self: DataTransfer, effect: EffectAllowed) void {
    std.debug.assert(!self.handle.isNull());
    self.handle.set("effectAllowed", webapi.constTagName(effect));
}

/// Retrieves drag/clipboard data for MIME `format` into an owned buffer.
/// https://developer.mozilla.org/en-US/docs/Web/API/DataTransfer/getData
pub fn getDataAlloc(
    self: DataTransfer,
    allocator: std.mem.Allocator,
    format: []const u8,
) !?[]u8 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(format.len > 0);
    const fmt_h = zjb.string(format);
    defer fmt_h.release();
    const text_h = self.handle.call("getData", .{fmt_h}, zjb.Handle);
    if (text_h.isNull()) {
        text_h.release();
        return null;
    }
    defer text_h.release();
    const enc = webapi.codec.encode(text_h);
    defer enc.release();
    return try webapi.bytesFromHandleAlloc(allocator, enc);
}

/// Sets drag/clipboard data for MIME `format` to `data`.
/// https://developer.mozilla.org/en-US/docs/Web/API/DataTransfer/setData
pub fn setData(self: DataTransfer, format: []const u8, data: []const u8) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(format.len > 0);
    const fmt_s = zjb.string(format);
    defer fmt_s.release();
    const data_s = zjb.string(data);
    defer data_s.release();
    self.handle.call("setData", .{ fmt_s, data_s }, void);
}

/// Clears drag/clipboard data for `format`, or all data when `format` is `null`.
/// https://developer.mozilla.org/en-US/docs/Web/API/DataTransfer/clearData
pub fn clearData(self: DataTransfer, format: ?[]const u8) void {
    std.debug.assert(!self.handle.isNull());
    if (format) |fmt| {
        std.debug.assert(fmt.len > 0);
        const fmt_s = zjb.string(fmt);
        defer fmt_s.release();
        self.handle.call("clearData", .{fmt_s}, void);
    } else {
        self.handle.call("clearData", .{}, void);
    }
}

/// Returns an owned JS handle to `dataTransfer.types` (`ReadonlyArray<string>`).
/// https://developer.mozilla.org/en-US/docs/Web/API/DataTransfer/types
pub fn types(self: DataTransfer) zjb.Handle {
    std.debug.assert(!self.handle.isNull());
    return self.handle.get("types", zjb.Handle);
}

// 9. Private helpers
fn readStringProp(h: zjb.Handle, comptime prop: []const u8, buf: []u8) []u8 {
    std.debug.assert(!h.isNull());
    std.debug.assert(buf.len > 0);
    const val_h = h.get(prop, zjb.Handle);
    defer val_h.release();
    if (val_h.isNull()) return "";
    return webapi.stringFromHandle(val_h, buf);
}
