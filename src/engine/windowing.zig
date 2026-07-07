const std = @import("std");
const rl = @import("raylib");
const core = @import("core.zig");
const assets = core.assets;
const inputs = core.inputs;
const Vector2 = core.math.Vector2;
const game_width = core.game_width;
const game_height = core.game_height;

pub fn handleWindowControls() void {
    if ((inputs.anyKeyDown(&.{ .left_alt, .right_alt }) and inputs.anyKeyPressed(&.{ .f, .enter })) or
        rl.isKeyPressed(.f11))
    {
        toggleFullscreen();
    }
}

pub fn fixWindowRatioIfResized() void {
    if (!isFullscreen() and rl.isWindowResized()) {
        display_scale = biggestDisplayScaleThatFitsIn(rl.getScreenWidth(), rl.getScreenHeight());
        display_scale = @max(display_scale, core.draw.high_res_text_scale); // can't go lower resolution than the text supports
        rl.setWindowSize(game_width * display_scale, game_height * display_scale);
        cacheDisplayOffset();
    }
}

/// The scale at which to draw game pixels as screen pixels.
pub var display_scale: i32 = 1;
pub inline fn fDisplayScale() f32 {
    return @floatFromInt(display_scale);
}

/// For letterboxing and pillarboxing.
pub var display_offset: Vector2 = .init(0, 0);
inline fn cacheDisplayOffset() void {
    const content_size = Vector2.init(@floatFromInt(game_width), @floatFromInt(game_height)).scale(fDisplayScale());
    const box_size: Vector2 = if (isFullscreen()) .{
        .x = @floatFromInt(rl.getMonitorWidth(rl.getCurrentMonitor())),
        .y = @floatFromInt(rl.getMonitorHeight(rl.getCurrentMonitor())),
    } else .{
        .x = @floatFromInt(rl.getScreenWidth()),
        .y = @floatFromInt(rl.getScreenHeight()),
    };
    display_offset = box_size.subtract(content_size).scale(0.5);
}

pub fn toggleFullscreen() void {
    rl.toggleBorderlessWindowed();
    if (!isFullscreen()) {
        // Disabling fullscreen
        display_scale = @divTrunc(rl.getScreenWidth(), game_width);
    } else {
        // Enabling fullscreen
        const monitor = rl.getCurrentMonitor();
        display_scale = biggestDisplayScaleThatFitsIn(rl.getMonitorWidth(monitor), rl.getMonitorHeight(monitor));
    }
    cacheDisplayOffset();
}

pub fn isFullscreen() bool {
    return rl.isWindowState(.{ .borderless_windowed_mode = true });
}

/// Returns the biggest multiple of the window size that can fit in the given bounds.
fn biggestDisplayScaleThatFitsIn(width: i32, height: i32) i32 {
    const w_scale = @divTrunc(width, game_width);
    const h_scale = @divTrunc(height, game_height);
    return @max(@min(w_scale, h_scale), 1);
}

pub fn textWidth(text: [:0]const u8, fontSize: f32) f32 {
    return textSize(text, fontSize).x;
}

pub fn textSize(text: [:0]const u8, fontSize: f32) Vector2 {
    return rl.measureTextEx(assets.font, text, fontSize, 0);
}

/// Returns the width in text-resolution-sized pixels.
pub fn textWidthAscii(text_len: usize) usize {
    const char_width = 8;
    if (core.debug.misc) {
        const font = assets.font;
        var idx: usize = 0;
        const m_width: c_int = while (idx < font.glyphCount) : (idx += 1) {
            if (font.glyphs[idx].value == 'm') {
                break @divExact(font.glyphs[idx].advanceX, assets.en_font_size);
            }
        } else std.debug.panic("no 'm' found in ascii font", .{});
        core.util.expectEq(c_int, m_width, char_width, .panic);
    }
    return text_len * char_width / core.draw.high_res_text_scale;
}
