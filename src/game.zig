const std = @import("std");
const Allocator = std.mem.Allocator;
const c_allocator = std.heap.c_allocator;
const rl = @import("raylib");

const core = @import("engine/core.zig");
const assets = core.assets;
const draw = core.draw;
const inputs = core.inputs;
const i18n = core.i18n;
const level_format = core.level_format;
const math = core.math;
const util = core.util;
const windowing = core.windowing;
const Timer = core.Timer;
const Color = draw.Color;
const SpriteSheet = draw.SpriteSheet;
const Rectangle = math.Rectangle;
const Vector2 = math.Vector2;
const debug = core.debug;
const pico8_colors = draw.pico8_colors;
const game_width = core.game_width;
const game_height = core.game_height;
const game_center = core.game_center;
const FRAMES_PER_SEC = core.FRAMES_PER_SEC;
const FRAME_DELTA = core.FRAME_DELTA;
const takeEntityId = core.takeEntityId;
const rectTopLeft = math.rectTopLeft;
const rectBottomRight = math.rectBottomRight;
const rectCenter = math.rectCenter;
const floorVec = math.floorVec;

const levels_raw = @import("levels.zig");
const Entity = @import("engine/Entity.zig");

const COLUMN_COUNT = 12;
const ROW_COUNT = 12;
const PADDING_H = 15;
const PADDING_V = PADDING_H;
const SHAPE_WIDTH = 35;
const SHAPE_HEIGHT = SHAPE_WIDTH;
const SELECT_WIDTH = SHAPE_WIDTH + PADDING_H;
const SELECT_HEIGHT = SHAPE_HEIGHT + PADDING_V;

const GRID_HEIGHT = SHAPE_HEIGHT * ROW_COUNT +
    PADDING_V * (ROW_COUNT - 1);
comptime {
    std.debug.assert(GRID_HEIGHT <= game_height);
}
const MARGIN_V = (game_height - GRID_HEIGHT) / 2;
const GRID_WIDTH = SHAPE_WIDTH * COLUMN_COUNT +
    PADDING_H * (COLUMN_COUNT - 1);
comptime {
    std.debug.assert(GRID_WIDTH <= game_width);
}
const MARGIN_H = (game_width - GRID_WIDTH) / 2;

pub fn run() void {
    while (true) {
        var merging_squares_buffer: [10]LevelState.Merging = undefined;
        var scoring_hexagons_buffer: [COLUMN_COUNT * ROW_COUNT]LevelState.Scoring = undefined;
        var vfx_buffer: [10]Entity = undefined;
        var sfx_buffer: [10]rl.Sound = undefined;
        LevelState.is_defined = true;
        level = .{
            .merging_squares = .initBuffer(&merging_squares_buffer),
            .scoring_hexagons = .initBuffer(&scoring_hexagons_buffer),
            .vfx = .initBuffer(&vfx_buffer),
            .sfx = .initBuffer(&sfx_buffer),
        };
        defer {
            level = undefined;
        }
        if (runLevel()) {
            // These may not have been called before returning, and it freezes if we don't call these on every frame.
            rl.beginDrawing();
            rl.clearBackground(.black); // it's less jarring if there's a transition
            rl.endDrawing();
            continue;
        }
        break;
    }
}

