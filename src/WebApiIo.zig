//! Browser `std.Io` implementation backed by `Wasi.FileSystem` (IndexedDB
//! persistent mounts), the browser `Fetch` API for HTTP/HTTPS networking, and
//! JavaScript `Promise`s (with optional WebAssembly JSPI stack suspension) for
//! `async`/`await`, `Group`, `futex`, and `sleep`.
//!
//! Unused OS-specific operations forward to `std.Io.failing.vtable`.

// 1. Imports
const std = @import("std");
const builtin = @import("builtin");
const webapi = @import("webapi.zig");

// 2. Shortcuts on imports
const WebApiIo = @This();
const Io = std.Io;
const Dir = Io.Dir;
const File = Io.File;
const net = Io.net;
const failing = Io.failing.vtable;
const FileSystem = webapi.Wasi.FileSystem;
const Fetch = webapi.Fetch;
const Promise = webapi.Promise;
const zjb = webapi.zjb;

// 3. File-level struct members
gpa: std.mem.Allocator,
fs: FileSystem = undefined,
fs_initialized: bool = false,
sockets_initialized: bool = false,
cwd_buf: [MAX_PATH_BYTES]u8 = initRootCwd(),
cwd_len: u32 = 1,
db_name: ?[]const u8 = "webapi_fs",
store_name: []const u8 = "files",
base_origin: ?[]const u8 = null,
instance: webapi.WebAssembly.Instance = .null,
owns_instance: bool = false,
sockets: std.AutoHashMapUnmanaged(i32, *HttpSocket) = .empty,
hosts: std.ArrayList(HostMapping) = .empty,
prefetched: std.ArrayList(PrefetchedEntry) = .empty,
futex_waiters: std.ArrayList(*FutexWaiter) = .empty,
mount_waiters: std.ArrayList(zjb.Handle) = .empty,
next_socket_id: i32 = FIRST_DYNAMIC_FD,
next_host_index: u32 = 1,
virtual_clock_offset_ns: i96 = 0,
prng_counter: u64 = 0x9E37_79B9_7F4A_7C15,
cancel_pending: bool = false,
cancel_protection: Io.CancelProtection = .unblocked,
jspi_initialized: bool = false,
jspi_depth: u32 = 0,
jspi_suspend_slot: i32 = -1,
jspi_promising_entry: zjb.Handle = .null,
jspi_tail_promise: zjb.Handle = .null,
jspi_stack: ?[]align(16) u8 = null,
mock_fetch: ?MockFetchFn = null,
mock_fetch_ctx: ?*anyopaque = null,
void_dir_fds: [MAX_VOID_HANDLES]i32 = @splat(CWD_SENTINEL_FD),
void_dir_len: u32 = 0,
void_file_fds: [MAX_VOID_HANDLES]i32 = @splat(-1),
void_file_len: u32 = 0,
void_socket_ids: [MAX_VOID_HANDLES]i32 = @splat(-1),
void_socket_len: u32 = 0,
user_mount_cb: ?*const fn (ctx: *anyopaque, dir_path: []const u8) void = null,
user_mount_ctx: ?*anyopaque = null,

// 4. Options struct for init
/// Configuration options for initializing `WebApiIo` in-place.
pub const Options = struct {
    gpa: std.mem.Allocator,
    /// Initial virtual working directory (defaults to `"/"`).
    cwd_path: []const u8 = "/",
    /// Default IndexedDB database name mounted at `"/"` when `preopens` is
    /// empty. Set to `null` for an in-memory-only root filesystem.
    db_name: ?[]const u8 = "webapi_fs",
    /// Object store name used for the default IndexedDB mount.
    store_name: []const u8 = "files",
    /// Explicit preopens (`.indexed_fs`, `.tar`, or `.dir`). When non-empty,
    /// overrides the default single-database root mount.
    preopens: []const FileSystem.Preopen = &.{},
    /// Optional base origin URL (e.g. `"https://example.com"`) used to resolve
    /// requests targeting `"origin.local"` or relative paths.
    base_origin: ?[]const u8 = null,
    /// Optional WASM instance providing `exports` and
    /// `__indirect_function_table` for JSPI suspension (auto-detected from
    /// `window.zjb.instance` if `.null`).
    instance: webapi.WebAssembly.Instance = .null,
    /// Optional callback invoked when an IndexedDB mount finishes loading.
    on_mount_ready: ?*const fn (ctx: *anyopaque, dir_path: []const u8) void =
        null,
    on_mount_ready_ctx: ?*anyopaque = null,
};

// 5. init
/// Initializes `WebApiIo` in-place so asynchronous IndexedDB and Promise
/// callbacks hold a stable pointer to `self`.
pub fn init(self: *WebApiIo, options: Options) !void {
    std.debug.assert(@intFromPtr(self) != 0);
    std.debug.assert(@intFromPtr(options.gpa.vtable) != 0);

    self.* = .{
        .gpa = options.gpa,
        .db_name = options.db_name,
        .store_name = options.store_name,
        .base_origin = options.base_origin,
        .instance = if (!options.instance.isNull())
            webapi.WebAssembly.Instance.fromHandle(
                webapi.retainHandle(options.instance.handle),
            )
        else
            .null,
        .owns_instance = !options.instance.isNull(),
        .user_mount_cb = options.on_mount_ready,
        .user_mount_ctx = options.on_mount_ready_ctx,
    };
    errdefer self.deinit();

    var default_preopen: [1]FileSystem.Preopen = undefined;
    const preopens: []const FileSystem.Preopen = if (options.preopens.len > 0)
        options.preopens
    else if (options.db_name) |db| blk: {
        default_preopen[0] = .{
            .indexed_fs = .{
                .path = "/",
                .db_name = db,
                .store_name = options.store_name,
                .preload_path = "/",
            },
        };
        break :blk &default_preopen;
    } else &.{};

    try self.fs.init(.{
        .allocator = options.gpa,
        .preopens = preopens,
        .on_indexed_fs_mount_ready = onFsMountReady,
        .indexed_fs_mount_ready_ctx = @ptrCast(self),
    });
    self.fs.next_fd = FIRST_DYNAMIC_FD;
    self.fs_initialized = true;

    try self.setCwdInternal(options.cwd_path);
}

// 6. deinit
/// Releases all open files, IndexedDB mounts, virtual HTTP sockets, cached
/// responses, and JS handles owned by `self`.
pub fn deinit(self: *WebApiIo) void {
    std.debug.assert(@intFromPtr(self) != 0);
    std.debug.assert(@intFromPtr(self.gpa.vtable) != 0);

    for (self.mount_waiters.items) |resolve_h| {
        if (!resolve_h.isNull()) resolve_h.release();
    }
    self.mount_waiters.deinit(self.gpa);

    for (self.futex_waiters.items) |w| {
        w.deinit(self.gpa);
    }
    self.futex_waiters.deinit(self.gpa);

    for (self.prefetched.items) |*entry| {
        entry.deinit(self.gpa);
    }
    self.prefetched.deinit(self.gpa);

    for (self.hosts.items) |h| {
        self.gpa.free(h.name);
    }
    self.hosts.deinit(self.gpa);

    var sit = self.sockets.iterator();
    while (sit.next()) |kv| {
        kv.value_ptr.*.destroy(self.gpa);
    }
    self.sockets.deinit(self.gpa);

    if (!self.jspi_promising_entry.isNull()) {
        self.jspi_promising_entry.release();
        self.jspi_promising_entry = .null;
    }
    if (!self.jspi_tail_promise.isNull()) {
        self.jspi_tail_promise.release();
        self.jspi_tail_promise = .null;
    }
    if (self.jspi_stack) |stack| {
        self.gpa.free(stack);
        self.jspi_stack = null;
    }
    if (self.owns_instance) {
        self.instance.release();
        self.owns_instance = false;
    }

    if (self.fs_initialized) {
        self.fs.deinit();
        self.fs_initialized = false;
    }
}

// 7. Public functions
/// Returns the `std.Io` interface backed by `self`.
pub fn io(self: *WebApiIo) Io {
    std.debug.assert(@intFromPtr(self) != 0);
    std.debug.assert(@intFromPtr(self.gpa.vtable) != 0);
    return .{
        .userdata = @ptrCast(@alignCast(self)),
        .vtable = &vtable,
    };
}

/// Creates a `std.http.Client` configured to route both `http://` and
/// `https://` requests through the browser `Fetch` API via `self.io()`.
pub fn httpClient(
    self: *WebApiIo,
    allocator: std.mem.Allocator,
) std.http.Client {
    std.debug.assert(@intFromPtr(self) != 0);
    std.debug.assert(@intFromPtr(allocator.vtable) != 0);
    var client: std.http.Client = .{
        .allocator = allocator,
        .io = self.io(),
    };
    configureHttpClient(&client);
    return client;
}

/// Configures an existing `std.http.Client` so `https://` requests bypass
/// in-WASM TLS handshakes and delegate transport + TLS to browser `fetch()`.
pub fn configureHttpClient(client: *std.http.Client) void {
    std.debug.assert(@intFromPtr(client) != 0);
    std.debug.assert(@intFromPtr(client.allocator.vtable) != 0);
    client.http_proxy = @constCast(&fetch_proxy);
    client.https_proxy = @constCast(&fetch_proxy);
}

/// Returns `true` if WebAssembly JSPI (`Suspending` + `promising` + exported
/// `__indirect_function_table`) is available for live stack suspension.
pub fn isJspiSupported(self: *WebApiIo) bool {
    std.debug.assert(@intFromPtr(self) != 0);
    std.debug.assert(@intFromPtr(self.gpa.vtable) != 0);
    self.ensureJspiInitialized();
    return self.jspi_suspend_slot >= 0 and
        !self.jspi_promising_entry.isNull() and
        self.jspi_stack != null;
}

/// Returns a `Promise` that resolves once all configured IndexedDB mounts have
/// opened and completed their initial preload.
pub fn waitMountsReady(self: *WebApiIo) !Promise.Typed(void) {
    std.debug.assert(@intFromPtr(self) != 0);
    std.debug.assert(@intFromPtr(self.gpa.vtable) != 0);

    try self.ensureFsInitialized();
    if (self.fs.areAllIndexedFsMountsReady()) {
        return .fromHandle(Promise.resolve(zjb.Handle.null).handle);
    }

    const prom_cls = zjb.global("Promise");
    const exec_fn = zjb.fnHandle(
        "webapi_io_mount_wait_exec",
        &mountWaitExecutor,
    );
    const self_ptr: JsPtrInt = @bitCast(@intFromPtr(self));
    const bound = exec_fn.call(
        "bind",
        .{ zjb.Handle.null, self_ptr },
        zjb.Handle,
    );
    defer bound.release();

    const p = prom_cls.new(.{bound});
    std.debug.assert(!p.isNull());
    return .fromHandle(p);
}

/// Prefetches `url` via `webapi.fetch` into an in-memory one-shot cache entry
/// so environments without JSPI can serve `std.http.Client` synchronously.
pub fn prefetch(
    self: *WebApiIo,
    url: []const u8,
    req_init: ?Fetch.RequestInit,
) !Promise.Typed(void) {
    std.debug.assert(@intFromPtr(self) != 0);
    std.debug.assert(url.len > 0);

    const ctx = try self.gpa.create(PrefetchContext);
    errdefer self.gpa.destroy(ctx);
    const url_copy = try self.gpa.dupe(u8, url);
    errdefer self.gpa.free(url_copy);

    ctx.* = .{
        .owner = self,
        .url = url_copy,
    };

    const prom_cls = zjb.global("Promise");
    const exec_fn = zjb.fnHandle("webapi_io_prefetch_exec", &prefetchExecutor);
    const ctx_ptr: JsPtrInt = @bitCast(@intFromPtr(ctx));
    const bound = exec_fn.call(
        "bind",
        .{ zjb.Handle.null, ctx_ptr },
        zjb.Handle,
    );
    defer bound.release();

    const outer_p = prom_cls.new(.{bound});
    const fetch_p = webapi.fetch(url, req_init);
    defer fetch_p.release();
    fetch_p.thenFn(
        PrefetchContext,
        ctx,
        PrefetchContext.onResponse,
        PrefetchContext.onError,
    );
    return .fromHandle(outer_p);
}

/// Runs `func(ctx, self.io())` inside a `WebAssembly.promising` call frame when
/// JSPI is supported (allowing synchronous-looking `std.Io` calls to suspend on
/// Fetch, IndexedDB, `sleep`, and `Future.await`), or runs after
/// `waitMountsReady` on non-JSPI hosts, returning a `Promise` for completion.
pub fn callPromising(
    self: *WebApiIo,
    comptime Context: type,
    ctx: *Context,
    comptime func: *const fn (*Context, Io) void,
) !Promise.Typed(void) {
    std.debug.assert(@intFromPtr(self) != 0);
    std.debug.assert(@intFromPtr(ctx) != 0 or @sizeOf(Context) == 0);

    try self.ensureFsInitialized();
    const Tramp = struct {
        fn run(raw_ctx: *anyopaque, io_val: Io) void {
            const typed_ctx: *Context = @ptrCast(@alignCast(raw_ctx));
            func(typed_ctx, io_val);
        }
    };

    if (is_wasm and self.isJspiSupported() and self.jspi_depth == 0) {
        const p = self.callJspiPromisingEntry(&Tramp.run, @ptrCast(ctx));
        if (!p.isNull()) {
            if (!self.jspi_tail_promise.isNull()) {
                self.jspi_tail_promise.release();
            }
            self.jspi_tail_promise = webapi.retainHandle(p);
            return .fromHandle(p);
        }
    }

    const fallback = try self.gpa.create(FallbackRunContext);
    fallback.* = .{
        .owner = self,
        .tramp = &Tramp.run,
        .ctx_raw = @ptrCast(ctx),
    };

    const gate_p: Promise.Typed(void) = if (is_wasm and
        self.isJspiSupported() and
        !self.jspi_tail_promise.isNull())
        .fromHandle(webapi.retainHandle(self.jspi_tail_promise))
    else
        try self.waitMountsReady();
    defer gate_p.release();

    const prom_cls = zjb.global("Promise");
    const exec_fn = zjb.fnHandle("webapi_io_fallback_exec", &fallbackExecutor);
    const fb_ptr: JsPtrInt = @bitCast(@intFromPtr(fallback));
    const bound = exec_fn.call(
        "bind",
        .{ zjb.Handle.null, fb_ptr },
        zjb.Handle,
    );
    defer bound.release();

    const outer = prom_cls.new(.{bound});
    if (is_wasm and self.isJspiSupported()) {
        if (!self.jspi_tail_promise.isNull()) {
            self.jspi_tail_promise.release();
        }
        self.jspi_tail_promise = webapi.retainHandle(outer);
    }
    gate_p.thenFn(
        FallbackRunContext,
        fallback,
        FallbackRunContext.onReady,
        FallbackRunContext.onError,
    );
    return .fromHandle(outer);
}

/// Suspends the current JSPI WebAssembly stack until `promise` settles.
/// Returns `false` if JSPI stack suspension is not currently active.
pub fn awaitPromise(self: *WebApiIo, promise: Promise) bool {
    std.debug.assert(@intFromPtr(self) != 0);
    std.debug.assert(!promise.isNull());

    if (!self.canSuspend()) return false;
    const suspend_fn = @as(
        *volatile *const fn (i32) callconv(.c) i32,
        @ptrCast(&jspi_suspend_fn),
    ).*;
    _ = suspend_fn(@backingInt(promise.handle));
    return true;
}

/// Registers an in-memory mock fetch callback (useful for deterministic host
/// unit tests). Pass `null` via `clearMockFetch` to restore browser `fetch()`.
pub fn setMockFetch(
    self: *WebApiIo,
    ctx: ?*anyopaque,
    handler: MockFetchFn,
) void {
    std.debug.assert(@intFromPtr(self) != 0);
    std.debug.assert(@intFromPtr(handler) != 0);
    self.mock_fetch_ctx = ctx;
    self.mock_fetch = handler;
}

/// Clears any registered mock fetch callback.
pub fn clearMockFetch(self: *WebApiIo) void {
    std.debug.assert(@intFromPtr(self) != 0);
    self.mock_fetch = null;
    self.mock_fetch_ctx = null;
}

/// Provides a `std_options_cwd` implementation for `wasm32-freestanding` roots.
pub fn freestandingCwd() Dir {
    return .{
        .handle = if (Dir.Handle == void) {} else CWD_SENTINEL_FD,
    };
}

// 8. Extra classes
/// OS limits exportable as `pub const os = webapi.WebApiIo.freestanding_os;`
/// in `wasm32-freestanding` root modules using `std.Io.Dir`.
pub const freestanding_os = struct {
    pub const PATH_MAX: usize = MAX_PATH_BYTES;
    pub const NAME_MAX: usize = 255;
};

/// Plain-HTTP proxy descriptor used by `configureHttpClient` so
/// `std.http.Client` delegates both `http://` and `https://` requests with full
/// request-target URIs to `WebApiIo`'s Fetch transport.
pub const fetch_proxy: std.http.Client.Proxy = .{
    .protocol = .plain,
    .host = .{ .bytes = PROXY_HOST },
    .authorization = null,
    .port = 80,
    .supports_connect = false,
};

/// Borrowed HTTP request view passed to `MockFetchFn`.
pub const MockFetchRequest = struct {
    method: []const u8,
    url: []const u8,
    headers: []const std.http.Header,
    body: ?[]const u8,
};

/// Response returned from `MockFetchFn` (`body` owned by `allocator`).
pub const MockFetchResponse = struct {
    status: u16 = 200,
    reason: []const u8 = "OK",
    content_type: []const u8 = "application/octet-stream",
    location: ?[]const u8 = null,
    etag: ?[]const u8 = null,
    body: []u8,
};

/// Callback signature for `setMockFetch`.
pub const MockFetchFn = *const fn (
    ctx: ?*anyopaque,
    allocator: std.mem.Allocator,
    request: MockFetchRequest,
) anyerror!MockFetchResponse;

// 9. Private declarations
const is_wasm = builtin.target.cpu.arch.isWasm();
const JsPtrInt = @Int(.signed, @bitSizeOf(usize));

