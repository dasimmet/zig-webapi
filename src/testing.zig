//! Host-side unit tests for `webapi` modules and the in-memory `zjb` mock.

const std = @import("std");
const webapi = @import("webapi.zig");

const dom = webapi.dom;
const IDB = webapi.IndexedDb;
const zjb = webapi.zjb;
const Mock = zjb.Mock;

/// Writes a single-file POSIX ustar tar archive into `buf` via
/// `std.tar.Writer` and returns the written slice.
fn buildSingleFileTar(
    buf: []u8,
    name: []const u8,
    payload: []const u8,
) ![]const u8 {
    std.debug.assert(name.len > 0);
    std.debug.assert(buf.len >= 2048);

    var out_w: std.Io.Writer = .fixed(buf);
    var tar_writer: std.tar.Writer = .{
        .underlying_writer = &out_w,
    };
    try tar_writer.writeFileBytes(name, payload, .{});
    try tar_writer.finishPedantically();
    return out_w.buffered();
}

test "zjb mock: handle lifecycle, double free detection, and leak tracking" {
    zjb.resetMock();
    try zjb.assertNoHandleLeaks();

    // 1. String allocation and release
    const s1 = zjb.string("hello");
    try std.testing.expectEqual(@as(u32, 1), zjb.unreleasedHandleCount());
    const s2 = zjb.string("world");
    try std.testing.expectEqual(@as(u32, 2), zjb.unreleasedHandleCount());

    s1.release();
    try std.testing.expectEqual(@as(u32, 1), zjb.unreleasedHandleCount());
    s2.release();
    try std.testing.expectEqual(@as(u32, 0), zjb.unreleasedHandleCount());
    try zjb.assertNoHandleLeaks();

    // 2. ConstHandles do not count toward leaks
    const cs = zjb.constString("constant");
    const g = zjb.global("document");
    _ = cs;
    _ = g;
    try std.testing.expectEqual(@as(u32, 0), zjb.unreleasedHandleCount());
    try zjb.assertNoHandleLeaks();

    // 3. Double free detection
    const s3 = zjb.string("double_free_test");
    try std.testing.expectEqual(@as(u32, 1), zjb.unreleasedHandleCount());
    s3.release();
    try std.testing.expectEqual(@as(u32, 0), zjb.unreleasedHandleCount());
    s3.release(); // second release
    try std.testing.expectError(
        error.JsHandleDoubleFree,
        zjb.assertNoHandleLeaks(),
    );

    // 4. Leak detection
    zjb.resetMock();
    const leaked = zjb.string("leaked_string");
    _ = leaked;
    try std.testing.expectError(
        error.LeakedJsHandles,
        zjb.assertNoHandleLeaks(),
    );

    zjb.resetMock();
    try zjb.assertNoHandleLeaks();
}

test "DOMRect fromHandle extracts fundamental fields and computes bounds" {
    const r = dom.DOMRect.fromHandle(.null);
    try std.testing.expectEqual(@as(f32, 0.0), r.x);
    try std.testing.expectEqual(@as(f32, 0.0), r.y);
    try std.testing.expectEqual(@as(f32, 0.0), r.width);
    try std.testing.expectEqual(@as(f32, 0.0), r.height);
    try std.testing.expectEqual(@as(f32, 0.0), r.top());
    try std.testing.expectEqual(@as(f32, 0.0), r.right());
    try std.testing.expectEqual(@as(f32, 0.0), r.bottom());
    try std.testing.expectEqual(@as(f32, 0.0), r.left());

    const rect: dom.DOMRect = .{
        .x = 10.0,
        .y = 20.0,
        .width = 100.0,
        .height = 50.0,
    };
    try std.testing.expectEqual(@as(f32, 20.0), rect.top());
    try std.testing.expectEqual(@as(f32, 110.0), rect.right());
    try std.testing.expectEqual(@as(f32, 70.0), rect.bottom());
    try std.testing.expectEqual(@as(f32, 10.0), rect.left());

    // Negative dimensions per W3C Geometry Interfaces
    const neg: dom.DOMRect = .{
        .x = 100.0,
        .y = 50.0,
        .width = -40.0,
        .height = -20.0,
    };
    try std.testing.expectEqual(@as(f32, 30.0), neg.top());
    try std.testing.expectEqual(@as(f32, 100.0), neg.right());
    try std.testing.expectEqual(@as(f32, 50.0), neg.bottom());
    try std.testing.expectEqual(@as(f32, 60.0), neg.left());
}

test "webapi.Fetch RequestInit" {
    const init = webapi.Fetch.RequestInit{
        .method = "POST",
        .body = "hello=world",
    };
    try std.testing.expectEqualStrings("POST", init.method);
    try std.testing.expectEqualStrings("hello=world", init.body.?);
}

test "webapi.IndexedDb TransactionMode @tagName" {
    try std.testing.expectEqualStrings(
        "readonly",
        @tagName(IDB.TransactionMode.readonly),
    );
    try std.testing.expectEqualStrings(
        "readwrite",
        @tagName(IDB.TransactionMode.readwrite),
    );
    try std.testing.expectEqualStrings(
        "versionchange",
        @tagName(IDB.TransactionMode.versionchange),
    );
}

