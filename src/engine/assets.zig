const std = @import("std");
const Allocator = std.mem.Allocator;
const rl = @import("raylib");
const i18n = @import("internationalization.zig");

// These are initialized at the start and valid for the whole program.
/// The main English font.
pub var font: rl.Font = undefined;
/// An alternate font that's easier to read and has more chars.
pub var alt_font: rl.Font = undefined;

pub var textures: AssetMap(rl.Texture, null) = undefined;
pub var sounds: AssetMap(rl.Sound, null) = undefined;

pub const fonts_by_lang = i18n.Multilingual(*const rl.Font).init(.{
    .en = &font,
});
pub const en_font_size = 32;
pub const font_size_by_lang = i18n.Multilingual(f32).init(.{
    .en = en_font_size,
});
pub const line_scale_by_lang = i18n.Multilingual(f32).init(.{
    .en = 1.5,
});

pub fn fetchSoundName(sound: rl.Sound) []const u8 {
    var iter = sounds.inner.iterator();
    while (iter.next()) |entry| {
        if (entry.value_ptr.stream.buffer == sound.stream.buffer) {
            return entry.key_ptr.*;
        }
    }
    return "<UNKNOWN SOUND>";
}

/// Holds assets for use in Raylib.
fn AssetMap(comptime T: type, comptime key_whitelist: ?[]const []const u8) type {
    return struct {
        inner: Inner,

        const Self = @This();
        const Inner = std.StringHashMapUnmanaged(T);

        pub fn init(allocator: Allocator, comptime keys: []const []const u8) Allocator.Error!Self {
            var self = Self{ .inner = Inner.empty };
            try self.inner.ensureTotalCapacity(allocator, @intCast(keys.len));
            inline for (keys) |key| _compileErrorIfKeyInvalid(key);
            return self;
        }

        pub fn get(self: Self, comptime key: []const u8) T {
            _compileErrorIfKeyInvalid(key);
            return self.inner.get(key) orelse std.debug.panic("unknown key '{s}'", .{key});
        }

        /// Panics if no room.
        pub fn put(self: *Self, comptime key: []const u8, value: T) void {
            _compileErrorIfKeyInvalid(key);
            self.inner.putAssumeCapacity(key, value);
        }

        fn _compileErrorIfKeyInvalid(comptime key: []const u8) void {
            if (key_whitelist) |keys| {
                var found = false;
                for (keys) |k| {
                    if (std.mem.eql(u8, k, key)) {
                        found = true;
                        break;
                    }
                }
                if (!found) @compileError("unknown key '" ++ key ++ "'");
            }
        }
    };
}
