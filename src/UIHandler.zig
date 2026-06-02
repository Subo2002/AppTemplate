const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const Lib = @import("lib.zig");
const Vector2U16 = Lib.Vector2U16;
const Vector2I16 = Lib.Vector2I16;
const Render = @import("Render.zig").Render;
const TextHandler = @import("TextHandler.zig");

//TODO:
// 1. breadth-first iterator (probs also make fn to compute them all so can iterate through them in passes)
// 2. recursive drop to finalize values of boxes for contexts (maybe do in render)
// 3. render cntxs
//      i. 1 - depth =: z = node counter while iterating child first (maybe seperate depth pass) -> move depth in to the boxes
//      ii. Also need to cut children boxes who are too large to fit in the parent (maybe seperate culling pass) -> do in the boxes

pub const UIHandler = @This();

pub const max_contexts = 100;
boxes: [max_contexts]Box,
flags: [max_contexts]Flags,
links: [max_contexts]Links,
limit: u15,
count: u15,

pub fn init(self: *UIHandler) void {
    self.limit = 0;
    self.count = 0;
}

//WARNING: NOT INITIALIZED
pub fn takeFreeCntx(self: *UIHandler) !Cntx {
    if (self.count == max_contexts) return error.outOfSpace;

    if (self.limit == self.count) {
        defer self.limit += 1;
        defer self.count += 1;
        self.flags[self.limit].free = false;
        return .init(self.limit);
    }

    for (self.flags[0..self.limit], 0..) |flag, id| {
        if (!flag.free) continue;
        defer self.count += 1;
        self.flags[id].free = false;
        return .init(@intCast(id));
    }
    unreachable;
}

//should rename as really inits the data of the cntx
fn clearCntx(self: *UIHandler, cntx: Cntx) void {
    self.boxes[cntx.id()] = .empty;
    self.flags[cntx.id()] = .empty;
    const link = &self.links[cntx.id()];
    link.* = .empty;
    link.nextSib = cntx;
    link.prevSib = cntx;
}

fn clear(self: *UIHandler) void {
    //just need to set them to free
    @memset(self.flags[0..self.limit], .empty);
}

pub fn freeCntx(self: *UIHandler, cntx: Cntx) void {
    self.flags[cntx.id.?] = true;
    if (cntx.id.? == self.limit) self.limit -= 1;
    self.count -= 1;
}

pub fn initCntx(self: *UIHandler) !Cntx {
    const cntx = try self.takeFreeCntx();
    self.clearCntx(cntx);
    self.flags[cntx.id()].active = true;
    return cntx;
}

pub fn getbox(self: *UIHandler, cntx: Cntx) *Box {
    return &self.boxes[cntx.id()];
}

pub fn setbox(self: *UIHandler, cntx: Cntx, box: Box) void {
    self.boxes[cntx.id()] = box;
}

pub fn getLinks(self: *UIHandler, cntx: Cntx) *Links {
    return &self.links[cntx.id()];
}

pub fn padCntx(self: *UIHandler, padding: Box, cntx: Cntx) !Cntx {
    const child_box = self.getBox(cntx);
    
    //const child_box = self.getBox(cntx);
    //const padding_box = padding.asrelc();
    //padding_box.lift(child_box);
    //padding_box.flip(child_box);

    //const padding_cntx = try self.initCntx();
    //self.setBox(padding_cntx, padding_box);
    //self.linkCntxs(padding_cntx, cntx);
    //return padding_cntx;
}

pub fn linkCntxs(self: *UIHandler, parent_cntx: Cntx, child_cntx: Cntx) void {
    const parent = self.getLinks(parent_cntx);
    const cur_first_child_cntx = if (parent.child.back) |c| c else child_cntx;
    const cur_first_child = self.getLinks(cur_first_child_cntx);
    const cur_last_child_cntx = cur_first_child.prevSib;
    const cur_last_child = self.getLinks(cur_last_child_cntx); //the list should always be initialized as initialized in clearCntx
    const child = self.getLinks(child_cntx);
    const child_last_sib_cntx = child.prevSib;
    const child_last_sib = self.getLinks(child_last_sib_cntx);
    cur_first_child.prevSib = child_last_sib_cntx;
    child_last_sib.nextSib = cur_first_child;
    child.prevSib = cur_last_child_cntx;
    cur_last_child.nextSib = child_cntx;
    child.parent = parent;
}

pub fn makeText(self: *UIHandler, text_info: TextHandler.TextInfo, padding: Box, text: []const u8) !Cntx {
    const text_cntx = try self.initCntx();
    const text_width = TextHandler.compTextLength(text_info, text);
    self.setbox(text_cntx, .init(.empty, .empty, .initFixed(text_info.pixel_height), .initFixed(text_width)));
    return self.padCntx(padding, text_cntx);
}

//recursively drops a parents box info in to it's children
pub fn dropRecursive(self: *UIHandler, cntx: Cntx) void {
    
}

pub fn renderCntxs(self: *UIHandler, render: *Render) void {
    //iterate down the tree, filling explicit info in children
    //if position not set then set it to 0 relative to the parent
    //then if size explicit can just offset by that to give position to sibling
    //if size is unknown
    var cntx: Cntx = .init(0); //assuming is the root
    while (!cntx.isempty()) {}
}

pub const Cntx = struct {
    pub const empty: Cntx = .{ .index = null };

    index: ?u15,

    pub fn init(index: u15) Cntx {
        return .{ .index = index };
    }

    pub fn id(self: Cntx) u15 {
        return self.index.?;
    }

    pub fn isempty(self: Cntx) bool {
        return self.index == null;
    }
};

