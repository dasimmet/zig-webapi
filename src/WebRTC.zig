//! WebRTC, WebSocket, and BroadcastChannel abstractions for zjb.
//!
//! Provides type-safe handle wrappers for browser networking APIs:
//! `RTCPeerConnection`, `RTCDataChannel`, `RTCSessionDescription`,
//! `RTCIceCandidate`, `WebSocket`, and `BroadcastChannel`, alongside
//! configuration structures (`RTCConfiguration`, `RTCIceServer`).

const std = @import("std");
const webapi = @import("webapi.zig");
const zjb = webapi.zjb;

/// Representation of an ICE server configuration in WebRTC (RTCIceServer).
/// https://developer.mozilla.org/en-US/docs/Web/API/RTCIceServer
pub const RTCIceServer = struct {
    urls: []const u8,
    username: ?[]const u8 = null,
    credential: ?[]const u8 = null,
};

/// WebRTC peer connection configuration (RTCConfiguration).
/// https://developer.mozilla.org/en-US/docs/Web/API/RTCConfiguration
pub const RTCConfiguration = struct {
    iceServers: []const RTCIceServer = &.{},
    iceCandidatePoolSize: u8 = 0,

    pub fn stringify(self: RTCConfiguration, buf: []u8) ![]const u8 {
        return try std.fmt.bufPrint(buf, "{f}", .{std.json.fmt(self, .{
            .emit_null_optional_fields = false,
        })});
    }

    pub fn stringifyAlloc(
        self: RTCConfiguration,
        allocator: std.mem.Allocator,
    ) ![]u8 {
        return try std.fmt.allocPrint(allocator, "{f}", .{std.json.fmt(self, .{
            .emit_null_optional_fields = false,
        })});
    }

    /// Converts this configuration into a JavaScript `RTCConfiguration` object.
    pub fn toJs(self: RTCConfiguration) zjb.Handle {
        const config = zjb.global("Object").new(.{});
        const ice_servers = zjb.global("Array").new(.{});
        defer ice_servers.release();

        for (self.iceServers) |server| {
            const s = zjb.global("Object").new(.{});
            defer s.release();
            const urls_s = zjb.string(server.urls);
            defer urls_s.release();
            s.set("urls", urls_s);
            if (server.username) |u| {
                const u_s = zjb.string(u);
                defer u_s.release();
                s.set("username", u_s);
            }
            if (server.credential) |c| {
                const c_s = zjb.string(c);
                defer c_s.release();
                s.set("credential", c_s);
            }
            ice_servers.call("push", .{s}, void);
        }
        config.set("iceServers", ice_servers);
        config.set("iceCandidatePoolSize", @as(i32, self.iceCandidatePoolSize));
        return config;
    }
};