const MAX_PATH_BYTES: usize = 4096;
const MAX_VOID_HANDLES: usize = 64;
const CWD_SENTINEL_FD: i32 = 3;
const FIRST_DYNAMIC_FD: i32 = 100;
const FD_FLAG_READ: i32 = 1 << 0;
const FD_FLAG_APPEND: i32 = 1 << 1;
const PROXY_HOST = "fetch.webapi.internal";
const JSPI_STACK_BYTES: usize = 128 * 1024;

/// Minimal 131-byte WASM bridge module isolating `__stack_pointer` (`e.sp`) on a
/// dedicated heap fiber stack while a JSPI fiber (`e.p`) is executing/suspended:
/// - `r(fiber_top, io, tramp, ctx)`: saves `__stack_pointer` to `$idle_sp`,
///   switches `__stack_pointer` to `fiber_top`, invokes `e.p`, and restores
///   `__stack_pointer` to `$idle_sp` on return.
/// - `f(promise_handle)`: saves the active fiber `__stack_pointer`, switches
///   `__stack_pointer` to `$idle_sp` before suspending in `e.s(Suspending)`,
///   captures the post-resume top-level `__stack_pointer` into `$idle_sp`, and
///   restores the fiber `__stack_pointer` cleanly across event loop turns.
const jspi_bridge_wasm = [_]u8{
    0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00,
    0x01, 0x13, 0x03, 0x60, 0x03, 0x7f, 0x7f, 0x7f,
    0x00, 0x60, 0x01, 0x7f, 0x01, 0x7f, 0x60, 0x04,
    0x7f, 0x7f, 0x7f, 0x7f, 0x00, 0x02, 0x15, 0x03,
    0x01, 0x65, 0x02, 0x73, 0x70, 0x03, 0x7f, 0x01,
    0x01, 0x65, 0x01, 0x70, 0x00, 0x00, 0x01, 0x65,
    0x01, 0x73, 0x00, 0x01, 0x03, 0x03, 0x02, 0x02,
    0x01, 0x06, 0x06, 0x01, 0x7f, 0x01, 0x41, 0x00,
    0x0b, 0x07, 0x09, 0x02, 0x01, 0x72, 0x00, 0x02,
    0x01, 0x66, 0x00, 0x03, 0x0a, 0x35, 0x02, 0x16,
    0x00, 0x23, 0x00, 0x24, 0x01, 0x20, 0x00, 0x24,
    0x00, 0x20, 0x01, 0x20, 0x02, 0x20, 0x03, 0x10,
    0x00, 0x23, 0x01, 0x24, 0x00, 0x0b, 0x1c, 0x01,
    0x02, 0x7f, 0x23, 0x00, 0x21, 0x01, 0x23, 0x01,
    0x24, 0x00, 0x20, 0x00, 0x10, 0x01, 0x21, 0x02,
    0x23, 0x00, 0x24, 0x01, 0x20, 0x01, 0x24, 0x00,
    0x20, 0x02, 0x0b,
};

const PromisingTrampoline = *const fn (*anyopaque, Io) void;

var jspi_suspend_fn: *const fn (i32) callconv(.c) i32 = &jspiSuspendPlaceholder;
var jspi_shared_slot: i32 = -1;
var jspi_shared_bridge: webapi.WebAssembly.Instance = .null;

comptime {
    if (is_wasm) {
        @export(&promisingEntryExport, .{
            .name = "webapi_io_promising_entry",
        });
        @export(&jspiSetSuspendSlot, .{
            .name = "webapi_io_set_suspend_slot",
        });
        @export(&jspiGetSuspendSlot, .{
            .name = "webapi_io_get_suspend_slot",
        });
    }
}

const vtable: Io.VTable = .{
    .crashHandler = failing.crashHandler,

    .async = ioAsync,
    .concurrent = ioConcurrent,
    .await = ioAwait,
    .cancel = ioCancel,

    .groupAsync = ioGroupAsync,
    .groupConcurrent = ioGroupConcurrent,
    .groupAwait = ioGroupAwait,
    .groupCancel = ioGroupCancel,

    .recancel = ioRecancel,
    .swapCancelProtection = ioSwapCancelProtection,
    .checkCancel = ioCheckCancel,

    .futexWait = ioFutexWait,
    .futexWaitUncancelable = ioFutexWaitUncancelable,
    .futexWake = ioFutexWake,

    .operate = ioOperate,
    .batchAwaitAsync = ioBatchAwaitAsync,
    .batchAwaitConcurrent = ioBatchAwaitConcurrent,
    .batchCancel = ioBatchCancel,

    .dirCreateDir = ioDirCreateDir,
    .dirCreateDirPath = ioDirCreateDirPath,
    .dirCreateDirPathOpen = ioDirCreateDirPathOpen,
    .dirOpenDir = ioDirOpenDir,
    .dirStat = ioDirStat,
    .dirStatFile = ioDirStatFile,
    .dirAccess = ioDirAccess,
    .dirCreateFile = ioDirCreateFile,
    .dirCreateFileAtomic = ioDirCreateFileAtomic,
    .dirOpenFile = ioDirOpenFile,
    .dirClose = ioDirClose,
    .dirRead = ioDirRead,
    .dirRealPath = ioDirRealPath,
    .dirRealPathFile = ioDirRealPathFile,
    .dirDeleteFile = ioDirDeleteFile,
    .dirDeleteDir = ioDirDeleteDir,
    .dirRename = ioDirRename,
    .dirRenamePreserve = ioDirRenamePreserve,
    .dirSymLink = failing.dirSymLink,
    .dirReadLink = failing.dirReadLink,
    .dirSetOwner = failing.dirSetOwner,
    .dirSetFileOwner = failing.dirSetFileOwner,
    .dirSetPermissions = failing.dirSetPermissions,
    .dirSetFilePermissions = failing.dirSetFilePermissions,
    .dirSetTimestamps = ioDirSetTimestamps,
    .dirHardLink = failing.dirHardLink,

    .fileStat = ioFileStat,
    .fileLength = ioFileLength,
    .fileClose = ioFileClose,
    .fileWritePositional = ioFileWritePositional,
    .fileWriteFileStreaming = failing.fileWriteFileStreaming,
    .fileWriteFilePositional = failing.fileWriteFilePositional,
    .fileReadPositional = ioFileReadPositional,
    .fileSeekBy = ioFileSeekBy,
    .fileSeekTo = ioFileSeekTo,
    .fileSync = ioFileSync,
    .fileIsTty = ioFileIsTty,
    .fileEnableAnsiEscapeCodes = ioFileEnableAnsiEscapeCodes,
    .fileSupportsAnsiEscapeCodes = ioFileSupportsAnsiEscapeCodes,
    .fileSetLength = ioFileSetLength,
    .fileSetOwner = failing.fileSetOwner,
    .fileSetPermissions = failing.fileSetPermissions,
    .fileSetTimestamps = ioFileSetTimestamps,
    .fileLock = failing.fileLock,
    .fileTryLock = failing.fileTryLock,
    .fileUnlock = failing.fileUnlock,
    .fileDowngradeLock = failing.fileDowngradeLock,
    .fileRealPath = ioFileRealPath,
    .fileHardLink = failing.fileHardLink,

    .fileMemoryMapCreate = failing.fileMemoryMapCreate,
    .fileMemoryMapDestroy = failing.fileMemoryMapDestroy,
    .fileMemoryMapSetLength = failing.fileMemoryMapSetLength,
    .fileMemoryMapRead = failing.fileMemoryMapRead,
    .fileMemoryMapWrite = failing.fileMemoryMapWrite,

    .processExecutableOpen = failing.processExecutableOpen,
    .processExecutablePath = failing.processExecutablePath,
    .lockStderr = failing.lockStderr,
    .tryLockStderr = failing.tryLockStderr,
    .unlockStderr = failing.unlockStderr,
    .processCurrentPath = ioProcessCurrentPath,
    .processSetCurrentDir = ioProcessSetCurrentDir,
    .processSetCurrentPath = ioProcessSetCurrentPath,
    .processReplace = failing.processReplace,
    .processSpawn = failing.processSpawn,
    .childWait = failing.childWait,
    .childKill = failing.childKill,

    .progressParentFile = failing.progressParentFile,
    .inheritParentDir = failing.inheritParentDir,
    .inheritParentFile = failing.inheritParentFile,

    .now = ioNow,
    .clockResolution = ioClockResolution,
    .sleep = ioSleep,

    .random = ioRandom,
    .randomSecure = ioRandomSecure,

    .netListenIp = failing.netListenIp,
    .netAccept = failing.netAccept,
    .netBindIp = failing.netBindIp,
    .netConnectIp = ioNetConnectIp,
    .netListenUnix = failing.netListenUnix,
    .netConnectUnix = failing.netConnectUnix,
    .netSocketCreatePair = failing.netSocketCreatePair,
    .netWriteFile = ioNetWriteFile,
    .netClose = ioNetClose,
    .netShutdown = ioNetShutdown,
    .netInterfaceNameResolve = failing.netInterfaceNameResolve,
    .netInterfaceName = failing.netInterfaceName,
    .netLookup = ioNetLookup,
};

const HostMapping = struct {
    ip: [4]u8,
    name: []u8,
};

const PrefetchedEntry = struct {
    url: []u8,
    status: u16,
    content_type: []u8,
    body: []u8,

    fn deinit(self: *PrefetchedEntry, gpa: std.mem.Allocator) void {
        gpa.free(self.url);
        gpa.free(self.content_type);
        gpa.free(self.body);
    }
};

const HttpSocket = struct {
    id: i32,
    host: []u8,
    port: u16,
    request_buf: std.ArrayList(u8) = .empty,
    response_buf: std.ArrayList(u8) = .empty,
    read_pos: usize = 0,
    has_response: bool = false,
    send_closed: bool = false,
    recv_closed: bool = false,

    fn destroy(self: *HttpSocket, gpa: std.mem.Allocator) void {
        self.request_buf.deinit(gpa);
        self.response_buf.deinit(gpa);
        gpa.free(self.host);
        gpa.destroy(self);
    }
};

const TaskKind = enum {
    future_result,
    group_void,
};

const PromiseTask = struct {
    owner: *WebApiIo,
    kind: TaskKind,
    context_buf: ?[]u8 = null,
    context_align: std.mem.Alignment = .@"1",
    result_buf: ?[]u8 = null,
    result_align: std.mem.Alignment = .@"1",
    start_future: ?*const fn (*const anyopaque, *anyopaque) void = null,
    start_group: ?*const fn (*const anyopaque) void = null,
    promise: Promise = .null,
    completed: bool = false,
    canceled: bool = false,

    fn execute(self: *PromiseTask) void {
        if (self.completed) return;
        const ctx_ptr: *const anyopaque = if (self.context_buf) |b|
            @ptrCast(b.ptr)
        else
            @ptrCast(self);

        switch (self.kind) {
            .future_result => {
                const res_ptr: *anyopaque = if (self.result_buf) |b|
                    @ptrCast(b.ptr)
                else
                    @ptrCast(self);
                self.start_future.?(ctx_ptr, res_ptr);
            },
            .group_void => {
                self.start_group.?(ctx_ptr);
            },
        }
        self.completed = true;
    }

    fn destroy(self: *PromiseTask) void {
        const gpa = self.owner.gpa;
        if (!self.promise.isNull()) {
            self.promise.release();
            self.promise = .null;
        }
        if (self.context_buf) |b| {
            gpa.rawFree(b, self.context_align, @returnAddress());
        }
        if (self.result_buf) |b| {
            gpa.rawFree(b, self.result_align, @returnAddress());
        }
        gpa.destroy(self);
    }
};

const GroupState = struct {
    tasks: std.ArrayList(*PromiseTask) = .empty,
    canceled: bool = false,
};

const FutexWaiter = struct {
    ptr: *const u32,
    resolve_h: zjb.Handle = .null,
    timeout_id: ?i32 = null,
    woken: bool = false,

    fn wake(self: *FutexWaiter) void {
        if (self.woken) return;
        self.woken = true;
        if (self.timeout_id) |tid| {
            webapi.dom.window().clearTimeout(tid);
            self.timeout_id = null;
        }
        if (!self.resolve_h.isNull()) {
            self.resolve_h.call(
                "call",
                .{ zjb.Handle.null, @as(i32, 0) },
                void,
            );
        }
    }

    fn onTimeout(self: *FutexWaiter) void {
        self.timeout_id = null;
        self.wake();
    }

    fn deinit(self: *FutexWaiter, gpa: std.mem.Allocator) void {
        if (self.timeout_id) |tid| {
            webapi.dom.window().clearTimeout(tid);
            self.timeout_id = null;
        }
        if (!self.resolve_h.isNull()) {
            self.resolve_h.release();
            self.resolve_h = .null;
        }
        gpa.destroy(self);
    }
};

const SleepTimer = struct {
    resolve_h: zjb.Handle = .null,

    fn onFire(self: *SleepTimer) void {
        if (!self.resolve_h.isNull()) {
            self.resolve_h.call(
                "call",
                .{ zjb.Handle.null, @as(i32, 0) },
                void,
            );
        }
    }
};

const AsyncFetchState = struct {
    gpa: std.mem.Allocator,
    resolve_h: zjb.Handle = .null,
    status: u16 = 0,
    reason_buf: [64]u8 = undefined,
    reason_len: usize = 0,
    ct_buf: [128]u8 = undefined,
    ct_len: usize = 0,
    loc_buf: [512]u8 = undefined,
    loc_len: usize = 0,
    etag_buf: [128]u8 = undefined,
    etag_len: usize = 0,
    body: ?[]u8 = null,
    failed: bool = false,

    fn onResponse(self: *AsyncFetchState, resp: Fetch.Response) void {
        const code = resp.status();
        self.status = if (code > 0 and code <= 999) @intCast(code) else 502;
        self.reason_len = resp.statusText(&self.reason_buf).len;

        const hdrs = resp.headers();
        defer hdrs.release();
        self.ct_len = hdrs.get("content-type", &self.ct_buf).len;
        self.loc_len = hdrs.get("location", &self.loc_buf).len;
        self.etag_len = hdrs.get("etag", &self.etag_buf).len;

        const ab_p = resp.arrayBuffer();
        defer ab_p.release();
        ab_p.thenFn(AsyncFetchState, self, onBytes, onError);
    }

    fn onBytes(self: *AsyncFetchState, buf_h: zjb.Handle) void {
        self.body = webapi.bytesFromHandleAlloc(self.gpa, buf_h) catch blk: {
            self.failed = true;
            break :blk null;
        };
        self.finish();
    }

    fn onError(self: *AsyncFetchState, _: zjb.Handle) void {
        self.failed = true;
        self.finish();
    }

    fn finish(self: *AsyncFetchState) void {
        if (!self.resolve_h.isNull()) {
            self.resolve_h.call(
                "call",
                .{ zjb.Handle.null, @as(i32, 0) },
                void,
            );
        }
    }
};

const PrefetchContext = struct {
    owner: *WebApiIo,
    url: []u8,
    status: u16 = 200,
    ct_buf: [128]u8 = undefined,
    ct_len: usize = 0,
    resolve_h: zjb.Handle = .null,
    reject_h: zjb.Handle = .null,

    fn deinit(self: *PrefetchContext) void {
        const gpa = self.owner.gpa;
        if (!self.resolve_h.isNull()) self.resolve_h.release();
        if (!self.reject_h.isNull()) self.reject_h.release();
        gpa.free(self.url);
        gpa.destroy(self);
    }

    fn onResponse(self: *PrefetchContext, resp: Fetch.Response) void {
        const code = resp.status();
        self.status = if (code > 0 and code <= 999) @intCast(code) else 200;
        const hdrs = resp.headers();
        defer hdrs.release();
        self.ct_len = hdrs.get("content-type", &self.ct_buf).len;

        const ab_p = resp.arrayBuffer();
        defer ab_p.release();
        ab_p.thenFn(PrefetchContext, self, onBytes, onError);
    }

    fn onBytes(self: *PrefetchContext, buf_h: zjb.Handle) void {
        const gpa = self.owner.gpa;
        const body = webapi.bytesFromHandleAlloc(gpa, buf_h) catch {
            self.onError(.null);
            return;
        };
        const ct = gpa.dupe(
            u8,
            if (self.ct_len > 0)
                self.ct_buf[0..self.ct_len]
            else
                "application/octet-stream",
        ) catch {
            gpa.free(body);
            self.onError(.null);
            return;
        };
        const url_owned = gpa.dupe(u8, self.url) catch {
            gpa.free(ct);
            gpa.free(body);
            self.onError(.null);
            return;
        };

        self.owner.storePrefetched(.{
            .url = url_owned,
            .status = self.status,
            .content_type = ct,
            .body = body,
        }) catch {
            gpa.free(url_owned);
            gpa.free(ct);
            gpa.free(body);
        };

        if (!self.resolve_h.isNull()) {
            self.resolve_h.call(
                "call",
                .{ zjb.Handle.null, zjb.Handle.null },
                void,
            );
        }
        self.deinit();
    }

    fn onError(self: *PrefetchContext, err_h: zjb.Handle) void {
        if (!self.reject_h.isNull()) {
            self.reject_h.call("call", .{ zjb.Handle.null, err_h }, void);
        }
        self.deinit();
    }
};

const FallbackRunContext = struct {
    owner: *WebApiIo,
    tramp: PromisingTrampoline,
    ctx_raw: *anyopaque,
    resolve_h: zjb.Handle = .null,
    reject_h: zjb.Handle = .null,

    fn onReady(self: *FallbackRunContext) void {
        if (is_wasm and
            self.owner.isJspiSupported() and
            self.owner.jspi_depth == 0)
        {
            const inner_p = self.owner.callJspiPromisingEntry(
                self.tramp,
                self.ctx_raw,
            );
            if (!inner_p.isNull()) {
                defer inner_p.release();
                if (!self.resolve_h.isNull()) {
                    self.resolve_h.call(
                        "call",
                        .{ zjb.Handle.null, inner_p },
                        void,
                    );
                    self.resolve_h.release();
                }
                if (!self.reject_h.isNull()) self.reject_h.release();
                self.owner.gpa.destroy(self);
                return;
            }
        }
        self.tramp(self.ctx_raw, self.owner.io());
        if (!self.resolve_h.isNull()) {
            self.resolve_h.call(
                "call",
                .{ zjb.Handle.null, zjb.Handle.null },
                void,
            );
            self.resolve_h.release();
        }
        if (!self.reject_h.isNull()) self.reject_h.release();
        self.owner.gpa.destroy(self);
    }

    fn onError(self: *FallbackRunContext, err_h: zjb.Handle) void {
        if (!self.reject_h.isNull()) {
            self.reject_h.call("call", .{ zjb.Handle.null, err_h }, void);
            self.reject_h.release();
        }
        if (!self.resolve_h.isNull()) self.resolve_h.release();
        self.owner.gpa.destroy(self);
    }
};

