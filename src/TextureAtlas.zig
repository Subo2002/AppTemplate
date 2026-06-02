const GraphicsLib = @import("Graphics.zig");
const Image = GraphicsLib.Image;
const ImageRef = GraphicsLib.ImageRef;
const Color = GraphicsLib.Color;

const Lib = @import("lib.zig");
const Vector2U16 = Lib.Vector2U16;
const Vector2I32 = Lib.Vector2I32;

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const Render = @import("Render.zig").Render;

pub const TextureAtlas = @This();

pub const atlas_size: Vector2U16 = .init(2048, 2048);

pub const Flags = packed struct {
    free: bool,
    render: bool,
    rendered: bool,
};

//TODO:
// DONE: 1. add images_to_upload struct instead of flags approach, but keep render, and rendered field, so can know if image is in use on the gpu and if it's on the gpu
// DONE: 2. move the texture atlas writing stuff in to here from render
// DONE: 3. write uploadImages, which just sorts them by height and adds them to the buffer,
// PARTIALLY DONE: 4. ...no page stuff, and if it's full wipe the gpu atlas and upload all the needed textures. Kind of arena style
// DONE: 5. write printLine method
// DONE: 6. replace all the logic in main with this new stuff, will basically be empty again
// DONE: 7. create UIHandler, and use it to make window (ui-) cntx
// DONE: 8. start ui
// 9. want to print a little text ui
// 10. want to be able to render images
// 10. want button
// 11. want to be able to input numbers, and text
// 12. want a screen division that is moveable
// 13. want a draggable and placeable item
// 14. want to be able to shrink and resize the window and all be nice

images: [max_no_images]Image,
flags: [max_no_images]Flags,
atlas_refs: [max_no_images]AtlasRef,
image_count: usize,
image_limit: usize,

uploads: ImageUploader,
atlas_ptr: Vector2U16,

//WARNING: MAKE SURE AGREES WITH WITH SHADER SIDE
pub const max_no_images = 100;

pub fn init(self: *TextureAtlas) void {
    self.flags[0].free = false;
    self.image_count = 1;
    self.image_limit = 1;
    self.uploads.init();
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

pub fn createImage(self: *TextureAtlas, allc: Allocator, width: u32, height: u32) !struct { Image, ImageRef } {
    const image: Image = try .createRaw(allc, width, height);
    const image_id = try self.takeFreeImageSlot();
    self.images[image_id.ref] = image;
    self.flags[image_id.ref].free = false;
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
    self.uploads.push(image) catch unreachable;
}

pub fn uploadImages(self: *TextureAtlas, render: *Render) !void {
    try self.compUploadsAtlasRefs();
    self.uploadToRender(render);
}

fn compUploadsAtlasRefs(self: *TextureAtlas) !void {
    //sort image_refs by their image's height
    const ImagesContext = struct {
        images: []Image,

        pub fn lessThan(images: @This(), lhs: ImageRef, rhs: ImageRef) bool {
            //sort works in ascending order, and want the biggest height ones first
            return images.images[lhs.ref].height > images.images[rhs.ref].height;
        }
    };
    const image_cntx: ImagesContext = .{
        .images = self.images[0..self.image_limit],
    };
    const uploads = self.uploads.getUploads();
    std.mem.sort(
        ImageRef,
        uploads,
        image_cntx,
        ImagesContext.lessThan,
    );

    var row_height: u32 = self.images[uploads[0].ref].height;
    for (uploads) |upload| {
        const image = self.images[upload.ref];
        const atlas_ref = &self.atlas_refs[upload.ref];
        //Vector2U for image size would be nice, get rid of this
        assert(image.width >= 0 and image.height >= 0);
        //TODO: want to build a better system to remove this assertion in future
        assert(image.width <= atlas_size.x and image.height <= atlas_size.y);
        if (@as(u32, @intCast(self.atlas_ptr.x)) + image.width > 256) {
            self.atlas_ptr.x = 0;
            self.atlas_ptr.y += @intCast(row_height);
            row_height = image.height;
        }

        if (@as(u32, @intCast(self.atlas_ptr.y)) + image.height > 256) {
            std.debug.print("height run-off", .{});
            self.atlas_ptr = .zero;
            return error.atlasFull;
        }

        const size: Vector2I32 = .init(@intCast(image.width), @intCast(image.height));

        atlas_ref.* = .{
            .size = size,
            .pos = .init(@intCast(self.atlas_ptr.x), @intCast(self.atlas_ptr.y)),
        };

        self.atlas_ptr.x += @intCast(image.width);
    }
}

fn uploadToRender(self: *TextureAtlas, render: *Render) void {
    defer self.uploads.init(); //clear

    const atlas = render.getAtlas();
    const queue = render.gfx_cntx.queue;
    for (self.uploads.images_to_upload[0..self.uploads.no]) |upload| {
        const image = self.images[upload.ref];
        const atlas_ref = self.atlas_refs[upload.ref];
        std.debug.assert(image.width == atlas_ref.size.x and image.height == atlas_ref.size.y);
        queue.writeTexture(
            .{
                .texture = atlas,
                .origin = .{
                    .x = @intCast(atlas_ref.pos.x),
                    .y = @intCast(atlas_ref.pos.y),
                },
            },
            .{
                .bytes_per_row = image.width * @sizeOf(Color),
                .rows_per_image = image.height,
            },
            .{ .width = image.width, .height = image.height },
            Color,
            image.data,
        );
    }

    queue.writeBuffer(
        render.getAtlasRefs(),
        0,
        AtlasRef,
        self.atlas_refs[0..],
    );
}

pub const AtlasRef = struct {
    size: Vector2I32,
    padding1: Vector2I32 = .zero,
    pos: Vector2I32,
    padding2: Vector2I32 = .zero,
};

pub const ImageUploader = struct {
    const max_no_uploads = 100;

    no: u32,
    images_to_upload: [max_no_uploads]ImageRef,

    pub fn init(self: *ImageUploader) void {
        self.no = 0;
    }

    pub fn push(self: *ImageUploader, image: ImageRef) !void {
        self.images_to_upload[self.no] = image;
        self.no += 1;
    }

    pub fn getUploads(self: *ImageUploader) []ImageRef {
        return self.images_to_upload[0..self.no];
    }
};
