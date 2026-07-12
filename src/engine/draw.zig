const std = @import("std");
const rl = @import("raylib");
const core = @import("core.zig");
const assets = core.assets;
const math = core.math;
const i18n = core.i18n;
const util = core.util;
const debug = core.debug;
const Entity = core.Entity;
const Multilingual = i18n.Multilingual;
const Rectangle = math.Rectangle;
const Vector2 = math.Vector2;

/// Resolution to draw text at. 2 for double (16x16 pixels in 8x8 game pixels).
/// Obviously, the game pixels can't be drawn at a scale lower than this.
pub const high_res_text_scale = 1;

/// Imported from Raylib.
pub const Color = rl.Color;

/// Imported from Raylib.
pub const Texture = rl.Texture;

/// Imported from Raylib.
pub const Image = rl.Image;
pub const getImageColor: fn (Image, i32, i32) Color = rl.getImageColor;

pub const SpriteSheet = struct {
    texture: rl.Texture,
    tile_size: Vector2,
};

/// Imported from Raylib.
pub const RenderTexture = rl.RenderTexture;
pub const beginTextureMode = rl.beginTextureMode;

// (My editor shows a preview of the color when it's preceded by a hash.)
pub const pico8_colors = struct {
    pub const black = rl.Color.init(0, 0, 0, 255); // #000000
    pub const dark_blue = rl.Color.init(29, 43, 83, 255); // #1D2B53
    pub const dark_purple = rl.Color.init(126, 37, 83, 255); // #7E2553
    pub const dark_green = rl.Color.init(0, 135, 81, 255); // #008751
    pub const brown = rl.Color.init(171, 82, 54, 255); // #AB5236
    pub const dark_grey = rl.Color.init(95, 87, 79, 255); // #5F574F
    pub const light_grey = rl.Color.init(194, 195, 199, 255); // #C2C3C7
    pub const white = rl.Color.init(255, 241, 232, 255); // #FFF1E8
    pub const red = rl.Color.init(255, 0, 77, 255); // #FF004D
    pub const orange = rl.Color.init(255, 163, 0, 255); // #FFA300
    pub const yellow = rl.Color.init(255, 236, 39, 255); // #FFEC27
    pub const green = rl.Color.init(0, 228, 54, 255); // #00E436
    pub const blue = rl.Color.init(41, 173, 255, 255); // #29ADFF
    pub const lavender = rl.Color.init(131, 118, 156, 255); // #83769C
    pub const pink = rl.Color.init(255, 119, 168, 255); // #FF77A8
    pub const light_peach = rl.Color.init(255, 204, 170, 255); // #FFCCAA

    pub const brownish_black = rl.Color.init(41, 24, 20, 255); // #291814
    pub const darker_blue = rl.Color.init(17, 29, 53, 255); // #111D35
    pub const darker_purple = rl.Color.init(66, 33, 54, 255); // #422136
    pub const blue_green = rl.Color.init(18, 83, 89, 255); // #125359
    pub const dark_brown = rl.Color.init(116, 47, 41, 255); // #742F29
    pub const darker_grey = rl.Color.init(73, 51, 59, 255); // #49333B
    pub const medium_grey = rl.Color.init(162, 136, 121, 255); // #A28879
    pub const light_yellow = rl.Color.init(243, 239, 125, 255); // #F3EF7D
    pub const dark_red = rl.Color.init(190, 18, 80, 255); // #BE1250
    pub const dark_orange = rl.Color.init(255, 108, 36, 255); // #FF6C24
    pub const lime_green = rl.Color.init(168, 231, 46, 255); // #A8E72E
    pub const medium_green = rl.Color.init(0, 181, 67, 255); // #00B543
    pub const true_blue = rl.Color.init(6, 90, 181, 255); // #065AB5
    pub const mauve = rl.Color.init(117, 70, 101, 255); // #754665
    pub const dark_peach = rl.Color.init(255, 110, 89, 255); // #FF6E59
    pub const peach = rl.Color.init(255, 157, 129, 255); // #FF9D81
};

//
// Shapes
//

pub fn line(startPos: Vector2, endPos: Vector2, thick: f32, color: Color) void {
    rl.drawLineEx(startPos, endPos, thick, color);
}

/// Draw triangle filled. Vertices in counter-clockwise order.
pub fn triangle(v1: Vector2, v2: Vector2, v3: Vector2, color: Color) void {
    rl.drawTriangle(v1, v2, v3, color);
}

