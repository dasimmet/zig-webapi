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

    b.step("test", "").dependOn(&test_run.step);
}
