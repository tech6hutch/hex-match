const std = @import("std");
const rl = @import("raylib");
const core = @import("core.zig");
const draw = core.draw;
const inputs = core.inputs;
const i18n = core.i18n;
const util = core.util;
const pico8_colors = draw.pico8_colors;
const Rectangle = core.math.Rectangle;
const Vector2 = core.math.Vector2;

pub const UpdateResult = enum {
    /// Either there's no menu or it's still open.
    no_change,
    /// The menu just closed, so ignore any input that could open one again this frame.
    closed,
    /// The menu just closed, but also exit the level.
    exit_level,
};
pub fn update() UpdateResult {
    const menu = get() orelse return .no_change;

    const result: UpdateResult = result: {
        const callbacks = switch (menu.def.callback) {
            .update => |updateFn| {
                switch (updateFn(menu)) {
                    .stay_open => {},
                    .push => |submenu| _push(submenu),
                    .pop => {
                        pop();
                        if (stack.items.len == 0) break :result .closed;
                    },
                    .close => {
                        close();
                        break :result .closed;
                    },
                    .exit_level => {
                        close();
                        break :result .exit_level;
                    },
                }
                break :result .no_change;
            },

            .input => |callbacks| callbacks,
        };

        moveSelectorBasedOnInput(menu);
        if (inputs.buttonPressed(.cancel, .{}) and (stack.items.len > 1 or menu.kind() == .pause)) {
            pop();
            if (stack.items.len == 0) break :result .closed; // we just unpaused, prevent re-pausing
        } else if (inputs.buttonPressed(.pause, .{}) and menu.kind() == .pause) {
            close();
            break :result .closed; // prevent immediately re-pausing
        }

        if (callbacks.on_confirm) |on_confirm| {
            if (inputs.buttonPressed(.confirm, .{})) {
                switch (on_confirm(menu.*)) {
                    .stay_open => {},
                    .push => |submenu| _push(submenu),
                    .pop => {
                        pop();
                        if (stack.items.len == 0) break :result .closed;
                    },
                    .close => {
                        close();
                        break :result .closed;
                    },
                    .exit_level => {
                        close();
                        break :result .exit_level;
                    },
                }
            }
        }
        if (callbacks.on_left_or_right) |on_left_or_right| {
            if (getLeftRightInput()) |lr| on_left_or_right(menu.*, lr.is_left, lr.is_repeat);
        }
        break :result .no_change;
    };

    just_opened -|= 1; // saturating subtraction: -1 if it's >0
    return result;
}
fn moveSelectorBasedOnInput(menu: *Menu) void {
    if (menu.def.items.len > 0) {
        while (true) {
            var idx: i32 = menu.selection;
            if (inputs.buttonPressed(.up, .{})) idx -= 1;
            if (inputs.buttonPressed(.down, .{})) idx += 1;
            if (idx < 0) idx = @intCast(menu.def.items.len - 1);
            if (idx >= menu.def.items.len) idx = 0;
            menu.selection = @intCast(idx);
            // Skip empty menu items
            if (!menu.def.items[menu.selection].isEmpty()) break;
        }
    }
}
const LeftRightInput = struct { is_left: bool, is_repeat: bool };
fn getLeftRightInput() ?LeftRightInput {
    const repeated_left = inputs.buttonHeld(.left, 0.2, .{});
    const repeated_right = inputs.buttonHeld(.right, 0.2, .{});
    const pressed_left = inputs.buttonPressed(.left, .{}) or repeated_left;
    const pressed_right = inputs.buttonPressed(.right, .{}) or repeated_right;
    return if (pressed_left or pressed_right)
        .{
            .is_left = pressed_left,
            .is_repeat = if (pressed_left) repeated_left else repeated_right,
        }
    else
        null;
}

