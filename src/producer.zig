const std = @import("std");
const core = @import("./core.zig");

/// Producer that always returns done.
pub const Empty = core.Empty;

/// Producer that executes application defined logic to generate values.
///
/// Takes a state that is passed as the first argument of the factory.
/// Producer that executes application defined logic to generate.
///
/// Takes a state that is passed as the first argument of the factory.
pub fn StatefulFactory(
    /// `S` is the state.
    comptime S: type,
    /// `predicate` is the function to call.
    comptime predicate: anytype,
) type {
    const self_mode = core.StateType.callMode(@TypeOf(predicate), S);
    const ret_info = core.ReturnType.Describe(@TypeOf(predicate));
    const error_union = ret_info.error_union;
    const T = switch (ret_info.pointer) {
        .one => |p| *const p,
        .slice => |p| []const p,
        .none => ret_info.base_type,
    };

    return struct {
        pub const TypeSet = core.Producer(@This(), T);

        state: S,

        pub inline fn init(state: S) TypeSet.Context {
            return .{ .state = state };
        }

        pub inline fn next(ctx: TypeSet.Context) TypeSet.OutUnit {
            var s = ctx.state;
            if (p(&s)) |out| {
                return TypeSet.OutUnit.step(init(s), out);
            } else {
                return TypeSet.OutUnit.done(init(s));
            }
        }

        pub inline fn p(s: *S) ?T {
            return switch (self_mode) {
                .none => switch (error_union) {
                    .set => @call(.always_inline, predicate, .{s.*}) orelse null,
                    .none => @call(.always_inline, predicate, .{s.*}),
                },
                .deref => switch (error_union) {
                    .set => @call(.always_inline, predicate, .{s.*.*}) orelse null,
                    .none => @call(.always_inline, predicate, .{s.*.*}),
                },
                .ptr => switch (error_union) {
                    .set => @call(.always_inline, predicate, .{s}) orelse null,
                    .none => @call(.always_inline, predicate, .{s}),
                },
            };
        }
    };
}

/// Produce a single value, then return done.
pub fn Once(comptime T: type) type {
    return struct {
        pub const TypeSet = core.Producer(@This(), T);

        value: ?T,

        pub inline fn init(value: ?T) TypeSet.Context {
            return .{ .value = value };
        }

        pub inline fn next(ctx: TypeSet.Context) TypeSet.OutUnit {
            const v = ctx.value;
            if (v) |out| {
                return TypeSet.OutUnit.step(init(null), out);
            } else {
                return TypeSet.OutUnit.done(init(null));
            }
        }
    };
}

/// Iterate over a zig iterator. Expects the zig iterator as state and that
/// `S.next` exists and returns an optional or error!optional value.
pub fn OverIterator(comptime S: type) type {
    return StatefulFactory(S, S.next);
}

/// Produce values in a range.
pub fn Range(comptime T: type) type {
    return struct {
        pub const TypeSet = core.Producer(@This(), T);

        start: T,
        length: T,
        pub inline fn init(start: T, length: T) TypeSet.Context {
            return .{
                .start = start,
                .length = length,
            };
        }
        pub inline fn next(ctx: TypeSet.Context) TypeSet.OutUnit {
            const s = ctx.start;
            const len = ctx.length;
            if (ctx.length <= 0) {
                return TypeSet.OutUnit.done(init(s, len));
            } else {
                return TypeSet.OutUnit.step(init(s + 1, len - 1), s);
            }
        }
    };
}

/// Wraps a producer to allow it to loop. Only works for producers that
/// can be reset.
///
/// This should maybe be a conducer, but since it owns the original producer
/// rather than taking the input, it will start as a producer.
pub fn Repeating(comptime T: type) type {
    return struct {
        pub const TypeSet = core.Producer(@This(), T.TypeSet.Output);

        reset: T,
        current: T,

        pub inline fn init(reset: T) TypeSet.Context {
            return _init(reset, reset);
        }

        inline fn _init(reset: T, current: T) TypeSet.Context {
            return .{
                .reset = reset,
                .current = current,
            };
        }

        pub inline fn next(ctx: TypeSet.Context) TypeSet.OutUnit {
            const c = ctx.current;
            const out = T.next(c);
            return switch (out.rslt) {
                .done => {
                    const r = ctx.reset;
                    const rout = T.next(r);
                    return switch (rout.rslt) {
                        .done => TypeSet.OutUnit.done(_init(ctx.reset, rout.ctx)),
                        .again => TypeSet.OutUnit.again(_init(ctx.reset, rout.ctx)),
                        .step => |v| TypeSet.OutUnit.step(_init(ctx.reset, rout.ctx), v),
                    };
                },
                .again => TypeSet.OutUnit.again(_init(ctx.reset, out.ctx)),
                .step => |v| TypeSet.OutUnit.step(_init(ctx.reset, out.ctx), v),
            };
        }
    };
}

pub const slice = @import("./producer/slice.zig");
pub const join = @import("./producer/join.zig");
