const std = @import("std");
const core = @import("core.zig");
const math = core.math;
const util = core.util;
const Vector2 = math.Vector2;
const Rectangle = math.Rectangle;

const Entity = @This();

// Collisions between entities are recorded in the entity whose kind is lower on
// this list (higher in value).
pub const FoeKind = enum(u8) {
    not_a_foe,

    pub fn format(kind: FoeKind, writer: anytype) !void {
        const count = std.enums.values(FoeKind).len;
        if (@intFromEnum(kind) >= count) {
            try writer.print("invalid{d}", .{@intFromEnum(kind)});
            return;
        }
        switch (kind) {
            .not_a_foe => try writer.print("entity", .{}),
            else => try writer.print("{t}", .{kind}),
        }
    }
};
pub const FoeData = union(FoeKind) {
    not_a_foe,

    pub fn format(kind: FoeData, writer: anytype) !void {
        try FoeKind.format(kind, writer);
    }
};

id: core.EntityId,
foe_kind: FoeData,
x: f32 = 0,
y: f32 = 0,
sx: f32 = 0,
sy: f32 = 0,
collision_size: Vector2,

sprite_sheet: core.draw.SpriteSheet,
/// Use for squash and stretch.
scale: Vector2 = .{ .x = 1, .y = 1 },

/// Defaults to just the first frame.
animation: Anim = .{ .frames = &.{.{}} },
/// In seconds.
anim_position: f32 = 0,
/// No worries, it knows when it's invalidated.
_anim_cache: ?Anim.Cache = null,

/// Entity flags.
is: packed struct {
    // todo: may not need dead or done
    /// Shouldn't respond to anything, but may still be playing an animation.
    dead: bool = false,
    /// Ready to be deleted (i.e., any death animation has finished).
    done: bool = false,
    /// All entities face right by default. If true, it's drawn flipped.
    facing_left: bool = false,
    upside_down: bool = false,
    /// The bottom of the entity is touching something solid.
    on_floor: bool = false,
    /// The top of the entity is touching something solid.
    on_ceiling: bool = false,
    left_on_wall: bool = false,
    right_on_wall: bool = false,
    /// Solid entities aren't allowed to overlap and count as wall/floor/ceiling for each other.
    solid: bool = false,
    held: bool = false,
    /// Either side of the entity is touching something solid.
    pub fn onWall(flags: @This()) bool {
        return flags.left_on_wall or flags.right_on_wall;
    }
    /// The front side of the entity is touching something solid.
    pub fn frontOnWall(flags: @This()) bool {
        return if (flags.facing_left) flags.left_on_wall else flags.right_on_wall;
    }
} = .{},

//
// Methods
//

pub fn position(ent: Entity) Vector2 {
    return .{ .x = ent.x, .y = ent.y };
}
pub fn setPosition(ent: *Entity, pos: Vector2) void {
    ent.x = pos.x;
    ent.y = pos.y;
}

pub fn velocity(ent: Entity) Vector2 {
    return .{ .x = ent.sx, .y = ent.sy };
}
pub fn setVelocity(ent: *Entity, vel: Vector2) void {
    ent.sx = vel.x;
    ent.sy = vel.y;
}

/// The visual center of the entity (using floored position), based on the size
/// defined in its sprite sheet. If its sprites don't normally take up a whole
/// one of those tiles, or take up multiple, it may look wrong.
pub fn centerPosition(ent: Entity) Vector2 {
    return .{
        .x = @floor(ent.x),
        .y = @floor(ent.y) - ent.sprite_sheet.tile_size.y / 2,
    };
}

pub fn applyGravity(ent: *Entity) void {
    ent.applyGravityWithScale(1.0);
}

pub fn applyGravityWithScale(ent: *Entity, scale: f32) void {
    // This number originally comes from Godot. I'm unaware of any significance, but I'm used to it.
    const gravity = 980 * core.FRAME_DELTA;
    const max_fall_speed = 300;
    ent.sy =
        if (ent.is.on_floor)
            @min(ent.sy, 0)
        else
            @min(ent.sy + gravity * scale, max_fall_speed);
}

pub fn applyFriction(ent: *Entity) void {
    const friction = 300 * core.FRAME_DELTA;
    ent.sx = util.moveTowardsF(ent.sx, 0, friction);
}

/// Collision boxes are floored, so this is only accurate within 1px.
pub fn isOverlapping(a: Entity, b: Entity) bool {
    for (core.getRectScreenWrapped(a.collisionRect())) |a_rec| {
        // We only need to wrap one of the entities.
        if (math.checkCollisionRecs(a_rec, b.collisionRect())) return true;
    }
    return false;
}

