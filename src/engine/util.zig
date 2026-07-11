const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

//
// Strings
//

/// Wrap words, based on the given function to measure the text's width.
pub fn wordWrapZ(allocator: Allocator, textWidth: fn ([:0]const u8, f32) f32, text: [:0]const u8, font_size: f32, desired_width: f32) Allocator.Error![:0]u8 {
    var lines: ArrayList([:0]const u8) = .empty;
    defer lines.deinit(allocator);

    // First, handle manual newlines.
    var nl_iter = std.mem.splitScalar(u8, text, '\n');
    while (nl_iter.next()) |line| {
        try lines.append(allocator, try allocator.dupeZ(u8, line));
    }

    // Second, break up lines automatically (preferably at word boundaries).
    var lines_idx: usize = 0;
    lines_loop: while (lines_idx < lines.items.len) : (lines_idx += 1) {
        const line = lines.items[lines_idx];
        if (textWidth(line, font_size) <= desired_width) continue;

        var before: ArrayList(u8) = try .initCapacity(allocator, line.len + 1);
        var word_iter = std.mem.splitScalar(u8, line, ' ');
        while (word_iter.next()) |word| {
            if (before.items.len > 0) before.appendAssumeCapacity(' ');
            before.appendSliceAssumeCapacity(word);
            if (textWidth(asSliceZ(&before), font_size) > desired_width) {
                before.items.len -= word.len;
                if (before.items.len > 0) {
                    before.items.len -= 1; // space
                    lines.items[lines_idx] = try before.toOwnedSliceSentinel(allocator, 0);
                    const after_z = try std.mem.joinZ(allocator, " ", &.{ word, word_iter.rest() });
                    try lines.insert(allocator, lines_idx + 1, after_z);
                    continue :lines_loop;
                }
                // Else, the first word, on its own, was too long.
                break;
            }
        }

        std.debug.assert(before.items.len == 0);
        for (line, 0..) |c, i| {
            before.appendAssumeCapacity(c);
            if (textWidth(asSliceZ(&before), font_size) > desired_width) {
                before.items.len -= 1;
                lines.items[lines_idx] = try before.toOwnedSliceSentinel(allocator, 0);
                const after_z = try allocator.dupeZ(u8, line[i..]);
                try lines.insert(allocator, lines_idx + 1, after_z);
            }
        }
    }

    // Lastly, re-join all the lines.
    return try std.mem.joinZ(allocator, "\n", lines.items);
}

/// List must have room for the sentinel.
fn asSliceZ(list: *ArrayList(u8)) [:0]u8 {
    list.appendAssumeCapacity(0);
    // Safety dance! Not even in Rust this time!
    const slice_z = list.items[0 .. list.items.len - 1 :0];
    list.items.len -= 1;
    return slice_z;
}

test "that asSliceZ works" {
    const allocator = std.testing.allocator;
    var list: ArrayList(u8) = .empty;
    defer list.deinit(allocator);
    try list.appendSlice(allocator, "abc");
    try list.ensureTotalCapacity(allocator, list.items.len + 1);
    const list_z = asSliceZ(&list);
    try std.testing.expectEqual(3, list.items.len);
    try std.testing.expectEqual(3, list_z.len);
    try std.testing.expectEqualStrings("abc", list_z);
    try std.testing.expectEqual(0, list_z[list_z.len]);
}

/// Only advances the reader if parsing succeeded, so you can still take/peek the chars on failure.
pub fn readerTakeHex(comptime IntType: type, reader: *std.io.Reader, digits: u8) (std.io.Reader.Error || std.fmt.ParseIntError)!IntType {
    std.debug.assert(digits <= 9); // this is digits, not base
    const slice = try reader.peek(digits);
    const n = try std.fmt.parseInt(IntType, slice, 16);
    reader.toss(digits);
    return n;
}

