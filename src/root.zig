const std = @import("std");
const core = @import("./core.zig");
const src = @import("./producer.zig");
const link = @import("./conducer.zig");
const dst = @import("./consumer.zig");
const pred = @import("./predicates.zig");
const iterst = @This();

/// Create an empty producer. Only ever outputs done.
pub inline fn empty(comptime T: type) Empty(T) {
    return .{ .source = src.Empty(T){} };
}
pub fn Empty(comptime T: type) type {
    return Stream(src.Empty(T));
}

/// Create a factory producer. Invokes the crafter for each production.
/// Can be stateful if you use a pointer receiver for the factory.
pub inline fn statefulFactory(state: anytype, comptime predicate: anytype) StatefulFactory(@TypeOf(state), predicate) {
    return .{ .source = src.StatefulFactory(@TypeOf(state), predicate).init(state) };
}
pub fn StatefulFactory(comptime S: type, comptime predicate: anytype) type {
    return Stream(src.StatefulFactory(S, predicate));
}

/// Create a single item producer. Only every outputs a single item once.
pub inline fn once(comptime T: type, value: T) Once(T) {
    return .{ .source = src.Once(T).init(value) };
}
pub fn Once(comptime T: type) type {
    return Stream(src.Once(T));
}

/// Create a producer that iterates over the items in a slice.
pub inline fn sliceBackwards(comptime T: type, slice: []const T) SliceBackwards(T) {
    return .{ .source = src.slice.Backwards(T).init(slice) };
}
pub fn SliceBackwards(comptime T: type) type {
    return Stream(src.slice.Backwards(T));
}

/// Create a producer that iterates over the items in a slice.
pub inline fn sliceForward(comptime T: type, slice: []const T) SliceForward(T) {
    return .{ .source = src.slice.Forward(T).init(slice) };
}
pub fn SliceForward(comptime T: type) type {
    return Stream(src.slice.Forward(T));
}

/// Create a producer that returns random items from a silce.
pub inline fn sliceRandom(comptime T: type, slice: []const T, rand: std.Random) SliceRandom(T) {
    return .{ .source = src.slice.Random(T).init(slice, rand) };
}
pub fn SliceRandom(comptime T: type) type {
    return Stream(src.slice.Random(T));
}

/// Create a stream over a Zig Iterator.
pub inline fn overIterator(state: anytype) OverIterator(@TypeOf(state)) {
    return .{ .source = src.OverIterator(@TypeOf(state)).init(state) };
}
pub fn OverIterator(comptime S: type) type {
    return Stream(src.OverIterator(S));
}

// create a producer that iterates over two other producers to create pairs.
pub inline fn pairs(left: anytype, right: anytype) Pairs(@TypeOf(left.source), @TypeOf(right.source)) {
    const L: type = @TypeOf(left.source);
    const R: type = @TypeOf(right.source);
    if (!@hasDecl(L.TypeSet, "Output")) @compileError("Pair Streams must have a left output.");
    if (!@hasDecl(R.TypeSet, "Output")) @compileError("Pair Streams must have a right output.");
    return .{ .source = src.Pairs(L, R).init(left.source, right.source) };
}
pub fn Pairs(comptime L: type, comptime R: type) type {
    return Stream(src.Pairs(L, R));
}

/// create a producer that iterates over a range of numbers
pub inline fn range(comptime T: type, start: T, length: usize) Range(T) {
    return .{ .source = src.Range(T).init(start, length) };
}
pub fn Range(comptime T: type) type {
    return Stream(src.Range(T));
}

/// switch over to a second producer when the first producer is done.
pub inline fn underflow(
    primary: anytype,
    secondary: anytype,
) Underflow(@TypeOf(primary.source), @TypeOf(secondary.source)) {
    return .{ .source = src.join.Underflow(@TypeOf(primary.source), @TypeOf(secondary.source)).init(primary.source, secondary.source) };
}
pub fn Underflow(comptime P: type, comptime S: type) type {
    return Stream(src.join.Underflow(P, S));
}

