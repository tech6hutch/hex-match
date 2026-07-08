const rl = @import("raylib");

/// Pixel coordinates.
///
/// Imported from Raylib.
pub const Vector2 = rl.Vector2;
pub fn vecIsZero(v: Vector2) bool {
    return v.x == 0 and v.y == 0;
}

/// Imported from Raylib.
pub const Rectangle = rl.Rectangle;
pub fn recIsZero(rec: Rectangle) bool {
    return rec.x == 0 and rec.y == 0 and rec.width == 0 and rec.height == 0;
}

pub const checkCollisionRecs = rl.checkCollisionRecs;

/// The rectangle should contain the ellipse.
pub fn checkCollisionPointEllipse(point: Vector2, ellipse_rect: Rectangle) bool {
    const radius_x = ellipse_rect.width / 2;
    const radius_y = ellipse_rect.height / 2;
    var delta = point.subtract(rectCenter(ellipse_rect));
    delta.y *= radius_x / radius_y;
    return delta.x * delta.x + delta.y * delta.y <= radius_x * radius_x;
}

pub fn rectFromTopLeft(top_left: Vector2, size: Vector2) Rectangle {
    return .{
        .x = top_left.x,
        .y = top_left.y,
        .width = size.x,
        .height = size.y,
    };
}

pub fn rectEnds(rect: Rectangle) struct { Vector2, Vector2 } {
    return .{ rectTopLeft(rect), rectBottomRight(rect) };
}

pub fn rectTopLeft(rect: Rectangle) Vector2 {
    return .init(rect.x, rect.y);
}

pub fn rectBottomRight(rect: Rectangle) Vector2 {
    return .init(rect.x + rect.width - 1, rect.y + rect.height - 1);
}

pub fn rectCenter(rect: Rectangle) Vector2 {
    return .init(rect.x + rect.width / 2, rect.y + rect.height / 2);
}

pub fn vecXY(vec: Vector2) struct { f32, f32 } {
    return .{ vec.x, vec.y };
}
pub fn vecXYZ(vec: rl.Vector3) struct { f32, f32, f32 } {
    return .{ vec.x, vec.y, vec.z };
}

pub fn floorVec(vec: Vector2) Vector2 {
    return .init(@floor(vec.x), @floor(vec.y));
}

/// Hues must be in the form 0..360. Handles wrapping around at the edges.
pub fn mixHues(a: f32, b: f32) f32 {
    if (@abs(a - b) <= 180) return (a + b) / 2;

    var hue = (a + b + 360) / 2;
    if (hue >= 360) hue -= 360;
    return hue;
}
/// Hues must be in the form 0..360. Handles wrapping around at the edges.
pub fn hueDistance(a: f32, b: f32) f32 {
    if (@abs(a - b) <= 180) return @abs(a - b);

    var smaller, const bigger =
        if (a < b)
            .{ a, b }
        else
            .{ b, a };
    smaller += 360;
    return @abs(smaller - bigger);
}
