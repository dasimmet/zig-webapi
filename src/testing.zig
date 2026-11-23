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
        const el = dom.Element.fromHandle(el_h);
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
            fn onOther(self: *@This(), h: zjb.Handle) void {
                _ = h;
                self.count += 2;
            }
        };
        const EmptyCtx = struct {
            fn onEmpty(_: *@This(), _: zjb.Handle) void {}
        };

        var state: State = .{};
        var state2: State = .{};
        var empty: EmptyCtx = .{};
        const target = Mock.allocHandle("mock_target");
        defer target.release();

        const callback = @import("callback.zig");
        const m1 = callback.memoizeCallback(State, false, &State.onCall);
        const m2 = callback.memoizeCallback(State, false, &State.onCall);
        const m_other = callback.memoizeCallback(State, false, &State.onOther);
        const m_owned = callback.memoizeCallback(State, true, &State.onCall);
        const m_empty = callback.memoizeCallback(
            EmptyCtx,
            false,
            &EmptyCtx.onEmpty,
        );
        try std.testing.expect(!m1.isNull());
        try std.testing.expectEqual(m1, m2);
        try std.testing.expect(m1 != m_other);
        try std.testing.expect(m1 != m_owned);
        try std.testing.expect(m1 != m_empty);
        try std.testing.expectEqual(@as(u32, 1), Mock.unreleased_count);

        const f1 = webapi.boundFunction(State, &state, &State.onCall);
        defer f1.release();
        const f1b = webapi.boundFunction(State, &state2, &State.onCall);
        defer f1b.release();
        try std.testing.expect(@backingInt(f1) != @backingInt(f1b));

        const f2 = webapi.boundFunctionOwned(State, &state, &State.onCall);
        defer f2.release();
        const f3 = webapi.boundFunction(EmptyCtx, &empty, &EmptyCtx.onEmpty);
        defer f3.release();

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

        const el = dom.Element.fromHandle(h);
        el.addEventListener("click", ListenerCtx, &ctx, ListenerCtx.onClick);
        el.addEventListenerOwned(
            "click",
            ListenerCtx,
            &ctx,
            ListenerCtx.onClick,
        );

        const mql = dom.MediaQueryList.fromHandle(h);
        mql.addChangeListener(ListenerCtx, &ctx, ListenerCtx.onChange);
        mql.addEventListener(
            "change",
            ListenerCtx,
            &ctx,
            ListenerCtx.onChange,
        );

        const vv = dom.VisualViewport.fromHandle(h);
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

        const sw = dom.ServiceWorker.fromHandle(h);
        sw.addEventListener(
            "statechange",
            ListenerCtx,
            &ctx,
            ListenerCtx.onGeneric,
        );

        const swc = dom.ServiceWorkerContainer.fromHandle(h);
        swc.addEventListener(
            "controllerchange",
            ListenerCtx,
            &ctx,
            ListenerCtx.onGeneric,
        );

        const swr = dom.ServiceWorkerRegistration.fromHandle(h);
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

        const pc = webapi.WebRTC.RTCPeerConnection.fromHandle(target_h);
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

        const dc = webapi.WebRTC.RTCDataChannel.fromHandle(target_h);
        dc.addEventListener("open", ListenerCtx, &ctx, ListenerCtx.onGeneric);
        dc.addEventListener("message", ListenerCtx, &ctx, ListenerCtx.onMessage);
        dc.addEventListener("close", ListenerCtx, &ctx, ListenerCtx.onClose);
        dc.addEventListenerOwned(
            "message",
            ListenerCtx,
            &ctx,
            ListenerCtx.onMessage,
        );

        const ws = webapi.WebSocket.fromHandle(target_h);
        ws.addEventListener("open", ListenerCtx, &ctx, ListenerCtx.onGeneric);
        ws.addEventListener("message", ListenerCtx, &ctx, ListenerCtx.onMessage);
        ws.addEventListener("close", ListenerCtx, &ctx, ListenerCtx.onClose);
        ws.addEventListenerOwned("close", ListenerCtx, &ctx, ListenerCtx.onClose);

        const bc = webapi.BroadcastChannel.fromHandle(target_h);
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
        var list = dom.RelatedApplication.List.fromHandle(list_h);
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

