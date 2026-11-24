//! Interactive WebGL 3D textured die and 2D canvas text banner demo.

// 1. Imports
const std = @import("std");
const webapi = @import("webapi");

// 2. Shortcuts on imports
const WebGLDemo = @This();
const dom = webapi.dom;
const Event = webapi.Event;
const Fetch = webapi.Fetch;
const WebGL = webapi.WebGL;
const zjb = webapi.zjb;

const vertex_shader_src = @embedFile("shaders/cube.vert");
const fragment_shader_src = @embedFile("shaders/cube.frag");
const banner_vertex_shader_src = @embedFile("shaders/banner.vert");
const banner_fragment_shader_src = @embedFile("shaders/banner.frag");

pub const default_banner_text = "Hello from Zig WASM";
const banner_tex_width: i32 = 1024;
const banner_tex_height: i32 = 128;

// 3. File-level struct members
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
frame_cb: zjb.Handle = .null,
dice_source: ?DiceSource = null,
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

// 5. init
/// Compiles WebGL shaders and allocates vertex buffers and textures for the
/// 3D die and 2D canvas banner.
pub fn init() !WebGLDemo {
    const doc = dom.document();
    const canvas = doc.getElementById("gl-canvas") orelse
        return error.CanvasNotFound;
    errdefer canvas.release();

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

    return .{
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
        .banner_pos_loc = gl.getAttribLocation(banner_program, "a_pos"),
        .banner_uv_loc = gl.getAttribLocation(banner_program, "a_uv"),
        .u_banner = gl.getUniformLocation(banner_program, "u_banner"),
    };
}

// 7. Public functions
/// Attaches pointer, wheel, double-click, and button listeners to `self`.
pub fn bind(self: *WebGLDemo) void {
    self.frame_cb = webapi.boundFunction(WebGLDemo, self, onFrame);

    if (dom.document().getElementById("btn-color")) |btn| {
        defer btn.release();
        btn.addEventListener("click", WebGLDemo, self, onRandomColorClick);
    }

    self.canvas.addEventListener("pointerdown", WebGLDemo, self, onCanvasPointerDown);
    self.canvas.addEventListener("wheel", WebGLDemo, self, onCanvasWheel);
    self.canvas.addEventListener("dblclick", WebGLDemo, self, onCanvasDblClick);

    const win = dom.window();
    win.addEventListener("pointermove", WebGLDemo, self, onWindowPointerMove);
    win.addEventListener("pointerup", WebGLDemo, self, onWindowPointerUp);
    win.addEventListener("pointercancel", WebGLDemo, self, onWindowPointerUp);
}

/// Fetches `dice.svg`, rasterizes it onto a 2D canvas, and starts the loop.
pub fn rasterizeDice(self: *WebGLDemo) void {
    const request = webapi.fetch("dice.svg", null);
    defer request.release();
    request.thenFn(WebGLDemo, self, onDiceResponse, onDiceError);
}