test "webapi.Wasi WasiOptions and preopens" {
    const opts = webapi.Wasi.Options{
        .allocator = std.testing.allocator,
        .args = &.{ "zig", "build-exe", "main.zig" },
        .env = &.{
            .{ "ZIG_LIB_DIR", "/lib" },
            .{ "ZIG_GLOBAL_CACHE_DIR", "/cache/global" },
            .{ "ZIG_LOCAL_CACHE_DIR", "/cache/local" },
        },
        .preopens = &.{
            .{ .dir = "." },
            .{ .tar = .{ .path = "/lib" } },
            .{
                .indexed_fs = .{
                    .path = "/cache",
                    .db_name = "zig_cache",
                    .store_name = "cache",
                },
            },
        },
    };
    try std.testing.expectEqual(opts.args.len, 3);
    try std.testing.expectEqual(opts.env.len, 3);
    try std.testing.expectEqual(opts.preopens.len, 3);
    try std.testing.expectEqualStrings(".", opts.preopens[0].path());
    try std.testing.expectEqualStrings("/lib", opts.preopens[1].path());
    try std.testing.expectEqualStrings("/cache", opts.preopens[2].path());
}

test "webapi.Wasi virtual filesystem and in-memory tar mounting" {
    const allocator = std.testing.allocator;

    var tar_buf: [2048]u8 = undefined;
    const tar_bytes = try buildSingleFileTar(
        &tar_buf,
        "std/std.zig",
        "pub const ok = true;\n",
    );

    const wasi = try webapi.Wasi.init(.{
        .allocator = allocator,
        .args = &.{ "zig", "build-exe", "main.zig" },
        .preopens = &.{
            .{ .dir = "." },
            .{ .tar = .{ .path = "/lib", .bytes = tar_bytes } },
            .{ .dir = "/cache" },
        },
    });
    defer wasi.deinit();

    const fn_src = "export fn add(a: i32, b: i32) i32 { return a + b; }";
    try wasi.fs.writeFile("main.zig", fn_src);
    try std.testing.expect(wasi.fs.fileExists("main.zig"));
    try std.testing.expect(wasi.fs.fileExists("/main.zig"));

    const content = wasi.fs.readFile("main.zig");
    try std.testing.expect(content != null);
    try std.testing.expectEqualStrings(fn_src, content.?);

    try wasi.fs.writeFile("/cache/test.txt", "cache data");
    try std.testing.expect(wasi.fs.fileExists("/cache/test.txt"));
    try std.testing.expectEqualStrings(
        "cache data",
        wasi.fs.readFile("/cache/test.txt").?,
    );

    try std.testing.expect(wasi.fs.fileExists("/lib/std/std.zig"));
    try std.testing.expectEqualStrings(
        "pub const ok = true;\n",
        wasi.fs.readFile("/lib/std/std.zig").?,
    );
}

test "webapi.Wasi resetForNextRun preserves virtual filesystem" {
    const allocator = std.testing.allocator;

    const wasi = try webapi.Wasi.init(.{
        .allocator = allocator,
        .args = &.{ "app", "arg1" },
        .preopens = &.{
            .{ .dir = "." },
        },
    });
    defer wasi.deinit();

    try wasi.fs.writeFile("file.txt", "persisted data");
    try wasi.resetForNextRun(&.{ "app", "arg2" });

    try std.testing.expect(wasi.fs.fileExists("file.txt"));
    const content = wasi.fs.readFile("file.txt");
    try std.testing.expect(content != null);
    try std.testing.expectEqualStrings("persisted data", content.?);
    try std.testing.expectEqual(wasi.args.len, 2);
    try std.testing.expectEqualStrings("arg2", wasi.args[1]);
}

test "webapi.Wasi removeFile and removeDirTree" {
    const allocator = std.testing.allocator;

    const wasi = try webapi.Wasi.init(.{
        .allocator = allocator,
        .args = &.{"app"},
        .preopens = &.{
            .{ .dir = "." },
            .{ .dir = "/cache" },
            .{ .dir = "/lib" },
        },
    });
    defer wasi.deinit();

    try wasi.fs.writeFile("out.wasm", "wasm binary");
    try wasi.fs.writeFile("/cache/a.o", "cache obj a");
    try wasi.fs.writeFile("/cache/nested/b.o", "cache obj b");
    try wasi.fs.writeFile("/lib/std.zig", "std library");

    try std.testing.expect(wasi.fs.fileExists("out.wasm"));
    try std.testing.expect(wasi.fs.fileExists("/cache/a.o"));
    try std.testing.expect(wasi.fs.fileExists("/cache/nested/b.o"));
    try std.testing.expect(wasi.fs.fileExists("/lib/std.zig"));

    // removeFile removes specific file
    try std.testing.expect(wasi.fs.removeFile("out.wasm"));
    try std.testing.expect(!wasi.fs.fileExists("out.wasm"));
    try std.testing.expect(!wasi.fs.removeFile("out.wasm"));

    // removeDirTree removes directory contents recursively
    try std.testing.expect(wasi.fs.removeDirTree("/cache"));
    try std.testing.expect(!wasi.fs.fileExists("/cache/a.o"));
    try std.testing.expect(!wasi.fs.fileExists("/cache/nested/b.o"));
    try std.testing.expect(wasi.fs.fileExists("/lib/std.zig"));
}