test "webapi.Worker, SharedWorker, MessageChannel, and Worker global scopes" {
    const warmup = webapi.codec.encode(zjb.constString("").asHandle());
    warmup.release();

    Mock.reset();
    {
        const Worker = webapi.Worker;
        const SharedWorker = Worker.SharedWorker;
        const MessageChannel = Worker.MessageChannel;
        const MessagePort = Worker.MessagePort;
        const DedicatedScope = Worker.DedicatedWorkerGlobalScope;
        const SharedScope = Worker.SharedWorkerGlobalScope;

        try std.testing.expect(Worker.null.isNull());
        try std.testing.expect(SharedWorker.null.isNull());
        try std.testing.expect(MessageChannel.null.isNull());
        try std.testing.expect(MessagePort.null.isNull());
        try std.testing.expect(DedicatedScope.null.isNull());
        try std.testing.expect(SharedScope.null.isNull());
        try std.testing.expect(Worker.WorkerLocation.null.isNull());
        try std.testing.expect(Worker.WorkerNavigator.null.isNull());

        try std.testing.expect(Worker.isSupported());
        try std.testing.expect(SharedWorker.isSupported());
        try std.testing.expect(MessageChannel.isSupported());

        const Ctx = struct {
            messages: u32 = 0,
            errors: u32 = 0,
            connects: u32 = 0,

            fn onMessage(self: *@This(), ev: webapi.Event.MessageEvent) void {
                const d = ev.data();
                d.release();
                const s = ev.source();
                s.release();
                if (ev.portAt(0)) |p| p.release();
                self.messages += 1;
            }

            fn onError(self: *@This(), ev: webapi.Event.ErrorEvent) void {
                var buf: [64]u8 = undefined;
                _ = ev.message(&buf);
                _ = ev.filename(&buf);
                _ = ev.lineno();
                _ = ev.colno();
                const err_v = ev.errorValue();
                err_v.release();
                self.errors += 1;
            }

            fn onConnect(self: *@This(), ev: webapi.Event.MessageEvent) void {
                if (ev.portAt(0)) |p| {
                    defer p.release();
                    p.start();
                }
                self.connects += 1;
            }
        };
        var ctx: Ctx = .{};

        const w = Worker.init("worker.js", .{
            .type = .module,
            .credentials = .@"same-origin",
            .name = "calc",
        });
        defer w.release();
        try std.testing.expect(!w.isNull());
        w.addEventListener("message", Ctx, &ctx, &Ctx.onMessage);
        w.addEventListener("error", Ctx, &ctx, &Ctx.onError);
        w.postText("hello worker");
        w.postBytes(&.{ 1, 2, 3, 4 });
        w.terminate();

        const w_plain = Worker.init("classic.js", null);
        defer w_plain.release();
        try std.testing.expect(!w_plain.isNull());

        const sw = SharedWorker.init("shared.js", .{
            .type = .module,
            .name = "shared-bus",
        });
        defer sw.release();
        try std.testing.expect(!sw.isNull());
        sw.addEventListener("error", Ctx, &ctx, &Ctx.onError);
        const sw_port = sw.port();
        defer sw_port.release();
        sw_port.start();
        sw_port.addEventListener("message", Ctx, &ctx, &Ctx.onMessage);
        sw_port.postText("ping");
        sw_port.postBytes("raw");
        sw_port.close();

        const ch = MessageChannel.init();
        defer ch.release();
        const p1 = ch.port1();
        defer p1.release();
        const p2 = ch.port2();
        defer p2.release();
        p1.start();
        p2.start();
        p1.postText("via channel");
        p1.close();
        p2.close();

        const d_scope = DedicatedScope.global();
        try std.testing.expect(!d_scope.isNull());
        var buf: [64]u8 = undefined;
        _ = d_scope.name(&buf);
        const w_loc = d_scope.location();
        defer w_loc.release();
        _ = w_loc.getHref(&buf);
        _ = w_loc.getOrigin(&buf);
        _ = w_loc.getProtocol(&buf);
        _ = w_loc.getHost(&buf);
        _ = w_loc.getHostname(&buf);
        _ = w_loc.getPort(&buf);
        _ = w_loc.getPathname(&buf);
        _ = w_loc.getSearch(&buf);
        _ = w_loc.getHash(&buf);

        const w_nav = d_scope.navigator();
        defer w_nav.release();
        _ = w_nav.hardwareConcurrency();
        _ = w_nav.onLine();
        _ = w_nav.userAgent(&buf);
        _ = w_nav.language(&buf);
        _ = w_nav.platform(&buf);
        const storage_h = w_nav.storage();
        storage_h.release();
        const locks_h = w_nav.locks();
        locks_h.release();

        d_scope.addEventListener("message", Ctx, &ctx, &Ctx.onMessage);
        d_scope.postText("reply");
        d_scope.postBytes("bytes");
        d_scope.importScripts(&.{ "a.js", "b.js" });
        d_scope.close();

        const s_scope = SharedScope.global();
        try std.testing.expect(!s_scope.isNull());
        _ = s_scope.name(&buf);
        s_scope.addEventListener("connect", Ctx, &ctx, &Ctx.onConnect);
        s_scope.close();

        const err_h = Mock.allocHandle("mock_error_event");
        const err_ev = webapi.Event.ErrorEvent.fromHandle(err_h);
        defer err_ev.release();
        ctx.onError(err_ev);
        try std.testing.expectEqual(@as(u32, 1), ctx.errors);
    }
    try Mock.assertNoHandleLeaks();
}

