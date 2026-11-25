//! Interactive `std.Io` (`webapi.WebApiIo`) showcase demonstrating persistent
//! IndexedDB file/directory I/O (`std.Io.Dir`), `std.http.Client` networking
//! over the browser `Fetch` API, and Promise-backed `io.async`/`await`.

// 1. Imports
const std = @import("std");
const webapi = @import("webapi");

// 2. Shortcuts on imports
const IoDemo = @This();
const dom = webapi.dom;
const Event = webapi.Event;
const WebApiIo = webapi.WebApiIo;
const zjb = webapi.zjb;

// 3. File-level struct members
allocator: std.mem.Allocator,
web_io: WebApiIo = undefined,
initialized: bool = false,

// 5. init
/// Constructs an uninitialized `IoDemo` storing `allocator` (`bind` initializes
/// `web_io` in-place once `App` has a stable heap address).
pub fn init(allocator: std.mem.Allocator) IoDemo {
    std.debug.assert(@intFromPtr(allocator.vtable) != 0);
    return .{ .allocator = allocator };
}

// 7. Public functions
/// Initializes `WebApiIo` in-place on `App`'s heap storage and attaches click
/// listeners for `#btn-io-fs`, `#btn-io-fetch`, and `#btn-io-clear`.
pub fn bind(self: *IoDemo) void {
    std.debug.assert(@intFromPtr(self) != 0);
    std.debug.assert(@intFromPtr(self.allocator.vtable) != 0);

    self.web_io.init(.{
        .gpa = self.allocator,
        .db_name = "webapi_example_io",
        .store_name = "files",
    }) catch {
        dom.document().setElemText(
            "io-output",
            "Failed to initialize WebApiIo.",
        );
        return;
    };
    self.initialized = true;

    const doc = dom.document();
    if (doc.getElementById("btn-io-fs")) |btn| {
        defer btn.release();
        btn.addEventListener("click", IoDemo, self, onFsClick);
    }
    if (doc.getElementById("btn-io-fetch")) |btn| {
        defer btn.release();
        btn.addEventListener("click", IoDemo, self, onFetchClick);
    }
    if (doc.getElementById("btn-io-clear")) |btn| {
        defer btn.release();
        btn.addEventListener("click", IoDemo, self, onClearClick);
    }
}

// 9. Private declarations
fn onFsClick(self: *IoDemo, _: Event.PointerEvent) void {
    if (!self.initialized) return;
    dom.document().setElemText(
        "io-output",
        "Running std.Io.Dir operations on IndexedDB...",
    );
    const p = self.web_io.callPromising(IoDemo, self, runFsDemo) catch {
        dom.document().setElemText("io-output", "Failed to start std.Io task.");
        return;
    };
    defer p.release();
    p.thenFn(IoDemo, self, null, onRunError);
}

fn onFetchClick(self: *IoDemo, _: Event.PointerEvent) void {
    if (!self.initialized) return;
    dom.document().setElemText(
        "io-output",
        "Fetching data.json via std.http.Client + WebApiIo...",
    );

    if (self.web_io.isJspiSupported()) {
        const p = self.web_io.callPromising(IoDemo, self, runFetchDemo) catch {
            dom.document().setElemText(
                "io-output",
                "Failed to start JSPI fetch task.",
            );
            return;
        };
        defer p.release();
        p.thenFn(IoDemo, self, null, onRunError);
        return;
    }

    const pre_p = self.web_io.prefetch("data.json", null) catch {
        dom.document().setElemText(
            "io-output",
            "Failed to prefetch data.json.",
        );
        return;
    };
    defer pre_p.release();
    pre_p.thenFn(IoDemo, self, onPrefetched, onRunError);
}

fn onPrefetched(self: *IoDemo) void {
    const p = self.web_io.callPromising(IoDemo, self, runFetchDemo) catch {
        dom.document().setElemText("io-output", "Failed to start fetch demo.");
        return;
    };
    defer p.release();
    p.thenFn(IoDemo, self, null, onRunError);
}

fn onClearClick(self: *IoDemo, _: Event.PointerEvent) void {
    if (!self.initialized) return;
    self.web_io.fs.clearIndexedFsMountPoint("/");
    dom.document().setElemText(
        "io-output",
        "Cleared IndexedDB mount (\"webapi_example_io\").",
    );
}

fn onRunError(_: *IoDemo, err_h: zjb.Handle) void {
    webapi.console.@"error"("WebApiIo demo error:", .{err_h});
    dom.document().setElemText(
        "io-output",
        "WebApiIo task failed (see console).",
    );
}