test "webapi.WebAssembly Suspending and async compile/instantiate" {
    Mock.reset();

    {
        try std.testing.expect(webapi.WebAssembly.isJspiSupported());

        var null_susp = webapi.WebAssembly.Suspending.null;
        try std.testing.expect(null_susp.isNull());
        null_susp.release();
        try std.testing.expect(null_susp.isNull());

        const fn_h = Mock.allocHandle("mock_fn");
        defer fn_h.release();
        var susp = try webapi.WebAssembly.Suspending.init(fn_h);
        try std.testing.expect(!susp.isNull());
        susp.release();
        try std.testing.expect(susp.isNull());

        const prom_h = try webapi.WebAssembly.promising(fn_h);
        prom_h.release();

        const wasm_hdr = "\x00asm\x01\x00\x00\x00";
        const cp = try webapi.WebAssembly.compile(wasm_hdr);
        cp.release();

        const ip = try webapi.WebAssembly.instantiateAsync(wasm_hdr, null);
        ip.release();
    }

    try Mock.assertNoHandleLeaks();
}

test "webapi.IndexedDb null handles and FileEntryData" {
    Mock.reset();

    try std.testing.expect(IDB.Database.null.isNull());
    try std.testing.expect(IDB.Transaction.null.isNull());
    try std.testing.expect(IDB.ObjectStore.null.isNull());

    const data = try std.testing.allocator.dupe(u8, "payload");
    const entry: IDB.ObjectStore.FileEntryData = .{
        .data = data,
        .mtime = 123_456,
    };
    defer std.testing.allocator.free(entry.data);
    try std.testing.expectEqual(@as(u64, 123_456), entry.mtime);
    try std.testing.expectEqualStrings("payload", entry.data);

    try Mock.assertNoHandleLeaks();
}

test "webapi.Wasi IndexedFs mount point read restore and write flush" {
    const allocator = std.testing.allocator;
    Mock.reset();

    const wasi = try webapi.Wasi.init(.{
        .allocator = allocator,
        .args = &.{"zig"},
        .preopens = &.{
            .{ .dir = "." },
            .{
                .indexed_fs = .{
                    .path = "/cache",
                    .db_name = "zig_cache",
                    .store_name = "cache",
                },
            },
        },
    });
    defer {
        wasi.deinit();
        Mock.assertNoHandleLeaks() catch unreachable;
    }

    try std.testing.expect(wasi.fs.areAllIndexedFsMountsReady());
    const mount_point = wasi.fs.findIndexedFsMountPoint("/cache/o/abc").?;
    try std.testing.expect(wasi.fs.findIndexedFsMountPoint("/cache") != null);
    try std.testing.expect(
        wasi.fs.findIndexedFsMountPoint("/cache2/a") == null,
    );
    try std.testing.expect(
        wasi.fs.findIndexedFsMountPoint("/lib/std.zig") == null,
    );
    try std.testing.expectEqualStrings(
        "o/abc",
        webapi.Wasi.FileSystem.indexedFsStoreKey("/cache/o/abc", "/cache").?,
    );
    try std.testing.expectEqualStrings(
        "foo/bar",
        webapi.Wasi.FileSystem.indexedFsStoreKey("/foo/bar", "/").?,
    );
    try std.testing.expect(
        webapi.Wasi.FileSystem.indexedFsStoreKey("/cache", "/cache") == null,
    );

    try wasi.fs.putMockIndexedFsEntry("/cache/o/abc", "cached-obj", 42_000_000);
    try std.testing.expect(!wasi.fs.fileExists("/cache/o/abc"));
    try std.testing.expect(mount_point.mock_entries.contains("o/abc"));
    try std.testing.expect(!mount_point.mock_entries.contains("/cache/o/abc"));

    const restored = wasi.fs.checkIndexedFsForRead("/cache/o/abc");
    try std.testing.expect(restored != null);
    try std.testing.expectEqual(@as(u64, 42_000_000), restored.?.mtime);
    try std.testing.expectEqualStrings("cached-obj", restored.?.data);
    try std.testing.expect(wasi.fs.fileExists("/cache/o/abc"));

    // Read-only open must not persist changes back on close/reset
    try wasi.fs.writeFileWithMtime("/cache/o/abc", "tmp-mem", 50_000_000);
    const ro_path = try allocator.dupe(u8, "/cache/o/abc");
    try wasi.fs.fds.put(10, .{
        .path = ro_path,
        .is_dir = false,
        .is_write = false,
        .was_written = false,
    });
    try wasi.resetForNextRun(&.{"zig"});
    const still_old = wasi.fs.getMockIndexedFsEntry("/cache/o/abc").?;
    try std.testing.expectEqualStrings("cached-obj", still_old.data);
    try std.testing.expectEqual(@as(u64, 42_000_000), still_old.mtime);

    // Open for writing must save data & mtime back to IndexedFs mount store
    try wasi.fs.writeFileWithMtime("/cache/o/abc", "updated-obj", 99_000_000);
    const rw_path = try allocator.dupe(u8, "/cache/o/abc");
    try wasi.fs.fds.put(11, .{
        .path = rw_path,
        .is_dir = false,
        .is_write = true,
        .was_written = true,
    });
    try wasi.resetForNextRun(&.{"zig"});
    const saved = wasi.fs.getMockIndexedFsEntry("/cache/o/abc").?;
    try std.testing.expectEqualStrings("updated-obj", saved.data);
    try std.testing.expectEqual(@as(u64, 99_000_000), saved.mtime);

    wasi.fs.removeIndexedFsEntry("/cache/o/abc");
    try std.testing.expect(
        wasi.fs.getMockIndexedFsEntry("/cache/o/abc") == null,
    );

    try wasi.fs.putMockIndexedFsEntry("/cache/o/def", "other", 10);
    wasi.fs.clearIndexedFsMountPoint("/cache");
    try std.testing.expect(
        wasi.fs.getMockIndexedFsEntry("/cache/o/def") == null,
    );

    // Exercise start, startPromise, and resetForNextRun handle cleanup
    const mock_inst = Mock.allocHandle("mock_inst");
    wasi.setInstance(webapi.WebAssembly.Instance.fromHandle(mock_inst));
    const start_p = try wasi.startPromise();
    start_p.release();
    _ = wasi.start();
    try wasi.resetForNextRun(&.{"zig"});
    try std.testing.expect(wasi.start_run_fn.isNull());
    try std.testing.expect(wasi.start_exports_h.isNull());
    try std.testing.expect(wasi.start_resolve_h.isNull());
}