pub const Deps = packed struct(u2) {
    parent: bool,
    child: bool,
    //prev_sib: bool,

    pub fn comp(box: Box) Deps {
        return .{
            .parent = box.flags.contains(.rel_p),
            .child = box.flags.contains(.rel_c),
            //.prev

        };
    }
};

pub const ValueKind = enum(u2) {
    none,
    rel_p,
    rel_c,
    fixed,
};

pub const Value = union(ValueKind) {
    pub const empty: Value = .{ .none = .{} };

    none: void,
    rel_p: i16,
    rel_c: i16,
    fixed: i16, //bit silly as position is always u16, but for casting a fixed box in a relative box

    pub fn initFixed(value: i16) Value {
        return .{ .fixed = value };
    }

    //lift the child's value in the parent
    pub fn lift(parent: *Value, child: Value) void {
        if (parent != .rel_c) return;
        if (child == .rel_p) unreachable;
        if (child != .fixed) return;
        parent.* = .{ .fixed = parent.rel_c + child.fixed };
    }

    //drops the parents value in the child
    pub fn drop(child: *Value, parent: Value) void {
        if (child != .rel_p) return;
        if (parent == .rel_c) unreachable;
        if (parent != .fixed) return;
        child.* = .{ .fixed = child.rel_p + parent.fixed };
    }

    //swaps the value dependancy around
    pub fn flip(parent: *Value, child: *Value) void {
        if (parent != .rel_c) return;
        if (child != .none) return;
        child.* = .{ .rel_p = -parent.rel_c };
        parent.* = .{ .none = .{} };
    }

    pub fn asrelp(a: Value) Value {
        return .{ .rel_p = a.fixed };
    }

    pub fn asrelc(a: Value) Value {
        return .{ .rel_c = a.fixed };
    }
};

pub const Box = struct {
    pub const empty: Box = .{};

    x: Value = .empty,
    y: Value = .empty,
    z: Value = .empty,
    w: Value = .empty,
    h: Value = .empty,

    pub fn init(x: Value, y: Value, w: Value, h: Value) Box {
        return .{ .x = x, .y = y, .w = w, .h = h };
    }

    pub fn initFixed(x: i16, y: i16, w: i16, h: i16) Box {
        return .init(.initFixed(x), .initFixed(y), .initFixed(w), .initFixed(h));
    }

    pub fn lift(parent: *Box, child: Box) void {
        parent.x.lift(child.x);
        parent.y.lift(child.y);
        parent.w.lift(child.w);
        parent.h.lift(child.h);
    }

    pub fn flip(parent: *Box, child: *Box) void {
        parent.x.flip(&child.x);
        parent.y.flip(&child.y);
        parent.w.flip(&child.w);
        parent.h.flip(&child.h);
    }

    pub fn drop(child: *Box, parent: Box) void {
        child.x.drop(parent.x);
        child.y.drop(parent.y);
        child.w.drop(parent.w);
        child.h.drop(parent.h);
    }

    pub fn asrelp(a: Box) Box {
        return .init(a.x.asrelp(), a.y.asrelp(), a.w.asrelp(), a.h.asrelp());
    }

    pub fn asrelc(a: Box) Box {
        return .init(a.x.asrelc(), a.y.asrelc(), a.w.asrelc(), a.h.relc());
    }

    pub fn contains(self: Box, flag: ValueKind) bool {
        return self.x == flag or self.y == flag or self.w == flag or self.h == flag;
    }
};

pub const BoxDiff = struct {
    x0: Num = .empty,
    y0: Num = .empty,
    x1: Num = .empty,
    y1: Num = .empty,

    //pub fn add(a: Box, diff: BoxDiff, b: Box) Box {
    //    //a.pos.x unknown then just return b.pos.x,
    //    //a.pos.x known, diff.x0 known, return a.pos.x + diff.x0 + b.pos.x <- the b.pos.x
    //}

    pub fn width(b: BoxDiff) Num {
        return .add(b.x0, b.x1);
    }

    pub fn uwidth(b: BoxDiff) u15 {
        return b.x0.unwrap() + b.x1.unwrap();
    }

    pub fn height(b: BoxDiff) Num {
        return .add(b.y0, b.y1);
    }

    pub fn uheight(b: BoxDiff) u15 {
        return b.y0.unwrap() + b.y1.unwrap();
    }
};

pub const Num = struct {
    pub const empty: Num = .{ .back = null };

    back: ?u15,

    pub fn init(back: ?u15) Num {
        return .{ .back = back };
    }

    pub fn wrap(value: u15) Num {
        return .{ .back = value };
    }

    //pub fn offsetBy(a: Num, offset: Num) Num {
    //
    // }

    pub fn isempty(num: Num) bool {
        return num.back == null;
    }

    pub fn unwrap(num: Num) u15 {
        return num.back;
    }

    pub fn add(a: Num, b: Num) Num {
        if (a.isempty() or b.isempty()) return .empty;
        return .wrap(a.unwrap() + b.unwrap());
    }
};

pub const Links = struct {
    pub const empty: Links = .{};

    parent: Cntx = .empty,
    child: Cntx = .empty,
    nextSib: Cntx = .empty,
    prevSib: Cntx = .empty,

    pub fn compDepthFirst(root: Cntx, list: []const Links, gpa: Allocator, ta: Allocator) []Cntx {}
};

pub const Flags = packed struct {
    pub const empty: Flags = .{};

    free: bool = true,
    active: bool = false,
    size_set: bool = false,
    pos_set: bool = false,
};