test "webapi.Blob and webapi.URL wrappers release handles without leaks" {
    const warmup = webapi.codec.encode(zjb.constString("").asHandle());
    warmup.release();

    Mock.reset();
    {
        const Blob = webapi.Blob;
        const URL = webapi.URL;

        try std.testing.expect(Blob.null.isNull());
        try std.testing.expect(URL.null.isNull());
        try std.testing.expect(URL.SearchParams.null.isNull());
        try std.testing.expect(Blob.isSupported());
        try std.testing.expect(URL.isSupported());

        const b1 = Blob.fromBytes("hello", .{
            .type = "text/plain",
            .endings = .transparent,
        });
        defer b1.release();
        try std.testing.expect(!b1.isNull());
        _ = b1.size();
        var buf: [64]u8 = undefined;
        _ = b1.mimeType(&buf);

        const b2 = Blob.fromText("world", null);
        defer b2.release();
        const b_slice = b2.slice(0, 3, "text/plain");
        defer b_slice.release();
        const b_slice2 = b2.slice(1, null, null);
        defer b_slice2.release();

        const p_text = b1.text();
        p_text.release();
        const p_ab = b1.arrayBuffer();
        p_ab.release();
        const p_bytes = b1.bytes();
        p_bytes.release();
        const stream_h = b1.stream();
        stream_h.release();

        const obj_url = URL.createObjectURL(b1);
        URL.revokeObjectURL(obj_url);
        obj_url.release();
        URL.revokeObjectURL("blob:https://example.com/123");

        const u = URL.init("/path?a=1#frag", "https://example.com");
        defer u.release();
        try std.testing.expect(!u.isNull());
        _ = URL.canParse("https://example.com", null);
        if (URL.parse("https://example.com/x", null)) |parsed| {
            parsed.release();
        }
        _ = u.getHref(&buf);
        u.setHref("https://example.com/y");
        _ = u.getOrigin(&buf);
        _ = u.getProtocol(&buf);
        u.setProtocol("https:");
        _ = u.getUsername(&buf);
        u.setUsername("user");
        _ = u.getPassword(&buf);
        u.setPassword("pass");
        _ = u.getHost(&buf);
        u.setHost("example.com");
        _ = u.getHostname(&buf);
        u.setHostname("example.com");
        _ = u.getPort(&buf);
        u.setPort("443");
        _ = u.getPathname(&buf);
        u.setPathname("/z");
        _ = u.getSearch(&buf);
        u.setSearch("?k=v");
        _ = u.getHash(&buf);
        u.setHash("#top");
        _ = u.toString(&buf);
        _ = u.toJSON(&buf);

        const sp = u.searchParams();
        defer sp.release();
        _ = sp.size();
        sp.append("x", "1");
        sp.set("y", "2");
        _ = sp.has("x");
        if (sp.get("x", &buf)) |_| {}
        sp.sort();
        sp.delete("x");
        _ = sp.toString(&buf);

        const sp2 = URL.SearchParams.init("a=1&b=2");
        defer sp2.release();

        const resp = webapi.Fetch.Response.fromHandle(
            Mock.allocHandle("mock_resp"),
        );
        defer resp.release();
        const blob_p = resp.blob();
        blob_p.release();
    }
    try Mock.assertNoHandleLeaks();
}

