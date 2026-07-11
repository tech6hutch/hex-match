const std = @import("std");
const c_allocator = std.heap.c_allocator;
const rl = @import("raylib");
const core = @import("engine/core.zig");
const game = @import("game.zig");

pub const is_web = @import("builtin").os.tag == .emscripten;

pub const std_options: std.Options = if (is_web) .{
    .networking = false,
    .logFn = logFn,
} else .{};
pub fn logFn(
    comptime message_level: std.log.Level,
    comptime scope: @EnumLiteral(),
    comptime format: []const u8,
    args: anytype,
) void {
    const rl_log_level: rl.TraceLogLevel = switch (message_level) {
        .err => .err,
        .warn => .warning,
        .info => .info,
        .debug => .debug,
    };
    var log_buf: [1024]u8 = undefined;
    const text = std.fmt.bufPrintSentinel(
        &log_buf,
        (if (scope == .default) "" else "(" ++ @tagName(scope) ++ ")") ++ format,
        args,
        0,
    ) catch |e| switch (e) {
        error.NoSpaceLeft => std.fmt.comptimePrint("[message longer than {} chars]", .{log_buf.len}),
    };
    rl.traceLog(rl_log_level, text, .{});
}

pub const panic = if (is_web) std.debug.no_panic else std.debug.FullPanic(std.debug.defaultPanic);

pub const main = if (is_web) webMain else desktopMain;

/// This exists because Zig didn't properly test 0.16.0 (and I didn't check before using it for a jam).
pub const IoOrNothing = if (is_web) void else std.Io;

pub fn webMain() !void {
    try _main({});
}
pub fn desktopMain(init: std.process.Init) !void {
    try _main(init.io);
}
fn _main(io: IoOrNothing) !void {
    const setup_err_msg = core.setup(
        if (is_web) {} else io,
        "Hex Match",
        "./assets/press_start_2p/PressStart2P.ttf",
        &.{},
        &.{},
        null,
    );
    if (setup_err_msg) |err_msg| {
        game.showError(err_msg);
        return;
    }

    game.run();
}
