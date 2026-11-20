//! Type-safe wrapper for the browser Web Workers API (`Worker`, `SharedWorker`,
//! `MessagePort`, `MessageChannel`, `DedicatedWorkerGlobalScope`,
//! `SharedWorkerGlobalScope`, `WorkerNavigator`, `WorkerLocation`).
//! https://developer.mozilla.org/en-US/docs/Web/API/Web_Workers_API

// 1. Imports
const std = @import("std");
const webapi = @import("webapi.zig");

pub const DedicatedWorkerGlobalScope =
    @import("Worker/DedicatedWorkerGlobalScope.zig");
pub const MessageChannel = @import("Worker/MessageChannel.zig");
pub const MessagePort = @import("Worker/MessagePort.zig");
pub const SharedWorker = @import("Worker/SharedWorker.zig");
pub const SharedWorkerGlobalScope =
    @import("Worker/SharedWorkerGlobalScope.zig");
pub const WorkerLocation = @import("Worker/WorkerLocation.zig");
pub const WorkerNavigator = @import("Worker/WorkerNavigator.zig");

// 2. Shortcuts on imports
const Worker = @This();
const zjb = webapi.zjb;

// 3. File-level struct members
handle: zjb.Handle,
pub const @"null": Worker = .{ .handle = .null };

// 7. Public functions
/// Returns true if `Worker` is available in the current global scope.
pub fn isSupported() bool {
    const cls = zjb.ConstHandle.global.get("Worker", zjb.Handle);
    defer cls.release();
    return !cls.isNull();
}

/// Spawns a dedicated background `Worker` executing `script_url`.
/// https://developer.mozilla.org/en-US/docs/Web/API/Worker/Worker
pub fn init(script_url: []const u8, options: ?Options) Worker {
    std.debug.assert(script_url.len > 0);
    const url_s = zjb.string(script_url);
    defer url_s.release();

    const ctor = zjb.global("Worker");
    if (options) |opt| {
        const opts_h = opt.toHandle();
        defer opts_h.release();
        return fromHandle(ctor.new(.{ url_s, opts_h }));
    }
    return fromHandle(ctor.new(.{url_s}));
}

/// Wraps a non-null JS Worker handle.
pub fn fromHandle(handle: zjb.Handle) Worker {
    std.debug.assert(!handle.isNull());
    std.debug.assert(@backingInt(handle) != 0);
    return .{ .handle = handle };
}

/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: Worker) bool {
    return self.handle.isNull();
}

/// Releases the underlying JS handle.
pub fn release(self: Worker) void {
    self.handle.release();
}

/// Sends a structured message handle to the worker's inner scope.
/// https://developer.mozilla.org/en-US/docs/Web/API/Worker/postMessage
pub fn postMessage(self: Worker, message: zjb.Handle) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(!message.isNull());
    self.handle.call("postMessage", .{message}, void);
}

/// Sends a structured message handle along with a JS array of transferables.
/// https://developer.mozilla.org/en-US/docs/Web/API/Worker/postMessage
pub fn postMessageWithTransfer(
    self: Worker,
    message: zjb.Handle,
    transfer: zjb.Handle,
) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(!message.isNull());
    std.debug.assert(!transfer.isNull());
    self.handle.call("postMessage", .{ message, transfer }, void);
}

/// Sends a UTF-8 text message to the worker's inner scope.
pub fn postText(self: Worker, text: []const u8) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@intFromPtr(text.ptr) != 0 or text.len == 0);
    const text_s = zjb.string(text);
    defer text_s.release();
    self.postMessage(text_s);
}

/// Sends raw bytes as a standalone `Uint8Array` copy to the worker's scope.
pub fn postBytes(self: Worker, data: []const u8) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@intFromPtr(data.ptr) != 0 or data.len == 0);
    const standalone = webapi.createStandaloneUint8Array(data);
    defer standalone.release();
    self.postMessage(standalone);
}

/// Immediately terminates the worker without letting pending operations finish.
/// https://developer.mozilla.org/en-US/docs/Web/API/Worker/terminate
pub fn terminate(self: Worker) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    self.handle.call("terminate", .{}, void);
}

/// Maps a Worker event name at compile time to its typed Event wrapper struct.
pub fn EventFor(comptime event_name: []const u8) type {
    if (std.mem.eql(u8, event_name, "error")) return webapi.Event.ErrorEvent;
    return webapi.Event.EventFor(event_name);
}

/// Attaches a context-bound listener receiving `Worker.EventFor(ev)`.
pub fn addEventListener(
    self: Worker,
    comptime ev: []const u8,
    comptime Context: type,
    ctx: *Context,
    comptime f: *const fn (*Context, EventFor(ev)) void,
) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(ev.len > 0);
    webapi.boundEventListenerTyped(
        Context,
        EventFor(ev),
        ev,
        self.handle,
        f,
        ctx,
    );
}

/// Attaches an owned-handle typed listener receiving `Worker.EventFor(ev)`.
pub fn addEventListenerOwned(
    self: Worker,
    comptime ev: []const u8,
    comptime Context: type,
    ctx: *Context,
    comptime f: *const fn (*Context, EventFor(ev)) void,
) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(ev.len > 0);
    webapi.boundEventListenerTypedOwned(
        Context,
        EventFor(ev),
        ev,
        self.handle,
        f,
        ctx,
    );
}

// 8. Extra classes and constants

/// Script evaluation mode for `Worker` and `SharedWorker`.
pub const Type = enum {
    classic,
    module,
};

/// Credentials policy when fetching a `module` worker script.
pub const Credentials = enum {
    omit,
    @"same-origin",
    include,
};

/// Configuration options passed to `Worker.init` and `SharedWorker.init`.
pub const Options = struct {
    type: ?Type = null,
    credentials: ?Credentials = null,
    name: ?[]const u8 = null,

    /// Converts these options into a JavaScript options object handle.
    pub fn toHandle(self: Options) zjb.Handle {
        const obj = zjb.global("Object").new(.{});
        std.debug.assert(!obj.isNull());
        std.debug.assert(@backingInt(obj) != 0);

        if (self.type) |t| {
            obj.set("type", webapi.constTagName(t));
        }
        if (self.credentials) |c| {
            obj.set("credentials", webapi.constTagName(c));
        }
        if (self.name) |n| {
            const name_s = zjb.string(n);
            defer name_s.release();
            obj.set("name", name_s);
        }
        return obj;
    }
};
