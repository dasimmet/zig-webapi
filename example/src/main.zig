//! Browser entry point for the interactive `zig-webapi` showcase application.

const std = @import("std");
const webapi = @import("webapi");
const App = @import("App.zig");

pub const std_options: std.Options = .{
    .logFn = webapi.console.rootLogFn,
    .log_level = switch (@import("builtin").optimize) {
        .debug => .debug,
        else => .info,
    },
};

pub const panic = webapi.panic;

pub fn main(init: std.process.Init.Minimal) !void {
    _ = init;
    const allocator = std.heap.wasm_allocator;

    const app = try App.init(allocator);
    app.start();

    std.log.info("webapi example initialized!", .{});
}
