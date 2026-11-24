//! Type-safe wrapper for the browser Geolocation Web API (`navigator.geolocation`).
//! https://developer.mozilla.org/en-US/docs/Web/API/Geolocation_API
//! https://developer.mozilla.org/en-US/docs/Web/API/Geolocation

// 1. Imports
const std = @import("std");
const webapi = @import("../webapi.zig");

// 2. Shortcuts on imports
const Geolocation = @This();
const zjb = webapi.zjb;

// 3. File-level struct members
handle: zjb.Handle,
pub const @"null": Geolocation = .{ .handle = .null };

// 6. Types
/// Opaque watch identifier returned by `watchPosition` and accepted by `clearWatch`.
pub const WatchId = enum(i32) {
    invalid = 0,
    _,
};

/// Options dictionary passed to `getCurrentPosition` and `watchPosition` (`PositionOptions`).
/// https://developer.mozilla.org/en-US/docs/Web/API/Geolocation/getCurrentPosition#options
pub const Options = struct {
    /// Hint that the application would like the best possible results.
    enable_high_accuracy: bool = false,
    /// Maximum length of time (milliseconds) the device is allowed to take to return a position.
    timeout: ?u32 = null,
    /// Maximum age (milliseconds) of a possible cached position that is acceptable to return.
    maximum_age: ?u32 = null,

    /// Converts these options into a newly allocated JS `PositionOptions` object handle.
    pub fn toHandle(self: Options) zjb.Handle {
        const obj = zjb.global("Object").new(.{});
        std.debug.assert(!obj.isNull());
        obj.set("enableHighAccuracy", self.enable_high_accuracy);
        if (self.timeout) |t| {
            obj.set("timeout", @as(f64, @floatFromInt(t)));
        }
        if (self.maximum_age) |m| {
            obj.set("maximumAge", @as(f64, @floatFromInt(m)));
        }
        return obj;
    }
};

/// Snapshot of `GeolocationCoordinates` extracted from a `Position`.
/// https://developer.mozilla.org/en-US/docs/Web/API/GeolocationCoordinates
pub const Coordinates = struct {
    latitude: f64 = 0.0,
    longitude: f64 = 0.0,
    altitude: ?f64 = null,
    accuracy: f64 = 0.0,
    altitude_accuracy: ?f64 = null,
    heading: ?f64 = null,
    speed: ?f64 = null,

    /// Extracts coordinate fields from a JS `GeolocationCoordinates` handle.
    pub fn fromHandle(handle: zjb.Handle) Coordinates {
        if (handle.isNull()) return .{};
        return .{
            .latitude = handle.get("latitude", f64),
            .longitude = handle.get("longitude", f64),
            .altitude = readOptionalF64(handle, "altitude"),
            .accuracy = handle.get("accuracy", f64),
            .altitude_accuracy = readOptionalF64(handle, "altitudeAccuracy"),
            .heading = readOptionalF64(handle, "heading"),
            .speed = readOptionalF64(handle, "speed"),
        };
    }
};

/// Type-safe wrapper for `GeolocationPosition`.
/// https://developer.mozilla.org/en-US/docs/Web/API/GeolocationPosition
pub const Position = struct {
    handle: zjb.Handle,
    pub const @"null": Position = .{ .handle = .null };

    /// Wraps a non-null JS `GeolocationPosition` handle.
    pub fn fromHandle(handle: zjb.Handle) Position {
        std.debug.assert(!handle.isNull());
        std.debug.assert(@backingInt(handle) != 0);
        return .{ .handle = handle };
    }

    /// Returns true if the underlying JS handle is null or undefined.
    pub fn isNull(self: Position) bool {
        return self.handle.isNull();
    }

    /// Releases the underlying JS handle.
    pub fn release(self: Position) void {
        self.handle.release();
    }

    /// Extracts the `Coordinates` (`position.coords`) for this position.
    /// https://developer.mozilla.org/en-US/docs/Web/API/GeolocationPosition/coords
    pub fn coords(self: Position) Coordinates {
        std.debug.assert(!self.handle.isNull());
        std.debug.assert(@backingInt(self.handle) != 0);
        const coords_h = self.handle.get("coords", zjb.Handle);
        defer coords_h.release();
        return Coordinates.fromHandle(coords_h);
    }

    /// Returns the DOMTimeStamp (milliseconds since Unix epoch) when the position was acquired.
    /// https://developer.mozilla.org/en-US/docs/Web/API/GeolocationPosition/timestamp
    pub fn timestamp(self: Position) f64 {
        std.debug.assert(!self.handle.isNull());
        std.debug.assert(@backingInt(self.handle) != 0);
        return self.handle.get("timestamp", f64);
    }
};

/// Numeric error code reported by `GeolocationPositionError.code`.
/// https://developer.mozilla.org/en-US/docs/Web/API/GeolocationPositionError/code
pub const ErrorCode = enum(i32) {
    permission_denied = 1,
    position_unavailable = 2,
    timeout = 3,
    _,
};

