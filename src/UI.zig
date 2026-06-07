const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const UIHandler = @import("UIHandler.zig");
const Box = UIHandler.Box;
const Cntx = UIHandler.Cntx;
const Lib = @import("lib.zig");
const Vector2U16 = Lib.Vector2U16;
const TextHandler = @import("TextHandler.zig");
const Render = @import("Render.zig").Render;

pub const TaskKind = enum {
    box_as_pos_to_size,
};

pub const Task = union(TaskKind) {};

pub const DomainKind = enum {
    empty = @bitCast(DataFlags{}),
    x = @bitCast(DataFlags{ .x = true }),
    y = @bitCast(DataFlags{ .y = true }),
    w = @bitCast(DataFlags{ .w = true }),
    h = @bitCast(DataFlags{ .h = true }),
    pos = @bitCast(DataFlags{ .x = true, .y = true }),
    size = @bitCast(DataFlags{ .w = true, .h = true }),
    box = @bitCast(DataFlags{ .x = true, .y = true, .w = true, .h = true }),

    pub const DomainType: std.EnumArray(DomainKind, type) = .init(.{
        .box = Box,
        .pos = Vector2U16,
        .size = VectorU16,
        .x = u16,
        .y = u16,
        .w = u16,
        .h = u16,
    });
};

pub const CtxFlags = packed struct {
    invalid: bool = false,
    data: DataFlags = .{},
};

pub const DataFlags = packed struct {
    x: bool = false,
    y: bool = false,
    w: bool = false,
    h: bool = false,

    pub fn contains(self: DataFlags, other: DataFlags) bool {
        return (self.x or !other.x) and
            (self.y or !other.y) and
            (self.w or !other.w) and
            (self.h or !other.h);
    }

    pub fn diff(self: DataFlags, other: DataFlags) DataFlags {
        std.debug.assert(self.contains(other));
        return .{
            .x = self.x and !other.x,
            .y = self.y and !other.y,
            .w = self.w and !other.w,
            .h = self.h and !other.h,
        };
    }

    pub fn diffType(T: type, other: DataFlags) type {
        return fromType(T).diff(other).Type();
    }

    pub fn fromType(type: Type) DataFlags {
        //TODO
    }

    pub fn Type(self: DataFlags) type {
        return DomainKind.DomainType.get(@bitCast(self));
    }
};

pub const BaseUI = struct {
    data: *UIHandler,
    root: Cntx,
    fn_stack: std.ArrayList(Task),

    pub fn callFnStack(self: *const BaseUI) BaseUI {
        while (self.fn_stack.pop()) |task| {
            switch (task) {
                inline else => |t| t.do(self.data),
            }
        }
        return self.*;
    }
};

pub const UI = struct {
    base: BaseUI,

    pub fn append(self: UI, child: PosUI) UI {}

    pub fn render(self: UI, allc: Allocator) []UIHandler.UIRenderData {}
};

pub const BoxUI = struct {
    base: BaseUI,

    pub fn init(ui_ctx: *UIHandler, allc: Allocator) !BoxUI {
        const root = try ui_ctx.initCtx(allc);
        const ui: BoxUI = .{ .base = .{
            .data = ui_ctx,
            .root = root,
            .fn_stack = .empty,
        } };
        return ui;
    }

    pub fn setBox(self: BoxUI, box: Box) UI {
        const flags = self.base.data.getFlags(self.base.root);
        assert(!flags.x_set and !flags.y_set and !flags.w_set and !flags.h_set);
        const box_ptr = self.base.data.getbox(self.base.root);
        box_ptr.* = box;
        flags.x_set = true;
        flags.y_set = true;
        flags.w_set = true;
        flags.h_set = true;
        return self.base.callFnStack();
    }

    pub fn initSet(ui_ctx: *UIHandler, allc: Allocator, box: Box) !UI {
        const box_ui: BoxUI = try .init(ui_ctx, allc);
        return box_ui.setBox(box);
    }

    pub fn setSize(self: BoxUI, size: Vector2U16) PosUI {}

    pub fn setPos(self: BoxUI, pos: Vector2U16) SizeUI {}

    pub fn pad(self: BoxUI, padding: Box) BoxUI {}
};

pub const PosUI = struct {
    base: BaseUI,

    pub fn pad(self: PosUI, allc: Allocator, padding: Box) PosUI {}
};

pub const SizeUI = struct {
    base: BaseUI,

    pub fn pad(self: SizeUI, allc: Allocator, padding: Box) PosUI {}
};

pub const Example = struct {
    pub fn init(text_handler: *TextHandler, text_info: TextHandler.TextInfo, allc: Allocator, renderer: *Render, window_size: Vector2U16) !void {
        _ = text_handler;

        const ui_ctx: UIHandler = .empty;
        const window = try BoxUI.initSet(
            ui_ctx,
            allc,
            .init(0, 0, @intCast(window_size.x), @intCast(window_size.y)),
        );

        //doesn't actually handle text rendering yet, so just grabbing the size atm
        const text = "dog";
        const glyphs = try TextHandler.compGlyphs(text_info.ttf, allc, text);
        defer allc.free(glyphs);
        const size = TextHandler.compTextLength(text_info, glyphs);
        const box_to_text = try BoxUI.init(ui_ctx, allc);
        const pos_to_text = box_to_text.setSize(.init(size, text_info.pixel_height));
        const pos_to_padded_text = pos_to_text.pad();
        const ui = window.append(pos_to_padded_text);

        //This is still todo
        const ui_render_data = ui.render(allc);
        defer allc.free(ui_render_data);
        renderer.renderUI(ui_render_data);
    }

    const text_padding: Box = .init(8, 8, 16, 16);
};
