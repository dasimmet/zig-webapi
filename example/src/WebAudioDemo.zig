//! Web Audio API playback demo (synthesized 523.25 Hz PCM `AudioBuffer` and
//! `decodeAudioData` playback of `blue-beep.mp3`).

// 1. Imports
const std = @import("std");
const webapi = @import("webapi");

// 2. Shortcuts on imports
const WebAudioDemo = @This();
const dom = webapi.dom;
const Event = webapi.Event;
const Fetch = webapi.Fetch;
const WebAudio = webapi.WebAudio;
const zjb = webapi.zjb;

// 3. File-level struct members
allocator: std.mem.Allocator,
audio_ctx: WebAudio.AudioContext = .null,
beep_buffer: WebAudio.AudioBuffer = .null,
beep_loading: bool = false,

// 7. Public functions
/// Attaches `#btn-audio-pcm` and `#btn-audio-mp3` click listeners.
pub fn bind(self: *WebAudioDemo) void {
    const doc = dom.document();
    if (doc.getElementById("btn-audio-pcm")) |btn| {
        defer btn.release();
        btn.addEventListener("click", WebAudioDemo, self, onAudioPcmClick);
    }
    if (doc.getElementById("btn-audio-mp3")) |btn| {
        defer btn.release();
        btn.addEventListener("click", WebAudioDemo, self, onAudioMp3Click);
    }
}

// 9. Private declarations
fn ensureAudioContext(self: *WebAudioDemo) ?WebAudio.AudioContext {
    if (!WebAudio.AudioContext.isSupported()) {
        dom.document().setElemText(
            "audio-output",
            "Web Audio API is not supported in this browser.",
        );
        return null;
    }
    if (self.audio_ctx.isNull()) {
        self.audio_ctx = WebAudio.AudioContext.init();
        if (self.audio_ctx.isNull()) {
            dom.document().setElemText(
                "audio-output",
                "Failed to create AudioContext.",
            );
            return null;
        }
    }
    if (self.audio_ctx.state() == .suspended) {
        const p = self.audio_ctx.@"resume"();
        p.release();
    }
    return self.audio_ctx;
}

fn onAudioPcmClick(self: *WebAudioDemo, _: Event.PointerEvent) void {
    const ctx = self.ensureAudioContext() orelse return;
    const sample_rate = ctx.sampleRate();
    const duration_sec: f32 = 1.0;
    const frame_count: usize = @intFromFloat(sample_rate * duration_sec);

    const samples = self.allocator.alloc(f32, frame_count) catch {
        dom.document().setElemText(
            "audio-output",
            "Failed to allocate PCM sample buffer.",
        );
        return;
    };
    defer self.allocator.free(samples);

    const freq_hz: f32 = 523.25;
    const fade_frames: usize = @intFromFloat(sample_rate * 0.02);
    for (samples, 0..) |*s, i| {
        const t: f32 = @as(f32, @floatFromInt(i)) / sample_rate;
        var env: f32 = 0.25;
        if (i < fade_frames) {
            env *= @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(fade_frames));
        } else if (i + fade_frames >= frame_count) {
            const rem = frame_count - 1 - i;
            env *= @as(f32, @floatFromInt(rem)) / @as(f32, @floatFromInt(fade_frames));
        }
        s.* = env * @sin(2.0 * std.math.pi * freq_hz * t);
    }

    const audio_buf = ctx.createBuffer(1, @intCast(frame_count), sample_rate);
    defer audio_buf.release();
    audio_buf.copyToChannel(samples, 0, 0);

    const src = ctx.createBufferSource();
    defer src.release();
    src.setBuffer(audio_buf);

    const dest = ctx.destination();
    defer dest.release();
    src.connect(dest);
    src.addEventListener("ended", WebAudioDemo, self, onAudioPcmEnded);
    src.start();

    var buf: [128]u8 = undefined;
    const msg = std.fmt.bufPrint(
        &buf,
        "Playing 523.25 Hz PCM sine AudioBuffer ({d} frames @ {d:.0} Hz)...",
        .{ frame_count, sample_rate },
    ) catch return;
    dom.document().setElemText("audio-output", msg);
}