fn runLevel() bool {
    var game_over_t: ?u32 = null;

    var score: u64 = 0;
    var chain_clear_time_bonus: u64 = 20;
    var time_bonus_flicker_left: f32 = 0;
    var time_left: f32 = 30.0;

    var bg_hue = Color.red.toHSV().x;

    var selected_square: ?GridPosition = null;
    var wrong_choice_timer: f32 = 0;

    for (&level.grid) |*column| {
        for (column) |*square| {
            square.* = .random();
        }
    }

    const high_res_text_scale = draw.high_res_text_scale;

    // Text is drawn at higher resolution. We scale the game screen and copy the drawn text over it.
    const game_texture = rl.loadRenderTexture(game_width, game_height) catch @panic("failed to load render texture (1)");
    const text_texture = rl.loadRenderTexture(game_width * high_res_text_scale, game_height * high_res_text_scale) catch @panic("failed to load render texture (2)");
    const game_texture_highres = rl.loadRenderTexture(game_width * high_res_text_scale, game_height * high_res_text_scale) catch @panic("failed to load render texture (3)");
    while (!rl.windowShouldClose()) {
        core.t += 1;
        windowing.fixWindowRatioIfResized();
        windowing.handleWindowControls();
        inputs.updateButtonsHeld();
        inputs.updateGamepadConnections();

        const SCORE_MAX_DIGITS = std.fmt.comptimePrint("{}", .{std.math.maxInt(@TypeOf(score))}).len;

        const HOVER_FADEOUT_SECS: comptime_float = 0.1;

        const RESTART_BUTTON_RECT = blk: {
            const height = 40;
            break :blk Rectangle{
                .x = MARGIN_H * 2,
                .width = game_width - (MARGIN_H * 2) * 2,
                .y = game_height / 2 - height / 2,
                .height = height,
            };
        };
        const show_restart_button = game_over_t != null and level.scoring_hexagons.items.len == 0;
        var restart_button_is_hovered = false;

        // Update
        {
            time_left -= FRAME_DELTA;
            if (time_left <= 0) {
                time_left = 0;
                if (game_over_t == null) game_over_t = core.t;
            }

            if (show_restart_button) {
                const mouse_pos = rl.getMousePosition();
                if (rl.checkCollisionPointRec(mouse_pos, RESTART_BUTTON_RECT)) {
                    restart_button_is_hovered = true;
                    if (rl.isMouseButtonPressed(.left)) {
                        return true;
                    }
                }
            }

            if (game_over_t == null) update_shapes: {
                wrong_choice_timer -= FRAME_DELTA;
                if (wrong_choice_timer <= 0) {
                    wrong_choice_timer = 0;
                    for (&level.grid) |*column| {
                        for (column) |*shape| {
                            if (shape.effect == .wrong) shape.unmarkWrong();
                        }
                    }
                } else {
                    var count: usize = 0;
                    for (level.grid) |column| {
                        for (column) |shape| {
                            if (shape.effect == .wrong) count += 1;
                        }
                    }
                    std.debug.assert(count > 0);
                }

                const SPAWN_DELAY_FRAMES: comptime_int = 1 * FRAMES_PER_SEC;

                const mouse_pos = rl.getMousePosition();
                var maybe_clicked_pos: ?GridPosition = null;
                inline for (&level.grid, 0..) |*column, grid_x| {
                    inline for (column, 0..) |*shape, grid_y| cont: {
                        const grid_pos = GridPosition{ .x = grid_x, .y = grid_y };
                        const center = gridCenter(grid_pos);

                        if (shape.kind == .empty and core.t - shape.creation_t >= SPAWN_DELAY_FRAMES) {
                            shape.* = .random();
                        }

                        const a_wrong_choice_was_made = wrong_choice_timer > 0;
                        if (!a_wrong_choice_was_made) std.debug.assert(shape.effect != .wrong);
                        if (a_wrong_choice_was_made or !shape.clickable) {
                            if (shape.effect == .hovered) shape.effect = .none;
                            break :cont; // not interactable
                        }

                        switch (shape.effect) {
                            .none => {},
                            .hovered => |*hovered| {
                                hovered.fadeout -= FRAME_DELTA;
                                if (hovered.fadeout <= 0) shape.effect = .none;
                            },
                            .wrong => unreachable,
                        }
                        if (!(@abs(center.x - mouse_pos.x) < SELECT_WIDTH / 2 and
                            @abs(center.y - mouse_pos.y) < SELECT_HEIGHT / 2))
                            break :cont; // not hovered
                        if (!rl.isMouseButtonPressed(.left)) {
                            shape.effect = .{ .hovered = .{ .fadeout = HOVER_FADEOUT_SECS } };
                            break :cont; // not clicked
                        }
                        maybe_clicked_pos = grid_pos;
                    }
                }

                const clicked_pos = maybe_clicked_pos orelse break :update_shapes;
                const clicked = level.gridGet(clicked_pos);
                clicked.effect = .none;
                const other_pos = selected_square orelse {
                    // None already selected
                    switch (clicked.kind) {
                        .empty => @panic("clicked empty square"),
                        .square, .diamond => {
                            selected_square = clicked_pos;
                        },
                        .hexagon => {
                            clearHexagonColorChain(clicked_pos, 1);
                            time_left += @floatFromInt(chain_clear_time_bonus);
                            chain_clear_time_bonus = @max(chain_clear_time_bonus / 2, 1);
                            time_bonus_flicker_left = 0.5;
                        },
                    }
                    break :update_shapes;
                };
                selected_square = null;
                if (other_pos == clicked_pos) {
                    break :update_shapes; // just deselect it
                }

                const other = level.gridGet(other_pos);
                const valid_match =
                    clicked.kind == .diamond and other.kind == .square or
                    clicked.kind == .square and other.kind == .diamond;
                if (!valid_match) {
                    clicked.markWrong();
                    other.markWrong();
                    wrong_choice_timer = 1.0;
                    break :update_shapes; // invalid match
                }

                other.clickable = false;
                level.merging_squares.appendBounded(.{
                    .shape = clicked.*,
                    .start = gridCenter(clicked_pos),
                    .end = gridCenter(other_pos),
                    .start_t = core.t,
                    .dest_grid_pos = other_pos,
                }) catch @panic("too many merging shapes");
                clicked.* = .{ .creation_t = core.t };
            } else {
                wrong_choice_timer = 0;
                for (&level.grid) |*column| {
                    for (column) |*shape| {
                        shape.clickable = false;
                        shape.effect = .none;
                    }
                }
            }

            // Update moving shapes
            if (game_over_t == null) {
                var i: usize = level.merging_squares.items.len;
                while (i > 0) {
                    i -= 1;
                    var merging = &level.merging_squares.items[i];
                    const pos = &merging.position;
                    const anim_position = util.toF32(core.t - merging.start_t) / FRAMES_PER_SEC;
                    const anim_duration = 0.2;
                    pos.* = Vector2.lerp(merging.start, merging.end, @min(anim_position / anim_duration, 1));

                    if (anim_position >= anim_duration) {
                        const merging_copy = level.merging_squares.swapRemove(i);
                        merging = undefined; // there's now a different one (or nothing) in that slot.

                        const new_hexagon = level.gridGet(merging_copy.dest_grid_pos);
                        new_hexagon.kind = .hexagon;
                        const old_h, const s, const v = math.vecXYZ(new_hexagon.color.toHSV());
                        const merging_h = merging_copy.shape.color.toHSV().x;
                        new_hexagon.color = Color.fromHSV(math.mixHues(old_h, merging_h), s, v);
                        new_hexagon.clickable = true;
                    }
                }
            }
            {
                var i: usize = level.scoring_hexagons.items.len;
                while (i > 0) {
                    i -= 1;
                    var scoring = &level.scoring_hexagons.items[i];
                    const pos = &scoring.position;
                    const anim_position =
                        if (core.t < scoring.start_t)
                            0.0
                        else
                            util.toF32(core.t - scoring.start_t) / FRAMES_PER_SEC;
                    const anim_duration = 0.5;
                    pos.* = Vector2.lerp(scoring.start, scoring.end, @min(anim_position / anim_duration, 1));

                    if (anim_position >= anim_duration) {
                        score += scoring.award;
                        _ = level.scoring_hexagons.swapRemove(i);
                        scoring = undefined; // there's now a different one (or nothing) in that slot.
                    }
                }
            }

            // Remove finished sound effects
            {
                var i: usize = level.sfx.items.len;
                while (i > 0) {
                    i -= 1;
                    const sound = level.sfx.items[i];
                    if (!rl.isSoundPlaying(sound)) {
                        _ = level.sfx.swapRemove(i);
                    }
                }
            }
        }

        rl.beginTextureMode(text_texture);
        rl.clearBackground(.blank);
        rl.endTextureMode();

        rl.beginTextureMode(game_texture);
        {
            defer rl.endTextureMode();

            bg_hue += 60.0 / 2 * FRAME_DELTA;
            rl.clearBackground(Color.fromHSV(bg_hue, 0.5, 0.5));

            // Draw vfx, behind entities
            {
                var i: usize = level.vfx.items.len;
                while (i > 0) {
                    i -= 1;
                    const vfx = &level.vfx.items[i];
                    draw.drawEntity(vfx);
                    if (vfx.isAnimDone()) {
                        _ = level.vfx.swapRemove(i);
                    }
                }
            }

            // Draw lines between similar hexagons
            if (game_over_t == null) {
                inline for (0..level.grid.len) |grid_x| {
                    inline for (0..level.grid[0].len) |grid_y| next_shape: { // can't use "continue" because of "inline"
                        const shape = level.grid[grid_x][grid_y];
                        const shape_pos = gridCenter(.{ .x = grid_x, .y = grid_y });
                        if (shape.kind != .hexagon) break :next_shape;

                        for (RIGHT_DOWN) |dir| {
                            const dx, const dy = dir;
                            var x: i16 = grid_x;
                            var y: i16 = grid_y;
                            x += dx;
                            y += dy;
                            if (x == COLUMN_COUNT or y == ROW_COUNT) continue;
                            std.debug.assert((x >= 1 and y >= 1) or ((x == 0) != (y == 0)));
                            std.debug.assert(x < COLUMN_COUNT);
                            std.debug.assert(y < ROW_COUNT);

                            const other = level.grid[@intCast(x)][@intCast(y)];
                            if (adjacentShapesCanChain(shape, other)) {
                                const other_pos = gridCenter(.{ .x = @intCast(x), .y = @intCast(y) });
                                const thickness: f32 = 6;
                                const color1 = shape.color;
                                const color2 = other.color;
                                switch (dy) {
                                    // Left to right
                                    0 => draw.rectangleGradient(.{
                                        .x = shape_pos.x,
                                        .y = shape_pos.y - thickness / 2,
                                        .width = other_pos.x - shape_pos.x,
                                        .height = thickness,
                                    }, color1, color1, color2, color2),
                                    // Top to bottom
                                    1 => draw.rectangleGradient(.{
                                        .x = shape_pos.x - thickness / 2,
                                        .y = shape_pos.y,
                                        .width = thickness,
                                        .height = other_pos.y - shape_pos.y,
                                    }, color1, color2, color2, color1),
                                    else => unreachable,
                                }
                            }
                        }
                    }
                }
            }
            // Draw shapes
            @setEvalBranchQuota(COLUMN_COUNT * ROW_COUNT * 4);
            inline for (level.grid, 0..) |column, grid_x| {
                inline for (column, 0..) |shape, grid_y| {
                    const grid_pos = GridPosition{ .x = grid_x, .y = grid_y };
                    const center = gridCenter(grid_pos);
                    const bg_color: Color =
                        if (selected_square == grid_pos)
                            Color.white
                        else switch (shape.effect) {
                            .none => Color.blank,
                            .hovered => |hovered| Color.white.alpha(0.7 * hovered.fadeout / HOVER_FADEOUT_SECS),
                            .wrong => Color.red,
                        };
                    draw.rectangle(.{
                        .x = center.x - SELECT_WIDTH / 2,
                        .y = center.y - SELECT_HEIGHT / 2,
                        .width = SELECT_WIDTH,
                        .height = SELECT_HEIGHT,
                    }, bg_color);
                    const SPAWN_ANIM_FRAMES = 1 * FRAMES_PER_SEC;
                    const GAME_OVER_ANIM_FRAMES = 1 * FRAMES_PER_SEC;
                    drawShape(shape, center, .{
                        .scale = if (game_over_t) |got|
                            @max(1.0 - util.toF32(core.t - got) / GAME_OVER_ANIM_FRAMES, 0.0)
                        else
                            @min(util.toF32(core.t - shape.creation_t) / SPAWN_ANIM_FRAMES, 1.0),
                    });
                }
            }

            if (game_over_t == null) {
                for (level.merging_squares.items) |merging| {
                    drawShape(merging.shape, merging.position, .{});
                }
            }
            for (level.scoring_hexagons.items) |scoring| {
                const pos = scoring.position;
                drawShape(scoring.shape, pos, .{ .scale = 2 });
                var buffer: [SCORE_MAX_DIGITS + 1]u8 = undefined;
                const text = std.fmt.bufPrintZ(&buffer, "{}", .{scoring.award}) catch unreachable;
                const text_size = core.windowing.textSize(text, HUD_FONT_SIZE);
                _ = draw.textHighRes(
                    text,
                    pos.x - text_size.x / 2,
                    pos.y - text_size.y / 2,
                    assets.font,
                    HUD_FONT_SIZE,
                    SHAPE_OUTLINE_COLOR,
                    null,
                );
            }

            rl.beginTextureMode(game_texture);

            // Draw HUD
            {
                {
                    var buffer: ["Score: ".len + SCORE_MAX_DIGITS + 1]u8 = undefined;
                    const text = std.fmt.bufPrintZ(&buffer, "Score: {}", .{score}) catch unreachable;
                    _ = draw.textHighRes(
                        text,
                        SCORE_TEXT_POSITION.x,
                        SCORE_TEXT_POSITION.y,
                        assets.font,
                        HUD_FONT_SIZE,
                        HUD_FONT_COLOR,
                        HUD_TEXT_EFFECT,
                    );
                }
                {
                    const top = game_height - MARGIN_V + (MARGIN_V - HUD_FONT_SIZE) / 2;
                    var x: f32 = MARGIN_H / 2;

                    const max_time_digits = 10;
                    var time_buffer: ["Time: ".len + max_time_digits + " ".len + 1]u8 = undefined;
                    const time_text = std.fmt.bufPrintZ(&time_buffer, "Time: {d:.0} ", .{time_left}) catch unreachable;
                    x += draw.textHighRes(
                        time_text,
                        x,
                        top,
                        assets.font,
                        HUD_FONT_SIZE,
                        HUD_FONT_COLOR,
                        HUD_TEXT_EFFECT,
                    );

                    time_bonus_flicker_left = @max(time_bonus_flicker_left - FRAME_DELTA, 0);
                    // When flickering, alternate on/off every 0.1 seconds.
                    if (time_bonus_flicker_left == 0 or @as(u32, @trunc(time_bonus_flicker_left * 10)) % 2 == 0) {
                        var bonus_buffer: ["Clear bonus: 20".len + 1]u8 = undefined;
                        const bonus_text = std.fmt.bufPrintZ(&bonus_buffer, "Clear bonus: {}", .{chain_clear_time_bonus}) catch unreachable;
                        _ = draw.textHighRes(
                            bonus_text,
                            x,
                            top + 9,
                            assets.font,
                            HUD_FONT_SIZE / 2,
                            HUD_FONT_COLOR,
                            blk: {
                                var text_effect = HUD_TEXT_EFFECT;
                                text_effect.scale /= 2;
                                break :blk text_effect;
                            },
                        );
                    }
                }

                if (debug.show_fps) {
                    rl.endTextureMode();
                    rl.beginTextureMode(text_texture);
                    defer {
                        rl.endTextureMode();
                        rl.beginTextureMode(game_texture);
                    }

                    const fps = rl.getFPS();
                    var buffer: ["1000fps".len + 1]u8 = undefined;
                    const text = std.fmt.bufPrintZ(&buffer, "{d}fps", .{fps}) catch unreachable;
                    const flash = fps < 60;
                    _ = draw.textHighRes(
                        text,
                        4,
                        4,
                        assets.font,
                        HUD_FONT_SIZE,
                        if (flash) pico8_colors.pink else pico8_colors.white,
                        .{ .kind = .{ .outline = if (flash) pico8_colors.red else pico8_colors.dark_blue } },
                    );
                }
            }

            if (show_restart_button) {
                const brightness_modifier: f32 = if (restart_button_is_hovered) 0.3 else 0.0;
                draw.rectangle(
                    RESTART_BUTTON_RECT,
                    Color.green.brightness(brightness_modifier),
                );
                draw.rectangleLines(
                    RESTART_BUTTON_RECT,
                    SHAPE_OUTLINE_THICKNESS,
                    Color.dark_green.brightness(brightness_modifier),
                );
                const text = "Play Again";
                const font_size = assets.en_font_size / 2;
                const text_size = windowing.textSize(text, font_size);
                _ = draw.textHighRes(
                    text,
                    RESTART_BUTTON_RECT.x + (RESTART_BUTTON_RECT.width - text_size.x) / 2,
                    RESTART_BUTTON_RECT.y + (RESTART_BUTTON_RECT.height - text_size.y) / 2,
                    assets.font,
                    font_size,
                    .white,
                    .{
                        .kind = .{ .outline = SHAPE_OUTLINE_COLOR.brightness(brightness_modifier) },
                        .scale = SHAPE_OUTLINE_THICKNESS / 2,
                    },
                );
            }

            // Draw debug
            if (debug.misc) {}
        }

        rl.beginTextureMode(game_texture_highres);
        {
            defer rl.endTextureMode();

            draw.textureRec(
                game_texture.texture,
                .init(0, 0, game_width * high_res_text_scale, game_height * high_res_text_scale),
                .{
                    .source = .init(0, 0, game_width, game_height),
                },
            );
            draw.textureRec(
                text_texture.texture,
                .init(0, 0, game_width * high_res_text_scale, game_height * high_res_text_scale),
                .{
                    .source = .init(0, 0, game_width * high_res_text_scale, game_height * high_res_text_scale),
                },
            );
        }

        rl.beginDrawing();
        {
            defer rl.endDrawing();

            rl.clearBackground(.black);
            const display_offset = windowing.display_offset;
            const f_display_scale = windowing.fDisplayScale();
            var dest = Rectangle.init(0, 0, game_width, game_height);
            dest.x *= f_display_scale;
            dest.y *= f_display_scale;
            dest.x += display_offset.x;
            dest.y += display_offset.y;
            dest.width *= f_display_scale;
            dest.height *= f_display_scale;
            draw.textureRec(
                game_texture_highres.texture,
                dest,
                .{
                    .source = .init(0, 0, game_width * high_res_text_scale, game_height * high_res_text_scale),
                },
            );
        }
    }

    return false;
}

