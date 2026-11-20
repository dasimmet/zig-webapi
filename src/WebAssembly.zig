//! Type-safe, generic wrapper for the browser WebAssembly JavaScript API.
//! https://developer.mozilla.org/en-US/docs/WebAssembly/JavaScript_interface
//!
//! Provides zero-eval abstractions for WebAssembly validation, compilation,
//! instance creation, linear memory inspection, and export invocation.

const std = @import("std");
const webapi = @import("webapi.zig");
const zjb = webapi.zjb;

const WebAssembly = @This();

/// Represents an instantiated WebAssembly module with imports.
pub const Instance = struct {
    handle: zjb.Handle,

    pub const @"null": Instance = .{ .handle = .null };

    /// Instantiates a compiled WebAssembly module with imports synchronously.
    pub fn init(module: Module, import_object: ?zjb.Handle) !Instance {
        std.debug.assert(!module.handle.isNull());
        std.debug.assert(@backingInt(module.handle) != 0);

        const wasm_global = zjb.global("WebAssembly");
        const inst_class = wasm_global.get("Instance", zjb.Handle);
        defer inst_class.release();

        const imp = if (import_object) |h|
            h
        else blk: {
            const empty = zjb.global("Object").new(.{});
            break :blk empty;
        };
        defer if (import_object == null) imp.release();

        const inst = inst_class.new(.{ module.handle, imp });
        if (inst.isNull()) return error.InstantiateFailed;

        return fromHandle(inst);
    }

    /// Asynchronously instantiates a compiled WebAssembly module via
    /// `WebAssembly.instantiate`, avoiding main-thread size restrictions.
    pub fn initAsync(
        module: Module,
        import_object: ?zjb.Handle,
    ) !webapi.Promise.Typed(Instance) {
        std.debug.assert(!module.handle.isNull());
        std.debug.assert(@backingInt(module.handle) != 0);

        const wasm_global = zjb.global("WebAssembly");
        if (wasm_global.isNull()) return error.InstantiateFailed;

        const imp = if (import_object) |h|
            h
        else
            zjb.global("Object").new(.{});
        defer if (import_object == null) imp.release();

        const p = wasm_global.call(
            "instantiate",
            .{ module.handle, imp },
            zjb.Handle,
        );
        if (p.isNull()) return error.InstantiateFailed;
        return .fromHandle(p);
    }

    /// Wraps an existing JavaScript WebAssembly.Instance handle.
    pub fn fromHandle(handle: zjb.Handle) Instance {
        std.debug.assert(!handle.isNull());
        std.debug.assert(@backingInt(handle) != 0);
        return .{ .handle = handle };
    }

    /// Releases the underlying JavaScript handle and resets to null.
    pub fn release(self: *Instance) void {
        if (!self.handle.isNull()) {
            self.handle.release();
            self.handle = .null;
        }
    }

    /// Checks whether the underlying JavaScript handle is null.
    pub fn isNull(self: Instance) bool {
        return self.handle.isNull();
    }

    /// Returns a handle to the `instance.exports` object.
    pub fn getExports(self: Instance) zjb.Handle {
        std.debug.assert(!self.handle.isNull());
        std.debug.assert(@backingInt(self.handle) != 0);
        return self.handle.get("exports", zjb.Handle);
    }

    /// Checks whether a function or symbol is exported by name.
    pub fn hasFunction(self: Instance, comptime fn_name: []const u8) bool {
        std.debug.assert(!self.handle.isNull());
        std.debug.assert(fn_name.len > 0);

        const exp = self.getExports();
        defer exp.release();
        const fn_h = exp.get(fn_name, zjb.Handle);
        defer fn_h.release();
        return !fn_h.isNull();
    }

    /// Calls an exported WebAssembly function by name with typed arguments.
    pub fn call(
        self: Instance,
        comptime fn_name: []const u8,
        args: anytype,
        comptime RetType: type,
    ) RetType {
        std.debug.assert(!self.handle.isNull());
        std.debug.assert(fn_name.len > 0);

        const exp = self.getExports();
        defer exp.release();
        return exp.call(fn_name, args, RetType);
    }

    /// Retrieves the exported WebAssembly linear memory if exported.
    pub fn getMemory(self: Instance) ?Memory {
        std.debug.assert(!self.handle.isNull());
        std.debug.assert(@backingInt(self.handle) != 0);

        const exp = self.getExports();
        defer exp.release();

        const mem_h = exp.get("memory", zjb.Handle);
        if (mem_h.isNull()) return null;
        return Memory.fromHandle(mem_h);
    }
};

