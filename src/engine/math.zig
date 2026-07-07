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

pub fn floorVec(vec: Vector2) Vector2 {
    return .init(@floor(vec.x), @floor(vec.y));
}
