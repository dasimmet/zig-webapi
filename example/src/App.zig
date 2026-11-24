//! Root application container owning all interactive demo modules in-place so
//! context-bound DOM listeners and Promise callbacks have stable heap pointers
//! without global singletons.

// 1. Imports
const std = @import("std");
const webapi = @import("webapi");
const AudioInputDemo = @import("AudioInputDemo.zig");
const CryptoDemo = @import("CryptoDemo.zig");
const DomEventsDemo = @import("DomEventsDemo.zig");
const DragDropDemo = @import("DragDropDemo.zig");
const FetchDemo = @import("FetchDemo.zig");
const GeolocationDemo = @import("GeolocationDemo.zig");
const ShareDemo = @import("ShareDemo.zig");
const VideoInputDemo = @import("VideoInputDemo.zig");
const WasiDemo = @import("WasiDemo.zig");
const WebAudioDemo = @import("WebAudioDemo.zig");
const WebGLDemo = @import("WebGLDemo.zig");
const WorkerDemo = @import("WorkerDemo.zig");

// 2. Shortcuts on imports
const App = @This();
const dom = webapi.dom;

// 3. File-level struct members
webgl: WebGLDemo,
dom_events: DomEventsDemo,
fetch_demo: FetchDemo,
crypto: CryptoDemo,
wasi: WasiDemo,
worker: WorkerDemo,
web_audio: WebAudioDemo,
audio_input: AudioInputDemo,
video_input: VideoInputDemo,
geolocation: GeolocationDemo,
share: ShareDemo,
drag_drop: DragDropDemo,

// 5. init
/// Allocates `App` on the heap and initializes all demo state structs.
pub fn init(allocator: std.mem.Allocator) !*App {
    const self = try allocator.create(App);
    errdefer allocator.destroy(self);

    self.* = .{
        .webgl = try WebGLDemo.init(),
        .dom_events = .{ .allocator = allocator },
        .fetch_demo = .{},
        .crypto = .{ .allocator = allocator },
        .wasi = .{ .allocator = allocator },
        .worker = .{ .allocator = allocator },
        .web_audio = .{ .allocator = allocator },
        .audio_input = .{},
        .video_input = .{},
        .geolocation = .{},
        .share = .{},
        .drag_drop = .{ .allocator = allocator },
    };
    return self;
}

// 7. Public functions
/// Wires DOM listeners across all demo panels and starts initial rendering.
pub fn start(self: *App) void {
    const doc = dom.document();
    const loc = dom.window().location();
    defer loc.release();
    var url_buf: [512]u8 = undefined;
    doc.setElemText("page-url", loc.getHref(&url_buf));

    self.webgl.bind();
    self.webgl.updateBannerText(WebGLDemo.default_banner_text);
    self.webgl.rasterizeDice();

    self.dom_events.bind(&self.webgl);
    self.fetch_demo.bind(&self.webgl);
    self.crypto.bind();
    self.wasi.bind();
    self.worker.bind();
    self.web_audio.bind();
    self.audio_input.bind();
    self.video_input.bind();
    self.geolocation.bind();
    self.share.bind(&self.webgl);
    self.drag_drop.bind();
}