/// Type-safe wrapper for `GeolocationPositionError`.
/// https://developer.mozilla.org/en-US/docs/Web/API/GeolocationPositionError
pub const PositionError = struct {
    handle: zjb.Handle,
    pub const @"null": PositionError = .{ .handle = .null };

    /// Wraps a non-null JS `GeolocationPositionError` handle.
    pub fn fromHandle(handle: zjb.Handle) PositionError {
        std.debug.assert(!handle.isNull());
        std.debug.assert(@backingInt(handle) != 0);
        return .{ .handle = handle };
    }

    /// Returns true if the underlying JS handle is null or undefined.
    pub fn isNull(self: PositionError) bool {
        return self.handle.isNull();
    }

    /// Releases the underlying JS handle.
    pub fn release(self: PositionError) void {
        self.handle.release();
    }

    /// Returns the `GeolocationPositionError.code` enum value.
    /// https://developer.mozilla.org/en-US/docs/Web/API/GeolocationPositionError/code
    pub fn code(self: PositionError) ErrorCode {
        std.debug.assert(!self.handle.isNull());
        std.debug.assert(@backingInt(self.handle) != 0);
        return @fromBackingInt(@intCast(self.handle.get("code", i32)));
    }

    /// Copies the human-readable error message (`error.message`) into `buf`.
    /// https://developer.mozilla.org/en-US/docs/Web/API/GeolocationPositionError/message
    pub fn message(self: PositionError, buf: []u8) []const u8 {
        std.debug.assert(!self.handle.isNull());
        std.debug.assert(buf.len > 0);
        const msg_h = self.handle.get("message", zjb.Handle);
        defer msg_h.release();
        return webapi.stringFromHandle(msg_h, buf);
    }
};

// 7. Public functions
/// Returns true if `navigator.geolocation` is available in this environment.
pub fn isSupported() bool {
    const h = zjb.global("navigator").get("geolocation", zjb.Handle);
    defer h.release();
    return !h.isNull();
}

/// Returns an owned `Geolocation` handle from `navigator.geolocation`, or `.null` if unsupported.
/// https://developer.mozilla.org/en-US/docs/Web/API/Navigator/geolocation
pub fn fromNavigator() Geolocation {
    const h = zjb.global("navigator").get("geolocation", zjb.Handle);
    if (h.isNull()) return .null;
    return fromHandle(h);
}

/// Wraps a non-null JS `Geolocation` handle.
pub fn fromHandle(handle: zjb.Handle) Geolocation {
    std.debug.assert(!handle.isNull());
    std.debug.assert(@backingInt(handle) != 0);
    return .{ .handle = handle };
}

/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: Geolocation) bool {
    return self.handle.isNull();
}

/// Releases the underlying JS handle.
pub fn release(self: Geolocation) void {
    self.handle.release();
}

/// Requests the device's current position once and dispatches the result to
/// `on_success` or `on_error` bound to `ctx`.
/// https://developer.mozilla.org/en-US/docs/Web/API/Geolocation/getCurrentPosition
pub fn getCurrentPosition(
    self: Geolocation,
    comptime Context: type,
    ctx: *Context,
    comptime on_success: *const fn (*Context, Position) void,
    comptime on_error: ?*const fn (*Context, PositionError) void,
    options: ?Options,
) void {
    self.invokePositionMethod(
        "getCurrentPosition",
        void,
        Context,
        ctx,
        on_success,
        on_error,
        options,
    );
}

/// Registers a handler invoked automatically whenever the device's position changes.
/// Returns a `WatchId` that can later be passed to `clearWatch`.
/// https://developer.mozilla.org/en-US/docs/Web/API/Geolocation/watchPosition
pub fn watchPosition(
    self: Geolocation,
    comptime Context: type,
    ctx: *Context,
    comptime on_success: *const fn (*Context, Position) void,
    comptime on_error: ?*const fn (*Context, PositionError) void,
    options: ?Options,
) WatchId {
    const raw = self.invokePositionMethod(
        "watchPosition",
        i32,
        Context,
        ctx,
        on_success,
        on_error,
        options,
    );
    return @fromBackingInt(@intCast(raw));
}

/// Unregisters a location/error monitoring handler previously installed via `watchPosition`.
/// https://developer.mozilla.org/en-US/docs/Web/API/Geolocation/clearWatch
pub fn clearWatch(self: Geolocation, watch_id: WatchId) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    self.handle.call("clearWatch", .{@backingInt(watch_id)}, void);
}

// 9. Private helpers
fn invokePositionMethod(
    self: Geolocation,
    comptime method: []const u8,
    comptime RetType: type,
    comptime Context: type,
    ctx: *Context,
    comptime on_success: *const fn (*Context, Position) void,
    comptime on_error: ?*const fn (*Context, PositionError) void,
    options: ?Options,
) RetType {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    std.debug.assert(@intFromPtr(ctx) != 0 or @sizeOf(Context) == 0);

    const SuccessWrapper = struct {
        fn call(inner_ctx: *Context, pos_h: zjb.Handle) void {
            on_success(inner_ctx, Position.fromHandle(pos_h));
        }
    };
    const cb_ok = webapi.boundFunction(Context, ctx, &SuccessWrapper.call);
    defer cb_ok.release();

    const cb_err: zjb.Handle = if (on_error) |err_fn| blk: {
        const ErrWrapper = struct {
            fn call(inner_ctx: *Context, err_h: zjb.Handle) void {
                err_fn(inner_ctx, PositionError.fromHandle(err_h));
            }
        };
        break :blk webapi.boundFunction(Context, ctx, &ErrWrapper.call);
    } else .null;
    defer if (!cb_err.isNull()) cb_err.release();

    if (options) |opt| {
        const opts_h = opt.toHandle();
        defer opts_h.release();
        return self.handle.call(method, .{ cb_ok, cb_err, opts_h }, RetType);
    }
    return self.handle.call(method, .{ cb_ok, cb_err }, RetType);
}

fn readOptionalF64(h: zjb.Handle, comptime prop: []const u8) ?f64 {
    const val_h = h.get(prop, zjb.Handle);
    defer val_h.release();
    if (val_h.isNull()) return null;
    return zjb.global("Number").call("call", .{ zjb.Handle.null, val_h }, f64);
}
