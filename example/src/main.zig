const std = @import("std");
const webapi = @import("webapi");

const vertex_shader_src = @embedFile("shaders/cube.vert");
const fragment_shader_src = @embedFile("shaders/cube.frag");
const banner_vertex_shader_src = @embedFile("shaders/banner.vert");
const banner_fragment_shader_src = @embedFile("shaders/banner.frag");

const dom = webapi.dom;
const Event = webapi.Event;
const Fetch = webapi.Fetch;
const WebAudio = webapi.WebAudio;
const WebGL = webapi.WebGL;
const zjb = webapi.zjb;

const default_banner_text = "Hello from Zig WASM";
const banner_tex_width: i32 = 1024;
const banner_tex_height: i32 = 128;

const Vertex = extern struct {
    pos: [3]f32,
    uv: [2]f32,
    normal: [3]f32,
};

const BannerVertex = extern struct {
    pos: [2]f32,
    uv: [2]f32,
};

const banner_vertices = [_]BannerVertex{
    .{ .pos = .{ -0.90, 0.54 }, .uv = .{ 0.0, 1.0 } },
    .{ .pos = .{ 0.90, 0.54 }, .uv = .{ 1.0, 1.0 } },
    .{ .pos = .{ 0.90, 0.94 }, .uv = .{ 1.0, 0.0 } },
    .{ .pos = .{ -0.90, 0.54 }, .uv = .{ 0.0, 1.0 } },
    .{ .pos = .{ 0.90, 0.94 }, .uv = .{ 1.0, 0.0 } },
    .{ .pos = .{ -0.90, 0.94 }, .uv = .{ 0.0, 0.0 } },
};

const cube_vertices = vertices: {
    // Faces are in dice.svg tile order, with opposite faces summing to seven.
    const faces = [_]struct { normal: [3]f32, corners: [4][3]f32 }{
        .{ .normal = .{ 0, 0, 1 }, .corners = .{ .{ -0.5, -0.5, 0.5 }, .{ 0.5, -0.5, 0.5 }, .{ 0.5, 0.5, 0.5 }, .{ -0.5, 0.5, 0.5 } } },
        .{ .normal = .{ 0, 1, 0 }, .corners = .{ .{ -0.5, 0.5, -0.5 }, .{ -0.5, 0.5, 0.5 }, .{ 0.5, 0.5, 0.5 }, .{ 0.5, 0.5, -0.5 } } },
        .{ .normal = .{ -1, 0, 0 }, .corners = .{ .{ -0.5, -0.5, -0.5 }, .{ -0.5, -0.5, 0.5 }, .{ -0.5, 0.5, 0.5 }, .{ -0.5, 0.5, -0.5 } } },
        .{ .normal = .{ 1, 0, 0 }, .corners = .{ .{ 0.5, -0.5, 0.5 }, .{ 0.5, -0.5, -0.5 }, .{ 0.5, 0.5, -0.5 }, .{ 0.5, 0.5, 0.5 } } },
        .{ .normal = .{ 0, -1, 0 }, .corners = .{ .{ -0.5, -0.5, -0.5 }, .{ 0.5, -0.5, -0.5 }, .{ 0.5, -0.5, 0.5 }, .{ -0.5, -0.5, 0.5 } } },
        .{ .normal = .{ 0, 0, -1 }, .corners = .{ .{ 0.5, -0.5, -0.5 }, .{ -0.5, -0.5, -0.5 }, .{ -0.5, 0.5, -0.5 }, .{ 0.5, 0.5, -0.5 } } },
    };
    const indices = [_]usize{ 0, 1, 2, 0, 2, 3 };
    // Sample within each tile's texel centers; the canvas uploads top row first.
    const uv_corners = [4][2]f32{ .{ 0.5, 127.5 }, .{ 127.5, 127.5 }, .{ 127.5, 0.5 }, .{ 0.5, 0.5 } };
    var vertices: [faces.len * indices.len]Vertex = undefined;
    for (faces, 0..) |face, tile| {
        const x: f32 = @floatFromInt(tile % 3 * 128);
        const y: f32 = @floatFromInt(tile / 3 * 128);
        for (indices, 0..) |corner, i| {
            const uv = uv_corners[corner];
            vertices[tile * indices.len + i] = .{
                .pos = face.corners[corner],
                .uv = .{ (x + uv[0]) / 384, (y + uv[1]) / 256 },
                .normal = face.normal,
            };
        }
    }
    break :vertices vertices;
};

