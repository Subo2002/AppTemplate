const std = @import("std");
const Io = std.Io;
const TrueType = @import("TrueType");
const zglfw = @import("zglfw");
const wgpu = @import("wgpu");

const AppTemplate = @import("AppTemplate");
const GLFW = zglfw.GLFW;
const Window = zglfw.Window;
pub fn main(init: std.process.Init) !void {
    var glfw: GLFW = try .init();
    defer glfw.terminate();

    const window = try Window.create(
        1600,
        900,
        "App",
        null,
        null,
    );
    defer window.destroy();

    glfw.makeContextCurrent(window);

    const instance = wgpu.Instance.create(null).?;
    defer instance.release();

    const adapter_request = instance.requestAdapterSync(
        &wgpu.RequestAdapterOptions{},
        init.io,
        0,
    );
    const adapter = switch (adapter_request.status) {
        .success => adapter_request.adapter.?,
        else => return error.NoAdapter,
    };
    defer adapter.release();

    const device_request = adapter.requestDeviceSync(
        instance,
        &wgpu.DeviceDescriptor{
            .required_limits = null,
        },
        init.io,
        0,
    );
    const device = switch (device_request.status) {
        .success => device_request.device.?,
        else => return error.NoDevice,
    };
    defer device.release();

    const queue = device.getQueue().?;
    queue.release();

    const swap_chain_format = wgpu.TextureFormat.bgra8_unorm_srgb;

    const target_texture = device.createTexture(&wgpu.TextureDescriptor{
        .label = wgpu.StringView.fromSlice("Render texture"),
        .size = output_extent,
        .format = swap_chain_format,
        .usage = wgpu.TextureUsages.render_attachment | wgpu.TextureUsages.copy_src,
    }).?;
    defer target_texture.release();

    const target_texture_view = target_texture.createView(&wgpu.TextureViewDescriptor{
        .label = wgpu.StringView.fromSlice("Render texture view"),
        .mip_level_count = 1,
        .array_layer_count = 1,
    }).?;

    const shader_module = device.createShaderModule(&wgpu.shaderModuleWGSLDescriptor(.{
        .code = @embedFile("./shader.wgsl"),
    })).?;
    defer shader_module.release();

    const staging_buffer = device.createBuffer(&wgpu.BufferDescriptor{
        .label = wgpu.StringView.fromSlice("staging_buffer"),
        .usage = wgpu.BufferUsages.map_read | wgpu.BufferUsages.copy_dst,
        .size = output_size,
        .mapped_at_creation = @as(u32, @intFromBool(false)),
    }).?;
    defer staging_buffer.release();

    const color_targets = &[_]wgpu.ColorTargetState{
        wgpu.ColorTargetState{
            .format = swap_chain_format,
            .blend = &wgpu.BlendState{
                .color = wgpu.BlendComponent{
                    .operation = .add,
                    .src_factor = .src_alpha,
                    .dst_factor = .one_minus_src_alpha,
                },
                .alpha = wgpu.BlendComponent{
                    .operation = .add,
                    .src_factor = .zero,
                    .dst_factor = .one,
                },
            },
        },
    };

    const pipeline = device.createRenderPipeline(&wgpu.RenderPipelineDescriptor{
        .vertex = wgpu.VertexState{
            .module = shader_module,
            .entry_point = wgpu.StringView.fromSlice("vs_main"),
        },
        .primitive = wgpu.PrimitiveState{},
        .fragment = &wgpu.FragmentState{ .module = shader_module, .entry_point = wgpu.StringView.fromSlice("fs_main"), .target_count = color_targets.len, .targets = color_targets.ptr },
        .multisample = wgpu.MultisampleState{},
    }).?;
    defer pipeline.release();

    { // Mock main "loop"

    }

    //try zopengl.loadCoreProfile(GLFW.getProcAddress, 4, 0);
    //const gl = zopengl.wrapper;
    //gl.clearBufferfv(.color, 0, &.{ 0.2, 0.4, 0.8, 1.0 });

    const arena = init.arena.allocator();

    const ttf = try TrueType.load(@embedFile("Mistral.ttf"));
    const example_string = "こんにちは!";
    const scale = ttf.scaleForPixelHeight(20);
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .init(.stdout(), init.io, stdout_buffer[0..]);
    const stdout = &stdout_writer.interface;
    var buffer: std.ArrayListUnmanaged(u8) = .empty;
    defer buffer.deinit(arena);
    var it = std.unicode.Utf8View.initComptime(example_string).iterator();
    while (it.nextCodepoint()) |codepoint| {
        const glyph = ttf.codepointGlyphIndex(codepoint);
        if (glyph == .notdef) {
            std.log.debug("0x{d}: none", .{codepoint});
            continue;
        }
        std.log.debug("0x{d}: {d}", .{ codepoint, glyph });
        buffer.clearRetainingCapacity();
        const dims = try ttf.glyphBitmap(arena, &buffer, glyph, scale, scale);
        const pixels = buffer.items;
        for (0..dims.height) |j| {
            for (0..dims.width) |i| {
                try stdout.writeByte(" .:ioVM@"[pixels[j * dims.width + i] >> 5]);
            }
            try stdout.writeByte('\n');
        }
    }
    try stdout.flush();

    while (!window.shouldClose()) {
        glfw.pollEvents();

        const next_texture = target_texture_view;

        const encoder = device.createCommandEncoder(&wgpu.CommandEncoderDescriptor{
            .label = wgpu.StringView.fromSlice("Command Encoder"),
        }).?;
        defer encoder.release();

        const color_attachments = &[_]wgpu.ColorAttachment{wgpu.ColorAttachment{
            .view = next_texture,
            .clear_value = wgpu.Color{},
        }};
        const render_pass = encoder.beginRenderPass(&wgpu.RenderPassDescriptor{
            .color_attachment_count = color_attachments.len,
            .color_attachments = color_attachments.ptr,
        }).?;

        render_pass.setPipeline(pipeline);
        render_pass.draw(3, 1, 0, 0);
        render_pass.end();

        // The render pass has to be released after .end() or otherwise we'll crash on queue.submit
        // https://github.com/gfx-rs/wgpu-native/issues/412#issuecomment-2311719154
        render_pass.release();

        defer next_texture.release();

        const img_copy_src = wgpu.TexelCopyTextureInfo{
            .origin = wgpu.Origin3D{},
            .texture = target_texture,
        };
        const img_copy_dst = wgpu.TexelCopyBufferInfo{
            .layout = wgpu.TexelCopyBufferLayout{
                .bytes_per_row = output_bytes_per_row,
                .rows_per_image = output_extent.height,
            },
            .buffer = staging_buffer,
        };

        encoder.copyTextureToBuffer(&img_copy_src, &img_copy_dst, &output_extent);

        const command_buffer = encoder.finish(&wgpu.CommandBufferDescriptor{
            .label = wgpu.StringView.fromSlice("Command Buffer"),
        }).?;
        defer command_buffer.release();

        queue.submit(&[_]*const wgpu.CommandBuffer{command_buffer});

        glfw.swapBuffers(window);
    }
}

