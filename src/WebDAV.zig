//! Generic WebDAV (RFC 4918) client utilities for browser WASM:
//! path/URL helpers, PROPFIND XML parsing, and async Fetch operations.
//! Callers supply an optional `Authorization` header (e.g. formatted via
//! `std.http.Client.basic_authorization`).

// 1. Imports
const std = @import("std");
const webapi = @import("webapi.zig");

// 2. Shortcuts on imports
const WebDAV = @This();
const dom = webapi.dom;
const Fetch = webapi.Fetch;
const zjb = webapi.zjb;

// 3. File-level struct members
dav_root: []const u8,
auth_header: ?[]const u8 = null,

// 4. Options struct for init
/// Initialization options for a `WebDAV` client handle.
pub const Options = struct {
    dav_root: []const u8,
    auth_header: ?[]const u8 = null,
};

// 5. init
/// Creates a `WebDAV` client referencing borrowed `dav_root` and optional
/// `Authorization` header slices.
pub fn init(options: Options) WebDAV {
    std.debug.assert(options.dav_root.len > 0);
    if (options.auth_header) |h| std.debug.assert(h.len > 0);
    return .{
        .dav_root = options.dav_root,
        .auth_header = options.auth_header,
    };
}

// 7. Public functions
/// Dispatches an async HTTP/WebDAV request via `webapi.fetch`.
/// `on_done` receives temporary borrowed slices in `Response` valid for the
/// duration of the callback.
pub fn request(
    alloc: std.mem.Allocator,
    url: []const u8,
    opts: RequestOptions,
    comptime Context: type,
    ctx: *Context,
    comptime on_done: *const fn (*Context, Response) void,
) !void {
    std.debug.assert(url.len > 0);
    std.debug.assert(opts.method.len > 0);
    const ReqCtx = MakeRequestContext(Context, on_done);
    const rctx = try alloc.create(ReqCtx);
    rctx.* = .{ .alloc = alloc, .user_ctx = ctx };
    rctx.send(url, opts);
}

/// Issues a `PROPFIND` request on `rel_path` relative to `self.dav_root`.
pub fn propfind(
    self: WebDAV,
    alloc: std.mem.Allocator,
    rel_path: []const u8,
    depth: Depth,
    comptime Context: type,
    ctx: *Context,
    comptime on_done: *const fn (*Context, Response) void,
) !void {
    std.debug.assert(self.dav_root.len > 0);
    const url = try buildDavItemUrl(alloc, self.dav_root, rel_path);
    defer alloc.free(url);
    try request(alloc, url, .{
        .method = "PROPFIND",
        .auth_header = self.auth_header,
        .depth = @tagName(depth),
        .content_type = "application/xml; charset=utf-8",
        .body = propfind_xml_body,
    }, Context, ctx, on_done);
}

/// Fetches the resource at `rel_path` via HTTP `GET`.
pub fn getFile(
    self: WebDAV,
    alloc: std.mem.Allocator,
    rel_path: []const u8,
    comptime Context: type,
    ctx: *Context,
    comptime on_done: *const fn (*Context, Response) void,
) !void {
    std.debug.assert(self.dav_root.len > 0);
    std.debug.assert(rel_path.len > 0);
    return self.itemRequest(
        alloc,
        "GET",
        rel_path,
        null,
        null,
        Context,
        ctx,
        on_done,
    );
}

/// Uploads `body` to `rel_path` via HTTP `PUT`.
pub fn putFile(
    self: WebDAV,
    alloc: std.mem.Allocator,
    rel_path: []const u8,
    content_type: []const u8,
    body: []const u8,
    comptime Context: type,
    ctx: *Context,
    comptime on_done: *const fn (*Context, Response) void,
) !void {
    std.debug.assert(self.dav_root.len > 0);
    std.debug.assert(content_type.len > 0);
    return self.itemRequest(
        alloc,
        "PUT",
        rel_path,
        content_type,
        body,
        Context,
        ctx,
        on_done,
    );
}

