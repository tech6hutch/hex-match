const std = @import("std");
const rl = @import("raylib");
const core = @import("core.zig");
const util = core.util;

//
// Game Inputs
//

pub const Input = enum {
    up,
    left,
    down,
    right,
    jump,
    throw,
    confirm,
    cancel,
    pause,
};

pub const default_inputs_keyboard = std.EnumArray(Input, rl.KeyboardKey).init(.{
    .up = .up,
    .left = .left,
    .down = .down,
    .right = .right,
    .jump = .z,
    .throw = .x,
    .confirm = .z,
    .cancel = .x,
    .pause = .enter,
});
pub const unrebindable_inputs_keyboard = std.EnumArray(Input, []const rl.KeyboardKey).initDefault(&.{}, .{
    .confirm = &.{ .enter, .space },
    .cancel = &.{.escape},
    .pause = &.{ .p, .escape },
});

pub const default_inputs_gamepad = std.EnumArray(Input, [3]rl.GamepadButton).init(.{
    .up = .{ .left_face_up, .unknown, .unknown },
    .left = .{ .left_face_left, .unknown, .unknown },
    .down = .{ .left_face_down, .unknown, .unknown },
    .right = .{ .left_face_right, .unknown, .unknown },
    .jump = .{ .right_face_left, .right_face_down, .right_face_right },
    .throw = .{ .right_face_up, .unknown, .unknown },
    .confirm = .{ .right_face_down, .unknown, .unknown },
    .cancel = .{ .right_face_right, .unknown, .unknown },
    .pause = .{ .middle_right, .unknown, .unknown },
});
pub const unrebindable_inputs_gamepad = std.EnumMap(Input, rl.GamepadButton).init(.{
    .cancel = .middle_left,
});

/// Get the name of the first btn or key currently bound to the input.
pub fn getBoundName(input: Input) [:0]const u8 {
    return switch (last_used_input_source) {
        .keyboard => @tagName(inputs_keyboard.get(input)),
        .gamepad => getBtnName(inputs_gamepad.get(input)[0]),
    };
}

fn shouldIgnoreInput(input: Input, options: InputOptions) bool {
    if (!options.ignore_gameplay) return false;
    // Defines which inputs are related to gameplay.
    return switch (input) {
        .left, .right, .up, .down, .jump, .throw => true,
        .confirm, .cancel, .pause => false,
    };
}

/// What controllers are connected.
pub var gamepads: [10]bool = @splat(false);
pub fn updateGamepadConnections() void {
    for (0..gamepads.len) |i| {
        gamepads[i] = rl.isGamepadAvailable(@intCast(i));
    }
}

pub var button_held_since: std.EnumArray(Input, ?u32) = .initFill(null);
pub fn updateButtonsHeld() void {
    for (std.enums.values(Input)) |input| {
        const since = button_held_since.getPtr(input);
        if (buttonDown(input, .{})) {
            if (since.* == null) {
                since.* = core.t;
            }
        } else {
            since.* = null;
        }
    }
}

pub var inputs_keyboard = default_inputs_keyboard;
pub var inputs_gamepad = default_inputs_gamepad;

pub const InputOptions = struct {
    /// Ignore gameplay controls (i.e., _not_ stuff like pausing).
    ignore_gameplay: bool = false,
};

pub fn buttonHeld(input: Input, at_least_secs: f32, options: InputOptions) bool {
    if (shouldIgnoreInput(input, options)) return false;
    const since_t = button_held_since.get(input) orelse return false;
    const secs_held = util.toF32(core.t - since_t) / core.FRAMES_PER_SEC;
    return secs_held >= at_least_secs;
}