test "webapi.Wasi fdStatSetFlags updates open descriptor flags" {
    const allocator = std.testing.allocator;
    const wasi = try webapi.Wasi.init(.{
        .allocator = allocator,
        .args = &.{"wasm-opt"},
        .preopens = &.{.{ .dir = "." }},
    });
    defer wasi.deinit();

    try std.testing.expectEqual(@as(i32, 0), wasi.fdStatSetFlags(0, 1));
    try std.testing.expectEqual(@as(i32, 0), wasi.fdStatSetFlags(3, 1));
    try std.testing.expectEqual(@as(i32, 8), wasi.fdStatSetFlags(999, 1));

    const open_fd: i32 = 10;
    const path = try allocator.dupe(u8, "/out.wasm");
    try wasi.fs.fds.put(open_fd, .{
        .path = path,
        .is_dir = false,
        .flags = 0,
    });

    try std.testing.expectEqual(
        @as(i32, 0),
        wasi.fdStatSetFlags(open_fd, 0x0001),
    );
    try std.testing.expectEqual(
        @as(i32, 0x0001),
        wasi.fs.fds.get(open_fd).?.flags,
    );
}

test "webapi.WebAudio wrappers release handles without leaks" {
    const warmup = webapi.codec.encode(zjb.constString("").asHandle());
    warmup.release();

    Mock.reset();
    {
        const WebAudio = webapi.WebAudio;
        const AudioContext = WebAudio.AudioContext;

        try std.testing.expect(AudioContext.null.isNull());
        try std.testing.expect(WebAudio.AudioDestinationNode.null.isNull());
        try std.testing.expect(WebAudio.AudioBuffer.null.isNull());
        try std.testing.expect(WebAudio.AudioBufferSourceNode.null.isNull());
        try std.testing.expect(AudioContext.isSupported());

        const ctx = AudioContext.init();
        defer ctx.release();
        try std.testing.expect(!ctx.isNull());
        _ = ctx.state();
        _ = ctx.sampleRate();

        const dest = ctx.destination();
        defer dest.release();
        try std.testing.expect(!dest.isNull());

        const Ctx = struct {
            ended: u32 = 0,
            fn onEnded(self: *@This(), ev: webapi.Event) void {
                _ = ev;
                self.ended += 1;
            }
        };
        var handler_ctx: Ctx = .{};

        const audio_buf = ctx.createBuffer(1, 256, 48000.0);
        defer audio_buf.release();
        _ = audio_buf.sampleRate();
        _ = audio_buf.duration();
        _ = audio_buf.numberOfChannels();
        const pcm: [256]f32 = @splat(0.25);
        audio_buf.copyToChannel(&pcm, 0, 0);

        const buf_src = ctx.createBufferSource();
        defer buf_src.release();
        buf_src.setBuffer(audio_buf);
        buf_src.connect(dest);
        buf_src.addEventListener("ended", Ctx, &handler_ctx, Ctx.onEnded);
        buf_src.start();

        const raw_ab = Mock.allocHandle("mock_array_buffer");
        defer raw_ab.release();
        const dec_p = ctx.decodeAudioData(raw_ab);
        dec_p.release();

        const res_p = ctx.@"resume"();
        res_p.release();
    }
    try Mock.assertNoHandleLeaks();
}

