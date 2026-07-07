const std = @import("std");
const c_allocator = std.heap.c_allocator;
const rl = @import("raylib");
pub const Entity = @import("Entity.zig");
pub const assets = @import("assets.zig");
pub const audio = @import("audio.zig");
pub const draw = @import("draw.zig");
pub const inputs = @import("inputs.zig");
pub const i18n = @import("internationalization.zig");
pub const level_format = @import("level_format.zig");
pub const math = @import("math.zig");
pub const menus = @import("menus.zig");
pub const util = @import("util.zig");
pub const windowing = @import("windowing.zig");
const Vector2 = math.Vector2;

pub const debug = struct {
    /// Enables various debugging things. Should be set to false for release builds.
    pub const misc = true;

    pub var show_fps = false;
    pub var animation_disabled = false;
    pub var animation_advance_once = false;

    pub const allocator = c_allocator;
};

pub const game_width = 720;
pub const game_height = 720;
pub const game_center = Vector2{
    .x = game_width / 2.0,
    .y = game_height / 2.0,
};
pub const game_size_in_tiles = Vector2{
    .x = @as(comptime_float, game_width) / 8.0,
    .y = @as(comptime_float, game_height) / 8.0,
};

/// The target FPS. Dev(s): lower this (separately from FRAME_DELTA) for slow-mo.
pub const FRAMES_PER_SEC = 60;
/// The (minimum) time, in seconds, between frames. This game uses a fixed time-step.
pub const FRAME_DELTA = 1.0 / 60.0;

/// Frames since game start. May crash if the game runs for over two years.
pub var t: u32 = 0;
/// Call setup() before using.
pub var rng: std.Random = undefined;
var rng_impl: std.Random.IoSource = undefined;
pub var lang: i18n.Lang = .en;

/// Returns an error message if anything went wrong.
pub fn setup(
    io: std.Io,
    window_title: [:0]const u8,
    font_path: [:0]const u8,
    comptime texture_names: []const []const u8,
    comptime sound_names: []const []const u8,
    localizations_path: ?[]const u8,
) ?[:0]const u8 {
    rng_impl = .{ .io = io };
    rng = rng_impl.interface();

    rl.setTraceLogLevel(.warning);
    rl.setConfigFlags(.{ .window_resizable = true });
    {
        const window_width = game_width * windowing.display_scale;
        const window_height = game_height * windowing.display_scale;
        // If the window is bigger than the screen, it doesn't load correctly. (2026-07-07)
        if (window_width > 720 or window_height > 720) std.debug.panic(
            "{d}x{d} is kinda big, are you sure?",
            .{ window_width, window_height },
        );
        rl.initWindow(window_width, window_height, window_title);
    }
    rl.setTargetFPS(FRAMES_PER_SEC);
    rl.setExitKey(.null);

    assets.font = rl.loadFont(font_path) catch return
        \\Failed to load font.
        \\
        \\Make sure you extracted them.
    ;

    rl.initAudioDevice(); // must be init'd before loading sounds

    assets.textures = @TypeOf(assets.textures).init(c_allocator, texture_names) catch @panic("OOM");
    inline for (texture_names) |name| {
        assets.textures.put(name, rl.loadTexture("./assets/" ++ name) catch return
            \\Failed to load textures.
            \\
            \\Make sure you extracted all of them.
        );
    }

    assets.sounds = @TypeOf(assets.sounds).init(c_allocator, sound_names) catch @panic("OOM");
    inline for (sound_names) |name| {
        assets.sounds.put(name, rl.loadSound("./assets/" ++ name) catch return
            \\Failed to load sounds.
            \\
            \\Make sure you extracted all of them.
        );
    }

    std.debug.print("Loaded {d} textures and {d} sounds\n", .{ assets.textures.inner.size, assets.sounds.inner.size });

    if (localizations_path) |path| {
        i18n.loadCsvFile(io, c_allocator, path) catch |e| {
            std.debug.print("Error loading translations: {t}\n", .{e});
            return
            \\Failed to load translations.
            ;
        };
    }

    return null;
}

/// I don't actually think it's necessary to call these if you're just exiting
/// the program. But here they are, just in case.
pub fn shutdown() void {
    rl.closeAudioDevice();
    rl.closeWindow();
}

/// Returns the rectangle screen-wrapped to the left and right.
pub fn getRectScreenWrapped(rect: math.Rectangle) [3]math.Rectangle {
    return .{
        .{ .y = rect.y, .width = rect.width, .height = rect.height, .x = rect.x - game_width },
        .{ .y = rect.y, .width = rect.width, .height = rect.height, .x = rect.x },
        .{ .y = rect.y, .width = rect.width, .height = rect.height, .x = rect.x + game_width },
    };
}

//
// Entity Management
//

pub const EntityId = enum(i32) {
    /// No entity, not found, invalid, etc.
    none = -1,
    _,
    pub fn format(self: EntityId, writer: anytype) !void {
        try writer.print("{d}", .{@intFromEnum(self)});
    }
};

var next_entity_id: i32 = 0;
/// After billions of IDs, may return duplicates.
pub fn takeEntityId() EntityId {
    // bug: if this wraps around, whatever entity gets -1 will be treated as nonexistent.
    next_entity_id += 1;
    return @enumFromInt(next_entity_id - 1);
}