/// Draws the borders and background to the current render target, but switches
/// to `text_texture` for text.
pub fn drawMenu(text_texture: rl.RenderTexture) void {
    const menu = core.menus.get() orelse return;

    const padding = 6;
    const border = 1;
    var cursor = draw.Cursor{
        .lang = core.lang,
        .color = pico8_colors.white,
    };
    std.debug.assert(menu.def.width > padding * 2); // width includes padding
    var non_empty_count: f32 = 0;
    for (menu.def.items) |menu_item| {
        if (!menu_item.isEmpty()) non_empty_count += 1;
    }
    const size = Vector2{
        .x = border + menu.def.width + border,
        .y = border + padding + cursor.lineHeight() * non_empty_count + padding + border,
    };
    const margin = Vector2.init(core.game_width, core.game_height).subtract(size).scale(0.5);
    cursor.start_x = margin.x + padding + border;
    cursor.x = cursor.start_x;
    cursor.y = margin.y + padding + border;
    draw.rectangle(Rectangle{
        .x = margin.x,
        .y = margin.y,
        .width = 1 + size.x + 1,
        .height = 1 + size.y + 1,
    }, pico8_colors.black);
    draw.rectangleLines(Rectangle{
        .x = margin.x + 1,
        .y = margin.y + 1,
        .width = size.x,
        .height = size.y,
    }, border, pico8_colors.white);
    // const box = rl.NPatchInfo{
    //     .source = Rectangle.init(0, 0, 8 * 3, 8 * 3),
    //     .left = border,
    //     .right = border,
    //     .top = border,
    //     .bottom = border,
    //     .layout = rl.NPatchType.nine_patch,
    // };
    // draw.nPatch(
    //     core.assets.textures.get("menu.png"),
    //     box,
    //     Rectangle.init(margin.x, margin.y, size.x, size.y),
    // );

    rl.beginTextureMode(text_texture);

    for (menu.def.items, 0..) |menu_item, i| {
        if (menu_item.isEmpty()) continue;

        if (i > 0) cursor.row();
        const selector = if (menu.selection == i) "> " else "  ";
        cursor.lang = .en;
        cursor.printAscii(selector);
        cursor.lang = core.lang;

        const text = menu_item.get(core.lang);
        // Not changing cursor.lang to text's lang because the menu is drawn based on all rows being the same size.
        cursor.print(text);
        if (menu.def.draw_item) |drawFn| drawFn(menu.*, i, &cursor);
    }
}

pub const Menu = struct {
    def: Definition,
    selection: u8 = 0,

    /// Returns the topmost menu's kind.
    pub fn kind(_: Menu) Kind {
        return stack.items[0].def.kind;
    }

    pub const Definition = struct {
        kind: Kind = .submenu,
        width: f32,
        /// Menu item text. Empty items will be skipped.
        items: []const i18n.String,
        callback: union(enum) {
            /// You control all input.
            update: *const fn (menu: *Menu) CallbackResult,
            /// Up/down inputs are handled automatically.
            input: struct {
                /// Make menu items actually do something when confirmed.
                on_confirm: ?*const fn (menu: Menu) CallbackResult,
                /// For adjustable options.
                on_left_or_right: ?*const fn (menu: Menu, is_left: bool, is_repeat: bool) void = null,
            },
            pub const none: @This() = .{ .input = .{ .on_confirm = null } };
        },
        /// For drawing extra things for a menu item. No need to call `cursor.row()`, it's done between calls.
        draw_item: ?*const fn (menu: Menu, item_idx: usize, cursor: *draw.Cursor) void = null,
    };
    pub const Kind = enum { submenu, pause };
    pub const CallbackResult = union(enum) {
        stay_open,
        push: Menu,
        pop,
        close,
        exit_level,
    };
};

var _stack_buffer: [4]Menu = undefined;
pub var stack: std.ArrayList(Menu) = .initBuffer(&_stack_buffer);

/// For menu callbacks, whether the menu was just opened this frame. It's a
/// number to make it easier to manage the state; **just check if it's nonzero**.
pub var just_opened: u8 = 0;

pub fn get() ?*Menu {
    return if (stack.items.len == 0) null else &stack.items[stack.items.len - 1];
}

/// Open a new menu from the given definition.
pub fn open(menu_def: Menu.Definition) void {
    std.debug.assert(menu_def.kind != .submenu);
    close();
    _push(.{ .def = menu_def });
}
pub fn close() void {
    stack.clearRetainingCapacity();
}

/// Create a menu from the given definition and push it on top of the existing stack of menus.
pub fn push(submenu_def: Menu.Definition) void {
    std.debug.assert(submenu_def.kind == .submenu);
    _push(.{ .def = submenu_def });
}
fn _push(submenu: Menu) void {
    stack.appendAssumeCapacity(submenu); // if this errs, just make the buf bigger
    just_opened = 2;
}
pub fn pop() void {
    _ = stack.pop().?;
}

