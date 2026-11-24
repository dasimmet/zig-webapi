//! Web Crypto (`window.crypto.randomUUID`, `getRandomValues`, `SubtleCrypto`
//! SHA-256 digest) demo.

// 1. Imports
const std = @import("std");
const webapi = @import("webapi");
const DomEventsDemo = @import("DomEventsDemo.zig");

// 2. Shortcuts on imports
const CryptoDemo = @This();
const dom = webapi.dom;
const Event = webapi.Event;
const zjb = webapi.zjb;

// 3. File-level struct members
allocator: std.mem.Allocator,

// 7. Public functions
/// Attaches `#btn-crypto-uuid` and `#btn-crypto-digest` click listeners.
pub fn bind(self: *CryptoDemo) void {
    const doc = dom.document();
    if (doc.getElementById("btn-crypto-uuid")) |btn| {
        defer btn.release();
        btn.addEventListener("click", CryptoDemo, self, onCryptoRandomClick);
    }
    if (doc.getElementById("btn-crypto-digest")) |btn| {
        defer btn.release();
        btn.addEventListener("click", CryptoDemo, self, onCryptoDigestClick);
    }
}

// 9. Private declarations
fn formatHex(bytes: []const u8, out: []u8) []const u8 {
    const hex = "0123456789abcdef";
    const n = @min(bytes.len, out.len / 2);
    for (bytes[0..n], 0..) |b, i| {
        out[i * 2] = hex[b >> 4];
        out[i * 2 + 1] = hex[b & 0x0f];
    }
    return out[0 .. n * 2];
}

fn onCryptoRandomClick(_: *CryptoDemo, _: Event.PointerEvent) void {
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

fn onCryptoDigestClick(self: *CryptoDemo, _: Event.PointerEvent) void {
    const subtle = webapi.Crypto.global().subtle();
    defer subtle.release();
    if (subtle.isNull()) {
        dom.document().setElemText(
            "crypto-output",
            "crypto.subtle requires a secure context (HTTPS or localhost).",
        );
        return;
    }

    const input = DomEventsDemo.readInputOrFallback(
        self.allocator,
        "hello from zig-webapi",
    );
    defer input.deinit(self.allocator);

    const digest_p = subtle.digest(.@"SHA-256", input.text);
    defer digest_p.release();
    digest_p.thenFn(CryptoDemo, self, onCryptoDigestDone, onCryptoError);
}

fn onCryptoDigestDone(self: *CryptoDemo, buf_h: zjb.Handle) void {
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

fn onCryptoError(_: *CryptoDemo, err_h: zjb.Handle) void {
    webapi.console.@"error"("Web Crypto failed:", .{err_h});
    dom.document().setElemText("crypto-output", "Web Crypto failed (see console).");
}
