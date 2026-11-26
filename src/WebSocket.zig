//! Type-safe wrapper for the browser `WebSocket` Web API.
//! https://developer.mozilla.org/en-US/docs/Web/API/WebSocket

// 1. Imports
const std = @import("std");
const webapi = @import("webapi.zig");

// 2. Shortcuts on imports
const WebSocket = @This();
const Blob = webapi.Blob;
const zjb = webapi.zjb;

pub const MessageEvent = webapi.Event.MessageEvent;
pub const CloseEvent = webapi.Event.CloseEvent;

// 3. File-level struct members
handle: zjb.Handle,

pub const @"null": WebSocket = .{ .handle = .null };

// 6. Types
/// Connection lifecycle state (`WebSocket.readyState`).
/// https://developer.mozilla.org/en-US/docs/Web/API/WebSocket/readyState
pub const ReadyState = enum(i32) {
    CONNECTING = 0,
    OPEN = 1,
    CLOSING = 2,
    CLOSED = 3,
    _,
};

/// Binary payload representation delivered to `"message"` events (`WebSocket.binaryType`).
/// https://developer.mozilla.org/en-US/docs/Web/API/WebSocket/binaryType
pub const BinaryType = enum {
    blob,
    arraybuffer,
};

/// Standard RFC 6455 WebSocket close status codes (`CloseEvent.code` / `WebSocket.close`).
/// https://developer.mozilla.org/en-US/docs/Web/API/CloseEvent/code
pub const CloseCode = enum(u16) {
    normal_closure = 1000,
    going_away = 1001,
    protocol_error = 1002,
    unsupported_data = 1003,
    no_status_received = 1005,
    abnormal_closure = 1006,
    invalid_frame_payload_data = 1007,
    policy_violation = 1008,
    message_too_big = 1009,
    mandatory_extension = 1010,
    internal_error = 1011,
    service_restart = 1012,
    try_again_later = 1013,
    bad_gateway = 1014,
    tls_handshake = 1015,
    _,
};

/// Connection options passed to `initWithOptions`.
pub const Options = struct {
    protocols: []const []const u8 = &.{},
    binary_type: ?BinaryType = null,
};

/// Graceful shutdown options passed to `closeWithOptions`.
pub const CloseOptions = struct {
    code: ?u16 = null,
    reason: ?[]const u8 = null,
};

// 7. Public functions
/// Returns true if the `WebSocket` constructor is available in the current global scope.
pub fn isSupported() bool {
    const cls = zjb.ConstHandle.global.get("WebSocket", zjb.Handle);
    defer cls.release();
    return !cls.isNull();
}

/// Opens a new `WebSocket` connection to `ws_url` (`ws://` or `wss://`).
/// https://developer.mozilla.org/en-US/docs/Web/API/WebSocket/WebSocket
pub fn init(ws_url: []const u8) WebSocket {
    std.debug.assert(ws_url.len > 0);
    const url_s = zjb.string(ws_url);
    defer url_s.release();
    return fromHandle(zjb.global("WebSocket").new(.{url_s}));
}

/// Opens a new `WebSocket` connection requesting a single `subprotocol`.
/// https://developer.mozilla.org/en-US/docs/Web/API/WebSocket/WebSocket
pub fn initWithProtocol(ws_url: []const u8, subprotocol: []const u8) WebSocket {
    std.debug.assert(ws_url.len > 0);
    std.debug.assert(subprotocol.len > 0);
    const url_s = zjb.string(ws_url);
    defer url_s.release();
    const proto_s = zjb.string(subprotocol);
    defer proto_s.release();
    return fromHandle(zjb.global("WebSocket").new(.{ url_s, proto_s }));
}

/// Opens a new `WebSocket` connection offering multiple `subprotocols` in preference order.
/// https://developer.mozilla.org/en-US/docs/Web/API/WebSocket/WebSocket
pub fn initWithProtocols(
    ws_url: []const u8,
    subprotocols: []const []const u8,
) WebSocket {
    std.debug.assert(ws_url.len > 0);
    const url_s = zjb.string(ws_url);
    defer url_s.release();
    const protos_arr = zjb.global("Array").new(.{});
    defer protos_arr.release();
    for (subprotocols) |proto| {
        const proto_s = zjb.string(proto);
        defer proto_s.release();
        protos_arr.call("push", .{proto_s}, void);
    }
    return fromHandle(zjb.global("WebSocket").new(.{ url_s, protos_arr }));
}

/// Opens a new `WebSocket` connection configured with `options` (`protocols` and `binary_type`).
pub fn initWithOptions(ws_url: []const u8, options: Options) WebSocket {
    const ws = if (options.protocols.len == 1)
        initWithProtocol(ws_url, options.protocols[0])
    else if (options.protocols.len > 1)
        initWithProtocols(ws_url, options.protocols)
    else
        init(ws_url);

    if (options.binary_type) |bt| {
        ws.setBinaryType(bt);
    }
    return ws;
}

