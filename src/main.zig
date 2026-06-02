const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const TrueType = @import("TrueType");
const zglfw = @import("zglfw");
const Window = zglfw.Window;
const stbi = @import("zstbi");
const Lib = @import("lib.zig");
const Vector2I32 = Lib.Vector2I32;
const Vector2 = @import("ZSMath").Vector2;
//const GraphicsLib = @import("Graphics.zig");

const Render = @import("Render.zig").Render;
const TextureAtlas = @import("TextureAtlas.zig");
const TextHandler = @import("TextHandler.zig");
const UIHandler = @import("UIHandler.zig");
const UI = @import("UI.zig");

pub const State = struct {
    render: Render,
    atlas: TextureAtlas,
    text: TextHandler,
    uih: UIHandler,
    ui: UI,

    pub fn init(state: *State, allc: Allocator, window: *Window, text_info: TextHandler.TextInfo) !void {
        try state.render.init(allc, window, TextureAtlas.atlas_size);
        state.atlas.init();
        state.text.init();
        state.uih = .empty;
        try UI.init(
            &state.text,
            text_info,
            allc,
            &state.render,
            .init(@intCast(window.getSize()[0]), @intCast(window.getSize()[1])),
        );
    }

    pub fn deinit(state: *State, allc: Allocator) void {
        state.render.deinit(allc);
        state.atlas.deinit(allc);
        state.text.deinit(allc);
    }
};

var _state: State = undefined;
var _buffer: [4096]u8 = undefined;
pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;

    try zglfw.init();
    defer zglfw.terminate();

    const window = try zglfw.createWindow(1600, 800, "App Template", null, null);
    defer window.destroy();
    zglfw.makeContextCurrent(window);

    stbi.init(io, arena);
    defer stbi.deinit();

    const ttf = try TrueType.load(@embedFile("Mistral.ttf"));
    const scale_up = 4;
    const text_pixel_height = 24;
    const text_info: TextHandler.TextInfo = .init(ttf, text_pixel_height, scale_up);

    const example_string = "dog";

    const state = &_state;
    try state.init(init.gpa, window, text_info);
    defer state.deinit(init.gpa);

    const glyphs = try state.text.compGlyphs(ttf, init.gpa, example_string);
    defer init.gpa.free(glyphs);
    try state.text.compAndAddNewGlyphImages(init.gpa, ttf, UI.text_pixel_height * scale_up, glyphs, init.arena, init.gpa, &state.atlas, true);
    try state.atlas.uploadImages(&state.render);
    while (!window.shouldClose()) {
        zglfw.pollEvents();
        state.text.renderText(&state.render, .init(0, 100), .init(ttf, UI.text_pixel_height, scale_up), .black, glyphs);
        draw(state);
    }
}

pub fn draw(state: *State) void {
    state.render.draw();
}
