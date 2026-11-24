//! Type-safe wrapper for a single media track (`MediaStreamTrack`) representing
//! an audio or video source within a `MediaStream`.
//! https://developer.mozilla.org/en-US/docs/Web/API/MediaStreamTrack

// 1. Imports
const std = @import("std");
const webapi = @import("../webapi.zig");

// 2. Shortcuts on imports
const MediaStreamTrack = @This();
const Event = webapi.Event;
const zjb = webapi.zjb;

// 3. File-level struct members
handle: zjb.Handle,
pub const @"null": MediaStreamTrack = .{ .handle = .null };

// 7. Public functions
/// Wraps a non-null JS `MediaStreamTrack` handle.
pub fn fromHandle(handle: zjb.Handle) MediaStreamTrack {
    std.debug.assert(!handle.isNull());
    std.debug.assert(@backingInt(handle) != 0);
    return .{ .handle = handle };
}

/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: MediaStreamTrack) bool {
    return self.handle.isNull();
}

/// Releases the underlying JS handle.
pub fn release(self: MediaStreamTrack) void {
    self.handle.release();
}

/// Copies the unique track identifier (`track.id`) into `buf`.
/// https://developer.mozilla.org/en-US/docs/Web/API/MediaStreamTrack/id
pub fn id(self: MediaStreamTrack, buf: []u8) []u8 {
    return readStringProp(self.handle, "id", buf);
}

/// Copies the human-readable device/source label (`track.label`) into `buf`.
/// Note: browsers may return an empty string before media permissions are granted.
/// https://developer.mozilla.org/en-US/docs/Web/API/MediaStreamTrack/label
pub fn label(self: MediaStreamTrack, buf: []u8) []u8 {
    return readStringProp(self.handle, "label", buf);
}

/// Returns the media kind (`audio` or `video`) of this track.
/// https://developer.mozilla.org/en-US/docs/Web/API/MediaStreamTrack/kind
pub fn kind(self: MediaStreamTrack) Kind {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    var buf: [16]u8 = undefined;
    return Kind.fromString(readStringProp(self.handle, "kind", &buf));
}

/// Returns the lifecycle state (`live` or `ended`) of this track.
/// https://developer.mozilla.org/en-US/docs/Web/API/MediaStreamTrack/readyState
pub fn readyState(self: MediaStreamTrack) ReadyState {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    var buf: [16]u8 = undefined;
    return ReadyState.fromString(
        readStringProp(self.handle, "readyState", &buf),
    );
}

/// Returns whether this track is enabled to render media (`track.enabled`).
/// https://developer.mozilla.org/en-US/docs/Web/API/MediaStreamTrack/enabled
pub fn enabled(self: MediaStreamTrack) bool {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return self.handle.get("enabled", bool);
}

/// Enables or silences/blacks-out media rendering (`track.enabled = val`).
/// https://developer.mozilla.org/en-US/docs/Web/API/MediaStreamTrack/enabled
pub fn setEnabled(self: MediaStreamTrack, val: bool) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    self.handle.set("enabled", val);
}

/// Returns true if the source is temporarily unable to provide media data.
/// https://developer.mozilla.org/en-US/docs/Web/API/MediaStreamTrack/muted
pub fn muted(self: MediaStreamTrack) bool {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return self.handle.get("muted", bool);
}

/// Permanently stops the track and releases its underlying capture source.
/// https://developer.mozilla.org/en-US/docs/Web/API/MediaStreamTrack/stop
pub fn stop(self: MediaStreamTrack) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    self.handle.call("stop", .{}, void);
}

/// Creates a duplicate `MediaStreamTrack` referencing the same media source.
/// Caller must call `.release()`.
/// https://developer.mozilla.org/en-US/docs/Web/API/MediaStreamTrack/clone
pub fn clone(self: MediaStreamTrack) MediaStreamTrack {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return fromHandle(self.handle.call("clone", .{}, zjb.Handle));
}

/// Extracts a snapshot of the track's active `MediaTrackSettings`.
/// https://developer.mozilla.org/en-US/docs/Web/API/MediaStreamTrack/getSettings
pub fn getSettings(self: MediaStreamTrack) Settings {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const h = self.handle.call("getSettings", .{}, zjb.Handle);
    defer h.release();
    return Settings.fromHandle(h);
}

