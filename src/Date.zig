//! Type-safe wrapper for the JavaScript `Date` built-in class.
//! https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Date

// 1. Imports
const std = @import("std");
const webapi = @import("webapi.zig");

// 2. Shortcuts on imports
const Date = @This();
const zjb = webapi.zjb;

// 3. File-level struct members
handle: zjb.Handle,
pub const @"null": Date = .{ .handle = .null };

// 5. init
/// Constructs a `Date` representing the current instant (`new Date()`).
/// https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Date/Date
pub fn init() Date {
    const h = zjb.global("Date").new(.{});
    std.debug.assert(!h.isNull());
    std.debug.assert(@backingInt(h) != 0);
    return fromHandle(h);
}

/// Constructs a `Date` from milliseconds since the Unix epoch.
/// https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Date/Date
pub fn initFromTimestamp(ms: f64) Date {
    std.debug.assert(std.math.isFinite(ms));
    const h = zjb.global("Date").new(.{ms});
    std.debug.assert(!h.isNull());
    return fromHandle(h);
}

/// Constructs a `Date` by parsing an ISO 8601 or RFC 2822 date string.
/// https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Date/Date
pub fn initFromString(date_str: []const u8) Date {
    std.debug.assert(date_str.len > 0);
    const s = zjb.string(date_str);
    defer s.release();
    const h = zjb.global("Date").new(.{s});
    std.debug.assert(!h.isNull());
    return fromHandle(h);
}

/// Constructs a `Date` in local time from explicit calendar fields.
/// Note that `month_index` is 0-based (0 = January, 11 = December).
/// https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Date/Date
pub fn initFromParts(parts: Parts) Date {
    std.debug.assert(@sizeOf(Date) == @sizeOf(zjb.Handle));
    std.debug.assert(parts.month_index >= 0 and parts.month_index <= 11);
    const h = zjb.global("Date").new(.{
        parts.year,
        parts.month_index,
        parts.day,
        parts.hours,
        parts.minutes,
        parts.seconds,
        parts.ms,
    });
    return fromHandle(h);
}

// 7. Public functions
/// Returns true if `Date` is available in the current global scope.
pub fn isSupported() bool {
    std.debug.assert(@sizeOf(Date) == @sizeOf(zjb.Handle));
    const cls = zjb.ConstHandle.global.get("Date", zjb.Handle);
    defer cls.release();
    std.debug.assert(@backingInt(cls) != 0 or cls.isNull());
    return !cls.isNull();
}

/// Wraps a non-null JS `Date` handle.
pub fn fromHandle(handle: zjb.Handle) Date {
    std.debug.assert(!handle.isNull());
    std.debug.assert(@backingInt(handle) != 0);
    return .{ .handle = handle };
}

/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: Date) bool {
    return self.handle.isNull();
}

/// Releases the underlying JS handle.
pub fn release(self: Date) void {
    self.handle.release();
}

/// Returns the current timestamp in milliseconds since the Unix epoch.
/// https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Date/now
pub fn now() f64 {
    const global_date = zjb.global("Date");
    std.debug.assert(!global_date.isNull());
    const ms = global_date.call("now", .{}, f64);
    std.debug.assert(std.math.isFinite(ms));
    return ms;
}

/// Parses `date_str` and returns milliseconds since the Unix epoch (or NaN).
/// https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Date/parse
pub fn parse(date_str: []const u8) f64 {
    std.debug.assert(date_str.len > 0);
    const global_date = zjb.global("Date");
    std.debug.assert(!global_date.isNull());
    const s = zjb.string(date_str);
    defer s.release();
    return global_date.call("parse", .{s}, f64);
}

/// Computes a UTC timestamp in milliseconds from calendar `parts`.
/// Note that `month_index` is 0-based (0 = January, 11 = December).
/// https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Date/UTC
pub fn utc(parts: Parts) f64 {
    const global_date = zjb.global("Date");
    std.debug.assert(!global_date.isNull());
    std.debug.assert(parts.month_index >= 0 and parts.month_index <= 11);
    return global_date.call("UTC", .{
        parts.year,
        parts.month_index,
        parts.day,
        parts.hours,
        parts.minutes,
        parts.seconds,
        parts.ms,
    }, f64);
}

/// Returns the stored time value in milliseconds since the Unix epoch (or NaN).
/// https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Date/getTime
pub fn getTime(self: Date) f64 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return self.handle.call("getTime", .{}, f64);
}

/// Sets the stored time value in milliseconds since the Unix epoch.
/// https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Date/setTime
pub fn setTime(self: Date, time_ms: f64) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(std.math.isFinite(time_ms));
    self.handle.call("setTime", .{time_ms}, void);
}

