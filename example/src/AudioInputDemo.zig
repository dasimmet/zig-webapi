//! Audio input capture demo using `MediaDevices.getUserMedia`,
//! `MediaDevices.enumerateDevices`, `MediaStreamAudioSourceNode`, and
//! `AnalyserNode` to render a real-time 2D canvas oscilloscope and level meter.

// 1. Imports
const std = @import("std");
const webapi = @import("webapi");

// 2. Shortcuts on imports
const AudioInputDemo = @This();
const Canvas2D = webapi.CanvasRenderingContext2D;
const dom = webapi.dom;
const Event = webapi.Event;
const MediaDeviceInfo = webapi.MediaDeviceInfo;
const MediaDevices = webapi.MediaDevices;
const MediaStream = webapi.MediaStream;
const WebAudio = webapi.WebAudio;
const zjb = webapi.zjb;

const fft_size: u32 = 512;

// 3. File-level struct members
audio_ctx: WebAudio.AudioContext = .null,
stream: MediaStream = .null,
source_node: WebAudio.MediaStreamAudioSourceNode = .null,
analyser: WebAudio.AnalyserNode = .null,
canvas: dom.Element = .null,
ctx2d: Canvas2D = .null,
frame_cb: zjb.Handle = .null,
request_pending: bool = false,
running: bool = false,

// 7. Public functions
/// Attaches microphone toggle and device enumeration buttons and draws the
/// idle oscilloscope canvas state.
pub fn bind(self: *AudioInputDemo) void {
    const doc = dom.document();
    if (doc.getElementById("mic-canvas")) |c| {
        self.canvas = c;
        if (Canvas2D.fromCanvas(c) catch null) |ctx2d| {
            self.ctx2d = ctx2d;
            self.drawIdleBanner("Microphone idle — click \"Start Microphone\"");
        }
    }
    if (doc.getElementById("btn-mic-toggle")) |btn| {
        defer btn.release();
        btn.addEventListener("click", AudioInputDemo, self, onToggleClick);
    }
    if (doc.getElementById("btn-media-devices")) |btn| {
        defer btn.release();
        btn.addEventListener("click", AudioInputDemo, self, onEnumerateClick);
    }
}

// 9. Private declarations
fn onToggleClick(self: *AudioInputDemo, _: Event.PointerEvent) void {
    if (self.running) {
        self.stopCapture("Microphone stopped.");
        return;
    }
    if (self.request_pending) return;

    const md = MediaDevices.fromNavigator();
    if (md.isNull()) {
        dom.document().setElemText(
            "mic-output",
            "navigator.mediaDevices is unavailable (requires HTTPS or localhost).",
        );
        return;
    }
    defer md.release();

    const stream_p = md.getUserMedia(.{
        .audio = .{
            .constraints = .{
                .echo_cancellation = true,
                .noise_suppression = true,
                .auto_gain_control = true,
            },
        },
        .video = .disabled,
    }) orelse {
        dom.document().setElemText(
            "mic-output",
            "getUserMedia() is not supported in this browser.",
        );
        return;
    };
    defer stream_p.release();

    self.request_pending = true;
    dom.document().setElemText("mic-output", "Requesting microphone permission...");
    stream_p.thenFn(AudioInputDemo, self, onMicStream, onMediaError);
}

fn onMicStream(self: *AudioInputDemo, borrowed_stream: MediaStream) void {
    self.request_pending = false;
    const owned_stream = MediaStream.fromHandle(
        webapi.retainHandle(borrowed_stream.handle),
    );

    if (!WebAudio.AudioContext.isSupported()) {
        owned_stream.stopAllTracks();
        owned_stream.release();
        dom.document().setElemText(
            "mic-output",
            "Web Audio API is unavailable for microphone analysis.",
        );
        return;
    }

    if (self.audio_ctx.isNull()) {
        self.audio_ctx = WebAudio.AudioContext.init();
    }
    if (self.audio_ctx.state() == .suspended) {
        const p = self.audio_ctx.@"resume"();
        p.release();
    }

    const src_node = self.audio_ctx.createMediaStreamSource(owned_stream);
    const analyser = self.audio_ctx.createAnalyser();
    analyser.setFftSize(fft_size);
    analyser.setSmoothingTimeConstant(0.8);
    // Connect only to AnalyserNode (not destination) to avoid speaker feedback.
    src_node.connect(analyser);

    self.stream = owned_stream;
    self.source_node = src_node;
    self.analyser = analyser;
    self.running = true;

    dom.document().setElemText("btn-mic-toggle", "Stop Microphone");
    self.reportTrackInfo();

    if (self.frame_cb.isNull()) {
        self.frame_cb = webapi.boundFunction(AudioInputDemo, self, onFrame);
    }
    dom.window().requestAnimationFrame(self.frame_cb);
}