test "webapi.dom wrappers release handles without leaks" {
    Mock.reset();
    {
        const perf = dom.window().performance();
        defer perf.release();
        _ = perf.now();

        const nav = dom.window().navigator();
        defer nav.release();
        const cb = nav.clipboard();
        defer cb.release();
        const wp = cb.writeText("abc");
        wp.release();
        const rp = cb.readText();
        rp.release();

        const evt_h = Mock.allocHandle("mock_evt");
        defer evt_h.release();
        const ev = webapi.Event.fromHandle(evt_h);
        ev.preventDefault();
        ev.stopPropagation();
        ev.stopImmediatePropagation();
        _ = ev.defaultPrevented();
        _ = ev.bubbles();
        _ = ev.cancelable();
        _ = ev.isTrusted();
        _ = ev.timeStamp();
        var str_buf: [16]u8 = undefined;
        _ = ev.eventType(&str_buf);

        const kb = webapi.Event.KeyboardEvent.fromEvent(ev);
        kb.preventDefault();
        _ = kb.key(&str_buf);
        _ = kb.code(&str_buf);
        _ = kb.ctrlKey();
        _ = kb.shiftKey();
        _ = kb.altKey();
        _ = kb.metaKey();
        _ = kb.repeat();
        _ = kb.isComposing();

        const me = webapi.Event.MouseEvent.fromEvent(ev);
        _ = me.button();
        _ = me.buttons();
        _ = me.clientX();
        _ = me.clientY();
        _ = me.offsetX();
        _ = me.offsetY();

        const pe = webapi.Event.PointerEvent.fromMouseEvent(me);
        _ = pe.pointerId();
        _ = pe.pointerType(&str_buf);
        _ = pe.isPrimary();
        _ = pe.clientX();

        const we = webapi.Event.WheelEvent.fromEvent(ev);
        _ = we.deltaX();
        _ = we.deltaY();
        _ = we.deltaZ();
        _ = we.deltaMode();
        _ = we.shiftKey();

        const ce = webapi.Event.ClipboardEvent.fromEvent(ev);
        const dt = ce.clipboardData();
        defer dt.release();
        if (try dt.getDataAlloc(std.testing.allocator, "text")) |data| {
            std.testing.allocator.free(data);
        }

        const mqle = webapi.Event.MediaQueryListEvent.fromEvent(ev);
        _ = mqle.matches();
        _ = mqle.media(&str_buf);

        const ev_ns = webapi.Event;
        try std.testing.expect(
            ev_ns.EventFor("keydown") == ev_ns.KeyboardEvent,
        );
        try std.testing.expect(ev_ns.EventFor("paste") == ev_ns.ClipboardEvent);
        try std.testing.expect(ev_ns.EventFor("mousedown") == ev_ns.MouseEvent);
        try std.testing.expect(ev_ns.EventFor("mousemove") == ev_ns.MouseEvent);
        try std.testing.expect(ev_ns.EventFor("mouseup") == ev_ns.MouseEvent);
        try std.testing.expect(ev_ns.EventFor("click") == ev_ns.PointerEvent);
        try std.testing.expect(
            ev_ns.EventFor("contextmenu") == ev_ns.PointerEvent,
        );
        try std.testing.expect(ev_ns.EventFor("wheel") == ev_ns.WheelEvent);
        try std.testing.expect(
            ev_ns.EventFor("change") == ev_ns.MediaQueryListEvent,
        );

        const el_h = Mock.allocHandle("mock_el");
        const el = dom.Element.init(el_h);
        defer el.release();
        const st = el.style();
        defer st.release();
        st.setProperty("cursor", "text");

        const mql = dom.window().matchMedia("(prefers-color-scheme: dark)");
        defer mql.release();
        try std.testing.expect(!mql.isNull());
        _ = mql.matches();
    }
    try Mock.assertNoHandleLeaks();
}

