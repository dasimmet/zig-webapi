//! Geolocation API (`navigator.geolocation`) one-shot and live watch demo.

// 1. Imports
const std = @import("std");
const webapi = @import("webapi");

// 2. Shortcuts on imports
const GeolocationDemo = @This();
const dom = webapi.dom;
const Event = webapi.Event;

// 3. File-level struct members
geo_watch_id: dom.Geolocation.WatchId = .invalid,

// 7. Public functions
/// Attaches `#btn-geo-once` and `#btn-geo-watch` click listeners.
pub fn bind(self: *GeolocationDemo) void {
    const doc = dom.document();
    if (doc.getElementById("btn-geo-once")) |btn| {
        defer btn.release();
        btn.addEventListener("click", GeolocationDemo, self, onGeoOnceClick);
    }
    if (doc.getElementById("btn-geo-watch")) |btn| {
        defer btn.release();
        btn.addEventListener("click", GeolocationDemo, self, onGeoWatchClick);
    }
}

// 9. Private declarations
fn onGeoOnceClick(self: *GeolocationDemo, _: Event.PointerEvent) void {
    const geo = dom.Geolocation.fromNavigator();
    defer geo.release();
    if (geo.isNull()) {
        dom.document().setElemText(
            "geo-output",
            "Geolocation is not supported in this browser.",
        );
        return;
    }
    dom.document().setElemText("geo-output", "Requesting current position...");
    geo.getCurrentPosition(
        GeolocationDemo,
        self,
        onGeoSuccess,
        onGeoError,
        .{ .enable_high_accuracy = true, .timeout = 10_000, .maximum_age = 0 },
    );
}

fn onGeoWatchClick(self: *GeolocationDemo, _: Event.PointerEvent) void {
    const geo = dom.Geolocation.fromNavigator();
    defer geo.release();
    if (geo.isNull()) {
        dom.document().setElemText(
            "geo-output",
            "Geolocation is not supported in this browser.",
        );
        return;
    }
    const doc = dom.document();
    if (self.geo_watch_id != .invalid) {
        geo.clearWatch(self.geo_watch_id);
        self.geo_watch_id = .invalid;
        doc.setElemText("btn-geo-watch", "Watch Position");
        doc.setElemText("geo-output", "Stopped watching position.");
        return;
    }
    doc.setElemText("geo-output", "Watching position updates...");
    self.geo_watch_id = geo.watchPosition(
        GeolocationDemo,
        self,
        onGeoSuccess,
        onGeoError,
        .{ .enable_high_accuracy = true, .timeout = 10_000, .maximum_age = 0 },
    );
    if (self.geo_watch_id != .invalid) {
        doc.setElemText("btn-geo-watch", "Stop Watch");
    }
}

fn onGeoSuccess(self: *GeolocationDemo, pos: dom.Geolocation.Position) void {
    const coords = pos.coords();
    const ts = pos.timestamp();
    var alt_buf: [32]u8 = undefined;
    const alt_str = if (coords.altitude) |alt|
        std.fmt.bufPrint(&alt_buf, "{d:.1} m", .{alt}) catch "n/a"
    else
        "n/a";
    var speed_buf: [32]u8 = undefined;
    const speed_str = if (coords.speed) |spd|
        std.fmt.bufPrint(&speed_buf, "{d:.2} m/s", .{spd}) catch "n/a"
    else
        "n/a";

    var out_buf: [320]u8 = undefined;
    const msg = std.fmt.bufPrint(
        &out_buf,
        "lat={d:.6}, lon={d:.6}\naccuracy=±{d:.1} m | alt={s} | speed={s}\nwatch={s} | timestamp={d:.0} ms",
        .{
            coords.latitude,
            coords.longitude,
            coords.accuracy,
            alt_str,
            speed_str,
            if (self.geo_watch_id != .invalid) "active" else "once",
            ts,
        },
    ) catch return;
    dom.document().setElemText("geo-output", msg);
}

fn onGeoError(self: *GeolocationDemo, err: dom.Geolocation.PositionError) void {
    var msg_buf: [160]u8 = undefined;
    const err_msg = err.message(&msg_buf);
    const code_label = switch (err.code()) {
        .permission_denied => "PERMISSION_DENIED",
        .position_unavailable => "POSITION_UNAVAILABLE",
        .timeout => "TIMEOUT",
        _ => "UNKNOWN",
    };
    if (self.geo_watch_id != .invalid) {
        const geo = dom.Geolocation.fromNavigator();
        defer geo.release();
        if (!geo.isNull()) geo.clearWatch(self.geo_watch_id);
        self.geo_watch_id = .invalid;
        dom.document().setElemText("btn-geo-watch", "Watch Position");
    }
    var out_buf: [256]u8 = undefined;
    const text = std.fmt.bufPrint(
        &out_buf,
        "Geolocation error ({s}): {s}",
        .{ code_label, if (err_msg.len > 0) err_msg else "no details" },
    ) catch "Geolocation error.";
    dom.document().setElemText("geo-output", text);
}