/// Wraps a non-null JS `WebSocket` handle.
pub fn fromHandle(handle: zjb.Handle) WebSocket {
    std.debug.assert(!handle.isNull());
    std.debug.assert(@backingInt(handle) != 0);
    return .{ .handle = handle };
}

/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: WebSocket) bool {
    return self.handle.isNull();
}

/// Releases the underlying JS handle.
pub fn release(self: WebSocket) void {
    self.handle.release();
}

/// Returns the current connection state (`CONNECTING`, `OPEN`, `CLOSING`, `CLOSED`).
/// https://developer.mozilla.org/en-US/docs/Web/API/WebSocket/readyState
pub fn readyState(self: WebSocket) ReadyState {
    std.debug.assert(!self.handle.isNull());
    return @fromBackingInt(@intCast(self.handle.get("readyState", i32)));
}

/// Returns true if this handle is non-null and `readyState() == .OPEN`.
pub fn isOpen(self: WebSocket) bool {
    return !self.isNull() and self.readyState() == .OPEN;
}

/// Returns the number of bytes queued by `send*` calls but not yet transmitted to the network.
/// https://developer.mozilla.org/en-US/docs/Web/API/WebSocket/bufferedAmount
pub fn bufferedAmount(self: WebSocket) u64 {
    std.debug.assert(!self.handle.isNull());
    const raw = self.handle.get("bufferedAmount", f64);
    if (raw > 0.0 and raw < 1.8e19) {
        return @intFromFloat(raw);
    }
    return 0;
}

/// Returns the configured binary frame type (`blob` or `arraybuffer`).
/// https://developer.mozilla.org/en-US/docs/Web/API/WebSocket/binaryType
pub fn binaryType(self: WebSocket) ?BinaryType {
    std.debug.assert(!self.handle.isNull());
    var buf: [16]u8 = undefined;
    const s = readStringProp(self.handle, "binaryType", &buf);
    return std.meta.stringToEnum(BinaryType, s);
}

/// Sets the type of binary data delivered to `"message"` listeners (`blob` or `arraybuffer`).
/// https://developer.mozilla.org/en-US/docs/Web/API/WebSocket/binaryType
pub fn setBinaryType(self: WebSocket, binary_type: BinaryType) void {
    std.debug.assert(!self.handle.isNull());
    self.handle.set("binaryType", webapi.constTagName(binary_type));
}

/// Copies the resolved WebSocket URL (`ws.url`) into `buf`.
/// https://developer.mozilla.org/en-US/docs/Web/API/WebSocket/url
pub fn url(self: WebSocket, buf: []u8) []u8 {
    return readStringProp(self.handle, "url", buf);
}

/// Allocates and returns the resolved WebSocket URL (`ws.url`).
/// https://developer.mozilla.org/en-US/docs/Web/API/WebSocket/url
pub fn urlAlloc(self: WebSocket, allocator: std.mem.Allocator) ![]u8 {
    return readStringPropAlloc(self.handle, "url", allocator);
}

/// Copies the subprotocol selected by the server (`ws.protocol`) into `buf`.
/// https://developer.mozilla.org/en-US/docs/Web/API/WebSocket/protocol
pub fn protocol(self: WebSocket, buf: []u8) []u8 {
    return readStringProp(self.handle, "protocol", buf);
}

/// Allocates and returns the subprotocol selected by the server (`ws.protocol`).
/// https://developer.mozilla.org/en-US/docs/Web/API/WebSocket/protocol
pub fn protocolAlloc(self: WebSocket, allocator: std.mem.Allocator) ![]u8 {
    return readStringPropAlloc(self.handle, "protocol", allocator);
}

/// Copies the extensions negotiated with the server (`ws.extensions`) into `buf`.
/// https://developer.mozilla.org/en-US/docs/Web/API/WebSocket/extensions
pub fn extensions(self: WebSocket, buf: []u8) []u8 {
    return readStringProp(self.handle, "extensions", buf);
}

/// Allocates and returns the extensions negotiated with the server (`ws.extensions`).
/// https://developer.mozilla.org/en-US/docs/Web/API/WebSocket/extensions
pub fn extensionsAlloc(self: WebSocket, allocator: std.mem.Allocator) ![]u8 {
    return readStringPropAlloc(self.handle, "extensions", allocator);
}

/// Enqueues `data` to be transmitted as a binary WebSocket frame (`Uint8Array`).
/// https://developer.mozilla.org/en-US/docs/Web/API/WebSocket/send
pub fn send(self: WebSocket, data: []const u8) void {
    self.sendBytes(data);
}