/// alternate between two producers
pub inline fn zip(
    first: anytype,
    second: anytype,
) Zip(@TypeOf(first.source), @TypeOf(second.source)) {
    return .{ .source = src.join.Zip(@TypeOf(first.source), @TypeOf(second.source)).init(first.source, second.source) };
}
pub fn Zip(comptime F: type, comptime S: type) type {
    return Stream(src.join.Zip(F, S));
}

/// interface for collecting the result.
pub const Pond = core.Pond;

/// Stream wrapper over a producer to make chaining easier.
pub fn Stream(comptime T: type) type {
    if (!@hasDecl(T.TypeSet, "Output")) @compileError("Flowing Streams must have an output.");
    return struct {
        /// Type of the producer
        pub const Src = T;
        /// Type of the output of this stream.
        pub const Out = T.TypeSet.Output;

        source: Src,

        const Self = @This();
        const Tester = link.stateless.Tester(Out);
        const BinaryOpFn = link.stateless.BinaryOpFn(Out);

        /// internal helper function to connect a producer and a conducer/consumer.
        fn connect(self: Self, next: anytype) core.Stream(Src, @TypeOf(next)) {
            return core.Stream(Src, @TypeOf(next)).init(self.source, next);
        }

        /// Wrap the current producer in a repeating producer.
        pub inline fn repeating(self: Self) Repeating {
            return .{ .source = src.Repeating(Src).init(self.source) };
        }
        pub const Repeating = Stream(src.Repeating(Src));

        pub inline fn intersperse(self: Self, delim: Out) Intersperse {
            const delim_iter = once(Out, delim).repeating();
            return zip(self, delim_iter);
        }
        pub const Intersperse = Zip(Src, Once(Out).Repeating.Src);

        /// Consume two items from the stream and produce a single item.
        pub inline fn binaryOp(
            self: Self,
            /// predicate called for each item. Expected signature of `fn (T, T) T`
            comptime predicate: BinaryOpFn,
        ) BinaryOp(predicate) {
            return .{ .source = self.connect(link.stateless.BinaryOp(Out, predicate).init()) };
        }
        pub fn BinaryOp(comptime predicate: BinaryOpFn) type {
            return Stream(core.Stream(Src, link.stateless.BinaryOp(Out, predicate)));
        }

        /// Filter the stream. only streams values that return true for the predicate.
        ///
        /// See `statefulFilter` for a filter that takes runtime state.
        pub inline fn filter(
            self: Self,
            /// Predicate called for each item. Expected signature of `fn (T) bool`
            comptime predicate: Tester,
        ) Filter(predicate) {
            return .{ .source = self.connect(link.stateless.Filter(Out, predicate).init()) };
        }
        pub fn Filter(comptime predicate: Tester) type {
            return Stream(core.Stream(Src, link.stateless.Filter(Out, predicate)));
        }

        /// Filter and map the stream. only streams values that map.
        ///
        /// See `statefulFilterMap` for a filterMap that takes runtime state.
        pub inline fn filterMap(
            self: Self,
            /// Predicate called for each item. Expected signature of `fn (T) !?R`.
            comptime predicate: anytype,
        ) FilterMap(predicate) {
            return .{ .source = self.connect(link.stateless.FilterMap(Out, predicate).init()) };
        }
        pub fn FilterMap(comptime predicate: anytype) type {
            return Stream(core.Stream(Src, link.stateless.FilterMap(Out, predicate)));
        }

        /// Map the stream. transforms values from one type to another.
        ///
        /// Does not deal with filtering or errors. See `filterMap` for a
        /// map that can filter over values.
        ///
        /// See `statefulMap` for a map that takes a runtime state.
        pub inline fn map(
            self: Self,
            /// Mapping output type.
            comptime R: type,
            /// Predicate called for each item. Expected signature of `fn (T) R`.
            comptime predicate: anytype,
        ) Map(R, predicate) {
            return .{ .source = self.connect(link.stateless.Map(Out, R, predicate).init()) };
        }
        pub fn Map(comptime R: type, comptime predicate: anytype) type {
            return Stream(core.Stream(Src, link.stateless.Map(Out, R, predicate)));
        }

        /// Filter the stream. only streams values that return true for the predicate.
        ///
        /// See `filter` for a filter that does not require runtime state.
        pub inline fn statefulFilter(
            self: Self,
            /// State passed as the first argument of the predicate.
            state: anytype,
            /// Predicate called for each item. Expected signature of `fn (@TypeOf(state), T) bool`.
            comptime predicate: anytype,
        ) StatefulFilter(@TypeOf(state), predicate) {
            return .{ .source = self.connect(link.stateful.Filter(Out, @TypeOf(state), predicate).init(state)) };
        }
        pub fn StatefulFilter(comptime S: type, comptime predicate: anytype) type {
            return Stream(core.Stream(Src, link.stateful.Filter(Out, S, predicate)));
        }

        /// Filter and map the stream. only streams values that map.
        ///
        /// See `filterMap` for a filterMap that does not require runtime state.
        pub inline fn statefulFilterMap(
            self: Self,
            /// State passed as the first argument of the predicate.
            state: anytype,
            /// Predicate called for each item. Expected signature of `fn (@TypeOf(state), T) !?R`.
            comptime predicate: anytype,
        ) StatefulFilterMap(@TypeOf(state), predicate) {
            return .{ .source = self.connect(link.stateful.FilterMap(Out, @TypeOf(state), predicate).init(state)) };
        }
        pub fn StatefulFilterMap(comptime S: type, comptime predicate: anytype) type {
            return Stream(core.Stream(Src, link.stateful.FilterMap(Out, S, predicate)));
        }

        /// Map the stream. transforms values from one type to another.
        ///
        /// Does not deal with filtering or errors. See `statefulFilterMap` for a
        /// map that can filter over values.
        ///
        /// See `map` for a map that does not require runtime state.
        pub inline fn statefulMap(
            self: Self,
            /// State passed as the first argument of the predicate.
            state: anytype,
            /// Predicate called for each item. Expected signature of `fn (@TypeOf(state), T) R`.
            comptime predicate: anytype,
        ) StatefulMap(@TypeOf(state), predicate) {
            return .{ .source = self.connect(link.stateful.Map(Out, @TypeOf(state), predicate).init(state)) };
        }
        pub fn StatefulMap(comptime S: type, comptime predicate: anytype) type {
            return Stream(core.Stream(Src, link.stateful.Map(Out, S, predicate)));
        }

        // -------------------------------------------------------------------
        // Conducers Above
        // Consumers Below
        // -------------------------------------------------------------------

        /// Collect an ArrayList of values. Grows the list as needed.
        pub inline fn collectArrayList(
            self: Self,
            /// ArrayList to accumulate the results into.
            accumulator: std.ArrayList(Out),
        ) CollectArrayList {
            return .{ .chain = self.connect(dst.CollectArrayList(Out).init(accumulator)) };
        }
        pub const CollectArrayList = Pond(Src, dst.CollectArrayList(Out));

        /// Collect a slice of values. Will return a shortened slice for incomplete collections
        pub inline fn collectSlice(
            self: Self,
            /// Slice to accumulate the results into.
            accumulator: []Out,
        ) CollectSlice {
            return .{ .chain = self.connect(dst.CollectSlice(Out).init(accumulator)) };
        }
        pub const CollectSlice = Pond(Src, dst.CollectSlice(Out));

        /// Collect the values by writing them to a writer.
        pub inline fn collectWriter(
            self: Self,
            /// Writer to accumulate the results into.
            accumulator: anytype,
        ) CollectWriter(@TypeOf(accumulator)) {
            return .{ .chain = self.connect(dst.CollectWriter(@TypeOf(accumulator), Out).init(accumulator)) };
        }
        pub fn CollectWriter(comptime W: type) type {
            return Pond(Src, dst.CollectWriter(W, Out));
        }

        /// Count of the stream.
        pub inline fn count(
            self: Self,
        ) Count {
            return self.fold(@as(usize, 0), pred.Count(usize));
        }
        const Count = Fold(usize, pred.Count(usize));

        /// Fold (reduce with initial value) using the provided reducer.
        pub inline fn fold(
            self: Self,
            /// initial state of the fold.
            first: anytype,
            /// predicate to execute the fold.
            comptime predicate: dst.ReducerFn(@TypeOf(first), Out),
        ) Fold(@TypeOf(first), predicate) {
            return .{ .chain = self.connect(dst.Fold(Out, @TypeOf(first), predicate).init(first)) };
        }
        pub fn Fold(comptime S: type, comptime predicate: anytype) type {
            return Pond(Src, dst.Fold(Out, S, predicate));
        }

        /// For Each over stream values.
        pub inline fn statefulForEach(
            self: Self,
            /// initial state of the foreach.
            state: anytype,
            /// predicate to execute the forEach.
            comptime predicate: anytype,
        ) StatefulForEach(@TypeOf(state), predicate) {
            return .{ .chain = self.connect(dst.ForEach(Out, @TypeOf(state), predicate).init(state)) };
        }
        pub fn StatefulForEach(comptime S: type, comptime predicate: anytype) type {
            return Pond(Src, dst.ForEach(Out, S, predicate));
        }

        /// collect a single value. Null if no value was collected.
        ///
        /// Can be used to mimic a zig iterator.
        pub inline fn one(
            self: Self,
        ) One {
            return .{ .chain = self.connect(dst.One(Out).init()) };
        }
        pub const One = Pond(Src, dst.One(Out));

        /// Reduce (fold without an initial value) using the provided reducer.
        pub inline fn reduce(
            self: Self,
            /// predicate to execute the reduce.
            comptime predicate: dst.ReducerFn(Out, Out),
        ) Reduce(predicate) {
            return .{ .chain = self.connect(dst.Reduce(Out, predicate).init()) };
        }
        pub fn Reduce(comptime predicate: anytype) type {
            return Pond(Src, dst.Reduce(Out, predicate));
        }

        /// Sum of the stream.
        pub inline fn sum(
            self: Self,
        ) Sum {
            return self.reduce(pred.Sum(Out));
        }
        pub const Sum = Reduce(pred.Sum(Out));

        /// Compensated sum of the stream.
        pub inline fn sumCompensated(
            self: Self,
        ) SumCompensated {
            return self.fold(pred.SumKahan(Out).init(), pred.SumKahan(Out).add);
        }
        pub const SumCompensated = Fold(pred.SumKahan(Out), pred.SumKahan(Out).add);
    };
}

