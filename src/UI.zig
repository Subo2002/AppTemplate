const std = @import("std");
const Allocator = std.mem.Allocator;
const UIHandler = @import("UIHandler.zig");
const Box = UIHandler.Box;
const Cntx = UIHandler.Cntx;
const Lib = @import("lib.zig");
const Vector2U16 = Lib.Vector2U16;
const TextHandler = @import("TextHandler.zig");
const Render = @import("Render.zig").Render;

pub const UI = @This();

pub const TaskKind = enum {};

pub const Task = union(TaskKind) {};

pub const CtxFlags = packed struct {
    invalid: bool = false,
    data: DataFlags = .{},
};

pub const DataFlags = packed struct {
    _x: bool = false,
    _y: bool = false,
    _w: bool = false,
    _h: bool = false,

    pub const x: DataFlags = .{ ._x = true };
    pub const y: DataFlags = .{ ._y = true };
    pub const w: DataFlags = .{ ._w = true };
    pub const h: DataFlags = .{ ._h = true };
    pub const pos: DataFlags = .{ ._x = true, ._y = true };
    pub const size: DataFlags = .{ ._w = true, ._h = true };
    pub const box: DataFlags = .{ ._x = true, ._y = true, ._w = true, ._h = true };
};

pub const MUIImpl = struct {
    S: type,
    set_size: ?fn(),
};

//(Function) Monad UI
//MUI = T -> MUI, where MUI(void) = UI, basically thinking of UI as a monad where it can be a function from T to the UI, thinking like that though that returned UI
//could be a functional UI
pub fn MUI(T: type, impl: MUIImpl) type {
    return struct {
        const This = @This();

        data: *UIHandler,
        root: This,
        flags: CtxFlags,
        tasks: std.ArrayList(Task),

        pub fn initBox(ui: *UIHandler) !This {
            return .{
                .data = ui,
                .root = try ui.initCtx(),
                .flags = .{},
            };
        }

        pub fn setSize(self: MUI, size: Vector2U16) This {
            if (!set_size) @compileError("No setSize");

            //set the size, create new context ref that has the size flags popped off
        }

        pub fn setBox(self: This, box: Box) This {

        }

        //
        pub fn curry(self: This, U: type, inc: fn(U) T) MUI(U, MUI(T, S)) {

        }

        //can take any
        pub fn pad(self: This, padding: Box) This {
            self
        }

        //should only take pos -> ui
        pub fn append(self: This) void {

        }
    };
};

pub fn init(text_handler: *TextHandler, text_info: TextHandler.TextInfo, allc: Allocator, renderer: *Render, window_size: Vector2U16) !void {
    _ = text_handler;

    const Blah = MUI(null, null, false);

    const box_to_window = try Blah.initBox(allc);
    window = box_to_window.setbox(.init(0, 0, @intCast(window_size.x), @intCast(window_size.y)));

    //doesn't actually handle text rendering yet, so just grabbing the size atm
    const text = "dog";
    const glyphs = try TextHandler.compGlyphs(text_info.ttf, allc, text);
    defer allc.free(glyphs);
    const size = TextHandler.compTextLength(text_info, glyphs);
    const box_to_text = try .initBox(allc);
    const pos_to_text = box_to_text.setSize(.init(size, text_info.pixel_height));
    const pos_to_padded_text = pos_to_text.pad();
    window.append(pos_to_padded_text);

    //This is still todo
    const ui_render_data: []UIHandler.UIRenderData = window.renderCtxs(allc);
    defer allc.free(ui_render_data);
    renderer.renderUI(ui_render_data);
}

const text_padding: Box = .init(8, 8, 16, 16);
