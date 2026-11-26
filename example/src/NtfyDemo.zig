//! WebSocket subscription and HTTP Fetch publishing demo against `ntfy.sh`.

// 1. Imports
const std = @import("std");
const webapi = @import("webapi");

// 2. Shortcuts on imports
const NtfyDemo = @This();
const dom = webapi.dom;
const Event = webapi.Event;
const Fetch = webapi.Fetch;
const WebSocket = webapi.WebSocket;
const zjb = webapi.zjb;

// 3. File-level struct members
allocator: std.mem.Allocator,
ws: WebSocket = .null,
log_buf: std.ArrayList(u8) = .empty,

// 6. Types
const NtfyPacket = struct {
    id: []const u8 = "",
    time: i64 = 0,
    event: []const u8 = "",
    topic: []const u8 = "",
    title: ?[]const u8 = null,
    message: ?[]const u8 = null,
    priority: ?i32 = null,
};

// 7. Public functions
/// Attaches `#btn-ntfy-connect` and `#btn-ntfy-publish` click listeners.
pub fn bind(self: *NtfyDemo) void {
    const doc = dom.document();
    if (doc.getElementById("btn-ntfy-connect")) |btn| {
        defer btn.release();
        btn.addEventListener("click", NtfyDemo, self, onConnectClick);
    }
    if (doc.getElementById("btn-ntfy-publish")) |btn| {
        defer btn.release();
        btn.addEventListener("click", NtfyDemo, self, onPublishClick);
    }
}

// 9. Private declarations
fn onConnectClick(self: *NtfyDemo, _: Event.PointerEvent) void {
    if (!WebSocket.isSupported()) {
        self.appendLog("WebSocket is not supported in this browser.");
        return;
    }

    if (!self.ws.isNull()) {
        const state = self.ws.readyState();
        if (state == .OPEN or state == .CONNECTING) {
            self.ws.closeWithCode(.normal_closure, "user disconnect");
            self.ws.release();
            self.ws = .null;
            dom.document().setElemText("btn-ntfy-connect", "Connect WebSocket");
            self.appendLog("Disconnected from ntfy.sh WebSocket.");
            return;
        }
        self.ws.release();
        self.ws = .null;
    }

    var topic_buf: [128]u8 = undefined;
    const topic = readTopic(&topic_buf) orelse {
        self.appendLog("Invalid topic (use 1-64 chars: letters, digits, '-' or '_').");
        return;
    };

    var url_buf: [192]u8 = undefined;
    const ws_url = std.fmt.bufPrint(&url_buf, "wss://ntfy.sh/{s}/ws", .{topic}) catch return;

    const ws = WebSocket.initWithOptions(ws_url, .{ .binary_type = .arraybuffer });
    if (ws.isNull()) {
        self.appendLog("Failed to construct WebSocket.");
        return;
    }
    ws.addEventListener("open", NtfyDemo, self, onWsOpen);
    ws.addEventListener("message", NtfyDemo, self, onWsMessage);
    ws.addEventListener("close", NtfyDemo, self, onWsClose);
    ws.addEventListener("error", NtfyDemo, self, onWsError);
    self.ws = ws;

    dom.document().setElemText("btn-ntfy-connect", "Disconnect");
    var msg_buf: [256]u8 = undefined;
    const line = std.fmt.bufPrint(&msg_buf, "Connecting to {s}...", .{ws_url}) catch return;
    self.appendLog(line);
}

fn onPublishClick(self: *NtfyDemo, _: Event.PointerEvent) void {
    var topic_buf: [128]u8 = undefined;
    const topic = readTopic(&topic_buf) orelse {
        self.appendLog("Invalid topic (use 1-64 chars: letters, digits, '-' or '_').");
        return;
    };

    var url_buf: [192]u8 = undefined;
    const post_url = std.fmt.bufPrint(&url_buf, "https://ntfy.sh/{s}", .{topic}) catch return;

    var msg_owned: ?[]u8 = null;
    defer if (msg_owned) |buf| self.allocator.free(buf);
    var body: []const u8 = "Hello from zig-webapi!";
    if (dom.document().getElementById("ntfy-message")) |input_el| {
        defer input_el.release();
        if (input_el.getValueAlloc(self.allocator) catch null) |val| {
            msg_owned = val;
            if (val.len > 0) body = val;
        }
    }

    const headers = Fetch.Headers.init();
    defer headers.release();
    headers.set("Title", "zig-webapi");
    headers.set("Tags", "zap");

    const req = webapi.fetch(post_url, .{
        .method = "POST",
        .headers = headers,
        .body = body,
    });
    defer req.release();
    req.thenFn(NtfyDemo, self, onPublishResponse, onPublishError);

    var log_line: [256]u8 = undefined;
    const text = std.fmt.bufPrint(&log_line, "Publishing to {s}...", .{post_url}) catch return;
    self.appendLog(text);
}

