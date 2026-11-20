//! MessagePort Web API interface representing one endpoint of a MessageChannel.
//! Used by `MessageChannel`, `SharedWorker.port`, and `MessageEvent.ports`.
//! https://developer.mozilla.org/en-US/docs/Web/API/MessagePort

// 1. Imports
const std = @import("std");
const webapi = @import("../webapi.zig");

// 2. Shortcuts on imports
const MessagePort = @This();
const zjb = webapi.zjb;

// 3. File-level struct members
handle: zjb.Handle,
pub const @"null": MessagePort = .{ .handle = .null };

// 7. Public functions
/// Wraps a non-null JS MessagePort handle.
pub fn fromHandle(handle: zjb.Handle) MessagePort {
    std.debug.assert(!handle.isNull());
    std.debug.assert(@backingInt(handle) != 0);
    return .{ .handle = handle };
}

/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: MessagePort) bool {
    return self.handle.isNull();
}

/// Releases the underlying JS handle.
pub fn release(self: MessagePort) void {
    self.handle.release();
}

/// Sends a structured message handle through the port.
/// https://developer.mozilla.org/en-US/docs/Web/API/MessagePort/postMessage
pub fn postMessage(self: MessagePort, message: zjb.Handle) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(!message.isNull());
    self.handle.call("postMessage", .{message}, void);
}

/// Sends a structured message handle along with a JS array of transferables.
/// https://developer.mozilla.org/en-US/docs/Web/API/MessagePort/postMessage
pub fn postMessageWithTransfer(
    self: MessagePort,
    message: zjb.Handle,
    transfer: zjb.Handle,
) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(!message.isNull());
    std.debug.assert(!transfer.isNull());
    self.handle.call("postMessage", .{ message, transfer }, void);
}

/// Sends a UTF-8 text message through the port.
pub fn postText(self: MessagePort, text: []const u8) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@intFromPtr(text.ptr) != 0 or text.len == 0);
    const text_s = zjb.string(text);
    defer text_s.release();
    self.postMessage(text_s);
}

/// Sends raw bytes as a standalone `Uint8Array` copy through the port.
pub fn postBytes(self: MessagePort, data: []const u8) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@intFromPtr(data.ptr) != 0 or data.len == 0);
    const standalone = webapi.createStandaloneUint8Array(data);
    defer standalone.release();
    self.postMessage(standalone);
}

/// Starts queuing/dispatching messages received on this port (required when
/// using `addEventListener` instead of `onmessage`).
/// https://developer.mozilla.org/en-US/docs/Web/API/MessagePort/start
pub fn start(self: MessagePort) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    self.handle.call("start", .{}, void);
}

/// Disconnects the port so it is no longer active.
/// https://developer.mozilla.org/en-US/docs/Web/API/MessagePort/close
pub fn close(self: MessagePort) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    self.handle.call("close", .{}, void);
}

/// Attaches a context-bound listener receiving `webapi.Event.EventFor(ev)`.
pub fn addEventListener(
    self: MessagePort,
    comptime ev: []const u8,
    comptime Context: type,
    ctx: *Context,
    comptime f: *const fn (*Context, webapi.Event.EventFor(ev)) void,
) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(ev.len > 0);
    webapi.boundEventListenerTyped(
        Context,
        webapi.Event.EventFor(ev),
        ev,
        self.handle,
        f,
        ctx,
    );
}

/// Attaches an owned-handle typed listener receiving `webapi.Event.EventFor(ev)`.
pub fn addEventListenerOwned(
    self: MessagePort,
    comptime ev: []const u8,
    comptime Context: type,
    ctx: *Context,
    comptime f: *const fn (*Context, webapi.Event.EventFor(ev)) void,
) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(ev.len > 0);
    webapi.boundEventListenerTypedOwned(
        Context,
        webapi.Event.EventFor(ev),
        ev,
        self.handle,
        f,
        ctx,
    );
}
