//! ClipboardEvent Web API interface for clipboard cut/copy/paste events.
//! Used by `"paste"` listeners (inherits from Event).
//! https://developer.mozilla.org/en-US/docs/Web/API/ClipboardEvent
//! https://developer.mozilla.org/en-US/docs/Web/API/Element/paste_event

// 1. Imports
const std = @import("std");
const webapi = @import("../webapi.zig");
const DataTransfer = @import("../dom/DataTransfer.zig");
const Event = @import("../Event.zig");

// 2. Shortcuts on imports
const ClipboardEvent = @This();
const zjb = webapi.zjb;

// 3. File-level struct members
handle: zjb.Handle,
pub const @"null": ClipboardEvent = .{ .handle = .null };

// 7. Public functions
/// Wraps a non-null JS ClipboardEvent handle.
pub fn fromHandle(handle: zjb.Handle) ClipboardEvent {
    std.debug.assert(!handle.isNull());
    std.debug.assert(@backingInt(handle) != 0);
    return .{ .handle = handle };
}

/// Views a base Event handle as a ClipboardEvent.
pub fn fromEvent(ev: Event) ClipboardEvent {
    std.debug.assert(!ev.isNull());
    std.debug.assert(@backingInt(ev.handle) != 0);
    return fromHandle(ev.handle);
}

/// Returns a base Event view over this ClipboardEvent.
pub fn asEvent(self: ClipboardEvent) Event {
    return Event.fromHandle(self.handle);
}

/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: ClipboardEvent) bool {
    return self.handle.isNull();
}

/// Releases the underlying JS handle when owned.
pub fn release(self: ClipboardEvent) void {
    self.handle.release();
}

/// Cancels default browser clipboard handling if cancelable.
/// https://developer.mozilla.org/en-US/docs/Web/API/Event/preventDefault
pub fn preventDefault(self: ClipboardEvent) void {
    self.asEvent().preventDefault();
}

/// Prevents further propagation of the ClipboardEvent.
/// https://developer.mozilla.org/en-US/docs/Web/API/Event/stopPropagation
pub fn stopPropagation(self: ClipboardEvent) void {
    self.asEvent().stopPropagation();
}

/// Returns a DataTransfer handle holding data affected by the operation.
/// Docs: https://developer.mozilla.org/en-US/docs/Web/API/ClipboardEvent
pub fn clipboardData(self: ClipboardEvent) DataTransfer {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const data_h = self.handle.get("clipboardData", zjb.Handle);
    if (data_h.isNull()) {
        data_h.release();
        return .null;
    }
    return DataTransfer.fromHandle(data_h);
}