//pub fn main(init: std.process.Init) !void {
//    _ = TrueType;
//    _ = zglfw;
//    _ = zopengl;
//    // Prints to stderr, unbuffered, ignoring potential errors.
//    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});
//
//    // This is appropriate for anything that lives as long as the process.
//    const arena: std.mem.Allocator = init.arena.allocator();
//
//    // Accessing command line arguments:
//    const args = try init.minimal.args.toSlice(arena);
//    for (args) |arg| {
//        std.log.info("arg: {s}", .{arg});
//    }
//
//    // In order to do I/O operations need an `Io` instance.
//    const io = init.io;
//
//    // Stdout is for the actual output of your application, for example if you
//    // are implementing gzip, then only the compressed bytes should be sent to
//    // stdout, not any debugging messages.
//    var stdout_buffer: [1024]u8 = undefined;
//    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
//    const stdout_writer = &stdout_file_writer.interface;
//
//    try AppTemplate.printAnotherMessage(stdout_writer);
//
//    try stdout_writer.flush(); // Don't forget to flush!
//}

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa); // Try commenting this out and see if zig detects the memory leak!
    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    try std.testing.fuzz({}, testOne, .{});
}

fn testOne(context: void, smith: *std.testing.Smith) !void {
    _ = context;
    // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!

    const gpa = std.testing.allocator;
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(gpa);
    while (!smith.eos()) switch (smith.value(enum { add_data, dup_data })) {
        .add_data => {
            const slice = try list.addManyAsSlice(gpa, smith.value(u4));
            smith.bytes(slice);
        },
        .dup_data => {
            if (list.items.len == 0) continue;
            if (list.items.len > std.math.maxInt(u32)) return error.SkipZigTest;
            const len = smith.valueRangeAtMost(u32, 1, @min(32, list.items.len));
            const off = smith.valueRangeAtMost(u32, 0, @intCast(list.items.len - len));
            try list.appendSlice(gpa, list.items[off..][0..len]);
            try std.testing.expectEqualSlices(
                u8,
                list.items[off..][0..len],
                list.items[list.items.len - len ..],
            );
        },
    };
}