/// Returns the entity's collision box, floored.
pub fn collisionRect(ent: Entity) Rectangle {
    return ent.collisionRectForSize(ent.collision_size);
}
pub fn collisionRectForSize(ent: Entity, size: Vector2) Rectangle {
    return .{
        .x = @floor(ent.x) - size.x / 2,
        .y = @floor(ent.y) - size.y + 1,
        .width = size.x,
        .height = size.y,
    };
}

/// The section of the screen in which to draw.
pub fn drawingRect(ent: *Entity) Rectangle {
    const sheet_rect = ent._sheetRectForFrame(ent.animCurrentFrame());
    const unscaled = Rectangle{
        .x = @floor(ent.x - sheet_rect.width / 2),
        .y = @floor(ent.y - sheet_rect.height + 1),
        .width = sheet_rect.width,
        .height = sheet_rect.height,
    };
    var scaled = unscaled;
    scaled.width *= ent.scale.x;
    scaled.height *= ent.scale.y;
    scaled.x += (unscaled.width - scaled.width) / 2;
    scaled.y += unscaled.height - scaled.height;
    return scaled;
}

/// The section of the sprite sheet to draw for this frame, flipped as necessary.
pub fn sheetRect(ent: *Entity) Rectangle {
    return ent.sheetRectForFrame(ent.animCurrentFrame());
}
/// The section of the sprite sheet to draw for `frame`, flipped as necessary.
///
/// Assumes that the frame is in the entity's sprite sheet. If not, you may not
/// get any error or warning until its out of bounds and you try to draw.
pub fn sheetRectForFrame(ent: Entity, frame: Frame) Rectangle {
    var rect = ent._sheetRectForFrame(frame);
    if (ent.is.facing_left != frame.flip_x) rect.width *= -1;
    if (frame.flip_y) rect.height *= -1;
    return rect;
}
fn _sheetRectForFrame(ent: Entity, frame: Frame) Rectangle {
    const tile_size = ent.sprite_sheet.tile_size;
    const rect = Rectangle{
        .x = @floor(tile_size.x) * util.toF32(frame.col),
        .y = @floor(tile_size.y) * util.toF32(frame.row),
        .width = @floor(tile_size.x * frame.tiles_wide),
        .height = @floor(tile_size.y * frame.tiles_high),
    };
    return rect;
}

pub fn animLen(ent: *Entity) f32 {
    return ent.animation.getLength(&ent._anim_cache);
}

pub fn animCurrentFrame(ent: *Entity) Frame {
    return ent.animation.getFrame(ent.anim_position, &ent._anim_cache);
}

/// Returns true if the animation reached the given seconds within the previous
/// game frame.
pub fn isAnimAt(ent: *Entity, secs: f32) bool {
    return ent.anim_position >= secs and
        ent.anim_position < secs + core.FRAME_DELTA;
}
/// Returns true if the animation reached the frame at index `frame_idx` within
/// the previous game frame.
pub fn isAnimAtIndex(ent: *Entity, comptime frame_idx: usize) bool {
    _ = ent.animCurrentFrame(); // update cache
    if (ent._anim_cache.?.frame_idx != frame_idx) return false;
    return ent.isAnimAt(ent._anim_cache.?.duration_up_to_frame);
}

pub fn isAnimDone(ent: *Entity) bool {
    return !ent.animation.loop and ent.anim_position >= ent.animLen();
}

pub const PlayAnimationOptions = struct {
    /// Only replace animations up to this priority level. If not given, the animation's priority is used.
    replace_up_to: ?Anim.Priority = null,
    /// Safety check to prevent infinite loops.
    will_be_manually_ended: bool = false,
};
/// Sets the animation to `anim`, unless it's already playing (and not done) or
/// the current animation has a higher priority.
pub fn playAnimation(ent: *Entity, anim: Anim, options: PlayAnimationOptions) void {
    const priority: Anim.Priority = options.replace_up_to orelse anim.priority;

    if (!options.will_be_manually_ended) {
        // You probably don't want to wait for an animation to finish that loops endlessly.
        std.debug.assert(!(anim.priority.int() >= Anim.Priority.important.int() and anim.loop));
    }

    if (!ent.isAnimDone()) {
        if (ent.animation.equals(anim)) return;
        if (ent.animation.priority.int() > priority.int()) return;
    }

    ent.animation = anim;
    ent.anim_position = 0;
    // Anything cached gets updated lazily.
}

pub fn advanceAnimation(ent: *Entity, amount: f32) void {
    var new_pos = ent.anim_position + amount;
    if (new_pos >= ent.animLen() and ent.animation.loop) {
        new_pos = @mod(new_pos, ent.animLen());
    }
    ent.anim_position = new_pos;
}

pub fn format(ent: Entity, writer: anytype) !void {
    try writer.print(
        "{f}#{f}({d:.1},{d:.1})",
        .{ ent.foe_kind, ent.id, ent.x, ent.y },
    );
}

