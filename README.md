# ziterstream

A lazy iter streaming library.

I liked the way they worked in Rust, and wanted something similar in zig.

It doesn't exactly work the way I want yet, but was a great experiement in template meta programming with zig.

# usage

```zig

const ziters = @import("");
const total = ziters.range(u32, 0, 11).sum().use();

```
