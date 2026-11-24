//! Video input capture demo using `MediaDevices.getUserMedia`,
//! `dom.HTMLVideoElement` (`srcObject`, `playsInline`, `videoWidth`,
//! `videoHeight`), and `CanvasRenderingContext2D.drawImageScaled` for frame
//! snapshot capture.

// 1. Imports
const std = @import("std");
const webapi = @import("webapi");

// 2. Shortcuts on imports
const VideoInputDemo = @This();
const Canvas2D = webapi.CanvasRenderingContext2D;
const dom = webapi.dom;
const Event = webapi.Event;
const HTMLVideoElement = dom.HTMLVideoElement;
const MediaDevices = webapi.MediaDevices;
const MediaStream = webapi.MediaStream;
const zjb = webapi.zjb;

// 3. File-level struct members
video: HTMLVideoElement = .null,
snap_canvas: dom.Element = .null,
snap_ctx: Canvas2D = .null,
stream: MediaStream = .null,
request_pending: bool = false,
running: bool = false,
snap_count: u32 = 0,

// 7. Public functions
/// Attaches camera start/stop and frame snapshot listeners and initializes the
/// snapshot preview canvas.
pub fn bind(self: *VideoInputDemo) void {
    const doc = dom.document();
    if (doc.getElementById("cam-video")) |el| {
        self.video = el.asVideo();
        self.video.setMuted(true);
        self.video.setPlaysInline(true);
        self.video.addEventListener(
            "loadedmetadata",
            VideoInputDemo,
            self,
            onVideoMetadata,
        );
    }
    if (doc.getElementById("cam-snapshot")) |c| {
        self.snap_canvas = c;
        if (Canvas2D.fromCanvas(c) catch null) |ctx2d| {
            self.snap_ctx = ctx2d;
            self.drawSnapshotPlaceholder("No snapshot yet — start camera & click \"Capture Frame\"");
        }
    }
    if (doc.getElementById("btn-cam-toggle")) |btn| {
        defer btn.release();
        btn.addEventListener("click", VideoInputDemo, self, onToggleClick);
    }
    if (doc.getElementById("btn-cam-snap")) |btn| {
        defer btn.release();
        btn.addEventListener("click", VideoInputDemo, self, onSnapClick);
    }
}

// 9. Private declarations
fn onToggleClick(self: *VideoInputDemo, _: Event.PointerEvent) void {
    if (self.running) {
        self.stopCamera("Camera stopped.");
        return;
    }
    if (self.request_pending) return;

    const md = MediaDevices.fromNavigator();
    if (md.isNull()) {
        dom.document().setElemText(
            "cam-output",
            "navigator.mediaDevices is unavailable (requires HTTPS or localhost).",
        );
        return;
    }
    defer md.release();

    const stream_p = md.getUserMedia(.{
        .audio = .disabled,
        .video = .{
            .constraints = .{
                .width = 640,
                .height = 360,
                .frame_rate = 30.0,
                .facing_mode = .user,
            },
        },
    }) orelse {
        dom.document().setElemText(
            "cam-output",
            "getUserMedia() is not supported in this browser.",
        );
        return;
    };
    defer stream_p.release();

    self.request_pending = true;
    dom.document().setElemText("cam-output", "Requesting camera permission...");
    stream_p.thenFn(VideoInputDemo, self, onCameraStream, onCameraError);
}

fn onCameraStream(self: *VideoInputDemo, borrowed_stream: MediaStream) void {
    self.request_pending = false;
    const owned_stream = MediaStream.fromHandle(
        webapi.retainHandle(borrowed_stream.handle),
    );

    if (self.video.isNull()) {
        owned_stream.stopAllTracks();
        owned_stream.release();
        return;
    }

    self.stream = owned_stream;
    self.running = true;

    self.video.setMuted(true);
    self.video.setPlaysInline(true);
    self.video.setSrcObject(owned_stream);
    const play_p = self.video.play();
    play_p.release();

    dom.document().setElemText("btn-cam-toggle", "Stop Camera");
    self.updateCameraReadout();

    var tracks = self.stream.getVideoTracks();
    defer tracks.release();
    if (tracks.next()) |track| {
        defer track.release();
        track.addEventListener("ended", VideoInputDemo, self, onTrackEnded);
    }
}

fn onVideoMetadata(self: *VideoInputDemo, _: Event) void {
    if (self.running) {
        self.updateCameraReadout();
    }
}