/// Returns a slice of the next bytes of buffered data from the stream until
/// `delimiter` is found, advancing the seek position up to (but not past)
/// the delimiter.
///
/// Returned slice excludes the delimiter. End-of-stream is treated equivalent
/// to a delimiter, unless it would result in a length 0 return value, in which
/// case `error.EndOfStream` is returned instead.
pub fn readerTakeDelimiterExclusive(reader: *std.io.Reader, delimiter: u8) std.io.Reader.Error![]u8 {
    // Zig 0.15.2 has a bug with reader.takeDelimiterExclusive where it sometimes doesn't take the delimiter.
    const remaining = reader.buffer[reader.seek..];
    if (remaining.len == 0) return error.EndOfStream;
    if (std.mem.indexOfScalar(u8, remaining, delimiter)) |len| {
        const slice = try reader.take(len);
        const next = reader.takeByte() catch 0;
        std.debug.assert(next == delimiter);
        return slice;
    } else {
        const slice = try reader.take(remaining.len);
        std.debug.assert(reader.seek == reader.end);
        return slice;
    }
}

//
// Debugging
//

/// Prints a newline.
pub fn printBuf(comptime T: type, comptime item_fmt: []const u8, buf: []const T) void {
    std.log.debug("[", .{});
    for (0..buf.len) |i| {
        if (i > 0) std.log.debug(", ", .{});
        std.log.debug(item_fmt, .{buf[i]});
    }
    std.log.debug("]\n", .{});
}

pub const AssertionMode = enum {
    print,
    panic,
    fn maybePanic(comptime mode: AssertionMode, comptime fmt: []const u8, args: anytype) switch (mode) {
        .print => void,
        .panic => noreturn,
    } {
        switch (mode) {
            .print => std.log.debug(fmt ++ "\n", args),
            .panic => std.debug.panic(fmt, args),
        }
    }
};
fn comptimePanic(comptime fmt: []const u8, args: anytype) noreturn {
    @compileError(std.fmt.comptimePrint(fmt, args));
}

pub fn expectEq(comptime T: type, a: T, b: T, comptime mode: AssertionMode) void {
    const fmt = switch (@typeInfo(T)) {
        .@"struct", .@"enum", .@"union" => "{f} != {f}",
        else => "{} != {}",
    };
    if (a != b) {
        if (T == comptime_int and mode == .panic)
            comptimePanic(fmt, .{ a, b })
        else
            mode.maybePanic(fmt, .{ a, b });
    }
}

pub fn expectLen(comptime T: type, len: usize, comptime item_fmt: []const u8, buf: []const T, comptime mode: AssertionMode) void {
    if (len != buf.len) {
        printBuf(T, item_fmt, buf);
        mode.maybePanic("{} != {}; see buffer dump above", .{ len, buf.len });
    }
}

pub fn expectMemEq(comptime T: type, a: []const T, b: []const T, comptime item_fmt: []const u8, comptime mode: AssertionMode) void {
    const start_green = "\x1b[32m";
    const start_red = "\x1b[31m";
    const reset_color = "\x1b[0m";
    if (!std.mem.eql(T, a, b)) {
        inline for ([_]struct { []const u8, []const T, []const T }{ .{ "a", a, b }, .{ "b", b, a } }) |item| {
            const name, const buf, const other_buf = item;
            std.log.debug("{s}: ", .{name});
            std.log.debug(
                "[{s}{}{s}]" ++ @typeName(T) ++ "{{",
                .{ if (other_buf.len == buf.len) start_green else start_red, buf.len, reset_color },
            );
            for (0..buf.len) |i| {
                std.log.debug(
                    "{s}" ++ item_fmt,
                    .{ if (other_buf.len > i and other_buf[i] == buf[i]) start_green else start_red, buf[i] },
                );
            }
            std.log.debug(reset_color ++ "}}" ++ "\n", .{});
        }
        mode.maybePanic("a != b; see above", .{});
    }
}

//
// Arrays
//

pub inline fn comptimeArrayLen(comptime array: anytype) comptime_int {
    switch (@typeInfo(@TypeOf(array))) {
        .array => |arr| return arr.len,
        else => @compileError("not an array"),
    }
}

pub fn totalLen(things_with_a_len: anytype) usize {
    var len: usize = 0;
    for (things_with_a_len) |thing| len += thing.len;
    return len;
}

/// Appends `item` to `list`. If it's full, removes the first element.
pub fn appendRemovingFirst(comptime T: type, list: *ArrayList(T), item: T) void {
    if (list.items.len >= list.capacity) {
        _ = list.orderedRemove(0);
    }
    list.appendBounded(item) catch unreachable; // we removed one if it was full
}

//
// Math
//

