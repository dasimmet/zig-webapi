//! Type-safe wrapper for `navigator.mediaDevices` (`MediaDevices`), providing
//! microphone, camera, and screen capture (`getUserMedia`, `getDisplayMedia`)
//! as well as audio/video device enumeration (`enumerateDevices`).
//! https://developer.mozilla.org/en-US/docs/Web/API/MediaDevices

// 1. Imports
const std = @import("std");
const webapi = @import("../webapi.zig");
const MediaDeviceInfo = @import("MediaDeviceInfo.zig");
const MediaStream = @import("../MediaStream.zig");

// 2. Shortcuts on imports
const MediaDevices = @This();
const Event = webapi.Event;
const Promise = webapi.Promise;
const zjb = webapi.zjb;

// 3. File-level struct members
handle: zjb.Handle,
pub const @"null": MediaDevices = .{ .handle = .null };

// 7. Public functions
/// Returns true if `navigator.mediaDevices` is available (requires HTTPS or localhost).
pub fn isSupported() bool {
    const h = zjb.global("navigator").get("mediaDevices", zjb.Handle);
    defer h.release();
    return !h.isNull();
}

/// Returns true if `navigator.mediaDevices.getUserMedia` is available.
pub fn isGetUserMediaSupported() bool {
    const md = fromNavigator();
    if (md.isNull()) return false;
    defer md.release();
    const fn_h = md.handle.get("getUserMedia", zjb.Handle);
    defer fn_h.release();
    return !fn_h.isNull();
}

/// Returns true if `navigator.mediaDevices.getDisplayMedia` is available.
pub fn isGetDisplayMediaSupported() bool {
    const md = fromNavigator();
    if (md.isNull()) return false;
    defer md.release();
    const fn_h = md.handle.get("getDisplayMedia", zjb.Handle);
    defer fn_h.release();
    return !fn_h.isNull();
}

/// Acquires an owned `MediaDevices` handle from `navigator.mediaDevices`, or `.null`.
/// Caller must call `.release()` when non-null.
/// https://developer.mozilla.org/en-US/docs/Web/API/Navigator/mediaDevices
pub fn fromNavigator() MediaDevices {
    const h = zjb.global("navigator").get("mediaDevices", zjb.Handle);
    if (h.isNull()) return .null;
    return fromHandle(h);
}

/// Wraps a non-null JS `MediaDevices` handle.
pub fn fromHandle(handle: zjb.Handle) MediaDevices {
    std.debug.assert(!handle.isNull());
    std.debug.assert(@backingInt(handle) != 0);
    return .{ .handle = handle };
}

/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: MediaDevices) bool {
    return self.handle.isNull();
}

/// Releases the underlying JS handle.
pub fn release(self: MediaDevices) void {
    self.handle.release();
}

/// Prompts the user for permission to capture audio and/or video input matching
/// `constraints`, returning a `Promise.Typed(MediaStream)` or `null` if unsupported.
/// Caller must `.release()` the returned `Promise`.
/// https://developer.mozilla.org/en-US/docs/Web/API/MediaDevices/getUserMedia
pub fn getUserMedia(
    self: MediaDevices,
    constraints: Constraints,
) ?Promise.Typed(MediaStream) {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const fn_h = self.handle.get("getUserMedia", zjb.Handle);
    defer fn_h.release();
    if (fn_h.isNull()) return null;

    const c_h = constraints.toHandle();
    defer c_h.release();
    const p_h = self.handle.call("getUserMedia", .{c_h}, zjb.Handle);
    if (p_h.isNull()) {
        p_h.release();
        return null;
    }
    return .fromHandle(p_h);
}

/// Prompts the user to select a screen, window, or tab to capture, returning a
/// `Promise.Typed(MediaStream)` or `null` if unsupported.
/// Caller must `.release()` the returned `Promise`.
/// https://developer.mozilla.org/en-US/docs/Web/API/MediaDevices/getDisplayMedia
pub fn getDisplayMedia(
    self: MediaDevices,
    constraints: ?DisplayConstraints,
) ?Promise.Typed(MediaStream) {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const fn_h = self.handle.get("getDisplayMedia", zjb.Handle);
    defer fn_h.release();
    if (fn_h.isNull()) return null;

    const p_h = if (constraints) |c| blk: {
        const c_h = c.toHandle();
        defer c_h.release();
        break :blk self.handle.call("getDisplayMedia", .{c_h}, zjb.Handle);
    } else self.handle.call("getDisplayMedia", .{}, zjb.Handle);

    if (p_h.isNull()) {
        p_h.release();
        return null;
    }
    return .fromHandle(p_h);
}

/// Requests a list of available audio and video input/output devices.
/// Caller must `.release()` the returned `Promise`.
/// https://developer.mozilla.org/en-US/docs/Web/API/MediaDevices/enumerateDevices
pub fn enumerateDevices(self: MediaDevices) ?Promise.Typed(MediaDeviceInfo.List) {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const fn_h = self.handle.get("enumerateDevices", zjb.Handle);
    defer fn_h.release();
    if (fn_h.isNull()) return null;

    const p_h = self.handle.call("enumerateDevices", .{}, zjb.Handle);
    if (p_h.isNull()) {
        p_h.release();
        return null;
    }
    return .fromHandle(p_h);
}