/// Represents a WebAssembly linear memory buffer.
pub const Memory = struct {
    handle: zjb.Handle,

    pub const @"null": Memory = .{ .handle = .null };

    /// Wraps an existing JavaScript WebAssembly.Memory handle.
    pub fn fromHandle(handle: zjb.Handle) Memory {
        std.debug.assert(!handle.isNull());
        std.debug.assert(@backingInt(handle) != 0);
        return .{ .handle = handle };
    }

    /// Releases the underlying JavaScript handle.
    pub fn release(self: Memory) void {
        self.handle.release();
    }

    /// Checks whether the underlying JavaScript handle is null.
    pub fn isNull(self: Memory) bool {
        return self.handle.isNull();
    }

    /// Returns a handle to the memory's underlying ArrayBuffer.
    pub fn buffer(self: Memory) zjb.Handle {
        std.debug.assert(!self.handle.isNull());
        std.debug.assert(@backingInt(self.handle) != 0);
        return self.handle.get("buffer", zjb.Handle);
    }

    /// Grows the linear memory by `pages` (each page is 64 KiB).
    pub fn grow(self: Memory, pages: i32) i32 {
        std.debug.assert(!self.handle.isNull());
        std.debug.assert(pages >= 0);
        return self.handle.call("grow", .{pages}, i32);
    }
};

/// Represents a compiled WebAssembly module.
pub const Module = struct {
    handle: zjb.Handle,

    pub const @"null": Module = .{ .handle = .null };

    /// Synchronously compiles a WebAssembly module from byte slice.
    /// Note: browsers such as Chromium disallow sync compilation above 4 KiB
    /// on the main thread; prefer `compile` or `instantiateAsync`.
    pub fn init(bytes: []const u8) !Module {
        std.debug.assert(bytes.len >= 4);
        std.debug.assert(std.mem.eql(u8, bytes[0..4], "\x00asm"));

        const wasm_global = zjb.global("WebAssembly");
        const mod_class = wasm_global.get("Module", zjb.Handle);
        defer mod_class.release();

        const view = zjb.u8ArrayView(bytes);
        defer view.release();

        const mod = mod_class.new(.{view});
        if (mod.isNull()) return error.CompileFailed;

        return fromHandle(mod);
    }

    /// Asynchronously compiles a WebAssembly module via `WebAssembly.compile`,
    /// safe for modules larger than 4 KiB on the browser main thread.
    pub fn compile(bytes: []const u8) !webapi.Promise.Typed(Module) {
        std.debug.assert(bytes.len >= 4);
        std.debug.assert(std.mem.eql(u8, bytes[0..4], "\x00asm"));

        const wasm_global = zjb.global("WebAssembly");
        if (wasm_global.isNull()) return error.CompileFailed;

        const standalone = webapi.createStandaloneUint8Array(bytes);
        defer standalone.release();

        const p = wasm_global.call("compile", .{standalone}, zjb.Handle);
        if (p.isNull()) return error.CompileFailed;
        return .fromHandle(p);
    }

    /// Wraps an existing JavaScript WebAssembly.Module handle.
    pub fn fromHandle(handle: zjb.Handle) Module {
        std.debug.assert(!handle.isNull());
        std.debug.assert(@backingInt(handle) != 0);
        return .{ .handle = handle };
    }

    /// Releases the underlying JavaScript handle.
    pub fn release(self: Module) void {
        self.handle.release();
    }

    /// Checks whether the underlying JavaScript handle is null.
    pub fn isNull(self: Module) bool {
        return self.handle.isNull();
    }
};

/// Wraps a JavaScript function so calls to it from WebAssembly can suspend
/// execution until a returned Promise settles (JSPI).
pub const Suspending = struct {
    handle: zjb.Handle,

    pub const @"null": Suspending = .{ .handle = .null };

    /// Constructs `new WebAssembly.Suspending(func)`.
    pub fn init(func: zjb.Handle) !Suspending {
        std.debug.assert(!func.isNull());
        std.debug.assert(@backingInt(func) != 0);

        const wasm_global = zjb.global("WebAssembly");
        if (wasm_global.isNull()) return error.JspiNotSupported;

        const susp_cls = wasm_global.get("Suspending", zjb.Handle);
        defer susp_cls.release();
        if (susp_cls.isNull()) return error.JspiNotSupported;

        const susp = susp_cls.new(.{func});
        if (susp.isNull()) return error.SuspendingInitFailed;
        return fromHandle(susp);
    }

    /// Wraps an existing JavaScript WebAssembly.Suspending handle.
    pub fn fromHandle(handle: zjb.Handle) Suspending {
        std.debug.assert(!handle.isNull());
        std.debug.assert(@backingInt(handle) != 0);
        return .{ .handle = handle };
    }

    /// Releases the underlying JavaScript handle and resets to null.
    pub fn release(self: *Suspending) void {
        std.debug.assert(@intFromPtr(self) != 0);
        if (!self.handle.isNull()) {
            self.handle.release();
            self.handle = .null;
        }
        std.debug.assert(self.handle.isNull());
    }

    /// Checks whether the underlying JavaScript handle is null.
    pub fn isNull(self: Suspending) bool {
        return self.handle.isNull();
    }
};