// Producer testing. Also shows some examples of how to use.
test "producer empty" {
    try std.testing.expectEqual(@as(?u8, null), iterst.empty(u8).one().use());
}

test "producer statefulFactory" {
    // Example of using a simple factory (a generator function) to output a stream
    {
        const craftCountDown = struct {
            fn f(counter: *u32) ?u32 {
                const ret = counter.*;
                if (ret == 0) return null;
                counter.* -= 1;
                return ret;
            }
        }.f;
        const expected: u32 = 55;
        const count: u32 = 10;
        const actual = iterst.statefulFactory(count, craftCountDown).sumCompensated().use().a;
        try std.testing.expectEqual(expected, actual);
    }
    {
        // because the state is a pointer (meaning repeating cannot "capture" the
        // initial state), repeating is unable to reset the initial stream, and it
        // still ends.
        //
        // This can be worked around by using a non-pointer type for the initial state.
        const craftCountDown = struct {
            fn f(counter: *u32) ?u32 {
                const ret = counter.*;
                if (ret == 0) return null;
                counter.* -= 1;
                return ret;
            }
        }.f;
        var count: u32 = 10;
        const total = iterst.statefulFactory(&count, craftCountDown).repeating().sumCompensated().use().a;
        try std.testing.expectEqual(@as(u32, 55), total);
    }
}