const AsyncIdbLookup = struct {
    fs: *FileSystem,
    mount_point: *FileSystem.ActiveIndexedFsMountPoint,
    path: []const u8,
    req: zjb.Handle = .null,
    resolve_h: zjb.Handle = .null,

    fn finish(self: *AsyncIdbLookup, result_h: zjb.Handle) void {
        self.fs.applyIdbResult(self.mount_point, self.path, result_h);
        if (!self.req.isNull()) {
            self.req.set("onsuccess", zjb.Handle.null);
            self.req.set("onerror", zjb.Handle.null);
            self.req.release();
            self.req = .null;
        }
        if (!self.resolve_h.isNull()) {
            self.resolve_h.call(
                "call",
                .{ zjb.Handle.null, @as(i32, 0) },
                void,
            );
        }
    }

    fn onSuccess(self: *AsyncIdbLookup, _: zjb.Handle) void {
        const res = self.req.get("result", zjb.Handle);
        defer if (!res.isNull()) res.release();
        self.finish(res);
    }

    fn onError(self: *AsyncIdbLookup, _: zjb.Handle) void {
        self.finish(.null);
    }
};

fn initRootCwd() [MAX_PATH_BYTES]u8 {
    var buf: [MAX_PATH_BYTES]u8 = @splat(0);
    buf[0] = '/';
    return buf;
}

fn fromUserdata(userdata: ?*anyopaque) *WebApiIo {
    std.debug.assert(userdata != null);
    const self: *WebApiIo = @ptrCast(@alignCast(userdata.?));
    std.debug.assert(@intFromPtr(self.gpa.vtable) != 0);
    return self;
}

fn ensureFsInitialized(self: *WebApiIo) !void {
    std.debug.assert(@intFromPtr(self) != 0);
    std.debug.assert(@intFromPtr(self.gpa.vtable) != 0);
    if (self.fs_initialized) return;

    var default_preopen: [1]FileSystem.Preopen = undefined;
    const preopens: []const FileSystem.Preopen = if (self.db_name) |db| blk: {
        default_preopen[0] = .{
            .indexed_fs = .{
                .path = "/",
                .db_name = db,
                .store_name = self.store_name,
                .preload_path = "/",
            },
        };
        break :blk &default_preopen;
    } else &.{};

    try self.fs.init(.{
        .allocator = self.gpa,
        .preopens = preopens,
        .on_indexed_fs_mount_ready = onFsMountReady,
        .indexed_fs_mount_ready_ctx = @ptrCast(self),
    });
    self.fs.next_fd = FIRST_DYNAMIC_FD;
    self.fs_initialized = true;
}

fn onFsMountReady(ctx_raw: *anyopaque, dir_path: []const u8) void {
    const self: *WebApiIo = @ptrCast(@alignCast(ctx_raw));
    if (self.user_mount_cb) |cb| {
        cb(self.user_mount_ctx orelse ctx_raw, dir_path);
    }
    if (self.fs.areAllIndexedFsMountsReady()) {
        for (self.mount_waiters.items) |resolve_h| {
            if (!resolve_h.isNull()) {
                resolve_h.call(
                    "call",
                    .{ zjb.Handle.null, zjb.Handle.null },
                    void,
                );
                resolve_h.release();
            }
        }
        self.mount_waiters.clearRetainingCapacity();
    }
}

fn mountWaitExecutor(
    ctx_ptr: JsPtrInt,
    resolve_h: zjb.Handle,
    reject_h: zjb.Handle,
) callconv(.c) void {
    if (!reject_h.isNull()) reject_h.release();
    const self: *WebApiIo = @ptrFromInt(@as(usize, @bitCast(ctx_ptr)));
    if (self.fs.areAllIndexedFsMountsReady()) {
        resolve_h.call("call", .{ zjb.Handle.null, zjb.Handle.null }, void);
        resolve_h.release();
        return;
    }
    self.mount_waiters.append(self.gpa, resolve_h) catch {
        resolve_h.call("call", .{ zjb.Handle.null, zjb.Handle.null }, void);
        resolve_h.release();
    };
}

fn prefetchExecutor(
    ctx_ptr: JsPtrInt,
    resolve_h: zjb.Handle,
    reject_h: zjb.Handle,
) callconv(.c) void {
    const ctx: *PrefetchContext = @ptrFromInt(@as(usize, @bitCast(ctx_ptr)));
    ctx.resolve_h = resolve_h;
    ctx.reject_h = reject_h;
}

fn fallbackExecutor(
    ctx_ptr: JsPtrInt,
    resolve_h: zjb.Handle,
    reject_h: zjb.Handle,
) callconv(.c) void {
    const ctx: *FallbackRunContext = @ptrFromInt(@as(usize, @bitCast(ctx_ptr)));
    ctx.resolve_h = resolve_h;
    ctx.reject_h = reject_h;
}

fn storePrefetched(self: *WebApiIo, entry: PrefetchedEntry) !void {
    for (self.prefetched.items) |*existing| {
        if (std.mem.eql(u8, existing.url, entry.url)) {
            existing.deinit(self.gpa);
            existing.* = entry;
            return;
        }
    }
    try self.prefetched.append(self.gpa, entry);
}

fn callJspiPromisingEntry(
    self: *WebApiIo,
    tramp: PromisingTrampoline,
    ctx_raw: *anyopaque,
) zjb.Handle {
    const stack = self.jspi_stack orelse return .null;
    const fiber_top: JsPtrInt = @bitCast(@intFromPtr(stack.ptr) + stack.len);
    const io_ptr: JsPtrInt = @bitCast(@intFromPtr(self));
    const tramp_ptr: JsPtrInt = @bitCast(@intFromPtr(tramp));
    const ctx_ptr: JsPtrInt = @bitCast(@intFromPtr(ctx_raw));
    return self.jspi_promising_entry.call(
        "call",
        .{ zjb.Handle.null, fiber_top, io_ptr, tramp_ptr, ctx_ptr },
        zjb.Handle,
    );
}

fn canSuspend(self: *WebApiIo) bool {
    if (!is_wasm or builtin.is_test) return false;
    if (self.jspi_depth == 0) return false;
    self.ensureJspiInitialized();
    return self.jspi_suspend_slot >= 0 and self.jspi_stack != null;
}

fn ensureJspiInitialized(self: *WebApiIo) void {
    if (self.jspi_initialized) return;
    self.jspi_initialized = true;
    if (!is_wasm or builtin.is_test) return;
    if (!webapi.WebAssembly.isJspiSupported()) return;

    var inst = self.instance;
    var release_inst = false;
    if (inst.isNull()) {
        const zjb_obj = zjb.ConstHandle.global.get("zjb", zjb.Handle);
        defer zjb_obj.release();
        if (zjb_obj.isNull()) return;
        const inst_h = zjb_obj.get("instance", zjb.Handle);
        if (inst_h.isNull()) return;
        inst = webapi.WebAssembly.Instance.fromHandle(inst_h);
        release_inst = true;
    }
    defer if (release_inst) inst.release();

    const exports = inst.getExports();
    defer exports.release();
    if (exports.isNull()) return;

    const sp_global_h = exports.get("__stack_pointer", zjb.Handle);
    defer sp_global_h.release();
    const entry_raw = exports.get("webapi_io_promising_entry", zjb.Handle);
    defer entry_raw.release();
    const table_h = exports.get("__indirect_function_table", zjb.Handle);
    defer table_h.release();
    if (sp_global_h.isNull() or entry_raw.isNull() or table_h.isNull()) return;

    if (jspi_shared_slot < 0) {
        const slot = jspiGetSuspendSlot();
        const table_len = table_h.get("length", i32);
        if (slot <= 0 or slot >= table_len) return;

        const passthrough = zjb.fnHandle(
            "webapi_io_jspi_passthrough",
            &jspiPassthroughPromise,
        );
        var susp = webapi.WebAssembly.Suspending.init(
            passthrough.asHandle(),
        ) catch return;
        defer susp.release();

        const env_obj = zjb.global("Object").new(.{});
        defer env_obj.release();
        env_obj.set("sp", sp_global_h);
        env_obj.set("p", entry_raw);
        env_obj.set("s", susp.handle);

        const imp_obj = zjb.global("Object").new(.{});
        defer imp_obj.release();
        imp_obj.set("e", env_obj);

        const bridge = webapi.WebAssembly.instantiate(
            &jspi_bridge_wasm,
            imp_obj,
        ) catch return;

        const bridge_exports = bridge.getExports();
        defer bridge_exports.release();
        const bridge_f = bridge_exports.get("f", zjb.Handle);
        defer bridge_f.release();
        const bridge_r = bridge_exports.get("r", zjb.Handle);
        defer bridge_r.release();
        if (bridge_f.isNull() or bridge_r.isNull()) {
            var b = bridge;
            b.release();
            return;
        }

        table_h.call("set", .{ slot, bridge_f }, void);
        jspi_shared_bridge = bridge;
        jspi_shared_slot = slot;
    }

    if (jspi_shared_bridge.isNull()) return;
    const shared_exports = jspi_shared_bridge.getExports();
    defer shared_exports.release();
    if (shared_exports.isNull()) return;
    const bridge_run = shared_exports.get("r", zjb.Handle);
    defer bridge_run.release();
    if (bridge_run.isNull()) return;

    const prom_entry = webapi.WebAssembly.promising(bridge_run) catch return;
    errdefer prom_entry.release();

    if (self.jspi_stack == null) {
        self.jspi_stack = self.gpa.alignedAlloc(
            u8,
            .@"16",
            JSPI_STACK_BYTES,
        ) catch return;
    }

    self.jspi_promising_entry = prom_entry;
    self.jspi_suspend_slot = jspi_shared_slot;
}

fn jspiSuspendPlaceholder(handle_id: i32) callconv(.c) i32 {
    return handle_id;
}

fn jspiGetSuspendSlot() callconv(.c) i32 {
    const ptr = @as(
        *volatile *const fn (i32) callconv(.c) i32,
        @ptrCast(&jspi_suspend_fn),
    ).*;
    return @intCast(@intFromPtr(ptr));
}

fn jspiSetSuspendSlot(slot: usize) callconv(.c) void {
    @as(
        *volatile *const fn (i32) callconv(.c) i32,
        @ptrCast(&jspi_suspend_fn),
    ).* = @ptrFromInt(slot);
}

fn jspiPassthroughPromise(handle_id: i32) callconv(.c) zjb.Handle {
    return @fromBackingInt(handle_id);
}

fn promisingEntryExport(
    io_ptr: JsPtrInt,
    tramp_ptr: JsPtrInt,
    ctx_ptr: JsPtrInt,
) callconv(.c) void {
    const self: *WebApiIo = @ptrFromInt(@as(usize, @bitCast(io_ptr)));
    const tramp: PromisingTrampoline = @ptrFromInt(
        @as(usize, @bitCast(tramp_ptr)),
    );
    const ctx_raw: *anyopaque = @ptrFromInt(@as(usize, @bitCast(ctx_ptr)));

    self.jspi_depth += 1;
    defer self.jspi_depth -= 1;

    if (!self.fs.areAllIndexedFsMountsReady()) {
        if (self.waitMountsReady() catch null) |ready_p| {
            defer ready_p.release();
            _ = self.awaitPromise(ready_p.promise);
        }
    }
    tramp(ctx_raw, self.io());
}

// =========================================================================
// Promise-based async / await / concurrent / Group / futex / cancelation
// =========================================================================

fn spawnPromiseTask(
    self: *WebApiIo,
    kind: TaskKind,
    result_len: usize,
    result_alignment: std.mem.Alignment,
    context: []const u8,
    context_alignment: std.mem.Alignment,
    start_future: ?*const fn (*const anyopaque, *anyopaque) void,
    start_group: ?*const fn (*const anyopaque) void,
) !*PromiseTask {
    const task = try self.gpa.create(PromiseTask);
    errdefer self.gpa.destroy(task);

    const ctx_copy: ?[]u8 = if (context.len > 0) blk: {
        const ptr = self.gpa.rawAlloc(
            context.len,
            context_alignment,
            @returnAddress(),
        ) orelse return error.OutOfMemory;
        const slice = ptr[0..context.len];
        @memcpy(slice, context);
        break :blk slice;
    } else null;
    errdefer if (ctx_copy) |b| {
        self.gpa.rawFree(b, context_alignment, @returnAddress());
    };

    const res_buf: ?[]u8 = if (result_len > 0) blk: {
        const ptr = self.gpa.rawAlloc(
            result_len,
            result_alignment,
            @returnAddress(),
        ) orelse return error.OutOfMemory;
        break :blk ptr[0..result_len];
    } else null;
    errdefer if (res_buf) |b| {
        self.gpa.rawFree(b, result_alignment, @returnAddress());
    };

    task.* = .{
        .owner = self,
        .kind = kind,
        .context_buf = ctx_copy,
        .context_align = context_alignment,
        .result_buf = res_buf,
        .result_align = result_alignment,
        .start_future = start_future,
        .start_group = start_group,
    };

    task.execute();
    task.promise = Promise.resolve(@as(i32, 0));
    return task;
}

fn ioAsync(
    userdata: ?*anyopaque,
    result: []u8,
    result_alignment: std.mem.Alignment,
    context: []const u8,
    context_alignment: std.mem.Alignment,
    start: *const fn (context: *const anyopaque, result: *anyopaque) void,
) ?*Io.AnyFuture {
    const self = fromUserdata(userdata);
    const task = self.spawnPromiseTask(
        .future_result,
        result.len,
        result_alignment,
        context,
        context_alignment,
        start,
        null,
    ) catch {
        start(context.ptr, result.ptr);
        return null;
    };
    return @ptrCast(task);
}

fn ioConcurrent(
    userdata: ?*anyopaque,
    result_len: usize,
    result_alignment: std.mem.Alignment,
    context: []const u8,
    context_alignment: std.mem.Alignment,
    start: *const fn (context: *const anyopaque, result: *anyopaque) void,
) Io.ConcurrentError!*Io.AnyFuture {
    const self = fromUserdata(userdata);
    const task = self.spawnPromiseTask(
        .future_result,
        result_len,
        result_alignment,
        context,
        context_alignment,
        start,
        null,
    ) catch return error.ConcurrencyUnavailable;
    return @ptrCast(task);
}

fn settleFuture(
    self: *WebApiIo,
    any_future: *Io.AnyFuture,
    result: []u8,
    request_cancel: bool,
) void {
    const task: *PromiseTask = @ptrCast(@alignCast(any_future));
    if (request_cancel) {
        task.canceled = true;
    }
    if (!task.completed and !task.promise.isNull()) {
        if (!self.awaitPromise(task.promise)) {
            task.execute();
        }
    }
    std.debug.assert(task.completed);
    if (result.len > 0) {
        if (task.result_buf) |src| {
            @memcpy(result, src);
        }
    }
    task.destroy();
}

fn ioAwait(
    userdata: ?*anyopaque,
    any_future: *Io.AnyFuture,
    result: []u8,
    result_alignment: std.mem.Alignment,
) void {
    _ = result_alignment;
    const self = fromUserdata(userdata);
    self.settleFuture(any_future, result, false);
}

fn ioCancel(
    userdata: ?*anyopaque,
    any_future: *Io.AnyFuture,
    result: []u8,
    result_alignment: std.mem.Alignment,
) void {
    _ = result_alignment;
    const self = fromUserdata(userdata);
    self.settleFuture(any_future, result, true);
}

fn ensureGroupState(self: *WebApiIo, group: *Io.Group) !*GroupState {
    if (group.token.load(.acquire)) |tok| {
        return @ptrCast(@alignCast(tok));
    }
    const gs = try self.gpa.create(GroupState);
    gs.* = .{};
    group.token.store(@ptrCast(gs), .release);
    return gs;
}

fn ioGroupAsync(
    userdata: ?*anyopaque,
    group: *Io.Group,
    context: []const u8,
    context_alignment: std.mem.Alignment,
    start: *const fn (context: *const anyopaque) void,
) void {
    const self = fromUserdata(userdata);
    const gs = self.ensureGroupState(group) catch {
        start(context.ptr);
        return;
    };
    const task = self.spawnPromiseTask(
        .group_void,
        0,
        .@"1",
        context,
        context_alignment,
        null,
        start,
    ) catch {
        start(context.ptr);
        return;
    };
    gs.tasks.append(self.gpa, task) catch {
        if (!task.completed and !task.promise.isNull()) {
            _ = self.awaitPromise(task.promise);
        }
        task.destroy();
    };
}

fn ioGroupConcurrent(
    userdata: ?*anyopaque,
    group: *Io.Group,
    context: []const u8,
    context_alignment: std.mem.Alignment,
    start: *const fn (context: *const anyopaque) void,
) Io.ConcurrentError!void {
    const self = fromUserdata(userdata);
    const gs = self.ensureGroupState(group) catch {
        return error.ConcurrencyUnavailable;
    };
    const task = self.spawnPromiseTask(
        .group_void,
        0,
        .@"1",
        context,
        context_alignment,
        null,
        start,
    ) catch return error.ConcurrencyUnavailable;
    gs.tasks.append(self.gpa, task) catch {
        task.destroy();
        return error.ConcurrencyUnavailable;
    };
}