test "webapi.Wasi.FileSystem standalone lifecycle" {
    const allocator = std.testing.allocator;
    const FS = webapi.Wasi.FileSystem;

    try std.testing.expectEqual(@as(i32, 0), FS.STDIN_FILENO);
    try std.testing.expectEqual(@as(i32, 1), FS.STDOUT_FILENO);
    try std.testing.expectEqual(@as(i32, 2), FS.STDERR_FILENO);
    try std.testing.expectEqual(@as(i32, 3), FS.FIRST_PREOPEN_FD);

    var empty_fs: FS = undefined;
    try empty_fs.init(.{ .allocator = allocator });
    defer empty_fs.deinit();
    try std.testing.expectEqual(@as(i32, 3), empty_fs.next_fd);

    var fs: FS = undefined;
    try fs.init(.{
        .allocator = allocator,
        .preopens = &.{
            .{ .dir = "." },
            .{ .dir = "/cache" },
        },
    });
    defer fs.deinit();
    try std.testing.expectEqual(@as(i32, 5), fs.next_fd);

    try std.testing.expect(fs.isPreopenOrRoot("/"));
    try std.testing.expect(fs.isPreopenOrRoot("/cache"));
    try std.testing.expect(!fs.isPreopenOrRoot("/tmp"));

    try fs.writeFile("/cache/item.bin", "hello");
    try std.testing.expect(fs.fileExists("/cache/item.bin"));
    try std.testing.expectEqualStrings(
        "hello",
        fs.readFile("/cache/item.bin").?,
    );

    const fd_path = try allocator.dupe(u8, "/cache/item.bin");
    try fs.fds.put(5, .{ .path = fd_path, .is_dir = false });
    fs.resetFds();
    try std.testing.expectEqual(@as(usize, 0), fs.fds.count());
    try std.testing.expectEqual(@as(i32, 5), fs.next_fd);

    try std.testing.expect(fs.removeDirTree("/cache"));
    try std.testing.expect(!fs.fileExists("/cache/item.bin"));
}

test "webapi.Promise.Typed wrappers and handle cleanup" {
    Mock.reset();
    {
        const Ctx = struct {
            void_calls: u32 = 0,
            code_val: i32 = 0,
            mod_calls: u32 = 0,

            fn onVoid(self: *@This()) void {
                self.void_calls += 1;
            }

            fn onCode(self: *@This(), code: i32) void {
                self.code_val = code;
            }

            fn onMod(self: *@This(), mod: webapi.WebAssembly.Module) void {
                if (!mod.isNull()) self.mod_calls += 1;
            }
        };

        var ctx: Ctx = .{};

        const nav = dom.window().navigator();
        defer nav.release();
        const cb = nav.clipboard();
        defer cb.release();
        const wp = cb.writeText("hi");
        try std.testing.expect(!wp.isNull());
        wp.thenFn(Ctx, &ctx, &Ctx.onVoid, null);
        wp.release();

        const p_code_h = Mock.allocHandle("mock_i32_promise");
        const p_code = webapi.Promise.Typed(i32).fromHandle(p_code_h);
        try std.testing.expect(!p_code.isNull());
        p_code.thenFn(Ctx, &ctx, &Ctx.onCode, null);
        p_code.release();

        const p_mod_h = Mock.allocHandle("mock_mod_promise");
        const p_mod = webapi.Promise.Typed(webapi.WebAssembly.Module)
            .fromHandle(p_mod_h);
        try std.testing.expect(!p_mod.isNull());
        p_mod.thenFn(Ctx, &ctx, &Ctx.onMod, null);
        p_mod.release();
    }
    try Mock.assertNoHandleLeaks();
}

test "webapi shared callback dispatcher and trampolines" {
    Mock.reset();
    {
        const State = struct {
            count: u32 = 0,
            fn onCall(self: *@This(), h: zjb.Handle) void {
                _ = h;
                self.count += 1;
            }
        };
        const EmptyCtx = struct {
            fn onEmpty(_: *@This(), _: zjb.Handle) void {}
        };

        var state: State = .{};
        var empty: EmptyCtx = .{};
        const target = Mock.allocHandle("mock_target");
        defer target.release();

        const f1 = webapi.boundFunction(State, &state, &State.onCall);
        f1.release();
        const f2 = webapi.boundFunctionOwned(State, &state, &State.onCall);
        f2.release();
        const f3 = webapi.boundFunction(EmptyCtx, &empty, &EmptyCtx.onEmpty);
        f3.release();

        webapi.boundEventListener(
            State,
            "click",
            target,
            &State.onCall,
            &state,
        );
        webapi.boundEventListenerOwned(
            EmptyCtx,
            "click",
            target,
            &EmptyCtx.onEmpty,
            &empty,
        );
    }
    try Mock.assertNoHandleLeaks();
}

test "dom.Window setTimeout and setInterval typed callbacks" {
    Mock.reset();
    {
        const TimerCtx = struct {
            ticks: u32 = 0,
            fn onTimeout(self: *@This()) void {
                self.ticks += 1;
            }
            fn onInterval(self: *@This()) void {
                self.ticks += 10;
            }
        };

        var ctx: TimerCtx = .{};
        const win = dom.window();
        const tid = win.setTimeout(TimerCtx, &ctx, TimerCtx.onTimeout, 25);
        win.clearTimeout(tid);
        const iid = win.setInterval(TimerCtx, &ctx, TimerCtx.onInterval, 50);
        win.clearInterval(iid);

        const opened = win.open("webapi/", "_blank");
        if (!opened.isNull()) opened.release();
    }
    try Mock.assertNoHandleLeaks();
}

