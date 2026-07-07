const std = @import("std");
const Allocator = std.mem.Allocator;
const core = @import("core.zig");
const math = @import("math.zig");
const util = @import("util.zig");
const debug = core.debug;
const logError = core.logError;
const Vector2 = math.Vector2;

pub const default_level_size_in_tiles = struct {
    pub const x: i16 = @intFromFloat(@ceil(core.game_size_in_tiles.x));
    pub const y: i16 = @intFromFloat(@ceil(core.game_size_in_tiles.y));
};

pub const Tile = packed struct {
    idx: u6,
    row: u1 = 0,
    flip_x: bool,

    pub const empty = Tile{ .idx = 0, .flip_x = false };
    pub const solid = Tile{ .idx = 1, .flip_x = false };

    pub fn row1(idx: u6) Tile {
        return .{ .idx = idx, .row = 1, .flip_x = false };
    }

    pub fn fromU8(n: u8) Tile {
        return @bitCast(n);
    }

    pub fn toU8(tile: Tile) u8 {
        return @bitCast(tile);
    }

    pub fn isZero(tile: Tile) bool {
        return tile.toU8() == Tile.empty.toU8();
    }
};

pub const TilePosition = packed struct {
    x: i16,
    y: i16,

    pub const zero = TilePosition{ .x = 0, .y = 0 };
    pub const min = TilePosition{ .x = std.math.minInt(i16), .y = std.math.minInt(i16) };
    pub const max = TilePosition{ .x = std.math.maxInt(i16), .y = std.math.maxInt(i16) };

    pub fn init(x: i16, y: i16) TilePosition {
        return TilePosition{ .x = x, .y = y };
    }
    pub fn initRowCol(row_: i16, col_: i16) TilePosition {
        return TilePosition{ .x = col_, .y = row_ };
    }
    pub fn fromPixels(v: Vector2) TilePosition {
        return TilePosition{
            .x = @intFromFloat(@divFloor(v.x, 8)),
            .y = @intFromFloat(@divFloor(v.y, 8)),
        };
    }
    pub fn toPixelsTopLeft(pos: TilePosition) Vector2 {
        return Vector2{
            .x = util.toF32(pos.x) * 8,
            .y = util.toF32(pos.y) * 8,
        };
    }
    pub fn toPixelsBottomRight(pos: TilePosition) Vector2 {
        return pos.toPixelsTopLeft().addValue(7);
    }

    pub fn row(pos: TilePosition) i16 {
        return pos.y;
    }
    pub fn col(pos: TilePosition) i16 {
        return pos.x;
    }
    pub fn xy(pos: TilePosition) struct { i16, i16 } {
        return .{ pos.x, pos.y };
    }
    pub fn major(pos: TilePosition, orientation: LevelOrientation) i16 {
        return switch (orientation) {
            .horizontal => pos.x,
            .vertical => pos.y,
        };
    }
    pub fn minor(pos: TilePosition, orientation: LevelOrientation) i16 {
        return switch (orientation) {
            .horizontal => pos.y,
            .vertical => pos.x,
        };
    }
    pub fn majorMinorPtr(pos: *TilePosition, orientation: LevelOrientation) struct { *i16, *i16 } {
        return switch (orientation) {
            .horizontal => .{ pos.x, pos.y },
            .vertical => .{ pos.y, pos.x },
        };
    }

    pub fn add(a: TilePosition, b: TilePosition) TilePosition {
        return .{
            .x = a.x + b.x,
            .y = a.y + b.y,
        };
    }

    pub fn eql(a: TilePosition, b: TilePosition) bool {
        return a.x == b.x and a.y == b.y;
    }
    pub fn order(a: TilePosition, b: TilePosition, ori: LevelOrientation) std.math.Order {
        return switch (std.math.order(a.major(ori), b.major(ori))) {
            .lt, .gt => |ord| ord,
            .eq => std.math.order(a.minor(ori), b.minor(ori)),
        };
    }

    pub fn format(pos: TilePosition, writer: anytype) !void {
        try writer.print("{d},{d}", .{ pos.x, pos.y });
    }
};

