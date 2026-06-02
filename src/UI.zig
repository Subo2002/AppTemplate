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

pub fn init(text_handler: *TextHandler, text_info: TextHandler.TextInfo, allc: Allocator, renderer: *Render, window_size: Vector2U16) !void {
    _ = text_handler;

    var ui: UIHandler = .empty;
    //Ctx is a handle to the ui context inside UIHandler
    //But it also contains flags for whether a certain piece of data of the ui context still needs to be handled by the user
    //i.e. before an explicit value is needed for rendering, input detection, the ui actually existing any way.
    //Handling it can mean it's set by the user like in setbox, setsize, or appendCtx. Or it can mean making it's final calculation a task that depends
    //on the data of another ctx, where the handling of set_whatever is passed in to that new ctx. For example padded_text_ctx will take the x, y, w, or h,
    //fields of a ctxs box and make them depend on the padding ctx's x, y, w, or h respectivley with a task that offsets according to the given a padding.
    //and so the responsability of setting x, y, w, or h in that scenario is passed along to the padded_ctx rather than the original ctx.
    var window_ctx: UIHandler.Ctx = try ui.initCtx(allc);
    ui.setbox(window_ctx.pop(.box), .init(0, 0, @intCast(window_size.x), @intCast(window_size.y)));

    //doesn't actually handle text rendering yet, so just grabbing the size atm
    const text = "dog";
    const glyphs = try  TextHandler.compGlyphs(text_info.ttf, allc, text);
    defer allc.free(glyphs);
    const size = TextHandler.compTextLength(text_info, glyphs);
    var text_ctx = ui.initCtx(allc) catch unreachable;
    ui.setsize(text_ctx, .init(size, text_info.pixel_height));
    var padded_text_ctx = ui.padCtx(allc, text_ctx.pop(.pos), text_padding) catch unreachable;
    ui.appendCtx(window_ctx, padded_text_ctx.pop(.pos));

    //This is still todo
    const ui_render_data: []UIHandler.UIRenderData = ui.renderCtxs(allc);
    defer allc.free(ui_render_data);
    renderer.renderUI(ui_render_data);
}

const text_padding: Box = .init(8, 8, 16, 16);