fn reportTrackInfo(self: *AudioInputDemo) void {
    var tracks = self.stream.getAudioTracks();
    defer tracks.release();

    var label_buf: [160]u8 = undefined;
    var track_label: []const u8 = "(default audio input)";
    var sr: u32 = @intFromFloat(@max(self.audio_ctx.sampleRate(), 0.0));
    var channels: u32 = 1;
    var echo_cancel: bool = true;
    var noise_sup: bool = true;

    if (tracks.next()) |track| {
        defer track.release();
        const lbl = track.label(&label_buf);
        if (lbl.len > 0) track_label = lbl;
        const settings = track.getSettings();
        if (settings.sample_rate) |s| sr = s;
        if (settings.channel_count) |c| channels = c;
        if (settings.echo_cancellation) |ec| echo_cancel = ec;
        if (settings.noise_suppression) |ns| noise_sup = ns;
        track.addEventListener("ended", AudioInputDemo, self, onTrackEnded);
    }

    var out_buf: [384]u8 = undefined;
    const msg = std.fmt.bufPrint(
        &out_buf,
        "Live audio track: {s}\nsampleRate={d} Hz | channels={d} | echoCancellation={} | noiseSuppression={}",
        .{ track_label, sr, channels, echo_cancel, noise_sup },
    ) catch return;
    dom.document().setElemText("mic-output", msg);
}

fn onTrackEnded(self: *AudioInputDemo, _: Event) void {
    if (self.running) {
        self.stopCapture("Microphone track ended by browser/hardware.");
    }
}

fn stopCapture(self: *AudioInputDemo, status_msg: []const u8) void {
    self.running = false;
    if (!self.source_node.isNull()) {
        self.source_node.disconnect();
        self.source_node.release();
        self.source_node = .null;
    }
    if (!self.analyser.isNull()) {
        self.analyser.disconnect();
        self.analyser.release();
        self.analyser = .null;
    }
    if (!self.stream.isNull()) {
        self.stream.stopAllTracks();
        self.stream.release();
        self.stream = .null;
    }
    dom.document().setElemText("btn-mic-toggle", "Start Microphone");
    dom.document().setElemText("mic-output", status_msg);
    self.drawIdleBanner("Microphone stopped — click \"Start Microphone\"");
}

fn onFrame(self: *AudioInputDemo, _: zjb.Handle) void {
    if (!self.running or self.analyser.isNull() or self.ctx2d.isNull()) return;

    var wave: [fft_size]u8 = undefined;
    var freq: [fft_size / 2]u8 = undefined;
    self.analyser.getByteTimeDomainData(&wave);
    self.analyser.getByteFrequencyData(&freq);

    var sum_sq: f64 = 0.0;
    for (wave) |sample| {
        const centered = (@as(f64, @floatFromInt(sample)) - 128.0) / 128.0;
        sum_sq += centered * centered;
    }
    const rms = @sqrt(sum_sq / @as(f64, @floatFromInt(wave.len)));
    const db = if (rms > 0.00001) 20.0 * std.math.log10(rms) else -100.0;
    const meter_norm = std.math.clamp((db + 60.0) / 60.0, 0.0, 1.0);

    const w: f64 = @floatFromInt(@max(self.canvas.get("width", i32), 1));
    const h: f64 = @floatFromInt(@max(self.canvas.get("height", i32), 1));
    const ctx = self.ctx2d;

    ctx.setFillStyle("#0d111a");
    ctx.fillRect(0.0, 0.0, w, h);

    // Subtle FFT spectrum bars along bottom
    const bar_count: usize = 64;
    const bar_step = w / @as(f64, @floatFromInt(bar_count));
    ctx.setFillStyle("rgba(247, 164, 29, 0.28)");
    for (0..bar_count) |i| {
        const mag = @as(f64, @floatFromInt(freq[i * 2])) / 255.0;
        const bar_h = mag * (h - 28.0);
        ctx.fillRect(
            @as(f64, @floatFromInt(i)) * bar_step,
            h - bar_h,
            @max(bar_step - 1.5, 1.0),
            bar_h,
        );
    }

    // Oscilloscope time-domain waveform trace
    ctx.setStrokeStyle("#f7a41d");
    ctx.setLineWidth(2.0);
    ctx.beginPath();
    for (wave, 0..) |sample, i| {
        const x = (@as(f64, @floatFromInt(i)) /
            @as(f64, @floatFromInt(wave.len - 1))) * w;
        const norm = @as(f64, @floatFromInt(sample)) / 255.0;
        const y = 24.0 + (1.0 - norm) * (h - 32.0);
        if (i == 0) ctx.moveTo(x, y) else ctx.lineTo(x, y);
    }
    ctx.stroke();

    // Level meter bar & dBFS readout
    ctx.setFillStyle("#1e2636");
    ctx.fillRect(10.0, 8.0, w - 20.0, 10.0);
    ctx.setFillStyle(if (meter_norm > 0.85) "#ff5f56" else "#38d39f");
    ctx.fillRect(10.0, 8.0, (w - 20.0) * meter_norm, 10.0);

    var hud_buf: [64]u8 = undefined;
    const hud = std.fmt.bufPrint(&hud_buf, "Level: {d:.1} dBFS", .{db}) catch "";
    ctx.setFont("600 12px ui-monospace, SFMono-Regular, monospace");
    ctx.setTextAlign(.right);
    ctx.setTextBaseline(.top);
    ctx.setFillStyle("#e6edf3");
    ctx.fillText(hud, w - 12.0, 22.0);

    dom.window().requestAnimationFrame(self.frame_cb);
}