/// Enqueues `data` to be transmitted as a binary WebSocket frame (`Uint8Array`).
/// https://developer.mozilla.org/en-US/docs/Web/API/WebSocket/send
pub fn sendBytes(self: WebSocket, data: []const u8) void {
    std.debug.assert(!self.handle.isNull());
    const view = zjb.u8ArrayView(data);
    defer view.release();
    self.handle.call("send", .{view}, void);
}

/// Enqueues UTF-8 `text` to be transmitted as a text WebSocket frame (`string`).
/// https://developer.mozilla.org/en-US/docs/Web/API/WebSocket/send
pub fn sendText(self: WebSocket, text: []const u8) void {
    std.debug.assert(!self.handle.isNull());
    const text_s = zjb.string(text);
    defer text_s.release();
    self.handle.call("send", .{text_s}, void);
}

/// Enqueues a `Blob` (or `File.asBlob()`) to be transmitted as a binary WebSocket frame.
/// https://developer.mozilla.org/en-US/docs/Web/API/WebSocket/send
pub fn sendBlob(self: WebSocket, blob: Blob) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(!blob.isNull());
    self.handle.call("send", .{blob.handle}, void);
}

/// Enqueues a raw JS payload handle (`ArrayBuffer`, `ArrayBufferView`, `Blob`, or `string`).
/// https://developer.mozilla.org/en-US/docs/Web/API/WebSocket/send
pub fn sendHandle(self: WebSocket, payload: zjb.Handle) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(!payload.isNull());
    self.handle.call("send", .{payload}, void);
}

/// Enqueues a JS `ArrayBuffer` or `ArrayBufferView` handle to be transmitted.
/// https://developer.mozilla.org/en-US/docs/Web/API/WebSocket/send
pub fn sendArrayBuffer(self: WebSocket, buffer: zjb.Handle) void {
    self.sendHandle(buffer);
}

/// Closes the WebSocket connection cleanly using default status.
/// https://developer.mozilla.org/en-US/docs/Web/API/WebSocket/close
pub fn close(self: WebSocket) void {
    std.debug.assert(!self.handle.isNull());
    self.handle.call("close", .{}, void);
}

/// Closes the WebSocket connection with an explicit status `code` (`1000` or `3000..4999`)
/// and optional UTF-8 `reason` (at most 123 bytes per RFC 6455).
/// https://developer.mozilla.org/en-US/docs/Web/API/WebSocket/close
pub fn closeWithCode(
    self: WebSocket,
    code: CloseCode,
    reason: ?[]const u8,
) void {
    self.closeWithOptions(.{
        .code = @backingInt(code),
        .reason = reason,
    });
}

/// Closes the WebSocket connection with optional numeric `code` and UTF-8 `reason`.
/// https://developer.mozilla.org/en-US/docs/Web/API/WebSocket/close
pub fn closeWithOptions(self: WebSocket, options: CloseOptions) void {
    std.debug.assert(!self.handle.isNull());
    if (options.code) |code| {
        const code_num: i32 = @intCast(code);
        if (options.reason) |r| {
            std.debug.assert(r.len <= 123);
            const reason_s = zjb.string(r);
            defer reason_s.release();
            self.handle.call("close", .{ code_num, reason_s }, void);
        } else {
            self.handle.call("close", .{code_num}, void);
        }
    } else {
        self.close();
    }
}

/// Attaches a context-bound listener receiving `webapi.Event.EventFor(event)`
/// (`"open"` -> `Event`, `"message"` -> `MessageEvent`, `"close"` -> `CloseEvent`, `"error"` -> `Event`).
pub fn addEventListener(
    self: WebSocket,
    comptime event: []const u8,
    comptime T: type,
    ctx: *T,
    comptime f: *const fn (*T, webapi.Event.EventFor(event)) void,
) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(event.len > 0);
    webapi.boundEventListenerTyped(
        T,
        webapi.Event.EventFor(event),
        event,
        self.handle,
        f,
        ctx,
    );
}

/// Attaches an owned-handle typed listener receiving `webapi.Event.EventFor(event)`.
pub fn addEventListenerOwned(
    self: WebSocket,
    comptime event: []const u8,
    comptime T: type,
    ctx: *T,
    comptime f: *const fn (*T, webapi.Event.EventFor(event)) void,
) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(event.len > 0);
    webapi.boundEventListenerTypedOwned(
        T,
        webapi.Event.EventFor(event),
        event,
        self.handle,
        f,
        ctx,
    );
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

fn readStringPropAlloc(
    h: zjb.Handle,
    comptime prop: []const u8,
    allocator: std.mem.Allocator,
) ![]u8 {
    std.debug.assert(!h.isNull());
    const val_h = h.get(prop, zjb.Handle);
    defer val_h.release();
    if (val_h.isNull()) return "";
    return try webapi.stringFromHandleAlloc(allocator, val_h);
}
