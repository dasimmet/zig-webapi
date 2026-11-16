const std = @import("std");
pub const javascript_bridge = @import("javascript_bridge");

pub const BindgenOptions = javascript_bridge.BindgenOptions;
pub const ModuleStyle = javascript_bridge.ModuleStyle;

/// Generates the JavaScript glue class (`Zjb`) for a compiled WASM binary
/// using the bundled `javascript_bridge` dependency.
pub fn bindgen(b: *std.Build, opt: BindgenOptions) std.Build.LazyPath {
    const self_dep = b.dependencyFromBuildZig(@This(), .{});
    const jb_dep = self_dep.builder.dependency("javascript_bridge", .{});
    const generate_js = jb_dep.artifact("generate_js");
    const run = b.addRunArtifact(generate_js);
    const out = run.addPrefixedOutputFileArg("--output=", opt.basename);
    run.addPrefixedFileArg("--wasm=", opt.wasm);
    run.addArg(b.fmt("--class={s}", .{opt.classname}));
    run.addArg(b.fmt("--module-style={s}", .{@tagName(opt.module_style)}));
    run.addArg(b.fmt("--minify={s}", .{if (opt.minify) "true" else "false"}));
    return out;
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zjb_module = b.dependency("javascript_bridge", .{}).module("zjb");

    _ = b.addModule("webapi", .{
        .root_source_file = b.path("src/webapi.zig"),
        .imports = &.{
            .{
                .name = "zjb",
                .module = zjb_module,
            },
        },
    });

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/testing.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const test_run = b.addRunArtifact(tests);

    b.step("test", "Run unit tests").dependOn(&test_run.step);

    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });
    const docs_obj = b.addObject(.{
        .name = "webapi",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/webapi.zig"),
            .target = wasm_target,
            .optimize = optimize,
            .imports = &.{
                .{
                    .name = "zjb",
                    .module = zjb_module,
                },
            },
        }),
    });
    const docs_install = b.addInstallDirectory(.{
        .source_dir = docs_obj.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "www/docs",
    });

    const landing_install = b.addInstallDirectory(.{
        .source_dir = b.path("site"),
        .install_dir = .prefix,
        .install_subdir = "www",
    });

    const example_run = std.Build.Step.Run.create(b, "build-example");
    example_run.setCwd(b.path("example"));
    example_run.addArg(b.graph.zig_exe);
    example_run.addArgs(&.{ "build", "-Doptimize=small", "--prefix" });
    const example_prefix = example_run.addOutputDirectoryArg("example-out");
    example_run.has_side_effects = true;

    const example_install = b.addInstallDirectory(.{
        .source_dir = example_prefix.path(b, "www"),
        .install_dir = .prefix,
        .install_subdir = "www/example",
    });
    example_install.step.dependOn(&example_run.step);

    const docs_step = b.step(
        "docs",
        "Emit API documentation, landing page, and example to zig-out/www",
    );
    docs_step.dependOn(&docs_install.step);
    docs_step.dependOn(&landing_install.step);
    docs_step.dependOn(&example_install.step);

    const fmt = b.addFmt(.{
        .check = b.option(bool, "fmtcheck", "run zig fmt in check mode") orelse false,
        .paths = b.pathList(&.{
            "src",
            "example/src",
            "example/build.zig",
            "example/build.zig.zon",
            "build.zig",
            "build.zig.zon",
        }),
    });
    b.step("fmt", "Format or check formatting of Zig source files").dependOn(&fmt.step);
}
