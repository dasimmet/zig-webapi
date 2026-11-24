//! Web Share API (`navigator.canShare` and `navigator.share` with URLs and
//! generated `webapi.File` objects) demo.

// 1. Imports
const std = @import("std");
const webapi = @import("webapi");
const WebGLDemo = @import("WebGLDemo.zig");

// 2. Shortcuts on imports
const ShareDemo = @This();
const dom = webapi.dom;
const Event = webapi.Event;
const zjb = webapi.zjb;

// 3. File-level struct members
webgl: ?*const WebGLDemo = null,

// 7. Public functions
/// Attaches `#btn-share-link` and `#btn-share-file` click listeners.
pub fn bind(self: *ShareDemo, webgl: *const WebGLDemo) void {
    self.webgl = webgl;
    const doc = dom.document();
    if (doc.getElementById("btn-share-link")) |btn| {
        defer btn.release();
        btn.addEventListener("click", ShareDemo, self, onShareLinkClick);
    }
    if (doc.getElementById("btn-share-file")) |btn| {
        defer btn.release();
        btn.addEventListener("click", ShareDemo, self, onShareFileClick);
    }
}

// 9. Private declarations
fn onShareLinkClick(self: *ShareDemo, _: Event.PointerEvent) void {
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
    share_p.thenFn(ShareDemo, self, onShareDone, onShareError);
}

fn onShareFileClick(self: *ShareDemo, _: Event.PointerEvent) void {
    const wgl = self.webgl orelse return;
    if (!dom.Share.isSupported() or !webapi.File.isSupported()) {
        dom.document().setElemText(
            "share-output",
            "Web Share API / File sharing is not supported in this browser/context.",
        );
        return;
    }
    var report_buf: [256]u8 = undefined;
    const report = wgl.formatReport(&report_buf, "zig-webapi share report") orelse
        return;

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
    share_p.thenFn(ShareDemo, self, onShareDone, onShareError);
}

fn onShareDone(_: *ShareDemo) void {
    dom.document().setElemText("share-output", "Shared successfully.");
}

fn onShareError(_: *ShareDemo, err_h: zjb.Handle) void {
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