test "webapi.Image wrapper releases handles without leaks" {
    const warmup = webapi.codec.encode(zjb.constString("").asHandle());
    warmup.release();

    Mock.reset();
    {
        const Image = webapi.Image;
        try std.testing.expect(Image.null.isNull());
        try std.testing.expect(Image.isSupported());

        const img = Image.init();
        defer img.release();
        try std.testing.expect(!img.isNull());

        img.setSrc("dice.svg");
        const url_h = Mock.allocHandle("mock_blob_url");
        defer url_h.release();
        img.setSrc(url_h);

        var buf: [64]u8 = undefined;
        _ = img.getSrc(&buf);
        img.setAlt("dice");
        _ = img.alt(&buf);
        img.setWidth(256);
        img.setHeight(256);
        _ = img.width();
        _ = img.height();
        _ = img.naturalWidth();
        _ = img.naturalHeight();
        _ = img.complete();
        img.setCrossOrigin(.anonymous);
        img.setCrossOrigin(null);
        img.setDecoding(.async);

        const Ctx = struct {
            loaded: u32 = 0,
            fn onLoad(self: *@This(), ev: webapi.Event) void {
                _ = ev;
                self.loaded += 1;
            }
        };
        var ctx: Ctx = .{};
        img.addEventListener("load", Ctx, &ctx, Ctx.onLoad);

        const dec_p = img.decode();
        dec_p.release();

        const sized = Image.initWithSize(64, 64);
        sized.release();
    }
    try Mock.assertNoHandleLeaks();
}

test "webapi.CanvasRenderingContext2D releases handles without leaks" {
    const warmup = webapi.codec.encode(zjb.constString("").asHandle());
    warmup.release();

    Mock.reset();
    {
        const Canvas2D = webapi.CanvasRenderingContext2D;
        try std.testing.expect(Canvas2D.null.isNull());

        const canvas = webapi.dom.document().createElement("canvas");
        defer canvas.release();

        const ctx = try Canvas2D.fromCanvas(canvas);
        defer ctx.release();
        try std.testing.expect(!ctx.isNull());

        const img = webapi.Image.init();
        defer img.release();

        ctx.drawImage(img, 0.0, 0.0);
        ctx.drawImageScaled(img, 0.0, 0.0, 64.0, 64.0);
        ctx.drawImageRect(img, 0.0, 0.0, 32.0, 32.0, 0.0, 0.0, 64.0, 64.0);
        ctx.clearRect(0.0, 0.0, 64.0, 64.0);
        ctx.fillRect(4.0, 4.0, 56.0, 56.0);
        ctx.strokeRect(4.0, 4.0, 56.0, 56.0);
        ctx.save();
        ctx.setFillStyle("#ffffff");
        ctx.setStrokeStyle("#f7a41d");
        ctx.setLineWidth(2.0);
        ctx.setFont("bold 24px sans-serif");
        var font_buf: [64]u8 = undefined;
        _ = ctx.getFont(&font_buf);
        ctx.setTextAlign(.center);
        ctx.setTextBaseline(.middle);
        ctx.setDirection(.ltr);
        ctx.fillText("zig-webapi", 32.0, 32.0);
        ctx.fillTextMaxWidth("zig-webapi", 32.0, 32.0, 60.0);
        ctx.strokeText("zig-webapi", 32.0, 32.0);
        ctx.strokeTextMaxWidth("zig-webapi", 32.0, 32.0, 60.0);
        const metrics = ctx.measureText("zig-webapi");
        defer metrics.release();
        try std.testing.expect(!metrics.isNull());
        try std.testing.expect(Canvas2D.TextMetrics.null.isNull());
        _ = metrics.width();
        _ = metrics.actualBoundingBoxLeft();
        _ = metrics.actualBoundingBoxRight();
        _ = metrics.actualBoundingBoxAscent();
        _ = metrics.actualBoundingBoxDescent();
        ctx.restore();
    }
    try Mock.assertNoHandleLeaks();
}

test "webapi.dom.parseDomString returns a Document without handle leaks" {
    Mock.reset();
    {
        const doc: webapi.dom.Document =
            webapi.dom.parseDomString("<svg/>", "image/svg+xml");
        defer doc.release();
        try std.testing.expect(!doc.isNull());
    }
    try Mock.assertNoHandleLeaks();
}