test "webapi.dom typed event listeners via boundEventListenerTyped" {
    Mock.reset();
    {
        const ListenerCtx = struct {
            count: u32 = 0,

            fn onKey(self: *@This(), ev: webapi.Event.KeyboardEvent) void {
                if (!ev.isNull()) self.count += 1;
            }
            fn onClick(self: *@This(), ev: webapi.Event.PointerEvent) void {
                if (!ev.isNull()) self.count += 1;
            }
            fn onChange(
                self: *@This(),
                ev: webapi.Event.MediaQueryListEvent,
            ) void {
                if (!ev.isNull()) self.count += 1;
            }
            fn onGeneric(self: *@This(), ev: webapi.Event) void {
                if (!ev.isNull()) self.count += 1;
            }
        };

        var ctx: ListenerCtx = .{};
        const h = Mock.allocHandle("mock_target");
        defer h.release();

        const win = dom.window();
        win.addEventListener("keydown", ListenerCtx, &ctx, ListenerCtx.onKey);
        win.addEventListenerOwned(
            "keydown",
            ListenerCtx,
            &ctx,
            ListenerCtx.onKey,
        );

        const doc = dom.document();
        doc.addEventListener("click", ListenerCtx, &ctx, ListenerCtx.onClick);

        const el = dom.Element.init(h);
        el.addEventListener("click", ListenerCtx, &ctx, ListenerCtx.onClick);
        el.addEventListenerOwned(
            "click",
            ListenerCtx,
            &ctx,
            ListenerCtx.onClick,
        );

        const mql = dom.MediaQueryList{ .handle = h };
        mql.addChangeListener(ListenerCtx, &ctx, ListenerCtx.onChange);
        mql.addEventListener(
            "change",
            ListenerCtx,
            &ctx,
            ListenerCtx.onChange,
        );

        const vv = dom.VisualViewport{ .handle = h };
        vv.addEventListener(
            "resize",
            ListenerCtx,
            &ctx,
            ListenerCtx.onGeneric,
        );
        vv.addEventListenerOwned(
            "resize",
            ListenerCtx,
            &ctx,
            ListenerCtx.onGeneric,
        );

        const sw = dom.ServiceWorker{ .handle = h };
        sw.addEventListener(
            "statechange",
            ListenerCtx,
            &ctx,
            ListenerCtx.onGeneric,
        );

        const swc = dom.ServiceWorkerContainer{ .handle = h };
        swc.addEventListener(
            "controllerchange",
            ListenerCtx,
            &ctx,
            ListenerCtx.onGeneric,
        );

        const swr = dom.ServiceWorkerRegistration{ .handle = h };
        swr.addEventListener(
            "updatefound",
            ListenerCtx,
            &ctx,
            ListenerCtx.onGeneric,
        );
    }
    try Mock.assertNoHandleLeaks();
}

test "Crypto: window.crypto, getRandomValues, randomUUID, and SubtleCrypto lifecycle" {
    // Warm up the singleton TextEncoder/TextDecoder cache before resetMock so
    // handle-leak assertions only measure handles allocated during the test.
    const warmup = webapi.codec.encode(zjb.constString("").asHandle());
    warmup.release();

    zjb.resetMock();
    try zjb.assertNoHandleLeaks();
    {
        // Global & Window accessors
        const c_global = webapi.Crypto.global();
        try std.testing.expect(!c_global.isNull());

        try std.testing.expect(webapi.Crypto.isSupported());
        try std.testing.expect(webapi.Crypto.null.isNull());

        // getRandomValues (empty, small, and >65536 chunked)
        var empty: [0]u8 = .{};
        c_global.getRandomValues(&empty);

        var small: [32]u8 = undefined;
        c_global.getRandomValues(&small);

        var large: [70000]u8 = undefined;
        c_global.getRandomValues(&large);

        _ = c_global.random(u64);
        const rng = c_global.stdRandom();
        _ = rng.int(u32);

        // randomUUID (buffer & allocator)
        var uuid_buf: [64]u8 = undefined;
        const uuid_slice = c_global.randomUUID(&uuid_buf);
        _ = uuid_slice;

        const uuid_alloc = try c_global.randomUUIDAlloc(std.testing.allocator);
        defer std.testing.allocator.free(uuid_alloc);

        // SubtleCrypto, CryptoKey, CryptoKeyPair
        const subtle = c_global.subtle();
        defer subtle.release();
        try std.testing.expect(!subtle.isNull());

        const digest_p = subtle.digest(.@"SHA-256", "hello");
        digest_p.release();

        const alg = zjb.global("Object").new(.{});
        defer alg.release();

        const key = webapi.Crypto.CryptoKey.fromHandle(zjb.string("secret"));
        defer key.release();
        try std.testing.expectEqual(@as(?webapi.Crypto.KeyType, null), key.keyType());
        try std.testing.expectEqual(
            @as(?webapi.Crypto.KeyType, .secret),
            std.meta.stringToEnum(webapi.Crypto.KeyType, "secret"),
        );
        _ = key.extractable();
        const key_alg = key.algorithm();
        key_alg.release();
        const key_usages = key.usages();
        key_usages.release();

        const pair = webapi.Crypto.CryptoKeyPair.fromHandle(Mock.allocHandle("CryptoKeyPair"));
        defer pair.release();
        const pub_k = pair.publicKey();
        pub_k.release();
        const priv_k = pair.privateKey();
        priv_k.release();

        const enc_p = subtle.encrypt(alg, key, "plaintext");
        enc_p.release();
        const dec_p = subtle.decrypt(alg, key, "ciphertext");
        dec_p.release();
        const sign_p = subtle.sign(alg, key, "message");
        sign_p.release();
        const verify_p = subtle.verify(alg, key, "sig", "message");
        verify_p.release();
        const gen_p = subtle.generateKey(alg, true, &.{ .encrypt, .decrypt });
        gen_p.release();
        const derive_k_p = subtle.deriveKey(alg, key, alg, false, &.{.deriveKey});
        derive_k_p.promise.release();
        const derive_b_p = subtle.deriveBits(alg, key, 256);
        derive_b_p.release();
        const import_p = subtle.importRawKey(.raw, "raw-key-bytes", alg, true, &.{.encrypt});
        import_p.promise.release();
        const export_p = subtle.exportKey(.jwk, key);
        export_p.release();
        const wrap_p = subtle.wrapKey(.raw, key, key, alg);
        wrap_p.release();
        const unwrap_p = subtle.unwrapKey(.raw, "wrapped", key, alg, alg, true, &.{.decrypt});
        unwrap_p.promise.release();
    }
    try zjb.assertNoHandleLeaks();
}