pub fn buttonDown(input: Input, options: InputOptions) bool {
    if (shouldIgnoreInput(input, options)) return false;
    return _buttonDownOnKeyboard(input) or _buttonDownOnGamepad(input);
}
pub fn _buttonDownOnKeyboard(input: Input) bool {
    if (isKeyDown(inputs_keyboard.get(input))) return true;
    for (unrebindable_inputs_keyboard.get(input)) |key| {
        if (isKeyDown(key)) return true;
    }
    return false;
}
pub fn _buttonDownOnGamepad(input: Input) bool {
    for (inputs_gamepad.get(input)) |btn| {
        if (isGamepadButtonDown(btn)) return true;
    }
    if (unrebindable_inputs_gamepad.get(input)) |btn| {
        if (isGamepadButtonDown(btn)) return true;
    }
    const push_strength = 0.5;
    return switch (input) {
        .up => _analogStrength(.up_down) <= -push_strength,
        .down => _analogStrength(.up_down) >= push_strength,
        .left => _analogStrength(.left_right) <= -push_strength,
        .right => _analogStrength(.left_right) >= push_strength,
        else => false,
    };
}

pub fn buttonPressed(input: Input, options: InputOptions) bool {
    if (shouldIgnoreInput(input, options)) return false;
    return _buttonPressedOnKeyboard(input) or _buttonPressedOnGamepad(input);
}
pub fn _buttonPressedOnKeyboard(input: Input) bool {
    if (isKeyPressed(inputs_keyboard.get(input))) return true;
    for (unrebindable_inputs_keyboard.get(input)) |key| {
        if (isKeyPressed(key)) return true;
    }
    return false;
}
pub fn _buttonPressedOnGamepad(input: Input) bool {
    for (inputs_gamepad.get(input)) |btn| {
        if (isGamepadButtonPressed(btn)) return true;
    }
    if (unrebindable_inputs_gamepad.get(input)) |btn| {
        if (isGamepadButtonPressed(btn)) return true;
    }
    return switch (input) {
        // We want to return true if the analog stick was just pushed far enough to count as a
        // directional input. The easiest way to do this is just to check if the input just started
        // being held this frame. (See buttonDown for what counts as a directional input.)
        .up, .down, .left, .right => button_held_since.get(input) == core.t,
        else => false,
    };
}

pub const InputAxis = enum { left_right, up_down };
/// Returns a number from -1.0 to 1.0.
pub fn inputStrength(comptime input: InputAxis, options: InputOptions) f32 {
    if (options.ignore_gameplay) return 0;

    var strength: f32 = 0;
    strength += switch (input) {
        .left_right => util.toF32(buttonDown(.right, options)) - util.toF32(buttonDown(.left, options)),
        .up_down => util.toF32(buttonDown(.down, options)) - util.toF32(buttonDown(.up, options)),
    };
    strength += _analogStrength(input);
    const deadzone = 0.1;
    return if (@abs(strength) < deadzone) 0 else std.math.clamp(strength, -1.0, 1.0);
}
fn _analogStrength(comptime input: InputAxis) f32 {
    var strength: f32 = 0;
    for (0..gamepads.len) |i| {
        if (!gamepads[i]) continue;
        const gamepad: i32 = @intCast(i);
        strength += switch (input) {
            .left_right => rl.getGamepadAxisMovement(gamepad, .left_x),
            .up_down => rl.getGamepadAxisMovement(gamepad, .left_y),
        };
    }
    return strength;
}

//
// Generic Inputs
//

/// Normalizes key.
pub fn isKeyPressed(key: rl.KeyboardKey) bool {
    if (rl.isKeyPressed(key)) return true;
    if (key == .enter and rl.isKeyPressed(.kp_enter)) return true;
    return false;
}
/// Normalizes key.
pub fn isKeyDown(key: rl.KeyboardKey) bool {
    if (rl.isKeyDown(key)) return true;
    if (key == .enter and rl.isKeyDown(.kp_enter)) return true;
    return false;
}
/// For keys that are treated the same.
pub fn normalizeKey(key: rl.KeyboardKey) rl.KeyboardKey {
    return switch (key) {
        .kp_enter => .enter,
        else => key,
    };
}