fn runFsDemo(_: *IoDemo, io: std.Io) void {
    const cwd = std.Io.Dir.cwd();
    cwd.createDirPath(io, "journal") catch {
        dom.document().setElemText("io-output", "createDirPath failed.");
        return;
    };

    var cnt_buf: [32]u8 = undefined;
    const prev_cnt: u32 = if (cwd.readFile(
        io,
        "journal/counter.txt",
        &cnt_buf,
    )) |slice|
        std.fmt.parseInt(
            u32,
            std.mem.trim(u8, slice, " \t\r\n"),
            10,
        ) catch 0
    else |_|
        0;

    const next_cnt = prev_cnt + 1;
    const cnt_text = std.fmt.bufPrint(&cnt_buf, "{d}\n", .{next_cnt}) catch {
        return;
    };
    cwd.writeFile(io, .{
        .sub_path = "journal/counter.txt",
        .data = cnt_text,
    }) catch {
        dom.document().setElemText("io-output", "Failed to write counter.txt.");
        return;
    };

    var note_buf: [128]u8 = undefined;
    const now_ms = std.Io.Clock.real.now(io).toMilliseconds();
    const note_text = std.fmt.bufPrint(
        &note_buf,
        "Persisted via std.Io at {d} ms (run #{d})",
        .{ now_ms, next_cnt },
    ) catch return;
    cwd.writeFile(io, .{
        .sub_path = "journal/note.txt",
        .data = note_text,
    }) catch return;

    var read_back: [128]u8 = undefined;
    const loaded_note = cwd.readFile(
        io,
        "journal/note.txt",
        &read_back,
    ) catch "";
    const st = cwd.statFile(io, "journal/note.txt", .{}) catch return;

    var list_buf: [256]u8 = undefined;
    var list_w: std.Io.Writer = .fixed(&list_buf);
    if (cwd.openDir(io, "journal", .{ .iterate = true })) |jdir| {
        defer jdir.close(io);
        var it = jdir.iterate();
        var first = true;
        while (it.next(io) catch null) |ent| {
            if (!first) list_w.writeAll(", ") catch {};
            list_w.writeAll(ent.name) catch {};
            first = false;
        }
    } else |_| {}

    var out_buf: [512]u8 = undefined;
    const msg = std.fmt.bufPrint(
        &out_buf,
        "IndexedDB persistence (reload page & click again!):\n" ++
            "  run count : {d}\n" ++
            "  note.txt  : \"{s}\" ({d} bytes)\n" ++
            "  /journal  : [{s}]",
        .{ next_cnt, loaded_note, st.size, list_w.buffered() },
    ) catch "IndexedDB write succeeded.";
    dom.document().setElemText("io-output", msg);
}

fn computeFnv1a32(bytes: []const u8) u32 {
    var h: u32 = 0x811c9dc5;
    for (bytes) |b| {
        h ^= b;
        h *%= 0x01000193;
    }
    return h;
}

fn runFetchDemo(self: *IoDemo, io: std.Io) void {
    var client = self.web_io.httpClient(self.allocator);
    defer client.deinit();

    var body_out: std.Io.Writer.Allocating = .init(self.allocator);
    defer body_out.deinit();

    const res = client.fetch(.{
        .location = .{ .url = "http://origin.local/data.json" },
        .method = .GET,
        .response_writer = &body_out.writer,
    }) catch |err| {
        var ebuf: [128]u8 = undefined;
        const emsg = std.fmt.bufPrint(
            &ebuf,
            "std.http.Client.fetch error: {s}",
            .{@errorName(err)},
        ) catch "std.http.Client.fetch failed.";
        dom.document().setElemText("io-output", emsg);
        return;
    };

    const payload = body_out.written();
    var hash_fut = io.async(computeFnv1a32, .{payload});
    const checksum = hash_fut.await(io);

    const cwd = std.Io.Dir.cwd();
    cwd.createDirPath(io, "journal") catch {};
    cwd.writeFile(io, .{
        .sub_path = "journal/fetched_data.json",
        .data = payload,
    }) catch {};
    const saved_len = if (cwd.statFile(
        io,
        "journal/fetched_data.json",
        .{},
    )) |s|
        s.size
    else |_|
        0;

    var out_buf: [1024]u8 = undefined;
    const mode_str = if (self.web_io.isJspiSupported())
        "live JSPI stack suspension"
    else
        "Promise fallback";
    const msg = std.fmt.bufPrint(
        &out_buf,
        "HTTP {d} via std.http.Client ({s})\n" ++
            "io.async FNV-1a: 0x{x:0>8} | " ++
            "saved /journal/fetched_data.json ({d} B)\n\n{s}",
        .{ @backingInt(res.status), mode_str, checksum, saved_len, payload },
    ) catch payload;
    dom.document().setElemText("io-output", msg);
}
