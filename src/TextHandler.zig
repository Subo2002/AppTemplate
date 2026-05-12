const TrueType = @import("TrueType");
const GlyphIndex = TrueType.GlyphIndex;

const std = @import("std");
const Allocator = std.mem.Allocator;

const GraphicsLib = @import("Graphics.zig");
const ImageRef = GraphicsLib.ImageRef;

const TextureAtlas = @import("TextureAtlas.zig");

const Render = @import("Render.zig").Render;

pub const TextHandler = @This();

pub const GlyphTextureID = struct {
    glyph: GlyphIndex,
    scale: f32,

    pub fn init(glyph: GlyphIndex, scale: f32) GlyphTextureID {
        return .{ .glyph = glyph, .scale = scale };
    }
};

glyph_textures: std.AutoHashMapUnmanaged(GlyphIndex, ImageRef),

pub fn compGlyphs(self: *TextHandler, ttf: TrueType, gpa: Allocator, text: []const u8) ![]const GlyphIndex {
    const it = (try std.unicode.Utf8View.init(text)).iterator();
    _ = self;
    var glyphs: std.ArrayListUnmanaged(GlyphIndex) = .empty;
    while (it.nextCodepoint()) |codepoint| {
        try glyphs.append(gpa, ttf.codepointGlyphIndex(codepoint));
    }
    try glyphs.shrinkToLen(gpa);
    return glyphs.toOwnedSliceAssert(gpa);
}

pub fn compAndAddNewGlyphImages(self: *TextHandler, self_glyph_tex_map_allc: Allocator, ttf: TrueType, scale: f32, glyphs: []const GlyphIndex, arena: *std.heap.ArenaAllocator, atlas_allc: Allocator, atlas: *TextureAtlas, set_to_render: bool) void {
    for (glyphs) |glyph| {
        const glyph_tex_id: GlyphTextureID = .init(glyph, scale);
        if (self.glyph_textures.contains(glyph_tex_id)) continue;
        var bitmap: std.ArrayListUnmanaged(u8) = .empty;
        defer arena.reset(.free_all);
        const dims = ttf.glyphBitmap(arena.allocator(), &bitmap, glyph, scale, scale);
        const pixels = bitmap.items;
        const image, const image_id = try atlas.createImage(atlas_allc, dims.width, dims.height);
        for (0..dims.height) |y| {
            for (0..dims.width) |x| {
                const index = y * dims.width + x;
                const alpha = pixels[index];
                image[index] = .init(alpha, alpha, alpha, alpha);
            }
        }
        try self.glyph_textures.put(self_glyph_tex_map_allc, glyph_tex_id, image_id);
        if (set_to_render) atlas.renderImage(image_id);
    }
}

pub const GlyphImagesFormat = enum {
    fixed_scale,
    arbitrary_scales,
};

pub const GlyphImages = union(GlyphImagesFormat) {
    fixed_scale: .{ f32, []const GlyphIndex },
    arbitrary_scales: .{ []const f32, []const GlyphIndex },
};

pub fn addGlyphsImagesToRender(self: *TextHandler, glyph_images: GlyphImages, atlas: *TextureAtlas) void {
    const glyphs = switch (glyph_images) {
        .fixed_scale => |_, glyphs| glyphs,
        .arbitrary_scales => |_, glyphs| glyphs,
    };
    for (glyphs, 0..) |glyph, index| {
        const scale = switch (glyph_images) {
            .fixed_scale => |s| s,
            .arbitrary_scales => |ss| ss[index],
        };
        const glyph_image = self.glyph_textures.get(.init(glyph, scale)).?;
        if (!atlas.flags[glyph_image.ref].rendered) continue;
        atlas.renderImage();
    }
}