fn onWsOpen(self: *NtfyDemo, _: Event) void {
    var url_buf: [192]u8 = undefined;
    const resolved = if (!self.ws.isNull()) self.ws.url(&url_buf) else "ntfy.sh";
    var line_buf: [256]u8 = undefined;
    const line = std.fmt.bufPrint(
        &line_buf,
        "WebSocket OPEN: {s}",
        .{if (resolved.len > 0) resolved else "wss://ntfy.sh"},
    ) catch "WebSocket OPEN.";
    self.appendLog(line);
}

fn onWsMessage(self: *NtfyDemo, ev: WebSocket.MessageEvent) void {
    const raw = ev.dataTextAlloc(self.allocator) catch {
        self.appendLog("Received non-text WebSocket frame.");
        return;
    };
    defer self.allocator.free(raw);

    const parsed = std.json.parseFromSlice(
        NtfyPacket,
        self.allocator,
        raw,
        .{ .ignore_unknown_fields = true },
    ) catch {
        self.appendLog(raw);
        return;
    };
    defer parsed.deinit();

    const pkt = parsed.value;
    var line_buf: [512]u8 = undefined;
    const line = if (std.mem.eql(u8, pkt.event, "message")) blk: {
        const title = pkt.title orelse pkt.topic;
        const msg = pkt.message orelse "";
        break :blk std.fmt.bufPrint(
            &line_buf,
            "[{s}] {s}: {s}",
            .{ pkt.event, title, msg },
        ) catch raw;
    } else std.fmt.bufPrint(
        &line_buf,
        "[{s}] topic={s} id={s}",
        .{ pkt.event, pkt.topic, pkt.id },
    ) catch raw;

    self.appendLog(line);
}

fn onWsClose(self: *NtfyDemo, ev: WebSocket.CloseEvent) void {
    var reason_buf: [128]u8 = undefined;
    const reason = ev.reason(&reason_buf);
    var line_buf: [256]u8 = undefined;
    const line = std.fmt.bufPrint(
        &line_buf,
        "WebSocket CLOSED (code={d} [{s}], clean={}, reason={s})",
        .{
            ev.code(),
            @tagName(ev.closeCode()),
            ev.wasClean(),
            if (reason.len > 0) reason else "none",
        },
    ) catch "WebSocket CLOSED.";
    self.appendLog(line);
    dom.document().setElemText("btn-ntfy-connect", "Connect WebSocket");
}

fn onWsError(self: *NtfyDemo, _: Event) void {
    self.appendLog("WebSocket ERROR (see browser console for details).");
}

fn onPublishResponse(self: *NtfyDemo, resp: Fetch.Response) void {
    var line_buf: [128]u8 = undefined;
    const line = std.fmt.bufPrint(
        &line_buf,
        "Publish HTTP {d} ({s})",
        .{ resp.status(), if (resp.ok()) "ok" else "error" },
    ) catch "Publish completed.";
    self.appendLog(line);
}

fn onPublishError(self: *NtfyDemo, err_h: zjb.Handle) void {
    webapi.console.@"error"("ntfy publish failed:", .{err_h});
    self.appendLog("Publish failed (see browser console).");
}

fn appendLog(self: *NtfyDemo, line: []const u8) void {
    if (self.log_buf.items.len > 3000) {
        self.log_buf.clearRetainingCapacity();
    }
    if (self.log_buf.items.len > 0) {
        self.log_buf.append(self.allocator, '\n') catch return;
    }
    self.log_buf.appendSlice(self.allocator, line) catch return;
    dom.document().setElemText("ntfy-output", self.log_buf.items);
}

fn readTopic(buf: []u8) ?[]const u8 {
    const fallback = "zig-webapi-demo";
    const doc = dom.document();
    const input_el = doc.getElementById("ntfy-topic") orelse {
        @memcpy(buf[0..fallback.len], fallback);
        return buf[0..fallback.len];
    };
    defer input_el.release();

    const raw_h = input_el.handle.get("value", zjb.Handle);
    defer raw_h.release();
    const val = webapi.stringFromHandle(raw_h, buf);
    const trimmed = std.mem.trim(u8, val, " \t\r\n");
    if (trimmed.len == 0) {
        @memcpy(buf[0..fallback.len], fallback);
        return buf[0..fallback.len];
    }
    if (trimmed.len > 64) return null;
    for (trimmed) |ch| {
        const ok = std.ascii.isAlphanumeric(ch) or ch == '-' or ch == '_';
        if (!ok) return null;
    }
    return trimmed;
}