/// Creates directory collection `rel_dir` via WebDAV `MKCOL`.
pub fn mkcol(
    self: WebDAV,
    alloc: std.mem.Allocator,
    rel_dir: []const u8,
    comptime Context: type,
    ctx: *Context,
    comptime on_done: *const fn (*Context, Response) void,
) !void {
    std.debug.assert(self.dav_root.len > 0);
    std.debug.assert(rel_dir.len > 0);
    return self.itemRequest(
        alloc,
        "MKCOL",
        rel_dir,
        null,
        null,
        Context,
        ctx,
        on_done,
    );
}

/// Deletes `rel_path` via HTTP `DELETE`.
pub fn deleteItem(
    self: WebDAV,
    alloc: std.mem.Allocator,
    rel_path: []const u8,
    comptime Context: type,
    ctx: *Context,
    comptime on_done: *const fn (*Context, Response) void,
) !void {
    std.debug.assert(self.dav_root.len > 0);
    std.debug.assert(rel_path.len > 0);
    return self.itemRequest(
        alloc,
        "DELETE",
        rel_path,
        null,
        null,
        Context,
        ctx,
        on_done,
    );
}

/// Formats a CORS diagnostic including the current browser `location.origin`.
pub fn formatCorsError(
    buf: []u8,
    action: []const u8,
    method: []const u8,
    endpoint: []const u8,
    js_err: ?[]const u8,
) []const u8 {
    std.debug.assert(buf.len > 0);
    std.debug.assert(action.len > 0);

    var origin_buf: [256]u8 = undefined;
    const origin = blk: {
        const loc = dom.window().location();
        if (loc.isNull()) break :blk "this origin";
        defer loc.release();
        const orig_h = loc.handle.get("origin", zjb.Handle);
        if (orig_h.isNull()) {
            orig_h.release();
            break :blk "this origin";
        }
        defer orig_h.release();
        const s = webapi.stringFromHandle(orig_h, &origin_buf);
        break :blk if (s.len > 0) s else "this origin";
    };

    const err_suffix = if (js_err) |e|
        (if (e.len > 0) e else "TypeError: Failed to fetch")
    else
        "TypeError: Failed to fetch";

    return std.fmt.bufPrint(
        buf,
        "CORS / network error on {s} ({s} {s} - {s}): The browser blocked " ++
            "cross-origin access from {s}. Configure WebDAV CORS for {s} " ++
            "(Access-Control-Allow-Origin: {s}, " ++
            "Access-Control-Allow-Methods: GET, POST, PUT, DELETE, MKCOL, " ++
            "PROPFIND, OPTIONS, Access-Control-Allow-Headers: Authorization, " ++
            "Depth, Content-Type).",
        .{ action, method, endpoint, err_suffix, origin, origin, origin },
    ) catch "CORS / network error while contacting WebDAV server.";
}

/// Normalizes a relative path within a WebDAV root.
/// Root directory is `""`; non-empty directories end with `"/"`.
pub fn normalizeRelativePath(
    alloc: std.mem.Allocator,
    raw_path: []const u8,
    is_dir: bool,
) ![]u8 {
    const trimmed = std.mem.trim(u8, raw_path, " \t\r\n/");
    if (trimmed.len == 0) return try alloc.dupe(u8, "");

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(alloc);

    var it = std.mem.tokenizeScalar(u8, trimmed, '/');
    var first = true;
    while (it.next()) |seg| {
        if (seg.len == 0 or std.mem.eql(u8, seg, ".")) continue;
        if (std.mem.eql(u8, seg, "..")) continue;
        if (!first) try out.append(alloc, '/');
        try out.appendSlice(alloc, seg);
        first = false;
    }

    if (is_dir and out.items.len > 0) try out.append(alloc, '/');
    return try out.toOwnedSlice(alloc);
}