//
// Animation
//

/// Defines a series of frames over time. No two animations should share `frames`.
pub const Anim = struct {
    frames: []const Frame,
    priority: Priority = .freely_interrupt,
    loop: bool = true,

    pub const Priority = enum(u8) {
        /// Able to be replaced by any new animation.
        freely_interrupt,
        /// Better than other animations in this context.
        preferred,
        /// It's important to gameplay that this animation is allowed to finish.
        important,
        /// A death animation.
        uninterruptable,

        fn int(self: Priority) u8 {
            return @intFromEnum(self);
        }
    };

    pub inline fn fromRow(comptime row: u8, comptime columns: anytype) Anim {
        return .{ .frames = &Frame.fromRow(row, columns) };
    }
    pub inline fn fromRowWithDuration(comptime duration: f32, comptime row: u8, comptime columns: anytype) Anim {
        return .{ .frames = &Frame.fromRowWithDuration(duration, row, columns) };
    }

    /// Two animations are considered equal if they point to the same frame data.
    pub fn equals(a: Anim, b: Anim) bool {
        return a.frames.ptr == b.frames.ptr;
    }

    const Cache = struct {
        anim: Anim,
        len: f32,
        frame_idx: usize = 0,
        duration_up_to_frame: f32 = 0,
    };

    fn cacheEnsureInit(self: Anim, maybe_cache: *?Cache) *Cache {
        if (maybe_cache.*) |*cache| if (self.equals(cache.anim))
            return cache;
        maybe_cache.* = Cache{
            .anim = self,
            .len = self.calculateLength(),
        };
        return &maybe_cache.*.?;
    }

    fn getLength(self: Anim, maybe_cache: *?Cache) f32 {
        return self.cacheEnsureInit(maybe_cache).len;
    }
    pub fn calculateLength(self: Anim) f32 {
        var len: f32 = 0;
        for (self.frames) |frame| len += frame.duration;
        return len;
    }

    fn getFrame(self: Anim, pos: f32, maybe_cache: *?Cache) Frame {
        var cache = self.cacheEnsureInit(maybe_cache);
        var i: usize = 0;
        var duration: f32 = 0;
        // The cache only supports going forward.
        if (pos >= cache.duration_up_to_frame) {
            i = cache.frame_idx;
            duration = cache.duration_up_to_frame;
        }
        while (i < self.frames.len) {
            const frame = self.frames[i];
            if (duration + frame.duration > pos) break;
            if (i + 1 >= self.frames.len) break;
            duration += frame.duration;
            i += 1;
        }
        cache.frame_idx = i;
        cache.duration_up_to_frame = duration;
        return self.frames[i];
    }
};

/// Defines a section of a sprite sheet to draw. Defaults to the first 1x1 tile
/// in the sheet, drawn over 160ms.
pub const Frame = packed struct {
    row: u8 = 0,
    col: u8 = 0,
    tiles_wide: f32 = 1,
    tiles_high: f32 = 1,
    flip_x: bool = false,
    flip_y: bool = false,
    duration: f32 = 0.16,

    const row0_frames = blk: {
        var array: [10]Frame = undefined;
        for (0..array.len) |i| array[i] = Frame{ .col = i };
        break :blk array;
    };
    /// Returns a slice containing a single frame on row 0.
    pub fn singleFrame(col: u8) []const Frame {
        return row0_frames[col .. col + 1];
    }

    pub inline fn fromRow(comptime row: u8, comptime columns: anytype) [arrayLen(columns)]Frame {
        var array: [arrayLen(columns)]Frame = undefined;
        inline for (columns, 0..) |col, i| {
            array[i] = Frame{ .row = row, .col = col };
        }
        return array;
    }
    pub inline fn fromRowWithDuration(comptime duration: f32, comptime row: u8, comptime columns: anytype) [arrayLen(columns)]Frame {
        var array: [arrayLen(columns)]Frame = undefined;
        inline for (columns, 0..) |col, i| {
            array[i] = Frame{
                .row = row,
                .col = col,
                .duration = duration,
            };
        }
        return array;
    }

    /// Flips horizontally.
    pub fn flipH(frame: Frame) Frame {
        var new_frame = frame;
        new_frame.flip_x = !new_frame.flip_x;
        return new_frame;
    }
    /// Flips vertically.
    pub fn flipV(frame: Frame) Frame {
        var new_frame = frame;
        new_frame.flip_y = !new_frame.flip_y;
        return new_frame;
    }

    /// Repeats `n` times.
    pub fn times(frame: Frame, n: f32) Frame {
        var new_frame = frame;
        new_frame.duration *= n;
        return new_frame;
    }
};
const arrayLen = util.comptimeArrayLen;
