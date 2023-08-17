const std = @import("std");

pub fn main() u8 {
    const stderr = std.io.getStdErr().writer();

    // TODO: Is arena allocator really necessary?
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const config = blk: {
        var args = std.process.argsWithAllocator(allocator) catch |err| {
            stderr.print("\x1B[1;91mError: Failed to get process arguments ({s})\x1B[0m\n", .{ @errorName(err) }) catch {};
            return 1;
        };
        defer args.deinit();
    }

    const file = std.fs.cwd().openFile("build", .{}) catch return 1;
    defer file.close();
    var stream = std.io.bufferedReaderSize(1024 * 1024, file.reader()); // TODO: What is the optimal size?

    std.debug.print("{}\n", .{ @TypeOf(stream.reader()) });

    return 0;
}