test "webapi.dom.getComputedStyle releases handles without leaks" {
    const warmup = webapi.codec.encode(zjb.constString("").asHandle());
    warmup.release();

    Mock.reset();
    {
        const doc = webapi.dom.document();
        const win = webapi.dom.window();
        const elem = doc.createElement("div");
        defer elem.release();

        const doc_style = doc.getComputedStyle(elem, null);
        defer doc_style.release();
        try std.testing.expect(!doc_style.isNull());

        const win_style = win.getComputedStyle(elem, "::before");
        defer win_style.release();
        try std.testing.expect(!win_style.isNull());

        var buf: [64]u8 = undefined;
        _ = doc_style.getPropertyValue("color", &buf);
        const owned = try win_style.getPropertyValueAlloc(
            std.testing.allocator,
            "display",
        );
        std.testing.allocator.free(owned);
    }
    try Mock.assertNoHandleLeaks();
}

test "webapi.Date lifecycle and methods without handle leaks" {
    const warmup = webapi.codec.encode(zjb.constString("").asHandle());
    warmup.release();

    Mock.reset();
    {
        const Date = webapi.Date;
        try std.testing.expect(Date.null.isNull());
        try std.testing.expect(Date.isSupported());

        const d1 = Date.init();
        defer d1.release();
        try std.testing.expect(!d1.isNull());

        const d2 = Date.initFromTimestamp(1_700_000_000_000.0);
        defer d2.release();
        const d3 = Date.initFromString("2026-11-20T12:00:00Z");
        defer d3.release();
        const d4 = Date.initFromParts(.{ .year = 2026, .month_index = 10 });
        defer d4.release();

        _ = Date.now();
        _ = Date.parse("2026-11-20T12:00:00Z");
        _ = Date.utc(.{ .year = 2026, .month_index = 10, .day = 20 });

        d1.setTime(1_700_000_000_000.0);
        _ = d1.getTime();
        _ = d1.getTimezoneOffset();

        d1.setFullYear(2026);
        _ = d1.getFullYear();
        d1.setMonth(10);
        _ = d1.getMonth();
        d1.setDate(20);
        _ = d1.getDate();
        _ = d1.getDay();
        d1.setHours(15);
        _ = d1.getHours();
        d1.setMinutes(30);
        _ = d1.getMinutes();
        d1.setSeconds(45);
        _ = d1.getSeconds();
        d1.setMilliseconds(500);
        _ = d1.getMilliseconds();

        d1.setUTCFullYear(2026);
        _ = d1.getUTCFullYear();
        d1.setUTCMonth(10);
        _ = d1.getUTCMonth();
        d1.setUTCDate(20);
        _ = d1.getUTCDate();
        _ = d1.getUTCDay();
        d1.setUTCHours(14);
        _ = d1.getUTCHours();
        d1.setUTCMinutes(30);
        _ = d1.getUTCMinutes();
        d1.setUTCSeconds(45);
        _ = d1.getUTCSeconds();
        d1.setUTCMilliseconds(500);
        _ = d1.getUTCMilliseconds();

        var buf: [128]u8 = undefined;
        _ = d1.toISOString(&buf);
        _ = d1.toUTCString(&buf);
        _ = d1.toDateString(&buf);
        _ = d1.toTimeString(&buf);
        _ = d1.toString(&buf);
        _ = d1.toLocaleString(null, &buf);
        _ = d1.toLocaleDateString("en-US", &buf);
        _ = d1.toLocaleTimeString(null, &buf);
        _ = d1.toJSON(&buf);

        const iso = try d1.toISOStringAlloc(std.testing.allocator);
        std.testing.allocator.free(iso);
        const full = try d1.toStringAlloc(std.testing.allocator);
        std.testing.allocator.free(full);
    }
    try Mock.assertNoHandleLeaks();
}