/// I hate `@as(f32, @floatFromInt(...))`.
pub inline fn toF32(n: anytype) f32 {
    const t = @TypeOf(n);
    switch (@typeInfo(t)) {
        .int => |int| {
            if (int.bits > 32) @compileError("did not expect " ++ @typeName(t));
            return @floatFromInt(n);
        },
        .float => |float| {
            if (float.bits == 32) @compileError("it's already an f32 🤨");
            @compileError("did not expect " ++ @typeName(t));
        },
        .bool => return @floatFromInt(@intFromBool(n)),
        else => @compileError("did not expect " ++ @typeName(t)),
    }
}

/// For coercing comptime values.
pub inline fn asF32(n: f32) f32 {
    return n;
}

/// Avoid verbose casting.
pub inline fn toI32(n: anytype) i32 {
    const t = @TypeOf(n);
    switch (@typeInfo(t)) {
        .int => |int| {
            if (int.bits > 32) @compileError("did not expect " ++ @typeName(t));
            return @intCast(n);
        },
        .float => return @intFromFloat(n),
        .bool => return @intFromBool(n),
        else => @compileError("did not expect " ++ @typeName(t)),
    }
}

/// Treating the enum value as an int, adds the amount. The enum _must_ be dense.
pub fn enumWrappingAdd(comptime E: type, dest: *E, amt: i32) void {
    const enum_fields = @typeInfo(E).@"enum".fields;
    const count = enum_fields.len;
    // Catches most common cases of sparsity.
    if (enum_fields[enum_fields.len - 1].value != count - 1) {
        @compileError(@typeName(E) ++ " isn't dense");
    }
    var idx: i32 = @intFromEnum(dest.*);
    idx += amt;
    if (idx < 0) idx = count - 1;
    if (idx >= count) idx = 0;
    dest.* = @enumFromInt(idx);
}
test "enumWrappingAdd's density check" {
    const E = enum(i32) {
        value = 1,
    };
    var e: E = .value;
    e = e;
    // Shouldn't compile:
    // enumWrappingAdd(E, &e, 1);
}

/// `min` and `max` are both inclusive.
pub inline fn inRange(n: anytype, min: anytype, max: anytype) bool {
    return min <= n and n <= max;
}

/// Accurate to within a ten thousandth.
pub fn isApproxZero(n: f32) bool {
    return @abs(n) < 0.0001;
}

/// Returns the fractional part of `n`, based on flooring the number. This is
/// nice and consistent for things like positions, but it does mean for negative
/// numbers it's like the fractional part is subtracted from 1.
/// E.g.: 3.4 -> .4, -3.4 -> 0.6, etc.
pub fn decPartF(n: f32) f32 {
    return n - @floor(n);
}

/// Copy the decimal part of `src` into `dst`. Despite the underlying math being
/// a bit weird for negative numbers, they should work just fine.
pub fn setDecPartF(dst: *f32, src: f32) void {
    dst.* = @floor(dst.*) + decPartF(src);
}

/// Move `n` towards `to` by `amount`.
pub fn moveTowardsF(n: f32, to: f32, amount: f32) f32 {
    return if (n <= to) @min(n + amount, to) else @max(n - amount, to);
}

/// Returns how much between `a` and `b` `value` is, as 0.0 to 1.0.
pub fn inverseLerpF(value: f32, a: f32, b: f32) f32 {
    return (value - a) / (b - a);
}

/// Returns a value between `out_start` and `out_end` (inclusive) based on how
/// much between `in_start` and `in_end` `value` is.
pub fn remap(value: f32, in_start: f32, in_end: f32, out_start: f32, out_end: f32) f32 {
    return std.math.lerp(out_start, out_end, inverseLerpF(value, in_start, in_end));
}

test "that the stuff I wrote about decPartF is true" {
    const tolerance = 0.01;
    try std.testing.expectApproxEqRel(0.4, decPartF(3.4), tolerance);
    try std.testing.expectApproxEqRel(0.6, decPartF(-3.4), tolerance);
}

test "that moveTowardsF works" {
    try std.testing.expectEqual(4, moveTowardsF(1, 5, 3));
    try std.testing.expectEqual(5, moveTowardsF(1, 5, 7));
    try std.testing.expectEqual(5, moveTowardsF(7, 5, 7));
    try std.testing.expectEqual(6, moveTowardsF(7, 5, 1));
    try std.testing.expectEqual(5, moveTowardsF(5, 5, 5));
}