/// Draw rectangle filled.
pub fn rectangle(rect: Rectangle, color: Color) void {
    rl.drawRectangleRec(rect, color);
}
/// Draw rectangle outline.
pub fn rectangleLines(rect: Rectangle, lineThick: f32, color: Color) void {
    rl.drawRectangleLinesEx(rect, lineThick, color);
}
/// Draw a rectangle filled with a gradient.
pub fn rectangleGradient(rect: Rectangle, topLeft: Color, bottomLeft: Color, bottomRight: Color, topRight: Color) void {
    rl.drawRectangleGradientEx(rect, topLeft, bottomLeft, bottomRight, topRight);
}

/// Draw a regular polygon.
pub fn polygon(center: Vector2, sides: i32, radius: f32, rotation: f32, color: Color) void {
    rl.drawPoly(center, sides, radius, rotation, color);
}
/// Draw a polygon outline.
pub fn polygonLines(center: Vector2, sides: i32, radius: f32, rotation: f32, lineThick: f32, color: Color) void {
    rl.drawPolyLinesEx(center, sides, radius, rotation, lineThick, color);
}

//
// Textures & images
//

pub const DrawTextureArgs = struct {
    source: Rectangle = .init(0, 0, 0, 0),
    origin: Vector2 = .init(0, 0),
    rotation: f32 = 0,
    tint: Color = .white,
};
/// Draw texture to fill rectangle.
pub fn textureRec(texture: Texture, dest: Rectangle, args: DrawTextureArgs) void {
    rl.drawTexturePro(
        texture,
        if (math.recIsZero(args.source))
            Rectangle{
                .x = 0,
                .y = 0,
                .width = @floatFromInt(texture.width),
                .height = @floatFromInt(texture.height),
            }
        else
            args.source,
        dest,
        args.origin,
        args.rotation,
        args.tint,
    );
}
/// Draw texture at position.
pub fn textureV(texture: Texture, pos: Vector2, args: DrawTextureArgs) void {
    textureRec(texture, .{
        .x = pos.x,
        .y = pos.y,
        .width = @floatFromInt(texture.width),
        .height = @floatFromInt(texture.height),
    }, args);
}

/// Draw texture at position with outline.
/// Position does not include the outline.
pub fn textureVWithOutline(texture: Texture, position: Vector2, outline_tint: rl.Color, args: DrawTextureArgs) void {
    const x, const y = math.vecXY(position);
    for (&[_]struct { f32, f32 }{ .{ -1, 0 }, .{ 1, 0 }, .{ 0, -1 }, .{ 0, 1 } }) |offsets| {
        var outline_args = args;
        outline_args.tint = outline_tint;
        const dx, const dy = offsets;
        textureRec(texture, .init(x + dx, y + dy, 8, 8), outline_args);
    }
    textureRec(texture, .init(x, y, 8, 8), args);
}

/// Draw texture that stretches and shrinks nicely.
pub fn nPatch(texture: rl.Texture, nPatchInfo: rl.NPatchInfo, dest: Rectangle) void {
    rl.drawTextureNPatch(texture, nPatchInfo, dest, .zero(), 0, .white);
}

pub fn imageIsHorizontallySymmetrical(image: Image, src: Rectangle) bool {
    var y: i32 = @intFromFloat(src.y);
    const last_y: i32 = @intFromFloat(math.rectBottomRight(src).y);
    while (y <= last_y) : (y += 1) {
        var x_left: i32 = @intFromFloat(src.x);
        var x_right: i32 = @intFromFloat(math.rectBottomRight(src).x);
        while (x_right > x_left) : ({
            x_left += 1;
            x_right -= 1;
        }) {
            if (image.getColor(x_left, y).toInt() != image.getColor(x_right, y).toInt()) return false;
        }
    }
    return true;
}

//
// Text
//