/// Returns the parent directory slice (with trailing `'/'`) or `""` for root.
pub fn parentDirPath(dir_path: []const u8) []const u8 {
    std.debug.assert(dir_path.len == 0 or @intFromPtr(dir_path.ptr) != 0);
    const trimmed = std.mem.trim(u8, dir_path, "/");
    if (trimmed.len == 0) return "";
    const slash = std.mem.lastIndexOfScalar(u8, trimmed, '/') orelse return "";
    std.debug.assert(slash < dir_path.len);
    return dir_path[0 .. slash + 1];
}

/// Returns the final path segment (file or directory name) without slashes.
pub fn basenameOfPath(rel_path: []const u8) []const u8 {
    std.debug.assert(rel_path.len == 0 or @intFromPtr(rel_path.ptr) != 0);
    const trimmed = std.mem.trim(u8, rel_path, "/");
    if (trimmed.len == 0) return "";
    if (std.mem.lastIndexOfScalar(u8, trimmed, '/')) |idx| {
        std.debug.assert(idx + 1 <= trimmed.len);
        return trimmed[idx + 1 ..];
    }
    return trimmed;
}

/// Returns the normalized parent directory of `file_path`.
pub fn dirnameOfFilePath(
    alloc: std.mem.Allocator,
    file_path: []const u8,
) ![]u8 {
    const trimmed = std.mem.trim(u8, file_path, "/");
    if (std.mem.lastIndexOfScalar(u8, trimmed, '/')) |idx| {
        return try normalizeRelativePath(alloc, trimmed[0..idx], true);
    }
    return try alloc.dupe(u8, "");
}

/// Joins `current_dir` with `file_input`, optionally appending `default_ext`
/// (e.g. `".html"`) when the basename has no extension.
pub fn joinDirAndFile(
    alloc: std.mem.Allocator,
    current_dir: []const u8,
    file_input: []const u8,
    default_ext: ?[]const u8,
) ![]u8 {
    const clean_input = std.mem.trim(u8, file_input, " \t\r\n");
    if (clean_input.len == 0) return error.EmptyFilename;

    const with_ext = blk: {
        if (default_ext) |ext| {
            std.debug.assert(ext.len > 0 and ext[0] == '.');
            const bname = basenameOfPath(clean_input);
            if (std.mem.indexOfScalar(u8, bname, '.') == null) {
                break :blk try std.fmt.allocPrint(alloc, "{s}{s}", .{
                    clean_input,
                    ext,
                });
            }
        }
        break :blk try alloc.dupe(u8, clean_input);
    };
    defer alloc.free(with_ext);

    if (clean_input[0] == '/') {
        return try normalizeRelativePath(alloc, with_ext, false);
    }
    const combined = if (current_dir.len > 0)
        try std.fmt.allocPrint(alloc, "{s}/{s}", .{
            std.mem.trim(u8, current_dir, "/"),
            with_ext,
        })
    else
        try alloc.dupe(u8, with_ext);
    defer alloc.free(combined);
    return try normalizeRelativePath(alloc, combined, false);
}

/// Builds a full WebDAV item URL from `dav_root` and `rel_path`,
/// percent-encoding each path segment using `std.Uri`.
pub fn buildDavItemUrl(
    alloc: std.mem.Allocator,
    dav_root: []const u8,
    rel_path: []const u8,
) ![]u8 {
    const base = std.mem.trimEnd(u8, dav_root, "/");
    if (base.len == 0) return error.EmptyDavRoot;

    var out: std.Io.Writer.Allocating = .init(alloc);
    errdefer out.deinit();

    try out.writer.writeAll(base);
    try out.writer.writeByte('/');

    const trimmed = std.mem.trimStart(u8, rel_path, "/");
    if (trimmed.len == 0) return try out.toOwnedSlice();

    const trailing_slash = std.mem.endsWith(u8, trimmed, "/");
    var it = std.mem.tokenizeScalar(u8, trimmed, '/');
    var first = true;
    while (it.next()) |seg| {
        if (!first) try out.writer.writeByte('/');
        const comp: std.Uri.Component = .{ .raw = seg };
        try comp.formatEscaped(&out.writer);
        first = false;
    }
    if (trailing_slash and !first) try out.writer.writeByte('/');
    return try out.toOwnedSlice();
}