pub const std_options: std.Options = .{
    .logFn = webapi.console.rootLogFn,
    .log_level = switch (@import("builtin").optimize) {
        .debug => .debug,
        else => .info,
    },
};

pub const panic = webapi.panic;

pub fn main(init: std.process.Init.Minimal) !void {
    _ = init;
    const allocator = std.heap.wasm_allocator;

    const app = try App.init(allocator);
    app.bindUi();
    app.updateBannerText(default_banner_text);
    app.rasterizeDice();

    std.log.info("webapi example initialized!", .{});
}

const App = struct {
    allocator: std.mem.Allocator,
    prng: std.Random.DefaultPrng,
    canvas: dom.Element,
    gl: WebGL,
    program: WebGL.Program,
    vbo: WebGL.Buffer,
    texture: WebGL.Texture,
    pos_loc: i32,
    uv_loc: i32,
    normal_loc: i32,
    u_yaw: WebGL.UniformLocation,
    u_pitch: WebGL.UniformLocation,
    u_scale: WebGL.UniformLocation,
    u_aspect: WebGL.UniformLocation,
    u_dice: WebGL.UniformLocation,
    u_tint: WebGL.UniformLocation,
    banner_program: WebGL.Program,
    banner_vbo: WebGL.Buffer,
    banner_texture: WebGL.Texture,
    banner_pos_loc: i32,
    banner_uv_loc: i32,
    u_banner: WebGL.UniformLocation,
    frame_cb: zjb.Handle,
    dice_source: ?struct { image: webapi.Image, url: zjb.Handle } = null,
    yaw: f32 = 0.65,
    pitch: f32 = -0.45,
    scale: f32 = 1.0,
    last_frame_ms: ?f64 = null,
    dragging: bool = false,
    active_pointer_id: i32 = 0,
    last_x: f32 = 0.0,
    last_y: f32 = 0.0,
    tint: [3]f32 = .{ 1.0, 0.85, 0.55 },
    click_count: u32 = 0,
    wasi: ?*webapi.Wasi = null,
    worker: webapi.Worker = .null,
    audio_ctx: WebAudio.AudioContext = .null,
    beep_buffer: WebAudio.AudioBuffer = .null,
    beep_loading: bool = false,
    geo_watch_id: dom.Geolocation.WatchId = .invalid,

    fn init(allocator: std.mem.Allocator) !*App {
        const doc = dom.document();
        const canvas = doc.getElementById("gl-canvas") orelse
            return error.CanvasNotFound;

        const gl = try WebGL.fromCanvas(canvas);
        errdefer gl.release();
        gl.enable(WebGL.DEPTH_TEST);
        gl.depthFunc(WebGL.LEQUAL);

        const program = try gl.createProgramFromSource(
            vertex_shader_src,
            fragment_shader_src,
        );
        errdefer program.release();

        const vbo = gl.createBuffer();
        errdefer vbo.release();

        gl.bindBuffer(WebGL.ARRAY_BUFFER, vbo);
        gl.bufferData(
            WebGL.ARRAY_BUFFER,
            std.mem.sliceAsBytes(&cube_vertices),
            WebGL.STATIC_DRAW,
        );

        const texture = gl.createTexture();
        if (texture.isNull()) return error.DiceTextureCreationFailed;
        errdefer {
            gl.deleteTexture(texture);
            texture.release();
        }
        gl.activeTexture(WebGL.TEXTURE0);
        gl.bindTexture(WebGL.TEXTURE_2D, texture);
        gl.texParameteri(WebGL.TEXTURE_2D, WebGL.TEXTURE_MIN_FILTER, WebGL.LINEAR);
        gl.texParameteri(WebGL.TEXTURE_2D, WebGL.TEXTURE_MAG_FILTER, WebGL.LINEAR);
        gl.texParameteri(WebGL.TEXTURE_2D, WebGL.TEXTURE_WRAP_S, WebGL.CLAMP_TO_EDGE);
        gl.texParameteri(WebGL.TEXTURE_2D, WebGL.TEXTURE_WRAP_T, WebGL.CLAMP_TO_EDGE);
        const pos_loc = gl.getAttribLocation(program, "a_pos");
        const uv_loc = gl.getAttribLocation(program, "a_uv");
        const normal_loc = gl.getAttribLocation(program, "a_normal");
        const u_yaw = gl.getUniformLocation(program, "u_yaw");
        const u_pitch = gl.getUniformLocation(program, "u_pitch");
        const u_scale = gl.getUniformLocation(program, "u_scale");
        const u_aspect = gl.getUniformLocation(program, "u_aspect");
        const u_dice = gl.getUniformLocation(program, "u_dice");
        const u_tint = gl.getUniformLocation(program, "u_tint");

        const banner_program = try gl.createProgramFromSource(
            banner_vertex_shader_src,
            banner_fragment_shader_src,
        );
        errdefer banner_program.release();

        const banner_vbo = gl.createBuffer();
        errdefer banner_vbo.release();
        gl.bindBuffer(WebGL.ARRAY_BUFFER, banner_vbo);
        gl.bufferData(
            WebGL.ARRAY_BUFFER,
            std.mem.sliceAsBytes(&banner_vertices),
            WebGL.STATIC_DRAW,
        );

        const banner_texture = gl.createTexture();
        if (banner_texture.isNull()) return error.BannerTextureCreationFailed;
        errdefer {
            gl.deleteTexture(banner_texture);
            banner_texture.release();
        }
        gl.activeTexture(WebGL.TEXTURE0);
        gl.bindTexture(WebGL.TEXTURE_2D, banner_texture);
        gl.texParameteri(WebGL.TEXTURE_2D, WebGL.TEXTURE_MIN_FILTER, WebGL.LINEAR);
        gl.texParameteri(WebGL.TEXTURE_2D, WebGL.TEXTURE_MAG_FILTER, WebGL.LINEAR);
        gl.texParameteri(WebGL.TEXTURE_2D, WebGL.TEXTURE_WRAP_S, WebGL.CLAMP_TO_EDGE);
        gl.texParameteri(WebGL.TEXTURE_2D, WebGL.TEXTURE_WRAP_T, WebGL.CLAMP_TO_EDGE);
        const banner_pos_loc = gl.getAttribLocation(banner_program, "a_pos");
        const banner_uv_loc = gl.getAttribLocation(banner_program, "a_uv");
        const u_banner = gl.getUniformLocation(banner_program, "u_banner");

        const self = try allocator.create(App);
        errdefer allocator.destroy(self);

        self.* = .{
            .allocator = allocator,
            .prng = webapi.PseudoRandomNumberGenerator(),
            .canvas = canvas,
            .gl = gl,
            .program = program,
            .vbo = vbo,
            .texture = texture,
            .pos_loc = pos_loc,
            .uv_loc = uv_loc,
            .normal_loc = normal_loc,
            .u_yaw = u_yaw,
            .u_pitch = u_pitch,
            .u_scale = u_scale,
            .u_aspect = u_aspect,
            .u_dice = u_dice,
            .u_tint = u_tint,
            .banner_program = banner_program,
            .banner_vbo = banner_vbo,
            .banner_texture = banner_texture,
            .banner_pos_loc = banner_pos_loc,
            .banner_uv_loc = banner_uv_loc,
            .u_banner = u_banner,
            .frame_cb = .null,
        };
        self.frame_cb = webapi.boundFunction(App, self, onFrame);
        return self;
    }

    fn rasterizeDice(self: *App) void {
        const request = webapi.fetch("dice.svg", null);
        defer request.release();
        request.thenFn(App, self, onDiceResponse, onDiceError);
    }

    fn onDiceResponse(self: *App, response: Fetch.Response) void {
        if (!response.ok()) {
            std.log.err("Could not fetch dice.svg: HTTP {d}", .{response.status()});
            return;
        }
        const blob = response.blob();
        defer blob.release();
        blob.thenFn(App, self, onDiceBlob, onDiceError);
    }

    fn onDiceBlob(self: *App, blob: webapi.Blob) void {
        const url = webapi.URL.createObjectURL(blob);
        const image = webapi.Image.init();
        self.dice_source = .{ .image = image, .url = url };
        image.setSrc(url);

        const decoded = image.decode();
        defer decoded.release();
        decoded.thenFn(App, self, onDiceDecoded, onDiceError);
    }

    fn releaseDiceSource(self: *App) void {
        const source = self.dice_source orelse return;
        webapi.URL.revokeObjectURL(source.url);
        source.url.release();
        source.image.release();
        self.dice_source = null;
    }

    fn onDiceDecoded(self: *App) void {
        const image = self.dice_source.?.image;
        defer self.releaseDiceSource();

        const bitmap = dom.document().createElement("canvas");
        defer bitmap.release();
        bitmap.set("width", image.naturalWidth());
        bitmap.set("height", image.naturalHeight());
        const context = webapi.CanvasRenderingContext2D.fromCanvas(bitmap) catch {
            std.log.err("Could not create the dice bitmap's 2D context", .{});
            return;
        };
        defer context.release();
        context.drawImage(image, 0, 0);

        self.gl.bindTexture(WebGL.TEXTURE_2D, self.texture);
        // The TexImageSource overload uploads the canvas without copying its pixels to Zig.
        self.gl.handle.call("texImage2D", .{
            WebGL.TEXTURE_2D, @as(i32, 0),         WebGL.RGBA,
            WebGL.RGBA,       WebGL.UNSIGNED_BYTE, bitmap.handle,
        }, void);
        dom.window().requestAnimationFrame(self.frame_cb);
    }

    fn onDiceError(self: *App, err: zjb.Handle) void {
        self.releaseDiceSource();
        webapi.console.@"error"("Could not load the dice texture:", .{err});
    }

    fn updateBannerText(self: *App, text: []const u8) void {
        const title = if (text.len > 0) text else default_banner_text;
        const bitmap = dom.document().createElement("canvas");
        defer bitmap.release();
        bitmap.set("width", banner_tex_width);
        bitmap.set("height", banner_tex_height);

        const ctx = webapi.CanvasRenderingContext2D.fromCanvas(bitmap) catch {
            std.log.err("Could not create the banner bitmap's 2D context", .{});
            return;
        };
        defer ctx.release();

        const w: f64 = @floatFromInt(banner_tex_width);
        const h: f64 = @floatFromInt(banner_tex_height);
        ctx.clearRect(0.0, 0.0, w, h);

        ctx.setFillStyle("rgba(15, 20, 32, 0.88)");
        ctx.fillRect(4.0, 4.0, w - 8.0, h - 8.0);
        ctx.setStrokeStyle("#f7a41d");
        ctx.setLineWidth(4.0);
        ctx.strokeRect(4.0, 4.0, w - 8.0, h - 8.0);

        ctx.setTextAlign(.center);
        ctx.setTextBaseline(.middle);
        ctx.setFont("700 44px system-ui, -apple-system, sans-serif");

        const metrics = ctx.measureText(title);
        defer metrics.release();
        const underline_w = @min(@max(metrics.width(), 120.0), w - 64.0);
        ctx.setFillStyle("rgba(247, 164, 29, 0.55)");
        ctx.fillRect((w - underline_w) * 0.5, 80.0, underline_w, 3.0);

        ctx.setStrokeStyle("rgba(0, 0, 0, 0.8)");
        ctx.setLineWidth(6.0);
        ctx.strokeTextMaxWidth(title, w * 0.5, 50.0, w - 64.0);
        ctx.setFillStyle("#fff7e6");
        ctx.fillTextMaxWidth(title, w * 0.5, 50.0, w - 64.0);

        ctx.setFont("600 20px ui-monospace, SFMono-Regular, monospace");
        ctx.setFillStyle("#f7a41d");
        ctx.fillText("CanvasRenderingContext2D -> WebGL Banner", w * 0.5, 102.0);

        self.gl.activeTexture(WebGL.TEXTURE0);
        self.gl.bindTexture(WebGL.TEXTURE_2D, self.banner_texture);
        self.gl.handle.call("texImage2D", .{
            WebGL.TEXTURE_2D, @as(i32, 0),         WebGL.RGBA,
            WebGL.RGBA,       WebGL.UNSIGNED_BYTE, bitmap.handle,
        }, void);
    }

    fn render(self: *App) void {
        const width = self.canvas.get("width", i32);
        const height = self.canvas.get("height", i32);
        self.gl.viewport(0, 0, width, height);
        self.gl.clearColor(0.08, 0.10, 0.15, 1.0);
        self.gl.clear(WebGL.COLOR_BUFFER_BIT | WebGL.DEPTH_BUFFER_BIT);

        self.gl.enable(WebGL.DEPTH_TEST);
        self.gl.disable(WebGL.BLEND);
        self.gl.useProgram(self.program);
        self.gl.bindBuffer(WebGL.ARRAY_BUFFER, self.vbo);
        self.gl.enableVertexAttribArray(self.pos_loc);
        self.gl.vertexAttribPointer(
            self.pos_loc,
            3,
            WebGL.FLOAT,
            false,
            @sizeOf(Vertex),
            @offsetOf(Vertex, "pos"),
        );
        self.gl.enableVertexAttribArray(self.uv_loc);
        self.gl.vertexAttribPointer(
            self.uv_loc,
            2,
            WebGL.FLOAT,
            false,
            @sizeOf(Vertex),
            @offsetOf(Vertex, "uv"),
        );
        self.gl.enableVertexAttribArray(self.normal_loc);
        self.gl.vertexAttribPointer(
            self.normal_loc,
            3,
            WebGL.FLOAT,
            false,
            @sizeOf(Vertex),
            @offsetOf(Vertex, "normal"),
        );
        self.gl.activeTexture(WebGL.TEXTURE0);
        self.gl.bindTexture(WebGL.TEXTURE_2D, self.texture);
        self.gl.uniform1i(self.u_dice, 0);
        self.gl.uniform1f(self.u_yaw, self.yaw);
        self.gl.uniform1f(self.u_pitch, self.pitch);
        self.gl.uniform1f(self.u_scale, self.scale);
        self.gl.uniform1f(
            self.u_aspect,
            @as(f32, @floatFromInt(width)) /
                @as(f32, @floatFromInt(@max(height, 1))),
        );
        self.gl.uniform3f(
            self.u_tint,
            self.tint[0],
            self.tint[1],
            self.tint[2],
        );
        self.gl.drawArrays(WebGL.TRIANGLES, 0, cube_vertices.len);
        self.gl.disableVertexAttribArray(self.pos_loc);
        self.gl.disableVertexAttribArray(self.uv_loc);
        self.gl.disableVertexAttribArray(self.normal_loc);

        self.gl.disable(WebGL.DEPTH_TEST);
        self.gl.enable(WebGL.BLEND);
        self.gl.blendFunc(WebGL.SRC_ALPHA, WebGL.ONE_MINUS_SRC_ALPHA);
        self.gl.useProgram(self.banner_program);
        self.gl.bindBuffer(WebGL.ARRAY_BUFFER, self.banner_vbo);
        self.gl.enableVertexAttribArray(self.banner_pos_loc);
        self.gl.vertexAttribPointer(
            self.banner_pos_loc,
            2,
            WebGL.FLOAT,
            false,
            @sizeOf(BannerVertex),
            @offsetOf(BannerVertex, "pos"),
        );
        self.gl.enableVertexAttribArray(self.banner_uv_loc);
        self.gl.vertexAttribPointer(
            self.banner_uv_loc,
            2,
            WebGL.FLOAT,
            false,
            @sizeOf(BannerVertex),
            @offsetOf(BannerVertex, "uv"),
        );
        self.gl.activeTexture(WebGL.TEXTURE0);
        self.gl.bindTexture(WebGL.TEXTURE_2D, self.banner_texture);
        self.gl.uniform1i(self.u_banner, 0);
        self.gl.drawArrays(WebGL.TRIANGLES, 0, banner_vertices.len);
        self.gl.disableVertexAttribArray(self.banner_pos_loc);
        self.gl.disableVertexAttribArray(self.banner_uv_loc);
    }

    fn onFrame(self: *App, ts_h: zjb.Handle) void {
        if (ts_h.isNull()) return;
        const ts_ms = zjb.global("Number").call(
            "call",
            .{ zjb.Handle.null, ts_h },
            f64,
        );
        if (self.last_frame_ms) |prev_ms| {
            if (!self.dragging) {
                const dt: f32 = @floatCast(
                    std.math.clamp((ts_ms - prev_ms) * 0.001, 0.0, 0.1),
                );
                self.yaw = @mod(self.yaw + dt * 0.45, std.math.tau);
                self.pitch = @mod(self.pitch + dt * 0.30, std.math.tau);
            }
        }
        self.last_frame_ms = ts_ms;
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
        self.yaw = @mod(self.yaw + (dx * 2.0) / w, std.math.tau);
        self.pitch = @mod(self.pitch + (dy * 2.0) / h, std.math.tau);
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
        self.yaw = 0.65;
        self.pitch = -0.45;
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

        const target_el = dom.Element.fromHandle(target_h);
        const val = (target_el.getValueAlloc(self.allocator) catch return) orelse
            return;
        defer self.allocator.free(val);

        dom.document().setElemText(
            "echo-output",
            if (val.len > 0) val else "(empty)",
        );
        self.updateBannerText(val);
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
        const crypto = webapi.Crypto.global();
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
        const subtle = webapi.Crypto.global().subtle();
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

    fn ensureAudioContext(self: *App) ?WebAudio.AudioContext {
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

    fn onAudioPcmClick(self: *App, _: Event.PointerEvent) void {
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
        src.addEventListener("ended", App, self, onAudioPcmEnded);
        src.start();

        var buf: [128]u8 = undefined;
        const msg = std.fmt.bufPrint(
            &buf,
            "Playing 523.25 Hz PCM sine AudioBuffer ({d} frames @ {d:.0} Hz)...",
            .{ frame_count, sample_rate },
        ) catch return;
        dom.document().setElemText("audio-output", msg);
    }

    fn onAudioMp3Click(self: *App, _: Event.PointerEvent) void {
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
        resp_p.thenFn(App, self, onAudioMp3Response, onAudioError);
    }

    fn onAudioMp3Response(self: *App, resp: Fetch.Response) void {
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
        ab_p.thenFn(App, self, onAudioMp3Bytes, onAudioError);
    }

    fn onAudioMp3Bytes(self: *App, buf_h: zjb.Handle) void {
        if (self.audio_ctx.isNull()) {
            self.beep_loading = false;
            return;
        }
        dom.document().setElemText("audio-output", "Decoding blue-beep.mp3...");
        const dec_p = self.audio_ctx.decodeAudioData(buf_h);
        defer dec_p.release();
        dec_p.thenFn(App, self, onAudioMp3Decoded, onAudioError);
    }

    fn onAudioMp3Decoded(self: *App, decoded: WebAudio.AudioBuffer) void {
        self.beep_loading = false;
        if (!self.beep_buffer.isNull()) {
            self.beep_buffer.release();
        }
        // Keep the decoded AudioBuffer across clicks so replay avoids re-fetching.
        self.beep_buffer = WebAudio.AudioBuffer.fromHandle(
            decoded.handle.call("valueOf", .{}, zjb.Handle),
        );
        self.playBeepBuffer();
    }

    fn playBeepBuffer(self: *App) void {
        const ctx = self.ensureAudioContext() orelse return;
        if (self.beep_buffer.isNull()) return;

        const src = ctx.createBufferSource();
        defer src.release();
        src.setBuffer(self.beep_buffer);

        const dest = ctx.destination();
        defer dest.release();
        src.connect(dest);
        src.addEventListener("ended", App, self, onAudioMp3Ended);
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

    fn onAudioPcmEnded(_: *App, _: Event) void {
        dom.document().setElemText("audio-output", "PCM sine AudioBuffer finished.");
    }

    fn onAudioMp3Ended(_: *App, _: Event) void {
        dom.document().setElemText("audio-output", "blue-beep.mp3 playback finished.");
    }

    fn onAudioError(self: *App, err_h: zjb.Handle) void {
        self.beep_loading = false;
        webapi.console.@"error"("Web Audio failed:", .{err_h});
        dom.document().setElemText(
            "audio-output",
            "Web Audio failed (see console).",
        );
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

    fn onGeoOnceClick(self: *App, _: Event.PointerEvent) void {
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
            App,
            self,
            onGeoSuccess,
            onGeoError,
            .{ .enable_high_accuracy = true, .timeout = 10_000, .maximum_age = 0 },
        );
    }

    fn onGeoWatchClick(self: *App, _: Event.PointerEvent) void {
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
            App,
            self,
            onGeoSuccess,
            onGeoError,
            .{ .enable_high_accuracy = true, .timeout = 10_000, .maximum_age = 0 },
        );
        if (self.geo_watch_id != .invalid) {
            doc.setElemText("btn-geo-watch", "Stop Watch");
        }
    }

    fn onGeoSuccess(self: *App, pos: dom.Geolocation.Position) void {
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

    fn onGeoError(self: *App, err: dom.Geolocation.PositionError) void {
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

    fn onShareLinkClick(self: *App, _: Event.PointerEvent) void {
        if (!dom.Share.isSupported()) {
            dom.document().setElemText(
                "share-output",
                "Web Share API (navigator.share) is not supported in this browser/context.",
            );
            return;
        }
        const loc = dom.window().location();
        defer loc.release();
        var url_buf: [512]u8 = undefined;
        const href = loc.getHref(&url_buf);

        const data: dom.Share.Data = .{
            .title = "zig-webapi Live Example",
            .text = "Interactive Zig WebAssembly browser APIs demo",
            .url = if (href.len > 0) href else "https://dasimmet.github.io/zig-webapi/example/",
        };
        if (dom.Share.isCanShareSupported() and !dom.Share.canShare(data)) {
            dom.document().setElemText(
                "share-output",
                "navigator.canShare() returned false for link payload.",
            );
            return;
        }
        const share_p = dom.Share.share(data) orelse {
            dom.document().setElemText("share-output", "navigator.share() unavailable.");
            return;
        };
        defer share_p.release();
        dom.document().setElemText("share-output", "Opening share sheet for link...");
        share_p.thenFn(App, self, onShareDone, onShareError);
    }

    fn onShareFileClick(self: *App, _: Event.PointerEvent) void {
        if (!dom.Share.isSupported() or !webapi.File.isSupported()) {
            dom.document().setElemText(
                "share-output",
                "Web Share API / File sharing is not supported in this browser/context.",
            );
            return;
        }
        var report_buf: [256]u8 = undefined;
        const report = std.fmt.bufPrint(
            &report_buf,
            "zig-webapi share report\nclicks={d}\ntint=({d:.2}, {d:.2}, {d:.2})\n",
            .{ self.click_count, self.tint[0], self.tint[1], self.tint[2] },
        ) catch return;

        const file = webapi.File.fromText(
            report,
            "zig-webapi-share.txt",
            .{ .type = "text/plain" },
        );
        defer file.release();

        const data: dom.Share.Data = .{
            .title = "zig-webapi Report",
            .text = "Generated in Zig WASM via webapi.File",
            .files = &.{file},
        };
        if (!dom.Share.canShare(data)) {
            dom.document().setElemText(
                "share-output",
                "navigator.canShare() reported file sharing is unsupported on this device/browser.",
            );
            return;
        }
        const share_p = dom.Share.share(data) orelse {
            dom.document().setElemText("share-output", "navigator.share() unavailable.");
            return;
        };
        defer share_p.release();
        dom.document().setElemText("share-output", "Opening share sheet for text file...");
        share_p.thenFn(App, self, onShareDone, onShareError);
    }

    fn onShareDone(_: *App) void {
        dom.document().setElemText("share-output", "Shared successfully.");
    }

    fn onShareError(_: *App, err_h: zjb.Handle) void {
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
            "Share failed ({s}): {s}",
            .{
                if (err_name.len > 0) err_name else "Error",
                if (err_msg.len > 0) err_msg else "cancelled or unsupported",
            },
        ) catch "Share failed (see console).";
        dom.document().setElemText("share-output", text);
    }

    fn setDropZoneActive(active: bool) void {
        const drop_zone = dom.document().getElementById("drop-zone") orelse return;
        defer drop_zone.release();
        const classes = drop_zone.classList();
        defer classes.release();
        if (active) {
            classes.add("drag-over");
        } else {
            classes.remove("drag-over");
        }
    }

    fn onDropZoneDragOver(_: *App, ev: Event.DragEvent) void {
        ev.preventDefault();
        setDropZoneActive(true);
        const dt = ev.dataTransfer();
        if (!dt.isNull()) {
            defer dt.release();
            dt.setDropEffect(.copy);
        }
    }

    fn onDropZoneDragLeave(_: *App, _: Event.DragEvent) void {
        setDropZoneActive(false);
    }

    fn onDropZoneDrop(self: *App, ev: Event.DragEvent) void {
        ev.preventDefault();
        setDropZoneActive(false);

        const dt = ev.dataTransfer();
        if (dt.isNull()) {
            dom.document().setElemText("drop-output", "Drop event had no DataTransfer.");
            return;
        }
        defer dt.release();

        var file_list = dt.files();
        defer file_list.release();

        if (file_list.len() > 0) {
            if (dom.document().getElementById("drop-file-input")) |input_el| {
                defer input_el.release();
                input_el.setFiles(file_list);
            }
            self.renderFileListMetadata(&file_list);
            return;
        }

        if (dt.getDataAlloc(self.allocator, "text/plain") catch null) |dropped_text| {
            defer self.allocator.free(dropped_text);
            if (dropped_text.len > 0) {
                var out_buf: [512]u8 = undefined;
                const msg = std.fmt.bufPrint(
                    &out_buf,
                    "No files dropped (received text/plain, {d} bytes):\n{s}",
                    .{ dropped_text.len, dropped_text[0..@min(dropped_text.len, 240)] },
                ) catch "No files dropped (received text/plain).";
                dom.document().setElemText("drop-output", msg);
                return;
            }
        }

        dom.document().setElemText("drop-output", "Dropped item contained no files.");
    }

    fn onDropFileInputChange(self: *App, ev_h: zjb.Handle) void {
        const ev = Event.fromHandle(ev_h);
        const target_h = ev.target();
        if (target_h.isNull()) return;
        defer target_h.release();

        const input_el = dom.Element.fromHandle(target_h);
        var file_list = input_el.files();
        if (file_list.isNull()) return;
        defer file_list.release();

        self.renderFileListMetadata(&file_list);
    }

    fn renderFileListMetadata(self: *App, file_list: *webapi.File.List) void {
        const count = file_list.len();
        if (count == 0) {
            dom.document().setElemText("drop-output", "No files selected.");
            return;
        }

        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(self.allocator);
        out.print(self.allocator, "Files ({d}):\n", .{count}) catch return;

        var idx: usize = 0;
        while (file_list.next()) |file| {
            defer file.release();
            idx += 1;

            var name_buf: [256]u8 = undefined;
            const fname = file.name(&name_buf);

            var mime_buf: [128]u8 = undefined;
            const mime = file.mimeType(&mime_buf);

            var rel_buf: [256]u8 = undefined;
            const rel_path = file.webkitRelativePath(&rel_buf);

            const lm = file.lastModified();
            const lm_date = webapi.Date.initFromTimestamp(@floatFromInt(lm));
            defer lm_date.release();
            var iso_buf: [64]u8 = undefined;
            const iso = lm_date.toISOString(&iso_buf);

            out.print(
                self.allocator,
                "\n[{d}] {s}\n    size: {d} bytes\n    type: {s}\n    lastModified: {s} ({d})",
                .{
                    idx,
                    if (fname.len > 0) fname else "(unnamed)",
                    file.size(),
                    if (mime.len > 0) mime else "(unknown)",
                    if (iso.len > 0) iso else "n/a",
                    lm,
                },
            ) catch return;

            if (rel_path.len > 0) {
                out.print(self.allocator, "\n    path: {s}", .{rel_path}) catch return;
            }
        }

        dom.document().setElemText("drop-output", out.items);
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
        if (doc.getElementById("btn-audio-pcm")) |btn| {
            defer btn.release();
            btn.addEventListener("click", App, self, onAudioPcmClick);
        }
        if (doc.getElementById("btn-audio-mp3")) |btn| {
            defer btn.release();
            btn.addEventListener("click", App, self, onAudioMp3Click);
        }
        if (doc.getElementById("btn-crypto-uuid")) |btn| {
            defer btn.release();
            btn.addEventListener("click", App, self, onCryptoRandomClick);
        }
        if (doc.getElementById("btn-crypto-digest")) |btn| {
            defer btn.release();
            btn.addEventListener("click", App, self, onCryptoDigestClick);
        }
        if (doc.getElementById("btn-geo-once")) |btn| {
            defer btn.release();
            btn.addEventListener("click", App, self, onGeoOnceClick);
        }
        if (doc.getElementById("btn-geo-watch")) |btn| {
            defer btn.release();
            btn.addEventListener("click", App, self, onGeoWatchClick);
        }
        if (doc.getElementById("btn-share-link")) |btn| {
            defer btn.release();
            btn.addEventListener("click", App, self, onShareLinkClick);
        }
        if (doc.getElementById("btn-share-file")) |btn| {
            defer btn.release();
            btn.addEventListener("click", App, self, onShareFileClick);
        }
        if (doc.getElementById("drop-zone")) |zone| {
            defer zone.release();
            zone.addEventListener("dragenter", App, self, onDropZoneDragOver);
            zone.addEventListener("dragover", App, self, onDropZoneDragOver);
            zone.addEventListener("dragleave", App, self, onDropZoneDragLeave);
            zone.addEventListener("drop", App, self, onDropZoneDrop);
        }
        if (doc.getElementById("drop-file-input")) |input| {
            defer input.release();
            webapi.boundEventListener(App, "change", input.handle, onDropFileInputChange, self);
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