/// Returns the difference in minutes between UTC and local time.
/// https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Date/getTimezoneOffset
pub fn getTimezoneOffset(self: Date) i32 {
    return self.callGetI32("getTimezoneOffset");
}

/// Returns the 4-digit year in local time.
pub fn getFullYear(self: Date) i32 {
    return self.callGetI32("getFullYear");
}

/// Sets the 4-digit year in local time.
pub fn setFullYear(self: Date, year: i32) void {
    self.callSetI32("setFullYear", year);
}

/// Returns the 0-based month index (0..11) in local time.
pub fn getMonth(self: Date) i32 {
    return self.callGetI32("getMonth");
}

/// Sets the 0-based month index in local time.
pub fn setMonth(self: Date, month_index: i32) void {
    self.callSetI32("setMonth", month_index);
}

/// Returns the day of the month (1..31) in local time.
pub fn getDate(self: Date) i32 {
    return self.callGetI32("getDate");
}

/// Sets the day of the month in local time.
pub fn setDate(self: Date, day_of_month: i32) void {
    self.callSetI32("setDate", day_of_month);
}

/// Returns the day of the week (0 = Sunday .. 6 = Saturday) in local time.
pub fn getDay(self: Date) i32 {
    return self.callGetI32("getDay");
}

/// Returns the hour (0..23) in local time.
pub fn getHours(self: Date) i32 {
    return self.callGetI32("getHours");
}

/// Sets the hour in local time.
pub fn setHours(self: Date, hours: i32) void {
    self.callSetI32("setHours", hours);
}

/// Returns the minutes (0..59) in local time.
pub fn getMinutes(self: Date) i32 {
    return self.callGetI32("getMinutes");
}

/// Sets the minutes in local time.
pub fn setMinutes(self: Date, minutes: i32) void {
    self.callSetI32("setMinutes", minutes);
}

/// Returns the seconds (0..59) in local time.
pub fn getSeconds(self: Date) i32 {
    return self.callGetI32("getSeconds");
}

/// Sets the seconds in local time.
pub fn setSeconds(self: Date, seconds: i32) void {
    self.callSetI32("setSeconds", seconds);
}

/// Returns the milliseconds (0..999) in local time.
pub fn getMilliseconds(self: Date) i32 {
    return self.callGetI32("getMilliseconds");
}

/// Sets the milliseconds in local time.
pub fn setMilliseconds(self: Date, ms: i32) void {
    self.callSetI32("setMilliseconds", ms);
}

/// Returns the 4-digit year in UTC.
pub fn getUTCFullYear(self: Date) i32 {
    return self.callGetI32("getUTCFullYear");
}

/// Sets the 4-digit year in UTC.
pub fn setUTCFullYear(self: Date, year: i32) void {
    self.callSetI32("setUTCFullYear", year);
}

/// Returns the 0-based month index (0..11) in UTC.
pub fn getUTCMonth(self: Date) i32 {
    return self.callGetI32("getUTCMonth");
}

/// Sets the 0-based month index in UTC.
pub fn setUTCMonth(self: Date, month_index: i32) void {
    self.callSetI32("setUTCMonth", month_index);
}

/// Returns the day of the month (1..31) in UTC.
pub fn getUTCDate(self: Date) i32 {
    return self.callGetI32("getUTCDate");
}

/// Sets the day of the month in UTC.
pub fn setUTCDate(self: Date, day_of_month: i32) void {
    self.callSetI32("setUTCDate", day_of_month);
}

/// Returns the day of the week (0 = Sunday .. 6 = Saturday) in UTC.
pub fn getUTCDay(self: Date) i32 {
    return self.callGetI32("getUTCDay");
}

/// Returns the hour (0..23) in UTC.
pub fn getUTCHours(self: Date) i32 {
    return self.callGetI32("getUTCHours");
}

/// Sets the hour in UTC.
pub fn setUTCHours(self: Date, hours: i32) void {
    self.callSetI32("setUTCHours", hours);
}

/// Returns the minutes (0..59) in UTC.
pub fn getUTCMinutes(self: Date) i32 {
    return self.callGetI32("getUTCMinutes");
}

/// Sets the minutes in UTC.
pub fn setUTCMinutes(self: Date, minutes: i32) void {
    self.callSetI32("setUTCMinutes", minutes);
}

/// Returns the seconds (0..59) in UTC.
pub fn getUTCSeconds(self: Date) i32 {
    return self.callGetI32("getUTCSeconds");
}

/// Sets the seconds in UTC.
pub fn setUTCSeconds(self: Date, seconds: i32) void {
    self.callSetI32("setUTCSeconds", seconds);
}

/// Returns the milliseconds (0..999) in UTC.
pub fn getUTCMilliseconds(self: Date) i32 {
    return self.callGetI32("getUTCMilliseconds");
}