fn settleGroup(
    self: *WebApiIo,
    group: *Io.Group,
    token: *anyopaque,
    request_cancel: bool,
) void {
    const gs: *GroupState = @ptrCast(@alignCast(token));
    if (request_cancel) {
        gs.canceled = true;
    }
    var idx: usize = 0;
    while (idx < gs.tasks.items.len) : (idx += 1) {
        const task = gs.tasks.items[idx];
        if (!task.completed and !task.promise.isNull()) {
            if (!self.awaitPromise(task.promise)) {
                task.execute();
            }
        }
        task.destroy();
    }
    gs.tasks.deinit(self.gpa);
    self.gpa.destroy(gs);
    group.token.store(null, .release);
}

fn ioGroupAwait(
    userdata: ?*anyopaque,
    group: *Io.Group,
    token: *anyopaque,
) Io.Cancelable!void {
    const self = fromUserdata(userdata);
    try ioCheckCancel(userdata);
    self.settleGroup(group, token, false);
}

fn ioGroupCancel(
    userdata: ?*anyopaque,
    group: *Io.Group,
    token: *anyopaque,
) void {
    const self = fromUserdata(userdata);
    self.settleGroup(group, token, true);
}

fn ioRecancel(userdata: ?*anyopaque) void {
    const self = fromUserdata(userdata);
    self.cancel_pending = true;
}

fn ioSwapCancelProtection(
    userdata: ?*anyopaque,
    new: Io.CancelProtection,
) Io.CancelProtection {
    const self = fromUserdata(userdata);
    const prev = self.cancel_protection;
    self.cancel_protection = new;
    return prev;
}

fn ioCheckCancel(userdata: ?*anyopaque) Io.Cancelable!void {
    const self = fromUserdata(userdata);
    if (self.cancel_protection == .unblocked and self.cancel_pending) {
        self.cancel_pending = false;
        return error.Canceled;
    }
}

fn futexWaitExecutor(
    ctx_ptr: JsPtrInt,
    resolve_h: zjb.Handle,
    reject_h: zjb.Handle,
) callconv(.c) void {
    if (!reject_h.isNull()) reject_h.release();
    const waiter: *FutexWaiter = @ptrFromInt(@as(usize, @bitCast(ctx_ptr)));
    waiter.resolve_h = resolve_h;
}

fn futexWaitInternal(
    self: *WebApiIo,
    ptr: *const u32,
    expected: u32,
    timeout: Io.Timeout,
) void {
    if (ptr.* != expected) return;
    if (!self.canSuspend()) return;

    const waiter = self.gpa.create(FutexWaiter) catch return;
    waiter.* = .{ .ptr = ptr };

    const prom_cls = zjb.global("Promise");
    const exec_fn = zjb.fnHandle("webapi_io_futex_exec", &futexWaitExecutor);
    const w_ptr: JsPtrInt = @bitCast(@intFromPtr(waiter));
    const bound = exec_fn.call("bind", .{ zjb.Handle.null, w_ptr }, zjb.Handle);
    defer bound.release();

    const p_h = prom_cls.new(.{bound});
    if (p_h.isNull()) {
        waiter.deinit(self.gpa);
        return;
    }
    const p = Promise.fromHandle(p_h);
    defer p.release();

    if (timeout.toDurationFromNow(self.io())) |dur| {
        const ms_i64 = @max(@as(i64, 0), dur.raw.toMilliseconds());
        const ms: i32 = @intCast(@min(ms_i64, std.math.maxInt(i32)));
        waiter.timeout_id = webapi.dom.window().setTimeout(
            FutexWaiter,
            waiter,
            FutexWaiter.onTimeout,
            ms,
        );
    }

    self.futex_waiters.append(self.gpa, waiter) catch {
        waiter.deinit(self.gpa);
        return;
    };
    _ = self.awaitPromise(p);

    for (self.futex_waiters.items, 0..) |item, i| {
        if (item == waiter) {
            _ = self.futex_waiters.orderedRemove(i);
            break;
        }
    }
    waiter.deinit(self.gpa);
}

fn ioFutexWait(
    userdata: ?*anyopaque,
    ptr: *const u32,
    expected: u32,
    timeout: Io.Timeout,
) Io.Cancelable!void {
    try ioCheckCancel(userdata);
    const self = fromUserdata(userdata);
    self.futexWaitInternal(ptr, expected, timeout);
}

fn ioFutexWaitUncancelable(
    userdata: ?*anyopaque,
    ptr: *const u32,
    expected: u32,
) void {
    const self = fromUserdata(userdata);
    self.futexWaitInternal(ptr, expected, .none);
}

fn ioFutexWake(
    userdata: ?*anyopaque,
    ptr: *const u32,
    max_waiters: u32,
) void {
    const self = fromUserdata(userdata);
    var woken: u32 = 0;
    var i: usize = 0;
    while (i < self.futex_waiters.items.len and woken < max_waiters) {
        const w = self.futex_waiters.items[i];
        if (w.ptr == ptr and !w.woken) {
            _ = self.futex_waiters.orderedRemove(i);
            w.wake();
            woken += 1;
        } else {
            i += 1;
        }
    }
}

// =========================================================================
// Unified `operate` & `Batch`
// =========================================================================

fn ioOperate(
    userdata: ?*anyopaque,
    operation: Io.Operation,
) Io.Cancelable!Io.Operation.Result {
    try ioCheckCancel(userdata);
    const self = fromUserdata(userdata);
    return switch (operation) {
        .file_read_streaming => |op| .{
            .file_read_streaming = self.fileReadStreamingImpl(op),
        },
        .file_write_streaming => |op| .{
            .file_write_streaming = self.fileWriteStreamingImpl(op),
        },
        .device_io_control => failing.operate(userdata, operation),
        .net_read => |op| .{
            .net_read = self.netReadImpl(op),
        },
        .net_write => |op| .{
            .net_write = self.netWriteImpl(op),
        },
        .net_receive => .{ .net_receive = .{ error.NetworkDown, 0 } },
        .net_send => .{ .net_send = .{ error.NetworkDown, 0 } },
    };
}

fn runSubmittedBatch(self: *WebApiIo, batch: *Io.Batch) Io.Cancelable!void {
    var index = batch.submitted.head;
    batch.submitted = .empty;
    while (index != .none) {
        const idx = index.toIndex();
        const sub = batch.storage[idx].submission;
        index = sub.node.next;

        const res = try ioOperate(@ptrCast(self), sub.operation);
        switch (batch.completed.tail) {
            .none => batch.completed.head = .fromIndex(idx),
            else => |tail_idx| {
                batch.storage[tail_idx.toIndex()].completion.node.next =
                    .fromIndex(idx);
            },
        }
        batch.storage[idx] = .{
            .completion = .{ .node = .{ .next = .none }, .result = res },
        };
        batch.completed.tail = .fromIndex(idx);
    }
}

fn ioBatchAwaitAsync(
    userdata: ?*anyopaque,
    batch: *Io.Batch,
) Io.Cancelable!void {
    const self = fromUserdata(userdata);
    try self.runSubmittedBatch(batch);
}

fn ioBatchAwaitConcurrent(
    userdata: ?*anyopaque,
    batch: *Io.Batch,
    timeout: Io.Timeout,
) Io.Batch.AwaitConcurrentError!void {
    _ = timeout;
    const self = fromUserdata(userdata);
    try self.runSubmittedBatch(batch);
}

fn ioBatchCancel(userdata: ?*anyopaque, batch: *Io.Batch) void {
    _ = userdata;
    batch.pending = .empty;
    batch.userdata = null;
}

// =========================================================================
// IndexedDB-backed Virtual Filesystem (`Dir` + `File`)
// =========================================================================

fn cwdSlice(self: *const WebApiIo) []const u8 {
    return self.cwd_buf[0..self.cwd_len];
}

fn setCwdInternal(self: *WebApiIo, raw_path: []const u8) !void {
    const norm = try self.fs.normalizePath(raw_path);
    defer self.fs.allocator.free(norm);
    if (norm.len > self.cwd_buf.len) return error.NameTooLong;
    @memcpy(self.cwd_buf[0..norm.len], norm);
    self.cwd_len = @intCast(norm.len);
}

fn makeDirFromFd(self: *WebApiIo, fd: i32) Dir {
    if (Dir.Handle == void) {
        if (self.void_dir_len < MAX_VOID_HANDLES) {
            self.void_dir_fds[self.void_dir_len] = fd;
            self.void_dir_len += 1;
        }
        return .{ .handle = {} };
    }
    return .{ .handle = @intCast(fd) };
}

fn makeFileFromFd(self: *WebApiIo, fd: i32, nonblocking: bool) File {
    if (File.Handle == void) {
        if (self.void_file_len < MAX_VOID_HANDLES) {
            self.void_file_fds[self.void_file_len] = fd;
            self.void_file_len += 1;
        }
        return .{ .handle = {}, .flags = .{ .nonblocking = nonblocking } };
    }
    return .{
        .handle = @intCast(fd),
        .flags = .{ .nonblocking = nonblocking },
    };
}

fn resolveDirFd(self: *const WebApiIo, dir: Dir) i32 {
    if (Dir.Handle == void) {
        if (self.void_dir_len > 0) {
            return self.void_dir_fds[self.void_dir_len - 1];
        }
        return CWD_SENTINEL_FD;
    }
    if (@TypeOf(dir.handle) == isize or @TypeOf(dir.handle) == i32) {
        return @intCast(dir.handle);
    }
    return CWD_SENTINEL_FD;
}

fn resolveFileFd(self: *const WebApiIo, file: File) i32 {
    if (File.Handle == void) {
        if (self.void_file_len > 0) {
            return self.void_file_fds[self.void_file_len - 1];
        }
        return -1;
    }
    if (@TypeOf(file.handle) == isize or @TypeOf(file.handle) == i32) {
        return @intCast(file.handle);
    }
    return -1;
}

fn getDirBasePath(self: *const WebApiIo, dir: Dir) ?[]const u8 {
    const fd = self.resolveDirFd(dir);
    if (fd < 0 or fd == CWD_SENTINEL_FD) {
        return self.cwdSlice();
    }
    if (self.fs.fds.get(fd)) |of| {
        if (!of.is_dir) return null;
        return of.path;
    }
    return null;
}

fn resolveSubPath(
    self: *WebApiIo,
    dir: Dir,
    sub_path: []const u8,
) error{
    BadPathName,
    NameTooLong,
    NotDir,
    FileNotFound,
    SystemResources,
}![]u8 {
    if (sub_path.len == 0) return error.BadPathName;
    if (std.mem.indexOfScalar(u8, sub_path, 0) != null) {
        return error.BadPathName;
    }
    if (sub_path.len >= MAX_PATH_BYTES) return error.NameTooLong;

    if (sub_path[0] == '/') {
        return self.fs.normalizePath(sub_path) catch error.SystemResources;
    }
    const base = self.getDirBasePath(dir) orelse return error.FileNotFound;
    const joined = std.fs.path.join(self.gpa, &.{ base, sub_path }) catch {
        return error.SystemResources;
    };
    defer self.gpa.free(joined);
    if (joined.len >= MAX_PATH_BYTES) return error.NameTooLong;
    return self.fs.normalizePath(joined) catch error.SystemResources;
}

fn asyncIdbLookupExec(
    ctx_ptr: JsPtrInt,
    resolve_h: zjb.Handle,
    reject_h: zjb.Handle,
) callconv(.c) void {
    if (!reject_h.isNull()) reject_h.release();
    const ctx: *AsyncIdbLookup = @ptrFromInt(@as(usize, @bitCast(ctx_ptr)));
    ctx.resolve_h = resolve_h;

    const tx = ctx.mount_point.db.transaction(
        ctx.mount_point.store_name,
        .readonly,
    );
    if (tx.isNull()) {
        ctx.finish(.null);
        return;
    }
    defer tx.release();

    const store = tx.objectStore(ctx.mount_point.store_name);
    if (store.isNull()) {
        ctx.finish(.null);
        return;
    }
    defer store.release();

    const key = FileSystem.indexedFsStoreKey(
        ctx.path,
        ctx.mount_point.dir_path,
    ) orelse {
        ctx.finish(.null);
        return;
    };
    const req = store.get(key);
    if (req.isNull()) {
        ctx.finish(.null);
        return;
    }
    ctx.req = req;

    const cb_ok = webapi.boundFunction(
        AsyncIdbLookup,
        ctx,
        AsyncIdbLookup.onSuccess,
    );
    defer cb_ok.release();
    const cb_err = webapi.boundFunction(
        AsyncIdbLookup,
        ctx,
        AsyncIdbLookup.onError,
    );
    defer cb_err.release();
    req.set("onsuccess", cb_ok);
    req.set("onerror", cb_err);
}

fn ensurePathLoaded(self: *WebApiIo, norm: []const u8) ?FileSystem.FileEntry {
    if (self.fs.files.get(norm)) |fe| return fe;
    if (self.fs.checkIndexedFsForRead(norm)) |fe| return fe;

    if (self.canSuspend()) {
        if (!self.fs.areAllIndexedFsMountsReady()) {
            if (self.waitMountsReady() catch null) |ready_p| {
                defer ready_p.release();
                _ = self.awaitPromise(ready_p.promise);
            }
            if (self.fs.files.get(norm)) |fe| return fe;
        }
        if (self.fs.findAsyncIndexedFsMount(norm)) |m| {
            var lookup: AsyncIdbLookup = .{
                .fs = &self.fs,
                .mount_point = m,
                .path = norm,
            };
            const prom_cls = zjb.global("Promise");
            const exec_fn = zjb.fnHandle(
                "webapi_io_idb_get_exec",
                &asyncIdbLookupExec,
            );
            const l_ptr: JsPtrInt = @bitCast(@intFromPtr(&lookup));
            const bound = exec_fn.call(
                "bind",
                .{ zjb.Handle.null, l_ptr },
                zjb.Handle,
            );
            defer bound.release();

            const p_h = prom_cls.new(.{bound});
            if (!p_h.isNull()) {
                const p = Promise.fromHandle(p_h);
                defer p.release();
                _ = self.awaitPromise(p);
            }
            if (!lookup.resolve_h.isNull()) lookup.resolve_h.release();
            return self.fs.files.get(norm);
        }
    }
    return null;
}

fn isKnownDirectory(self: *const WebApiIo, norm: []const u8) bool {
    if (std.mem.eql(u8, norm, "/")) return true;
    if (self.fs.directories.contains(norm)) return true;
    return false;
}

fn checkAncestorsAreDirs(
    self: *const WebApiIo,
    norm: []const u8,
) error{ FileNotFound, NotDir }!void {
    if (std.mem.eql(u8, norm, "/")) return;
    var idx: usize = 1;
    while (idx < norm.len) : (idx += 1) {
        if (norm[idx] == '/') {
            const parent = norm[0..idx];
            if (self.fs.files.contains(parent)) return error.NotDir;
            if (!self.isKnownDirectory(parent)) return error.FileNotFound;
        }
    }
}

fn makeInode(path: []const u8) File.INode {
    if (File.INode == void) return {};
    return @intCast(std.hash.Wyhash.hash(0, path));
}

fn makeNLink() File.NLink {
    if (File.NLink == u0) return 0;
    return 1;
}

fn buildStat(
    path: []const u8,
    kind: File.Kind,
    size: u64,
    mtime_ns: u64,
) File.Stat {
    const ts: Io.Timestamp = .{ .nanoseconds = @intCast(mtime_ns) };
    return .{
        .inode = makeInode(path),
        .nlink = makeNLink(),
        .size = size,
        .permissions = if (kind == .directory) .default_dir else .default_file,
        .kind = kind,
        .atime = ts,
        .mtime = ts,
        .ctime = ts,
        .block_size = 4096,
    };
}

fn allocFd(
    self: *WebApiIo,
    norm_path: []const u8,
    is_dir: bool,
    flags: i32,
    is_write: bool,
    was_written: bool,
) error{SystemResources}!i32 {
    const dup = self.fs.allocator.dupe(u8, norm_path) catch {
        return error.SystemResources;
    };
    const fd = self.fs.next_fd;
    self.fs.next_fd += 1;
    self.fs.fds.put(fd, .{
        .path = dup,
        .is_dir = is_dir,
        .pos = 0,
        .flags = flags,
        .is_write = is_write,
        .was_written = was_written,
    }) catch {
        self.fs.allocator.free(dup);
        return error.SystemResources;
    };
    return fd;
}

fn ioDirCreateDir(
    userdata: ?*anyopaque,
    dir: Dir,
    sub_path: []const u8,
    permissions: Dir.Permissions,
) Dir.CreateDirError!void {
    _ = permissions;
    try ioCheckCancel(userdata);
    const self = fromUserdata(userdata);
    self.ensureFsInitialized() catch return error.SystemResources;

    const norm = try self.resolveSubPath(dir, sub_path);
    defer self.fs.allocator.free(norm);

    try self.checkAncestorsAreDirs(norm);
    if (self.isKnownDirectory(norm) or self.ensurePathLoaded(norm) != null) {
        return error.PathAlreadyExists;
    }

    const dup = self.fs.allocator.dupe(u8, norm) catch {
        return error.SystemResources;
    };
    self.fs.directories.put(dup, {}) catch {
        self.fs.allocator.free(dup);
        return error.SystemResources;
    };
}

fn ioDirCreateDirPath(
    userdata: ?*anyopaque,
    dir: Dir,
    sub_path: []const u8,
    permissions: Dir.Permissions,
) Dir.CreateDirPathError!Dir.CreatePathStatus {
    _ = permissions;
    try ioCheckCancel(userdata);
    const self = fromUserdata(userdata);
    self.ensureFsInitialized() catch return error.SystemResources;

    const norm = try self.resolveSubPath(dir, sub_path);
    defer self.fs.allocator.free(norm);

    if (self.ensurePathLoaded(norm) != null) return error.NotDir;
    if (self.isKnownDirectory(norm)) return .existed;

    var i: usize = 1;
    while (i <= norm.len) : (i += 1) {
        if (i == norm.len or norm[i] == '/') {
            const prefix = norm[0..i];
            if (self.fs.files.contains(prefix)) return error.NotDir;
            if (!self.fs.directories.contains(prefix)) {
                const dup = self.fs.allocator.dupe(u8, prefix) catch {
                    return error.SystemResources;
                };
                self.fs.directories.put(dup, {}) catch {
                    self.fs.allocator.free(dup);
                    return error.SystemResources;
                };
            }
        }
    }
    return .created;
}

