const std = @import("std");
const webapi = @import("webapi");

const vertex_shader_src = @embedFile("shaders/triangle.vert");
const fragment_shader_src = @embedFile("shaders/triangle.frag");

const dom = webapi.dom;
const Event = webapi.Event;
const Fetch = webapi.Fetch;
const WebGL = webapi.WebGL;
const zjb = webapi.zjb;

pub const std_options: std.Options = .{
    .logFn = webapi.console.rootLogFn,
    .log_level = .debug,
};

pub const panic = zjb.panic;

pub fn main(init: std.process.Init.Minimal) !void {
    _ = init;
    const allocator = std.heap.wasm_allocator;

    const app = try App.init(allocator);
    app.bindUi();
    dom.window().requestAnimationFrame(app.frame_cb);

    std.log.info("webapi example initialized!", .{});
}

const App = struct {
    allocator: std.mem.Allocator,
    prng: std.Random.DefaultPrng,
    canvas: dom.Element,
    gl: WebGL,
    program: WebGL.Program,
    vbo: WebGL.Buffer,
    pos_loc: i32,
    u_angle: WebGL.UniformLocation,
    u_scale: WebGL.UniformLocation,
    u_offset: WebGL.UniformLocation,
    u_tint: WebGL.UniformLocation,
    frame_cb: zjb.Handle,
    angle: f32 = 0.0,
    scale: f32 = 1.0,
    offset: [2]f32 = .{ 0.0, 0.0 },
    dragging: bool = false,
    active_pointer_id: i32 = 0,
    last_x: f32 = 0.0,
    last_y: f32 = 0.0,
    tint: [3]f32 = .{ 1.0, 0.85, 0.55 },
    click_count: u32 = 0,
    wasi: ?*webapi.Wasi = null,
    worker: webapi.Worker = .null,

    fn init(allocator: std.mem.Allocator) !*App {
        const doc = dom.document();
        const canvas = doc.getElementById("gl-canvas") orelse
            return error.CanvasNotFound;

        const gl = try WebGL.fromCanvas(canvas);
        errdefer gl.release();

        const program = try gl.createProgramFromSource(
            vertex_shader_src,
            fragment_shader_src,
        );
        errdefer program.release();

        const vbo = gl.createBuffer();
        errdefer vbo.release();

        const vertices = [_]f32{
            0.0,   0.65,
            -0.58, -0.45,
            0.58,  -0.45,
        };
        gl.bindBuffer(WebGL.ARRAY_BUFFER, vbo);
        gl.bufferData(
            WebGL.ARRAY_BUFFER,
            std.mem.sliceAsBytes(&vertices),
            WebGL.STATIC_DRAW,
        );

        const pos_loc = gl.getAttribLocation(program, "a_pos");
        const u_angle = gl.getUniformLocation(program, "u_angle");
        const u_scale = gl.getUniformLocation(program, "u_scale");
        const u_offset = gl.getUniformLocation(program, "u_offset");
        const u_tint = gl.getUniformLocation(program, "u_tint");

        const self = try allocator.create(App);
        errdefer allocator.destroy(self);

        self.* = .{
            .allocator = allocator,
            .prng = webapi.PseudoRandomNumberGenerator(),
            .canvas = canvas,
            .gl = gl,
            .program = program,
            .vbo = vbo,
            .pos_loc = pos_loc,
            .u_angle = u_angle,
            .u_scale = u_scale,
            .u_offset = u_offset,
            .u_tint = u_tint,
            .frame_cb = .null,
        };
        self.frame_cb = webapi.boundFunction(App, self, onFrame);
        return self;
    }

    fn render(self: *App) void {
        const width = self.canvas.get("width", i32);
        const height = self.canvas.get("height", i32);
        self.gl.viewport(0, 0, width, height);
        self.gl.clearColor(0.08, 0.10, 0.15, 1.0);
        self.gl.clear(WebGL.COLOR_BUFFER_BIT);

        self.gl.useProgram(self.program);
        self.gl.bindBuffer(WebGL.ARRAY_BUFFER, self.vbo);
        if (self.pos_loc >= 0) {
            self.gl.enableVertexAttribArray(self.pos_loc);
            self.gl.vertexAttribPointer(
                self.pos_loc,
                2,
                WebGL.FLOAT,
                false,
                0,
                0,
            );
        }
        self.gl.uniform1f(self.u_angle, self.angle);
        self.gl.uniform1f(self.u_scale, self.scale);
        self.gl.uniform2f(self.u_offset, self.offset[0], self.offset[1]);
        self.gl.uniform3f(
            self.u_tint,
            self.tint[0],
            self.tint[1],
            self.tint[2],
        );
        self.gl.drawArrays(WebGL.TRIANGLES, 0, 3);
    }

    fn onFrame(self: *App, _: zjb.Handle) void {
        if (!self.dragging) {
            self.angle += 0.015;
        }
        self.render();
        dom.window().requestAnimationFrame(self.frame_cb);
    }

    fn onCanvasPointerDown(self: *App, ev: Event.PointerEvent) void {
        ev.preventDefault();
        self.dragging = true;
        self.active_pointer_id = ev.pointerId();
        self.last_x = ev.clientX();
        self.last_y = ev.clientY();
    }

    fn onWindowPointerMove(self: *App, ev: Event.PointerEvent) void {
        if (!self.dragging or ev.pointerId() != self.active_pointer_id) return;
        const x = ev.clientX();
        const y = ev.clientY();
        const dx = x - self.last_x;
        const dy = y - self.last_y;
        self.last_x = x;
        self.last_y = y;

        const w: f32 = @floatFromInt(@max(self.canvas.get("clientWidth", i32), 1));
        const h: f32 = @floatFromInt(@max(self.canvas.get("clientHeight", i32), 1));
        self.offset[0] = std.math.clamp(self.offset[0] + (dx * 2.0) / w, -0.85, 0.85);
        self.offset[1] = std.math.clamp(self.offset[1] - (dy * 2.0) / h, -0.85, 0.85);
        self.angle += dx * 0.01;
    }

    fn onWindowPointerUp(self: *App, ev: Event.PointerEvent) void {
        if (self.dragging and ev.pointerId() == self.active_pointer_id) {
            self.dragging = false;
        }
    }

    fn onCanvasWheel(self: *App, ev: Event.WheelEvent) void {
        ev.preventDefault();
        const factor = 1.0 - ev.deltaY() * 0.001;
        self.scale = std.math.clamp(self.scale * factor, 0.35, 2.2);
    }

    fn onCanvasDblClick(self: *App, _: Event.PointerEvent) void {
        self.offset = .{ 0.0, 0.0 };
        self.scale = 1.0;
    }

    fn onRandomColorClick(self: *App, ev: Event.PointerEvent) void {
        _ = ev;
        const rand = self.prng.random();
        self.tint = .{
            0.35 + 0.65 * rand.float(f32),
            0.35 + 0.65 * rand.float(f32),
            0.35 + 0.65 * rand.float(f32),
        };
        self.click_count += 1;

        var buf: [128]u8 = undefined;
        const status = std.fmt.bufPrint(
            &buf,
            "Clicks: {d} | Tint: ({d:.2}, {d:.2}, {d:.2})",
            .{ self.click_count, self.tint[0], self.tint[1], self.tint[2] },
        ) catch return;
        dom.document().setElemText("click-status", status);
        std.log.info("{s}", .{status});
    }

    fn onFetchClick(self: *App, _: Event.PointerEvent) void {
        dom.document().setElemText("fetch-output", "Fetching data.json...");
        const req = webapi.fetch("data.json", null);
        defer req.release();
        req.thenFn(App, self, onFetchResponse, onFetchError);
    }

    fn onFetchResponse(self: *App, resp: Fetch.Response) void {
        if (!resp.ok()) {
            var buf: [64]u8 = undefined;
            const msg = std.fmt.bufPrint(
                &buf,
                "HTTP error: {d}",
                .{resp.status()},
            ) catch "HTTP error";
            dom.document().setElemText("fetch-output", msg);
            return;
        }
        const text_p = resp.text();
        defer text_p.release();
        text_p.thenFn(App, self, onFetchText, onFetchError);
    }

    fn onFetchText(_: *App, text_h: zjb.Handle) void {
        var buf: [4096]u8 = undefined;
        const body = webapi.stringFromHandle(text_h, &buf);
        dom.document().setElemText("fetch-output", body);
    }

    fn onFetchError(_: *App, err_h: zjb.Handle) void {
        webapi.console.@"error"("Fetch failed:", .{err_h});
        dom.document().setElemText("fetch-output", "Fetch failed (see console).");
    }

    fn onWasiClick(self: *App, _: Event.PointerEvent) void {
        if (self.wasi) |w| {
            w.deinit();
            self.wasi = null;
        }
        dom.document().setElemText("wasi-output", "Loading wasi_hello.wasm...");
        const req = webapi.fetch("wasi_hello.wasm", null);
        defer req.release();
        req.thenFn(App, self, onWasiResponse, onWasiError);
    }

    fn onWasiResponse(self: *App, resp: Fetch.Response) void {
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
        ab_p.thenFn(App, self, onWasiBytes, onWasiError);
    }

    fn onWasiBytes(self: *App, buf_h: zjb.Handle) void {
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
        run_p.thenFn(App, self, onWasiDone, onWasiError);
    }

    fn onWasiDone(self: *App, exit_code: i32) void {
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

    fn onWasiError(self: *App, err_h: zjb.Handle) void {
        if (self.wasi) |w| {
            w.deinit();
            self.wasi = null;
        }
        webapi.console.@"error"("WASI failed:", .{err_h});
        dom.document().setElemText("wasi-output", "WASI failed (see console).");
    }

    fn onDownloadClick(self: *App, _: Event.PointerEvent) void {
        var buf: [256]u8 = undefined;
        const report = std.fmt.bufPrint(
            &buf,
            "webapi example report\nclicks={d}\ntint=({d:.2}, {d:.2}, {d:.2})\n",
            .{ self.click_count, self.tint[0], self.tint[1], self.tint[2] },
        ) catch return;
        webapi.download.bytes(.{
            .bytes = report,
            .filename = "webapi-report.txt",
            .mimetype = "text/plain",
        });
    }

    fn onTextInput(self: *App, ev: Event.InputEvent) void {
        const target_h = ev.asEvent().target();
        if (target_h.isNull()) return;
        defer target_h.release();

        const target_el = dom.Element.init(target_h);
        const val = (target_el.getValueAlloc(self.allocator) catch return) orelse
            return;
        defer self.allocator.free(val);

        dom.document().setElemText(
            "echo-output",
            if (val.len > 0) val else "(empty)",
        );
    }

    fn onWindowKeydown(_: *App, ev: Event.KeyboardEvent) void {
        var key_buf: [64]u8 = undefined;
        const key_name = ev.key(&key_buf);
        dom.document().setElemText("key-output", key_name);
    }

    fn formatHex(bytes: []const u8, out: []u8) []const u8 {
        const hex = "0123456789abcdef";
        const n = @min(bytes.len, out.len / 2);
        for (bytes[0..n], 0..) |b, i| {
            out[i * 2] = hex[b >> 4];
            out[i * 2 + 1] = hex[b & 0x0f];
        }
        return out[0 .. n * 2];
    }

    fn onCryptoRandomClick(_: *App, _: Event.PointerEvent) void {
        const crypto = webapi.crypto();
        var rand_bytes: [16]u8 = undefined;
        crypto.getRandomValues(&rand_bytes);

        var hex_buf: [32]u8 = undefined;
        const rand_hex = formatHex(&rand_bytes, &hex_buf);

        var uuid_buf: [64]u8 = undefined;
        const uuid = crypto.randomUUID(&uuid_buf);

        var out_buf: [256]u8 = undefined;
        const msg = std.fmt.bufPrint(
            &out_buf,
            "randomUUID:      {s}\ngetRandomValues: {s}",
            .{
                if (uuid.len > 0) uuid else "(requires secure context)",
                rand_hex,
            },
        ) catch return;
        dom.document().setElemText("crypto-output", msg);
    }

    fn onCryptoDigestClick(self: *App, _: Event.PointerEvent) void {
        const subtle = webapi.crypto().subtle();
        defer subtle.release();
        if (subtle.isNull()) {
            dom.document().setElemText(
                "crypto-output",
                "crypto.subtle requires a secure context (HTTPS or localhost).",
            );
            return;
        }

        const doc = dom.document();
        var input_owned: ?[]u8 = null;
        defer if (input_owned) |buf| self.allocator.free(buf);

        var input: []const u8 = "hello from zig-webapi";
        if (doc.getElementById("text-input")) |el| {
            defer el.release();
            if (el.getValueAlloc(self.allocator) catch null) |val| {
                input_owned = val;
                if (val.len > 0) input = val;
            }
        }

        const digest_p = subtle.digest(.@"SHA-256", input);
        defer digest_p.release();
        digest_p.thenFn(App, self, onCryptoDigestDone, onCryptoError);
    }

    fn onCryptoDigestDone(self: *App, buf_h: zjb.Handle) void {
        const bytes = webapi.bytesFromHandleAlloc(self.allocator, buf_h) catch {
            dom.document().setElemText("crypto-output", "Failed to read digest bytes.");
            return;
        };
        defer self.allocator.free(bytes);

        var hex_buf: [128]u8 = undefined;
        const digest_hex = formatHex(bytes, &hex_buf);

        var out_buf: [192]u8 = undefined;
        const msg = std.fmt.bufPrint(
            &out_buf,
            "SHA-256 ({d} bytes):\n{s}",
            .{ bytes.len, digest_hex },
        ) catch return;
        dom.document().setElemText("crypto-output", msg);
    }

    fn onCryptoError(_: *App, err_h: zjb.Handle) void {
        webapi.console.@"error"("Web Crypto failed:", .{err_h});
        dom.document().setElemText("crypto-output", "Web Crypto failed (see console).");
    }

    fn onWorkerSendClick(self: *App, _: Event.PointerEvent) void {
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
            w.addEventListener("message", App, self, onWorkerMessage);
            w.addEventListener("error", App, self, onWorkerError);
            self.worker = w;
            dom.document().setElemText("worker-output", "Starting worker.wasm...");
        }

        const doc = dom.document();
        var input_owned: ?[]u8 = null;
        defer if (input_owned) |buf| self.allocator.free(buf);

        var input: []const u8 = "hello from main thread";
        if (doc.getElementById("text-input")) |el| {
            defer el.release();
            if (el.getValueAlloc(self.allocator) catch null) |val| {
                input_owned = val;
                if (val.len > 0) input = val;
            }
        }

        self.worker.postText(input);
    }

    fn onWorkerTerminateClick(self: *App, _: Event.PointerEvent) void {
        if (self.worker.isNull()) {
            dom.document().setElemText("worker-output", "No active worker.");
            return;
        }
        self.worker.terminate();
        self.worker.release();
        self.worker = .null;
        dom.document().setElemText("worker-output", "Worker terminated.");
    }

    fn onWorkerMessage(_: *App, ev: Event.MessageEvent) void {
        const data_h = ev.data();
        defer data_h.release();
        var buf: [1024]u8 = undefined;
        const text = webapi.stringFromHandle(data_h, &buf);
        dom.document().setElemText("worker-output", text);
    }

    fn onWorkerError(_: *App, ev: Event.ErrorEvent) void {
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

    fn bindUi(self: *App) void {
        const doc = dom.document();

        if (doc.getElementById("btn-color")) |btn| {
            defer btn.release();
            btn.addEventListener("click", App, self, onRandomColorClick);
        }
        if (doc.getElementById("btn-fetch")) |btn| {
            defer btn.release();
            btn.addEventListener("click", App, self, onFetchClick);
        }
        if (doc.getElementById("btn-download")) |btn| {
            defer btn.release();
            btn.addEventListener("click", App, self, onDownloadClick);
        }
        if (doc.getElementById("btn-wasi")) |btn| {
            defer btn.release();
            btn.addEventListener("click", App, self, onWasiClick);
        }
        if (doc.getElementById("btn-worker-send")) |btn| {
            defer btn.release();
            btn.addEventListener("click", App, self, onWorkerSendClick);
        }
        if (doc.getElementById("btn-worker-terminate")) |btn| {
            defer btn.release();
            btn.addEventListener("click", App, self, onWorkerTerminateClick);
        }
        if (doc.getElementById("btn-crypto-uuid")) |btn| {
            defer btn.release();
            btn.addEventListener("click", App, self, onCryptoRandomClick);
        }
        if (doc.getElementById("btn-crypto-digest")) |btn| {
            defer btn.release();
            btn.addEventListener("click", App, self, onCryptoDigestClick);
        }
        if (doc.getElementById("text-input")) |input| {
            defer input.release();
            input.addEventListener("input", App, self, onTextInput);
        }

        self.canvas.addEventListener("pointerdown", App, self, onCanvasPointerDown);
        self.canvas.addEventListener("wheel", App, self, onCanvasWheel);
        self.canvas.addEventListener("dblclick", App, self, onCanvasDblClick);

        const win = dom.window();
        win.addEventListener("pointermove", App, self, onWindowPointerMove);
        win.addEventListener("pointerup", App, self, onWindowPointerUp);
        win.addEventListener("pointercancel", App, self, onWindowPointerUp);
        win.addEventListener("keydown", App, self, onWindowKeydown);

        const loc = win.location();
        defer loc.release();
        var url_buf: [512]u8 = undefined;
        const href = loc.getHref(&url_buf);
        doc.setElemText("page-url", href);
    }
};
