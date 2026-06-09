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
const Task = UIHandler.Task;

//{Thing}UI means the UI is a function of Thing returning a UI

//The ones implemented below though are a bit more specific as they
// take Thing to be a field of the root ctx
//and also the fn_stack is not taking the data and passing the output to the next fn and so on (i.e. not recusrive-ish)
//but rather are more like the effects explicitizing monadic/maybe-ish values of the ui contexts

//maybe make the fn_stack an intrusive hierarchical linked list, then can just put it in UIHandler as well

pub const BaseUI = struct {
    data: *UIHandler,
    root: Cntx,
    fn_stack: std.ArrayList(UIHandler.Task),

    pub fn callFnStack(self: *const BaseUI) BaseUI {
        while (self.fn_stack.pop()) |task| {
            switch (task) {
                inline else => |t| t.do(self.data),
            }
        }
        return self.*;
    }
};

pub const ChildUI = struct {
    base: BaseUI,

    //want to be able to run this on things that don't have all their data set yet
    //PROBLEM: way too many possible {}UI types. Probably need to return to the pop/push system for responsabilities

    //Needs to be a wrapper context, so it keeps track of the childs height, and that context represents a row
    //and it fails if it doesn't fit in that row (fixed width i guess, or there is need for a max/min flag instead of init)

    //WRONG, this needs to be having y_first = self_box.y, i.e. aligned to parent.
    pub fn append(self: ChildUI, child: PosUI) !ChildUI {
        assert(self.base.data == child.base.data);
        const ctx = self.base.data;
        const self_links = ctx.getLinks(self.base.root);
        const first_child = ctx.getLinks(self_links.child);
        const last_child_box = ctx.getbox(first_child.prevSib);
        const last_child_flags = ctx.getFlags(first_child.prevSib);
        assert(last_child_flags.x and last_child_flags.y and last_child_flags.w and last_child_flags.h);
        const child_box = ctx.getbox(child.base.root);
        const x_first = last_child_box.x + last_child_box.w;
        const y_first = last_child_box.y + last_child_box.h;
        const child_flags = ctx.getFlags(child.base.root);
        const child_w = switch (child_flags.w) {
            .empty => 0,
            .init => child_box.w,
            .set => child_box.w,
        };
        const child_h = switch (child_flags.h) {
            .empty => 0,
            .init => child_box.h,
            .set => child_box.h,
        };
        const self_box = ctx.getbox(self.base.root);

        //STILL NEED TO DO THE FN COMPS

        if (x_first + child_w >= self_box.w) return error.childGoesOffEdge;
        if (y_first + child_h >= self_box.h) return error.childGoesOffBottom;

        //Actually do the stuff now
        child_box.x = x_first;
        child_box.y = y_first;

        ctx.linkCntxs(self.base.root, child.base.root);

        child.base.callFnStack();

        return self;
    }
};

pub const UI = struct {
    base: BaseUI,

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
        assert(!flags.x and !flags.y and !flags.w and !flags.h);
        const box_ptr = self.base.data.getbox(self.base.root);
        box_ptr.* = box;
        flags.x = true;
        flags.y = true;
        flags.w = true;
        flags.h = true;
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

pub const XUI = struct {
    base: BaseUI,

    pub fn pad(self: XUI, allc: Allocator, padding: Box) XUI {
        const padding_ctx = try self.base.data.initCtx();
        const padding_box = self.base.data.getbox(padding_ctx);
        const self_box: *const Box = self.base.data.getbox(self.base.root);
        const flags: *const UIHandler.Flags = self.base.data.getFlags(self.base.root);
        assert(!flags.x and flags.y and flags.w and flags.h);
        self.base.fn_stack.append(allc, .{ .offset_x = .init(self.base.root, padding_ctx, -padding.x) });
        padding_box.y = self_box.y + padding.y;
        padding_box.w = self_box.w + padding.w;
        padding_box.h = self_box.h + padding.h;
    }
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