test "producer once" {
    var slice = [_]u8{ 0, 0 };
    const actual = iterst.once(u8, 'A').collectSlice(&slice).use();
    try std.testing.expectEqual(@as(usize, 1), actual.len);
    try std.testing.expectEqual(@as(u8, 'A'), actual[0]);
}

test "producer OverIterator" {
    const zig_iter = std.mem.splitScalar(u8, "foo bar baz", ' ');
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    _ = iterst.overIterator(zig_iter).collectWriter(&aw.writer).use();
    try std.testing.expectEqualStrings("foobarbaz", aw.writer.buffer[0..aw.writer.end]);
}

test "producer Range" {
    const total2 = iterst.range(u32, 0, 11).sum().use();
    try std.testing.expectEqual(@as(u32, 55), total2);
}

test "producer Repeating" {
    var slice = [_]u8{ 0, 0 };
    const actual = iterst.once(u8, 'A').repeating().collectSlice(&slice).use();
    try std.testing.expectEqual(@as(usize, 2), actual.len);
    try std.testing.expectEqual(@as(u8, 'A'), actual[0]);
    try std.testing.expectEqual(@as(u8, 'A'), actual[1]);
}

test "producer SliceBackwards" {
    const input = "gnib zab rab oof";
    const expected = "foo bar baz bing";
    var outbuf: [16]u8 = undefined;
    const actual = iterst.sliceBackwards(u8, input).collectSlice(&outbuf).use();
    try std.testing.expectEqualStrings(expected, actual);
}