pub fn getLevelWidth(level_min: TilePosition, level_max: TilePosition) i16 {
    return level_max.x - level_min.x + 1;
}
pub fn getLevelHeight(level_min: TilePosition, level_max: TilePosition) i16 {
    return level_max.y - level_min.y + 1;
}
pub fn getLevelSize(level_min: TilePosition, level_max: TilePosition) usize {
    return @as(usize, @intCast(
        getLevelWidth(level_min, level_max),
    )) * @as(usize, @intCast(
        getLevelHeight(level_min, level_max),
    ));
}

pub const TileMap = struct {
    /// Intended to be accessed directly.
    inner: Inner,

    pub const empty = TileMap{ .inner = .empty };
    pub const Inner = std.AutoArrayHashMapUnmanaged(TilePosition, Tile);

    pub fn deinit(self: *TileMap, allocator: Allocator) void {
        self.inner.deinit(allocator);
    }

    pub inline fn size(self: TileMap) usize {
        return self.inner.entries.len;
    }

    pub fn get(self: TileMap, key: TilePosition) ?Tile {
        return self.inner.get(key);
    }
    pub fn getPtr(self: TileMap, key: TilePosition) ?*Tile {
        return self.inner.getPtr(key);
    }
    pub fn put(self: *TileMap, allocator: Allocator, key: TilePosition, value: Tile) !void {
        try self.inner.put(allocator, key, value);
    }
    pub fn remove(self: *TileMap, key: TilePosition) bool {
        return self.inner.swapRemove(key);
    }

    pub fn sort(self: *TileMap, ori: LevelOrientation) void {
        self.inner.sortUnstable(SortCtx{ .keys = self.inner.keys(), .ori = ori });
    }
    const SortCtx = struct {
        keys: []const TilePosition,
        ori: LevelOrientation,
        pub fn lessThan(self: SortCtx, a_index: usize, b_index: usize) bool {
            return TilePosition.order(self.keys[a_index], self.keys[b_index], self.ori) == .lt;
        }
    };

    /// Preallocate `tile_data` based on the level size.
    pub fn getTileData(tile_map: TileMap, tile_data: []u8, level_min: TilePosition, level_max: TilePosition) void {
        if (tile_data.len != getLevelSize(level_min, level_max)) {
            std.debug.panic(
                "tile_data wrong size ({d}) for level ({d})",
                .{ tile_data.len, getLevelSize(level_min, level_max) },
            );
        }
        const level_width = getLevelWidth(level_min, level_max);
        @memset(tile_data, 0);
        var iter = tile_map.inner.iterator();
        while (iter.next()) |entry| {
            const pos = entry.key_ptr.*;
            const tile = entry.value_ptr.*;
            const x = pos.x - level_min.x;
            const y = pos.y - level_min.y;
            tile_data[@intCast(y * level_width + x)] = tile.toU8();
        }
    }

    pub fn getTileDataAllocating(tile_map: TileMap, allocator: Allocator, level_min: TilePosition, level_max: TilePosition) Allocator.Error![]u8 {
        const tile_data = try allocator.alloc(u8, getLevelSize(level_min, level_max));
        tile_map.getTileData(tile_data, level_min, level_max);
        return tile_data;
    }

    /// Returns number of bytes written. Sorts the tile map if `encoding == .delta_map`.
    pub fn serialize(
        tile_map: *TileMap,
        allocator: Allocator,
        buf: *std.ArrayList(u8),
        comptime encoding: TileMapEncoding,
        level_min: TilePosition,
        level_max: TilePosition,
    ) Allocator.Error!usize {
        switch (encoding) {
            .array, .rle => {
                const tile_data = tile_map.getTileDataAllocating(allocator, level_min, level_max);
                defer allocator.free(tile_data);
                return serializeTileData(allocator, buf, encoding, tile_data);
            },

            .delta_map => {
                const orientation = LevelOrientation.inferFromLevelSize(level_min, level_max);
                tile_map.sort(orientation);

                const old_len = buf.items.len;
                try buf.ensureUnusedCapacity(allocator, tile_map.size() * hex_digits_in_u8 * 3); // doesn't include dummy entities
                var prev_major: i16 = 0;
                var dummies_needed: usize = 0;
                var iter = tile_map.inner.iterator();
                while (iter.next()) |entry| {
                    const major_i16, const minor_i16 = switch (orientation) {
                        .horizontal => .{ entry.key_ptr.x, entry.key_ptr.y },
                        .vertical => .{ entry.key_ptr.y, entry.key_ptr.x },
                    };
                    const major_delta: i8 = while (true) {
                        if (std.math.cast(i8, major_i16 - prev_major)) |major_delta| {
                            break major_delta;
                        } else {
                            const major_delta: i8 = 127;
                            prev_major += major_delta;
                            try buf.print(allocator, "{x:0>2}{x:0>2}{x:0>2}", .{ @as(u8, @bitCast(major_delta)), 0, 0 });
                            dummies_needed += 1;
                        }
                    };
                    const minor = std.math.cast(i8, minor_i16) orelse {
                        std.debug.panic("an entity was placed offscreen (minor={d})", .{minor_i16});
                    };
                    // Print as u8 to avoid needing a negative sign.
                    try buf.print(allocator, "{x:0>2}{x:0>2}{x:0>2}", .{ @as(u8, @bitCast(major_delta)), @as(u8, @bitCast(minor)), entry.value_ptr.toU8() });
                    prev_major = major_i16;
                }
                if (dummies_needed > 0) {
                    logError("serializing tile map", "needed {d} dummy objects", .{dummies_needed});
                }
                const expected_length = (tile_map.size() + dummies_needed) * hex_digits_in_u8 * 3;
                util.expectLen(u8, old_len + expected_length, "{c}", buf.items, .panic);
                return expected_length;
            },
        }
    }

    pub fn deserializeFromStream(
        tile_map: *TileMap,
        allocator: Allocator,
        reader: *std.io.Reader,
        comptime encoding: TileMapEncoding,
        level_min: TilePosition,
        level_max: TilePosition,
    ) (Allocator.Error || std.io.Reader.Error || error{InvalidTile})!void {
        const PREFIX = "deserializing tile map";
        var y = level_min.y;
        const max_y = level_max.y;
        var x = level_min.x;
        const max_x = level_max.x;
        // Doing it manually because reader.takeDelimiterExclusive(',') advances past the comma.
        const tile_data_end = std.mem.indexOfScalarPos(u8, reader.buffer, reader.seek, ',') orelse reader.buffer.len;
        switch (encoding) {
            .array => {
                const level_size = getLevelSize(level_min, level_max);
                util.expectEq(usize, tile_data_end - reader.seek, level_size * hex_digits_in_u8, .panic);
                for (0..level_size) |_| {
                    const hex_u8 = try reader.takeArray(hex_digits_in_u8);
                    const tile = Tile.fromU8(std.fmt.parseInt(u8, hex_u8, 16) catch return error.InvalidTile);
                    if (tile.idx != Tile.empty.idx) {
                        try tile_map.inner.putNoClobber(allocator, .init(x, y), tile);
                    }
                    x += 1;
                    if (x > max_x) {
                        y += 1;
                        x = level_min.x;
                    }
                }
            },
            .rle => {
                const tile_data = reader.buffer[reader.seek..tile_data_end];
                reader.toss(tile_data.len);
                var run_iter = rle.decode(tile_data);
                while (run_iter.next() catch return error.InvalidTile) |run| {
                    const tile = Tile.fromU8(run.char);
                    if (tile.idx != Tile.empty.idx) {
                        try tile_map.inner.ensureUnusedCapacity(allocator, run.len);
                    }
                    for (0..run.len) |_| {
                        if (tile.idx != Tile.empty.idx) {
                            tile_map.inner.putAssumeCapacityNoClobber(.init(x, y), tile);
                        }
                        x += 1;
                        if (x > max_x) {
                            y += 1;
                            x = level_min.x;
                        }
                    }
                }
            },
            .delta_map => {
                const orientation = LevelOrientation.inferFromLevelSize(level_min, level_max);
                const tile_data_size = tile_data_end - reader.seek;
                var prev_major: i16 = 0;
                const tile_count: usize = std.math.divExact(usize, tile_data_size, hex_digits_in_u8 * 3) catch |e| switch (e) {
                    error.DivisionByZero => unreachable,
                    error.UnexpectedRemainder => {
                        logError(PREFIX, "bad tile length: {d}", .{tile_data_size});
                        return error.InvalidTile;
                    },
                };
                try tile_map.inner.ensureTotalCapacity(allocator, @intCast(tile_count));
                for (0..tile_count) |_| {
                    (parse_hex: {
                        const major_delta: i8 = @bitCast(util.readerTakeHex(u8, reader, hex_digits_in_u8) catch |e| break :parse_hex e);
                        const minor: i8 = @bitCast(util.readerTakeHex(u8, reader, hex_digits_in_u8) catch |e| break :parse_hex e);
                        const major: i16 = prev_major + major_delta;
                        const tile_entry = tile_map.inner.getOrPutAssumeCapacity(switch (orientation) {
                            .horizontal => .{ .x = major, .y = minor },
                            .vertical => .{ .y = major, .x = minor },
                        });
                        tile_entry.value_ptr.* = .fromU8(util.readerTakeHex(u8, reader, hex_digits_in_u8) catch |e| break :parse_hex e);
                        if (tile_entry.found_existing) {
                            logError(PREFIX, "clobbered at {f}", .{tile_entry.key_ptr});
                        }
                        prev_major = major;
                    } catch |e| switch (e) {
                        error.ReadFailed, error.EndOfStream => |r_e| {
                            logError(PREFIX, "{t}", .{r_e});
                            return r_e;
                        },
                        error.Overflow, error.InvalidCharacter => {
                            logError(PREFIX, "failed to parse hex digit: {t}", .{e});
                            return error.InvalidTile;
                        },
                    });
                }
                return; // avoid those asserts at the bottom
            },
        }
        std.debug.assert(y > max_y);
        std.debug.assert(x == level_min.x);
    }

    pub fn pruneDummies(tile_map: *TileMap) void {
        var iter = tile_map.inner.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.isZero()) {
                const existed = tile_map.remove(entry.key_ptr.*);
                std.debug.assert(existed);
                iter.index -= 1;
            }
        }
    }
};