pub const EntityRef = struct {
    id: EntityId = .none,
    /// Last known index.
    index: u32 = 0,
    pub fn format(self: EntityRef, writer: anytype) !void {
        try writer.print("{f}(at {d})", .{ self.id, self.index });
    }
};

pub fn retrieveEntity(items: []Entity, entity_ref: *EntityRef) ?*Entity {
    if (entity_ref.id == .none) return null;
    if (entity_ref.index < items.len) {
        const ent = &items[entity_ref.index];
        if (ent.id == entity_ref.id) return ent;
    }
    for (items, 0..) |*ent, item_index| {
        if (ent.id == entity_ref.id) {
            entity_ref.index = @intCast(item_index);
            return ent;
        }
    }
    entity_ref.id = .none;
    return null;
}

pub fn assertNoDuplicateIds(items: []const Entity) void {
    for (0..items.len) |i| {
        for (i + 1..items.len) |j| {
            if (items[i].id == items[j].id) {
                std.debug.panic("duplicate entity ID found ({f})", .{items[i].id});
            }
        }
    }
}

//
// Misc Gameplay
//

/// Measures time in game frames.
///
/// Timers start out already done and must be restarted.
pub const Timer = struct {
    /// In frames.
    duration: u32,
    /// A frame, in the future if the timer is still running.
    start_t: u32 = 0,
    pub const expired = Timer{ .duration = 0 };
    pub fn withDurationInSecs(duration: f32) Timer {
        return .{ .duration = @intFromFloat(@round(duration * FRAMES_PER_SEC)) };
    }
    pub fn stop(timer: *Timer) void {
        timer.start_t = 0;
    }
    pub fn restart(timer: *Timer) void {
        timer.start_t = t + timer.duration;
    }
    pub fn restartWithDurationInSecs(timer: *Timer, duration: f32) void {
        timer.duration = @intFromFloat(@round(duration * FRAMES_PER_SEC));
        timer.restart();
    }
    pub fn isRunning(timer: Timer) bool {
        return t < timer.start_t;
    }
    pub fn isDone(timer: Timer) bool {
        return !timer.isRunning();
    }
};

pub fn getCameraMinMax(
    level_orientation: level_format.LevelOrientation,
    level_width_in_tiles: i16,
    level_height_in_tiles: i16,
) struct { Vector2, Vector2 } {
    const camera_screen_offset = switch (level_orientation) {
        .horizontal => Vector2{
            .x = 0,
            .y = if (game_size_in_tiles.y % 2 == 0) 0 else 4, // half a block to center it vertically
        },
        .vertical => Vector2{
            .x = 0,
            .y = 0,
        },
    };
    const camera_min = game_center.add(camera_screen_offset);
    const camera_max = level_format.TilePosition.toPixelsTopLeft(.{ .x = level_width_in_tiles, .y = level_height_in_tiles })
        .subtract(game_center);
    return .{ camera_min, camera_max };
}

/// Simple, four-way camera movement (in 2D).
pub fn cameraFollowEnt(ent: Entity, ent_old_pos: Vector2, camera: *rl.Camera2D, camera_min: Vector2, camera_max: Vector2) void {
    const delta = ent.position().subtract(ent_old_pos);
    camera.target.x = ent.centerPosition().x;
    camera.target.y = ent.centerPosition().y;
    // Copy over the fractional part to make it smoother. (Or at least, it feels smoother.)
    if (delta.x != 0) {
        util.setDecPartF(&camera.target.x, ent.x);
    }
    if (delta.y != 0) {
        util.setDecPartF(&camera.target.y, ent.y);
    }
    camera.target = camera.target.clamp(camera_min, camera_max);
}

pub fn pause() void {
    std.debug.assert(menus.stack.items.len == 0); // pause called when already paused?
    menus.open(menus.pause_menu.top_def);
}
pub fn unpause() void {
    menus.close();
}
/// Whether gameplay should pause (whether there's a menu open, of any kind).
pub fn isPaused() bool {
    return menus.stack.items.len > 0;
}

//
// Debugging
//

/// Adds a newline.
pub fn logError(comptime prefix: []const u8, comptime fmt: []const u8, args: anytype) void {
    std.debug.print(prefix ++ ": " ++ fmt ++ "\n", args);
}

/// Wrap the value in a printable type.
pub fn rlFmt(value: anytype) Printable {
    return switch (@TypeOf(value)) {
        draw.Color => .{ .color = value },
        Vector2 => .{ .vec2 = value },
        math.Rectangle => .{ .rect = value },
        else => |ty| @compileError("unsupported type " ++ @typeName(ty)),
    };
}

pub const Printable = union(enum) {
    color: draw.Color,
    vec2: Vector2,
    rect: math.Rectangle,
    pub fn format(p: Printable, writer: anytype) !void {
        switch (p) {
            .color => |c| try writer.print("{d},{d},{d},{d}", .{ c.r, c.g, c.b, c.a }),
            .vec2 => |v| try writer.print("{d},{d}", .{ v.x, v.y }),
            .rect => |r| try writer.print("{d},{d} {d}x{d}", .{ r.x, r.y, r.width, r.height }),
        }
    }
};
