const GraphicsLib = @import("Graphics.zig");
const Image = GraphicsLib.Image;
const ImageRef = GraphicsLib.ImageRef;

const Lib = @import("lib.zig");
const Vector2U16 = Lib.Vector2U16;

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const Render = @import("Render.zig").Render;

pub const TextureAtlas = @This();

pub const atlas_size: Vector2U16 = .init(2048, 2048);
pub const max_no_images = 100;

pub const Flags = packed struct {
    free: bool,
    render: bool,
    rendered: bool,
};

//TODO:
// 1. add images_to_upload struct instead of flags approach, but keep render, and rendered field, so can know if image is in use on the gpu and if it's on the gpu
// 2. move the texture atlas writing stuff in to here from render
// 3. write uploadImages, which just sorts them by height and adds them to the buffer,
// 4. ...no page stuff, and if it's full wipe the gpu atlas and upload all the needed textures. Kind of arena style
// 5. write printLine method
// 6. replace all the logic in main with this new stuff, will basically be empty again
// 7. start ui
// 8. want a centered title context
// 9. want button
// 10. want to be able to input numbers, and text
// 11. want a screen division that is moveable
// 12. want a draggable and placeable item
// 13. want to be able to shrink and resize the window and all be nice

images: [max_no_images]Image,
flags: [max_no_images]Flags,
image_count: usize,
image_limit: usize,
atlas_ptr: Vector2U16,

pub fn init(self: *TextureAtlas) void {
    self.flags[0].free = false;
    self.image_count = 1;
    self.image_limit = 1;
    self.atlas_ptr = .zero;
}

pub fn deinit(self: *TextureAtlas, allc: Allocator) void {
    for (self.images[1..self.image_count]) |image| {
        allc.free(image.data);
    }
}

pub fn takeFreeImageSlot(self: *TextureAtlas) !ImageRef {
    if (self.image_limit == self.image_count) {
        defer self.image_limit += 1;
        defer self.image_count += 1;
        return .init(@intCast(self.image_limit));
    }
    for (self.flags[0..self.image_limit], 0..) |flag, index| {
        if (flag.free) {
            self.image_count += 1;
            return .init(@intCast(index));
        }
    }
    return error.outOfSlots;
}

pub fn createImage(self: *TextureAtlas, allc: Allocator, width: u32, height: u32) !.{ Image, ImageRef } {
    const image: Image = try .createRaw(allc, width, height);
    const image_id = self.takeFreeImageSlot();
    self.images[image_id] = image;
    self.flags[image_id] = false;
    return .{ image, image_id };
}

pub fn freeImage(self: *TextureAtlas, allc: Allocator, image: ImageRef) void {
    allc.free(self.images[image].data);
    self.flags[image.ref] = true;
    if (image.ref == self.image_count) self.image_count -= 1;
}

pub fn renderImage(self: *TextureAtlas, image: ImageRef) void {
    assert(!self.flags[image.ref].free);
    self.flags[image.ref].render = true;
}

pub fn renderImages(self: *TextureAtlas, render: *Render) void {
    const ImagesContext = struct {
        images: []Image,

        pub fn lessThan(images: @This(), lhs: ImageRef, rhs: ImageRef) bool {
            //sort works in ascending order, and want the biggest height ones first
            return images.images[lhs.ref].height > images.images[rhs.ref].height;
        }
    };
    std.sort.
}
