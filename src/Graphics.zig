const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const gpu = @import("zgpu");
const wgpu = gpu.wgpu;
const glfw = @import("zglfw");
const math = @import("zmath");
const stbi = @import("zstbi");

const Lib = @import("lib.zig");
const Vector2I32 = Lib.Vector2I32;
const Vector2U16 = Lib.Vector2U16;

const zsmath = @import("ZSMath");
const Vector2B = zsmath.Vector2B;
const Vector2 = zsmath.Vector2;
const Vector2U32 = zsmath.Vector2Int(u32);

const spline = @import("zspline");
const Circle = spline.Circle;
const CubicSpline = spline.CubicSpline;
const Line = spline.Line;
const world_size = @import("main.zig").world_size;

const ImagesContext = @import("TextureAtlas.zig").ImagesContext;

pub const InstanceData = struct {
    pos: Vector2 = .zero,
    dims: Vector2 = .zero,
    depth: f32 = 0,
    tex: u32 = 0,
    col: Color = .white,

    const empty = InstanceData{
        .pos = .zero,
        .dims = .zero,
        .depth = 0,
        .tex = 0,
        .col = Color{
            .red = 0,
            .green = 0,
            .blue = 0,
            .a = 0,
        },
    };
};

//OLD
//pub const ImageUpload = struct {
//    start: u32,
//    atlas_ref: AtlasRef,
//};

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

//NEW
pub const ImageUpload = struct {
    image_ref: ImageRef,
    atlas_ref: AtlasRef,
};

pub const AtlasRef = struct {
    size: Vector2I32,
    padding1: Vector2I32 = .zero,
    pos: Vector2I32,
    padding2: Vector2I32 = .zero,
};

pub const ImageRef = struct {
    ref: u32,

    pub const invalid = ImageRef{
        .ref = (1 << 32) - 1,
    };

    pub fn init(ref: u32) ImageRef {
        std.debug.assert(ref != (1 << 32) - 1);
        return ImageRef{
            .ref = ref,
        };
    }
};

pub const ImageUploadData = struct {
    no: u32,
    size: u32,
};

pub const TextureAtlas = struct {
    size: Vector2U32,
};

