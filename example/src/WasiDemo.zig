//! In-browser WASI Snapshot Preview 1 execution demo (`wasi_hello.wasm`).

// 1. Imports
const std = @import("std");
const webapi = @import("webapi");

// 2. Shortcuts on imports
const WasiDemo = @This();
const dom = webapi.dom;
const Event = webapi.Event;
const Fetch = webapi.Fetch;
const zjb = webapi.zjb;

// 3. File-level struct members
allocator: std.mem.Allocator,
wasi: ?*webapi.Wasi = null,

// 7. Public functions
/// Attaches the `#btn-wasi` click listener.
pub fn bind(self: *WasiDemo) void {
    if (dom.document().getElementById("btn-wasi")) |btn| {
        defer btn.release();
        btn.addEventListener("click", WasiDemo, self, onWasiClick);
    }
}

// 9. Private declarations
fn onWasiClick(self: *WasiDemo, _: Event.PointerEvent) void {
    if (self.wasi) |w| {
        w.deinit();
        self.wasi = null;
    }
    dom.document().setElemText("wasi-output", "Loading wasi_hello.wasm...");
    const req = webapi.fetch("wasi_hello.wasm", null);
    defer req.release();
    req.thenFn(WasiDemo, self, onWasiResponse, onWasiError);
}

fn onWasiResponse(self: *WasiDemo, resp: Fetch.Response) void {
    if (!resp.ok()) {
        var buf: [64]u8 = undefined;
        const msg = std.fmt.bufPrint(
            &buf,
            "HTTP error: {d}",
            .{resp.status()},
        ) catch "HTTP error";
        dom.document().setElemText("wasi-output", msg);
        return;
    }
    const ab_p = resp.arrayBuffer();
    defer ab_p.release();
    ab_p.thenFn(WasiDemo, self, onWasiBytes, onWasiError);
}

fn onWasiBytes(self: *WasiDemo, buf_h: zjb.Handle) void {
    const wasm_bytes = webapi.bytesFromHandleAlloc(self.allocator, buf_h) catch {
        dom.document().setElemText("wasi-output", "Failed to read WASM bytes.");
        return;
    };
    defer self.allocator.free(wasm_bytes);

    const wasi = webapi.Wasi.init(.{
        .allocator = self.allocator,
        .args = &.{"wasi_hello.wasm"},
    }) catch {
        dom.document().setElemText("wasi-output", "Failed to initialize WASI.");
        return;
    };
    self.wasi = wasi;

    const run_p = wasi.runWasmAsync(wasm_bytes) catch {
        wasi.deinit();
        self.wasi = null;
        dom.document().setElemText("wasi-output", "Failed to start WASI binary.");
        return;
    };
    defer run_p.release();
    run_p.thenFn(WasiDemo, self, onWasiDone, onWasiError);
}

fn onWasiDone(self: *WasiDemo, exit_code: i32) void {
    const wasi = self.wasi orelse return;
    defer {
        wasi.deinit();
        self.wasi = null;
    }

    const stdout = wasi.getStdout();
    const stderr = wasi.getStderr();
    var buf: [1024]u8 = undefined;
    const msg = std.fmt.bufPrint(
        &buf,
        "exit_code={d}\nstdout:\n{s}{s}{s}",
        .{
            exit_code,
            stdout,
            if (stderr.len > 0) "\nstderr:\n" else "",
            stderr,
        },
    ) catch "WASI completed (output truncated).";
    dom.document().setElemText("wasi-output", msg);
}

fn onWasiError(self: *WasiDemo, err_h: zjb.Handle) void {
    if (self.wasi) |w| {
        w.deinit();
        self.wasi = null;
    }
    webapi.console.@"error"("WASI failed:", .{err_h});
    dom.document().setElemText("wasi-output", "WASI failed (see console).");
}
