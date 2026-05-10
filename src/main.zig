const sdl = @import("sdl");
const std = @import("std");

const screen_width: c_int = 800;
const screen_height: c_int = 600;

const fps = 60;

pub fn main(
    init: std.process.Init,
) !void {
    const allocator = init.gpa;
    _ = allocator;

    const log_app = sdl.log.Category.application;

    try sdl.init(.{ .video = true, .events = true });
    defer sdl.quit(.{ .video = true, .events = true });

    try sdl.ttf.init();
    defer sdl.ttf.quit();

    try log_app.logInfo("Using SDL_ttf {d}.{d}.{d}", .{ sdl.ttf.major_version, sdl.ttf.minor_version, sdl.ttf.micro_version });
    try log_app.logInfo("Linked against SDL_ttf version: {any}", .{sdl.ttf.getVersion()});
    std.debug.assert(sdl.ttf.Version.atLeast(3, 0, 0));
    const ft_version = sdl.ttf.getFreeTypeVersion();
    try log_app.logInfo("Using FreeType {d}.{d}.{d}", .{ ft_version.major, ft_version.minor, ft_version.patch });
    const hb_version = sdl.ttf.getHarfBuzzVersion();
    try log_app.logInfo("Using HarfBuzz {d}.{d}.{d}", .{ hb_version.major, hb_version.minor, hb_version.patch });
    std.debug.assert(sdl.ttf.wasInit() > 0);

    const tag = sdl.ttf.stringToTag("test");
    const tag_str = sdl.ttf.tagToString(tag);
    try log_app.logInfo("Tag 'test' -> {any} -> {s}", .{ tag, &tag_str });

    const window, const renderer = try sdl.render.Renderer.initWithWindow(
        "SDL_ttf Example",
        screen_width,
        screen_height,
        .{ .resizable = true, .high_pixel_density = true },
    );

    defer renderer.deinit();
    defer window.deinit();

    var frame_capper = sdl.extras.FramerateCapper(f32){ .mode = .{ .unlimited = {} } };
    renderer.setVSync(.{ .on_each_num_refresh = 1 }) catch {
        frame_capper.mode = .{ .limited = fps };
    };

    const font_path = "data/Roboto-Regular.ttf";
    var font = try sdl.ttf.Font.init(font_path, 24);
    font.setHinting(.normal);
    defer font.deinit();

    try log_app.logInfo("Font Family: {s}", .{font.getFamilyName()});
    try log_app.logInfo("Font Style: {s}", .{font.getStyleName()});
    try log_app.logInfo("Font is fixed width: {}", .{font.isFixedWidth()});
    try log_app.logInfo("Font is scalable: {}", .{font.isScalable()});
    try log_app.logInfo("Font height: {d}", .{font.getHeight()});
    try log_app.logInfo("Font ascent: {d}", .{font.getAscent()});
    try log_app.logInfo("Font descent: {d}", .{font.getDescent()});
    try log_app.logInfo("Font lineskip: {d}", .{font.getLineSkip()});
    try log_app.logInfo("Font faces: {d}", .{font.getNumFaces()});
    try log_app.logInfo("Font kerning enabled: {}", .{font.getKerning()});
    try log_app.logInfo("Font has glyph 'A': {}", .{font.hasGlyph('A')});
    if (font.getGlyphMetrics('A')) |metrics| {
        try log_app.logInfo("Glyph 'A' metrics: minx={d}, maxx={d}, miny={d}, maxy={d}, advance={d}", .{
            metrics.minx, metrics.maxx, metrics.miny, metrics.maxy, metrics.advance,
        });
    } else |err| {
        try log_app.logWarn("Could not get glyph metrics for 'A': {s}", .{@errorName(err)});
    }
    if (font.getGlyphKerning('V', 'A')) |kerning| {
        try log_app.logInfo("Kerning for 'VA': {d}", .{kerning});
    } else |err| {
        try log_app.logWarn("Could not get glyph kerning for 'VA': {s}", .{@errorName(err)});
    }

    const white: sdl.ttf.Color = .{ .r = 255, .g = 255, .b = 255, .a = 255 };
    _ = white;
    const yellow: sdl.ttf.Color = .{ .r = 255, .g = 255, .b = 0, .a = 255 };
    _ = yellow;
    const cyan: sdl.ttf.Color = .{ .r = 0, .g = 255, .b = 255, .a = 255 };
    _ = cyan;
    const magenta: sdl.ttf.Color = .{ .r = 255, .g = 0, .b = 255, .a = 255 };
    _ = magenta;
    //const clear: sdl.ttf.Color = .{ .r = 0, .g = 0, .b = 0, .a = 0 };
    const black: sdl.ttf.Color = .{ .r = 0, .g = 0, .b = 0, .a = 255 };

    const blended_texture = try textureFromSurface(renderer, try font.renderTextBlended("Blended Text", black));
    defer blended_texture.deinit();

    const text_engine: sdl.ttf.RendererTextEngine = try .initWithProperties(.{
        .renderer = renderer,
        .atlas_texture_size = 1024,
    });
    defer text_engine.deinit();

    const text_obj: sdl.ttf.Text = try .init(.{ .value = text_engine.value }, font, "Editable Text Object");
    defer text_obj.deinit();
    try text_obj.setColor(255, 165, 0, 255);
    try text_obj.setPosition(10, 450);

    var quit_app = false;
    while (!quit_app) {
        const dt = frame_capper.delay();
        _ = dt;

        while (sdl.events.poll()) |event| {
            switch (event) {
                .quit, .terminating => quit_app = true,
                .key_down => |key| {
                    if (key.key == .escape) {
                        quit_app = true;
                    }
                },
                else => {},
            }
        }

        if (frame_capper.frame_num > 0 and frame_capper.frame_num % 60 == 0) {
            if (text_obj.getText().len > 50) {
                try text_obj.setString("Editable Text Object");
            } else {
                try text_obj.appendString(" .");
            }
        }

        // --- Rendering ---
        try renderer.setDrawColor(.{ .r = 255, .g = 255, .b = 255, .a = 255 });
        try renderer.clear();

        var y_pos: f32 = 10;
        const textures_to_render = [_]*const sdl.render.Texture{
            &blended_texture,
        };

        for (textures_to_render) |tex_ptr| {
            const tex = tex_ptr.*;
            const width, const height = try tex.getSize();
            const dst = sdl.rect.FRect{ .x = 10, .y = y_pos, .w = width, .h = height };
            try renderer.renderTexture(tex, null, dst);
            y_pos += height + 5;
        }

        const text_pos_x, const text_pos_y = try text_obj.getPosition();
        try sdl.ttf.drawRendererText(text_obj, @as(f32, @floatFromInt(text_pos_x)), @as(f32, @floatFromInt(text_pos_y)));

        try renderer.present();
    }
}

fn textureFromSurface(renderer: sdl.render.Renderer, surface: sdl.surface.Surface) !sdl.render.Texture {
    defer surface.deinit();
    return try renderer.createTextureFromSurface(surface);
}