fn ioDirCreateDirPathOpen(
    userdata: ?*anyopaque,
    dir: Dir,
    sub_path: []const u8,
    permissions: Dir.Permissions,
    options: Dir.OpenOptions,
) Dir.CreateDirPathOpenError!Dir {
    _ = try ioDirCreateDirPath(userdata, dir, sub_path, permissions);
    return ioDirOpenDir(userdata, dir, sub_path, options);
}

fn ioDirOpenDir(
    userdata: ?*anyopaque,
    dir: Dir,
    sub_path: []const u8,
    options: Dir.OpenOptions,
) Dir.OpenError!Dir {
    _ = options;
    try ioCheckCancel(userdata);
    const self = fromUserdata(userdata);
    self.ensureFsInitialized() catch return error.SystemResources;

    const norm = if (std.mem.eql(u8, sub_path, ".")) blk: {
        const base = self.getDirBasePath(dir) orelse return error.FileNotFound;
        break :blk self.fs.allocator.dupe(u8, base) catch {
            return error.SystemResources;
        };
    } else try self.resolveSubPath(dir, sub_path);
    defer self.fs.allocator.free(norm);

    if (self.ensurePathLoaded(norm) != null) return error.NotDir;
    if (!self.isKnownDirectory(norm)) return error.FileNotFound;

    const fd = try self.allocFd(norm, true, FD_FLAG_READ, false, false);
    return self.makeDirFromFd(fd);
}

fn ioDirStat(userdata: ?*anyopaque, dir: Dir) Dir.StatError!Dir.Stat {
    try ioCheckCancel(userdata);
    const self = fromUserdata(userdata);
    self.ensureFsInitialized() catch return error.SystemResources;

    const base = self.getDirBasePath(dir) orelse return error.AccessDenied;
    return buildStat(base, .directory, 0, self.fs.last_timestamp_ns);
}

fn ioDirStatFile(
    userdata: ?*anyopaque,
    dir: Dir,
    sub_path: []const u8,
    options: Dir.StatFileOptions,
) Dir.StatFileError!File.Stat {
    _ = options;
    try ioCheckCancel(userdata);
    const self = fromUserdata(userdata);
    self.ensureFsInitialized() catch return error.SystemResources;

    const norm = if (std.mem.eql(u8, sub_path, ".")) blk: {
        const base = self.getDirBasePath(dir) orelse return error.FileNotFound;
        break :blk self.fs.allocator.dupe(u8, base) catch {
            return error.SystemResources;
        };
    } else try self.resolveSubPath(dir, sub_path);
    defer self.fs.allocator.free(norm);

    if (self.ensurePathLoaded(norm)) |fe| {
        return buildStat(norm, .file, fe.data.len, fe.mtime);
    }
    if (self.isKnownDirectory(norm)) {
        return buildStat(norm, .directory, 0, self.fs.last_timestamp_ns);
    }
    return error.FileNotFound;
}

fn ioDirAccess(
    userdata: ?*anyopaque,
    dir: Dir,
    sub_path: []const u8,
    options: Dir.AccessOptions,
) Dir.AccessError!void {
    _ = ioDirStatFile(userdata, dir, sub_path, .{
        .follow_symlinks = options.follow_symlinks,
    }) catch |err| switch (err) {
        error.FileNotFound, error.NotDir => return error.FileNotFound,
        error.NameTooLong => return error.NameTooLong,
        error.BadPathName => return error.BadPathName,
        error.Canceled => return error.Canceled,
        else => return error.SystemResources,
    };
}

fn ioDirCreateFile(
    userdata: ?*anyopaque,
    dir: Dir,
    sub_path: []const u8,
    options: Dir.CreateFileOptions,
) File.OpenError!File {
    try ioCheckCancel(userdata);
    const self = fromUserdata(userdata);
    self.ensureFsInitialized() catch return error.SystemResources;

    const norm = try self.resolveSubPath(dir, sub_path);
    defer self.fs.allocator.free(norm);

    try self.checkAncestorsAreDirs(norm);
    if (self.isKnownDirectory(norm)) return error.IsDir;

    const existing = self.ensurePathLoaded(norm);
    if (options.exclusive and existing != null) {
        return error.PathAlreadyExists;
    }

    const should_reset = existing == null or options.truncate;
    if (should_reset) {
        self.fs.writeFile(norm, &.{}) catch return error.SystemResources;
    }

    const flags: i32 = if (options.read) FD_FLAG_READ else 0;
    const fd = try self.allocFd(norm, false, flags, true, should_reset);
    return self.makeFileFromFd(fd, false);
}

fn ioDirCreateFileAtomic(
    userdata: ?*anyopaque,
    dir: Dir,
    sub_path: []const u8,
    options: Dir.CreateFileAtomicOptions,
) Dir.CreateFileAtomicError!File.Atomic {
    try ioCheckCancel(userdata);
    const self = fromUserdata(userdata);
    self.ensureFsInitialized() catch return error.SystemResources;

    const parent_sub = std.fs.path.dirnamePosix(sub_path);
    const basename = std.fs.path.basenamePosix(sub_path);
    if (basename.len == 0) return error.BadPathName;

    var target_dir = dir;
    var close_dir = false;
    if (parent_sub) |ps| {
        if (options.make_path) {
            target_dir = ioDirCreateDirPathOpen(
                userdata,
                dir,
                ps,
                options.permissions,
                .{},
            ) catch |err| switch (err) {
                error.NameTooLong => return error.NameTooLong,
                error.BadPathName => return error.BadPathName,
                error.NotDir => return error.NotDir,
                error.FileNotFound => return error.FileNotFound,
                error.AccessDenied => return error.AccessDenied,
                error.PermissionDenied => return error.PermissionDenied,
                error.NoSpaceLeft => return error.NoSpaceLeft,
                error.Canceled => return error.Canceled,
                else => return error.SystemResources,
            };
        } else {
            target_dir = try ioDirOpenDir(userdata, dir, ps, .{});
        }
        close_dir = true;
    }
    errdefer if (close_dir) ioDirClose(userdata, (&target_dir)[0..1]);

    var rand_val: u64 = 0;
    ioRandom(userdata, std.mem.asBytes(&rand_val));
    const tmp_name = std.fmt.hex(rand_val);
    const file = ioDirCreateFile(userdata, target_dir, &tmp_name, .{
        .truncate = true,
        .exclusive = true,
        .permissions = options.permissions,
    }) catch |err| switch (err) {
        error.NameTooLong => return error.NameTooLong,
        error.BadPathName => return error.BadPathName,
        error.NotDir => return error.NotDir,
        error.FileNotFound => return error.FileNotFound,
        error.AccessDenied => return error.AccessDenied,
        error.PermissionDenied => return error.PermissionDenied,
        error.NoSpaceLeft => return error.NoSpaceLeft,
        error.Canceled => return error.Canceled,
        else => return error.SystemResources,
    };

    return .{
        .file = file,
        .file_basename_hex = rand_val,
        .file_open = true,
        .file_exists = true,
        .dir = target_dir,
        .close_dir_on_deinit = close_dir,
        .dest_sub_path = basename,
    };
}

fn ioDirOpenFile(
    userdata: ?*anyopaque,
    dir: Dir,
    sub_path: []const u8,
    options: Dir.OpenFileOptions,
) File.OpenError!File {
    try ioCheckCancel(userdata);
    const self = fromUserdata(userdata);
    self.ensureFsInitialized() catch return error.SystemResources;

    const norm = try self.resolveSubPath(dir, sub_path);
    defer self.fs.allocator.free(norm);

    try self.checkAncestorsAreDirs(norm);
    if (self.isKnownDirectory(norm)) {
        if (!options.allow_directory or options.isWrite()) return error.IsDir;
        const fd = try self.allocFd(norm, true, FD_FLAG_READ, false, false);
        return self.makeFileFromFd(fd, false);
    }

    if (self.ensurePathLoaded(norm) == null) return error.FileNotFound;
    const flags: i32 = if (options.isRead()) FD_FLAG_READ else 0;
    const fd = try self.allocFd(norm, false, flags, options.isWrite(), false);
    return self.makeFileFromFd(fd, false);
}

fn ioDirClose(userdata: ?*anyopaque, dirs: []const Dir) void {
    const self = fromUserdata(userdata);
    if (!self.fs_initialized) return;

    for (dirs) |d| {
        const fd = if (Dir.Handle == void) blk: {
            if (self.void_dir_len == 0) continue;
            self.void_dir_len -= 1;
            break :blk self.void_dir_fds[self.void_dir_len];
        } else self.resolveDirFd(d);

        if (fd >= FIRST_DYNAMIC_FD) {
            if (self.fs.fds.fetchRemove(fd)) |kv| {
                self.fs.allocator.free(kv.value.path);
            }
        }
    }
}

fn directChildSlice(full_path: []const u8, dir_path: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, full_path, dir_path)) return null;
    const rest = if (std.mem.eql(u8, dir_path, "/")) blk: {
        if (!std.mem.startsWith(u8, full_path, "/")) return null;
        break :blk full_path[1..];
    } else blk: {
        if (!std.mem.startsWith(u8, full_path, dir_path)) return null;
        if (full_path.len <= dir_path.len or full_path[dir_path.len] != '/') {
            return null;
        }
        break :blk full_path[dir_path.len + 1 ..];
    };
    if (rest.len == 0) return null;
    if (std.mem.indexOfScalar(u8, rest, '/') != null) return null;
    return rest;
}

fn ioDirRead(
    userdata: ?*anyopaque,
    reader: *Dir.Reader,
    out_entries: []Dir.Entry,
) Dir.Reader.Error!usize {
    try ioCheckCancel(userdata);
    const self = fromUserdata(userdata);
    self.ensureFsInitialized() catch return error.SystemResources;

    if (reader.state == .finished) return 0;
    if (reader.state == .reset) {
        reader.index = 0;
        reader.end = 0;
        reader.state = .reading;
    }
    if (out_entries.len == 0) return 0;

    const dir_path = self.getDirBasePath(reader.dir) orelse {
        return error.AccessDenied;
    };

    const ChildItem = struct {
        name: []const u8,
        full_path: []const u8,
        kind: File.Kind,
    };
    var children: std.ArrayList(ChildItem) = .empty;
    defer children.deinit(self.gpa);

    var dit = self.fs.directories.iterator();
    while (dit.next()) |kv| {
        if (directChildSlice(kv.key_ptr.*, dir_path)) |child_name| {
            children.append(self.gpa, .{
                .name = child_name,
                .full_path = kv.key_ptr.*,
                .kind = .directory,
            }) catch return error.SystemResources;
        }
    }

    var fit = self.fs.files.iterator();
    while (fit.next()) |kv| {
        if (directChildSlice(kv.key_ptr.*, dir_path)) |child_name| {
            children.append(self.gpa, .{
                .name = child_name,
                .full_path = kv.key_ptr.*,
                .kind = .file,
            }) catch return error.SystemResources;
        }
    }

    std.mem.sort(ChildItem, children.items, {}, struct {
        fn less(_: void, a: ChildItem, b: ChildItem) bool {
            return std.mem.order(u8, a.name, b.name) == .lt;
        }
    }.less);

    var emitted: usize = 0;
    var buf_used: usize = 0;
    while (reader.index < children.items.len and emitted < out_entries.len) {
        const item = children.items[reader.index];
        if (buf_used + item.name.len > reader.buffer.len) {
            if (emitted == 0) return error.SystemResources;
            break;
        }
        const name_dst = reader.buffer[buf_used .. buf_used + item.name.len];
        @memcpy(name_dst, item.name);
        buf_used += item.name.len;

        out_entries[emitted] = .{
            .name = name_dst,
            .kind = item.kind,
            .inode = makeInode(item.full_path),
        };
        emitted += 1;
        reader.index += 1;
    }

    if (reader.index >= children.items.len) {
        reader.state = .finished;
    }
    return emitted;
}

fn ioDirRealPath(
    userdata: ?*anyopaque,
    dir: Dir,
    out_buffer: []u8,
) Dir.RealPathError!usize {
    try ioCheckCancel(userdata);
    const self = fromUserdata(userdata);
    self.ensureFsInitialized() catch return error.SystemResources;

    const base = self.getDirBasePath(dir) orelse return error.FileNotFound;
    if (out_buffer.len < base.len) return error.NameTooLong;
    @memcpy(out_buffer[0..base.len], base);
    return base.len;
}

fn ioDirRealPathFile(
    userdata: ?*anyopaque,
    dir: Dir,
    path_name: []const u8,
    out_buffer: []u8,
) Dir.RealPathFileError!usize {
    try ioCheckCancel(userdata);
    const self = fromUserdata(userdata);
    self.ensureFsInitialized() catch return error.SystemResources;

    const norm = try self.resolveSubPath(dir, path_name);
    defer self.fs.allocator.free(norm);

    if (self.ensurePathLoaded(norm) == null and !self.isKnownDirectory(norm)) {
        return error.FileNotFound;
    }
    if (out_buffer.len < norm.len) return error.NameTooLong;
    @memcpy(out_buffer[0..norm.len], norm);
    return norm.len;
}

fn ioDirDeleteFile(
    userdata: ?*anyopaque,
    dir: Dir,
    sub_path: []const u8,
) Dir.DeleteFileError!void {
    try ioCheckCancel(userdata);
    const self = fromUserdata(userdata);
    self.ensureFsInitialized() catch return error.SystemResources;

    const norm = try self.resolveSubPath(dir, sub_path);
    defer self.fs.allocator.free(norm);

    if (self.isKnownDirectory(norm)) return error.IsDir;
    const existed = self.ensurePathLoaded(norm) != null;
    const removed = self.fs.removeFile(norm);
    self.fs.removeIndexedFsEntry(norm);
    if (!existed and !removed) return error.FileNotFound;
}

fn hasChildrenUnder(self: *const WebApiIo, dir_norm: []const u8) bool {
    var fit = self.fs.files.iterator();
    while (fit.next()) |kv| {
        if (directChildSlice(kv.key_ptr.*, dir_norm) != null) return true;
    }
    var dit = self.fs.directories.iterator();
    while (dit.next()) |kv| {
        if (directChildSlice(kv.key_ptr.*, dir_norm) != null) return true;
    }
    return false;
}

fn ioDirDeleteDir(
    userdata: ?*anyopaque,
    dir: Dir,
    sub_path: []const u8,
) Dir.DeleteDirError!void {
    try ioCheckCancel(userdata);
    const self = fromUserdata(userdata);
    self.ensureFsInitialized() catch return error.SystemResources;

    const norm = try self.resolveSubPath(dir, sub_path);
    defer self.fs.allocator.free(norm);

    if (self.fs.isPreopenOrRoot(norm)) return error.AccessDenied;
    if (self.ensurePathLoaded(norm) != null) return error.NotDir;
    if (!self.fs.directories.contains(norm)) return error.FileNotFound;
    if (self.hasChildrenUnder(norm)) return error.DirNotEmpty;

    if (self.fs.directories.fetchRemove(norm)) |old| {
        self.fs.allocator.free(old.key);
    }
}

fn renameImpl(
    userdata: ?*anyopaque,
    old_dir: Dir,
    old_sub_path: []const u8,
    new_dir: Dir,
    new_sub_path: []const u8,
    preserve: bool,
) !void {
    try ioCheckCancel(userdata);
    const self = fromUserdata(userdata);
    self.ensureFsInitialized() catch return error.SystemResources;

    const old_norm = try self.resolveSubPath(old_dir, old_sub_path);
    defer self.fs.allocator.free(old_norm);
    const new_norm = try self.resolveSubPath(new_dir, new_sub_path);
    defer self.fs.allocator.free(new_norm);

    try self.checkAncestorsAreDirs(new_norm);

    if (preserve) {
        if (self.ensurePathLoaded(new_norm) != null or
            self.isKnownDirectory(new_norm))
        {
            return error.PathAlreadyExists;
        }
    }

    if (std.mem.eql(u8, old_norm, new_norm)) {
        if (self.ensurePathLoaded(old_norm) == null and
            !self.isKnownDirectory(old_norm))
        {
            return error.FileNotFound;
        }
        return;
    }

    if (self.ensurePathLoaded(old_norm) != null) {
        if (self.isKnownDirectory(new_norm)) return error.IsDir;
        if (self.fs.files.fetchRemove(old_norm)) |entry| {
            self.fs.removeIndexedFsEntry(old_norm);
            const dup_key = self.fs.allocator.dupe(u8, new_norm) catch {
                self.fs.allocator.free(entry.key);
                self.fs.allocator.free(entry.value.data);
                return error.SystemResources;
            };
            self.fs.allocator.free(entry.key);
            if (self.fs.files.fetchPut(dup_key, entry.value) catch {
                self.fs.allocator.free(dup_key);
                self.fs.allocator.free(entry.value.data);
                return error.SystemResources;
            }) |replaced| {
                self.fs.allocator.free(replaced.key);
                self.fs.allocator.free(replaced.value.data);
            }
            self.fs.unmarkPathChecked(new_norm);
            self.fs.saveIndexedFsOnClose(new_norm);
            return;
        }
    }

    if (self.fs.directories.fetchRemove(old_norm)) |old_d| {
        self.fs.allocator.free(old_d.key);
        const dup_d = self.fs.allocator.dupe(u8, new_norm) catch {
            return error.SystemResources;
        };
        if (self.fs.directories.fetchPut(dup_d, {}) catch {
            self.fs.allocator.free(dup_d);
            return error.SystemResources;
        }) |replaced| {
            self.fs.allocator.free(replaced.key);
        }
        return;
    }

    return error.FileNotFound;
}

fn ioDirRename(
    userdata: ?*anyopaque,
    old_dir: Dir,
    old_sub_path: []const u8,
    new_dir: Dir,
    new_sub_path: []const u8,
) Dir.RenameError!void {
    renameImpl(
        userdata,
        old_dir,
        old_sub_path,
        new_dir,
        new_sub_path,
        false,
    ) catch |err| switch (err) {
        error.PathAlreadyExists => unreachable,
        else => |e| return e,
    };
}