test "producer SliceForward" {
    const expected = "foo bar baz bing";
    var outbuf: [16]u8 = undefined;
    const actual = iterst.sliceForward(u8, expected).collectSlice(&outbuf).use();
    try std.testing.expectEqualStrings(expected, actual);
}

test "producer SliceRandom" {
    {
        const input = "foo bar baz bing";
        var rand = std.Random.DefaultPrng.init(33);
        var outbuf: [16]u8 = undefined;
        const expected = "nibna zbrba b gg";
        const actual = iterst.sliceRandom(u8, input, rand.random()).collectSlice(&outbuf).use();
        try std.testing.expectEqualStrings(expected, actual);
    }
}

test "producer Underflow" {
    {
        const tester = struct {
            pub fn filter(v: u32) bool {
                return v % 2 == 0;
            }
        }.filter;
        const expected: u32 = 85;
        const stream1 = iterst.range(u32, 0, 11).filter(tester);
        const stream2 = iterst.range(u32, 0, 11);
        const actual = iterst.underflow(stream1, stream2).sum().use();
        try std.testing.expectEqual(expected, actual);
    }
}

test "producer Zip" {
    {
        const sub = struct {
            pub fn sub(a: i32, b: i32) i32 {
                return a - b;
            }
        }.sub;
        const expected: i32 = 10;
        const stream1 = iterst.range(i32, 10, 2);
        const stream2 = iterst.range(i32, 5, 2);
        const actual = iterst.zip(stream1, stream2).binaryOp(sub).sum().use();
        try std.testing.expectEqual(expected, actual);
    }
}

test "conducer Filter" {
    {
        const tester = struct {
            pub fn filter(v: u32) bool {
                return v % 2 == 0;
            }
        }.filter;
        const expected: u32 = 30;
        const actual = iterst.range(u32, 0, 11).filter(tester).sum().use();
        try std.testing.expectEqual(expected, actual);
    }
    {
        const tester = struct {
            pub fn filter(s: u32, v: u32) bool {
                return v % s == 0;
            }
        }.filter;
        const expected: u32 = 18;
        const actual = iterst.range(u32, 0, 11).statefulFilter(@as(u32, 3), tester).sum().use();
        try std.testing.expectEqual(expected, actual);
    }
}

test "conducer Map" {
    {
        const mapper = struct {
            pub fn double(v: u32) u32 {
                return v * 2;
            }
        }.double;
        const expected: u32 = 110;
        const actual = iterst.range(u32, 0, 11).map(u32, mapper).sum().use();
        try std.testing.expectEqual(expected, actual);
    }
    {
        const mapper = struct {
            pub fn calc(one: u32, parts: u32) f64 {
                const num: f64 = @floatFromInt(parts);
                const den: f64 = @floatFromInt(one);
                return num / den;
            }
        }.calc;
        const expected: f64 = 5.5;
        const actual = iterst.range(u32, 0, 11).statefulMap(@as(u32, 10), mapper).sumCompensated().use().a;
        try std.testing.expectEqual(expected, actual);
    }
}