test "webapi.WebRTC, WebSocket, and BroadcastChannel typed event wrappers" {
    const warmup = webapi.codec.encode(zjb.constString("").asHandle());
    warmup.release();

    Mock.reset();
    {
        const ev_ns = webapi.Event;
        try std.testing.expect(ev_ns.EventFor("message") == ev_ns.MessageEvent);
        try std.testing.expect(ev_ns.EventFor("messageerror") == ev_ns.MessageEvent);
        try std.testing.expect(ev_ns.EventFor("close") == ev_ns.CloseEvent);
        try std.testing.expect(
            ev_ns.EventFor("icecandidate") == ev_ns.RTCPeerConnectionIceEvent,
        );
        try std.testing.expect(
            ev_ns.EventFor("icecandidateerror") ==
                ev_ns.RTCPeerConnectionIceErrorEvent,
        );
        try std.testing.expect(
            ev_ns.EventFor("datachannel") == ev_ns.RTCDataChannelEvent,
        );
        try std.testing.expect(ev_ns.EventFor("open") == ev_ns);
        try std.testing.expect(ev_ns.EventFor("error") == ev_ns);

        const evt_h = Mock.allocHandle("mock_rtc_evt");
        defer evt_h.release();
        var buf: [32]u8 = undefined;

        const msg_ev = ev_ns.MessageEvent.fromHandle(evt_h);
        const data_h = msg_ev.data();
        data_h.release();
        _ = msg_ev.origin(&buf);
        _ = msg_ev.lastEventId(&buf);

        const close_ev = ev_ns.CloseEvent.fromHandle(evt_h);
        _ = close_ev.code();
        _ = close_ev.reason(&buf);
        _ = close_ev.wasClean();

        const dc_ev = ev_ns.RTCDataChannelEvent.fromHandle(evt_h);
        const ch = dc_ev.channel();
        ch.release();

        const ice_ev = ev_ns.RTCPeerConnectionIceEvent.fromHandle(evt_h);
        if (ice_ev.candidate()) |cand| {
            cand.release();
        }
        _ = ice_ev.url(&buf);

        const ice_err_ev = ev_ns.RTCPeerConnectionIceErrorEvent.fromHandle(evt_h);
        _ = ice_err_ev.address(&buf);
        _ = ice_err_ev.port();
        _ = ice_err_ev.url(&buf);
        _ = ice_err_ev.errorCode();
        _ = ice_err_ev.errorText(&buf);

        const ListenerCtx = struct {
            count: u32 = 0,

            fn onGeneric(self: *@This(), ev: ev_ns) void {
                if (!ev.isNull()) self.count += 1;
            }
            fn onMessage(self: *@This(), ev: ev_ns.MessageEvent) void {
                if (!ev.isNull()) self.count += 1;
            }
            fn onClose(self: *@This(), ev: ev_ns.CloseEvent) void {
                if (!ev.isNull()) self.count += 1;
            }
            fn onIce(self: *@This(), ev: ev_ns.RTCPeerConnectionIceEvent) void {
                if (!ev.isNull()) self.count += 1;
            }
            fn onIceErr(
                self: *@This(),
                ev: ev_ns.RTCPeerConnectionIceErrorEvent,
            ) void {
                if (!ev.isNull()) self.count += 1;
            }
            fn onDc(self: *@This(), ev: ev_ns.RTCDataChannelEvent) void {
                if (!ev.isNull()) self.count += 1;
            }
        };

        var ctx: ListenerCtx = .{};
        const target_h = Mock.allocHandle("mock_rtc_target");
        defer target_h.release();

        const pc = webapi.WebRTC.RTCPeerConnection{ .handle = target_h };
        pc.addEventListener("icecandidate", ListenerCtx, &ctx, ListenerCtx.onIce);
        pc.addEventListener(
            "icecandidateerror",
            ListenerCtx,
            &ctx,
            ListenerCtx.onIceErr,
        );
        pc.addEventListener("datachannel", ListenerCtx, &ctx, ListenerCtx.onDc);
        pc.addEventListener(
            "connectionstatechange",
            ListenerCtx,
            &ctx,
            ListenerCtx.onGeneric,
        );
        pc.addEventListenerOwned(
            "icecandidate",
            ListenerCtx,
            &ctx,
            ListenerCtx.onIce,
        );

        const dc = webapi.WebRTC.RTCDataChannel{ .handle = target_h };
        dc.addEventListener("open", ListenerCtx, &ctx, ListenerCtx.onGeneric);
        dc.addEventListener("message", ListenerCtx, &ctx, ListenerCtx.onMessage);
        dc.addEventListener("close", ListenerCtx, &ctx, ListenerCtx.onClose);
        dc.addEventListenerOwned(
            "message",
            ListenerCtx,
            &ctx,
            ListenerCtx.onMessage,
        );

        const ws = webapi.WebSocket{ .handle = target_h };
        ws.addEventListener("open", ListenerCtx, &ctx, ListenerCtx.onGeneric);
        ws.addEventListener("message", ListenerCtx, &ctx, ListenerCtx.onMessage);
        ws.addEventListener("close", ListenerCtx, &ctx, ListenerCtx.onClose);
        ws.addEventListenerOwned("close", ListenerCtx, &ctx, ListenerCtx.onClose);

        const bc = webapi.BroadcastChannel{ .handle = target_h };
        bc.addEventListener("message", ListenerCtx, &ctx, ListenerCtx.onMessage);
        bc.addEventListenerOwned(
            "message",
            ListenerCtx,
            &ctx,
            ListenerCtx.onMessage,
        );

        const SdpCtx = struct {
            sdp_calls: u32 = 0,
            void_calls: u32 = 0,
            err_calls: u32 = 0,

            fn onSdp(
                self: *@This(),
                desc: webapi.WebRTC.RTCSessionDescription,
            ) void {
                if (!desc.isNull()) self.sdp_calls += 1;
            }
            fn onApplied(self: *@This()) void {
                self.void_calls += 1;
            }
            fn onErr(self: *@This(), _: zjb.Handle) void {
                self.err_calls += 1;
            }
        };

        var sdp_ctx: SdpCtx = .{};
        const desc = webapi.WebRTC.RTCSessionDescription.create(
            "offer",
            "v=0",
        );
        defer desc.release();
        pc.createOffer(SdpCtx, &sdp_ctx, &SdpCtx.onSdp, &SdpCtx.onErr);
        pc.createAnswer(SdpCtx, &sdp_ctx, &SdpCtx.onSdp, null);
        pc.setLocalDescription(
            desc,
            SdpCtx,
            &sdp_ctx,
            &SdpCtx.onApplied,
            null,
        );
        pc.setRemoteDescription(desc, SdpCtx, &sdp_ctx, null, null);
    }
    try Mock.assertNoHandleLeaks();
}