fn ioDirRenamePreserve(
    userdata: ?*anyopaque,
    old_dir: Dir,
    old_sub_path: []const u8,
    new_dir: Dir,
    new_sub_path: []const u8,
) Dir.RenamePreserveError!void {
    try renameImpl(
        userdata,
        old_dir,
        old_sub_path,
        new_dir,
        new_sub_path,
        true,
    );
}

fn resolveTimestampNs(self: *WebApiIo, spec: File.SetTimestamp, prev: u64) u64 {
    return switch (spec) {
        .unchanged => prev,
        .now => @intCast(
            @max(@as(i96, 0), ioNow(@ptrCast(self), .real).nanoseconds),
        ),
        .new => |ts| @intCast(@max(@as(i96, 0), ts.nanoseconds)),
    };
}

fn ioDirSetTimestamps(
    userdata: ?*anyopaque,
    dir: Dir,
    sub_path: []const u8,
    options: Dir.SetTimestampsOptions,
) Dir.SetTimestampsError!void {
    try ioCheckCancel(userdata);
    const self = fromUserdata(userdata);
    self.ensureFsInitialized() catch return error.AccessDenied;

    const norm = self.resolveSubPath(dir, sub_path) catch |err| switch (err) {
        error.NameTooLong => return error.NameTooLong,
        error.BadPathName => return error.BadPathName,
        else => return error.AccessDenied,
    };
    defer self.fs.allocator.free(norm);

    _ = self.ensurePathLoaded(norm);
    if (self.fs.files.getPtr(norm)) |fe| {
        fe.mtime = self.resolveTimestampNs(options.modify_timestamp, fe.mtime);
        self.fs.saveIndexedFsOnClose(norm);
    }
}

fn ioFileStat(userdata: ?*anyopaque, file: File) File.StatError!File.Stat {
    try ioCheckCancel(userdata);
    const self = fromUserdata(userdata);
    self.ensureFsInitialized() catch return error.SystemResources;

    const fd = self.resolveFileFd(file);
    if (fd >= 0 and fd <= FileSystem.STDERR_FILENO) return error.Streaming;
    const of = self.fs.fds.get(fd) orelse return error.AccessDenied;
    if (of.is_dir) {
        return buildStat(of.path, .directory, 0, self.fs.last_timestamp_ns);
    }
    const fe = self.fs.files.get(of.path) orelse return error.AccessDenied;
    return buildStat(of.path, .file, fe.data.len, fe.mtime);
}

fn ioFileLength(userdata: ?*anyopaque, file: File) File.LengthError!u64 {
    return (try ioFileStat(userdata, file)).size;
}

fn ioFileClose(userdata: ?*anyopaque, files: []const File) void {
    const self = fromUserdata(userdata);
    if (!self.fs_initialized) return;

    for (files) |f| {
        const fd = if (File.Handle == void) blk: {
            if (self.void_file_len == 0) continue;
            self.void_file_len -= 1;
            break :blk self.void_file_fds[self.void_file_len];
        } else self.resolveFileFd(f);

        if (fd >= FIRST_DYNAMIC_FD) {
            if (self.fs.fds.fetchRemove(fd)) |kv| {
                if (!kv.value.is_dir and kv.value.was_written) {
                    self.fs.saveIndexedFsOnClose(kv.value.path);
                }
                self.fs.allocator.free(kv.value.path);
            }
        }
    }
}

fn writeSliceAtOffset(
    self: *WebApiIo,
    path: []const u8,
    offset: u64,
    bytes: []const u8,
) error{ SystemResources, FileTooBig }!void {
    if (bytes.len == 0) return;
    const start = std.math.cast(usize, offset) orelse return error.FileTooBig;
    const end = std.math.add(usize, start, bytes.len) catch {
        return error.FileTooBig;
    };

    if (self.fs.files.getPtr(path)) |fe| {
        if (end > fe.data.len) {
            const old_len = fe.data.len;
            const grown = self.fs.allocator.realloc(fe.data, end) catch {
                return error.SystemResources;
            };
            if (start > old_len) {
                @memset(grown[old_len..start], 0);
            }
            fe.data = grown;
        }
        @memcpy(fe.data[start..end], bytes);
        fe.mtime = self.fs.nextTimestampNs();
    } else {
        const buf = self.fs.allocator.alloc(u8, end) catch {
            return error.SystemResources;
        };
        errdefer self.fs.allocator.free(buf);
        if (start > 0) @memset(buf[0..start], 0);
        @memcpy(buf[start..end], bytes);
        self.fs.putFileOwnedWithMtime(
            path,
            buf,
            self.fs.nextTimestampNs(),
        ) catch return error.SystemResources;
    }
}

fn writeVectoredToFile(
    self: *WebApiIo,
    path: []const u8,
    start_offset: u64,
    header: []const u8,
    data: []const []const u8,
    splat: usize,
) error{ SystemResources, FileTooBig }!usize {
    var cursor = start_offset;
    var written: usize = 0;

    if (header.len > 0) {
        try self.writeSliceAtOffset(path, cursor, header);
        cursor += header.len;
        written += header.len;
    }
    if (data.len > 0) {
        for (data[0 .. data.len - 1]) |seg| {
            if (seg.len > 0) {
                try self.writeSliceAtOffset(path, cursor, seg);
                cursor += seg.len;
                written += seg.len;
            }
        }
        const tail = data[data.len - 1];
        if (tail.len > 0 and splat > 0) {
            for (0..splat) |_| {
                try self.writeSliceAtOffset(path, cursor, tail);
                cursor += tail.len;
                written += tail.len;
            }
        }
    }
    return written;
}

fn ioFileWritePositional(
    userdata: ?*anyopaque,
    file: File,
    header: []const u8,
    data: []const []const u8,
    splat: usize,
    offset: u64,
) File.WritePositionalError!usize {
    try ioCheckCancel(userdata);
    const self = fromUserdata(userdata);
    self.ensureFsInitialized() catch return error.SystemResources;

    const fd = self.resolveFileFd(file);
    if (fd >= 0 and fd <= FileSystem.STDERR_FILENO) return error.Unseekable;
    const of = self.fs.fds.getPtr(fd) orelse return error.AccessDenied;
    if (of.is_dir or !of.is_write) return error.NotOpenForWriting;

    const n = try self.writeVectoredToFile(
        of.path,
        offset,
        header,
        data,
        splat,
    );
    if (n > 0) of.was_written = true;
    return n;
}

fn fileWriteStreamingImpl(
    self: *WebApiIo,
    op: Io.Operation.FileWriteStreaming,
) Io.Operation.FileWriteStreaming.Error!usize {
    self.ensureFsInitialized() catch return error.SystemResources;
    const fd = self.resolveFileFd(op.file);
    if (fd == FileSystem.STDIN_FILENO) return error.NotOpenForWriting;
    if (fd == FileSystem.STDOUT_FILENO or fd == FileSystem.STDERR_FILENO) {
        var total: usize = op.header.len;
        if (op.data.len > 0) {
            for (op.data[0 .. op.data.len - 1]) |seg| total += seg.len;
            total += op.data[op.data.len - 1].len * op.splat;
        }
        return total;
    }

    const of = self.fs.fds.getPtr(fd) orelse return error.AccessDenied;
    if (of.is_dir or !of.is_write) return error.NotOpenForWriting;

    const n = try self.writeVectoredToFile(
        of.path,
        of.pos,
        op.header,
        op.data,
        op.splat,
    );
    of.pos += n;
    if (n > 0) of.was_written = true;
    return n;
}

fn readVectoredAt(
    file_bytes: []const u8,
    start_offset: u64,
    buffers: []const []u8,
) struct { read: usize, had_space: bool } {
    var total_space: usize = 0;
    for (buffers) |b| total_space += b.len;
    if (total_space == 0) return .{ .read = 0, .had_space = false };

    const start = std.math.cast(usize, start_offset) orelse {
        return .{ .read = 0, .had_space = true };
    };
    if (start >= file_bytes.len) return .{ .read = 0, .had_space = true };

    var cursor = start;
    var copied: usize = 0;
    for (buffers) |dst| {
        if (cursor >= file_bytes.len) break;
        const avail = file_bytes.len - cursor;
        const n = @min(dst.len, avail);
        if (n > 0) {
            @memcpy(dst[0..n], file_bytes[cursor .. cursor + n]);
            cursor += n;
            copied += n;
        }
    }
    return .{ .read = copied, .had_space = true };
}

fn ioFileReadPositional(
    userdata: ?*anyopaque,
    file: File,
    data: []const []u8,
    offset: u64,
) File.ReadPositionalError!usize {
    try ioCheckCancel(userdata);
    const self = fromUserdata(userdata);
    self.ensureFsInitialized() catch return error.SystemResources;

    const fd = self.resolveFileFd(file);
    if (fd >= 0 and fd <= FileSystem.STDERR_FILENO) return error.Unseekable;
    const of = self.fs.fds.get(fd) orelse return error.AccessDenied;
    if (of.is_dir) return error.IsDir;
    if ((of.flags & FD_FLAG_READ) == 0) return error.NotOpenForReading;

    const fe = self.fs.files.get(of.path) orelse return error.InputOutput;
    return readVectoredAt(fe.data, offset, data).read;
}

fn fileReadStreamingImpl(
    self: *WebApiIo,
    op: Io.Operation.FileReadStreaming,
) Io.Operation.FileReadStreaming.Error!usize {
    self.ensureFsInitialized() catch return error.SystemResources;
    const fd = self.resolveFileFd(op.file);
    if (fd == FileSystem.STDIN_FILENO) return error.EndOfStream;
    if (fd == FileSystem.STDOUT_FILENO or fd == FileSystem.STDERR_FILENO) {
        return error.NotOpenForReading;
    }

    const of = self.fs.fds.getPtr(fd) orelse return error.AccessDenied;
    if (of.is_dir) return error.IsDir;
    if ((of.flags & FD_FLAG_READ) == 0) return error.NotOpenForReading;

    const fe = self.fs.files.get(of.path) orelse return error.InputOutput;
    const outcome = readVectoredAt(fe.data, of.pos, op.data);
    if (!outcome.had_space) return 0;
    if (outcome.read == 0) return error.EndOfStream;
    of.pos += outcome.read;
    return outcome.read;
}

fn ioFileSeekBy(
    userdata: ?*anyopaque,
    file: File,
    relative_offset: i64,
) File.SeekError!void {
    try ioCheckCancel(userdata);
    const self = fromUserdata(userdata);
    self.ensureFsInitialized() catch return error.Unexpected;

    const fd = self.resolveFileFd(file);
    const of = self.fs.fds.getPtr(fd) orelse return error.AccessDenied;
    if (of.is_dir) return error.Unseekable;

    const cur: i128 = @intCast(of.pos);
    const next = cur + @as(i128, relative_offset);
    if (next < 0 or next > std.math.maxInt(u64)) return error.Unseekable;
    of.pos = @intCast(next);
}

fn ioFileSeekTo(
    userdata: ?*anyopaque,
    file: File,
    absolute_offset: u64,
) File.SeekError!void {
    try ioCheckCancel(userdata);
    const self = fromUserdata(userdata);
    self.ensureFsInitialized() catch return error.Unexpected;

    const fd = self.resolveFileFd(file);
    const of = self.fs.fds.getPtr(fd) orelse return error.AccessDenied;
    if (of.is_dir) return error.Unseekable;
    of.pos = absolute_offset;
}

fn ioFileSync(userdata: ?*anyopaque, file: File) File.SyncError!void {
    try ioCheckCancel(userdata);
    const self = fromUserdata(userdata);
    if (!self.fs_initialized) return;

    const fd = self.resolveFileFd(file);
    const of = self.fs.fds.getPtr(fd) orelse return error.AccessDenied;
    if (!of.is_dir and of.was_written) {
        self.fs.saveIndexedFsOnClose(of.path);
    }
}

fn ioFileIsTty(userdata: ?*anyopaque, file: File) Io.Cancelable!bool {
    _ = file;
    try ioCheckCancel(userdata);
    return false;
}

fn ioFileEnableAnsiEscapeCodes(
    userdata: ?*anyopaque,
    file: File,
) File.EnableAnsiEscapeCodesError!void {
    _ = file;
    try ioCheckCancel(userdata);
    return error.NotTerminalDevice;
}

fn ioFileSupportsAnsiEscapeCodes(
    userdata: ?*anyopaque,
    file: File,
) Io.Cancelable!bool {
    _ = file;
    try ioCheckCancel(userdata);
    return false;
}

fn ioFileSetLength(
    userdata: ?*anyopaque,
    file: File,
    new_length: u64,
) File.SetLengthError!void {
    try ioCheckCancel(userdata);
    const self = fromUserdata(userdata);
    self.ensureFsInitialized() catch return error.AccessDenied;

    const fd = self.resolveFileFd(file);
    const of = self.fs.fds.getPtr(fd) orelse return error.AccessDenied;
    if (of.is_dir or !of.is_write) return error.AccessDenied;

    const target_len = std.math.cast(usize, new_length) orelse {
        return error.FileTooBig;
    };
    const fe = self.fs.files.getPtr(of.path) orelse return error.InputOutput;
    const old_len = fe.data.len;
    const resized = self.fs.allocator.realloc(fe.data, target_len) catch {
        return error.InputOutput;
    };
    if (target_len > old_len) {
        @memset(resized[old_len..target_len], 0);
    }
    fe.data = resized;
    fe.mtime = self.fs.nextTimestampNs();
    of.was_written = true;
}

fn ioFileSetTimestamps(
    userdata: ?*anyopaque,
    file: File,
    options: File.SetTimestampsOptions,
) File.SetTimestampsError!void {
    try ioCheckCancel(userdata);
    const self = fromUserdata(userdata);
    self.ensureFsInitialized() catch return error.AccessDenied;

    const fd = self.resolveFileFd(file);
    const of = self.fs.fds.getPtr(fd) orelse return error.AccessDenied;
    if (self.fs.files.getPtr(of.path)) |fe| {
        fe.mtime = self.resolveTimestampNs(options.modify_timestamp, fe.mtime);
        of.was_written = true;
    }
}

fn ioFileRealPath(
    userdata: ?*anyopaque,
    file: File,
    out_buffer: []u8,
) File.RealPathError!usize {
    try ioCheckCancel(userdata);
    const self = fromUserdata(userdata);
    self.ensureFsInitialized() catch return error.SystemResources;

    const fd = self.resolveFileFd(file);
    const of = self.fs.fds.get(fd) orelse return error.FileNotFound;
    if (out_buffer.len < of.path.len) return error.NameTooLong;
    @memcpy(out_buffer[0..of.path.len], of.path);
    return of.path.len;
}

// =========================================================================
// Process Working Directory, Clocks, Sleep, and Web Crypto CSPRNG
// =========================================================================

fn ioProcessCurrentPath(
    userdata: ?*anyopaque,
    buffer: []u8,
) std.process.CurrentPathError!usize {
    try ioCheckCancel(userdata);
    const self = fromUserdata(userdata);
    const cwd = self.cwdSlice();
    if (buffer.len < cwd.len) return error.NameTooLong;
    @memcpy(buffer[0..cwd.len], cwd);
    return cwd.len;
}

fn ioProcessSetCurrentDir(
    userdata: ?*anyopaque,
    dir: Dir,
) std.process.SetCurrentDirError!void {
    try ioCheckCancel(userdata);
    const self = fromUserdata(userdata);
    self.ensureFsInitialized() catch return error.Unexpected;

    const base = self.getDirBasePath(dir) orelse return error.FileNotFound;
    if (base.len > self.cwd_buf.len) return error.Unexpected;
    @memcpy(self.cwd_buf[0..base.len], base);
    self.cwd_len = @intCast(base.len);
}

fn ioProcessSetCurrentPath(
    userdata: ?*anyopaque,
    path: []const u8,
) std.process.SetCurrentPathError!void {
    try ioCheckCancel(userdata);
    const self = fromUserdata(userdata);
    self.ensureFsInitialized() catch return error.SystemResources;

    const norm = self.resolveSubPath(
        freestandingCwd(),
        path,
    ) catch |err| switch (err) {
        error.NameTooLong => return error.NameTooLong,
        error.BadPathName => return error.BadPathName,
        error.NotDir => return error.NotDir,
        error.FileNotFound => return error.FileNotFound,
        error.SystemResources => return error.SystemResources,
    };
    defer self.fs.allocator.free(norm);

    if (self.ensurePathLoaded(norm) != null) return error.NotDir;
    if (!self.isKnownDirectory(norm)) return error.FileNotFound;

    @memcpy(self.cwd_buf[0..norm.len], norm);
    self.cwd_len = @intCast(norm.len);
}

fn ioNow(userdata: ?*anyopaque, clock: Io.Clock) Io.Timestamp {
    _ = clock;
    const self = fromUserdata(userdata);
    const now_ms = webapi.Date.now();
    const base_ns: i96 = if (now_ms > 0.0 and std.math.isFinite(now_ms))
        @intFromFloat(now_ms * 1_000_000.0)
    else
        1_700_000_000_000_000_000;
    return .{ .nanoseconds = base_ns + self.virtual_clock_offset_ns };
}

fn ioClockResolution(
    userdata: ?*anyopaque,
    clock: Io.Clock,
) Io.Clock.ResolutionError!Io.Duration {
    _ = userdata;
    _ = clock;
    return .fromMicroseconds(1);
}

fn sleepTimerExecutor(
    ctx_ptr: JsPtrInt,
    resolve_h: zjb.Handle,
    reject_h: zjb.Handle,
) callconv(.c) void {
    if (!reject_h.isNull()) reject_h.release();
    const timer: *SleepTimer = @ptrFromInt(@as(usize, @bitCast(ctx_ptr)));
    timer.resolve_h = resolve_h;
}