/// Returns true if both `WebAssembly.Suspending` and `WebAssembly.promising`
/// are available in the host environment.
pub fn isJspiSupported() bool {
    const wasm_global = zjb.global("WebAssembly");
    std.debug.assert(@backingInt(wasm_global) != 0);
    if (wasm_global.isNull()) return false;

    const susp_h = wasm_global.get("Suspending", zjb.Handle);
    defer susp_h.release();
    const prom_h = wasm_global.get("promising", zjb.Handle);
    defer prom_h.release();
    std.debug.assert(!wasm_global.isNull());
    return !susp_h.isNull() and !prom_h.isNull();
}

/// Wraps an exported WebAssembly function with `WebAssembly.promising(func)`
/// so calling it returns a Promise that suspends cleanly on Suspending imports.
pub fn promising(func: zjb.Handle) !zjb.Handle {
    std.debug.assert(!func.isNull());
    std.debug.assert(@backingInt(func) != 0);

    if (!isJspiSupported()) return error.JspiNotSupported;

    const wasm_global = zjb.global("WebAssembly");
    const wrapped = wasm_global.call("promising", .{func}, zjb.Handle);
    if (wrapped.isNull()) return error.PromisingFailed;
    return wrapped;
}

/// Validates whether the given byte slice represents a valid WebAssembly
/// binary format.
pub fn validate(bytes: []const u8) bool {
    std.debug.assert(@intFromPtr(bytes.ptr) != 0 or bytes.len == 0);
    std.debug.assert(bytes.len <= 1024 * 1024 * 512);

    if (bytes.len < 4) return false;
    if (!std.mem.eql(u8, bytes[0..4], "\x00asm")) return false;

    const wasm_global = zjb.global("WebAssembly");
    if (wasm_global.isNull()) return false;

    const view = zjb.u8ArrayView(bytes);
    defer view.release();

    return wasm_global.call("validate", .{view}, bool);
}

/// Asynchronously compiles WebAssembly bytes via `WebAssembly.compile`.
pub fn compile(bytes: []const u8) !webapi.Promise.Typed(Module) {
    std.debug.assert(bytes.len >= 4);
    std.debug.assert(std.mem.eql(u8, bytes[0..4], "\x00asm"));
    return Module.compile(bytes);
}

/// Compiles and instantiates a WebAssembly binary synchronously.
/// Note: prefer `instantiateAsync` for binaries larger than 4 KiB on the
/// browser main thread.
pub fn instantiate(
    wasm_bytes: []const u8,
    import_object: ?zjb.Handle,
) !Instance {
    std.debug.assert(wasm_bytes.len >= 4);
    std.debug.assert(std.mem.eql(u8, wasm_bytes[0..4], "\x00asm"));

    const mod = try Module.init(wasm_bytes);
    defer mod.release();

    return Instance.init(mod, import_object);
}

/// Asynchronously compiles and instantiates a WebAssembly binary via
/// `WebAssembly.instantiate`, avoiding main-thread size restrictions.
/// Resolves to a `{ module, instance }` JS object.
pub fn instantiateAsync(
    wasm_bytes: []const u8,
    import_object: ?zjb.Handle,
) !webapi.Promise.Typed(ResultObject) {
    std.debug.assert(wasm_bytes.len >= 4);
    std.debug.assert(std.mem.eql(u8, wasm_bytes[0..4], "\x00asm"));

    const wasm_global = zjb.global("WebAssembly");
    if (wasm_global.isNull()) return error.InstantiateFailed;

    const standalone = webapi.createStandaloneUint8Array(wasm_bytes);
    defer standalone.release();

    const imp = if (import_object) |h|
        h
    else
        zjb.global("Object").new(.{});
    defer if (import_object == null) imp.release();

    const p = wasm_global.call(
        "instantiate",
        .{ standalone, imp },
        zjb.Handle,
    );
    if (p.isNull()) return error.InstantiateFailed;
    return .fromHandle(p);
}

pub const ResultObject = struct {
    handle: zjb.Handle,
    pub const @"null": ResultObject = .{ .handle = .null };

    /// Wraps a non-null JS WebAssembly instantiate result object handle.
    pub fn fromHandle(handle: zjb.Handle) ResultObject {
        std.debug.assert(!handle.isNull());
        std.debug.assert(@backingInt(handle) != 0);
        return .{ .handle = handle };
    }

    /// Returns `true` if the underlying JS handle is null or undefined.
    pub fn isNull(self: ResultObject) bool {
        return self.handle.isNull();
    }

    /// Releases the underlying JavaScript handle.
    pub fn release(self: ResultObject) void {
        self.handle.release();
    }

    pub fn instance(self: @This()) Instance {
        return Instance.fromHandle(self.handle.get("instance", zjb.Handle));
    }
};
