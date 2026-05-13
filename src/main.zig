const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const TrueType = @import("TrueType");

const zglfw = @import("zglfw");
const Window = zglfw.Window;

const zgpu = @import("zgpu");

const Render = @import("Render.zig").Render;

const GraphicsLib = @import("Graphics.zig");
const Image = GraphicsLib.Image;

const TextureAtlasLib = @import("TextureAtlas.zig");
const TextureAtlas = TextureAtlasLib.TextureAtlas;

const stbi = @import("zstbi");

const Lib = @import("lib.zig");
const Vector2I32 = Lib.Vector2I32;
const Vector2 = @import("ZSMath").Vector2;

const TextHandler = @import("TextHandler.zig");

pub const State = struct {
    render: Render,
    atlas: TextureAtlas,
    text: TextHandler,

    pub fn init(state: *State, allc: Allocator, window: *Window) !void {
        try state.render.init(allc, window, TextureAtlas.atlas_size);
        state.atlas.init();
        state.text.init();
    }

    pub fn deinit(state: *State, allc: Allocator) void {
        state.render.deinit(allc);
        state.atlas.deinit(allc);
        state.text.deinit(allc);
    }
};

//use program memory instead of heap or stack
//var _state: State = undefined;
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

    const state = try init.gpa.create(State);
    defer init.gpa.destroy(state);
    try state.init(init.gpa, window);
    defer state.deinit(init.gpa);

    const ttf = try TrueType.load(@embedFile("Mistral.ttf"));
    const example_string = "dog";
    const pixel_height = 24 * 4;

    const glyphs = try state.text.compGlyphs(ttf, init.gpa, example_string);
    defer init.gpa.free(glyphs);
    try state.text.compAndAddNewGlyphImages(init.gpa, ttf, pixel_height, glyphs, init.arena, init.gpa, &state.atlas, true);
    try state.atlas.uploadImages(&state.render);
    while (!window.shouldClose()) {
        zglfw.pollEvents();
        state.text.renderText(&state.render, .init(0, 100), ttf, pixel_height, .black, glyphs);
        draw(state);
    }
}

pub fn draw(state: *State) void {
    state.render.draw();
    state.render.no_instances = 0;
}
