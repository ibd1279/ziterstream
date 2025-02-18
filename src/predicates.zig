/// Count for Fold.
pub fn Count(comptime T: type) fn (usize, T) usize {
    return struct {
        fn count(a: usize, _: T) usize {
            return a + 1;
        }
    }.count;
}

/// Pair add for Map
pub fn PairAdd(comptime T: type, comptime R: type) fn (T) R {
    return struct {
        fn pairAdd(pair: T) R {
            return pair.left + pair.right;
        }
    }.pairAdd;
}

pub fn PairCompare(comptime T: type) fn (T) bool {
    return struct {
        fn pairCompare(pair: T) bool {
            return pair.left == pair.right;
        }
    }.pairCompare;
}

/// Summation for Reduce
pub fn Sum(comptime T: type) fn (T, T) T {
    return struct {
        fn sum(a: T, v: T) T {
            return a + v;
        }
    }.sum;
}

/// Kahan summation for Fold.
pub fn SumKahan(comptime T: type) type {
    return struct {
        a: T,
        c: T,
        pub inline fn init() @This() {
            return .{ .a = 0, .c = 0 };
        }
        pub fn add(self: @This(), v: T) @This() {
            const a = self.a;
            const c = self.c;
            const y = v - c;
            const t = a + y;
            return .{ .a = t, .c = (t - a) - y };
        }
    };
}