const HUD_FONT_SIZE = assets.en_font_size;
const HUD_FONT_COLOR = Color.white;
const HUD_TEXT_EFFECT: draw.TextEffect = .{
    .kind = .{ .outline = SHAPE_OUTLINE_COLOR },
    .scale = SHAPE_OUTLINE_THICKNESS,
};
const SCORE_TEXT_POSITION = Vector2{
    .x = MARGIN_H / 2,
    .y = (MARGIN_V - HUD_FONT_SIZE) / 2,
};

const RIGHT_DOWN: [2]struct { i8, i8 } = .{
    .{ 1, 0 },
    .{ 0, 1 },
};
const UP_DOWN_LEFT_RIGHT: [4]struct { i8, i8 } = .{
    .{ -1, 0 },
    .{ 0, -1 },
} ++ RIGHT_DOWN;

fn gridCenter(grid_pos: GridPosition) Vector2 {
    return .{
        .x = MARGIN_H + (SHAPE_WIDTH + PADDING_H) * util.toF32(grid_pos.x) + SHAPE_WIDTH / 2,
        .y = MARGIN_V + (SHAPE_HEIGHT + PADDING_V) * util.toF32(grid_pos.y) + SHAPE_HEIGHT / 2,
    };
}

/// Assumes that the shapes are adjacent.
fn adjacentShapesCanChain(a: Shape, b: Shape) bool {
    return a.kind == .hexagon and b.kind == .hexagon and
        math.hueDistance(a.color.toHSV().x, b.color.toHSV().x) < 30;
}

