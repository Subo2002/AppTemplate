const std = @import("std");
const Io = std.Io;
const TrueType = @import("TrueType");
const zglfw = @import("zglfw");
const zopengl = @import("zopengl");

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

    try zopengl.loadCoreProfile(GLFW.getProcAddress, 4, 0);
    const gl = zopengl.wrapper;
    gl.clearBufferfv(.color, 0, &.{ 0.2, 0.4, 0.8, 1.0 });

    const arena = init.arena.allocator();
    _ = arena;

    while (!window.shouldClose()) {
        glfw.pollEvents();

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