pub fn isKeyPressedWithRepeat(key: rl.KeyboardKey) bool {
    return rl.isKeyPressed(key) or rl.isKeyPressedRepeat(key);
}

pub fn anyKeyPressed(keys: []const rl.KeyboardKey) bool {
    for (keys) |key| {
        if (rl.isKeyPressed(key)) return true;
    }
    return false;
}

pub fn anyKeyDown(keys: []const rl.KeyboardKey) bool {
    for (keys) |key| {
        if (rl.isKeyDown(key)) return true;
    }
    return false;
}

pub fn anyKeyReleased(keys: []const rl.KeyboardKey) bool {
    for (keys) |key| {
        if (rl.isKeyReleased(key)) return true;
    }
    return false;
}

pub fn isGamepadButtonPressed(button: rl.GamepadButton) bool {
    for (0..gamepads.len) |i| {
        if (!gamepads[i]) continue;
        const gamepad: i32 = @intCast(i);
        if (rl.isGamepadButtonPressed(gamepad, button)) return true;
    }
    return false;
}

pub fn isGamepadButtonDown(button: rl.GamepadButton) bool {
    for (0..gamepads.len) |i| {
        if (!gamepads[i]) continue;
        const gamepad: i32 = @intCast(i);
        if (rl.isGamepadButtonDown(gamepad, button)) return true;
    }
    return false;
}

pub const InputSource = enum { keyboard, gamepad };
pub var last_used_input_source: InputSource = .keyboard;
pub const GamepadLayout = enum { microsoft, nintendo, sony };
pub var gamepad_layout: GamepadLayout =
    if (core.debug.misc)
        .nintendo // my controller has this layout
    else
        .microsoft; // but this one is more standard on PCs

const button_names_shared = std.EnumArray(rl.GamepadButton, [:0]const u8).init(.{
    .unknown = "",
    .left_face_up = "up",
    .left_face_right = "right",
    .left_face_down = "down",
    .left_face_left = "left",
    .right_face_up = "",
    .right_face_right = "",
    .right_face_down = "",
    .right_face_left = "",
    .left_trigger_1 = "L1",
    .left_trigger_2 = "L2",
    .right_trigger_1 = "R1",
    .right_trigger_2 = "R2",
    .middle_left = "select",
    // I can't actually get this button to trigger. It works with Steam and Windows's "controller bar"
    // (which I just learned is a thing), but even with those disabled, it isn't passed to the game.
    .middle = "",
    .middle_right = "start",
    // Clicking the stick
    .left_thumb = "L3",
    .right_thumb = "R3",
});
const button_names_by_vendor = std.EnumArray(GamepadLayout, std.EnumArray(rl.GamepadButton, [:0]const u8)).init(.{
    .microsoft = .initDefault("", .{
        .right_face_up = "Y",
        .right_face_right = "B",
        .right_face_down = "A",
        .right_face_left = "X",
        .middle_left = "back",
        .middle = "Xbox",
        // The shoulder buttons have different names, but "L1" etc is fine IMO.
    }),
    .nintendo = .initDefault("", .{
        .right_face_up = "X",
        .right_face_right = "A",
        .right_face_down = "B",
        .right_face_left = "Y",
        .middle = "home", // I think?
    }),
    .sony = .initDefault("", .{
        .right_face_up = "triangle",
        .right_face_right = "circle",
        .right_face_down = "cross",
        .right_face_left = "square",
        .middle = "PS",
        // I'm not sure what select is on PS4+ (the touchpad thing?), so I'll just call it select.
        // And if I'm leaving it as "select" then I might as well leave "start" as-is.
    }),
});
pub fn getBtnName(btn: rl.GamepadButton) [:0]const u8 {
    var name = button_names_by_vendor.get(gamepad_layout).get(btn);
    if (name.len > 0) return name;
    name = button_names_shared.get(btn);
    if (name.len > 0) return name;
    return @tagName(btn);
}