fn clearHexagonColorChain(grid_pos: GridPosition, award: u64) void {
    const shape_ptr = level.gridGet(grid_pos);
    const shape = shape_ptr.*;
    shape_ptr.* = .{ .creation_t = core.t };

    std.debug.assert(shape.kind == .hexagon);
    const delay_secs = 0.1 * @as(f32, @floatFromInt(award - 1));
    level.scoring_hexagons.appendBounded(.{
        .award = award,
        .shape = shape,
        .start = gridCenter(grid_pos),
        .end = SCORE_TEXT_POSITION,
        .start_t = core.t + @as(u32, @trunc(delay_secs * FRAMES_PER_SEC)),
    }) catch @panic("too many scoring hexagons");

    for (UP_DOWN_LEFT_RIGHT) |dir| {
        const dx, const dy = dir;
        var x: i16 = grid_pos.x;
        var y: i16 = grid_pos.y;
        x += dx;
        y += dy;
        if (x < 0 or
            x >= COLUMN_COUNT or
            y < 0 or
            y >= ROW_COUNT) continue;

        const next_pos = GridPosition{ .x = @intCast(x), .y = @intCast(y) };
        const next = level.gridGet(next_pos).*;
        if (!adjacentShapesCanChain(shape, next)) continue;

        clearHexagonColorChain(next_pos, award + 1);
    }
}

