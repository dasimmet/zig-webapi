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
    u_tint: WebGL.UniformLocation,
    frame_cb: zjb.Handle,
    angle: f32 = 0.0,
    tint: [3]f32 = .{ 1.0, 0.85, 0.55 },
    click_count: u32 = 0,

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
        self.gl.uniform3f(
            self.u_tint,
            self.tint[0],
            self.tint[1],
            self.tint[2],
        );
        self.gl.drawArrays(WebGL.TRIANGLES, 0, 3);
    }

    fn onFrame(self: *App, _: zjb.Handle) void {
        self.angle += 0.015;
        self.render();
        dom.window().requestAnimationFrame(self.frame_cb);
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
        if (doc.getElementById("text-input")) |input| {
            defer input.release();
            input.addEventListener("input", App, self, onTextInput);
        }

        const win = dom.window();
        win.addEventListener("keydown", App, self, onWindowKeydown);

        const loc = win.location();
        defer loc.release();
        var url_buf: [512]u8 = undefined;
        const href = loc.getHref(&url_buf);
        doc.setElemText("page-url", href);
    }
};
