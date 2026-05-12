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

pub const State = struct {
    gfx: Render,
    atlas: TextureAtlas,

    pub fn init(state: *State, allc: Allocator, window: *Window) !void {
        try state.gfx.init(allc, window, TextureAtlas.atlas_size);
        state.atlas.init();
    }

    pub fn deinit(state: *State, allc: Allocator) void {
        state.gfx.deinit(allc);
        state.atlas.deinit(allc);
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
    const scale = ttf.scaleForPixelHeight(24 * 4);

    //var buf: [1024]u8 = undefined;
    //const stdout_writer = std.Io.File.stdout().writer(io, &buf);
    //const stdout = stdout_writer.interface;

    var buffer: std.ArrayListUnmanaged(u8) = .empty;
    defer buffer.deinit(init.gpa);

    var it = std.unicode.Utf8View.initComptime(example_string).iterator();
    var i: u32 = @intCast(state.atlas.image_count);
    var atlas_pos: Vector2I32 = .zero;
    var write_pos: f32 = 0;
    var last_glyph: TrueType.GlyphIndex = .notdef;
    const text_color: GraphicsLib.Color = .black;

    const tcr = @as(f32, @floatFromInt(text_color.r)) / 255;
    const tcg = @as(f32, @floatFromInt(text_color.g)) / 255;
    const tcb = @as(f32, @floatFromInt(text_color.b)) / 255;
    while (it.nextCodepoint()) |codepoint| {
        const glyph = ttf.codepointGlyphIndex(codepoint);
        defer last_glyph = glyph;
        if (glyph == .notdef) {
            continue;
        }
        defer i += 1;
        buffer.clearRetainingCapacity();
        const dims = try ttf.glyphBitmap(init.gpa, &buffer, glyph, scale, scale);
        const pixels = buffer.items;
        const image = try state.atlas.createImage(init.gpa, dims.width, dims.height);
        for (0..dims.height) |y| {
            for (0..dims.width) |x| {
                const color = pixels[y * dims.width + x];
                const c = @as(f32, @floatFromInt(color)) / 255;
                image.data[y * dims.width + x] = .init(@intFromFloat(255 * tcr * c), @intFromFloat(255 * tcg * c), @intFromFloat(255 * tcb * c), color);
            }
        }
        state.gfx.uploads_data[state.gfx.upload.no] = .{
            .image_ref = .init(i),
            .atlas_ref = .{
                .size = .init(dims.width, dims.height),
                .pos = atlas_pos,
            },
        };
        std.log.debug("asking to add image {}", .{i});
        state.gfx.upload.no += 1;
        const data = ttf.glyphHMetrics(glyph);
        const kern = ttf.glyphKernAdvance(last_glyph, glyph) * scale;
        const box = ttf.glyphBitmapBox(glyph, scale, scale);
        const y1 = @as(f32, @floatFromInt(box.y1));
        _ = y1;
        const y_off = @as(f32, @floatFromInt(box.y0));
        const x_off = @as(f32, @floatFromInt(box.x0));

        write_pos += kern;
        _ = state.gfx.addInstance(.{
            .tex = i,
            .dims = .init(@as(f32, @floatFromInt(dims.width)) / 4, @as(f32, @floatFromInt(dims.height)) / 4),
            .pos = Vector2.init(0, 100).add(Vector2.init((write_pos + x_off) / 4, (y_off) / 4)),
        });
        write_pos += data.advance_width * scale;
        atlas_pos.x += @intCast(image.width);
    }

    while (!window.shouldClose()) {
        zglfw.pollEvents();
        draw(state);
    }
}

pub fn draw(state: *State) void {
    state.gfx.draw(state.atlas.images[0..state.atlas.image_count]);
    state.gfx.no_instances = 0;
    state.gfx.upload.no = 0;
    state.gfx.upload.size = 0;
}
