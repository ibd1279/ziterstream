const std = @import("std");

/// Producer OutUnit type to describe the result.
pub const StepType = enum {
    done,
    again,
    step,
};

/// Consumer OutUnit type to describe the result.
pub const ActionType = enum {
    done,
    again,
};

pub const ParamType = struct {
    const ErrorUnion = union(enum) {
        set: type,
        none,
    };
    const PointerChild = union(enum) {
        slice: type,
        one: type,
        none,
    };
    base_type: type,
    error_union: ErrorUnion,
    optional: bool,
    pointer: PointerChild,

    pub fn Describe(comptime RawType: type) ParamType {
        const OptType = switch (@typeInfo(RawType)) {
            .ErrorUnion => |eu| eu.payload,
            else => RawType,
        };
        const err_union = switch (@typeInfo(RawType)) {
            .ErrorUnion => |eu| ErrorUnion{ .set = eu.error_set },
            else => ErrorUnion.none,
        };
        const optional = switch (@typeInfo(OptType)) {
            .Optional => true,
            else => false,
        };
        const PtrType = switch (@typeInfo(OptType)) {
            .Optional => |o| o.child,
            else => OptType,
        };
        const pointer = switch (@typeInfo(PtrType)) {
            .Pointer => |p| switch (p.size) {
                .One => PointerChild{ .one = p.child },
                .Slice => PointerChild{ .slice = p.child },
                // Will come back and support the others when I understand what they need better
                else => PointerChild.none,
            },
            else => PointerChild.none,
        };
        const base_type = switch (pointer) {
            .one => |p| p,
            .slice => |p| p,
            else => PtrType,
        };

        return .{
            .base_type = base_type,
            .error_union = err_union,
            .optional = optional,
            .pointer = pointer,
        };
    }
    pub fn DescribeParam(comptime idx: comptime_int, comptime FnType: type) ParamType {
        const fn_info = switch (@typeInfo(FnType)) {
            .Fn => |f| f,
            else => @compileError("Provided Predicate type is not a function."),
        };
        return Describe(fn_info.params[idx].type.?);
    }
};

pub const StateType = struct {
    const CallMode = enum { none, deref, ptr };
    pub fn callMode(comptime FnType: type, comptime S: type) CallMode {
        const self_info = ParamType.DescribeParam(0, FnType);
        const state_info = ParamType.Describe(S);
        const self_mode: CallMode = switch (self_info.pointer) {
            .one => switch (state_info.pointer) {
                .one => .none,
                .slice => @compileError("S is a slice type, but predicate expects a pointer."),
                .none => .ptr,
            },
            .slice => switch (state_info.pointer) {
                .one => @compileError("S is not a slice type, but predicate expects a slice."),
                .slice => .none,
                .none => @compileError("S is not a slice type, but predicate expects a slice."),
            },
            .none => switch (state_info.pointer) {
                .one => .deref,
                .slice => @compileError("S is a slice type, but predicate expects a value."),
                .none => .none,
            },
        };
        return self_mode;
    }
};

/// Helper type to unpack the return type from a function, and extract `T`.
pub const ReturnType = struct {
    pub fn Describe(comptime FnType: type) ParamType {
        const raw_type = Capture(FnType);
        return ParamType.Describe(raw_type);
    }
    pub fn Capture(comptime FnType: type) type {
        const fn_info = switch (@typeInfo(FnType)) {
            .Fn => |f| f,
            else => @compileError("Provided Predicate type is not a function."),
        };
        return fn_info.return_type.?;
    }
};

/// The type specific interface for building producers.
/// Producers accept no inputs, and produce a stream of output.
pub fn Producer(
    /// C is the type of the Context.
    comptime C: type,
    /// O is the type of the Output.
    comptime O: type,
) type {
    return struct {
        pub const Context = C;
        pub const Output = O;

        /// OutUnit is the result of producing.
        pub const OutUnit = struct {
            /// ctx is the new context after producing.
            ctx: Context,
            /// rslt is the result of production.
            rslt: union(StepType) {
                done: void,
                again: void,
                step: Output,
            },

            /// Producer is done producing. There is no next.
            pub inline fn done(ctx: Context) OutUnit {
                return .{ .ctx = ctx, .rslt = .{ .done = {} } };
            }
            /// Producer needs another cycle to produce something.
            pub inline fn again(ctx: Context) OutUnit {
                return .{ .ctx = ctx, .rslt = .{ .again = {} } };
            }
            /// Producer produced a value.
            pub inline fn step(ctx: Context, out: Output) OutUnit {
                return .{ .ctx = ctx, .rslt = .{ .step = out } };
            }
        };

        /// Signature for a producer next function.
        pub const Next = fn (Context) OutUnit;
    };
}