/// Attaches a typed listener (e.g. `"ended"`, `"mute"`, `"unmute"`).
pub fn addEventListener(
    self: MediaStreamTrack,
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
/// Media category of a `MediaStreamTrack`.
pub const Kind = enum {
    audio,
    video,
    unknown,

    pub fn fromString(s: []const u8) Kind {
        if (std.mem.eql(u8, s, "audio")) return .audio;
        if (std.mem.eql(u8, s, "video")) return .video;
        return .unknown;
    }
};

/// Lifecycle state of a `MediaStreamTrack`.
pub const ReadyState = enum {
    live,
    ended,
    unknown,

    pub fn fromString(s: []const u8) ReadyState {
        if (std.mem.eql(u8, s, "live")) return .live;
        if (std.mem.eql(u8, s, "ended")) return .ended;
        return .unknown;
    }
};

/// Snapshot of `MediaTrackSettings` returned by `MediaStreamTrack.getSettings()`.
/// https://developer.mozilla.org/en-US/docs/Web/API/MediaTrackSettings
pub const Settings = struct {
    width: ?u32 = null,
    height: ?u32 = null,
    aspect_ratio: ?f64 = null,
    frame_rate: ?f64 = null,
    sample_rate: ?u32 = null,
    sample_size: ?u32 = null,
    channel_count: ?u32 = null,
    echo_cancellation: ?bool = null,
    noise_suppression: ?bool = null,
    auto_gain_control: ?bool = null,

    /// Extracts settings properties from a JS `MediaTrackSettings` handle.
    pub fn fromHandle(h: zjb.Handle) Settings {
        if (h.isNull()) return .{};
        return .{
            .width = readOptionalU32(h, "width"),
            .height = readOptionalU32(h, "height"),
            .aspect_ratio = readOptionalF64(h, "aspectRatio"),
            .frame_rate = readOptionalF64(h, "frameRate"),
            .sample_rate = readOptionalU32(h, "sampleRate"),
            .sample_size = readOptionalU32(h, "sampleSize"),
            .channel_count = readOptionalU32(h, "channelCount"),
            .echo_cancellation = readOptionalBool(h, "echoCancellation"),
            .noise_suppression = readOptionalBool(h, "noiseSuppression"),
            .auto_gain_control = readOptionalBool(h, "autoGainControl"),
        };
    }
};

/// Typed view/iterator over a JS `Array<MediaStreamTrack>` returned by
/// `MediaStream.getTracks()`, `getAudioTracks()`, or `getVideoTracks()`.
pub const List = struct {
    handle: zjb.Handle,
    pos: usize = 0,

    pub const @"null": List = .{ .handle = .null };

    /// Wraps a non-null JS `Array<MediaStreamTrack>` handle.
    pub fn fromHandle(handle: zjb.Handle) List {
        std.debug.assert(!handle.isNull());
        std.debug.assert(@backingInt(handle) != 0);
        return .{ .handle = handle };
    }

    /// Returns true if the underlying JS handle is null or undefined.
    pub fn isNull(self: List) bool {
        return self.handle.isNull();
    }

    /// Releases the underlying JS array handle.
    pub fn release(self: List) void {
        self.handle.release();
    }

    /// Returns the number of tracks in the array.
    pub fn len(self: List) usize {
        if (self.handle.isNull()) return 0;
        const raw = self.handle.get("length", i32);
        return if (raw > 0) @intCast(raw) else 0;
    }

    /// Returns an owned `MediaStreamTrack` at `idx`, or `null` if out of bounds.
    pub fn get(self: List, idx: usize) ?MediaStreamTrack {
        if (idx >= self.len()) return null;
        const item = self.handle.indexGet(@as(i32, @intCast(idx)), zjb.Handle);
        if (item.isNull()) {
            item.release();
            return null;
        }
        return MediaStreamTrack.fromHandle(item);
    }

    /// Returns the next owned `MediaStreamTrack`, or `null` when exhausted.
    pub fn next(self: *List) ?MediaStreamTrack {
        const cur = self.pos;
        if (cur >= self.len()) return null;
        self.pos += 1;
        return self.get(cur);
    }
};

// 9. Private declarations
fn readStringProp(h: zjb.Handle, comptime prop: []const u8, buf: []u8) []u8 {
    std.debug.assert(!h.isNull());
    std.debug.assert(buf.len > 0);
    const val_h = h.get(prop, zjb.Handle);
    defer val_h.release();
    if (val_h.isNull()) return "";
    return webapi.stringFromHandle(val_h, buf);
}

fn readOptionalF64(h: zjb.Handle, comptime prop: []const u8) ?f64 {
    const val_h = h.get(prop, zjb.Handle);
    defer val_h.release();
    if (val_h.isNull()) return null;
    return zjb.global("Number").call("call", .{ zjb.Handle.null, val_h }, f64);
}

fn readOptionalU32(h: zjb.Handle, comptime prop: []const u8) ?u32 {
    const v = readOptionalF64(h, prop) orelse return null;
    if (!std.math.isFinite(v) or v < 0.0) return null;
    return @intFromFloat(v);
}

fn readOptionalBool(h: zjb.Handle, comptime prop: []const u8) ?bool {
    const val_h = h.get(prop, zjb.Handle);
    defer val_h.release();
    if (val_h.isNull()) return null;
    return zjb.global("Boolean").call(
        "call",
        .{ zjb.Handle.null, val_h },
        bool,
    );
}
