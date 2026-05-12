const GraphicsLib = @import("Graphics.zig");
const Image = GraphicsLib.Image;

const Lib = @import("lib.zig");
const Vector2U16 = Lib.Vector2U16;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const TextureAtlas = struct {
    pub const atlas_size: Vector2U16 = .init(2048, 2048);
    pub const max_no_images = 100;

    images: [max_no_images]Image,
    image_count: usize,

    pub fn init(self: *TextureAtlas) void {
        self.image_count = 1;
    }

    pub fn deinit(self: *TextureAtlas, allc: Allocator) void {
        for (self.images[1..self.image_count]) |image| {
            allc.free(image.data);
        }
    }

    pub fn createImage(self: *TextureAtlas, allc: Allocator, width: u32, height: u32) !Image {
        const image: Image = try .createRaw(allc, width, height);
        self.images[self.image_count] = image;
        self.image_count += 1;
        return image;
    }
};
