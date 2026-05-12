@group(0) @binding(1) var image: texture_2d<f32>;
@group(0) @binding(2) var image_sampler: sampler;
//@group(0) @binding(3) var tex: texture_2d<f32>;
//@group(0) @binding(4) var tex2: texture_2d<f32>;
@group(0) @binding(9) var atlas: texture_2d<f32>;
@group(0) @binding(11) var<uniform> images: array<AtlasRef, max_no_images>;
@group(0) @binding(12) var<uniform> texture_atlas_header: TextureAtlas;
//WARNING: make sure this agrees with the cpu side code
const max_no_images: u32 = 256;

struct VertexOut {
    @builtin(position) position_clip: vec4<f32>,
    @location(0) @interpolate(linear) uv: vec2<f32>,
    @location(1) @interpolate(flat) tex: u32,
    @location(2) @interpolate(linear) pos: vec3<f32>,
    @location(3) @interpolate(flat) col: vec4<f32>,
}

struct AtlasRef {
    size: vec2<i32>,
    pad1: vec2<i32>,
    start: vec2<i32>,
    pad2: vec2<i32>,
}

struct TextureAtlas {
    size: vec2<u32>,
}

@fragment fn main(v: VertexOut) -> @location(0) vec4<f32> {
    let atlas_size: vec2<f32> = vec2(f32(texture_atlas_header.size.x), f32(texture_atlas_header.size.y));
    var col = vec4(1.0, 1.0, 1.0, 1.0);
    let tex_ref: AtlasRef = images[v.tex];
    let tex_pos: vec2<f32> = vec2(f32(tex_ref.start.x), f32(tex_ref.start.y)) / atlas_size;
    let tex_size: vec2<f32> = vec2(f32(tex_ref.size.x), f32(tex_ref.size.y)) / atlas_size;
    col = textureSample(atlas, image_sampler, tex_pos + v.uv * tex_size);
    if (v.tex == 0) {
        col = v.col;
    }
    if (col.a == 0) {
        discard;
    }
    return col;
}