/// Handy bundle of state for drawing text and other things.
pub const Cursor = struct {
    start_x: f32 = 0,
    x: f32 = 0,
    y: f32 = 0,
    lang: i18n.Lang,
    color: Color = .black,
    effect: ?TextEffect = null,
    text_scale: u8 = 1,

    pub fn font(self: Cursor) rl.Font {
        return assets.fonts_by_lang.get(self.lang).*;
    }
    pub fn fontSize(self: Cursor) f32 {
        return assets.font_size_by_lang.get(self.lang);
    }
    pub fn lineHeight(self: Cursor) f32 {
        return @ceil(self.fontSize() * util.toF32(self.text_scale) * assets.line_scale_by_lang.get(self.lang));
    }
    pub fn lineOffsetY(self: Cursor) f32 {
        return @floor((self.lineHeight() - self.fontSize()) / 2);
    }

    pub fn print(self: *Cursor, text: [:0]const u8) void {
        self.x += textHighRes(
            text,
            self.x,
            self.y + self.lineOffsetY(),
            self.font(),
            self.fontSize() * util.toF32(self.text_scale),
            self.color,
            self.effect,
        );
    }

    pub const PrintExArgs = struct {
        ascii: bool = false,
        centered: bool = false,
        color: Color = .blank,
        /// If present but false, inserts empty space instead.
        surround_with_arrows_if: ?bool = null,
    };
    pub fn printEx(self: *Cursor, text: [:0]const u8, args: PrintExArgs) void {
        if (args.centered) {
            self.center(text.len);
        }
        const color = self.color;
        const lang = self.lang;
        if (args.ascii) self.lang = .en;
        if (args.color.a > 0) self.color = args.color;
        if (args.surround_with_arrows_if) |cond| self.printAscii(if (cond) "<" else " ");
        self.print(text);
        if (args.surround_with_arrows_if) |cond| self.printAscii(if (cond) ">" else " ");
        self.lang = lang;
        self.color = color;
    }

    /// Newlines are supported, but must be in a string by themselves.
    pub fn printAll(self: *Cursor, texts: []const [:0]const u8, args: PrintExArgs) void {
        var args2 = args;
        if (args.centered) {
            self.center(util.totalLen(texts));
            args2.centered = false;
        }
        std.debug.assert(args.surround_with_arrows_if == null); // unimplemented
        for (texts) |text| {
            if (text.len > 0 and std.mem.allEqual(u8, text, '\n')) {
                for (0..text.len) |_| self.row();
            } else {
                self.printEx(text, args2);
            }
        }
    }

    fn center(self: *Cursor, text_len: usize) void {
        std.debug.assert(core.lang == .en); // todo: get the actual width, to support other langs
        const width = core.windowing.textWidthAscii(text_len * self.text_scale);
        self.start_x =
            if (width > core.game_width)
                0
            else
                @as(f32, @floatFromInt(core.game_width - width)) / 2;
        self.x = self.start_x;
    }

    pub fn printAscii(self: *Cursor, text: [:0]const u8) void {
        self.printEx(text, .{ .ascii = true });
    }

    pub fn row(self: *Cursor) void {
        self.x = self.start_x;
        self.y += self.lineHeight();
    }
};

/// Draw text and return its size.
pub fn textSized(text: [:0]const u8, posX: f32, posY: f32, fontSize: f32, color: Color) f32 {
    rl.drawTextEx(assets.font, text, Vector2.init(posX, posY), fontSize, 0, color);
    return rl.measureTextEx(assets.font, text, fontSize, 0).x;
}
pub const TextEffect = struct {
    kind: union(enum) {
        outline: Color,
        thick_outline: Color,
        shadow: Color,
        basic_shadow: Color,
    },
    scale: f32 = 1,
};
/// Draw text at higher-than-normal resolution. Returns its width.
pub fn textHighRes(text: [:0]const u8, posX: f32, posY: f32, font: rl.Font, fontSize: f32, color: Color, text_effect: ?TextEffect) f32 {
    if (text_effect) |effect| {
        const extra_color: Color, const offsets: []const Vector2 = switch (effect.kind) {
            .thick_outline => |outline| .{
                outline,
                &[_]Vector2{
                    .init(-1, -1), .init(0, -1), .init(1, -1),
                    .init(-1, 0),  .init(0, 0),  .init(1, 0),
                    .init(-1, 1),  .init(0, 1),  .init(1, 1),
                },
            },
            .outline => |outline| .{ outline, &[_]Vector2{ .init(-1, 0), .init(1, 0), .init(0, -1), .init(0, 1) } },
            .shadow => |shadow| .{ shadow, &[_]Vector2{ .init(1, 1), .init(1, 0), .init(0, 1) } },
            .basic_shadow => |shadow| .{ shadow, &[_]Vector2{.init(1, 1)} },
        };
        for (offsets) |offset| {
            const text_scale_inverted = 1.0 / @as(comptime_float, high_res_text_scale);
            rl.drawTextEx(
                font,
                text,
                Vector2.init(posX, posY).add(
                    offset.scale(text_scale_inverted).scale(effect.scale),
                ).scale(high_res_text_scale),
                fontSize * high_res_text_scale,
                0,
                extra_color,
            );
        }
    }
    rl.drawTextEx(
        font,
        text,
        Vector2.init(posX, posY).scale(high_res_text_scale),
        fontSize * high_res_text_scale,
        0,
        color,
    );
    return rl.measureTextEx(font, text, fontSize, 0).x;
}

//
// Game stuff
//

/// Draw the entity and advance its animation.
pub fn drawEntity(ent: *Entity) void {
    for (core.getRectScreenWrapped(ent.drawingRect())) |dest| {
        textureRec(ent.sprite_sheet.texture, dest, .{ .source = ent.sheetRect() });
    }

    if (debug.animation_disabled) {
        if (!debug.animation_advance_once) return;
        debug.animation_advance_once = false;
    }
    ent.advanceAnimation(core.FRAME_DELTA);
}