test "dom.Window.launchQueue, LaunchQueue.setConsumer, and LaunchParams" {
    const warmup = webapi.codec.encode(zjb.constString("").asHandle());
    warmup.release();

    Mock.reset();
    {
        try std.testing.expect(dom.LaunchQueue.null.isNull());
        try std.testing.expect(dom.LaunchParams.null.isNull());

        const LaunchCtx = struct {
            calls: u32 = 0,
            fn onLaunch(self: *@This(), params: dom.LaunchParams) void {
                if (!params.isNull()) self.calls += 1;
            }
        };

        var ctx: LaunchCtx = .{};
        if (dom.window().launchQueue()) |lq| {
            defer lq.release();
            try std.testing.expect(!lq.isNull());
            lq.setConsumer(LaunchCtx, &ctx, &LaunchCtx.onLaunch);
        }

        const params_h = Mock.allocHandle("mock_launch_params");
        const params = dom.LaunchParams.fromHandle(params_h);
        defer params.release();
        try std.testing.expect(!params.isNull());

        var url_buf: [64]u8 = undefined;
        _ = params.targetURL(&url_buf);

        if (try params.targetURLAlloc(std.testing.allocator)) |allocated| {
            std.testing.allocator.free(allocated);
        }

        const files_h = params.files();
        files_h.release();
    }
    try Mock.assertNoHandleLeaks();
}

test "dom.Navigator.getInstalledRelatedApps and RelatedApplication" {
    const warmup = webapi.codec.encode(zjb.constString("").asHandle());
    warmup.release();

    Mock.reset();
    {
        try std.testing.expect(dom.RelatedApplication.null.isNull());

        const AppsCtx = struct {
            checked: bool = false,
            fn onApps(self: *@This(), apps: dom.RelatedApplication.List) void {
                if (!apps.isNull() and apps.len() == 0) {
                    self.checked = true;
                }
            }
        };

        var ctx: AppsCtx = .{};
        const nav = dom.window().navigator();
        defer nav.release();
        if (nav.getInstalledRelatedApps()) |p| {
            defer p.release();
            try std.testing.expect(!p.isNull());
            p.thenFn(AppsCtx, &ctx, &AppsCtx.onApps, null);
        }

        const list_h = Mock.allocHandle("mock_related_apps");
        var list: dom.RelatedApplication.List = .{ .handle = list_h };
        defer list.release();
        try std.testing.expect(!list.isNull());
        try std.testing.expectEqual(@as(usize, 0), list.len());
        try std.testing.expect(list.get(0) == null);
        try std.testing.expect(list.next() == null);

        const app_h = Mock.allocHandle("mock_related_app");
        const app = dom.RelatedApplication.fromHandle(app_h);
        defer app.release();
        try std.testing.expect(!app.isNull());
        var buf: [64]u8 = undefined;
        _ = app.platform(&buf);
        _ = app.id(&buf);
        _ = app.url(&buf);
        _ = app.version(&buf);
    }
    try Mock.assertNoHandleLeaks();
}