/// Parses a WebDAV `PROPFIND` (`207 Multi-Status`) XML response into sorted
/// directory and file entries via `dom.parseDomString(xml, "application/xml")`.
pub fn parsePropfindXml(
    alloc: std.mem.Allocator,
    xml: []const u8,
    current_rel_dir: []const u8,
    options: PropfindOptions,
) ![]DavEntry {
    const trimmed_xml = std.mem.trim(u8, xml, " \t\r\n");
    if (trimmed_xml.len == 0) return try alloc.alloc(DavEntry, 0);

    const norm_cur = try normalizeRelativePath(alloc, current_rel_dir, true);
    defer alloc.free(norm_cur);

    const xml_doc = dom.parseDomString(trimmed_xml, "application/xml");
    if (xml_doc.isNull()) return error.InvalidXml;
    defer xml_doc.release();

    var entries: std.ArrayList(DavEntry) = .empty;
    errdefer {
        for (entries.items) |*e| e.deinit(alloc);
        entries.deinit(alloc);
    }

    var responses = getElementsByLocalName(xml_doc.asElement(), "response");
    defer responses.release();

    while (responses.next()) |resp_el| {
        defer resp_el.release();
        if (try parseResponseElement(
            alloc,
            resp_el,
            norm_cur,
            options,
        )) |entry| {
            try entries.append(alloc, entry);
        }
    }

    std.mem.sort(DavEntry, entries.items, {}, struct {
        fn lessThan(_: void, a: DavEntry, b: DavEntry) bool {
            if (a.is_dir != b.is_dir) return a.is_dir;
            return asciiLessThanIgnoreCase(a.name, b.name);
        }
    }.lessThan);

    return try entries.toOwnedSlice(alloc);
}

/// Validates and constructs a direct-child `DavEntry` from a decoded `href`.
pub fn buildValidatedDavEntry(
    alloc: std.mem.Allocator,
    decoded_href: []const u8,
    norm_cur: []const u8,
    is_dir: bool,
    size: ?u64,
    options: PropfindOptions,
) !?DavEntry {
    const rel = extractRelativePathFromHref(
        decoded_href,
        norm_cur,
        options.dav_root,
    ) orelse return null;
    const norm_rel = try normalizeRelativePath(alloc, rel, is_dir);
    errdefer alloc.free(norm_rel);

    if (norm_rel.len == 0 or std.mem.eql(u8, norm_rel, norm_cur)) {
        alloc.free(norm_rel);
        return null;
    }

    if (!isDirectChild(norm_rel, norm_cur)) {
        alloc.free(norm_rel);
        return null;
    }

    const bname = basenameOfPath(norm_rel);
    if (bname.len == 0 or (!options.include_hidden and bname[0] == '.')) {
        alloc.free(norm_rel);
        return null;
    }

    if (!is_dir and !matchesAllowedExtension(
        bname,
        options.allowed_extensions,
    )) {
        alloc.free(norm_rel);
        return null;
    }

    const name_copy = try alloc.dupe(u8, bname);
    return .{
        .name = name_copy,
        .rel_path = norm_rel,
        .is_dir = is_dir,
        .size = size,
    };
}

// 8. Extra classes and constants
pub const propfind_xml_body =
    \\<?xml version="1.0" encoding="utf-8" ?>
    \\<d:propfind xmlns:d="DAV:">
    \\  <d:prop>
    \\    <d:resourcetype/>
    \\    <d:getcontentlength/>
    \\    <d:getlastmodified/>
    \\    <d:getetag/>
    \\  </d:prop>
    \\</d:propfind>
;

