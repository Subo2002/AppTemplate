const std = @import("std");
const mach = @import("mach");
const gpu = mach.gpu;
const builtin = @import("builtin");

const App = @This();

// The set of Mach modules our application may use.
pub const Modules = mach.Modules(.{
    mach.Core,
    App,
});

pub const mach_module = .app;

pub const mach_systems = .{
    .main,
    .init,
    .appTick,
    .tick,
    .render,
    .deinit,
};

pub const main = mach.schedule(.{
    .{ mach.Core, .init },
    .{ App, .init },
    .{ mach.Core, .main },
});

allocator: std.mem.Allocator,
pipeline: ?*gpu.RenderPipeline = null,
app_thread: mach.Thread,
window: mach.ObjectID,
texture_atlas: mach.gfx.Atlas = undefined,
texture: *gpu.Texture = undefined,

pub fn init(
    core: *mach.Core,
    app: *App,
    app_mod: mach.Mod(App),
    core_mod: mach.Mod(mach.Core),
) !void {
    core.on_exit = app_mod.id.deinit;

    const window = try core.windows.new(.{
        .title = "Hello, Mach!",
        .on_render = app_mod.id.render,
    });

    const allocator = std.heap.c_allocator;

    // Store our render pipeline in our module's state, so we can access it later on.
    app.* = .{
        .app_thread = try mach.startThread(core, app_mod.id.tick, core_mod, .app),
        .window = window,
        .allocator = allocator,
    };
}

fn setupPipeline(core: *mach.Core, app: *App) !void {
    var window = core.windows.getValue(core.window);
    defer core.windows.setValueRaw(core.window, window);

    // rgba32_pixels
    const img_size = gpu.Extent3D{ .width = 1024, .height = 1024 };

    // Create our shader module
    const shader_module = window.device.createShaderModuleWGSL("shader.wgsl", @embedFile("shader.wgsl"));
    defer shader_module.release();

    // Blend state describes how rendered colors get blended
    const blend = gpu.BlendState{};

    // Color target describes e.g. the pixel format of the window we are rendering to.
    const color_target = gpu.ColorTargetState{
        .format = window.framebuffer_format,
        .blend = &blend,
    };

    // Fragment state describes which shader and entrypoint to use for rendering fragments.
    const fragment = gpu.FragmentState.init(.{
        .module = shader_module,
        .entry_point = "frag_main",
        .targets = &.{color_target},
    });

    // Create our render pipeline that will ultimately get pixels onto the screen.
    const label = @tagName(mach_module) ++ ".init";
    const pipeline_descriptor = gpu.RenderPipeline.Descriptor{
        .label = label,
        .fragment = &fragment,
        .vertex = gpu.VertexState{
            .module = shader_module,
            .entry_point = "vertex_main",
        },
    };

    app.texture = window.device.createTexture(&.{
        .label = label,
        .size = img_size,
        .format = .rgba8_unorm,
        .usage = .{
            .texture_binding = true,
            .copy_dst = true,
            .render_attachment = true,
        },
    });

    app.texture_atlas = try mach.gfx.Atlas.init(
        app.allocator,
        img_size.width,
        .rgba,
    );

    if (c.FT_Init_FreeType(&app.ft) != 0) return error.FreetypeInitFailed;
    const roboto_medium_ttf = @embedFile("Roboto-Regular.ttf");
    if (c.FT_New_Memory_Face(app.ft, roboto_medium_ttf.*, @intCast(roboto_medium_ttf.len), 0, &app.face) != 0)
        return error.FreetypeError;
    //if (c.FT_New_Memory_Face(app.ft, assets.roboto_medium_ttf.ptr, @intCast(assets.roboto_medium_ttf.len), 0, &app.face) != 0)
    //    return error.FreetypeError;
    try prepareGlyphs(window.queue, app);

    app.pipeline = window.device.createRenderPipeline(&pipeline_descriptor);
}

