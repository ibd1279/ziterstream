const std = @import("std");
const core = @import("../core.zig");

pub fn BinaryOpFn(comptime T: type) type {
    return fn (T, T) T;
}

/// Consume two values and perform a binary function call.
pub fn BinaryOp(
    /// Input and Output type
    comptime T: type,
    /// Function to do the operation.
    ///
    /// Consumes two values to generate one value.
    comptime predicate: BinaryOpFn(T),
) type {
    return struct {
        pub const TypeSet = core.Conducer(T, @This(), T);

        first: ?TypeSet.Input,

        pub inline fn init() TypeSet.Context {
            return _init(null);
        }
        pub inline fn _init(first: ?T) TypeSet.Context {
            return .{ .first = first };
        }
        pub inline fn next(in: TypeSet.InUnit) TypeSet.OutUnit {
            const first = in.ctx.first;
            if (first) |a| {
                return switch (in.rslt) {
                    .done => TypeSet.OutUnit.done(in.ctx),
                    .again => TypeSet.OutUnit.again(in.ctx),
                    .step => |b| TypeSet.OutUnit.step(_init(null), p(a, b)),
                };
            } else {
                return switch (in.rslt) {
                    .done => TypeSet.OutUnit.done(in.ctx),
                    .again => TypeSet.OutUnit.again(in.ctx),
                    .step => |v| TypeSet.OutUnit.again(_init(v)),
                };
            }
        }
        inline fn p(a: TypeSet.Input, b: TypeSet.Input) TypeSet.Output {
            return @call(.always_inline, predicate, .{ a, b });
        }
    };
}

/// Stateless filter map glue.
///
/// Filters out values where the predicate returns null or error. The
/// values filtered out are ignored. The errors are ignored. If you need
/// to capture the values that get filtered out, see
/// `DeadLetterMap`.
///
/// Result type is inferred from the predicate.
pub fn FilterMap(
    /// Input Type (before mapping).
    comptime T: type,
    /// Function to do the translation.
    ///
    /// Signature is expected to be in the format of `fn (T) ?R`
    comptime predicate: anytype,
) type {
    const ret_info = core.ReturnType.Describe(@TypeOf(predicate));
    const error_union = ret_info.error_union;
    const R = switch (ret_info.pointer) {
        .one => |p| *const p,
        .slice => |p| []const p,
        .none => ret_info.base_type,
    };

    return struct {
        pub const TypeSet = core.Conducer(T, @This(), R);

        pub inline fn init() TypeSet.Context {
            return .{};
        }
        pub inline fn next(in: TypeSet.InUnit) TypeSet.OutUnit {
            return switch (in.rslt) {
                .done => TypeSet.OutUnit.done(in.ctx),
                .again => TypeSet.OutUnit.again(in.ctx),
                .step => |v| if (p(v)) |r| TypeSet.OutUnit.step(init(), r) else TypeSet.OutUnit.again(in.ctx),
            };
        }
        inline fn p(v: TypeSet.Input) ?R {
            return switch (error_union) {
                .set => @call(.always_inline, predicate, .{v}) catch null,
                .none => @call(.always_inline, predicate, .{v}),
            };
        }
    };
}

/// call signature for tests that don't need state or runtime knowledge.
pub fn Tester(comptime T: type) type {
    return fn (T) bool;
}

/// Stateless filter glue.
///
/// Filters out values where the predicate returns false or error. The
/// values filtered out are ignored. The errors are ignored. If you need
/// to capture the values that get filtered out, see
/// `DeadLetterFilter`.
///
/// Result type matches the input type.
pub fn Filter(
    /// Input Type.
    comptime T: type,
    /// Function to do the translation.
    ///
    /// Signature is expected to be in the format of `fn (T) bool`
    comptime predicate: Tester(T),
) type {
    const ret_info = core.ReturnType.Describe(@TypeOf(predicate));
    const error_union = ret_info.error_union;

    return struct {
        pub const TypeSet = core.Conducer(T, @This(), T);

        pub inline fn init() TypeSet.Context {
            return .{};
        }
        pub inline fn next(in: TypeSet.InUnit) TypeSet.OutUnit {
            return switch (in.rslt) {
                .done => TypeSet.OutUnit.done(in.ctx),
                .again => TypeSet.OutUnit.again(in.ctx),
                .step => |v| if (p(v)) TypeSet.OutUnit.step(init(), v) else TypeSet.OutUnit.again(in.ctx),
            };
        }
        inline fn p(v: TypeSet.Input) bool {
            switch (error_union) {
                .set => return @call(.always_inline, predicate, .{v}) catch false,
                .none => return @call(.always_inline, predicate, .{v}),
            }
        }
    };
}

pub fn Mapper(comptime T: type, comptime R: type) type {
    return fn (T) R;
}

/// Stateless map glue.
///
/// Result type is inferred from the predicate.
///
/// The predicate must always return a result. If you need to skip over error values or
/// otherwise filter values, see
/// `FilterMap`.
pub fn Map(
    /// Input Type (before mapping).
    comptime T: type,
    /// Output Type (after mapping).
    comptime R: type,
    /// Function to do the translation.
    ///
    /// Signature is expected to be in the format of `fn (T) R`
    comptime predicate: Mapper(T, R),
) type {
    return FilterMap(T, predicate);
}
