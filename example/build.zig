const std = @import("std");
const webapi_pkg = @import("webapi");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const wasm_target = b.standardTargetOptions(.{
        .default_target = .{
            .cpu_arch = .wasm32,
            .os_tag = .freestanding,
        },
    });

    const webapi_dep = b.dependency("webapi", .{});
    const webapi_mod = webapi_dep.module("webapi");

    const exe = b.addExecutable(.{
        .name = "example",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = wasm_target,
            .optimize = optimize,
            .strip = false,
            .imports = &.{
                .{
                    .name = "webapi",
                    .module = webapi_mod,
                },
            },
        }),
    });
    exe.rdynamic = true;

    const zjb_bindings = webapi_pkg.bindgen(b, .{
        .wasm = exe.getEmittedBin(),
        .basename = "zjb_bindings.js",
        .classname = "Zjb",
        .module_style = .es6,
        .minify = optimize != .debug,
    });

    const wasm_install = b.addInstallFile(exe.getEmittedBin(), "www/example.wasm");
    b.default_step.dependOn(&wasm_install.step);

    const wasi_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .wasi,
    });
    const wasi_hello = b.addExecutable(.{
        .name = "wasi_hello",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/wasi_hello.zig"),
            .target = wasi_target,
            .optimize = optimize,
        }),
    });
    const wasi_hello_install = b.addInstallFile(
        wasi_hello.getEmittedBin(),
        "www/wasi_hello.wasm",
    );
    b.default_step.dependOn(&wasi_hello_install.step);

    const js_install = b.addInstallFile(zjb_bindings, "www/zjb_bindings.js");
    b.default_step.dependOn(&js_install.step);

    const static_install = b.addInstallDirectory(.{
        .source_dir = b.path("static"),
        .install_dir = .prefix,
        .install_subdir = "www",
    });
    b.default_step.dependOn(&static_install.step);

    const serve_step = b.step("serve", "Serve zig-out/www on http://127.0.0.1:8080");
    const serve_cmd = b.addSystemCommand(&.{
        "python3", "-m", "http.server", "8080", "--directory", "zig-out/www",
    });
    serve_cmd.step.dependOn(b.default_step);
    serve_step.dependOn(&serve_cmd.step);
}