/// Renders `text` onto an offscreen 2D canvas and uploads it to the WebGL banner.
pub fn updateBannerText(self: *WebGLDemo, text: []const u8) void {
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

/// Formats a text summary of click count and tint values into `buf`.
pub fn formatReport(
    self: *const WebGLDemo,
    buf: []u8,
    header: []const u8,
) ?[]const u8 {
    return std.fmt.bufPrint(
        buf,
        "{s}\nclicks={d}\ntint=({d:.2}, {d:.2}, {d:.2})\n",
        .{ header, self.click_count, self.tint[0], self.tint[1], self.tint[2] },
    ) catch null;
}

// 8. Extra classes
const DiceSource = struct {
    image: webapi.Image,
    url: zjb.Handle,
};

const Vertex = extern struct {
    pos: [3]f32,
    uv: [2]f32,
    normal: [3]f32,
};

const BannerVertex = extern struct {
    pos: [2]f32,
    uv: [2]f32,
};

// 9. Private declarations
const banner_vertices = [_]BannerVertex{
    .{ .pos = .{ -0.90, 0.54 }, .uv = .{ 0.0, 1.0 } },
    .{ .pos = .{ 0.90, 0.54 }, .uv = .{ 1.0, 1.0 } },
    .{ .pos = .{ 0.90, 0.94 }, .uv = .{ 1.0, 0.0 } },
    .{ .pos = .{ -0.90, 0.54 }, .uv = .{ 0.0, 1.0 } },
    .{ .pos = .{ 0.90, 0.94 }, .uv = .{ 1.0, 0.0 } },
    .{ .pos = .{ -0.90, 0.94 }, .uv = .{ 0.0, 0.0 } },
};

const cube_vertices = vertices: {
    const faces = [_]struct { normal: [3]f32, corners: [4][3]f32 }{
        .{ .normal = .{ 0, 0, 1 }, .corners = .{ .{ -0.5, -0.5, 0.5 }, .{ 0.5, -0.5, 0.5 }, .{ 0.5, 0.5, 0.5 }, .{ -0.5, 0.5, 0.5 } } },
        .{ .normal = .{ 0, 1, 0 }, .corners = .{ .{ -0.5, 0.5, -0.5 }, .{ -0.5, 0.5, 0.5 }, .{ 0.5, 0.5, 0.5 }, .{ 0.5, 0.5, -0.5 } } },
        .{ .normal = .{ -1, 0, 0 }, .corners = .{ .{ -0.5, -0.5, -0.5 }, .{ -0.5, -0.5, 0.5 }, .{ -0.5, 0.5, 0.5 }, .{ -0.5, 0.5, -0.5 } } },
        .{ .normal = .{ 1, 0, 0 }, .corners = .{ .{ 0.5, -0.5, 0.5 }, .{ 0.5, -0.5, -0.5 }, .{ 0.5, 0.5, -0.5 }, .{ 0.5, 0.5, 0.5 } } },
        .{ .normal = .{ 0, -1, 0 }, .corners = .{ .{ -0.5, -0.5, -0.5 }, .{ 0.5, -0.5, -0.5 }, .{ 0.5, -0.5, 0.5 }, .{ -0.5, -0.5, 0.5 } } },
        .{ .normal = .{ 0, 0, -1 }, .corners = .{ .{ 0.5, -0.5, -0.5 }, .{ -0.5, -0.5, -0.5 }, .{ -0.5, 0.5, -0.5 }, .{ 0.5, 0.5, -0.5 } } },
    };
    const indices = [_]usize{ 0, 1, 2, 0, 2, 3 };
    const uv_corners = [4][2]f32{
        .{ 0.5, 127.5 },
        .{ 127.5, 127.5 },
        .{ 127.5, 0.5 },
        .{ 0.5, 0.5 },
    };
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

fn onDiceResponse(self: *WebGLDemo, response: Fetch.Response) void {
    if (!response.ok()) {
        std.log.err("Could not fetch dice.svg: HTTP {d}", .{response.status()});
        return;
    }
    const blob = response.blob();
    defer blob.release();
    blob.thenFn(WebGLDemo, self, onDiceBlob, onDiceError);
}

fn onDiceBlob(self: *WebGLDemo, blob: webapi.Blob) void {
    const url = webapi.URL.createObjectURL(blob);
    const image = webapi.Image.init();
    self.dice_source = .{ .image = image, .url = url };
    image.setSrc(url);

    const decoded = image.decode();
    defer decoded.release();
    decoded.thenFn(WebGLDemo, self, onDiceDecoded, onDiceError);
}

fn releaseDiceSource(self: *WebGLDemo) void {
    const source = self.dice_source orelse return;
    webapi.URL.revokeObjectURL(source.url);
    source.url.release();
    source.image.release();
    self.dice_source = null;
}

fn onDiceDecoded(self: *WebGLDemo) void {
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
    self.gl.handle.call("texImage2D", .{
        WebGL.TEXTURE_2D, @as(i32, 0),         WebGL.RGBA,
        WebGL.RGBA,       WebGL.UNSIGNED_BYTE, bitmap.handle,
    }, void);
    dom.window().requestAnimationFrame(self.frame_cb);
}

fn onDiceError(self: *WebGLDemo, err: zjb.Handle) void {
    self.releaseDiceSource();
    webapi.console.@"error"("Could not load the dice texture:", .{err});
}

fn render(self: *WebGLDemo) void {
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

fn onFrame(self: *WebGLDemo, ts_h: zjb.Handle) void {
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

fn onCanvasPointerDown(self: *WebGLDemo, ev: Event.PointerEvent) void {
    ev.preventDefault();
    self.dragging = true;
    self.active_pointer_id = ev.pointerId();
    self.last_x = ev.clientX();
    self.last_y = ev.clientY();
}

fn onWindowPointerMove(self: *WebGLDemo, ev: Event.PointerEvent) void {
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

fn onWindowPointerUp(self: *WebGLDemo, ev: Event.PointerEvent) void {
    if (self.dragging and ev.pointerId() == self.active_pointer_id) {
        self.dragging = false;
    }
}

fn onCanvasWheel(self: *WebGLDemo, ev: Event.WheelEvent) void {
    ev.preventDefault();
    const factor = 1.0 - ev.deltaY() * 0.001;
    self.scale = std.math.clamp(self.scale * factor, 0.35, 2.2);
}

fn onCanvasDblClick(self: *WebGLDemo, _: Event.PointerEvent) void {
    self.yaw = 0.65;
    self.pitch = -0.45;
    self.scale = 1.0;
}

fn onRandomColorClick(self: *WebGLDemo, _: Event.PointerEvent) void {
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