fn prepareGlyphs(queue: *gpu.Queue, app: *App) !void {
    // Prepare which glyphs we will render
    const codepoints: []const u21 = &[_]u21{ '?', '!', 'a', 'b', '#', '@', '%', '$', '&', '^', '*', '+', '=', '<', '>', '/', ':', ';', 'Q', '~' };
    for (codepoints) |codepoint| {
        const font_size = 48 * 1;
        if (c.FT_Set_Char_Size(app.face, font_size * 64, 0, 50, 0) != 0) return error.FreetypeError;
        if (c.FT_Load_Char(app.face, codepoint, c.FT_LOAD_RENDER) != 0) return error.FreetypeError;
        const glyph = app.face.*.glyph;
        const metrics = glyph.*.metrics;

        const glyph_bitmap = glyph.*.bitmap;
        const glyph_width = glyph_bitmap.width;
        const glyph_height = glyph_bitmap.rows;

        // Add 1 pixel padding to texture to avoid bleeding over other textures
        const margin = 1;
        const glyph_data = try app.allocator.alloc([4]u8, (glyph_width + (margin * 2)) * (glyph_height + (margin * 2)));
        defer app.allocator.free(glyph_data);
        const glyph_buffer: [*]const u8 = glyph_bitmap.buffer;
        const glyph_buffer_len = glyph_bitmap.pitch * @as(c_int, @intCast(glyph_height));
        const glyph_buffer_slice = glyph_buffer[0..@intCast(glyph_buffer_len)];
        for (glyph_data, 0..) |*data, i| {
            const x = i % (glyph_width + (margin * 2));
            const y = i / (glyph_width + (margin * 2));
            if (x < margin or x > (glyph_width + margin) or y < margin or y > (glyph_height + margin)) {
                data.* = [4]u8{ 0, 0, 0, 0 };
            } else {
                const alpha = glyph_buffer_slice[((y - margin) * glyph_width + (x - margin)) % glyph_buffer_slice.len];
                data.* = [4]u8{ 0, 0, 0, alpha };
            }
        }
        var glyph_atlas_region = try app.texture_atlas.reserve(app.allocator, glyph_width + (margin * 2), glyph_height + (margin * 2));
        app.texture_atlas.set(glyph_atlas_region, @as([*]const u8, @ptrCast(glyph_data.ptr))[0 .. glyph_data.len * 4]);

        glyph_atlas_region.x += margin;
        glyph_atlas_region.y += margin;
        glyph_atlas_region.width -= margin * 2;
        glyph_atlas_region.height -= margin * 2;

        try app.regions.put(app.allocator, codepoint, glyph_atlas_region);
        _ = metrics;
    }

    // rgba32_pixels
    const img_size = gpu.Extent3D{ .width = 1024, .height = 1024 };
    const data_layout = gpu.Texture.DataLayout{
        .bytes_per_row = @as(u32, @intCast(img_size.width * 4)),
        .rows_per_image = @as(u32, @intCast(img_size.height)),
    };
    queue.writeTexture(&.{ .texture = app.texture }, &data_layout, &img_size, app.texture_atlas.data);
}

pub const tick = mach.schedule(.{
    .{ App, .appTick },
    .{ mach.Core, .snapshotStart },
    .{ mach.Core, .snapshotEnd },
});

pub fn appTick(core: *mach.Core) void {
    var iter = core.events(.default);
    while (iter.next()) |event| {
        switch (event) {
            .close => core.exit(),
            else => {},
        }
    }
}

pub fn render(app: *App, core: *mach.Core) !void {
    const pipeline = app.pipeline orelse {
        try setupPipeline(core, app);
        return;
    };
    const label = @tagName(mach_module) ++ ".render";
    const window = core.windows.getValue(core.window);

    // Grab the back buffer of the swapchain
    // TODO(core): this wouldn't exist in browser
    const back_buffer_view = window.swap_chain.getCurrentTextureView() orelse return;
    defer back_buffer_view.release();

    // Create a command encoder
    const encoder = window.device.createCommandEncoder(&.{ .label = label });
    defer encoder.release();

    // Begin render pass
    const sky_blue_background = gpu.Color{ .r = 0.776, .g = 0.988, .b = 1, .a = 1 };
    const color_attachments = [_]gpu.RenderPassColorAttachment{.{
        .view = back_buffer_view,
        .clear_value = sky_blue_background,
        .load_op = .clear,
        .store_op = .store,
    }};
    const render_pass = encoder.beginRenderPass(&gpu.RenderPassDescriptor.init(.{
        .label = label,
        .color_attachments = &color_attachments,
    }));
    defer render_pass.release();

    // Draw
    render_pass.setPipeline(pipeline);
    render_pass.draw(3, 1, 0, 0);

    // Finish render pass
    render_pass.end();

    // Submit our commands to the queue
    var command = encoder.finish(&.{ .label = label });
    defer command.release();
    window.queue.submit(&[_]*gpu.CommandBuffer{command});

    {
        core.windows.lock();
        defer core.windows.unlock();
        try core.fmtTitle(app.window, "Hello, Mach! [ {d}fps ] [ Input {d}hz ]", .{
            core.frame.rate, core.input.rate,
        });
    }
}

pub fn deinit(app: *App) void {
    app.app_thread.join();
    if (app.pipeline) |p| p.release();
}