/// Directory or file metadata extracted from a WebDAV `PROPFIND` entry.
pub const DavEntry = struct {
    name: []u8,
    rel_path: []u8,
    is_dir: bool,
    size: ?u64 = null,
    last_modified: ?[]u8 = null,
    etag: ?[]u8 = null,

    /// Releases owned entry strings.
    pub fn deinit(self: *DavEntry, alloc: std.mem.Allocator) void {
        alloc.free(self.name);
        alloc.free(self.rel_path);
        if (self.last_modified) |lm| alloc.free(lm);
        if (self.etag) |tag| alloc.free(tag);
    }
};

/// Options controlling `parsePropfindXml` path resolution and filtering.
pub const PropfindOptions = struct {
    /// Base WebDAV root URL or path prefix stripped from response `<href>`s.
    dav_root: []const u8 = "",
    /// Allowed file extensions (case-insensitive, e.g. `".html"`), or empty
    /// to accept all files.
    allowed_extensions: []const []const u8 = &.{},
    /// Whether dotfiles / dot-directories (names starting with `'.'`) appear.
    include_hidden: bool = false,
};

/// Depth header values supported by WebDAV `PROPFIND`.
pub const Depth = enum {
    @"0",
    @"1",
    infinity,
};

/// Parameters passed to `WebDAV.request`.
pub const RequestOptions = struct {
    method: []const u8 = "GET",
    auth_header: ?[]const u8 = null,
    depth: ?[]const u8 = null,
    content_type: ?[]const u8 = null,
    body: ?[]const u8 = null,
    credentials: ?[]const u8 = "omit",
    cache: ?[]const u8 = null,
};

/// Result delivered to async `WebDAV` request callbacks.
/// `status == 0` indicates a network/CORS rejection (`error_message` set).
pub const Response = struct {
    status: i32,
    body: ?[]const u8 = null,
    etag: ?[]const u8 = null,
    error_message: ?[]const u8 = null,
};

// 9. Private declarations
fn freeOptionalSlice(alloc: std.mem.Allocator, slot: *?[]u8) void {
    std.debug.assert(@intFromPtr(slot) != 0);
    if (slot.*) |s| {
        alloc.free(s);
        slot.* = null;
    }
}

fn itemRequest(
    self: WebDAV,
    alloc: std.mem.Allocator,
    method: []const u8,
    rel_path: []const u8,
    content_type: ?[]const u8,
    body: ?[]const u8,
    comptime Context: type,
    ctx: *Context,
    comptime on_done: *const fn (*Context, Response) void,
) !void {
    std.debug.assert(self.dav_root.len > 0);
    std.debug.assert(method.len > 0);
    const url = try buildDavItemUrl(alloc, self.dav_root, rel_path);
    defer alloc.free(url);
    try request(alloc, url, .{
        .method = method,
        .auth_header = self.auth_header,
        .content_type = content_type,
        .body = body,
    }, Context, ctx, on_done);
}