//
// Actual Menus
//

pub const pause_menu = struct {
    pub const top_def = Menu.Definition{
        .kind = .pause,
        .width = 60,
        .items = &.{
            .c("Resume", "menu"),
            .c("Options", "menu"),
            .c("Exit Level", "menu"),
        },
        .callback = .{ .input = .{
            .on_confirm = &topMenuConfirm,
        } },
    };
    fn topMenuConfirm(menu: Menu) Menu.CallbackResult {
        return switch (menu.selection) {
            // Resume
            0 => .close,
            // Options
            1 => .{ .push = Menu{ .def = options_def } },
            // Exit level
            2 => .exit_level,
            else => unreachable,
        };
    }

    const options_def = Menu.Definition{
        .width = 90,
        .items = &.{
            .c("Back", "menu"),
            if (i18n.Lang.count == 1) .empty else .c("Language:", "option"),
            .c("Fullscreen:", "option"),
            .c("Volume:", "option"),
            .t("Keyboard controls"),
            .t("Gamepad controls"),
            .t("Gamepad options"),
        },
        .callback = .{ .input = .{
            .on_confirm = &optionsMenuConfirm,
            .on_left_or_right = &optionsMenuLeftRight,
        } },
        .draw_item = &optionsMenuDraw,
    };
    fn optionsMenuConfirm(menu: Menu) Menu.CallbackResult {
        switch (menu.selection) {
            // Back
            0 => return .pop,
            // Language
            1 => {},
            // Fullscreen
            2 => core.windowing.toggleFullscreen(),
            // Volume
            3 => {},
            // Keyboard controls
            4 => return .{ .push = Menu{ .def = key_controls_def } },
            // Gamepad controls
            5 => return .{ .push = Menu{ .def = pad_controls_def } },
            // Gamepad options
            6 => return .{ .push = Menu{ .def = pad_options_def } },
            else => unreachable,
        }
        return .stay_open;
    }
    fn optionsMenuLeftRight(menu: Menu, is_left: bool, is_repeat: bool) void {
        switch (menu.selection) {
            // Language
            1 => if (!is_repeat) {
                util.enumWrappingAdd(i18n.Lang, &core.lang, if (is_left) -1 else 1);
            },
            // Volume
            3 => {
                var vol = rl.getMasterVolume();
                vol += if (is_left) -0.01 else 0.01;
                rl.setMasterVolume(std.math.clamp(vol, 0, 1));
            },
            else => {},
        }
    }
    fn optionsMenuDraw(menu: Menu, item_idx: usize, cursor: *draw.Cursor) void {
        switch (item_idx) {
            // Language
            1 => {
                cursor.print(" ");
                cursor.printEx(
                    core.lang.name(),
                    .{ .surround_with_arrows_if = menu.selection == 1 },
                );
            },
            // Fullscreen
            2 => {
                cursor.print(" ");
                cursor.printAscii(if (core.windowing.isFullscreen()) "Y" else "N");
            },
            // Volume
            3 => {
                cursor.print(" ");
                var vol_buf: [5]u8 = @splat(0); // "100%" + null
                const vol = std.fmt.bufPrintZ(&vol_buf, "{d}%", .{@floor(rl.getMasterVolume() * 100)}) catch unreachable;
                // If this ends up not looking right in some lang's font, print in ascii.
                cursor.printEx(
                    vol,
                    .{ .surround_with_arrows_if = menu.selection == 3 },
                );
            },
            else => {},
        }
    }

    //
    // Keyboard Controls
    //

    const key_controls_def = Menu.Definition{
        .width = 130,
        .items = capitalized_input_names,
        .callback = .{ .input = .{ .on_confirm = &keyControlsConfirm } },
        .draw_item = &keyControlsDraw,
    };
    fn keyControlsConfirm(_: Menu) Menu.CallbackResult {
        return .{ .push = Menu{ .def = key_remap_def } };
    }
    fn keyControlsDraw(_: Menu, item_idx: usize, item_cursor: *draw.Cursor) void {
        if (item_idx == 0) { // only need to draw this once per frame
            get().?.selection = 0; // a bit hacky: only select the first item

            var top_cursor = getCursorForDrawingAtTheTop();
            top_cursor.printEx("Keyboard controls", .{ .centered = true });
            top_cursor.start_x = text_left_margin;
            top_cursor.row();
            top_cursor.row();
            top_cursor.printAll(&.{
                "Press ",
                @tagName(inputs.inputs_keyboard.get(.confirm)),
                " to remap,",
                "\n",
                "or ",
                @tagName(inputs.inputs_keyboard.get(.cancel)),
                " to cancel",
            }, .{});
        }

        drawKeyControls(false, item_idx, item_cursor, false);
    }

    /// Known bug: pressing DEL to reset an input doesn't check if the default key is already in use,
    /// so it can be used to set two inputs to the same key. But I want you to be able to just mash
    /// DEL to get back to all default keys without it complaining about them already being in use,
    /// so, wontfix. Using the key mapper again forces you to set a different key anyway.
    const key_remap_def = Menu.Definition{
        .width = 130,
        .items = capitalized_input_names,
        .callback = .{ .update = &keyRemapUpdate },
        .draw_item = &keyRemapDraw,
    };
    var old_inputs_keyboard: @TypeOf(inputs.inputs_keyboard) = undefined;
    var key_already_used: rl.KeyboardKey = .null;
    fn keyRemapUpdate(menu: *Menu) Menu.CallbackResult {
        if (just_opened != 0) {
            old_inputs_keyboard = inputs.inputs_keyboard;
            key_already_used = .null;
            return .stay_open;
        }

        // Allow gamepad users to escape purgatory.
        if (inputs._buttonDownOnGamepad(.cancel)) return .pop;

        if (key_already_used != .null) {
            if (inputs.isKeyDown(key_already_used)) return .stay_open;
            key_already_used = .null;
        }
        var key = inputs.normalizeKey(rl.getKeyPressed());
        if (key == .null) return .stay_open;

        const selected_input: inputs.Input = @enumFromInt(menu.selection);
        for (std.enums.values(inputs.Input)) |input| {
            switch (input) {
                // Allow reusing these since the default bindings do anyway.
                .confirm, .cancel => continue,
                else => {},
            }
            if (input != selected_input and inputs.inputs_keyboard.get(input) == key) {
                key_already_used = key;
                return .stay_open;
            }
        }

        switch (key) {
            // Reset this input to default
            .delete => key = inputs.default_inputs_keyboard.get(selected_input),
            // Cancel rebinding
            .escape => {
                inputs.inputs_keyboard = old_inputs_keyboard;
                return .pop;
            },
            // Rebind this input
            else => {},
        }

        inputs.inputs_keyboard.set(selected_input, key);
        menu.selection += 1;
        return if (menu.selection >= menu.def.items.len) .pop else .stay_open;
    }
    fn keyRemapDraw(menu: Menu, item_idx: usize, item_cursor: *draw.Cursor) void {
        if (item_idx == 0) { // only need to draw this once per frame
            var top_cursor = getCursorForDrawingAtTheTop();
            top_cursor.row();
            top_cursor.printEx("Press new key or DEL to reset", .{});
            top_cursor.row();
            top_cursor.print("Press ESC to cancel");

            // while (true) {
            //     const key = rl.getKeyPressed();
            //     if (key == .null) break;
            //     top_cursor.row();
            //     top_cursor.print(@tagName(key));
            // }
        }

        drawKeyControls(menu.selection == item_idx, item_idx, item_cursor, true);
    }

    fn drawKeyControls(item_is_selected: bool, item_idx: usize, cursor: *draw.Cursor, gray_out_unrebindable: bool) void {
        cursor.printAscii(": ");
        const prev_color = cursor.color;
        if (item_is_selected and key_already_used != .null) {
            cursor.color = pico8_colors.red;
            cursor.printAscii("already used");
            cursor.color = prev_color;
            return;
        }

        const item_input: inputs.Input = @enumFromInt(item_idx);
        const key = inputs.inputs_keyboard.get(item_input);
        const key_name = @tagName(key);
        if (item_is_selected and core.t % (core.FRAMES_PER_SEC / 2) < 10) {
            for (0..key_name.len) |_| cursor.printAscii(" ");
        } else {
            if (key_already_used == key) cursor.color = pico8_colors.red;
            cursor.printAscii(key_name);
            cursor.color = prev_color;
        }
        if (gray_out_unrebindable) cursor.color = pico8_colors.light_grey;
        switch (item_input) {
            .confirm => _printAlternateKeys(cursor, &.{ .enter, .space }),
            .cancel => _printAlternateKeys(cursor, &.{.escape}),
            .pause => _printAlternateKeys(cursor, &.{ .p, .escape }),
            else => {},
        }
        cursor.color = prev_color;
    }
    fn _printAlternateKeys(cursor: *draw.Cursor, keys: []const rl.KeyboardKey) void {
        cursor.printAscii(" or ");
        for (keys, 0..) |key, i| {
            if (i > 0) cursor.printAscii("/");
            cursor.printAscii(@tagName(key));
        }
    }

    //
    // Gamepad Controls
    //

    const pad_controls_def = Menu.Definition{
        .width = 130,
        .items = [_]i18n.String{.t("Move")} ++
            [1]i18n.String{.empty} ** 3 ++
            capitalized_input_names[4..],
        .callback = .{ .input = .{ .on_confirm = &padControlsConfirm } },
        .draw_item = &padControlsDraw,
    };
    fn padControlsConfirm(_: Menu) Menu.CallbackResult {
        return .{ .push = Menu{ .def = pad_remap_def } };
    }
    fn padControlsDraw(_: Menu, item_idx: usize, item_cursor: *draw.Cursor) void {
        if (item_idx == 0) { // only need to draw this once per frame
            get().?.selection = 0; // a bit hacky: only select the first item

            var top_cursor = getCursorForDrawingAtTheTop();
            top_cursor.printEx("Gamepad controls", .{ .centered = true });
            top_cursor.start_x = text_left_margin;
            top_cursor.row();
            top_cursor.row();
            top_cursor.printAll(&.{
                "Press ",
                inputs.getBtnName(inputs.inputs_gamepad.get(.confirm)[0]),
                " to remap,",
                "\n",
                "or ",
                inputs.getBtnName(inputs.inputs_gamepad.get(.cancel)[0]),
                " to cancel",
            }, .{});
        }

        drawPadControls(false, item_idx, item_cursor, false);
    }

    const pad_remap_def = Menu.Definition{
        .width = 130,
        .items = [_]i18n.String{.t("Move")} ++
            [1]i18n.String{.empty} ** 3 ++
            capitalized_input_names[4..],
        .callback = .{ .update = &padRemapUpdate },
        .draw_item = &padRemapDraw,
    };
    var old_inputs_gamepad: @TypeOf(inputs.inputs_gamepad) = undefined;
    var btn_already_used: rl.GamepadButton = .unknown;
    var ignore_btn_held: rl.GamepadButton = .unknown;
    fn padRemapUpdate(menu: *Menu) Menu.CallbackResult {
        // Skip unrebindable
        if (menu.selection < 4) menu.selection = 4;
        if (menu.selection == @intFromEnum(inputs.Input.pause)) menu.selection += 1;
        if (menu.selection >= menu.def.items.len) return .pop;

        if (just_opened != 0) {
            old_inputs_gamepad = inputs.inputs_gamepad;
            btn_already_used = .unknown;
            // Unlike keyboard inputs, Raylib seems to return any button that's currently down, not
            // only ones that were just pressed.
            ignore_btn_held = rl.getGamepadButtonPressed();
            return .stay_open;
        }

        // Allow keyboard users to escape purgatory.
        if (inputs._buttonDownOnKeyboard(.cancel)) return .pop;

        if (btn_already_used != .unknown) {
            if (inputs.isGamepadButtonDown(btn_already_used)) return .stay_open;
            btn_already_used = .unknown;
        }
        // Note: Raylib only supports the buttons in the enum, so no L4 or anything. (2026-01-16)
        const btn = rl.getGamepadButtonPressed();
        const should_ignore = btn == ignore_btn_held;
        ignore_btn_held = btn;
        if (btn == .unknown or should_ignore) return .stay_open;

        const selected_input: inputs.Input = @enumFromInt(menu.selection);

        const btn_array: [3]rl.GamepadButton = switch (btn) {
            // Cancel rebinding
            .middle_left => {
                inputs.inputs_gamepad = old_inputs_gamepad;
                return .pop;
            },
            // Reset this input to default
            .middle_right => inputs.default_inputs_gamepad.get(selected_input),
            // Try to rebind this input
            else => blk: {
                // Check for inputs that already use just this button.
                for (std.enums.values(inputs.Input)) |input| {
                    if (input == selected_input) continue;
                    const input_btns = inputs.inputs_gamepad.getPtr(input);
                    var count: u8 = 0;
                    while (count < input_btns.len and input_btns[count] != .unknown) count += 1;
                    std.debug.assert(count > 0);
                    if (count == 1 and input_btns[0] == btn) {
                        btn_already_used = btn;
                        return .stay_open;
                    }
                }
                // Remove the button from inputs that have other buttons.
                for (std.enums.values(inputs.Input)) |input| {
                    if (input == selected_input) continue;
                    const input_btns = inputs.inputs_gamepad.getPtr(input);
                    var count: u8 = 0;
                    while (count < input_btns.len and input_btns[count] != .unknown) count += 1;
                    std.debug.assert(count > 0);
                    if (count > 1) {
                        while (std.mem.indexOfScalar(rl.GamepadButton, input_btns, btn)) |i| {
                            // Ordered remove
                            @memmove(input_btns[i .. input_btns.len - 1], input_btns[i + 1 ..]);
                            input_btns[input_btns.len - 1] = .unknown;
                        }
                    }
                }
                break :blk .{ btn, .unknown, .unknown };
            },
        };

        inputs.inputs_gamepad.set(selected_input, btn_array);
        menu.selection += 1;
        return if (menu.selection >= menu.def.items.len) .pop else .stay_open;
    }
    fn padRemapDraw(menu: Menu, item_idx: usize, item_cursor: *draw.Cursor) void {
        if (item_idx == 0) { // only need to draw this once per frame
            var top_cursor = getCursorForDrawingAtTheTop();
            top_cursor.printAll(&.{
                "\n",
                "Press new button or",
                "\n",
                "  ",
                inputs.getBtnName(.middle_right),
                " to reset",
            }, .{});
            top_cursor.row();
            top_cursor.printAll(&.{
                "Press ",
                inputs.getBtnName(.middle_left),
                " to cancel",
            }, .{});
        }

        drawPadControls(menu.selection == item_idx, item_idx, item_cursor, true);
    }

    fn drawPadControls(item_is_selected: bool, item_idx: usize, cursor: *draw.Cursor, gray_out_unrebindable: bool) void {
        cursor.printAscii(": ");
        const prev_color = cursor.color;
        if (item_is_selected and btn_already_used != .unknown) {
            cursor.color = pico8_colors.red;
            cursor.printAscii("already used");
            cursor.color = prev_color;
            return;
        }

        if (item_idx == 0) {
            // "Move"
            cursor.printAll(
                &.{"D-pad or L-stick"},
                .{
                    .color = if (gray_out_unrebindable) pico8_colors.light_grey else .blank,
                },
            );
            return;
        }

        const item_input: inputs.Input = @enumFromInt(item_idx);
        if (gray_out_unrebindable and item_input == .pause) cursor.color = pico8_colors.light_grey;
        const btns = inputs.inputs_gamepad.get(item_input);
        if (item_is_selected and core.t % (core.FRAMES_PER_SEC / 2) < 10) {
            var btn_list_len: usize = 0;
            for (btns, 0..) |btn, i| {
                if (btn == .unknown) break;
                if (i > 0) btn_list_len += 1; // slashes between btns
                btn_list_len += inputs.getBtnName(btn).len;
            }
            for (0..btn_list_len) |_| cursor.printAscii(" ");
        } else {
            for (btns, 0..) |btn, i| {
                if (btn == .unknown) break;
                if (i > 0) cursor.printAscii("/");
                if (btn_already_used == btn) cursor.color = pico8_colors.red;
                cursor.printAscii(inputs.getBtnName(btn));
                cursor.color = prev_color;
            }
        }
        if (inputs.unrebindable_inputs_gamepad.get(item_input)) |unrebindable_btn| {
            cursor.printAll(
                &.{ " or ", inputs.getBtnName(unrebindable_btn) },
                .{
                    .ascii = true,
                    .color = if (gray_out_unrebindable) pico8_colors.light_grey else .blank,
                },
            );
        }
    }

    const capitalized_input_names: []const i18n.String = blk: {
        const input_names = std.meta.fieldNames(inputs.Input);
        const total_len = util.totalLen(input_names) + input_names.len; // +1 for each null
        var chars_buf = [_]u8{0} ** total_len;
        var chars = std.ArrayList(u8).initBuffer(&chars_buf);
        for (input_names) |input_name| {
            chars.printAssumeCapacity("{c}{s}", .{ std.ascii.toUpper(input_name[0]), input_name[1..] });
            _ = chars.addOneAssumeCapacity(); // null (already zeroed)
        }
        const chars_const = chars_buf;

        var list_buf: [input_names.len]i18n.String = undefined;
        var list = std.ArrayList(i18n.String).initBuffer(&list_buf);
        var chars_idx: usize = 0;
        for (input_names) |input_name| {
            const slice = chars_const[chars_idx .. chars_idx + input_name.len :0];
            list.appendAssumeCapacity(.t(slice));
            chars_idx += input_name.len + 1; // +1 for null
        }
        const list_const = list_buf;

        break :blk &list_const;
    };

    const pad_options_def = Menu.Definition{
        .width = 130,
        .items = &.{
            .c("Back", "menu"),
            .t("Button style:"),
        },
        .callback = .{ .update = &padOptionsUpdate },
        .draw_item = &padOptionsDraw,
    };
    var bad_input: enum { none, x_key, right_face_right } = .none;
    fn padOptionsUpdate(menu: *Menu) Menu.CallbackResult {
        moveSelectorBasedOnInput(menu);

        bad_input = .none;
        if (menu.selection == 1) { // "Button style"
            if (getLeftRightInput()) |lr| {
                if (!lr.is_repeat) {
                    util.enumWrappingAdd(inputs.GamepadLayout, &inputs.gamepad_layout, if (lr.is_left) -1 else 1);
                }
            } else {
                switch (rl.getGamepadButtonPressed()) {
                    .right_face_up => inputs.gamepad_layout = .nintendo,
                    .right_face_left => inputs.gamepad_layout = .microsoft,
                    .right_face_down => inputs.gamepad_layout = .sony,
                    .right_face_right => bad_input = .right_face_right,
                    else => if (rl.isKeyDown(.x)) {
                        bad_input = .x_key;
                    },
                }
            }
            return .stay_open;
        }

        if (inputs.buttonPressed(.cancel, .{})) return .pop;
        if (inputs.buttonPressed(.confirm, .{})) {
            switch (menu.selection) {
                // Back
                0 => return .pop,
                // Button style
                1 => unreachable,
                else => unreachable,
            }
        }
        return .stay_open;
    }
    fn padOptionsDraw(menu: Menu, item_idx: usize, cursor: *draw.Cursor) void {
        switch (item_idx) {
            // Button style
            1 => {
                var top_cursor = getCursorForDrawingAtTheTop();
                if (menu.selection == 1) top_cursor.printEx("Press X to auto detect.", .{ .centered = true });
                cursor.print(" ");
                switch (bad_input) {
                    .none, .x_key => {
                        cursor.printEx(switch (inputs.gamepad_layout) {
                            .microsoft => "Xbox",
                            .nintendo => "Nintendo",
                            .sony => "PlayStation",
                        }, .{
                            .ascii = true,
                            .surround_with_arrows_if = menu.selection == 1,
                        });
                    },
                    .right_face_right => {
                        cursor.printEx(
                            "unknown layout",
                            .{ .color = pico8_colors.red },
                        );
                    },
                }
                if (bad_input == .x_key) {
                    top_cursor.row();
                    top_cursor.printEx(
                        "X on the controller, dummy.",
                        .{ .color = pico8_colors.red, .centered = true },
                    );
                }
            },
            else => {},
        }
    }

    fn getCursorForDrawingAtTheTop() draw.Cursor {
        return .{
            .lang = .en,
            .y = 2,
            .color = pico8_colors.white,
            .effect = .{ .kind = .{ .thick_outline = pico8_colors.black }, .scale = 2 },
            .text_scale = 2,
            .start_x = text_left_margin,
            .x = text_left_margin,
        };
    }
    const text_left_margin = 4;
};