fn ioSleep(userdata: ?*anyopaque, timeout: Io.Timeout) Io.Cancelable!void {
    try ioCheckCancel(userdata);
    const self = fromUserdata(userdata);

    const dur = timeout.toDurationFromNow(self.io()) orelse return;
    if (dur.raw.nanoseconds <= 0) return;

    if (self.canSuspend()) {
        var timer: SleepTimer = .{};
        const prom_cls = zjb.global("Promise");
        const exec_fn = zjb.fnHandle(
            "webapi_io_sleep_exec",
            &sleepTimerExecutor,
        );
        const t_ptr: JsPtrInt = @bitCast(@intFromPtr(&timer));
        const bound = exec_fn.call(
            "bind",
            .{ zjb.Handle.null, t_ptr },
            zjb.Handle,
        );
        defer bound.release();

        const p_h = prom_cls.new(.{bound});
        if (!p_h.isNull()) {
            const p = Promise.fromHandle(p_h);
            defer p.release();
            const ms_i64 = @max(@as(i64, 1), dur.raw.toMilliseconds());
            const ms: i32 = @intCast(@min(ms_i64, std.math.maxInt(i32)));
            _ = webapi.dom.window().setTimeout(
                SleepTimer,
                &timer,
                SleepTimer.onFire,
                ms,
            );
            _ = self.awaitPromise(p);
        }
        if (!timer.resolve_h.isNull()) timer.resolve_h.release();
        return;
    }

    self.virtual_clock_offset_ns += dur.raw.nanoseconds;
}

fn fillFallbackEntropy(self: *WebApiIo, buffer: []u8) void {
    var rng = std.Random.DefaultPrng.init(self.prng_counter);
    self.prng_counter +%= 0x9E37_79B9_7F4A_7C15 +% @as(u64, buffer.len);
    rng.random().bytes(buffer);
}

fn ioRandom(userdata: ?*anyopaque, buffer: []u8) void {
    if (buffer.len == 0) return;
    const self = fromUserdata(userdata);
    self.fillFallbackEntropy(buffer);
    webapi.Crypto.global().getRandomValues(buffer);
}

fn ioRandomSecure(
    userdata: ?*anyopaque,
    buffer: []u8,
) Io.RandomSecureError!void {
    try ioCheckCancel(userdata);
    ioRandom(userdata, buffer);
}

// =========================================================================
// Fetch API HTTP/HTTPS Networking (`netLookup`, `netConnectIp`, `Stream`)
// =========================================================================

fn ioNetLookup(
    userdata: ?*anyopaque,
    host_name: net.HostName,
    resolved: *Io.Queue(net.HostName.LookupResult),
    options: net.HostName.LookupOptions,
) net.HostName.LookupError!void {
    const self = fromUserdata(userdata);
    const io_val = self.io();
    defer resolved.close(io_val);

    try ioCheckCancel(userdata);

    if (options.canonical_name_buffer) |canon_buf| {
        @memcpy(canon_buf[0..host_name.bytes.len], host_name.bytes);
        resolved.putOne(io_val, .{
            .canonical_name = .{ .bytes = canon_buf[0..host_name.bytes.len] },
        }) catch |err| switch (err) {
            error.Canceled => return error.Canceled,
            error.Closed => return,
        };
    } else {
        resolved.putOne(io_val, .{
            .canonical_name = host_name,
        }) catch |err| switch (err) {
            error.Canceled => return error.Canceled,
            error.Closed => return,
        };
    }

    const ip_bytes = self.internHostIp(host_name.bytes) catch {
        return error.SystemResources;
    };
    const addr: net.IpAddress = .{
        .ip4 = .{ .bytes = ip_bytes, .port = options.port },
    };
    resolved.putOne(io_val, .{ .address = addr }) catch |err| switch (err) {
        error.Canceled => return error.Canceled,
        error.Closed => return,
    };
}

fn internHostIp(self: *WebApiIo, host_bytes: []const u8) ![4]u8 {
    for (self.hosts.items) |h| {
        if (std.ascii.eqlIgnoreCase(h.name, host_bytes)) return h.ip;
    }
    const idx = self.next_host_index;
    self.next_host_index += 1;
    const ip: [4]u8 = .{
        198,
        18,
        @truncate(idx >> 8),
        @truncate(idx & 0xFF),
    };
    const dup = try self.gpa.dupe(u8, host_bytes);
    errdefer self.gpa.free(dup);
    try self.hosts.append(self.gpa, .{ .ip = ip, .name = dup });
    return ip;
}

fn lookupHostByIp(self: *const WebApiIo, ip: [4]u8) ?[]const u8 {
    for (self.hosts.items) |h| {
        if (std.mem.eql(u8, &h.ip, &ip)) return h.name;
    }
    return null;
}

fn ioNetConnectIp(
    userdata: ?*anyopaque,
    address: *const net.IpAddress,
    options: net.IpAddress.ConnectOptions,
) net.IpAddress.ConnectError!net.Socket {
    try ioCheckCancel(userdata);
    if (options.mode != .stream) return error.SocketModeUnsupported;

    const self = fromUserdata(userdata);
    var host_buf: [64]u8 = undefined;
    const host_str: []const u8 = switch (address.*) {
        .ip4 => |v4| self.lookupHostByIp(v4.bytes) orelse
            (std.fmt.bufPrint(
                &host_buf,
                "{d}.{d}.{d}.{d}",
                .{ v4.bytes[0], v4.bytes[1], v4.bytes[2], v4.bytes[3] },
            ) catch return error.SystemResources),
        .ip6 => return error.AddressFamilyUnsupported,
    };

    const sock = self.gpa.create(HttpSocket) catch return error.SystemResources;
    errdefer self.gpa.destroy(sock);
    const host_copy = self.gpa.dupe(u8, host_str) catch {
        return error.SystemResources;
    };
    errdefer self.gpa.free(host_copy);

    const id = self.next_socket_id;
    self.next_socket_id += 1;
    sock.* = .{
        .id = id,
        .host = host_copy,
        .port = address.getPort(),
    };
    self.sockets.put(self.gpa, id, sock) catch {
        self.gpa.free(host_copy);
        self.gpa.destroy(sock);
        return error.SystemResources;
    };

    if (net.Socket.Handle == void) {
        if (self.void_socket_len < MAX_VOID_HANDLES) {
            self.void_socket_ids[self.void_socket_len] = id;
            self.void_socket_len += 1;
        }
        return .{ .handle = {}, .address = address.* };
    }
    return .{ .handle = @intCast(id), .address = address.* };
}

fn resolveSocketId(self: *const WebApiIo, handle: net.Socket.Handle) i32 {
    if (net.Socket.Handle == void) {
        if (self.void_socket_len > 0) {
            return self.void_socket_ids[self.void_socket_len - 1];
        }
        return -1;
    }
    if (@TypeOf(handle) == isize or @TypeOf(handle) == i32) {
        return @intCast(handle);
    }
    return -1;
}

fn ioNetWriteFile(
    userdata: ?*anyopaque,
    handle: net.Socket.Handle,
    header: []const u8,
    file_reader: *Io.File.Reader,
    limit: Io.Limit,
) net.Stream.Writer.WriteFileError!usize {
    _ = userdata;
    _ = handle;
    _ = header;
    _ = file_reader;
    _ = limit;
    return error.Unimplemented;
}

fn ioNetClose(userdata: ?*anyopaque, sockets: []const net.Socket) void {
    const self = fromUserdata(userdata);
    for (sockets) |s| {
        const id = if (net.Socket.Handle == void) blk: {
            if (self.void_socket_len == 0) continue;
            self.void_socket_len -= 1;
            break :blk self.void_socket_ids[self.void_socket_len];
        } else self.resolveSocketId(s.handle);

        if (self.sockets.fetchRemove(id)) |kv| {
            kv.value.destroy(self.gpa);
        }
    }
}

fn ioNetShutdown(
    userdata: ?*anyopaque,
    handle: net.Socket.Handle,
    how: net.ShutdownHow,
) net.ShutdownError!void {
    try ioCheckCancel(userdata);
    const self = fromUserdata(userdata);
    const id = self.resolveSocketId(handle);
    const sock = self.sockets.get(id) orelse return error.SocketUnconnected;
    switch (how) {
        .send => sock.send_closed = true,
        .recv => sock.recv_closed = true,
        .both => {
            sock.send_closed = true;
            sock.recv_closed = true;
        },
    }
}

fn netWriteImpl(
    self: *WebApiIo,
    op: Io.Operation.NetWrite,
) Io.Operation.NetWrite.Error!usize {
    const id = self.resolveSocketId(op.socket_handle);
    const sock = self.sockets.get(id) orelse return error.SocketUnconnected;
    if (sock.send_closed) return error.ConnectionResetByPeer;

    if (sock.has_response and sock.read_pos >= sock.response_buf.items.len) {
        sock.has_response = false;
        sock.response_buf.clearRetainingCapacity();
        sock.read_pos = 0;
    }

    var written: usize = 0;
    if (op.header.len > 0) {
        sock.request_buf.appendSlice(self.gpa, op.header) catch {
            return error.SystemResources;
        };
        written += op.header.len;
    }
    if (op.data.len > 0) {
        for (op.data[0 .. op.data.len - 1]) |seg| {
            if (seg.len > 0) {
                sock.request_buf.appendSlice(self.gpa, seg) catch {
                    return error.SystemResources;
                };
                written += seg.len;
            }
        }
        const tail = op.data[op.data.len - 1];
        if (tail.len > 0 and op.splat > 0) {
            for (0..op.splat) |_| {
                sock.request_buf.appendSlice(self.gpa, tail) catch {
                    return error.SystemResources;
                };
                written += tail.len;
            }
        }
    }
    return written;
}

const ParsedHttpRequest = struct {
    method: []const u8,
    target: []const u8,
    host_header: ?[]const u8,
    headers: []std.http.Header,
    body: ?[]u8,
    consumed_len: usize,

    fn deinit(self: *ParsedHttpRequest, gpa: std.mem.Allocator) void {
        gpa.free(self.headers);
        if (self.body) |b| gpa.free(b);
    }
};

fn containsAsciiIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (haystack.len < needle.len) return false;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[i .. i + needle.len], needle)) {
            return true;
        }
    }
    return false;
}

fn isBrowserForbiddenHeader(name: []const u8) bool {
    const forbidden = [_][]const u8{
        "host",
        "connection",
        "content-length",
        "transfer-encoding",
        "user-agent",
        "accept-encoding",
        "keep-alive",
        "upgrade",
    };
    for (forbidden) |f| {
        if (std.ascii.eqlIgnoreCase(name, f)) return true;
    }
    return false;
}

fn parseHttpRequest(
    gpa: std.mem.Allocator,
    raw: []const u8,
) !?ParsedHttpRequest {
    const head_end = std.mem.indexOf(u8, raw, "\r\n\r\n") orelse return null;
    const head_slice = raw[0..head_end];
    const body_offset = head_end + 4;

    var lines = std.mem.splitSequence(u8, head_slice, "\r\n");
    const req_line = lines.first();
    var parts = std.mem.tokenizeScalar(u8, req_line, ' ');
    const method = parts.next() orelse return error.InvalidHttpRequest;
    const target = parts.next() orelse return error.InvalidHttpRequest;

    var host_hdr: ?[]const u8 = null;
    var content_len: ?usize = null;
    var is_chunked = false;
    var hdr_list: std.ArrayList(std.http.Header) = .empty;
    errdefer hdr_list.deinit(gpa);

    while (lines.next()) |line| {
        if (line.len == 0) break;
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        const h_name = std.mem.trim(u8, line[0..colon], " \t");
        const h_val = std.mem.trim(u8, line[colon + 1 ..], " \t");

        if (std.ascii.eqlIgnoreCase(h_name, "host")) {
            host_hdr = h_val;
        } else if (std.ascii.eqlIgnoreCase(h_name, "content-length")) {
            content_len = std.fmt.parseInt(usize, h_val, 10) catch {
                return error.InvalidHttpRequest;
            };
        } else if (std.ascii.eqlIgnoreCase(h_name, "transfer-encoding")) {
            if (containsAsciiIgnoreCase(h_val, "chunked")) {
                is_chunked = true;
            }
        }

        if (!isBrowserForbiddenHeader(h_name)) {
            try hdr_list.append(gpa, .{ .name = h_name, .value = h_val });
        }
    }

    var body_owned: ?[]u8 = null;
    errdefer if (body_owned) |b| gpa.free(b);
    var consumed = body_offset;

    if (is_chunked) {
        var decoded: std.ArrayList(u8) = .empty;
        errdefer decoded.deinit(gpa);
        var pos = body_offset;
        while (true) {
            const line_end = std.mem.indexOfPos(u8, raw, pos, "\r\n") orelse {
                return null;
            };
            const size_str = std.mem.trim(
                u8,
                std.mem.sliceTo(raw[pos..line_end], ';'),
                " \t",
            );
            const chunk_len = std.fmt.parseInt(usize, size_str, 16) catch {
                return error.InvalidHttpRequest;
            };
            pos = line_end + 2;
            if (chunk_len == 0) {
                if (pos + 2 > raw.len) return null;
                consumed = pos + 2;
                break;
            }
            if (pos + chunk_len + 2 > raw.len) return null;
            try decoded.appendSlice(gpa, raw[pos .. pos + chunk_len]);
            pos += chunk_len + 2;
        }
        body_owned = try decoded.toOwnedSlice(gpa);
    } else if (content_len) |clen| {
        if (body_offset + clen > raw.len) return null;
        if (clen > 0) {
            const end = body_offset + clen;
            body_owned = try gpa.dupe(u8, raw[body_offset..end]);
        }
        consumed = body_offset + clen;
    }

    return .{
        .method = method,
        .target = target,
        .host_header = host_hdr,
        .headers = try hdr_list.toOwnedSlice(gpa),
        .body = body_owned,
        .consumed_len = consumed,
    };
}

fn buildFetchUrl(
    self: *const WebApiIo,
    sock: *const HttpSocket,
    req: *const ParsedHttpRequest,
) ![]u8 {
    for ([_][]const u8{
        "http://origin.local",
        "https://origin.local",
        "http://webapi.local",
        "https://webapi.local",
    }) |local_prefix| {
        if (std.ascii.startsWithIgnoreCase(req.target, local_prefix)) {
            const suffix = req.target[local_prefix.len..];
            const clean_suffix = if (suffix.len > 0) suffix else "/";
            if (self.base_origin) |origin| {
                const base = std.mem.trimEnd(u8, origin, "/");
                return std.fmt.allocPrint(self.gpa, "{s}{s}", .{
                    base,
                    clean_suffix,
                });
            }
            const rel = std.mem.trimStart(u8, clean_suffix, "/");
            return self.gpa.dupe(u8, if (rel.len > 0) rel else ".");
        }
    }

    if (std.ascii.startsWithIgnoreCase(req.target, "http://") or
        std.ascii.startsWithIgnoreCase(req.target, "https://"))
    {
        return self.gpa.dupe(u8, req.target);
    }

    const effective_host = if (req.host_header) |hh|
        (if (!std.ascii.eqlIgnoreCase(hh, PROXY_HOST)) hh else sock.host)
    else
        sock.host;

    if (std.ascii.eqlIgnoreCase(effective_host, "origin.local") or
        std.ascii.eqlIgnoreCase(effective_host, "webapi.local") or
        std.ascii.eqlIgnoreCase(effective_host, PROXY_HOST))
    {
        if (self.base_origin) |origin| {
            const base = std.mem.trimEnd(u8, origin, "/");
            return std.fmt.allocPrint(
                self.gpa,
                "{s}{s}",
                .{ base, req.target },
            );
        }
        const rel = std.mem.trimStart(u8, req.target, "/");
        return self.gpa.dupe(u8, if (rel.len > 0) rel else ".");
    }

    const scheme = if (sock.port == 443) "https" else "http";
    const has_port = std.mem.indexOfScalar(u8, effective_host, ':') != null;
    const default_port = sock.port == 80 or sock.port == 443 or sock.port == 0;
    if (has_port or default_port) {
        return std.fmt.allocPrint(self.gpa, "{s}://{s}{s}", .{
            scheme,
            effective_host,
            req.target,
        });
    }
    return std.fmt.allocPrint(self.gpa, "{s}://{s}:{d}{s}", .{
        scheme,
        effective_host,
        sock.port,
        req.target,
    });
}

fn formatHttpResponse(
    gpa: std.mem.Allocator,
    out: *std.ArrayList(u8),
    status: u16,
    reason: []const u8,
    content_type: ?[]const u8,
    location: ?[]const u8,
    etag: ?[]const u8,
    body: []const u8,
) !void {
    const safe_reason = if (reason.len > 0) reason else "OK";
    var hdr_buf: [1024]u8 = undefined;
    const head1 = try std.fmt.bufPrint(
        &hdr_buf,
        "HTTP/1.1 {d:0>3} {s}\r\n" ++
            "content-length: {d}\r\n" ++
            "connection: keep-alive\r\n",
        .{ status, safe_reason, body.len },
    );
    try out.appendSlice(gpa, head1);

    if (content_type) |ct| {
        if (ct.len > 0) {
            try out.appendSlice(gpa, "content-type: ");
            try out.appendSlice(gpa, ct);
            try out.appendSlice(gpa, "\r\n");
        }
    }
    if (location) |loc| {
        if (loc.len > 0) {
            try out.appendSlice(gpa, "location: ");
            try out.appendSlice(gpa, loc);
            try out.appendSlice(gpa, "\r\n");
        }
    }
    if (etag) |tag| {
        if (tag.len > 0) {
            try out.appendSlice(gpa, "etag: ");
            try out.appendSlice(gpa, tag);
            try out.appendSlice(gpa, "\r\n");
        }
    }
    try out.appendSlice(gpa, "\r\n");
    if (body.len > 0) {
        try out.appendSlice(gpa, body);
    }
}

fn asyncFetchExecutor(
    ctx_ptr: JsPtrInt,
    resolve_h: zjb.Handle,
    reject_h: zjb.Handle,
) callconv(.c) void {
    if (!reject_h.isNull()) reject_h.release();
    const state: *AsyncFetchState = @ptrFromInt(@as(usize, @bitCast(ctx_ptr)));
    state.resolve_h = resolve_h;
}

