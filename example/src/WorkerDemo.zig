//! Dedicated Web Worker (`webapi.Worker`) message passing and termination demo.

// 1. Imports
const std = @import("std");
const webapi = @import("webapi");
const DomEventsDemo = @import("DomEventsDemo.zig");

// 2. Shortcuts on imports
const WorkerDemo = @This();
const dom = webapi.dom;
const Event = webapi.Event;

// 3. File-level struct members
allocator: std.mem.Allocator,
worker: webapi.Worker = .null,

// 7. Public functions
/// Attaches `#btn-worker-send` and `#btn-worker-terminate` click listeners.
pub fn bind(self: *WorkerDemo) void {
    const doc = dom.document();
    if (doc.getElementById("btn-worker-send")) |btn| {
        defer btn.release();
        btn.addEventListener("click", WorkerDemo, self, onWorkerSendClick);
    }
    if (doc.getElementById("btn-worker-terminate")) |btn| {
        defer btn.release();
        btn.addEventListener("click", WorkerDemo, self, onWorkerTerminateClick);
    }
}

// 9. Private declarations
fn onWorkerSendClick(self: *WorkerDemo, _: Event.PointerEvent) void {
    if (!webapi.Worker.isSupported()) {
        dom.document().setElemText(
            "worker-output",
            "Web Workers are not supported in this environment.",
        );
        return;
    }

    if (self.worker.isNull()) {
        const w = webapi.Worker.init("worker.js", .{
            .type = .module,
            .name = "zig-worker",
        });
        if (w.isNull()) {
            dom.document().setElemText("worker-output", "Failed to start Worker.");
            return;
        }
        w.addEventListener("message", WorkerDemo, self, onWorkerMessage);
        w.addEventListener("error", WorkerDemo, self, onWorkerError);
        self.worker = w;
        dom.document().setElemText("worker-output", "Starting worker.wasm...");
    }

    const input = DomEventsDemo.readInputOrFallback(
        self.allocator,
        "hello from main thread",
    );
    defer input.deinit(self.allocator);

    self.worker.postText(input.text);
}

fn onWorkerTerminateClick(self: *WorkerDemo, _: Event.PointerEvent) void {
    if (self.worker.isNull()) {
        dom.document().setElemText("worker-output", "No active worker.");
        return;
    }
    self.worker.terminate();
    self.worker.release();
    self.worker = .null;
    dom.document().setElemText("worker-output", "Worker terminated.");
}

fn onWorkerMessage(_: *WorkerDemo, ev: Event.MessageEvent) void {
    const data_h = ev.data();
    defer data_h.release();
    var buf: [1024]u8 = undefined;
    const text = webapi.stringFromHandle(data_h, &buf);
    dom.document().setElemText("worker-output", text);
}

fn onWorkerError(_: *WorkerDemo, ev: Event.ErrorEvent) void {
    var msg_buf: [256]u8 = undefined;
    const msg = ev.message(&msg_buf);
    var out_buf: [320]u8 = undefined;
    const text = std.fmt.bufPrint(
        &out_buf,
        "Worker error (line {d}): {s}",
        .{ ev.lineno(), if (msg.len > 0) msg else "unknown error" },
    ) catch "Worker error (see console).";
    dom.document().setElemText("worker-output", text);
}
