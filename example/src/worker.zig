const std = @import("std");
const webapi = @import("webapi");

const Event = webapi.Event;
const Worker = webapi.Worker;
const DedicatedScope = Worker.DedicatedWorkerGlobalScope;
const zjb = webapi.zjb;

pub const std_options: std.Options = .{
    .logFn = webapi.console.rootLogFn,
    .log_level = .debug,
};

pub const panic = webapi.panic;

const WorkerApp = struct {
    scope: DedicatedScope,
    msg_count: u32 = 0,

    fn onMessage(self: *WorkerApp, ev: Event.MessageEvent) void {
        const data_h = ev.data();
        defer data_h.release();

        var input_buf: [512]u8 = undefined;
        const input = webapi.stringFromHandle(data_h, &input_buf);
        self.msg_count += 1;

        var name_buf: [64]u8 = undefined;
        const w_name = self.scope.name(&name_buf);

        const nav = self.scope.navigator();
        defer nav.release();
        const cores = nav.hardwareConcurrency();

        const hash = std.hash.Fnv1a_64.hash(input);

        var out_buf: [1024]u8 = undefined;
        const reply = std.fmt.bufPrint(
            &out_buf,
            "worker=\"{s}\" cores={d} msg=#{d}\ninput: \"{s}\" ({d} bytes)\nfnv1a_64: 0x{x:0>16}",
            .{
                if (w_name.len > 0) w_name else "unnamed",
                cores,
                self.msg_count,
                input,
                input.len,
                hash,
            },
        ) catch return;
        self.scope.postText(reply);
    }
};

pub fn main(init: std.process.Init.Minimal) !void {
    _ = init;
    const scope = DedicatedScope.global();
    const app = try std.heap.wasm_allocator.create(WorkerApp);
    app.* = .{ .scope = scope };

    scope.addEventListener("message", WorkerApp, app, WorkerApp.onMessage);

    var name_buf: [64]u8 = undefined;
    const w_name = scope.name(&name_buf);

    const loc = scope.location();
    defer loc.release();
    var path_buf: [256]u8 = undefined;
    const path = loc.getPathname(&path_buf);

    const nav = scope.navigator();
    defer nav.release();
    const cores = nav.hardwareConcurrency();

    var ready_buf: [512]u8 = undefined;
    const ready_msg = std.fmt.bufPrint(
        &ready_buf,
        "Worker \"{s}\" initialized at {s} (hardwareConcurrency={d}).",
        .{ if (w_name.len > 0) w_name else "unnamed", path, cores },
    ) catch "Worker initialized.";
    scope.postText(ready_msg);
}