test "webapi.WebDAV URL, paths, PROPFIND parsing, and Fetch dispatch" {
    const alloc = std.testing.allocator;
    const WebDAV = webapi.WebDAV;

    const dav_root = "https://dav.example.com/dav/";
    const item_url = try WebDAV.buildDavItemUrl(
        alloc,
        dav_root,
        "Sync/Noten/backup 1.html",
    );
    defer alloc.free(item_url);
    try std.testing.expectEqualStrings(
        "https://dav.example.com/dav/Sync/Noten/backup%201.html",
        item_url,
    );

    const norm_dir = try WebDAV.normalizeRelativePath(
        alloc,
        "/Sync/.././Noten/",
        true,
    );
    defer alloc.free(norm_dir);
    try std.testing.expectEqualStrings("Sync/Noten/", norm_dir);
    try std.testing.expectEqualStrings("Sync/", WebDAV.parentDirPath(norm_dir));
    try std.testing.expectEqualStrings(
        "backup.html",
        WebDAV.basenameOfPath("Sync/backup.html"),
    );

    const joined = try WebDAV.joinDirAndFile(
        alloc,
        "Sync/",
        "notes",
        ".html",
    );
    defer alloc.free(joined);
    try std.testing.expectEqualStrings("Sync/notes.html", joined);

    const parent_dir = try WebDAV.dirnameOfFilePath(alloc, joined);
    defer alloc.free(parent_dir);
    try std.testing.expectEqualStrings("Sync/", parent_dir);

    var dir_entry = (try WebDAV.buildValidatedDavEntry(
        alloc,
        "/dav/Sync/html/",
        "Sync/",
        true,
        null,
        .{ .dav_root = dav_root },
    )).?;
    defer dir_entry.deinit(alloc);
    try std.testing.expect(dir_entry.is_dir);
    try std.testing.expectEqualStrings("Sync/html/", dir_entry.rel_path);

    var generic_entry = (try WebDAV.buildValidatedDavEntry(
        alloc,
        "/custom/dav/docs/notes.txt",
        "docs/",
        false,
        42,
        .{ .dav_root = "https://dav.example.com/custom/dav/" },
    )).?;
    defer generic_entry.deinit(alloc);
    try std.testing.expect(!generic_entry.is_dir);
    try std.testing.expectEqualStrings("docs/notes.txt", generic_entry.rel_path);
    try std.testing.expect((try WebDAV.buildValidatedDavEntry(
        alloc,
        "/custom/dav/docs/notes.txt",
        "docs/",
        false,
        42,
        .{
            .dav_root = "https://dav.example.com/custom/dav/",
            .allowed_extensions = &.{".html"},
        },
    )) == null);

    var auth_buf: [std.http.Client.basic_authorization.max_value_len]u8 =
        undefined;
    const auth_hdr = std.http.Client.basic_authorization.value(.{
        .scheme = "https",
        .user = .{ .raw = "alice" },
        .password = .{ .raw = "secret" },
    }, &auth_buf);

    Mock.reset();
    {
        const dav = WebDAV.init(.{
            .dav_root = dav_root,
            .auth_header = auth_hdr,
        });

        const sample_xml =
            \\<?xml version="1.0"?>
            \\<d:multistatus xmlns:d="DAV:">
            \\  <d:response>
            \\    <d:href>/dav/Sync/</d:href>
            \\  </d:response>
            \\</d:multistatus>
        ;
        const parsed_entries = try WebDAV.parsePropfindXml(
            alloc,
            sample_xml,
            "Sync/",
            .{ .dav_root = dav_root },
        );
        defer {
            for (parsed_entries) |*e| e.deinit(alloc);
            alloc.free(parsed_entries);
        }

        var cors_buf: [512]u8 = undefined;
        const cors_msg = WebDAV.formatCorsError(
            &cors_buf,
            "listing",
            "PROPFIND",
            dav_root,
            null,
        );
        try std.testing.expect(cors_msg.len > 0);

        const Cb = struct {
            fn done(_: *@This(), _: WebDAV.Response) void {}
        };
        var cb: Cb = .{};
        // Promise.thenFn does not settle in mock; use arena for in-flight ctx
        var req_arena = std.heap.ArenaAllocator.init(alloc);
        defer req_arena.deinit();
        const ralloc = req_arena.allocator();
        try dav.propfind(ralloc, "", .@"1", Cb, &cb, Cb.done);
        try dav.getFile(ralloc, "Sync/backup.html", Cb, &cb, Cb.done);
        try dav.putFile(
            ralloc,
            "Sync/backup.html",
            "text/html",
            "<html/>",
            Cb,
            &cb,
            Cb.done,
        );
        try dav.mkcol(ralloc, "Sync/NewDir/", Cb, &cb, Cb.done);
        try dav.deleteItem(ralloc, "Sync/old.html", Cb, &cb, Cb.done);
    }
    // Reset mock handles left unreleased by unsettled mock Promises
    Mock.reset();
    try Mock.assertNoHandleLeaks();
}
