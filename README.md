# zjblib

High-level, type-safe WebAssembly browser and WASI API wrappers built on top of [`zig-javascript-bridge`](https://github.com/dasimmet/zig-javascript-bridge) (`zjb`).

`zjblib` lets Zig WebAssembly applications interact with DOM APIs, events, WebGL, Fetch, Promises, IndexedDB, WebRTC, WebSockets, BroadcastChannel, WebAssembly/JSPI, and a pure-Zig WASI Snapshot Preview 1 runtime without writing custom JavaScript glue or relying on global callback singletons.

## Requirements

- **Zig**: `0.17.1` (see `minimum_zig_version` in [`build.zig.zon`](build.zig.zon))
- **Targets**: `wasm32-freestanding` or `wasm64-freestanding` in the browser; host target (`b.graph.host`) for unit tests via the built-in in-memory `zjb` mock.

## Modules

All modules are re-exported from [`src/zjblib.zig`](src/zjblib.zig):

| Module / Symbol | Source | Purpose |
| --- | --- | --- |
| `zjblib` (root) | [`src/zjblib.zig`](src/zjblib.zig) | Zero-allocation string extraction (`stringFromHandle`, `stringFromHandles`), allocating helpers (`stringFromHandleAlloc`, `bytesFromHandleAlloc`, `createStandaloneUint8Array`), context-bound callbacks (`boundFunction`, `boundEventListener`, `boundEventListenerTyped`), Web Crypto PRNG (`PseudoRandomNumberGenerator`), `constTagName`, `getUri`, `retainHandle`, `hasProperty`, `callAsync`. |
| `zjblib.zjb` | [`src/zjblib.zig`](src/zjblib.zig) | Resolves to `@import("zjb")` on WASM targets and [`src/testing/zjb.zig`](src/testing/zjb.zig) on host targets. |
| `zjblib.codec` | [`src/codec.zig`](src/codec.zig) | Cached singleton JS `TextEncoder` / `TextDecoder` helpers (`encode`, `decode`). |
| `zjblib.console` | [`src/console.zig`](src/console.zig) | Browser console logging (`log`, `debug`, `@"error"`) and `rootLogFn` for `std.Options.logFn`. |
| `zjblib.dom` | [`src/dom.zig`](src/dom.zig) | Typed DOM wrappers: `Document`, `Window`, `Element`, `CSSStyleDeclaration`, `TokenList`, `DOMRect`, `Location`, `History`, `Navigator`, `Clipboard`, `Performance`, `MediaQueryList`, `VisualViewport`, `DataTransfer`, `HTMLIFrameElement`, `ServiceWorker`, `ServiceWorkerContainer`, `ServiceWorkerRegistration`. |
| `zjblib.Event` | [`src/Event.zig`](src/Event.zig) | Base `Event` wrapper and compile-time `EventFor(name)` mapping to `KeyboardEvent`, `PointerEvent`, `MouseEvent`, `WheelEvent`, `InputEvent`, `ClipboardEvent`, `FocusEvent`, `SubmitEvent`, `TouchEvent`, `HashChangeEvent`, `PopStateEvent`, `MediaQueryListEvent`, and `BeforeInstallPromptEvent`. |
| `zjblib.Promise` | [`src/Promise.zig`](src/Promise.zig) | `Promise` and `Promise.Typed(T)` wrappers with context-bound `.thenFn(...)`. |
| `zjblib.Fetch` / `zjblib.fetch` | [`src/Fetch.zig`](src/Fetch.zig) | Browser Fetch API: `fetch`, `Headers`, `RequestInit`, and `Response`. |
| `zjblib.download` | [`src/download.zig`](src/download.zig) | Trigger browser file downloads from raw byte slices (`download.bytes`). |
| `zjblib.WebGL` | [`src/WebGL.zig`](src/WebGL.zig) | WebGL2 / WebGL rendering context, buffers, textures, shaders/programs (`createProgramFromSource`), uniforms (`uploadMat4`, etc.), framebuffers, VAOs, and draw calls. |
| `zjblib.IndexedDb` | [`src/IndexedDb.zig`](src/IndexedDb.zig) | Context-bound async `IndexedDB` wrapper (`open`, `Database`, `Transaction`, `ObjectStore`, `loadAllEntries`) using detached `Uint8Array` copies safe across WASM memory growth. |
| `zjblib.WebRTC` | [`src/WebRTC.zig`](src/WebRTC.zig) | `RTCPeerConnection`, `RTCDataChannel`, `RTCSessionDescription`, `RTCIceCandidate`, `RTCConfiguration`, and `RTCIceServer`. |
| `zjblib.WebSocket` | [`src/WebSocket.zig`](src/WebSocket.zig) | `WebSocket` wrapper with `ReadyState` and typed listener attachment. |
| `zjblib.BroadcastChannel` | [`src/BroadcastChannel.zig`](src/BroadcastChannel.zig) | Cross-tab / worker `BroadcastChannel` wrapper. |
| `zjblib.WebAssembly` | [`src/WebAssembly.zig`](src/WebAssembly.zig) | `Module`, `Instance`, `Memory`, `validate`, `compile`, `instantiate`, `instantiateAsync`, and JSPI (`Suspending`, `isJspiSupported`, `promising`). |
| `zjblib.Wasi` | [`src/Wasi.zig`](src/Wasi.zig) | Pure-Zig WASI Snapshot Preview 1 runtime for running WASM binaries in the browser with in-memory, `.tar`, and `IndexedDb`-backed filesystems ([`src/Wasi/FileSystem.zig`](src/Wasi/FileSystem.zig)). |
| `zjblib.testing` | [`src/testing.zig`](src/testing.zig) | Host-side unit tests and handle-leak checks powered by [`src/testing/zjb.zig`](src/testing/zjb.zig). |

## Quick Start

### 1. Add `zjblib` to `build.zig.zon`

Reference `zjblib` via `zig fetch --save=zjblib <url>` or a local path:

```zig
.{
    .name = .my_wasm_app,
    .version = "0.0.1",
    .minimum_zig_version = "0.17.1",
    .dependencies = .{
        .zjblib = .{
            .path = "../zjblib",
        },
    },
    .paths = .{ "build.zig", "build.zig.zon", "src", "static" },
}
```

### 2. Configure `build.zig`

`zjblib` exports both the `"zjblib"` Zig module (with `"zjb"` already wired in) and a `bindgen` helper that generates the matching JavaScript `Zjb` class from your compiled `.wasm` binary:

```zig
const std = @import("std");
const zjblib_pkg = @import("zjblib");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const wasm_target = b.standardTargetOptions(.{
        .default_target = .{
            .cpu_arch = .wasm32,
            .os_tag = .freestanding,
        },
    });

    const zjblib_mod = b.dependency("zjblib", .{}).module("zjblib");

    const exe = b.addExecutable(.{
        .name = "app",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = wasm_target,
            .optimize = optimize,
            .strip = false,
            .imports = &.{
                .{ .name = "zjblib", .module = zjblib_mod },
            },
        }),
    });
    exe.rdynamic = true;

    const zjb_bindings = zjblib_pkg.bindgen(b, .{
        .wasm = exe.getEmittedBin(),
        .basename = "zjb_bindings.js",
        .classname = "Zjb",
        .module_style = .es6,
        .minify = optimize != .debug,
    });

    b.default_step.dependOn(&b.addInstallFile(exe.getEmittedBin(), "www/app.wasm").step);
    b.default_step.dependOn(&b.addInstallFile(zjb_bindings, "www/zjb_bindings.js").step);
}
```

### 3. Write Zig Application Code

```zig
const std = @import("std");
const zjblib = @import("zjblib");

const dom = zjblib.dom;
const Event = zjblib.Event;
const zjb = zjblib.zjb;

pub const std_options: std.Options = .{
    .logFn = zjblib.console.rootLogFn,
    .log_level = .debug,
};

pub const panic = zjb.panic;

const App = struct {
    clicks: u32 = 0,

    fn onClick(self: *App, ev: Event.PointerEvent) void {
        _ = ev;
        self.clicks += 1;
        var buf: [64]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "Clicked {d} times", .{self.clicks}) catch return;
        dom.document().setElemText("status", msg);
    }
};

pub fn main(init: std.process.Init.Minimal) !void {
    _ = init;
    const app = try std.heap.wasm_allocator.create(App);
    app.* = .{};

    if (dom.document().getElementById("my-btn")) |btn| {
        defer btn.release();
        btn.addEventListener("click", App, app, App.onClick);
    }

    std.log.info("App ready", .{});
}
```

### 4. Bootstrap in JavaScript

```javascript
import { Zjb } from "./zjb_bindings.js";

const zjb = new Zjb();
const { instance } = await WebAssembly.instantiateStreaming(fetch("app.wasm"), {
  env: {
    memory: new WebAssembly.Memory({ initial: 16 }),
    __stack_pointer: 0,
  },
  zjb: zjb.imports,
});

zjb.setInstance(instance);
instance.exports._start();
```

## Handle Ownership Rules

`zjb.Handle` values reference JavaScript objects stored in `Zjb._handles`:

- **Release owned handles**: Any wrapper or `zjb.Handle` returned by constructors or getters (`getElementById`, `getUniformLocation`, `createBuffer`, `fetch`, `response.text()`, `event.target()`, etc.) must be released with `.release()` when no longer needed.
- **Callback & listener views**: Handles passed into `boundFunction`, `addEventListener`, and `Promise.thenFn` callbacks are non-owning views and are automatically released when the callback returns. Use `boundFunctionOwned` / `addEventListenerOwned` / `boundEventListenerTypedOwned` if you need to keep the handle past callback return.
- **Global singletons**: `dom.document()` and `dom.window()` wrap `zjb.ConstHandle` values and do not need to be released.

## Running Unit Tests

Host-side unit tests use the in-memory mock in [`src/testing/zjb.zig`](src/testing/zjb.zig) to verify wrapper behavior and detect handle leaks or double-frees without a browser:

```bash
zig build test
```

## Example Project

A complete interactive browser example lives in [`example/`](example/):

- [`example/build.zig`](example/build.zig) & [`example/build.zig.zon`](example/build.zig.zon) — standalone package configuration consuming `zjblib` via `.path = ".."`.
- [`example/src/main.zig`](example/src/main.zig) — demonstrates `console.rootLogFn`, `PseudoRandomNumberGenerator`, `WebGL`, `requestAnimationFrame` with `boundFunction`, typed `PointerEvent` / `InputEvent` / `KeyboardEvent` listeners, `fetch` + `Promise.Typed(Response)`, `Location.getHref`, and `download.bytes`.
- [`example/static/`](example/static/) — HTML, CSS, ES6 module bootstrap, and `data.json`.

Build and serve it locally:

```bash
cd example
zig build serve
```

Then open <http://127.0.0.1:8080> in a WebGL-capable browser. To build `example/zig-out/www/` without starting the HTTP server, run `zig build` inside `example/`.