// General note about serialization:
// - Functions that deserialize should handle errors gracefully, since that's
//   the end-end-user, and it's not their fault if they receive a bad code.
// - Functions that serialize, however, are currently only used by the level
//   editor, which is currently developer-only, or at least not a main feature
//   of the game. If it ever gets promoted to a main feature, I should make
//   these functions more robust.
// Also see RLE below.

pub const TileMapEncoding = enum {
    /// Every tile listed in order from top-left to bottom-right, including
    /// empty ones.
    array,
    /// Every tile listed in order (like `.array`), but run-length encoded.
    /// Intended for tiles, which tend to be dense.
    rle,
    /// Only non-empty tiles and their positions listed, where the major
    /// coordinate is relative to the previous tile. Intended for entities,
    /// which tend to be sparse.
    delta_map,
};

/// Returns number of bytes written.
pub fn serializeTileData(
    allocator: Allocator,
    buf: *std.ArrayList(u8),
    comptime encoding: TileMapEncoding,
    tile_data: []const u8,
) Allocator.Error!usize {
    var encoded_length: usize = 0;

    switch (encoding) {
        .array => {
            const expected_length = hex_digits_in_u8 * tile_data.len;
            try buf.ensureUnusedCapacity(allocator, expected_length);
            for (tile_data) |n| {
                buf.printBounded("{x:0>2}", .{n}) catch unreachable; // We ensured it has capacity.
                encoded_length += 2;
            }
            std.debug.assert(encoded_length == expected_length);
        },

        .rle => {
            var run_iter = rle.encode(tile_data);
            while (run_iter.next()) |run| {
                switch (run.len) {
                    0x0 => unreachable,
                    // For small amounts: preceded by a single hex digit, 1 to F.
                    0x1...0xf => {
                        try buf.print(allocator, "{x}", .{run.len});
                        encoded_length += 1;
                    },
                    // For large amounts: a 0 followed by a (single-digit) count of the number of digits to follow.
                    0x10...std.math.maxInt(u32) => {
                        try buf.print(allocator, "0", .{});
                        var n: u32 = run.len;
                        var digit_count: u8 = 1;
                        inline for ([_]u8{ 4, 2, 1 }) |zero_count| {
                            const power = comptime std.math.powi(u32, 0x10, zero_count) catch unreachable;
                            if (n >= power) {
                                digit_count += zero_count;
                                n /= power;
                            }
                        }
                        if (digit_count >= 0x10) @panic("too many digits");
                        try buf.print(allocator, "{x}", .{digit_count});
                        try buf.print(allocator, "{[len]x:0>[width]}", .{ .len = run.len, .width = digit_count });
                        encoded_length += 1 + 1 + digit_count;
                    },
                }
                try buf.print(allocator, "{x:0>2}", .{run.char});
                encoded_length += hex_digits_in_u8;
            }
        },

        .delta_map => @compileError("arrays of tile data don't support this method of encoding; serialize the whole tile map it came from instead"),
    }

    return encoded_length;
}