/// Producer that always returns done.
pub fn Empty(
    /// T is the Output type.
    comptime T: type,
) type {
    return struct {
        pub const TypeSet = Producer(@This(), T);
        pub inline fn next(_: TypeSet.Context) TypeSet.OutUnit {
            return TypeSet.OutUnit.done(TypeSet.Context{});
        }
    };
}

/// The type specific interface for building Consuming Producers.
/// Con-ducers Consume some input to pro-duce an output.
pub fn Conducer(
    /// I is the type of the Input.
    comptime I: type,
    /// C is the type of the Context.
    comptime C: type,
    /// O is the type of the Output.
    comptime O: type,
) type {
    return struct {
        pub const Input = I;
        pub const Context = C;
        pub const Output = O;

        /// InUnit is the input to production.
        pub const InUnit = struct {
            /// ctx is the current context.
            ctx: Context,
            rslt: union(StepType) {
                done: void,
                again: void,
                step: Input,
            },

            /// Upstream producer is done producing. There is no next.
            pub inline fn done(ctx: Context) InUnit {
                return .{ .ctx = ctx, .rslt = .{ .done = {} } };
            }
            /// Upstream producer produced a value.
            pub inline fn step(ctx: Context, in: Input) InUnit {
                return .{ .ctx = ctx, .rslt = .{ .step = in } };
            }
        };

        /// OutUnit is the output of production.
        pub const OutUnit = struct {
            /// ctx is the new context after producing.
            ctx: Context,
            rslt: union(StepType) {
                done: void,
                again: void,
                step: Output,
            },

            /// Producer is done producing. There is no next.
            pub inline fn done(ctx: Context) OutUnit {
                return .{ .ctx = ctx, .rslt = .{ .done = {} } };
            }
            /// Producer needs another cycle to produce something.
            pub inline fn again(ctx: Context) OutUnit {
                return .{ .ctx = ctx, .rslt = .{ .again = {} } };
            }
            /// Producer produced a value.
            pub inline fn step(ctx: Context, out: Output) OutUnit {
                return .{ .ctx = ctx, .rslt = .{ .step = out } };
            }
        };
    };
}

/// The type specific interface for building Consumers.
/// Consumers do not produce anything. They terminate the stream.
pub fn Consumer(
    /// I is the type of the Input.
    comptime I: type,
    /// C is the type of the Context.
    comptime C: type,
) type {
    return struct {
        pub const Input = I;
        pub const Context = C;

        /// InUnit is the input to production.
        pub const InUnit = struct {
            /// ctx is the current context.
            ctx: Context,
            rslt: union(StepType) {
                done: void,
                again: void,
                step: Input,
            },

            /// Producer is done producing. There is no next.
            pub inline fn done(ctx: Context) InUnit {
                return .{ .ctx = ctx, .rslt = .{ .done = {} } };
            }
            /// Producer produced a value.
            pub inline fn step(ctx: Context, in: Input) InUnit {
                return .{ .ctx = ctx, .rslt = .{ .step = in } };
            }
        };
        /// OutUnit is the output of consumption. It  wraps the
        /// new context after consumption, and if the stream sign
        /// was `done`.
        pub const OutUnit = struct {
            ctx: Context,
            rslt: ActionType,

            /// Consumer is done.
            pub inline fn done(ctx: Context) OutUnit {
                return .{ .ctx = ctx, .rslt = ActionType.done };
            }
            /// Consumer is done.
            pub inline fn again(ctx: Context) OutUnit {
                return .{ .ctx = ctx, .rslt = ActionType.again };
            }
        };
        pub const Next = fn (in: InUnit) OutUnit;
    };
}

