const std = @import("std");
const core = @import("../core.zig");

/// Stateful filter map glue.
///
/// Filters out values where the predicate returns null or error. The
/// values filtered out are ignored. The errors are ignored. If you need
/// to capture the values that get filtered out, see
/// `StatefulDeadLetterMap`.
///
/// Result type is inferred from the predicate.
pub fn FilterMap(
    /// Input Type (before mapping).
    comptime T: type,
    /// State Type.
    comptime S: type,
    /// Function to do the translation.
    ///
    /// Signature is expected to be in the format of `fn (S, T) ?R`
    comptime predicate: anytype,
) type {
    const self_mode = core.StateType.callMode(@TypeOf(predicate), S);
    const ret_info = core.ReturnType.Describe(@TypeOf(predicate));
    const error_union = ret_info.error_union;
    const R = switch (ret_info.pointer) {
        .one => |p| *const p,
        .slice => |p| []const p,
        .none => ret_info.base_type,
    };

    return struct {
        pub const TypeSet = core.Conducer(T, @This(), R);

        state: S,

        pub inline fn init(state: S) TypeSet.Context {
            return .{ .state = state };
        }
        pub inline fn next(in: TypeSet.InUnit) TypeSet.OutUnit {
            var s = in.ctx.state;
            return switch (in.rslt) {
                .done => TypeSet.OutUnit.done(in.ctx),
                .again => TypeSet.OutUnit.again(in.ctx),
                .step => |v| if (p(&s, v)) |r| TypeSet.OutUnit.step(init(s), r) else TypeSet.OutUnit.again(init(s)),
            };
        }
        inline fn p(s: *S, v: TypeSet.Input) ?R {
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
    };
}

/// Stateful filter glue.
///
/// Filters out values where the predicate returns false or error. The
/// values filtered out are ignored. The errors are ignored. If you need
/// to capture the values that get filtered out, see
/// `StatefulDeadLetterFilter`.
///
/// Result type matches the input type.
pub fn Filter(
    /// Input Type.
    comptime T: type,
    /// State Type.
    comptime S: type,
    /// Function to do the translation.
    ///
    /// Signature is expected to be in the format of `fn (S, T) bool`
    comptime predicate: anytype,
) type {
    const self_mode = core.StateType.callMode(@TypeOf(predicate), S);
    const ret_info = core.ReturnType.Describe(@TypeOf(predicate));
    const error_union = ret_info.error_union;

    return struct {
        pub const TypeSet = core.Conducer(T, @This(), T);

        state: S,

        pub inline fn init(state: S) TypeSet.Context {
            return .{ .state = state };
        }
        pub inline fn next(in: TypeSet.InUnit) TypeSet.OutUnit {
            var s = in.ctx.state;
            return switch (in.rslt) {
                .done => TypeSet.OutUnit.done(in.ctx),
                .again => TypeSet.OutUnit.again(in.ctx),
                .step => |v| if (p(&s, v)) TypeSet.OutUnit.step(init(s), v) else TypeSet.OutUnit.again(in.ctx),
            };
        }
        inline fn p(s: *S, v: TypeSet.Input) bool {
            switch (self_mode) {
                .none => switch (error_union) {
                    .set => return @call(.always_inline, predicate, .{ s.*, v }) catch false,
                    .none => return @call(.always_inline, predicate, .{ s.*, v }),
                },
                .deref => switch (error_union) {
                    .set => return @call(.always_inline, predicate, .{ s.*.*, v }) catch false,
                    .none => return @call(.always_inline, predicate, .{ s.*.*, v }),
                },
                .ptr => switch (error_union) {
                    .set => return @call(.always_inline, predicate, .{ s, v }) catch false,
                    .none => return @call(.always_inline, predicate, .{ s, v }),
                },
            }
        }
    };
}

/// Stateful map glue.
///
/// Result type is inferred from the predicate.
///
/// The predicate must always return a result. If you need to skip over error values or
/// otherwise filter values, see
/// `StatefulFilterMap`.
pub fn Map(
    /// Input Type (before mapping).
    comptime T: type,
    /// State Type.
    comptime S: type,
    /// Function to do the translation.
    ///
    /// Signature is expected to be in the format of `fn (S, T) R`
    comptime predicate: anytype,
) type {
    // This is mostly to enforce semantics as the two may diverge in the future.
    // read as "where R is not an optional and not an error union."
    const ret_info = core.ReturnType.Describe(@TypeOf(predicate));
    if (ret_info.optional) @compileError("predicate returns an optional type. See StatefulFilterMap.");
    switch (ret_info.error_union) {
        .set => @compileError("predicate returns an error union. See StatefulFilterMap."),
        else => {},
    }

    return FilterMap(T, S, predicate);
}

pub fn DeadLetterCallback(
    comptime T: type,
    comptime D: type,
) type {
    return fn (*D, T, anyerror) void;
}

pub fn DeadLetterFilterMap(
    comptime T: type,
    comptime State: type,
    comptime Dstate: type,
    comptime predicate: anytype,
    comptime Dpredicate: DeadLetterCallback(T, Dstate),
) type {
    const self_mode = core.StateType.callMode(@TypeOf(predicate), State);
    const ret_info = core.ReturnType.Describe(@TypeOf(predicate));
    const error_union = ret_info.error_union;
    const R = switch (ret_info.pointer) {
        .one => |p| *const p,
        .slice => |p| []const p,
        .none => ret_info.base_type,
    };

    return struct {
        pub const TypeSet = core.Conducer(T, @This(), R);

        state: State,
        dlq: Dstate,

        pub inline fn init(state: State, dlq: Dstate) TypeSet.Context {
            return .{ .state = state, .dlq = dlq };
        }
        pub inline fn next(in: TypeSet.InUnit) TypeSet.OutUnit {
            var s = in.ctx.state;
            var d = in.ctx.dlq;
            return switch (in.rslt) {
                .done => TypeSet.OutUnit.done(in.ctx),
                .again => TypeSet.OutUnit.again(in.ctx),
                .step => |v| if (p(&s, v, &d)) |r| TypeSet.OutUnit.step(init(s, d), r) else TypeSet.OutUnit.again(init(s, d)),
            };
        }
        inline fn p(s: *State, v: TypeSet.Input, d: *Dstate) ?R {
            return switch (self_mode) {
                .none => switch (error_union) {
                    .set => @call(.always_inline, predicate, .{ s.*, v }) catch |err| q(d, v, err),
                    .none => @call(.always_inline, predicate, .{ s.*, v }),
                },
                .deref => switch (error_union) {
                    .set => @call(.always_inline, predicate, .{ s.*.*, v }) catch |err| q(d, v, err),
                    .none => @call(.always_inline, predicate, .{ s.*.*, v }),
                },
                .ptr => switch (error_union) {
                    .set => @call(.always_inline, predicate, .{ s, v }) catch |err| q(d, v, err),
                    .none => @call(.always_inline, predicate, .{ s, v }),
                },
            };
        }
        inline fn q(d: *Dstate, v: TypeSet.Input, err: anyerror) ?R {
            @call(.always_inline, Dpredicate, .{ d, v, err });
            return null;
        }
    };
}