/// Type-safe wrapper for a browser `RTCDataChannel`.
/// https://developer.mozilla.org/en-US/docs/Web/API/RTCDataChannel
pub const RTCDataChannel = struct {
    handle: zjb.Handle = .null,

    pub const @"null": RTCDataChannel = .{ .handle = .null };

    pub fn release(self: RTCDataChannel) void {
        self.handle.release();
    }

    pub fn isNull(self: RTCDataChannel) bool {
        return self.handle.isNull();
    }

    pub fn eql(self: RTCDataChannel, other: anytype) bool {
        const other_h: zjb.Handle = switch (@TypeOf(other)) {
            RTCDataChannel => other.handle,
            zjb.Handle => other,
            else => other.handle,
        };
        return self.handle.eql(other_h);
    }

    pub fn send(self: RTCDataChannel, data: []const u8) void {
        const view = zjb.u8ArrayView(data);
        defer view.release();
        self.handle.call("send", .{view}, void);
    }

    pub fn close(self: RTCDataChannel) void {
        self.handle.call("close", .{}, void);
    }

    pub fn setBinaryType(self: RTCDataChannel, binary_type: []const u8) void {
        const bt_s = zjb.string(binary_type);
        defer bt_s.release();
        self.handle.set("binaryType", bt_s);
    }

    pub fn readyState(self: RTCDataChannel) zjb.Handle {
        return self.handle.get("readyState", zjb.Handle);
    }

    pub fn isOpen(self: RTCDataChannel) bool {
        if (self.handle.isNull()) return false;
        const rs_h = self.readyState();
        defer rs_h.release();
        var buf: [16]u8 = undefined;
        const s = webapi.stringFromHandle(rs_h, &buf);
        return std.mem.eql(u8, s, "open");
    }

    /// Attaches a context-bound listener receiving `webapi.Event.EventFor(event)`.
    pub fn addEventListener(
        self: @This(),
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
        self: @This(),
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
};

/// Type-safe wrapper for a browser `RTCSessionDescription`.
/// https://developer.mozilla.org/en-US/docs/Web/API/RTCSessionDescription
pub const RTCSessionDescription = struct {
    handle: zjb.Handle = .null,

    pub const null_description: RTCSessionDescription = .{ .handle = .null };

    pub fn init(init_dict: zjb.Handle) RTCSessionDescription {
        return .{
            .handle = zjb.global("RTCSessionDescription").new(.{init_dict}),
        };
    }

    pub fn create(
        desc_type: []const u8,
        sdp_str: []const u8,
    ) RTCSessionDescription {
        const desc = zjb.global("Object").new(.{});
        defer desc.release();
        const type_s = zjb.string(desc_type);
        defer type_s.release();
        desc.set("type", type_s);
        const sdp_s = zjb.string(sdp_str);
        defer sdp_s.release();
        desc.set("sdp", sdp_s);
        return init(desc);
    }

    pub fn release(self: RTCSessionDescription) void {
        self.handle.release();
    }

    pub fn isNull(self: RTCSessionDescription) bool {
        return self.handle.isNull();
    }

    pub fn sdp(self: RTCSessionDescription) zjb.Handle {
        return self.handle.get("sdp", zjb.Handle);
    }

    pub fn @"type"(self: RTCSessionDescription) zjb.Handle {
        return self.handle.get("type", zjb.Handle);
    }
};

/// Type-safe wrapper for an `RTCIceCandidate`.
/// https://developer.mozilla.org/en-US/docs/Web/API/RTCIceCandidate
pub const RTCIceCandidate = struct {
    handle: zjb.Handle = .null,

    pub const null_candidate: RTCIceCandidate = .{ .handle = .null };

    pub fn release(self: RTCIceCandidate) void {
        self.handle.release();
    }

    pub fn isNull(self: RTCIceCandidate) bool {
        return self.handle.isNull();
    }

    pub fn candidate(self: RTCIceCandidate) zjb.Handle {
        return self.handle.get("candidate", zjb.Handle);
    }
};

/// Type-safe wrapper for a browser `RTCPeerConnection`.
/// https://developer.mozilla.org/en-US/docs/Web/API/RTCPeerConnection
pub const RTCPeerConnection = struct {
    handle: zjb.Handle = .null,

    pub const @"null": RTCPeerConnection = .{};

    pub fn init(config: zjb.Handle) RTCPeerConnection {
        return .{
            .handle = zjb.global("RTCPeerConnection").new(.{config}),
        };
    }

    pub fn release(self: RTCPeerConnection) void {
        self.handle.release();
    }

    pub fn isNull(self: RTCPeerConnection) bool {
        return self.handle.isNull();
    }

    pub fn eql(self: RTCPeerConnection, other: anytype) bool {
        const other_h: zjb.Handle = switch (@TypeOf(other)) {
            RTCPeerConnection => other.handle,
            zjb.Handle => other,
            else => other.handle,
        };
        return self.handle.eql(other_h);
    }

    pub fn close(self: RTCPeerConnection) void {
        self.handle.call("close", .{}, void);
    }

    pub fn createDataChannel(
        self: RTCPeerConnection,
        label: []const u8,
    ) RTCDataChannel {
        const label_s = zjb.string(label);
        defer label_s.release();
        return .{
            .handle = self.handle.call(
                "createDataChannel",
                .{label_s},
                zjb.Handle,
            ),
        };
    }

    /// Creates an SDP offer and invokes `on_ok` with the resulting
    /// `RTCSessionDescription` (or `on_err` on rejection).
    /// https://developer.mozilla.org/en-US/docs/Web/API/RTCPeerConnection/createOffer
    pub inline fn createOffer(
        self: RTCPeerConnection,
        comptime Context: type,
        ctx: *Context,
        comptime on_ok: ?*const fn (*Context, RTCSessionDescription) void,
        comptime on_err: ?*const fn (*Context, zjb.Handle) void,
    ) void {
        self.callPromiseMethod(
            "createOffer",
            .{},
            RTCSessionDescription,
            Context,
            ctx,
            on_ok,
            on_err,
        );
    }

    /// Creates an SDP answer and invokes `on_ok` with the resulting
    /// `RTCSessionDescription` (or `on_err` on rejection).
    /// https://developer.mozilla.org/en-US/docs/Web/API/RTCPeerConnection/createAnswer
    pub inline fn createAnswer(
        self: RTCPeerConnection,
        comptime Context: type,
        ctx: *Context,
        comptime on_ok: ?*const fn (*Context, RTCSessionDescription) void,
        comptime on_err: ?*const fn (*Context, zjb.Handle) void,
    ) void {
        self.callPromiseMethod(
            "createAnswer",
            .{},
            RTCSessionDescription,
            Context,
            ctx,
            on_ok,
            on_err,
        );
    }

    /// Sets the local session description and invokes `on_ok` when applied
    /// (or `on_err` on rejection).
    /// https://developer.mozilla.org/en-US/docs/Web/API/RTCPeerConnection/setLocalDescription
    pub inline fn setLocalDescription(
        self: RTCPeerConnection,
        desc: RTCSessionDescription,
        comptime Context: type,
        ctx: *Context,
        comptime on_ok: ?*const fn (*Context) void,
        comptime on_err: ?*const fn (*Context, zjb.Handle) void,
    ) void {
        self.callPromiseMethod(
            "setLocalDescription",
            .{desc.handle},
            void,
            Context,
            ctx,
            on_ok,
            on_err,
        );
    }

    /// Sets the remote session description and invokes `on_ok` when applied
    /// (or `on_err` on rejection).
    /// https://developer.mozilla.org/en-US/docs/Web/API/RTCPeerConnection/setRemoteDescription
    pub inline fn setRemoteDescription(
        self: RTCPeerConnection,
        desc: RTCSessionDescription,
        comptime Context: type,
        ctx: *Context,
        comptime on_ok: ?*const fn (*Context) void,
        comptime on_err: ?*const fn (*Context, zjb.Handle) void,
    ) void {
        self.callPromiseMethod(
            "setRemoteDescription",
            .{desc.handle},
            void,
            Context,
            ctx,
            on_ok,
            on_err,
        );
    }

    inline fn callPromiseMethod(
        self: RTCPeerConnection,
        comptime method: []const u8,
        args: anytype,
        comptime ResType: type,
        comptime Context: type,
        ctx: *Context,
        comptime on_ok: ?*const webapi.Promise.Typed(ResType).OkFn(Context),
        comptime on_err: ?*const fn (*Context, zjb.Handle) void,
    ) void {
        std.debug.assert(!self.handle.isNull());
        std.debug.assert(@backingInt(self.handle) != 0);
        const p_h = self.handle.call(method, args, zjb.Handle);
        const p = webapi.Promise.Typed(ResType).fromHandle(p_h);
        defer p.release();
        if (on_ok != null or on_err != null) {
            p.thenFn(Context, ctx, on_ok, on_err);
        }
    }

    pub fn connectionState(self: RTCPeerConnection) ConnectionState {
        if (self.handle.isNull()) return .unknown;
        const h = self.handle.get("connectionState", zjb.Handle);
        if (h.isNull()) return .unknown;
        defer h.release();
        var buf: [32]u8 = undefined;
        const s = webapi.stringFromHandle(h, &buf);
        return ConnectionState.fromString(s);
    }

    pub fn iceConnectionState(self: RTCPeerConnection) IceConnectionState {
        if (self.handle.isNull()) return .unknown;
        const h = self.handle.get("iceConnectionState", zjb.Handle);
        if (h.isNull()) return .unknown;
        defer h.release();
        var buf: [32]u8 = undefined;
        const s = webapi.stringFromHandle(h, &buf);
        return IceConnectionState.fromString(s);
    }

    pub fn signalingState(self: RTCPeerConnection) SignalingState {
        if (self.handle.isNull()) return .unknown;
        const h = self.handle.get("signalingState", zjb.Handle);
        if (h.isNull()) return .unknown;
        defer h.release();
        var buf: [32]u8 = undefined;
        const s = webapi.stringFromHandle(h, &buf);
        return SignalingState.fromString(s);
    }

    pub fn iceGatheringState(self: RTCPeerConnection) IceGatheringState {
        if (self.handle.isNull()) return .unknown;
        const h = self.handle.get("iceGatheringState", zjb.Handle);
        if (h.isNull()) return .unknown;
        defer h.release();
        var buf: [32]u8 = undefined;
        const s = webapi.stringFromHandle(h, &buf);
        return IceGatheringState.fromString(s);
    }

    pub fn localDescription(self: RTCPeerConnection) RTCSessionDescription {
        return .{
            .handle = self.handle.get("localDescription", zjb.Handle),
        };
    }

    /// Attaches a context-bound listener receiving `webapi.Event.EventFor(event)`.
    pub fn addEventListener(
        self: @This(),
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
        self: @This(),
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
};

/// Aggregate connection state of all ICE and DTLS transports in an
/// RTCPeerConnection.
/// https://developer.mozilla.org/en-US/docs/Web/API/RTCPeerConnection/connectionState
pub const ConnectionState = enum {
    new,
    connecting,
    connected,
    disconnected,
    failed,
    closed,
    unknown,

    pub fn fromString(str: []const u8) ConnectionState {
        inline for (comptime std.enums.values(ConnectionState)) |v| {
            if (std.mem.eql(u8, str, @tagName(v))) return v;
        }
        return .unknown;
    }
};

/// State of the ICE agent associated with an RTCPeerConnection.
/// https://developer.mozilla.org/en-US/docs/Web/API/RTCPeerConnection/iceConnectionState
pub const IceConnectionState = enum {
    new,
    checking,
    connected,
    completed,
    disconnected,
    failed,
    closed,
    unknown,

    pub fn fromString(str: []const u8) IceConnectionState {
        inline for (comptime std.enums.values(IceConnectionState)) |v| {
            if (std.mem.eql(u8, str, @tagName(v))) return v;
        }
        return .unknown;
    }
};

/// Aggregate signaling state of an RTCPeerConnection.
/// https://developer.mozilla.org/en-US/docs/Web/API/RTCPeerConnection/signalingState
pub const SignalingState = enum {
    stable,
    @"have-local-offer",
    @"have-remote-offer",
    @"have-local-pranswer",
    @"have-remote-pranswer",
    closed,
    unknown,

    pub fn fromString(str: []const u8) SignalingState {
        inline for (comptime std.enums.values(SignalingState)) |v| {
            if (std.mem.eql(u8, str, @tagName(v))) return v;
        }
        return .unknown;
    }
};

/// State of the ICE gathering process on an RTCPeerConnection.
/// https://developer.mozilla.org/en-US/docs/Web/API/RTCPeerConnection/iceGatheringState
pub const IceGatheringState = enum {
    new,
    gathering,
    complete,
    unknown,

    pub fn fromString(str: []const u8) IceGatheringState {
        inline for (comptime std.enums.values(IceGatheringState)) |v| {
            if (std.mem.eql(u8, str, @tagName(v))) return v;
        }
        return .unknown;
    }
};