fn MakeRequestContext(
    comptime Context: type,
    comptime on_done: *const fn (*Context, Response) void,
) type {
    return struct {
        alloc: std.mem.Allocator,
        user_ctx: *Context,
        etag: ?[]u8 = null,
        status: i32 = 0,

        fn destroy(self: *@This()) void {
            const alloc = self.alloc;
            freeOptionalSlice(alloc, &self.etag);
            alloc.destroy(self);
        }

        fn send(self: *@This(), url: []const u8, opts: RequestOptions) void {
            const has_hdrs = opts.auth_header != null or
                opts.depth != null or
                opts.content_type != null;
            const hdrs: ?Fetch.Headers = if (has_hdrs)
                Fetch.Headers.init()
            else
                null;
            defer if (hdrs) |h| h.release();

            if (hdrs) |h| {
                if (opts.auth_header) |a| h.set("Authorization", a);
                if (opts.depth) |d| h.set("Depth", d);
                if (opts.content_type) |ct| h.set("Content-Type", ct);
            }

            const non_empty_body: ?[]const u8 = if (opts.body) |b|
                (if (b.len > 0) b else null)
            else
                null;

            const p = webapi.fetch(url, .{
                .method = opts.method,
                .headers = hdrs,
                .body = non_empty_body,
                .credentials = opts.credentials,
                .cache = opts.cache,
            });
            defer p.release();
            p.thenFn(@This(), self, &onRes, &onErr);
        }

        fn onRes(self: *@This(), res: Fetch.Response) void {
            self.status = res.status();
            const hdrs = res.headers();
            defer hdrs.release();
            var etag_buf: [256]u8 = undefined;
            const raw_etag = hdrs.get("ETag", &etag_buf);
            if (raw_etag.len > 0) {
                self.etag = self.alloc.dupe(u8, raw_etag) catch null;
            }
            const tp = res.text();
            defer tp.release();
            tp.thenFn(@This(), self, &onBodyText, &onErr);
        }

        fn onBodyText(self: *@This(), text_h: zjb.Handle) void {
            const alloc = self.alloc;
            const user_ctx = self.user_ctx;
            const status = self.status;
            const etag = self.etag;
            self.etag = null;

            const body_txt = if (!text_h.isNull())
                webapi.stringFromHandleAlloc(alloc, text_h) catch null
            else
                null;
            defer if (body_txt) |b| alloc.free(b);
            defer if (etag) |t| alloc.free(t);

            self.destroy();
            on_done(user_ctx, .{
                .status = status,
                .body = body_txt,
                .etag = etag,
            });
        }

        fn onErr(self: *@This(), err_h: zjb.Handle) void {
            const alloc = self.alloc;
            const user_ctx = self.user_ctx;
            const err_txt: ?[]u8 = if (!err_h.isNull()) blk: {
                const msg_h = err_h.get("message", zjb.Handle);
                defer msg_h.release();
                if (msg_h.isNull()) break :blk null;
                break :blk webapi.stringFromHandleAlloc(
                    alloc,
                    msg_h,
                ) catch null;
            } else null;
            defer if (err_txt) |e| alloc.free(e);

            self.destroy();
            on_done(user_ctx, .{
                .status = 0,
                .error_message = err_txt,
            });
        }
    };
}

fn parseResponseElement(
    alloc: std.mem.Allocator,
    resp_el: dom.Element,
    norm_cur: []const u8,
    options: PropfindOptions,
) !?DavEntry {
    const raw_href = (try firstElementTextAlloc(
        alloc,
        resp_el,
        "href",
    )) orelse return null;
    defer alloc.free(raw_href);

    const trimmed_href = try alloc.dupe(
        u8,
        std.mem.trim(u8, raw_href, " \t\r\n"),
    );
    defer alloc.free(trimmed_href);
    const decoded_href = std.Uri.percentDecodeInPlace(trimmed_href);

    const is_dir = blk: {
        var cols = getElementsByLocalName(resp_el, "collection");
        defer cols.release();
        if (cols.len > 0) break :blk true;
        break :blk std.mem.endsWith(u8, decoded_href, "/");
    };

    const size: ?u64 = blk: {
        const txt = (try firstElementTextAlloc(
            alloc,
            resp_el,
            "getcontentlength",
        )) orelse break :blk null;
        defer alloc.free(txt);
        break :blk std.fmt.parseInt(
            u64,
            std.mem.trim(u8, txt, " \t\r\n"),
            10,
        ) catch null;
    };

    var entry = (try buildValidatedDavEntry(
        alloc,
        decoded_href,
        norm_cur,
        is_dir,
        size,
        options,
    )) orelse return null;
    errdefer entry.deinit(alloc);

    entry.last_modified = try firstElementTextAlloc(
        alloc,
        resp_el,
        "getlastmodified",
    );
    entry.etag = try firstElementTextAlloc(alloc, resp_el, "getetag");
    return entry;
}

