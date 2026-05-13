const TrueType = @import("TrueType");
const GlyphIndex = TrueType.GlyphIndex;

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const GraphicsLib = @import("Graphics.zig");
const ImageRef = GraphicsLib.ImageRef;
const Color = GraphicsLib.Color;

const TextureAtlas = @import("TextureAtlas.zig");

const Render = @import("Render.zig").Render;

const Lib = @import("lib.zig");
const Vector2I32 = Lib.Vector2I32;

pub const TextHandler = @This();

pub const GlyphTextureID = struct {
    glyph: GlyphIndex,
    pixel_height: u16,

    pub fn init(glyph: GlyphIndex, pixel_height: u16) GlyphTextureID {
        return .{ .glyph = glyph, .pixel_height = pixel_height };
    }
};

glyph_textures: std.AutoHashMapUnmanaged(GlyphTextureID, ImageRef),

pub fn init(self: *TextHandler) void {
    self.glyph_textures = .empty;
}

pub fn deinit(self: *TextHandler, allc: Allocator) void {
    self.glyph_textures.deinit(allc);
}

pub fn compGlyphs(self: *TextHandler, ttf: TrueType, gpa: Allocator, text: []const u8) ![]const GlyphIndex {
    var it = (try std.unicode.Utf8View.init(text)).iterator();
    _ = self;
    var glyphs: std.ArrayListUnmanaged(GlyphIndex) = .empty;
    while (it.nextCodepoint()) |codepoint| {
        try glyphs.append(gpa, ttf.codepointGlyphIndex(codepoint));
    }
    try glyphs.shrinkToLen(gpa);
    return glyphs.toOwnedSliceAssert();
}

pub fn compAndAddNewGlyphImages(self: *TextHandler, self_glyph_tex_map_allc: Allocator, ttf: TrueType, pixel_height: u16, glyphs: []const GlyphIndex, arena: *std.heap.ArenaAllocator, atlas_allc: Allocator, atlas: *TextureAtlas, set_to_render: bool) !void {
    const scale = ttf.scaleForPixelHeight(pixel_height);
    for (glyphs) |glyph| {
        const glyph_tex_id: GlyphTextureID = .init(glyph, pixel_height);
        if (self.glyph_textures.contains(glyph_tex_id)) continue;
        var bitmap: std.ArrayListUnmanaged(u8) = .empty;
        defer assert(arena.reset(.free_all));
        const dims = try ttf.glyphBitmap(arena.allocator(), &bitmap, glyph, scale, scale);
        const pixels = bitmap.items;
        const image, const image_id = try atlas.createImage(atlas_allc, dims.width, dims.height);
        for (0..dims.height) |y| {
            for (0..dims.width) |x| {
                const index = y * dims.width + x;
                const alpha = pixels[index];
                image.data[index] = .init(alpha, alpha, alpha, alpha);
            }
        }
        try self.glyph_textures.put(self_glyph_tex_map_allc, glyph_tex_id, image_id);
        if (set_to_render) atlas.renderImage(image_id);
    }
}

pub const GlyphImagesFormat = enum {
    fixed_height,
    arbitrary_heights,
};

pub const GlyphImages = union(GlyphImagesFormat) {
    fixed_height: .{ u16, []const GlyphIndex },
    arbitrary_heights: .{ []const u16, []const GlyphIndex },
};
//TODO: should make in to GlyphHeights, instead of dragging the glyphs index in to it as well
pub fn addGlyphsImagesToRender(self: *TextHandler, glyph_images: GlyphImages, atlas: *TextureAtlas) void {
    const glyphs = switch (glyph_images) {
        .fixed_height => |_, glyphs| glyphs,
        .arbitrary_height => |_, glyphs| glyphs,
    };
    for (glyphs, 0..) |glyph, index| {
        const pixel_height = switch (glyph_images) {
            .fixed_height => |ph| ph,
            .arbitrary_height => |phs| phs[index],
        };
        const glyph_image = self.glyph_textures.get(.init(glyph, pixel_height)).?;
        if (!atlas.flags[glyph_image.ref].rendered) continue;
        atlas.renderImage();
    }
}

pub fn renderText(self: *TextHandler, render: *Render, pos: Vector2I32, ttf: TrueType, pixel_height: u16, color: Color, glyphs: []const GlyphIndex) void {
    var write_pos: f32 = 0;
    var last_glyph: ?GlyphIndex = null;
    const scale = ttf.scaleForPixelHeight(pixel_height);
    for (glyphs) |glyph| {
        defer last_glyph = glyph;
        const data = ttf.glyphHMetrics(glyph);
        const kern = if (last_glyph) |lg| ttf.glyphKernAdvance(lg, glyph) * scale else 0;
        const box = ttf.glyphBitmapBox(glyph, scale, scale);
        const y1 = @as(f32, @floatFromInt(box.y1));
        const x1 = @as(f32, @floatFromInt(box.x1));
        const y0 = @as(f32, @floatFromInt(box.y0));
        const x0 = @as(f32, @floatFromInt(box.x0));

        write_pos += kern;
        std.log.debug("tex: {}, width: {}, height: {}, x: {}, y: {}", .{
            self.glyph_textures.get(.init(glyph, pixel_height)).?.ref,
            (x1 - x0) / 4,
            (y1 - y0) / 4,
            pos.toFloat().x + (write_pos + x0) / 4,
            pos.toFloat().y + y0 / 4,
            //color,
        });
        _ = render.addInstance(.{
            .tex = self.glyph_textures.get(.init(glyph, pixel_height)).?.ref,
            .dims = .init((x1 - x0) / 4, (y1 - y0) / 4),
            .pos = pos.toFloat().add(.init((write_pos + x0) / 4, y0 / 4)),
            .col = color,
        });
        write_pos += data.advance_width * scale;
    }
}
