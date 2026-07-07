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

const COLUMN_COUNT = 10;
const ROW_COUNT = 10;
const PADDING_H = 10;
const PADDING_V = PADDING_H;
const SHAPE_WIDTH = 20;
const SHAPE_HEIGHT = SHAPE_WIDTH;

pub fn run() void {
    while (true) {
        var merging_squares_buffer: [10]LevelState.Merging = undefined;
        var hexagons_buffer: [10]Shape = undefined;
        var vfx_buffer: [10]Entity = undefined;
        var sfx_buffer: [10]rl.Sound = undefined;
        LevelState.is_defined = true;
        level = .{
            .merging_squares = .initBuffer(&merging_squares_buffer),
            .hexagons = .initBuffer(&hexagons_buffer),
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
    var bg_hue = Color.red.toHSV().x;

    for (&level.squares) |*column| {
        for (column) |*square| {
            square.* = Shape{
                .kind = .square,
                .color = Color.fromHSV(core.rng.float(f32) * 360.0, 1.0, 1.0),
                .x_px = 0,
                .y_px = 0,
                .clickable = true,
            };
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
        const do_update = switch (core.menus.update()) {
            .no_change => !core.isPaused(),
            .closed => false,
            .exit_level => return false,
        };

        // Update
        if (do_update) {
            std.debug.assert(!core.isPaused());
            if (inputs.buttonPressed(.pause, .{})) {
                core.pause();
            }

            // Update HUD
            {}

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

            bg_hue += 0.5;
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

            const GRID_HEIGHT = SHAPE_HEIGHT * ROW_COUNT +
                PADDING_V * (ROW_COUNT - 1);
            comptime std.debug.assert(GRID_HEIGHT <= game_height);
            const MARGIN_V = (game_height - GRID_HEIGHT) / 2;
            const GRID_WIDTH = SHAPE_WIDTH * COLUMN_COUNT +
                PADDING_H * (COLUMN_COUNT - 1);
            comptime std.debug.assert(GRID_WIDTH <= game_width);
            const MARGIN_H = (game_width - GRID_WIDTH) / 2;

            inline for (&level.squares, 0..) |*column, x| {
                inline for (column, 0..) |*square, y| {
                    drawShape(square.*, .{ .at = .{
                        MARGIN_H + (SHAPE_WIDTH + PADDING_H) * x,
                        MARGIN_V + (SHAPE_HEIGHT + PADDING_V) * y,
                    } });
                }
            }

            rl.beginTextureMode(game_texture);

            // Draw HUD
            if (!core.isPaused()) {
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
                        7.5,
                        if (flash) pico8_colors.pink else pico8_colors.white,
                        .{ .kind = .{ .outline = if (flash) pico8_colors.red else pico8_colors.dark_blue } },
                    );
                }
            }

            // Draw pause menu
            if (core.isPaused()) {
                draw.rectangle(.init(0, 0, game_width, game_height), Color.gray.alpha(0.2));
                core.menus.drawMenu(text_texture);
                rl.beginTextureMode(game_texture);
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
    squares: [COLUMN_COUNT][ROW_COUNT]Shape = @splat(@splat(Shape{})),
    merging_squares: std.ArrayList(Merging) = .empty,
    hexagons: std.ArrayList(Shape) = .empty,

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
        mover: Shape,
        dest_x: u8,
        dest_y: u8,
    };

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
                    std.debug.print("Can't add sfx '{s}': already at max\n", .{assets.fetchSoundName(sound)});
                    std.debug.print(" sfx in buffer: ", .{});
                    for (0..level.sfx.items.len) |i| {
                        if (i > 0) std.debug.print(", ", .{});
                        std.debug.print("{s}", .{assets.fetchSoundName(level.sfx.items[i])});
                    }
                    std.debug.print("\n", .{});
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
    kind: enum {
        empty,
        square,
        diamond,
        hexagon,
    } = .empty,
    color: Color = .black,
    x_px: f32 = 0,
    y_px: f32 = 0,
    scale: f32 = 1,
    clickable: bool = false,
};

//
// Drawing
//

fn drawShape(
    shape: Shape,
    position: union(enum) {
        at_its_own_position,
        at: struct { f32, f32 },
    },
) void {
    const x: f32, const y: f32 = switch (position) {
        .at_its_own_position => .{ shape.x_px, shape.y_px },
        .at => |pos| pos,
    };
    switch (shape.kind) {
        .empty => {},
        .square => {
            draw.rectangle(.{
                .x = @trunc(x - SHAPE_WIDTH / 2),
                .y = @trunc(y - SHAPE_HEIGHT / 2),
                .width = SHAPE_WIDTH,
                .height = SHAPE_HEIGHT,
            }, shape.color);
        },
        .diamond, .hexagon => @panic("not implemented yet"),
    }
}
