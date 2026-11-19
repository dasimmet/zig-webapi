const std = @import("std");
const webapi = @import("webapi.zig");
const zjb = webapi.zjb;

pub const Options = struct {
    bytes: []const u8,
    filename: []const u8,
    mimetype: []const u8 = "application/octet-stream",
};

/// downloads bytes as a file from the browser
pub fn bytes(opt: Options) void {
    const bytes_blob = webapi.Blob.fromBytes(opt.bytes, .{
        .type = opt.mimetype,
    });
    defer bytes_blob.release();

    const bytes_url = webapi.URL.createObjectURL(bytes_blob);
    defer bytes_url.release();

    const fname = zjb.string(opt.filename);
    defer fname.release();

    const a = zjb.global("document").call(
        "createElement",
        .{zjb.constString("a")},
        zjb.Handle,
    );
    defer a.release();

    a.set("href", bytes_url);
    a.set("download", fname);

    const style = a.get("style", zjb.Handle);
    defer style.release();
    style.set("display", zjb.constString("none"));

    const body = webapi.dom.document().body() orelse unreachable;
    defer body.release();

    body.appendChild(.init(a));

    a.call("click", .{}, void);
    a.call("remove", .{}, void);
}