fn updateCameraReadout(self: *VideoInputDemo) void {
    var tracks = self.stream.getVideoTracks();
    defer tracks.release();

    var label_buf: [160]u8 = undefined;
    var track_label: []const u8 = "(default camera)";
    var w: u32 = self.video.videoWidth();
    var h: u32 = self.video.videoHeight();
    var fps: f64 = 0.0;

    if (tracks.next()) |track| {
        defer track.release();
        const lbl = track.label(&label_buf);
        if (lbl.len > 0) track_label = lbl;
        const settings = track.getSettings();
        if (w == 0) w = settings.width orelse 0;
        if (h == 0) h = settings.height orelse 0;
        fps = settings.frame_rate orelse 0.0;
    }

    var out_buf: [320]u8 = undefined;
    const msg = std.fmt.bufPrint(
        &out_buf,
        "Live video track: {s}\nresolution={d}x{d} px | frameRate={d:.1} fps | snapshots={d}",
        .{ track_label, w, h, fps, self.snap_count },
    ) catch return;
    dom.document().setElemText("cam-output", msg);
}

fn onTrackEnded(self: *VideoInputDemo, _: Event) void {
    if (self.running) {
        self.stopCamera("Camera track ended by browser/hardware.");
    }
}

fn stopCamera(self: *VideoInputDemo, status_msg: []const u8) void {
    self.running = false;
    if (!self.video.isNull()) {
        self.video.pause();
        self.video.setSrcObject(null);
    }
    if (!self.stream.isNull()) {
        self.stream.stopAllTracks();
        self.stream.release();
        self.stream = .null;
    }
    dom.document().setElemText("btn-cam-toggle", "Start Camera");
    dom.document().setElemText("cam-output", status_msg);
}

fn onSnapClick(self: *VideoInputDemo, _: Event.PointerEvent) void {
    if (!self.running or self.video.isNull() or self.snap_ctx.isNull()) {
        dom.document().setElemText(
            "cam-output",
            "Start the camera first before capturing a snapshot.",
        );
        return;
    }
    const vw = self.video.videoWidth();
    const vh = self.video.videoHeight();
    if (vw == 0 or vh == 0) {
        dom.document().setElemText(
            "cam-output",
            "Waiting for first video frame before capturing...",
        );
        return;
    }

    self.snap_canvas.set("width", @as(i32, @intCast(vw)));
    self.snap_canvas.set("height", @as(i32, @intCast(vh)));

    const fw: f64 = @floatFromInt(vw);
    const fh: f64 = @floatFromInt(vh);
    const ctx = self.snap_ctx;
    ctx.drawImageScaled(self.video, 0.0, 0.0, fw, fh);

    self.snap_count += 1;
    ctx.setFillStyle("rgba(12, 16, 26, 0.78)");
    ctx.fillRect(10.0, fh - 34.0, 250.0, 24.0);

    var badge_buf: [64]u8 = undefined;
    const badge = std.fmt.bufPrint(
        &badge_buf,
        "Snapshot #{d} ({d}x{d})",
        .{ self.snap_count, vw, vh },
    ) catch "Snapshot";
    ctx.setFont("600 13px ui-monospace, SFMono-Regular, monospace");
    ctx.setTextAlign(.left);
    ctx.setTextBaseline(.middle);
    ctx.setFillStyle("#f7a41d");
    ctx.fillText(badge, 18.0, fh - 22.0);

    self.updateCameraReadout();
}

fn drawSnapshotPlaceholder(self: *VideoInputDemo, text: []const u8) void {
    if (self.snap_ctx.isNull() or self.snap_canvas.isNull()) return;
    const w: f64 = @floatFromInt(@max(self.snap_canvas.get("width", i32), 1));
    const h: f64 = @floatFromInt(@max(self.snap_canvas.get("height", i32), 1));
    const ctx = self.snap_ctx;

    ctx.setFillStyle("#0d111a");
    ctx.fillRect(0.0, 0.0, w, h);
    ctx.setFont("600 13px system-ui, -apple-system, sans-serif");
    ctx.setTextAlign(.center);
    ctx.setTextBaseline(.middle);
    ctx.setFillStyle("#a6b0c0");
    ctx.fillTextMaxWidth(text, w * 0.5, h * 0.5, w - 24.0);
}

fn onCameraError(self: *VideoInputDemo, err_h: zjb.Handle) void {
    self.request_pending = false;
    var name_buf: [64]u8 = undefined;
    var msg_buf: [192]u8 = undefined;
    const name_h = err_h.get("name", zjb.Handle);
    defer name_h.release();
    const msg_h = err_h.get("message", zjb.Handle);
    defer msg_h.release();
    const err_name = webapi.stringFromHandle(name_h, &name_buf);
    const err_msg = webapi.stringFromHandle(msg_h, &msg_buf);

    var out_buf: [280]u8 = undefined;
    const text = std.fmt.bufPrint(
        &out_buf,
        "Video input error ({s}): {s}",
        .{
            if (err_name.len > 0) err_name else "Error",
            if (err_msg.len > 0) err_msg else "permission denied or no camera",
        },
    ) catch "Video input failed (see console).";
    dom.document().setElemText("cam-output", text);
}
