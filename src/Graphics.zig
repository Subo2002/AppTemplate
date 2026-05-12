const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

pub const ImageRef = struct {
    ref: u32,

    pub const invalid = ImageRef{
        .ref = (1 << 32) - 1,
    };

    pub fn init(ref: u32) ImageRef {
        assert(ref != (1 << 32) - 1);
        return ImageRef{
            .ref = ref,
        };
    }
};

pub const Image = struct {
    width: u32,
    height: u32,
    data: []Color,

    pub fn init(width: u32, height: u32, data: []Color) Image {
        assert(data.len == width * height);
        return .{
            .width = width,
            .height = height,
            .data = data,
        };
    }

    pub fn createRaw(allc: Allocator, width: u32, height: u32) !Image {
        return .init(width, height, try allc.alloc(Color, width * height));
    }
};

pub const Color = struct {
    pub const blank: Color = .init(0, 0, 0, 0);
    pub const black: Color = .init(0, 0, 0, 255);
    pub const white: Color = .initRGB(255, 255, 255);
    pub const red: Color = .initRGB(255, 0, 0);
    pub const green: Color = .initRGB(0, 255, 0);
    pub const blue: Color = .initRGB(0, 0, 255);
    pub const yellow: Color = .initRGB(255, 255, 0);
    pub const cyan: Color = .initRGB(0, 255, 255);
    pub const magenta: Color = .initRGB(255, 0, 255);

    r: u8,
    g: u8,
    b: u8,
    a: u8,

    pub fn initRGB(r: u8, g: u8, b: u8) Color {
        return .init(r, g, b, 255);
    }

    pub fn init(r: u8, g: u8, b: u8, a: u8) Color {
        return Color{
            .r = r,
            .g = g,
            .b = b,
            .a = a,
        };
    }
};