fn onAudioMp3Click(self: *WebAudioDemo, _: Event.PointerEvent) void {
    _ = self.ensureAudioContext() orelse return;
    if (!self.beep_buffer.isNull()) {
        self.playBeepBuffer();
        return;
    }
    if (self.beep_loading) return;
    self.beep_loading = true;
    dom.document().setElemText("audio-output", "Fetching blue-beep.mp3...");

    const resp_p = webapi.fetch("blue-beep.mp3", null);
    defer resp_p.release();
    resp_p.thenFn(WebAudioDemo, self, onAudioMp3Response, onAudioError);
}

fn onAudioMp3Response(self: *WebAudioDemo, resp: Fetch.Response) void {
    if (!resp.ok()) {
        self.beep_loading = false;
        var buf: [64]u8 = undefined;
        const msg = std.fmt.bufPrint(
            &buf,
            "Failed to fetch blue-beep.mp3: HTTP {d}",
            .{resp.status()},
        ) catch "Failed to fetch blue-beep.mp3";
        dom.document().setElemText("audio-output", msg);
        return;
    }
    const ab_p = resp.arrayBuffer();
    defer ab_p.release();
    ab_p.thenFn(WebAudioDemo, self, onAudioMp3Bytes, onAudioError);
}

fn onAudioMp3Bytes(self: *WebAudioDemo, buf_h: zjb.Handle) void {
    if (self.audio_ctx.isNull()) {
        self.beep_loading = false;
        return;
    }
    dom.document().setElemText("audio-output", "Decoding blue-beep.mp3...");
    const dec_p = self.audio_ctx.decodeAudioData(buf_h);
    defer dec_p.release();
    dec_p.thenFn(WebAudioDemo, self, onAudioMp3Decoded, onAudioError);
}

fn onAudioMp3Decoded(self: *WebAudioDemo, decoded: WebAudio.AudioBuffer) void {
    self.beep_loading = false;
    if (!self.beep_buffer.isNull()) {
        self.beep_buffer.release();
    }
    self.beep_buffer = WebAudio.AudioBuffer.fromHandle(
        webapi.retainHandle(decoded.handle),
    );
    self.playBeepBuffer();
}

fn playBeepBuffer(self: *WebAudioDemo) void {
    const ctx = self.ensureAudioContext() orelse return;
    if (self.beep_buffer.isNull()) return;

    const src = ctx.createBufferSource();
    defer src.release();
    src.setBuffer(self.beep_buffer);

    const dest = ctx.destination();
    defer dest.release();
    src.connect(dest);
    src.addEventListener("ended", WebAudioDemo, self, onAudioMp3Ended);
    src.start();

    var buf: [160]u8 = undefined;
    const msg = std.fmt.bufPrint(
        &buf,
        "Playing blue-beep.mp3 ({d:.2}s, {d} ch, {d:.0} Hz)...",
        .{
            self.beep_buffer.duration(),
            self.beep_buffer.numberOfChannels(),
            self.beep_buffer.sampleRate(),
        },
    ) catch return;
    dom.document().setElemText("audio-output", msg);
}

fn onAudioPcmEnded(_: *WebAudioDemo, _: Event) void {
    dom.document().setElemText("audio-output", "PCM sine AudioBuffer finished.");
}

fn onAudioMp3Ended(_: *WebAudioDemo, _: Event) void {
    dom.document().setElemText("audio-output", "blue-beep.mp3 playback finished.");
}

fn onAudioError(self: *WebAudioDemo, err_h: zjb.Handle) void {
    self.beep_loading = false;
    webapi.console.@"error"("Web Audio failed:", .{err_h});
    dom.document().setElemText(
        "audio-output",
        "Web Audio failed (see console).",
    );
}