/// Stream is a connection bewteen upstream (a producer) and downstream
/// (a conducer or a consumer).
pub fn Stream(
    /// `P` is the producer's type. P.TypeSet.Output must be a type.
    comptime P: type,
    /// `C` is the consumer's type. C.TypeSet.Input must be a type.
    comptime C: type,
) type {
    // Verify the producer can produce.
    if (!@hasDecl(P.TypeSet, "Output")) @compileError("Provided Producer does not expect an output. " ++ @typeName(P));
    const pure_producer = if (@hasDecl(P.TypeSet, "Input") or !@hasDecl(P.TypeSet, "Output")) false else true;
    if (!pure_producer) @compileError("Provided Producer expects an input. " ++ @typeName(P));

    // Verify the consumer can consume.
    if (!@hasDecl(C.TypeSet, "Input")) @compileError("Provided Consumer does not expect an input. " ++ @typeName(C));
    const pure_consumer = if (@hasDecl(C.TypeSet, "Output")) false else true;

    return struct {
        pub const TypeSet = if (!pure_consumer) Producer(@This(), C.TypeSet.Output) else Consumer(P.TypeSet.Output, @This());

        /// The `Up`-stream producer.
        pub const Up = P;

        /// The `Down`-stream producer.
        pub const Down = C;

        /// internal wrapper to cache "done" results from the producer
        const Spring = union(enum) {
            wet: Up,
            dry: Up.TypeSet.OutUnit,
            inline fn next(w: @This()) Up.TypeSet.OutUnit {
                return switch (w) {
                    .wet => |p| Up.next(p),
                    .dry => |out| out,
                };
            }
        };

        producer: Spring,
        consumer: Down,

        /// Initialize the Stream.
        pub inline fn init(producer: Up, consumer: Down) TypeSet.Context {
            return _init(.{ .wet = producer }, consumer);
        }

        /// Internal initialize that is `Spring` aware, used by next.
        inline fn _init(producer: Spring, consumer: Down) TypeSet.Context {
            return .{
                .producer = producer,
                .consumer = consumer,
            };
        }

        /// perform an iteration/cycle of this stream.
        pub inline fn next(ctx: TypeSet.Context) TypeSet.OutUnit {
            const p_out = ctx.producer.next();

            // if the spring has run dry, flip the type to stop visiting it.
            const spring: Spring = switch (p_out.rslt) {
                .done => .{ .dry = p_out },
                else => .{ .wet = p_out.ctx },
            };

            // Pass the well result to the consumer.
            const c = ctx.consumer;
            const c_out = switch (p_out.rslt) {
                .done => Down.next(Down.TypeSet.InUnit.done(c)),
                .again => return TypeSet.OutUnit.again(_init(spring, c)),
                .step => |v| Down.next(Down.TypeSet.InUnit.step(c, v)),
            };

            // process the conducer/consumer result.
            if (!pure_consumer) {
                return switch (c_out.rslt) {
                    .done => TypeSet.OutUnit.done(_init(spring, c_out.ctx)),
                    .again => TypeSet.OutUnit.again(_init(spring, c_out.ctx)),
                    .step => |v| TypeSet.OutUnit.step(_init(spring, c_out.ctx), v),
                };
            } else {
                return switch (c_out.rslt) {
                    .done => TypeSet.OutUnit.done(_init(spring, c_out.ctx)),
                    .again => TypeSet.OutUnit.again(_init(spring, c_out.ctx)),
                };
            }
        }
    };
}

pub fn Pond(comptime P: type, comptime C: type) type {
    // Verify the consumer can consume.
    if (@hasDecl(C.TypeSet, "Output")) @compileError("Provided Consumer has an output. Ponds require pure consumers.");
    const R = ReturnType.Capture(@TypeOf(C.result));

    return struct {
        chain: Stream(P, C),

        /// The `Up`-stream producer.
        pub const Up = P;

        /// The `Down`-stream consumer.
        pub const Down = C;

        /// The `Result` of the pond.
        pub const Result = R;

        const Self = @This();

        /// Flow the stream from upstream to downstream.
        ///
        /// Consumers from the stream until the pond is full.
        pub fn flow(self: Self) Self {
            var c = self.chain;
            while (true) {
                const c_out = c.next();
                c = c_out.ctx;
                switch (c_out.rslt) {
                    .done => break,
                    .again => continue,
                }
            }
            return .{ .chain = c };
        }

        /// Get the result from the last flow.
        pub fn result(self: Self) Result {
            return self.pond().result();
        }

        /// Causes the stream to flow until the `Pond` is full, and returns the Pond result.
        ///
        /// Provides the zig iterator interface.
        pub fn next(self: *Self) Result {
            self.* = self.flow();
            return self.result();
        }

        /// Get the first result.
        ///
        /// Equivalent to calling flow().result()
        pub fn use(self: Self) Result {
            return self.flow().result();
        }

        /// Get the upstream object.
        ///
        /// Since the Stream creates new contexts instead of
        /// mutating the exisiting context, this is used to pull the
        /// current producer context off the stream.
        pub inline fn stream(self: Self) P {
            return switch (self.chain.producer) {
                .wet => |ctx| ctx,
                .dry => |out| out.ctx,
            };
        }

        /// Get the downstream object.
        ///
        /// Since the Stream creates new contexts instead of
        /// mutating the existing context, this is used to pull the
        /// current consumer context off the stream.
        ///
        /// Often used for capturing the result.
        pub inline fn pond(self: Self) C {
            return self.chain.consumer;
        }
    };
}
