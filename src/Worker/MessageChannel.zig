//! MessageChannel Web API interface creating a pair of connected MessagePorts.
//! https://developer.mozilla.org/en-US/docs/Web/API/MessageChannel

// 1. Imports
const std = @import("std");
const webapi = @import("../webapi.zig");
const MessagePort = @import("MessagePort.zig");

// 2. Shortcuts on imports
const MessageChannel = @This();
const zjb = webapi.zjb;

// 3. File-level struct members
handle: zjb.Handle = .null,

// 7. Public functions
/// Returns true if `MessageChannel` is available in the current global scope.
pub fn isSupported() bool {
    const cls = zjb.ConstHandle.global.get("MessageChannel", zjb.Handle);
    defer cls.release();
    return !cls.isNull();
}

/// Constructs a new `MessageChannel` with two entangled `MessagePort`s.
/// https://developer.mozilla.org/en-US/docs/Web/API/MessageChannel/MessageChannel
pub fn init() MessageChannel {
    const h = zjb.global("MessageChannel").new(.{});
    std.debug.assert(!h.isNull());
    std.debug.assert(@backingInt(h) != 0);
    return .{ .handle = h };
}

/// Wraps a non-null JS MessageChannel handle.
pub fn fromHandle(handle: zjb.Handle) MessageChannel {
    std.debug.assert(!handle.isNull());
    std.debug.assert(@backingInt(handle) != 0);
    return .{ .handle = handle };
}

/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: MessageChannel) bool {
    return self.handle.isNull();
}

/// Releases the underlying JS handle.
pub fn release(self: MessageChannel) void {
    self.handle.release();
}

/// Returns an owned handle to the first `MessagePort` of the channel.
/// https://developer.mozilla.org/en-US/docs/Web/API/MessageChannel/port1
pub fn port1(self: MessageChannel) MessagePort {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return .{ .handle = self.handle.get("port1", zjb.Handle) };
}

/// Returns an owned handle to the second `MessagePort` of the channel.
/// https://developer.mozilla.org/en-US/docs/Web/API/MessageChannel/port2
pub fn port2(self: MessageChannel) MessagePort {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return .{ .handle = self.handle.get("port2", zjb.Handle) };
}

// 8. Extra classes and constants
pub const @"null": MessageChannel = .{};