/// Attaches a typed listener (e.g. `"devicechange"`).
/// https://developer.mozilla.org/en-US/docs/Web/API/MediaDevices/devicechange_event
pub fn addEventListener(
    self: MediaDevices,
    comptime event: []const u8,
    comptime T: type,
    ctx: *T,
    comptime f: *const fn (*T, Event.EventFor(event)) void,
) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(event.len > 0);
    webapi.boundEventListenerTyped(
        T,
        Event.EventFor(event),
        event,
        self.handle,
        f,
        ctx,
    );
}

// 8. Extra classes
/// Camera direction preference accepted by `VideoTrackConstraints.facing_mode`.
/// https://developer.mozilla.org/en-US/docs/Web/API/MediaTrackConstraints/facingMode
pub const FacingMode = enum {
    user,
    environment,
    left,
    right,
};

/// Audio capture constraints (`MediaTrackConstraints`) for `getUserMedia`.
/// https://developer.mozilla.org/en-US/docs/Web/API/MediaTrackConstraints#instance_properties_of_audio_tracks
pub const AudioTrackConstraints = struct {
    device_id: ?[]const u8 = null,
    echo_cancellation: ?bool = null,
    noise_suppression: ?bool = null,
    auto_gain_control: ?bool = null,
    sample_rate: ?u32 = null,
    channel_count: ?u32 = null,

    /// Converts these audio constraints into a JS `MediaTrackConstraints` handle.
    pub fn toHandle(self: AudioTrackConstraints) zjb.Handle {
        const obj = zjb.global("Object").new(.{});
        std.debug.assert(!obj.isNull());
        std.debug.assert(@backingInt(obj) != 0);
        if (self.device_id) |id_str| {
            const s = zjb.string(id_str);
            defer s.release();
            obj.set("deviceId", s);
        }
        if (self.echo_cancellation) |v| obj.set("echoCancellation", v);
        if (self.noise_suppression) |v| obj.set("noiseSuppression", v);
        if (self.auto_gain_control) |v| obj.set("autoGainControl", v);
        if (self.sample_rate) |sr| obj.set("sampleRate", @as(i32, @intCast(sr)));
        if (self.channel_count) |ch| {
            obj.set("channelCount", @as(i32, @intCast(ch)));
        }
        return obj;
    }
};

/// Video capture constraints (`MediaTrackConstraints`) for `getUserMedia`.
/// https://developer.mozilla.org/en-US/docs/Web/API/MediaTrackConstraints#instance_properties_of_video_tracks
pub const VideoTrackConstraints = struct {
    device_id: ?[]const u8 = null,
    width: ?u32 = null,
    height: ?u32 = null,
    frame_rate: ?f64 = null,
    facing_mode: ?FacingMode = null,

    /// Converts these video constraints into a JS `MediaTrackConstraints` handle.
    pub fn toHandle(self: VideoTrackConstraints) zjb.Handle {
        const obj = zjb.global("Object").new(.{});
        std.debug.assert(!obj.isNull());
        std.debug.assert(@backingInt(obj) != 0);
        if (self.device_id) |id_str| {
            const s = zjb.string(id_str);
            defer s.release();
            obj.set("deviceId", s);
        }
        if (self.width) |w| obj.set("width", @as(i32, @intCast(w)));
        if (self.height) |h| obj.set("height", @as(i32, @intCast(h)));
        if (self.frame_rate) |fps| obj.set("frameRate", fps);
        if (self.facing_mode) |fm| {
            obj.set("facingMode", webapi.constTagName(fm));
        }
        return obj;
    }
};

/// Audio request selector in `MediaDevices.Constraints`.
pub const AudioConstraint = union(enum) {
    disabled,
    enabled,
    constraints: AudioTrackConstraints,
};

/// Video request selector in `MediaDevices.Constraints`.
pub const VideoConstraint = union(enum) {
    disabled,
    enabled,
    constraints: VideoTrackConstraints,
};

/// Top-level `MediaStreamConstraints` dictionary passed to `getUserMedia`.
/// At least one of `audio` or `video` must not be `.disabled`.
/// https://developer.mozilla.org/en-US/docs/Web/API/MediaStreamConstraints
pub const Constraints = struct {
    audio: AudioConstraint = .disabled,
    video: VideoConstraint = .disabled,

    /// Converts these constraints into a JS `MediaStreamConstraints` object.
    pub fn toHandle(self: Constraints) zjb.Handle {
        const obj = zjb.global("Object").new(.{});
        std.debug.assert(!obj.isNull());
        std.debug.assert(@backingInt(obj) != 0);

        switch (self.audio) {
            .disabled => obj.set("audio", false),
            .enabled => obj.set("audio", true),
            .constraints => |ac| {
                const ac_h = ac.toHandle();
                defer ac_h.release();
                obj.set("audio", ac_h);
            },
        }
        switch (self.video) {
            .disabled => obj.set("video", false),
            .enabled => obj.set("video", true),
            .constraints => |vc| {
                const vc_h = vc.toHandle();
                defer vc_h.release();
                obj.set("video", vc_h);
            },
        }
        return obj;
    }
};

/// Options dictionary (`DisplayMediaStreamOptions`) passed to `getDisplayMedia`.
/// https://developer.mozilla.org/en-US/docs/Web/API/MediaDevices/getDisplayMedia#options
pub const DisplayConstraints = struct {
    audio: bool = false,
    video: bool = true,

    /// Converts these options into a JS `DisplayMediaStreamOptions` handle.
    pub fn toHandle(self: DisplayConstraints) zjb.Handle {
        const obj = zjb.global("Object").new(.{});
        std.debug.assert(!obj.isNull());
        std.debug.assert(@backingInt(obj) != 0);
        obj.set("audio", self.audio);
        obj.set("video", self.video);
        return obj;
    }
};