/// Sets the milliseconds in UTC.
pub fn setUTCMilliseconds(self: Date, ms: i32) void {
    self.callSetI32("setUTCMilliseconds", ms);
}

/// Copies the ISO 8601 extended-format string (`toISOString()`) into `buf`.
/// https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Date/toISOString
pub fn toISOString(self: Date, buf: []u8) []u8 {
    return self.callStringMethod("toISOString", buf);
}

/// Allocates and returns `date.toISOString()`.
pub fn toISOStringAlloc(self: Date, allocator: std.mem.Allocator) ![]u8 {
    return self.callStringMethodAlloc("toISOString", allocator);
}

/// Copies the RFC 7231 UTC string (`toUTCString()`) into `buf`.
pub fn toUTCString(self: Date, buf: []u8) []u8 {
    return self.callStringMethod("toUTCString", buf);
}

/// Copies the human-readable date portion (`toDateString()`) into `buf`.
pub fn toDateString(self: Date, buf: []u8) []u8 {
    return self.callStringMethod("toDateString", buf);
}

/// Copies the human-readable time portion (`toTimeString()`) into `buf`.
pub fn toTimeString(self: Date, buf: []u8) []u8 {
    return self.callStringMethod("toTimeString", buf);
}

/// Copies the full string representation (`toString()`) into `buf`.
pub fn toString(self: Date, buf: []u8) []u8 {
    return self.callStringMethod("toString", buf);
}

/// Allocates and returns `date.toString()`.
pub fn toStringAlloc(self: Date, allocator: std.mem.Allocator) ![]u8 {
    return self.callStringMethodAlloc("toString", allocator);
}

/// Copies `toLocaleString(locales?)` into `buf`.
pub fn toLocaleString(self: Date, locales: ?[]const u8, buf: []u8) []u8 {
    return self.callLocaleMethod("toLocaleString", locales, buf);
}

/// Copies `toLocaleDateString(locales?)` into `buf`.
pub fn toLocaleDateString(self: Date, locales: ?[]const u8, buf: []u8) []u8 {
    return self.callLocaleMethod("toLocaleDateString", locales, buf);
}

/// Copies `toLocaleTimeString(locales?)` into `buf`.
pub fn toLocaleTimeString(self: Date, locales: ?[]const u8, buf: []u8) []u8 {
    return self.callLocaleMethod("toLocaleTimeString", locales, buf);
}

/// Copies `toJSON()` into `buf`, or returns `null` when JS returns `null`.
pub fn toJSON(self: Date, buf: []u8) ?[]u8 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(buf.len > 0);
    const h = self.handle.call("toJSON", .{}, zjb.Handle);
    defer h.release();
    if (h.isNull()) return null;
    return webapi.stringFromHandle(h, buf);
}

// 8. Extra classes
/// Calendar components used to construct local (`initFromParts`) or UTC (`utc`)
/// dates.
pub const Parts = struct {
    year: i32,
    /// 0-based month index (0 = January, 11 = December).
    month_index: i32,
    day: i32 = 1,
    hours: i32 = 0,
    minutes: i32 = 0,
    seconds: i32 = 0,
    ms: i32 = 0,
};

// 9. Private declarations
fn callGetI32(self: Date, comptime method: []const u8) i32 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(method.len > 0);
    return self.handle.call(method, .{}, i32);
}

fn callSetI32(self: Date, comptime method: []const u8, val: i32) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(method.len > 0);
    self.handle.call(method, .{val}, void);
}

fn callStringMethod(
    self: Date,
    comptime method: []const u8,
    buf: []u8,
) []u8 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(buf.len > 0);
    const h = self.handle.call(method, .{}, zjb.Handle);
    defer h.release();
    if (h.isNull()) return "";
    return webapi.stringFromHandle(h, buf);
}

fn callStringMethodAlloc(
    self: Date,
    comptime method: []const u8,
    allocator: std.mem.Allocator,
) ![]u8 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(method.len > 0);
    const h = self.handle.call(method, .{}, zjb.Handle);
    defer h.release();
    return webapi.stringFromHandleAlloc(allocator, h);
}

fn callLocaleMethod(
    self: Date,
    comptime method: []const u8,
    locales: ?[]const u8,
    buf: []u8,
) []u8 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(buf.len > 0);
    const h = if (locales) |loc| blk: {
        std.debug.assert(loc.len > 0);
        const loc_s = zjb.string(loc);
        defer loc_s.release();
        break :blk self.handle.call(method, .{loc_s}, zjb.Handle);
    } else self.handle.call(method, .{}, zjb.Handle);
    defer h.release();
    if (h.isNull()) return "";
    return webapi.stringFromHandle(h, buf);
}
