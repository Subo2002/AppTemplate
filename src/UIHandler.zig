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

pub const CtxData = struct {
    box: Box,
    flags: Flags,
    links: Links,
};

pub const Box = struct {
    x: u16,
    y: u16,
    w: u16,
    h: u16,

    pub const empty: Box = .{};
};

ctxs: std.MultiArrayList(CtxData),

pub const empty: UIHandler = .{
    .ctxs = .empty,
};

//WARNING: NOT INITIALIZED
pub fn takeFreeCntx(self: *UIHandler) !Ctx {
    const index = try self.ctxs.;

}

//should rename as really inits the data of the cntx
fn clearCntx(self: *UIHandler, cntx: Ctx) void {
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

pub fn freeCntx(self: *UIHandler, cntx: Ctx) void {
    self.flags[cntx.id.?] = true;
    if (cntx.id.? == self.limit) self.limit -= 1;
    self.count -= 1;
}

pub fn initCtx(self: *UIHandler) !Ctx {
    const cntx = try self.takeFreeCntx();
    self.clearCntx(cntx);
    self.flags[cntx.id()].active = true;
    return cntx;
}

pub fn getbox(self: *UIHandler, cntx: Ctx) *Box {
    return &self.boxes[cntx.id()];
}

pub fn getFlags(self: *UIHandler, ctx: Ctx) *Flags {
    return &self.ctxs.items(.flags)[ctx.id()];
}

pub fn setbox(self: *UIHandler, cntx: Ctx, box: Box) void {
    self.boxes[cntx.id()] = box;
}

pub fn getLinks(self: *UIHandler, cntx: Ctx) *Links {
    return &self.links[cntx.id()];
}

pub fn padCntx(self: *UIHandler, padding: Box, cntx: Ctx) !Ctx {
    const child_box = self.getBox(cntx);
}

pub fn linkCntxs(self: *UIHandler, parent_cntx: Ctx, child_cntx: Ctx) void {
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

pub fn makeText(self: *UIHandler, text_info: TextHandler.TextInfo, padding: Box, text: []const u8) !Ctx {
    const text_cntx = try self.initCtx();
    const text_width = TextHandler.compTextLength(text_info, text);
    self.setbox(text_cntx, .init(.empty, .empty, .initFixed(text_info.pixel_height), .initFixed(text_width)));
    return self.padCntx(padding, text_cntx);
}

pub fn renderCntxs(self: *UIHandler, render: *Render) void {
    //iterate down the tree, filling explicit info in children
    //if position not set then set it to 0 relative to the parent
    //then if size explicit can just offset by that to give position to sibling
    //if size is unknown
    var cntx: Ctx = .init(0); //assuming is the root
    while (!cntx.isempty()) {}
}

pub const Ctx = struct {
    pub const empty: Ctx = .{ .index = null };

    index: ?u15,

    pub fn init(index: u15) Ctx {
        return .{ .index = index };
    }

    pub fn id(self: Ctx) u15 {
        return self.index.?;
    }

    pub fn isempty(self: Ctx) bool {
        return self.index == null;
    }
};

pub fn Compose(comptime kind1: TaskKind, comptime kind2: TaskKind, task1: Task(kind1), task2: Task(kind2)) Task(ComposeTaskKind(kind1, kind2)) {
    return .init(.{ task1.t, task2.t });
}

pub fn ComposeTaskKind(comptime kind1: TaskKind, comptime kind2: TaskKind) TaskKind {
    const ComposedType = .{kind1.T, kind2.T};
    const composedfn = struct {
        pub fn do(data: *const ComposedType) void {
            kind1.task(data[0]);
            kind2.task(data[1]);
        }
    };
    return .init(ComposedType, composedfn.do);
}

pub const TaskKind = struct {
    T: type,
    task: fn(*const T) void,

    pub fn init(T: type, task: *fn(*const T) void) TaskKind {
        return .{
            .T = T,
            .task = task,
        };
    }
};

pub fn Task(kind: TaskKind) type {
    return struct {
        t: kind.T,

        pub fn init(t: kind: T) Task(kind) {
            return .{ .t = t };
        }

        pub fn do(self: *const @This()) void {
            task(kind.t);
        }
    };
}

pub const OffsetTask = struct {
    ctx: *CtxData,
    from: *const CtxData,
    by: i16,

    pub fn offsetX(ctx: *CtxData, from: *const CtxData, by: i16) void {
        ctx.box.x = from.box.x + by;
    }

    pub fn doX(self: *const OffsetTask) void {
        offsetX(self.ctx, self.from, self.by);
    }
};

pub const Links = struct {
    pub const empty: Links = .{};

    parent: Ctx = .empty,
    child: Ctx = .empty,
    nextSib: Ctx = .empty,
    prevSib: Ctx = .empty,
};

pub const Flags = packed struct {
    pub const empty: Flags = .{};

    free: bool = true,
    active: bool = false,
    x_set: bool = false,
    y_set: bool = false,
    w_set: bool = false,
    h_set: bool = false,
};