pub fn showError(text: [:0]const u8) void {
    const font_size = 15;
    const margin = 4;
    const wrapped_msg = util.wordWrapZ(c_allocator, windowing.textWidth, text, font_size, game_width - margin * 2) catch {
        @panic("OOM");
    };

    while (!rl.windowShouldClose()) {
        windowing.fixWindowRatioIfResized();
        rl.beginDrawing();
        windowing.handleWindowControls();
        rl.clearBackground(.white);
        _ = draw.textSized(wrapped_msg, margin, margin, font_size, .black);
        rl.endDrawing();
    }
}

const game = @This();

//
// Level Stuff
// todo: might move this stuff (except the var) to its own file. probably rename levels_raw to LevelData.
//

// todo: should probably make this optional instead, it's safer. ".?" isn't a big deal.
pub var level: LevelState = undefined;

pub const LevelState = struct {
    grid: [COLUMN_COUNT][ROW_COUNT]Shape = @splat(@splat(Shape{ .creation_t = 0 })),
    merging_squares: std.ArrayList(Merging) = .empty,
    scoring_hexagons: std.ArrayList(Scoring) = .empty,

    /// Custom animations. Automatically removed when the anim is done, but otherwise
    /// controlled by whatever code added them.
    vfx: std.ArrayList(Entity) = .empty,
    /// Sound effects are actually kept track of by Raylib, but there's no good way to
    /// query them, so we keep track of them ourselves.
    sfx: std.ArrayList(rl.Sound) = .empty,

    /// todo: this will go away once `game.level` is made nullable.
    _defined_check: bool = true,

    pub var is_defined: bool = false;

    pub const Merging = struct {
        shape: Shape,
        position: Vector2 = .{ .x = 0, .y = 0 },
        start: Vector2,
        end: Vector2,
        start_t: u32,
        dest_grid_pos: GridPosition,
    };
    pub const Scoring = struct {
        award: u64,
        shape: Shape,
        position: Vector2 = .{ .x = 0, .y = 0 },
        start: Vector2,
        end: Vector2,
        start_t: u32,
    };

    pub fn gridGet(self: *LevelState, pos: GridPosition) *Shape {
        return &self.grid[pos.x][pos.y];
    }

    pub const PlaySfxOptions = struct {
        /// Used for panning.
        pos: ?Vector2 = null,
        /// Only if (re)starting playback. Randomized by default.
        pitch: ?struct {
            /// The docs say 1.0 is default.
            base: f32,
            /// Random amount above or below `base`.
            range: f32,
            pub fn fixed(n: f32) @This() {
                return .{ .base = n, .range = 0 };
            }
        } = .{ .base = 1.0, .range = 0.2 },
        /// Only if (re)starting playback. Not randomized by default.
        volume: ?struct {
            /// The docs say this shouldn't go above 1.0.
            max: f32,
            /// Random amount below `max`.
            range: f32,
            pub fn fixed(n: f32) @This() {
                return .{ .max = n, .range = 0 };
            }
        } = .fixed(0.5),
    };
    pub const SfxAlreadyPlayingAction = enum { restart, update_pos };

    pub fn playSoundEffect(_self: *LevelState, sound: rl.Sound, if_already_playing: SfxAlreadyPlayingAction, options: PlaySfxOptions) error{OutOfMemory}!void {
        std.debug.assert(_self == &level);
        if (options.pos) |pos| {
            rl.setSoundPan(sound, 1 - rl.getWorldToScreen2D(pos, level.camera_raw).x / game_width);
        }
        const in_array = for (level.sfx.items) |snd| {
            if (snd.stream.buffer == sound.stream.buffer) break true;
        } else false;
        if (!in_array) {
            level.sfx.appendBounded(sound) catch |e| switch (e) {
                error.OutOfMemory => {
                    std.log.err("Can't add sfx '{s}': already at max\n", .{assets.fetchSoundName(sound)});
                    std.log.err(" sfx in buffer: ", .{});
                    for (0..level.sfx.items.len) |i| {
                        if (i > 0) std.log.err(", ", .{});
                        std.log.err("{s}", .{assets.fetchSoundName(level.sfx.items[i])});
                    }
                    std.log.err("\n", .{});
                    return error.OutOfMemory;
                },
            };
        }
        const should_play: bool = switch (if_already_playing) {
            .restart => true,
            .update_pos => !rl.isSoundPlaying(sound),
        };
        if (should_play) {
            if (options.volume) |volume| {
                rl.setSoundVolume(sound, volume.max - core.rng.float(f32) * volume.range);
            }
            if (options.pitch) |pitch| {
                rl.setSoundPitch(sound, pitch.base + (core.rng.float(f32) - 0.5) * pitch.range);
            }
            rl.playSound(sound);
        }
    }
};