fn executeSocketFetch(
    self: *WebApiIo,
    sock: *HttpSocket,
) Io.Operation.NetRead.Error!void {
    var parsed = (parseHttpRequest(self.gpa, sock.request_buf.items) catch {
        return error.ConnectionResetByPeer;
    }) orelse return error.ConnectionResetByPeer;
    const consumed_len = parsed.consumed_len;
    defer {
        const rem = sock.request_buf.items.len - consumed_len;
        if (rem > 0) {
            std.mem.copyForwards(
                u8,
                sock.request_buf.items[0..rem],
                sock.request_buf.items[consumed_len..],
            );
        }
        sock.request_buf.shrinkRetainingCapacity(rem);
    }
    defer parsed.deinit(self.gpa);

    const url = self.buildFetchUrl(sock, &parsed) catch {
        return error.SystemResources;
    };
    defer self.gpa.free(url);

    // Build real `Fetch.Headers` & `Fetch.RequestInit` to exercise the browser
    // Fetch API (and verify handle ownership under `zjb.Mock` in host tests).
    const js_headers: ?Fetch.Headers = if (parsed.headers.len > 0) blk: {
        const h = Fetch.Headers.init();
        for (parsed.headers) |hdr| {
            h.set(hdr.name, hdr.value);
        }
        break :blk h;
    } else null;
    defer if (js_headers) |h| h.release();

    const req_init: Fetch.RequestInit = .{
        .method = parsed.method,
        .headers = js_headers,
        .body = parsed.body,
    };

    sock.response_buf.clearRetainingCapacity();
    sock.read_pos = 0;

    // 1. Custom mock fetch hook (used in deterministic host unit tests).
    if (self.mock_fetch) |handler| {
        const init_h = req_init.toHandle();
        init_h.release();

        const mock_res = handler(self.mock_fetch_ctx, self.gpa, .{
            .method = parsed.method,
            .url = url,
            .headers = parsed.headers,
            .body = parsed.body,
        }) catch return error.NetworkDown;
        defer self.gpa.free(mock_res.body);

        formatHttpResponse(
            self.gpa,
            &sock.response_buf,
            mock_res.status,
            mock_res.reason,
            mock_res.content_type,
            mock_res.location,
            mock_res.etag,
            mock_res.body,
        ) catch return error.SystemResources;
        sock.has_response = true;
        return;
    }

    // 2. Prefetched cache lookup (supports non-JSPI browsers).
    for (self.prefetched.items) |entry| {
        if (std.mem.eql(u8, entry.url, url)) {
            formatHttpResponse(
                self.gpa,
                &sock.response_buf,
                entry.status,
                "OK",
                entry.content_type,
                null,
                null,
                entry.body,
            ) catch return error.SystemResources;
            sock.has_response = true;
            return;
        }
    }

    // 3. Live `webapi.fetch` + JSPI Promise suspension.
    const fetch_p = webapi.fetch(url, req_init);
    defer fetch_p.release();

    if (self.canSuspend()) {
        var state: AsyncFetchState = .{ .gpa = self.gpa };
        defer if (state.body) |b| self.gpa.free(b);

        const prom_cls = zjb.global("Promise");
        const exec_fn = zjb.fnHandle(
            "webapi_io_fetch_exec",
            &asyncFetchExecutor,
        );
        const s_ptr: JsPtrInt = @bitCast(@intFromPtr(&state));
        const bound = exec_fn.call(
            "bind",
            .{ zjb.Handle.null, s_ptr },
            zjb.Handle,
        );
        defer bound.release();

        const wait_h = prom_cls.new(.{bound});
        if (wait_h.isNull()) return error.SystemResources;
        const wait_p = Promise.fromHandle(wait_h);
        defer wait_p.release();

        fetch_p.thenFn(
            AsyncFetchState,
            &state,
            AsyncFetchState.onResponse,
            AsyncFetchState.onError,
        );
        _ = self.awaitPromise(wait_p);
        if (!state.resolve_h.isNull()) state.resolve_h.release();

        if (state.failed) return error.NetworkDown;
        formatHttpResponse(
            self.gpa,
            &sock.response_buf,
            state.status,
            state.reason_buf[0..state.reason_len],
            state.ct_buf[0..state.ct_len],
            state.loc_buf[0..state.loc_len],
            state.etag_buf[0..state.etag_len],
            state.body orelse &.{},
        ) catch return error.SystemResources;
        sock.has_response = true;
        return;
    }

    if (!is_wasm) {
        formatHttpResponse(
            self.gpa,
            &sock.response_buf,
            200,
            "OK",
            "text/plain",
            null,
            null,
            "",
        ) catch return error.SystemResources;
        sock.has_response = true;
        return;
    }

    return error.NetworkDown;
}

fn netReadImpl(
    self: *WebApiIo,
    op: Io.Operation.NetRead,
) Io.Operation.NetRead.Error!net.Stream.ReadResult {
    const id = self.resolveSocketId(op.socket_handle);
    const sock = self.sockets.get(id) orelse return error.SocketUnconnected;
    if (sock.recv_closed) return .{ .data_len = 0 };

    if (!sock.has_response) {
        if (sock.request_buf.items.len == 0) return .{ .data_len = 0 };
        try self.executeSocketFetch(sock);
    }

    const bytes = sock.response_buf.items;
    if (sock.read_pos >= bytes.len) {
        return .{ .data_len = 0 };
    }

    var copied: usize = 0;
    for (op.data) |dst| {
        if (sock.read_pos >= bytes.len) break;
        const avail = bytes.len - sock.read_pos;
        const n = @min(dst.len, avail);
        if (n > 0) {
            @memcpy(dst[0..n], bytes[sock.read_pos .. sock.read_pos + n]);
            sock.read_pos += n;
            copied += n;
        }
    }
    return .{ .data_len = copied };
}

// =========================================================================
// Unit Tests
// =========================================================================

test "WebApiIo IndexedDB filesystem create, write, read, stat, and seek" {
    const warmup = webapi.codec.encode(zjb.constString("").asHandle());
    warmup.release();
    zjb.resetMock();
    defer zjb.assertNoHandleLeaks() catch unreachable;

    var vio: WebApiIo = .{
        .gpa = std.testing.allocator,
    };
    defer vio.deinit();

    const io_inst = vio.io();

    // 1. Direct file creation, streaming write, positional overwrite, and seek.
    {
        const fd = try Dir.cwd().createFile(
            io_inst,
            "/test.txt",
            .{ .read = true },
        );
        defer fd.close(io_inst);
        try fd.writeStreamingAll(io_inst, "Hello World");
        try fd.writePositionalAll(io_inst, "IndexedDB!", 6);

        try io_inst.vtable.fileSeekTo(io_inst.userdata, fd, 0);
        try io_inst.vtable.fileSeekBy(io_inst.userdata, fd, 6);
        var stream_buf: [32]u8 = undefined;
        var sr = fd.readerStreaming(io_inst, &stream_buf);
        var word_buf: [10]u8 = undefined;
        try sr.interface.readSliceAll(&word_buf);
        try std.testing.expectEqualStrings("IndexedDB!", &word_buf);
    }

    // Verify file persisted into the underlying IndexedFs store on close.
    const persisted = vio.fs.getMockIndexedFsEntry("/test.txt");
    try std.testing.expect(persisted != null);
    try std.testing.expectEqualStrings("Hello IndexedDB!", persisted.?.data);

    // 2. Read back via `Dir.readFile` and inspect `statFile`.
    var read_buf: [64]u8 = undefined;
    const content = try Dir.cwd().readFile(io_inst, "/test.txt", &read_buf);
    try std.testing.expectEqualStrings("Hello IndexedDB!", content);

    const st = try Dir.cwd().statFile(io_inst, "/test.txt", .{});
    try std.testing.expectEqual(File.Kind.file, st.kind);
    try std.testing.expectEqual(@as(u64, 16), st.size);

    // 3. Positional read/write and `setLength` truncation/extension.
    {
        const fd = try Dir.cwd().openFile(io_inst, "/test.txt", .{
            .mode = .read_write,
        });
        defer fd.close(io_inst);

        var slice_buf: [9]u8 = undefined;
        const n = try fd.readPositionalAll(io_inst, &slice_buf, 6);
        try std.testing.expectEqual(@as(usize, 9), n);
        try std.testing.expectEqualStrings("IndexedDB", &slice_buf);

        try fd.setLength(io_inst, 5);
        try std.testing.expectEqual(@as(u64, 5), try fd.length(io_inst));
    }

    const truncated = try Dir.cwd().readFile(io_inst, "/test.txt", &read_buf);
    try std.testing.expectEqualStrings("Hello", truncated);
    try zjb.assertNoHandleLeaks();
}

test "WebApiIo nested directories, walk, updateFile, rename, and delete" {
    const warmup = webapi.codec.encode(zjb.constString("").asHandle());
    warmup.release();
    zjb.resetMock();

    var vio: WebApiIo = undefined;
    try vio.init(.{
        .gpa = std.testing.allocator,
        .db_name = "test_idb_fs",
        .store_name = "entries",
    });
    defer vio.deinit();

    const io_inst = vio.io();

    // Create nested directory path and populate files.
    const status1 = try Dir.cwd().createDirPathStatus(
        io_inst,
        "workspace/src",
        .default_dir,
    );
    try std.testing.expectEqual(Dir.CreatePathStatus.created, status1);

    const status2 = try Dir.cwd().createDirPathStatus(
        io_inst,
        "workspace/src",
        .default_dir,
    );
    try std.testing.expectEqual(Dir.CreatePathStatus.existed, status2);

    try Dir.cwd().writeFile(io_inst, .{
        .sub_path = "workspace/README.md",
        .data = "# WebApiIo\n",
    });
    try Dir.cwd().writeFile(io_inst, .{
        .sub_path = "workspace/src/main.zig",
        .data = "pub fn main() void {}\n",
    });

    // Atomic file copy via `Dir.updateFile`.
    const prev_status = try Dir.cwd().updateFile(
        io_inst,
        "workspace/src/main.zig",
        Dir.cwd(),
        "workspace/backup/main.zig",
        .{},
    );
    try std.testing.expectEqual(Dir.PrevStatus.stale, prev_status);

    // Iterate direct children of `workspace`.
    {
        const ws_dir = try Dir.cwd().openDir(io_inst, "workspace", .{
            .iterate = true,
        });
        defer ws_dir.close(io_inst);

        var it = ws_dir.iterate();
        var count: usize = 0;
        while (try it.next(io_inst)) |entry| {
            try std.testing.expect(entry.name.len > 0);
            count += 1;
        }
        try std.testing.expectEqual(@as(usize, 3), count);

        // Recursive walk under `workspace`.
        var walker = try ws_dir.walk(std.testing.allocator);
        defer walker.deinit();
        var file_count: usize = 0;
        while (try walker.next(io_inst)) |w_entry| {
            if (w_entry.kind == .file) file_count += 1;
        }
        try std.testing.expectEqual(@as(usize, 3), file_count);
    }

    // Rename, working directory change, realPath, and deletion.
    try Dir.cwd().rename(
        "workspace/README.md",
        Dir.cwd(),
        "workspace/ DOC.md",
        io_inst,
    );
    try std.testing.expect(
        vio.fs.getMockIndexedFsEntry("/workspace/README.md") == null,
    );
    try std.testing.expect(
        vio.fs.getMockIndexedFsEntry("/workspace/ DOC.md") != null,
    );

    try std.process.setCurrentPath(io_inst, "/workspace");
    var cwd_buf: [128]u8 = undefined;
    const cwd_n = try std.process.currentPath(io_inst, &cwd_buf);
    try std.testing.expectEqualStrings("/workspace", cwd_buf[0..cwd_n]);

    try Dir.cwd().deleteFile(io_inst, " DOC.md");
    try std.testing.expectError(
        error.FileNotFound,
        Dir.cwd().openFile(io_inst, " DOC.md", .{}),
    );
    try std.testing.expectError(
        error.DirNotEmpty,
        Dir.cwd().deleteDir(io_inst, "src"),
    );
    try Dir.cwd().deleteFile(io_inst, "src/main.zig");
    try Dir.cwd().deleteDir(io_inst, "src");

    try zjb.assertNoHandleLeaks();
}

test "WebApiIo Fetch networking with std.http.Client over HTTP and HTTPS" {
    const warmup = webapi.codec.encode(zjb.constString("").asHandle());
    warmup.release();
    zjb.resetMock();

    const MockState = struct {
        call_count: usize = 0,
        last_method: [16]u8 = undefined,
        last_method_len: usize = 0,
        last_url: [256]u8 = undefined,
        last_url_len: usize = 0,
        seen_auth: bool = false,

        fn handle(
            ctx_raw: ?*anyopaque,
            allocator: std.mem.Allocator,
            req: MockFetchRequest,
        ) !MockFetchResponse {
            const st: *@This() = @ptrCast(@alignCast(ctx_raw.?));
            st.call_count += 1;
            @memcpy(st.last_method[0..req.method.len], req.method);
            st.last_method_len = req.method.len;
            @memcpy(st.last_url[0..req.url.len], req.url);
            st.last_url_len = req.url.len;

            for (req.headers) |h| {
                if (std.ascii.eqlIgnoreCase(h.name, "authorization") and
                    std.mem.eql(u8, h.value, "Bearer zig-token"))
                {
                    st.seen_auth = true;
                }
            }

            const body = try std.fmt.allocPrint(
                allocator,
                "{{\"ok\":true,\"echo\":\"{s}\"}}",
                .{req.body orelse "none"},
            );
            return .{
                .status = 200,
                .reason = "OK",
                .content_type = "application/json",
                .body = body,
            };
        }
    };

    var mock_state: MockState = .{};
    var vio: WebApiIo = undefined;
    try vio.init(.{
        .gpa = std.testing.allocator,
        .db_name = null,
        .base_origin = "https://app.example.test",
    });
    defer vio.deinit();
    vio.setMockFetch(&mock_state, MockState.handle);

    var client = vio.httpClient(std.testing.allocator);
    defer client.deinit();

    // 1. HTTPS POST with custom header and payload via `std.http.Client.fetch`.
    var resp_body: Io.Writer.Allocating = .init(std.testing.allocator);
    defer resp_body.deinit();

    const post_res = try client.fetch(.{
        .location = .{ .url = "https://api.example.test/v1/items?limit=2" },
        .method = .POST,
        .payload = "hello-fetch",
        .extra_headers = &.{
            .{ .name = "Authorization", .value = "Bearer zig-token" },
        },
        .response_writer = &resp_body.writer,
    });
    try std.testing.expectEqual(std.http.Status.ok, post_res.status);
    try std.testing.expectEqualStrings(
        "{\"ok\":true,\"echo\":\"hello-fetch\"}",
        resp_body.written(),
    );
    try std.testing.expectEqualStrings(
        "POST",
        mock_state.last_method[0..mock_state.last_method_len],
    );
    try std.testing.expectEqualStrings(
        "https://api.example.test/v1/items?limit=2",
        mock_state.last_url[0..mock_state.last_url_len],
    );
    try std.testing.expect(mock_state.seen_auth);

    // 2. Origin-relative GET via `origin.local` reusing pooled connection.
    resp_body.clearRetainingCapacity();
    const get_res = try client.fetch(.{
        .location = .{ .url = "http://origin.local/data.json" },
        .method = .GET,
        .response_writer = &resp_body.writer,
    });
    try std.testing.expectEqual(std.http.Status.ok, get_res.status);
    try std.testing.expectEqualStrings(
        "https://app.example.test/data.json",
        mock_state.last_url[0..mock_state.last_url_len],
    );
    try std.testing.expectEqual(@as(usize, 2), mock_state.call_count);

    // 3. Default `zjb.Mock` Fetch path (no mock hook) has zero handle leaks.
    vio.clearMockFetch();
    resp_body.clearRetainingCapacity();
    const raw_res = try client.fetch(.{
        .location = .{ .url = "http://example.org/ping" },
        .response_writer = &resp_body.writer,
    });
    try std.testing.expectEqual(std.http.Status.ok, raw_res.status);

    try zjb.assertNoHandleLeaks();
}

test "WebApiIo Promise async/await, Group, sleep, random, and fallbacks" {
    const warmup = webapi.codec.encode(zjb.constString("").asHandle());
    warmup.release();
    zjb.resetMock();

    var vio: WebApiIo = undefined;
    try vio.init(.{
        .gpa = std.testing.allocator,
        .db_name = null,
    });
    defer vio.deinit();
    const io_inst = vio.io();

    // 1. `io.async` + `future.await` and `io.concurrent` + `future.cancel`.
    const Work = struct {
        fn compute(a: u32, b: u32) u32 {
            return a * 10 + b;
        }
        fn addToAtomic(sum: *std.atomic.Value(u32), delta: u32) void {
            _ = sum.fetchAdd(delta, .monotonic);
        }
    };

    var fut1 = io_inst.async(Work.compute, .{ 4, 2 });
    try std.testing.expectEqual(@as(u32, 42), fut1.await(io_inst));

    var fut2 = try io_inst.concurrent(Work.compute, .{ 9, 9 });
    try std.testing.expectEqual(@as(u32, 99), fut2.cancel(io_inst));

    // 2. `Io.Group` with multiple Promise-backed tasks.
    var total: std.atomic.Value(u32) = .init(0);
    var group: Io.Group = .init;
    group.async(io_inst, Work.addToAtomic, .{ &total, 10 });
    try group.concurrent(io_inst, Work.addToAtomic, .{ &total, 25 });
    try group.await(io_inst);
    try std.testing.expectEqual(@as(u32, 35), total.load(.monotonic));

    // 3. Clock, sleep, random, and failing vtable forwarding.
    const t0 = Io.Clock.awake.now(io_inst);
    try io_inst.sleep(.fromMilliseconds(25), .awake);
    const t1 = Io.Clock.awake.now(io_inst);
    try std.testing.expect(
        t1.nanoseconds >= t0.nanoseconds + 25 * std.time.ns_per_ms,
    );

    var rand_bytes: [32]u8 = @splat(0);
    try io_inst.randomSecure(&rand_bytes);
    var non_zero = false;
    for (rand_bytes) |b| {
        if (b != 0) non_zero = true;
    }
    try std.testing.expect(non_zero);

    try std.testing.expectError(
        error.OperationUnsupported,
        net.Socket.createPair(io_inst, .{}),
    );
    try zjb.assertNoHandleLeaks();
}
