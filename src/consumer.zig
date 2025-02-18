const std = @import("std");
const core = @import("./core.zig");

pub fn CollectArrayList(comptime T: type) type {
    return struct {
        pub const TypeSet = core.Consumer(T, @This());
        const Self = @This();

        accumulator: std.ArrayList(T),

        pub inline fn init(accumulator: std.ArrayList(T)) TypeSet.Context {
            return .{ .accumulator = accumulator };
        }

        pub fn next(in: TypeSet.InUnit) TypeSet.OutUnit {
            var a = in.ctx.accumulator;
            return switch (in.rslt) {
                .done => TypeSet.OutUnit.done(in.ctx),
                .again => TypeSet.OutUnit.again(in.ctx),
                .step => |v| {
                    a.append(v) catch return TypeSet.OutUnit.done(in.ctx);
                    return TypeSet.OutUnit.again(init(a));
                },
            };
        }

        pub inline fn result(self: Self) std.ArrayList(T) {
            return self.accumulator;
        }
    };
}

pub fn CollectSlice(comptime T: type) type {
    return struct {
        pub const TypeSet = core.Consumer(T, @This());
        const Self = @This();

        accumulator: []T,
        pos: usize,

        pub inline fn init(accumulator: []T) TypeSet.Context {
            return _init(accumulator, 0);
        }
        inline fn _init(accumulator: []T, pos: usize) TypeSet.Context {
            return .{ .accumulator = accumulator, .pos = pos };
        }

        pub fn next(in: TypeSet.InUnit) TypeSet.OutUnit {
            const a = in.ctx.accumulator;
            const p = if (in.ctx.pos >= a.len) 0 else in.ctx.pos;

            return switch (in.rslt) {
                .done => TypeSet.OutUnit.done(in.ctx),
                .again => TypeSet.OutUnit.again(in.ctx),
                .step => |v| {
                    a[p] = v;
                    if (p + 1 >= a.len) {
                        return TypeSet.OutUnit.done(_init(a, p + 1));
                    } else {
                        return TypeSet.OutUnit.again(_init(a, p + 1));
                    }
                },
            };
        }

        pub inline fn result(self: Self) []T {
            return self.accumulator[0..self.pos];
        }
    };
}

pub fn CollectWriter(comptime W: type, comptime T: type) type {
    const param_info = core.ParamType.Describe(T);

    return struct {
        pub const TypeSet = core.Consumer(T, @This());
        const Self = @This();

        accumulator: W,

        pub inline fn init(accumulator: W) TypeSet.Context {
            return .{ .accumulator = accumulator };
        }

        pub fn next(in: TypeSet.InUnit) TypeSet.OutUnit {
            const a = in.ctx.accumulator;

            return switch (in.rslt) {
                .done => TypeSet.OutUnit.done(in.ctx),
                .again => TypeSet.OutUnit.again(in.ctx),
                .step => |v| {
                    _ = switch (param_info.pointer) {
                        .one => a.write(@constCast(v).*) catch null,
                        .slice => a.writeAll(@constCast(v)) catch null,
                        .none => a.write(v) catch null,
                    };
                    return TypeSet.OutUnit.again(init(a));
                },
            };
        }

        pub inline fn result(self: Self) W {
            return self.accumulator;
        }
    };
}

pub fn ReducerFn(comptime R: type, comptime T: type) type {
    return fn (R, T) R;
}

pub fn Fold(comptime T: type, comptime R: type, comptime predicate: ReducerFn(R, T)) type {
    return struct {
        pub const TypeSet = core.Consumer(T, @This());
        const Self = @This();

        accumulator: R,

        pub inline fn init(accumulator: R) TypeSet.Context {
            return .{ .accumulator = accumulator };
        }

        pub fn next(in: TypeSet.InUnit) TypeSet.OutUnit {
            const a = in.ctx.accumulator;
            return switch (in.rslt) {
                .done => TypeSet.OutUnit.done(in.ctx),
                .again => TypeSet.OutUnit.again(in.ctx),
                .step => |v| TypeSet.OutUnit.again(init(p(a, v))),
            };
        }

        inline fn p(a: R, v: TypeSet.Input) R {
            return @call(std.builtin.CallModifier.always_inline, predicate, .{ a, v });
        }

        pub inline fn result(self: Self) R {
            return self.accumulator;
        }
    };
}