pub const Shape = struct {
    creation_t: u32,
    kind: Kind = .empty,
    color: Color = .black,
    clickable: bool = false,
    effect: union(enum) {
        none,
        hovered: struct { fadeout: f32 },
        /// Fadeout time is handled globally.
        wrong,
    } = .none,

    pub fn random() Shape {
        return .{
            .creation_t = core.t,
            .kind = if (core.rng.boolean()) .square else .diamond,
            .color = Color.fromHSV(core.rng.float(f32) * 360.0, 1.0, 1.0),
            .clickable = true,
        };
    }

    pub fn markWrong(self: *Shape) void {
        self.clickable = false;
        self.effect = .wrong;
    }
    pub fn unmarkWrong(self: *Shape) void {
        self.clickable = true;
        self.effect = .none;
    }

    pub const Kind = enum {
        empty,
        square,
        diamond,
        hexagon,
    };
};

pub const GridPosition = packed struct {
    x: Int = 0,
    y: Int = 0,
    pub const Int = u8;
};

//
// Drawing
//

const SHAPE_OUTLINE_THICKNESS = 4;
const SHAPE_OUTLINE_COLOR = Color.black;

fn drawShape(shape: Shape, at: Vector2, options: struct {
    scale: f32 = 1,
}) void {
    const width = SHAPE_WIDTH * options.scale;
    const height = SHAPE_HEIGHT * options.scale;
    const radius = (SHAPE_WIDTH / 2) * options.scale;
    std.debug.assert(SHAPE_WIDTH == SHAPE_HEIGHT);
    const left = at.x - radius;
    const top = at.y - radius;
    switch (shape.kind) {
        .empty => {},
        .square => {
            const rect = Rectangle.init(left, top, width, height);
            draw.rectangle(rect, shape.color);
            draw.rectangleLines(rect, SHAPE_OUTLINE_THICKNESS, SHAPE_OUTLINE_COLOR);
        },
        .diamond => {
            draw.polygon(at, 4, radius, 0, shape.color);
            draw.polygonLines(at, 4, radius, 0, SHAPE_OUTLINE_THICKNESS, SHAPE_OUTLINE_COLOR);
        },
        .hexagon => {
            const rotation = util.decPartF(util.toF32(core.t) / FRAMES_PER_SEC) * 60;
            draw.polygon(at, 6, radius, rotation, shape.color);
            draw.polygonLines(at, 6, radius, rotation, SHAPE_OUTLINE_THICKNESS, SHAPE_OUTLINE_COLOR);
        },
    }
}
