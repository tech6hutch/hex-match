const std = @import("std");
const Font = @import("raylib").Font;
const core = @import("core.zig");
const assets = core.assets;

/// The languages this game supports.
pub const Lang = enum {
    en,
    pub const names: [count][:0]const u8 = .{
        "ENG",
    };
    pub const count = @typeInfo(Lang).@"enum".fields.len;

    pub fn name(self: Lang) [:0]const u8 {
        return names[@intFromEnum(self)];
    }
};

/// Get a translation in the current language.
pub fn _t(comptime en_line: [:0]const u8) [:0]const u8 {
    return String.t(en_line).get(core.lang);
}

/// Get a translation in the current language.
pub fn _c(comptime en_line: [:0]const u8, comptime context: []const u8) [:0]const u8 {
    return String.c(en_line, context).get(core.lang);
}

/// Get (a placeholder for) all translations for the line. The value for `.en` is guaranteed to exist.
pub fn _a(comptime en_line: [:0]const u8, comptime context: []const u8) String {
    return .{ .en_line = en_line, .context = context };
}

/// A unique identifier for a maybe-localized line of text. Can be used to get
/// an actual string (slice of chars) based on language.
pub const String = struct {
    en_line: [:0]const u8,
    context: []const u8,

    pub const empty = String.t("");
    pub fn isEmpty(self: String) bool {
        return self.eql(empty);
    }

    pub fn t(en_line: [:0]const u8) String {
        return c(en_line, "");
    }
    pub fn c(en_line: [:0]const u8, context: []const u8) String {
        return .{ .en_line = en_line, .context = context };
    }

    /// Resolves this string in the given language (EN if missing).
    pub fn get(self: String, lang: Lang) [:0]const u8 {
        return self._get(lang) orelse self.en_line;
    }
    /// Returns the font to use for this string (the EN font if the string is missing for `lang`).
    pub fn getFont(self: String, lang: Lang) Font {
        return assets.fonts_by_lang.get(self.resolveLang(lang)).*;
    }
    /// Returns the language if this string exists in it, otherwise EN.
    pub fn resolveLang(self: String, preferred: Lang) Lang {
        return if (self._get(preferred) != null) preferred else .en;
    }
    /// Resolves this string in the given language, if possible.
    fn _get(self: String, lang: Lang) ?[:0]const u8 {
        if (lang_data.get(lang).get(self)) |line| return line;

        // Don't complain about missing localizations if localizations weren't loaded to begin with.
        if (lang_data_was_loaded) {
            if (lang == .en or !lang_data.get(.en).contains(self)) {
                reportLineMissingEntirely(self);
            } else {
                reportLineMissingInLang(lang, self);
            }
        }
        return null;
    }

    fn eql(a: String, b: String) bool {
        return std.mem.eql(u8, a.en_line, b.en_line) and
            std.mem.eql(u8, a.context, b.context);
    }

    pub fn format(self: String, writer: anytype) !void {
        try writer.print("'{s}'", .{self.en_line});
        if (self.context.len > 0) try writer.print(" ({s})", .{self.context});
    }

    pub const Hasher = struct {
        pub fn hash(_: @This(), key: String) u64 {
            var h = std.hash.Wyhash.init(0);
            h.update(key.en_line);
            h.update(key.context);
            return h.final();
        }
        pub fn eql(_: @This(), a: String, b: String) bool {
            return a.eql(b);
        }
    };

    fn reportLineMissingEntirely(string: String) void {
        if (core.debug.misc) {
            const entry = reported_lines.getOrPutValue(core.debug.allocator, string, .initEmpty()) catch @panic("OOM");
            const already_reported = entry.value_ptr.eql(.initFull());
            entry.value_ptr.* = .initFull();
            if (already_reported) return;
        }
        std.debug.print("line not localized: {f}\n", .{string});
    }
    fn reportLineMissingInLang(lang: Lang, string: String) void {
        if (core.debug.misc) {
            const entry = reported_lines.getOrPutValue(core.debug.allocator, string, .initEmpty()) catch @panic("OOM");
            const already_reported = entry.value_ptr.contains(lang);
            entry.value_ptr.insert(lang);
            if (already_reported) return;
        }
        std.debug.print("language {t} missing {f}\n", .{ lang, string });
    }
    // Prevent console spam.
    var reported_lines: std.HashMapUnmanaged(String, std.EnumSet(Lang), String.Hasher, std.hash_map.default_max_load_percentage) = .empty;
};

/// Localized lines of text, per language.
///
/// Put in a language, get a map of `String`s (identifiers for lines) to strings (slices of chars).
pub var lang_data = std.EnumArray(
    Lang,
    std.HashMapUnmanaged(
        String,
        [:0]const u8,
        String.Hasher,
        std.hash_map.default_max_load_percentage,
    ),
).initFill(.empty);
var lang_data_was_loaded = false;

