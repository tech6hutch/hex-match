const std = @import("std");
const core = @import("engine/core.zig");
const draw = core.draw;
const level_format = core.level_format;
const util = core.util;
const Entity = core.Entity;
const Color = draw.Color;
const pico8_colors = draw.pico8_colors;
const game = @import("game.zig");

pub const count = file_names.len;

pub const file_names = [_][:0]const u8{
    "bg_tiles", "room",
};
pub const display_names = [count][:0]const u8{
    "Background (Unused)", "Mail Room",
};

pub var textures: [count]draw.Texture = undefined;
pub fn initTextureIndexArrays() void {
    inline for (0..count) |i| {
        textures[i] = core.assets.textures.get("tiles/" ++ file_names[i] ++ ".png");
    }
}

pub const bg_colors = [count]Color{
    .black, pico8_colors.darker_grey,
};

const tile_info = [_]TileInfo{
    .{ .collision = .pass_thru },
    .{ .collision = .solid },
    .{ .collision = .bumpable },
    .{ .collision = .bumpable },
    .{ .collision = .moving_bumpable },
};
pub fn getInfoForTiles(tile_set_idx: u8) []const TileInfo {
    return switch (tile_set_idx) {
        0 => @panic("tried to get collision info for the background"),
        else => &tile_info,
    };
}

const max_tile_count: usize = tile_info.len;

const tiles_as_entity_frames: [max_tile_count * 2]Entity.Frame = blk: {
    var array: [max_tile_count * 2]Entity.Frame = undefined;
    for (0..max_tile_count) |i| {
        array[i] = .{ .col = i };
        array[i + max_tile_count] = .{ .col = i, .row = 1 };
    }
    break :blk array;
};
const tiles_as_entity_frames_flip_x: [max_tile_count * 2]Entity.Frame = blk: {
    var array: [max_tile_count * 2]Entity.Frame = undefined;
    for (0..max_tile_count) |i| {
        array[i] = .{ .col = i, .flip_x = true };
        array[i + max_tile_count] = .{ .col = i, .row = 1, .flip_x = true };
    }
    break :blk array;
};
pub fn getTileAsEntityFrames(tile: level_format.Tile) []const Entity.Frame {
    std.debug.assert(tile.row < 2);
    return (&(if (tile.flip_x) tiles_as_entity_frames_flip_x else tiles_as_entity_frames)[tile.idx + tile.row * max_tile_count])[0..1];
}

pub const TileInfo = struct {
    collision: Collision,
    reactions: struct {
        overlap: ?struct {
            any: level_format.Tile,
            left: level_format.Tile = .empty,
            right: level_format.Tile = .empty,
            duration: f32 = 0.5,
        } = null,
    } = .{},
    breakable: bool = false,

    pub const Collision = enum(u8) { pass_thru, solid, bumpable, moving_bumpable, one_way, top_harmful };
};