pub const TileArray = struct {
    items: []Tile,
    width: u15,
    height: u15,

    pub fn deinit(self: TileArray, allocator: Allocator) void {
        allocator.free(self.items);
    }

    pub fn dupe(self: TileArray, allocator: Allocator) Allocator.Error!TileArray {
        return TileArray{
            .items = try allocator.dupe(Tile, self.items),
            .width = self.width,
            .height = self.height,
        };
    }

    pub fn get(self: TileArray, pos: TilePosition) ?Tile {
        const x, const y = pos.xy();
        if (!self.xInBounds(x)) return null;
        if (!self.yInBounds(y)) return null;
        return self.items[@intCast(y * self.width + x)];
    }
    pub fn getPtr(self: *TileArray, pos: TilePosition) ?*Tile {
        const x, const y = pos.xy();
        if (!self.xInBounds(x)) return null;
        if (!self.yInBounds(y)) return null;
        return &self.items[@intCast(y * self.width + x)];
    }

    pub fn xInBounds(self: TileArray, x: i16) bool {
        return 0 <= x and x < self.width;
    }
    pub fn yInBounds(self: TileArray, y: i16) bool {
        return 0 <= y and y < self.height;
    }

    pub const DeserializationError = Allocator.Error || error{
        NegativeDimension,
        LengthMismatch,
        InvalidNumber,
    };
    pub fn deserialize(allocator: Allocator, slice: []const u8, comptime encoding: TileMapEncoding, min: TilePosition, max: TilePosition) DeserializationError!TileArray {
        const width = std.math.cast(u15, getLevelWidth(min, max)) orelse return error.NegativeDimension;
        const height = std.math.cast(u15, getLevelHeight(min, max)) orelse return error.NegativeDimension;

        var array: std.ArrayList(Tile) = .empty;
        var i: usize = 0;
        switch (encoding) {
            .array => {
                const expected_len = width * height * hex_digits_in_u8;
                if (slice.len != expected_len) {
                    logError("deserializing tile array", "expected length {d} but was {d}", .{ expected_len, slice.len });
                    return error.LengthMismatch;
                }
                array = try .initCapacity(allocator, width * height);
                while (i < slice.len) : (i += hex_digits_in_u8) {
                    const n = std.fmt.parseInt(u8, slice[i .. i + 2], 16) catch return error.InvalidNumber;
                    array.appendAssumeCapacity(Tile.fromU8(n)); // We preallocated the exact amount needed.
                }
                std.debug.assert(array.items.len == array.capacity);
            },
            .rle => {
                var run_iter = rle.decode(slice);
                while (run_iter.next() catch return error.InvalidNumber) |run| {
                    try array.appendNTimes(allocator, Tile.fromU8(run.char), run.len);
                }
            },
            .delta_map => @compileError("not implemented for this type"),
        }

        return TileArray{
            .items = try array.toOwnedSlice(allocator),
            .width = width,
            .height = height,
        };
    }
};