const CSV_COLUMNS: [Lang.count + 1][]const u8 = blk: {
    const names = std.meta.fieldNames(Lang);
    var arr: [Lang.count + 1][]const u8 = undefined;
    arr[0] = names[0];
    arr[1] = "context";
    for (1..names.len) |i| arr[i + 1] = names[i];
    break :blk arr;
};
pub fn loadCsvFile(io: std.Io, allocator: std.mem.Allocator, path: []const u8) error{ LoadCsvError, OutOfMemory }!void {
    const contents = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, std.Io.Limit.limited(5000)) catch |e| switch (e) {
        error.FileTooBig => std.debug.panic("'{s}' too big", .{path}), // the max bytes needs to be bigger
        else => std.debug.panic("{t}", .{e}),
    };
    defer allocator.free(contents);
    var line_iter = std.mem.splitScalar(u8, contents, '\n');

    // Column headers
    var column_line = line_iter.next() orelse @panic("pretty sure even an empty file has one line");
    const uf8_bom = [_]u8{ 0xEF, 0xBB, 0xBF };
    if (std.mem.startsWith(u8, column_line, &uf8_bom)) {
        column_line = column_line[uf8_bom.len..];
    }
    column_line = std.mem.trimEnd(u8, column_line, "\r");
    const column_headers = try splitCsv(column_line, 0);
    for (CSV_COLUMNS, column_headers) |col_name, value| {
        if (!std.mem.eql(u8, col_name, value)) {
            std.debug.print(
                "expected column {s} (len {d}), found '{s}' (len ({d})\n",
                .{ col_name, col_name.len, value, value.len },
            );
            return error.LoadCsvError;
        }
    }

    // Load data
    var line_num: u32 = 1;
    const languages = std.enums.values(Lang);
    while (line_iter.next()) |line_untrimmed| {
        const line = std.mem.trimEnd(u8, line_untrimmed, "\r");
        if (line.len == 0) break;
        const values = try splitCsv(line, line_num);
        line_num += 1;

        const en_line = try allocator.dupeZ(u8, values[0]);
        const key = String.c(en_line, try allocator.dupe(u8, values[1]));
        if (lang_data.get(.en).contains(key)) {
            std.debug.print("duplicate key: {f}\n", .{key});
        }
        try lang_data.getPtr(.en).put(allocator, key, en_line);

        for (2..CSV_COLUMNS.len) |col_idx| {
            try lang_data.getPtr(languages[col_idx - 1]).put(allocator, key, try allocator.dupeZ(u8, values[col_idx]));
        }
    }
    if (line_iter.next() != null) {
        std.debug.print("empty lines aren't allowed\n", .{});
        return error.LoadCsvError;
    }

    lang_data_was_loaded = true;
}

fn splitCsv(full_line: []const u8, line_num: u32) error{LoadCsvError}![CSV_COLUMNS.len][]const u8 {
    var buffer: [CSV_COLUMNS.len][]const u8 = undefined;
    var values = std.ArrayList([]const u8).initBuffer(&buffer);

    var line = full_line;
    while (true) {
        if (line.len == 0) {
            // Last value is empty.
            values.appendBounded(line) catch |e| switch (e) {
                error.OutOfMemory => return _splitCsvErr(line_num, "too many values in this line", @src()),
            };
            break;
        }
        if (line[0] == '"') {
            line = line[1..];
            const end = std.mem.indexOfScalar(u8, line, '"') orelse {
                return _splitCsvErr(line_num, "expected close quote", @src());
            };
            values.appendBounded(line[0..end]) catch |e| switch (e) {
                error.OutOfMemory => return _splitCsvErr(line_num, "too many values in this line", @src()),
            };
            line = line[end..];
            if (line.len > 0) line = line[1..]; // advance to the comma (if any)
        } else {
            const end = std.mem.indexOfScalar(u8, line, ',') orelse line.len;
            values.appendBounded(line[0..end]) catch |e| switch (e) {
                error.OutOfMemory => return _splitCsvErr(line_num, "too many values in this line", @src()),
            };
            line = line[end..];
        }
        if (line.len == 0) break;
        if (line[0] != ',') return _splitCsvErr(line_num, "expected comma between values", @src());
        line = line[1..];
    }

    if (values.items.len != values.capacity) return _splitCsvErr(line_num, "expected more values", @src());
    return buffer;
}

fn _splitCsvErr(line_num: u32, msg: []const u8, src: std.builtin.SourceLocation) error{LoadCsvError} {
    std.debug.print("Code line {d}, CSV line {d}: {s}\n", .{ src.line, line_num, msg });
    return error.LoadCsvError;
}

//
// Misc
//

/// Contains values of T for all languages.
pub fn Multilingual(comptime T: type) type {
    return std.EnumArray(Lang, T);
}
