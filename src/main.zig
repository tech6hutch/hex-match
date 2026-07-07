const std = @import("std");
const c_allocator = std.heap.c_allocator;
const rl = @import("raylib");
const core = @import("engine/core.zig");
const util = core.util;
const game = @import("game.zig");
const levels_raw = @import("levels.zig");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const setup_err_msg = core.setup(
        io,
        "Mail Bros.",
        "./assets/press_start_2p/PressStart2P.ttf",
        &.{
            "menu.png",
        },
        &.{},
        null,
    );
    if (setup_err_msg) |err_msg| {
        game.showError(err_msg);
        return;
    }

    game.run();
}