fn drawIdleBanner(self: *AudioInputDemo, label_text: []const u8) void {
    if (self.ctx2d.isNull() or self.canvas.isNull()) return;
    const w: f64 = @floatFromInt(@max(self.canvas.get("width", i32), 1));
    const h: f64 = @floatFromInt(@max(self.canvas.get("height", i32), 1));
    const ctx = self.ctx2d;

    ctx.setFillStyle("#0d111a");
    ctx.fillRect(0.0, 0.0, w, h);
    ctx.setStrokeStyle("rgba(247, 164, 29, 0.35)");
    ctx.setLineWidth(1.5);
    ctx.beginPath();
    ctx.moveTo(0.0, h * 0.5);
    ctx.lineTo(w, h * 0.5);
    ctx.stroke();

    ctx.setFont("600 14px system-ui, -apple-system, sans-serif");
    ctx.setTextAlign(.center);
    ctx.setTextBaseline(.middle);
    ctx.setFillStyle("#a6b0c0");
    ctx.fillText(label_text, w * 0.5, h * 0.5);
}

fn onEnumerateClick(self: *AudioInputDemo, _: Event.PointerEvent) void {
    const md = MediaDevices.fromNavigator();
    if (md.isNull()) {
        dom.document().setElemText(
            "mic-output",
            "navigator.mediaDevices is unavailable (requires HTTPS or localhost).",
        );
        return;
    }
    defer md.release();

    const list_p = md.enumerateDevices() orelse {
        dom.document().setElemText("mic-output", "enumerateDevices() unsupported.");
        return;
    };
    defer list_p.release();
    dom.document().setElemText("mic-output", "Enumerating media devices...");
    list_p.thenFn(AudioInputDemo, self, onDevicesEnumerated, onMediaError);
}

fn onDevicesEnumerated(_: *AudioInputDemo, devices_in: MediaDeviceInfo.List) void {
    var devices = devices_in;
    const total = devices.len();
    if (total == 0) {
        dom.document().setElemText("mic-output", "No media devices reported.");
        return;
    }

    var out_buf: [2048]u8 = undefined;
    var fbs = std.Io.Writer.fixed(&out_buf);
    fbs.print("Media devices ({d}):", .{total}) catch {};

    var idx: usize = 0;
    while (devices.next()) |dev| {
        defer dev.release();
        idx += 1;
        var label_buf: [160]u8 = undefined;
        var id_buf: [96]u8 = undefined;
        const lbl = dev.label(&label_buf);
        const did = dev.deviceId(&id_buf);
        const short_id = did[0..@min(did.len, 12)];
        fbs.print(
            "\n[{d}] {s}: {s} (id={s}{s})",
            .{
                idx,
                @tagName(dev.kind()),
                if (lbl.len > 0) lbl else "(label hidden until permission granted)",
                if (short_id.len > 0) short_id else "n/a",
                if (did.len > 12) "..." else "",
            },
        ) catch break;
    }
    dom.document().setElemText("mic-output", fbs.buffered());
}

fn onMediaError(self: *AudioInputDemo, err_h: zjb.Handle) void {
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
        "Audio input error ({s}): {s}",
        .{
            if (err_name.len > 0) err_name else "Error",
            if (err_msg.len > 0) err_msg else "permission denied or no microphone",
        },
    ) catch "Audio input failed (see console).";
    dom.document().setElemText("mic-output", text);
}
