@group(0) @binding(0) var<uniform> object_to_clip: mat4x4<f32>;


struct VertexIn {
    @location(0) position: vec3<f32>,
    @location(1) color: vec3<f32>,
    @location(2) uv: vec2<f32>,
}

struct InstanceData {
    @location(3) pos: vec2<f32>,
    @location(4) dims: vec2<f32>,
    @location(5) depth: f32,
    @location(6) tex: u32,
    @location(7) col: u32,
};
struct VertexOut {
    @builtin(position) position_clip: vec4<f32>, //this goes -1 to 1
    @location(0) @interpolate(linear) uv: vec2<f32>,
    @location(1) @interpolate(flat) tex: u32,
    @location(2) @interpolate(linear) pos: vec3<f32>,
    @location(3) @interpolate(flat) col: vec4<f32>,
};

//world size is 256 * 2 by 144 * 2
//window size is 1600 by 1000
@vertex fn main(in: VertexIn, inst: InstanceData) -> VertexOut {
    var output: VertexOut;

    let dims = vec3(f32(inst.dims.x), f32(inst.dims.y), 1);
    let pos = vec3(f32(inst.pos.x), f32(inst.pos.y), 0);

    var position: vec3<f32> = in.position;
    //position.x /= 1.6;
    position *= dims;
    position += pos;
    position.z = inst.depth;
    //let ndc = position / vec3(256, 144, 1);
    //output.position_clip = vec4(
    //    ndc.x * 2.0 - 1.0,
    //    ndc.y * 2.0 - 1.0,
    //    ndc.z,
    //    1.0
    //);
    output.position_clip = vec4(position / vec3(256.0 * 2, 144.0 * 2, 1.0), 1.0);

    output.uv = in.uv;
    output.tex = inst.tex;
    let col = vec4(
        f32(inst.col & 0x000000FF),
        f32((inst.col & 0x0000FF00) >> 8),
        f32((inst.col & 0x00FF0000) >> 16),
        f32((inst.col & 0xFF000000) >> 24),
    ) / f32(255);
    output.col = col;
    return output;
}