/// 00 to FF.
pub const hex_digits_in_u8 = 2;
/// 0000 to FFFF.
pub const hex_digits_in_u16 = 4;

pub const LevelOrientation = enum {
    horizontal,
    vertical,

    pub fn inferFromLevelSize(level_min: TilePosition, level_max: TilePosition) LevelOrientation {
        return if (getLevelHeight(level_min, level_max) > default_level_size_in_tiles.y) .vertical else .horizontal;
    }
};

// My reasoning behind the RLE compression for level data:
// - Only operate on tile data because it's going to have the most runs.
// - Use the whole number for a run, i.e., two ASCII chars. Otherwise there aren't gonna be any runs.
// - Ideally, we'd optimize for runs of one, a small amount, and a large amount of length.
// - I can't really think of a way to optimize for length one specifically, but it can be lumped in
//   with small amounts without too much loss, especially since each "char" is two bytes.
// - For small amounts: preceded by a single hex digit, 1 to F, for lengths from 1 to 15.
// - For large amounts: a 0 followed by a (single-digit) count of the number of digits to follow.
//   I don't think more than 15 digits (lengths > 16^15) will be needed!
const rle = struct {
    pub fn encode(buf: []const u8) EncodingIterator {
        return EncodingIterator{ .buf = buf };
    }

    pub fn decode(buf: []const u8) DecodingIterator {
        if (debug.misc) {
            for (buf) |c| {
                if (!std.ascii.isHex(c)) {
                    std.debug.panic("You passed too much. Only pass the tile data. (Found a '{c}'.)", .{c});
                }
            }
        }
        return DecodingIterator{ .reader = std.io.Reader.fixed(buf) };
    }

    pub const EncodingIterator = struct {
        buf: []const u8,
        idx: usize = 0,

        pub fn next(self: *EncodingIterator) ?Run {
            if (self.idx >= self.buf.len) return null;
            const char: u8 = self.buf[self.idx];
            const start_idx = self.idx;
            while (self.idx < self.buf.len and self.buf[self.idx] == char) : (self.idx += 1) {}
            return .{ .len = @intCast(self.idx - start_idx), .char = char };
        }
    };

    pub const DecodingIterator = struct {
        reader: std.io.Reader,
        idx: usize = 0,
        is_done: bool = false,

        pub const Error = error{Invalid};

        pub fn next(self: *DecodingIterator) Error!?Run {
            const PREFIX = "decoding RLE data";
            if (self.reader.seek == self.reader.end) self.is_done = true;
            if (self.is_done) return null;

            const len_or_0 = util.readerTakeHex(u8, &self.reader, 1) catch |e| {
                logError(PREFIX, "{t}: expected len or 0, found '{any}'", .{ e, self.reader.peekByte() });
                self.is_done = true;
                return error.Invalid;
            };
            // For small amounts: preceded by a single hex digit, 1 to F.
            const len: u32 = if (len_or_0 > 0) len_or_0 else blk: {
                // For large amounts: a 0 followed by a (single-digit) count of the number of digits to follow.
                const digit_count = util.readerTakeHex(u8, &self.reader, 1) catch |e| {
                    logError(PREFIX, "expected digit count of len: {t}", .{e});
                    self.is_done = true;
                    return error.Invalid;
                };
                if (digit_count == 0) {
                    logError(PREFIX, "digit_count is 0", .{});
                }
                if (self.reader.peekByte() catch '9' == '0') {
                    logError(PREFIX, "len starts with a 0, so digit_count ({d}) should be smaller", .{digit_count});
                }
                break :blk util.readerTakeHex(u32, &self.reader, digit_count) catch |e| {
                    const reset_color = "\x1b[0m";
                    logError(
                        PREFIX,
                        "{t}: expected len (with {d} digits) at {d}, found '{any}'" ++ reset_color,
                        .{ e, digit_count, self.reader.seek, self.reader.peek(digit_count) },
                    );
                    self.is_done = true;
                    return error.Invalid;
                };
            };
            const char = util.readerTakeHex(u8, &self.reader, 2) catch |e| {
                logError(PREFIX, "expected hexadecimal number: {t}", .{e});
                self.is_done = true;
                return error.Invalid;
            };

            return Run{ .len = len, .char = char };
        }
    };

    pub const Run = struct { len: u32, char: u8 };
};
