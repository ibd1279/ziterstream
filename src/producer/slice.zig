const std = @import("std");
const core = @import("../core.zig");

/// Produce backwards successive elements from a slice.
pub fn Backwards(comptime T: type) type {
    return struct {
        pub const TypeSet = core.Producer(@This(), T);

        slice: []const T,

        pub inline fn init(slice: []const T) TypeSet.Context {
            return .{ .slice = slice };
        }

        pub inline fn next(ctx: TypeSet.Context) TypeSet.OutUnit {
            const s = ctx.slice;
            if (s.len == 0) {
                return TypeSet.OutUnit.done(init(s));
            } else {
                const end = s.len - 1;
                return TypeSet.OutUnit.step(init(s[0..end]), s[end]);
            }
        }
    };
}

/// Produce successive elements from a slice.
pub fn Forward(comptime T: type) type {
    return struct {
        pub const TypeSet = core.Producer(@This(), T);

        slice: []const T,

        pub inline fn init(slice: []const T) TypeSet.Context {
            return .{ .slice = slice };
        }

        pub inline fn next(ctx: TypeSet.Context) TypeSet.OutUnit {
            const s = ctx.slice;
            if (s.len == 0) {
                return TypeSet.OutUnit.done(init(s));
            } else {
                return TypeSet.OutUnit.step(init(s[1..]), s[0]);
            }
        }
    };
}

/// Produce elements from a slice in a random order.
///
/// Does not guarentee that each slice item is produced (at least|at most) once.
/// Produces the same number of items as are in the slice.
pub fn Random(comptime T: type) type {
    return struct {
        pub const TypeSet = core.Producer(@This(), T);

        slice: []const T,
        rand: std.Random,
        count: usize,

        pub inline fn init(slice: []const T, rand: std.Random) TypeSet.Context {
            return _init(slice, rand, slice.len);
        }
        pub inline fn _init(slice: []const T, rand: std.Random, count: usize) TypeSet.Context {
            return .{ .slice = slice, .rand = rand, .count = count };
        }

        pub inline fn next(ctx: TypeSet.Context) TypeSet.OutUnit {
            const s = ctx.slice;
            const r: std.Random = ctx.rand;
            const c = ctx.count;
            if (c == 0) {
                return TypeSet.OutUnit.done(_init(s, r, c));
            } else {
                const idx = r.uintAtMostBiased(usize, s.len - 1);
                return TypeSet.OutUnit.step(_init(s, r, c - 1), s[idx]);
            }
        }
    };
}