pub fn ForEach(comptime T: type, comptime S: type, comptime predicate: anytype) type {
    const self_mode = core.StateType.callMode(@TypeOf(predicate), S);
    const ret_info = core.ReturnType.Describe(@TypeOf(predicate));
    const error_union = ret_info.error_union;

    return struct {
        pub const TypeSet = core.Consumer(T, @This());
        const Self = @This();

        state: S,

        pub inline fn init(state: S) TypeSet.Context {
            return .{ .state = state };
        }

        pub fn next(in: TypeSet.InUnit) TypeSet.OutUnit {
            var s = in.ctx.state;
            return switch (in.rslt) {
                .done => TypeSet.OutUnit.done(in.ctx),
                .again => TypeSet.OutUnit.again(in.ctx),
                .step => |v| if (p(&s, v)) |new_s| TypeSet.OutUnit.again(init(new_s)) else TypeSet.OutUnit.done(in.ctx),
            };
        }

        inline fn p(s: *S, v: TypeSet.Input) ?S {
            return switch (self_mode) {
                .none => switch (error_union) {
                    .set => @call(.always_inline, predicate, .{ s.*, v }) catch null,
                    .none => @call(.always_inline, predicate, .{ s.*, v }),
                },
                .deref => switch (error_union) {
                    .set => @call(.always_inline, predicate, .{ s.*.*, v }) catch null,
                    .none => @call(.always_inline, predicate, .{ s.*.*, v }),
                },
                .ptr => switch (error_union) {
                    .set => @call(.always_inline, predicate, .{ s, v }) catch null,
                    .none => @call(.always_inline, predicate, .{ s, v }),
                },
            };
        }

        pub inline fn result(self: Self) S {
            return self.state;
        }
    };
}

pub fn One(comptime T: type) type {
    return struct {
        pub const TypeSet = core.Consumer(T, @This());
        const Self = @This();

        accumulator: ?T,

        pub inline fn init() TypeSet.Context {
            return _init(null);
        }
        inline fn _init(accumulator: ?T) TypeSet.Context {
            return .{ .accumulator = accumulator };
        }

        pub fn next(in: TypeSet.InUnit) TypeSet.OutUnit {
            return switch (in.rslt) {
                .done => TypeSet.OutUnit.done(_init(null)),
                .again => TypeSet.OutUnit.again(_init(null)),
                .step => |v| TypeSet.OutUnit.done(_init(v)),
            };
        }

        pub inline fn result(self: Self) ?T {
            return self.accumulator;
        }
    };
}

pub fn Reduce(comptime T: type, comptime predicate: ReducerFn(T, T)) type {
    return struct {
        pub const TypeSet = core.Consumer(T, @This());
        const Self = @This();
        const State = union(enum) {
            tail: T,
            head,
        };

        accumulator: State,

        pub inline fn init() TypeSet.Context {
            return _init(.head);
        }
        pub inline fn initFold(state: T) TypeSet.Context {
            return _init(.{ .tail = state });
        }
        inline fn _init(accumulator: State) TypeSet.Context {
            return .{ .accumulator = accumulator };
        }

        pub fn next(in: TypeSet.InUnit) TypeSet.OutUnit {
            const a = in.ctx.accumulator;
            return switch (a) {
                .tail => |r| {
                    return switch (in.rslt) {
                        .done => TypeSet.OutUnit.done(in.ctx),
                        .again => TypeSet.OutUnit.again(in.ctx),
                        .step => |v| TypeSet.OutUnit.again(_init(.{ .tail = p(r, v) })),
                    };
                },
                .head => {
                    return switch (in.rslt) {
                        .done => TypeSet.OutUnit.done(in.ctx),
                        .again => TypeSet.OutUnit.again(in.ctx),
                        .step => |v| TypeSet.OutUnit.again(_init(.{ .tail = v })),
                    };
                },
            };
        }

        inline fn p(a: T, v: TypeSet.Input) T {
            return @call(std.builtin.CallModifier.always_inline, predicate, .{ a, v });
        }

        pub inline fn result(self: Self) ?T {
            return switch (self.accumulator) {
                .tail => |r| return r,
                .head => return null,
            };
        }
    };
}
