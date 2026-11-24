//! DragEvent Web API interface for drag-and-drop events.
//! Used by `"drag"`, `"dragstart"`, `"dragend"`, `"dragenter"`, `"dragover"`,
//! `"dragleave"`, and `"drop"` listeners (inherits MouseEvent).
//! https://developer.mozilla.org/en-US/docs/Web/API/DragEvent

// 1. Imports
const std = @import("std");
const webapi = @import("../webapi.zig");
const DataTransfer = @import("../dom/DataTransfer.zig");
const Event = @import("../Event.zig");
const MouseEvent = @import("MouseEvent.zig");

// 2. Shortcuts on imports
const DragEvent = @This();
const zjb = webapi.zjb;

// 3. File-level struct members
handle: zjb.Handle,
pub const @"null": DragEvent = .{ .handle = .null };

// 7. Public functions
/// Wraps a non-null JS DragEvent handle.
pub fn fromHandle(handle: zjb.Handle) DragEvent {
    std.debug.assert(!handle.isNull());
    std.debug.assert(@backingInt(handle) != 0);
    return .{ .handle = handle };
}

/// Views a base Event handle as a DragEvent.
pub fn fromEvent(ev: Event) DragEvent {
    std.debug.assert(!ev.isNull());
    std.debug.assert(@backingInt(ev.handle) != 0);
    return fromHandle(ev.handle);
}

/// Views a MouseEvent handle as a DragEvent.
pub fn fromMouseEvent(ev: MouseEvent) DragEvent {
    std.debug.assert(!ev.isNull());
    std.debug.assert(@backingInt(ev.handle) != 0);
    return fromHandle(ev.handle);
}

/// Returns a MouseEvent view over this DragEvent.
pub fn asMouseEvent(self: DragEvent) MouseEvent {
    return MouseEvent.fromHandle(self.handle);
}

/// Returns a base Event view over this DragEvent.
pub fn asEvent(self: DragEvent) Event {
    return Event.fromHandle(self.handle);
}

/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: DragEvent) bool {
    return self.handle.isNull();
}

/// Releases the underlying JS handle when owned.
pub fn release(self: DragEvent) void {
    self.handle.release();
}

/// Cancels default browser drag/drop handling if cancelable.
/// https://developer.mozilla.org/en-US/docs/Web/API/Event/preventDefault
pub fn preventDefault(self: DragEvent) void {
    self.asEvent().preventDefault();
}

/// Prevents further propagation of the DragEvent.
/// https://developer.mozilla.org/en-US/docs/Web/API/Event/stopPropagation
pub fn stopPropagation(self: DragEvent) void {
    self.asEvent().stopPropagation();
}

/// Returns the `DataTransfer` holding the dragged data and files (or `.null`).
/// https://developer.mozilla.org/en-US/docs/Web/API/DragEvent/dataTransfer
pub fn dataTransfer(self: DragEvent) DataTransfer {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const dt_h = self.handle.get("dataTransfer", zjb.Handle);
    if (dt_h.isNull()) {
        dt_h.release();
        return .null;
    }
    return DataTransfer.fromHandle(dt_h);
}