pub const Graphics = struct {
    gfx_cntx: *gpu.GraphicsContext,

    //compute_pipeline: gpu.ComputePipelineHandle,
    pipeline: gpu.RenderPipelineHandle,
    bind_group: gpu.BindGroupHandle,
    blend: wgpu.BlendState,

    vertex_buffer: gpu.BufferHandle,
    index_buffer: gpu.BufferHandle,

    texture: gpu.TextureHandle,
    texture_view: gpu.TextureViewHandle,
    sampler: gpu.SamplerHandle,

    window: *glfw.Window,

    instance_data: [instance_buffer_size]InstanceData,
    instance_buffer: gpu.BufferHandle,
    no_instances: u32,

    upload: ImageUploadData,
    uploads_data: [max_no_images_per_frame]ImageUpload,

    images_handle: gpu.BufferHandle,
    images: [max_no_images]AtlasRef,

    texture_atlas: gpu.TextureHandle,
    texture_atlas_header_handle: gpu.BufferHandle,
    texture_atlas_header: TextureAtlas,

    const instance_buffer_size = 50;
    const max_no_images_per_frame = 64;
    //WARNING: make sure this agrees with the fragment shader
    const max_no_images = 256;
    const raw_uploads_buffer_pixel_size = 1024 * 1024 * 2; //max upload 1MB in a frame
    pub const raw_uploads_buffer_size = raw_uploads_buffer_pixel_size * @sizeOf(Color);

    fn glfwGetTime() f64 {
        return glfw.getTime();
    }

    fn glfwGetFramebufferSize(window: *const anyopaque) [2]u32 {
        const w: *const glfw.Window = @ptrCast(window);
        const size = @constCast(w).getFramebufferSize();
        return [2]u32{ @intCast(size[0]), @intCast(size[1]) };
    }

    pub fn init(self: *Graphics, allc: std.mem.Allocator, window: *glfw.Window, atlas_size: Vector2U16) !void {
        //not necessary
        @memset(self.images[0..], AtlasRef{
            .size = .zero,
            .pos = .zero,
        });

        std.debug.assert(@sizeOf(c_int) == @sizeOf(u32));
        const gfx_cntx = try gpu.GraphicsContext.create(
            allc,
            .{
                .window = window,
                .fn_getTime = &glfwGetTime,
                .fn_getFramebufferSize = &glfwGetFramebufferSize,
                .fn_getWin32Window = @ptrCast(&glfw.getWin32Window),
                .fn_getX11Display = @ptrCast(&glfw.getX11Display),
                .fn_getX11Window = @ptrCast(&glfw.getX11Window),
                .fn_getWaylandDisplay = @ptrCast(&glfw.getWaylandDisplay),
                .fn_getWaylandSurface = @ptrCast(&glfw.getWaylandWindow),
                .fn_getCocoaWindow = @ptrCast(&glfw.getCocoaWindow),
            },
            .{},
        );
        errdefer gfx_cntx.destroy(allc);

        //create bind group layout for rendering
        const bind_group_layout = gfx_cntx.createBindGroupLayout(&.{
            gpu.bufferEntry(0, .{ .vertex = true, .fragment = true }, .uniform, true, 0),
            gpu.textureEntry(1, .{ .fragment = true }, .float, .tvdim_2d, false),
            gpu.samplerEntry(2, .{ .fragment = true }, .filtering),
            //gpu.textureEntry(3, .{ .fragment = true }, .float, .tvdim_2d, false),
            //gpu.textureEntry(4, .{ .fragment = true }, .float, .tvdim_2d, false),
            //gpu.storageTextureEntry(5, .{ .compute = true }, .write_only, .rgba8_unorm, .tvdim_2d),
            //gpu.bufferEntry(6, .{ .fragment = true }, .uniform, false, 0), //image data to upload
            //gpu.bufferEntry(7, .{ .compute = true }, .read_only_storage, false, 0), //image to upload data
            //gpu.bufferEntry(8, .{ .compute = true, .vertex = true, .fragment = true }, .read_only_storage, false, 0), //image on atlas data
            gpu.textureEntry(9, .{ .fragment = true }, .float, .tvdim_2d, false),
            //gpu.bufferEntry(10, .{ .compute = true }, .uniform, false, 0),
            gpu.bufferEntry(11, .{ .fragment = true }, .uniform, false, 0),
            gpu.bufferEntry(12, .{ .fragment = true }, .uniform, false, 0),
        });
        defer gfx_cntx.releaseResource(bind_group_layout);

        //const compute_pipeline_layout = gfx_cntx.createPipelineLayout(&.{bind_group_layout});
        //defer gfx_cntx.releaseResource(compute_pipeline_layout);

        //const compute_pipeline = compute_pipeline: {
        //    const cs_module = gpu.createWgslShaderModule(gfx_cntx.device, @embedFile("compute.wgsl"), "cs");
        //    defer cs_module.release();
        //
        //    const pipeline_descriptor = wgpu.ComputePipelineDescriptor{
        //        .compute = wgpu.ProgrammableStageDescriptor{
        //            .entry_point = "main",
        //            .module = cs_module,
        //        },
        //    };
        //    break :compute_pipeline gfx_cntx.createComputePipeline(compute_pipeline_layout, pipeline_descriptor);
        //};

        const pipeline_layout = gfx_cntx.createPipelineLayout(&.{bind_group_layout});
        defer gfx_cntx.releaseResource(pipeline_layout);

        const pipeline = pipeline: {
            const vs_module = gpu.createWgslShaderModule(gfx_cntx.device, @embedFile("vertex.wgsl"), "vs");
            defer vs_module.release();

            const fs_module = gpu.createWgslShaderModule(gfx_cntx.device, @embedFile("fragment.wgsl"), "fs");
            defer fs_module.release();

            self.blend = .{
                .color = .{
                    .operation = .add,
                    .src_factor = .one,
                    .dst_factor = .one_minus_src_alpha,
                },
                .alpha = .{},
            };

            const color_targets = [_]wgpu.ColorTargetState{.{
                .format = gpu.GraphicsContext.swapchain_format,
                .blend = &self.blend,
            }};

            const vertex_attributes = [_]wgpu.VertexAttribute{
                .{ .format = .float32x3, .offset = @offsetOf(Vertex, "position"), .shader_location = 0 },
                .{ .format = .float32x3, .offset = @offsetOf(Vertex, "color"), .shader_location = 1 },
                .{ .format = .float32x2, .offset = @offsetOf(Vertex, "uv"), .shader_location = 2 },
            };

            const instance_attributes = [_]wgpu.VertexAttribute{
                .{ .format = .float32x2, .offset = @offsetOf(InstanceData, "pos"), .shader_location = 3 },
                .{ .format = .float32x2, .offset = @offsetOf(InstanceData, "dims"), .shader_location = 4 },
                .{ .format = .float32, .offset = @offsetOf(InstanceData, "depth"), .shader_location = 5 },
                .{ .format = .uint32, .offset = @offsetOf(InstanceData, "tex"), .shader_location = 6 },
                .{ .format = .uint32, .offset = @offsetOf(InstanceData, "col"), .shader_location = 7 },
            };

            const vertex_buffers = [_]wgpu.VertexBufferLayout{
                .{
                    .array_stride = @sizeOf(Vertex),
                    .attribute_count = vertex_attributes.len,
                    .attributes = &vertex_attributes,
                },
                .{
                    .array_stride = @sizeOf(InstanceData),
                    .step_mode = .instance, //MUST DO THIS!!!!!!
                    .attribute_count = instance_attributes.len,
                    .attributes = &instance_attributes,
                },
            };

            const pipeline_descriptor = wgpu.RenderPipelineDescriptor{
                .vertex = wgpu.VertexState{
                    .module = vs_module,
                    .entry_point = "main",
                    .buffer_count = vertex_buffers.len,
                    .buffers = &vertex_buffers,
                },
                .primitive = wgpu.PrimitiveState{
                    .front_face = .ccw,
                    .cull_mode = .none,
                    .topology = .triangle_list,
                },
                .depth_stencil = null,
                .fragment = &wgpu.FragmentState{
                    .module = fs_module,
                    .entry_point = "main",
                    .target_count = color_targets.len,
                    .targets = &color_targets,
                },
            };

            break :pipeline gfx_cntx.createRenderPipeline(pipeline_layout, pipeline_descriptor);
        };

        //create vertex buffer
        const vertex_buffer = gfx_cntx.createBuffer(.{
            .usage = .{ .copy_dst = true, .vertex = true },
            .size = 4 * @sizeOf(Vertex),
        });
        const vertex_data = [_]Vertex{
            .{
                .position = [3]f32{ 0.0, 0.0, 0.0 }, //lower left
                .color = [3]f32{ 1.0, 0.0, 0.0 },
                .uv = [2]f32{ 0.0, 1.0 },
            },
            .{
                .position = [3]f32{ 0.0, 1.0, 0.0 }, //upper left
                .color = [3]f32{ 1.0, 1.0, 1.0 },
                .uv = [2]f32{ 0.0, 0.0 },
            },
            .{
                .position = [3]f32{ 1.0, 0.0, 0.0 }, //lower right
                .color = [3]f32{ 1.0, 1.0, 1.0 },
                .uv = [2]f32{ 1.0, 1.0 },
            },
            .{
                .position = [3]f32{ 1.0, 1.0, 0.0 },
                .color = [3]f32{ 1.0, 1.0, 1.0 },
                .uv = [2]f32{ 1.0, 0.0 },
            },
        };
        gfx_cntx.queue.writeBuffer(gfx_cntx.lookupResource(vertex_buffer).?, 0, Vertex, vertex_data[0..]);

        //create index buffer
        const index_buffer = gfx_cntx.createBuffer(.{
            .usage = .{ .copy_dst = true, .index = true },
            .size = 6 * @sizeOf(u32),
        });
        const index_data = [_]u32{
            0, 1, 2,
            1, 3, 2,
        };
        gfx_cntx.queue.writeBuffer(gfx_cntx.lookupResource(index_buffer).?, 0, u32, index_data[0..]);

        //create instance buffer
        const instance_buffer = gfx_cntx.createBuffer(.{
            .usage = .{ .copy_dst = true, .vertex = true },
            .size = instance_buffer_size * @sizeOf(InstanceData),
        });

        //const raw_uploads_buffer = gfx_cntx.createBuffer(.{
        //    .label = "Raw Uploads Buffer",
        //    .usage = .{
        //        .copy_dst = true,
        //        .copy_src = true,
        //        //.uniform = true,
        //    },
        //    .size = raw_uploads_buffer_size,
        //});

        const images_data = gfx_cntx.createBuffer(.{
            .label = "Images Data",
            .usage = .{
                .uniform = true,
                .copy_dst = true,
            },
            .size = max_no_images * @sizeOf(AtlasRef),
        });

        const texture_atlas = gfx_cntx.createTexture(.{
            .label = "Texture Atlas",
            .size = .{
                .width = @intCast(atlas_size.x),
                .height = @intCast(atlas_size.y),
                .depth_or_array_layers = 1,
            },
            .format = .rgba8_unorm,
            .mip_level_count = 1,
            .usage = .{
                .texture_binding = true,
                //.storage_binding = true,
                .copy_dst = true,
            },
        });

        const atlas_read_view = gfx_cntx.createTextureView(
            texture_atlas,
            .{
                //.format = .rgba8_unorm,
            },
        );

        const texture_atlas_header_handle = gfx_cntx.createBuffer(.{
            .usage = .{
                .uniform = true,
                .copy_dst = true,
            },
            .size = @sizeOf(TextureAtlas),
        });

        const texture_atlas_header: TextureAtlas = .{
            .size = .implCast(atlas_size),
        };

        gfx_cntx.queue.writeBuffer(
            gfx_cntx.lookupResource(texture_atlas_header_handle).?,
            0,
            TextureAtlas,
            ([_]TextureAtlas{texture_atlas_header})[0..1],
        );

        const width = 256;
        const height = 144;
        const image: [width * height]Color = [1]Color{Color.blank} ** (width * height);

        //create texture
        const texture = gfx_cntx.createTexture(.{
            .usage = .{ .texture_binding = true, .copy_dst = true },
            .size = .{
                .width = width,
                .height = height,
                .depth_or_array_layers = 1,
            },
            .format = gpu.imageInfoToTextureFormat(
                4,
                1,
                false,
            ),
            .mip_level_count = 1,
        });
        const texture_view = gfx_cntx.createTextureView(texture, .{
            .format = .rgba8_unorm,
        });

        gfx_cntx.queue.writeTexture(
            .{ .texture = gfx_cntx.lookupResource(texture).? },
            .{ .bytes_per_row = width * @sizeOf(Color), .rows_per_image = height },
            .{ .width = width, .height = height },
            Color,
            image[0..],
        );

        const sampler = gfx_cntx.createSampler(.{
            .mag_filter = .linear,
            .min_filter = .linear,
        });

        const bind_group = gfx_cntx.createBindGroup(bind_group_layout, &.{
            .{ .binding = 0, .buffer_handle = gfx_cntx.uniforms.buffer, .offset = 0, .size = 512 },
            .{ .binding = 1, .texture_view_handle = texture_view },
            .{ .binding = 2, .sampler_handle = sampler },
            //.{ .binding = 5, .texture_view_handle = atlas_write_view },
            //.{ .binding = 6, .buffer_handle = raw_uploads_buffer, .offset = 0, .size = raw_uploads_buffer_size },
            //.{ .binding = 7, .buffer_handle = uploads_data, .offset = 0, .size = max_no_images_per_frame * @sizeOf(ImageUpload) },
            //.{ .binding = 8, .buffer_handle = images_data, .offset = 0, .size = max_no_images * @sizeOf(ImageAtlasRef) },
            .{ .binding = 9, .texture_view_handle = atlas_read_view },
            //.{ .binding = 10, .buffer_handle = upload_data, .offset = 0, .size = @sizeOf(ImageUpload) },
            .{ .binding = 11, .buffer_handle = images_data, .offset = 0, .size = max_no_images * @sizeOf(AtlasRef) },
            .{ .binding = 12, .buffer_handle = texture_atlas_header_handle, .offset = 0, .size = @sizeOf(TextureAtlas) },
        });

        self.gfx_cntx = gfx_cntx;

        //.compute_pipeline_handle = compute_pipeline,
        self.pipeline = pipeline;
        self.bind_group = bind_group;

        self.vertex_buffer = vertex_buffer;
        self.index_buffer = index_buffer;

        self.texture = texture;
        self.texture_view = texture_view;
        self.sampler = sampler;

        self.window = window;

        self.instance_buffer = instance_buffer;
        self.instance_data = undefined;
        self.no_instances = 0;

        //self.raw_uploads_handle = raw_uploads_buffer;
        //self.raw_uploads_data = undefined;
        self.uploads_data = undefined;
        self.upload = .{
            .no = 0,
            .size = 0,
        };

        self.images_handle = images_data;
        self.images = undefined;

        self.texture_atlas = texture_atlas;

        self.texture_atlas_header_handle = texture_atlas_header_handle;
        self.texture_atlas_header = texture_atlas_header;
    }

    pub fn deinit(state: *Graphics, allc: std.mem.Allocator) void {
        state.gfx_cntx.destroy(allc);
        state.* = undefined;
    }

    fn loadImage(gfx_cntx: *gpu.GraphicsContext, name: [:0]const u8) !gpu.TextureViewHandle {
        var _image = try stbi.Image.loadFromFile(name, 4);
        defer _image.deinit();

        const _texture = gfx_cntx.createTexture(.{
            .usage = .{ .texture_binding = true, .copy_dst = true },
            .size = .{ .width = _image.width, .height = _image.height, .depth_or_array_layers = 1 },
            .format = gpu.imageInfoToTextureFormat(
                _image.num_components,
                _image.bytes_per_component,
                _image.is_hdr,
            ),
            .mip_level_count = 1,
        });

        const _texture_view = gfx_cntx.createTextureView(_texture, .{});

        gfx_cntx.queue.writeTexture(
            .{ .texture = gfx_cntx.lookupResource(_texture).? },
            .{
                .bytes_per_row = _image.bytes_per_row,
                .rows_per_image = _image.height,
            },
            .{ .width = _image.width, .height = _image.height },
            u8,
            _image.data,
        );

        return _texture_view;
    }

    pub fn draw(render: *Graphics, images: []Image) void {
        std.log.debug("drawing", .{});
        for (render.uploads_data[0..render.upload.no]) |upload| {
            std.log.debug("uploading image with ref: {}", .{upload.image_ref.ref});
            render.images[upload.image_ref.ref] = upload.atlas_ref;
        }
        defer render.upload.no = 0;

        const gfx_cntx = render.gfx_cntx;

        const back_buffer_view = gfx_cntx.swapchain.getCurrentTextureView();
        defer back_buffer_view.release();

        const _window_size = render.window.getSize();
        const window_size: Vector2 = .init(@floatFromInt(_window_size[0]), @floatFromInt(_window_size[1]));
        const ratio = 9.0 / 16.0;
        //should flip to prioritizing the y, more normal that way around
        var canvas_size: Vector2 = .init(window_size.x, ratio * window_size.x);
        //y too big if keep the x
        if (canvas_size.y > window_size.y) {
            canvas_size.x = window_size.y / ratio;
            canvas_size.y = window_size.y;
        }

        const scale = canvas_size.div(window_size);

        const view: math.Mat = .{
            .{ scale.x, 0, 0, 0 },
            .{ 0, scale.y, 0, 0 },
            .{ 0, 0, 1, 0 },
            .{ 0, 0, 0, 1 },
        };

        gfx_cntx.queue.writeBuffer(
            gfx_cntx.lookupResource(render.images_handle).?,
            0,
            AtlasRef,
            render.images[0..],
        );

        const atlas = gfx_cntx.lookupResource(render.texture_atlas).?;
        for (render.uploads_data[0..render.upload.no]) |upload| {
            const image = images[upload.image_ref.ref];
            std.debug.assert(image.width == upload.atlas_ref.size.x and image.height == upload.atlas_ref.size.y);
            std.log.debug("writing: {}", .{upload.image_ref.ref});
            gfx_cntx.queue.writeTexture(
                .{
                    .texture = atlas,
                    .origin = .{
                        .x = @intCast(upload.atlas_ref.pos.x),
                        .y = @intCast(upload.atlas_ref.pos.y),
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

        gfx_cntx.queue.writeBuffer(
            gfx_cntx.lookupResource(render.instance_buffer).?,
            0,
            InstanceData,
            render.instance_data[0..],
        );

        const commands = commands: {
            const encoder = gfx_cntx.device.createCommandEncoder(null);
            defer encoder.release();

            pass: {
                const vb_info = gfx_cntx.lookupResourceInfo(render.vertex_buffer) orelse break :pass;
                const ib_info = gfx_cntx.lookupResourceInfo(render.index_buffer) orelse break :pass;
                const instb_info = gfx_cntx.lookupResourceInfo(render.instance_buffer) orelse break :pass;
                const pipeline = gfx_cntx.lookupResource(render.pipeline) orelse break :pass;
                const bind_group = gfx_cntx.lookupResource(render.bind_group) orelse break :pass;

                const color_attachments = [_]wgpu.RenderPassColorAttachment{.{
                    .view = back_buffer_view,
                    .load_op = .clear,
                    .store_op = .store,
                    .clear_value = .{
                        .r = 0,
                        .g = 255,
                        .b = 0,
                        .a = 255,
                    },
                }};
                const render_pass_info = wgpu.RenderPassDescriptor{
                    .color_attachment_count = color_attachments.len,
                    .color_attachments = &color_attachments,
                    .depth_stencil_attachment = null,
                };

                const pass = encoder.beginRenderPass(render_pass_info);
                defer {
                    pass.end();
                    pass.release();
                }

                pass.setVertexBuffer(0, vb_info.gpuobj.?, 0, vb_info.size);
                pass.setVertexBuffer(1, instb_info.gpuobj.?, 0, instb_info.size);
                pass.setIndexBuffer(ib_info.gpuobj.?, .uint32, 0, ib_info.size);

                pass.setPipeline(pipeline);

                // Draw
                {
                    const mem = gfx_cntx.uniformsAllocate(math.Mat, 1);
                    mem.slice[0] = math.transpose(view);
                    pass.setBindGroup(0, bind_group, &.{mem.offset});
                    pass.drawIndexed(6, render.no_instances, 0, 0, 0);
                }
            }
            {
                const color_attachments = [_]wgpu.RenderPassColorAttachment{.{
                    .view = back_buffer_view,
                    .load_op = .load,
                    .store_op = .store,
                }};
                const render_pass_info = wgpu.RenderPassDescriptor{
                    .color_attachment_count = color_attachments.len,
                    .color_attachments = &color_attachments,
                };
                const pass = encoder.beginRenderPass(render_pass_info);
                defer {
                    pass.end();
                    pass.release();
                }
            }

            break :commands encoder.finish(null);
        };
        defer commands.release();
        gfx_cntx.submit(&.{commands});

        //swaps frame buffers
        if (gfx_cntx.present() == .swap_chain_resized) {}
    }

    pub fn addInstance(gfx: *Graphics, instance: InstanceData) u32 {
        const id = gfx.no_instances;
        gfx.instance_data[id] = instance;
        gfx.no_instances += 1;
        return id;
    }
};

pub const ScreenState = struct {
    width: u16,
    height: u16,
    image: [world_size.x * world_size.y]Color,

    pub fn getSize(self: *const ScreenState) Vector2I32 {
        return .{ .x = self.width, .y = self.height };
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

const Vertex = struct {
    position: [3]f32,
    color: [3]f32,
    uv: [2]f32,
};
