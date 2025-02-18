const std = @import("std");
const core = @import("../core.zig");

// pub fn Combine(comptime Left: type, comptime Right: type) type {
//     if (T.TypeSet.Output != P.TypeSet.Output) @compileError("Mismatched outputs from " ++ @typeName(T) ++ " and " ++ @typeName(P) ++ ".");

//     return struct {
//         pub const Pair = return struct { left: L.TypeSet.Output, right: R.TypeSet.Output };
//         pub const TypeSet = core.Producer(@This(), T.TypeSet.Output);

//         left: T.TypeSet.Context,
//         right: P.TypeSet.Context,

//         pub inline fn init(first: T.TypeSet.Context, second: P.TypeSet.Context) TypeSet.Context {
//             return _init(first, second, false);
//         }
//         pub inline fn _init(first: T.TypeSet.Context, second: P.TypeSet.Context, odd: bool) TypeSet.Context {
//             return .{ .first = first, .second = second, .odd = odd };
//         }
//         pub inline fn next(ctx: TypeSet.Context) TypeSet.OutUnit {
//             const first = ctx.first;
//             const second = ctx.second;
//             if (!ctx.odd) {
//                 const f_out = T.next(first);
//                 return switch (f_out.rslt) {
//                     .done => TypeSet.OutUnit.done(_init(f_out.ctx, second, ctx.odd)),
//                     .again => TypeSet.OutUnit.again(_init(f_out.ctx, second, ctx.odd)),
//                     .step => |v| TypeSet.OutUnit.step(_init(f_out.ctx, second, !ctx.odd), v),
//                 };
//             } else {
//                 const s_out = P.next(second);
//                 return switch (s_out.rslt) {
//                     .done => TypeSet.OutUnit.done(_init(first, s_out.ctx, ctx.odd)),
//                     .again => TypeSet.OutUnit.again(_init(first, s_out.ctx, ctx.odd)),
//                     .step => |v| TypeSet.OutUnit.step(_init(first, s_out.ctx, !ctx.odd), v),
//                 };
//             }
//         }
//     };
// }

/// Underflow starts consuming from a second producer when the first runs dry.
pub fn Underflow(comptime T: type, comptime P: type) type {
    if (T.TypeSet.Output != P.TypeSet.Output) @compileError("Mismatched outputs from " ++ @typeName(T) ++ " and " ++ @typeName(P) ++ ".");

    return struct {
        pub const TypeSet = core.Producer(@This(), T.TypeSet.Output);

        first: T.TypeSet.Context,
        second: P.TypeSet.Context,

        pub inline fn init(first: T.TypeSet.Context, second: P.TypeSet.Context) TypeSet.Context {
            return .{ .first = first, .second = second };
        }
        pub inline fn next(ctx: TypeSet.Context) TypeSet.OutUnit {
            const first = ctx.first;
            const second = ctx.second;
            const f_out = T.next(first);
            return switch (f_out.rslt) {
                .done => {
                    const s_out = P.next(second);
                    return switch (s_out.rslt) {
                        .done => TypeSet.OutUnit.done(init(f_out.ctx, s_out.ctx)),
                        .again => TypeSet.OutUnit.again(init(f_out.ctx, s_out.ctx)),
                        .step => |v| TypeSet.OutUnit.step(init(f_out.ctx, s_out.ctx), v),
                    };
                },
                .again => TypeSet.OutUnit.again(init(f_out.ctx, second)),
                .step => |v| TypeSet.OutUnit.step(init(f_out.ctx, second), v),
            };
        }
    };
}

pub fn Zip(comptime T: type, comptime P: type) type {
    if (T.TypeSet.Output != P.TypeSet.Output) @compileError("Mismatched outputs from " ++ @typeName(T) ++ " and " ++ @typeName(P) ++ ".");

    return struct {
        pub const TypeSet = core.Producer(@This(), T.TypeSet.Output);

        first: T.TypeSet.Context,
        second: P.TypeSet.Context,
        odd: bool,

        pub inline fn init(first: T.TypeSet.Context, second: P.TypeSet.Context) TypeSet.Context {
            return _init(first, second, false);
        }
        pub inline fn _init(first: T.TypeSet.Context, second: P.TypeSet.Context, odd: bool) TypeSet.Context {
            return .{ .first = first, .second = second, .odd = odd };
        }
        pub inline fn next(ctx: TypeSet.Context) TypeSet.OutUnit {
            const first = ctx.first;
            const second = ctx.second;
            if (!ctx.odd) {
                const f_out = T.next(first);
                return switch (f_out.rslt) {
                    .done => TypeSet.OutUnit.done(_init(f_out.ctx, second, ctx.odd)),
                    .again => TypeSet.OutUnit.again(_init(f_out.ctx, second, ctx.odd)),
                    .step => |v| TypeSet.OutUnit.step(_init(f_out.ctx, second, !ctx.odd), v),
                };
            } else {
                const s_out = P.next(second);
                return switch (s_out.rslt) {
                    .done => TypeSet.OutUnit.done(_init(first, s_out.ctx, ctx.odd)),
                    .again => TypeSet.OutUnit.again(_init(first, s_out.ctx, ctx.odd)),
                    .step => |v| TypeSet.OutUnit.step(_init(first, s_out.ctx, !ctx.odd), v),
                };
            }
        }
    };
}
