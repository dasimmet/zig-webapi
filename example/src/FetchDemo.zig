//! Fetch API (`webapi.fetch`), typed Promises, and browser file download demo.

// 1. Imports
const std = @import("std");
const webapi = @import("webapi");
const WebGLDemo = @import("WebGLDemo.zig");

// 2. Shortcuts on imports
const FetchDemo = @This();
const dom = webapi.dom;
const Event = webapi.Event;
const Fetch = webapi.Fetch;
const zjb = webapi.zjb;

// 3. File-level struct members
webgl: ?*const WebGLDemo = null,

// 7. Public functions
/// Attaches `#btn-fetch` and `#btn-download` click listeners.
pub fn bind(self: *FetchDemo, webgl: *const WebGLDemo) void {
    self.webgl = webgl;
    const doc = dom.document();
    if (doc.getElementById("btn-fetch")) |btn| {
        defer btn.release();
        btn.addEventListener("click", FetchDemo, self, onFetchClick);
    }
    if (doc.getElementById("btn-download")) |btn| {
        defer btn.release();
        btn.addEventListener("click", FetchDemo, self, onDownloadClick);
    }
}

// 9. Private declarations
fn onFetchClick(self: *FetchDemo, _: Event.PointerEvent) void {
    dom.document().setElemText("fetch-output", "Fetching data.json...");
    const req = webapi.fetch("data.json", null);
    defer req.release();
    req.thenFn(FetchDemo, self, onFetchResponse, onFetchError);
}

fn onFetchResponse(self: *FetchDemo, resp: Fetch.Response) void {
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
    text_p.thenFn(FetchDemo, self, onFetchText, onFetchError);
}

fn onFetchText(_: *FetchDemo, text_h: zjb.Handle) void {
    var buf: [4096]u8 = undefined;
    const body = webapi.stringFromHandle(text_h, &buf);
    dom.document().setElemText("fetch-output", body);
}

fn onFetchError(_: *FetchDemo, err_h: zjb.Handle) void {
    webapi.console.@"error"("Fetch failed:", .{err_h});
    dom.document().setElemText("fetch-output", "Fetch failed (see console).");
}

fn onDownloadClick(self: *FetchDemo, _: Event.PointerEvent) void {
    const wgl = self.webgl orelse return;
    var buf: [256]u8 = undefined;
    const report = wgl.formatReport(&buf, "webapi example report") orelse return;
    webapi.download.bytes(.{
        .bytes = report,
        .filename = "webapi-report.txt",
        .mimetype = "text/plain",
    });
}