fn getElementsByLocalName(
    el: dom.Element,
    comptime local_name: []const u8,
) dom.Element.Iterator {
    std.debug.assert(!el.isNull());
    std.debug.assert(local_name.len > 0);
    const col = el.handle.call(
        "getElementsByTagNameNS",
        .{ zjb.constString("*"), zjb.constString(local_name) },
        zjb.Handle,
    );
    return dom.Element.Iterator.fromHandle(col);
}

fn firstElementTextAlloc(
    alloc: std.mem.Allocator,
    parent: dom.Element,
    comptime local_name: []const u8,
) !?[]u8 {
    var it = getElementsByLocalName(parent, local_name);
    defer it.release();
    const child = it.next() orelse return null;
    defer child.release();
    const txt_h = child.get("textContent", zjb.Handle);
    defer txt_h.release();
    if (txt_h.isNull()) return null;
    const txt = try webapi.stringFromHandleAlloc(alloc, txt_h);
    if (txt.len == 0) {
        alloc.free(txt);
        return null;
    }
    return txt;
}

fn isDirectChild(norm_rel: []const u8, norm_cur: []const u8) bool {
    std.debug.assert(norm_rel.len > 0);
    std.debug.assert(norm_cur.len == 0 or @intFromPtr(norm_cur.ptr) != 0);
    if (norm_cur.len > 0) {
        if (!std.mem.startsWith(u8, norm_rel, norm_cur)) return false;
        const sub = std.mem.trimEnd(u8, norm_rel[norm_cur.len..], "/");
        return sub.len > 0 and std.mem.indexOfScalar(u8, sub, '/') == null;
    }
    const sub = std.mem.trimEnd(u8, norm_rel, "/");
    return sub.len > 0 and std.mem.indexOfScalar(u8, sub, '/') == null;
}

fn matchesAllowedExtension(
    filename: []const u8,
    allowed: []const []const u8,
) bool {
    std.debug.assert(filename.len > 0);
    std.debug.assert(allowed.len == 0 or @intFromPtr(allowed.ptr) != 0);
    if (allowed.len == 0) return true;
    for (allowed) |ext| {
        if (endsWithIgnoreCase(filename, ext)) return true;
    }
    return false;
}

fn stripUrlSchemeAndHost(input: []const u8) []const u8 {
    std.debug.assert(input.len == 0 or @intFromPtr(input.ptr) != 0);
    if (std.mem.indexOf(u8, input, "://")) |scheme_idx| {
        const after_scheme = input[scheme_idx + 3 ..];
        if (std.mem.indexOfScalar(u8, after_scheme, '/')) |slash_idx| {
            return after_scheme[slash_idx..];
        }
        return "";
    }
    return input;
}

fn extractRelativePathFromHref(
    decoded_href: []const u8,
    norm_cur: []const u8,
    dav_root: []const u8,
) ?[]const u8 {
    const path = stripUrlSchemeAndHost(decoded_href);

    if (dav_root.len > 0) {
        const stripped = stripUrlSchemeAndHost(dav_root);
        const root_path = std.mem.trimEnd(u8, stripped, "/");
        if (root_path.len > 0 and std.mem.startsWith(u8, path, root_path)) {
            return std.mem.trimStart(u8, path[root_path.len..], "/");
        }
    }

    if (norm_cur.len > 0) {
        if (std.mem.indexOf(u8, path, norm_cur)) |idx| {
            return path[idx..];
        }
    }

    return std.mem.trimStart(u8, path, "/");
}

fn endsWithIgnoreCase(haystack: []const u8, suffix: []const u8) bool {
    if (haystack.len < suffix.len) return false;
    return std.ascii.eqlIgnoreCase(
        haystack[haystack.len - suffix.len ..],
        suffix,
    );
}

fn asciiLessThanIgnoreCase(a: []const u8, b: []const u8) bool {
    const min_len = @min(a.len, b.len);
    for (a[0..min_len], b[0..min_len]) |ca, cb| {
        const la = std.ascii.toLower(ca);
        const lb = std.ascii.toLower(cb);
        if (la != lb) return la < lb;
    }
    return a.len < b.len;
}
