const std = @import("std");

// https://github.com/ziglang/zig/blob/master/tools/spirv/grammar.zig
pub const Registry = struct {
    copyright: [][]const u8,
    magic_number: []const u8,
    major_version: u32,
    minor_version: u32,
    revision: u32,
    instruction_printing_class: []InstructionPrintingClass,
    instructions: []Instruction,
    operand_kinds: []OperandKind,

    pub const InstructionPrintingClass = struct {
        tag: []const u8,
        heading: ?[]const u8 = null,
    };

    pub const Instruction = struct {
        opname: []const u8,
        class: ?[]const u8 = null,
        opcode: u32,
        operands: []Operand = &[_]Operand {},
        capabilities: [][]const u8 = &[_][]const u8 {},
        extensions: [][]const u8 = &[_][]const u8 {},
        version: ?[]const u8 = null,
        lastVersion: ?[]const u8 = null,
    };

    pub const Operand = struct {
        kind: []const u8,
        quantifier: ?Quantifier = null,
        name: []const u8 = "",
    };

    pub const Quantifier = enum {
        @"?",
        @"*",
    };

    pub const OperandCategory = enum {
        BitEnum,
        ValueEnum,
        Id,
        Literal,
        Composite,
    };

    pub const OperandKind = struct {
        category: OperandCategory,
        kind: []const u8,
        doc: ?[]const u8 = null,
        enumerants: ?[]Enumerant = null,
        bases: ?[]const []const u8 = null,
    };

    pub const Enumerant = struct {
        enumerant: []const u8,
        value: union(enum) {
            bitflag: []const u8,
            int: u31,

            pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, _: std.json.ParseOptions) std.json.ParseError(@TypeOf(source.*))!@This() {
                switch (try source.nextAlloc(allocator, .alloc_if_needed)) {
                    inline .string, .allocated_string => |s| return @This() { .bitflag = s },
                    inline .number, .allocated_number => |s| return @This() { .int = try std.fmt.parseInt(u31, s, 10) },
                    else => return error.UnexpectedToken,
                }
            }

            pub const jsonStringify = @compileError("Not supported");
        },
        capabilities: [][]const u8 = &[_][]const u8 {},
        extensions: [][]const u8 = &[_][]const u8 {},
        parameters: []Operand = &[_]Operand {},
        version: ?[]const u8 = null,
        lastVersion: ?[]const u8 = null,
    };
};

pub fn main() u8 {
    const stderr = std.io.getStdErr().writer();

    // TODO: Is arena allocator really necessary?
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var uri: ?std.Uri = null;
    var out: ?std.fs.File = null;
    {
        var args = std.process.argsWithAllocator(allocator) catch |err| {
            stderr.print("\x1B[1;91mError: Failed to get process arguments ({s})\x1B[0m\n", .{ @errorName(err) }) catch {};
            return 1;
        };
        defer args.deinit();
        // _ = args.skip();
        
    }

        while (args.next()) |arg| switch (std.hash.Fnv1a_64.hash(arg)) { // TODO: Is 64-bit FNV-1a really the best hashing algorithm for the job?
            0x4C4E90193DC8C6FD, //   uri
            0xE357B8F7AE7D9A2,  //  -uri
            0x32EAF6FCC4061D47, // --uri
            => break args.next() orelse return 1, // TODO
            0xA9918CC5FA26ABA,  //   help
            0x8A5545E61220768B, //  -help
            0x5DAAF2E4C8A8BF3C, // --help
            => return 1, // TODO
            else => return 1, // TODO
        } else "https://raw.githubusercontent.com/KhronosGroup/SPIRV-Headers/main/include/spirv/unified1/spirv.core.grammar.json";

    const json = blk: {
        var client = std.http.Client { .allocator = allocator };
        defer client.deinit();
        var headers = std.http.Headers { .allocator = allocator };
        defer headers.deinit();
        headers.append("Accept", "application/json") catch return 1; // TODO
        headers.append("Connection", "close") catch return 1; // TODO
        var request = client.request(.GET, std.Uri.parse(uri) catch |err| {
            stderr.print("\x1B[1;91mError: Failed to parse provided URI ({s})\x1B[0m\n", .{ @errorName(err) }) catch {};
            return 1;
        }, headers, .{}) catch |err| {
            stderr.print("\x1B[1;91mError: Failed to send HTTP GET request to provided URI ({s})\x1B[0m\n", .{ @errorName(err) }) catch {};
            return 1;
        };
        defer request.deinit();
        request.start() catch return 1; // TODO
        request.wait() catch return 1; // TODO

        // https://registry.khronos.org/SPIR-V/specs/unified1/MachineReadableGrammar.html
        // https://github.com/ziglang/zig/blob/master/tools/spirv/grammar.zig
        @setEvalBranchQuota(10_000); // Idrk what this means...
        var reader = std.json.reader(allocator, request.reader());
        defer reader.deinit();
        var diagnostics = std.json.Diagnostics {};
        reader.enableDiagnostics(&diagnostics);
        break :blk std.json.parseFromTokenSource(Registry, allocator, &reader, .{}) catch |err| {
            stderr.print("\x1B[1;91mError: Failed to parse received JSON ({s}, line: {d}, column: {d})\x1B[0m\n", .{ @errorName(err), diagnostics.getLine(), diagnostics.getColumn() }) catch {};
            return 1;
        };
    };
    defer json.deinit();

    var stdout = std.io.bufferedWriter(std.io.getStdOut().writer());
    defer stdout.flush() catch |err| stderr.print("Failed to flush stdout buffer: error \"{s}\"\n", .{ @errorName(err) }) catch {};

    render(stdout.writer(), json.value) catch |err| {
        stderr.print("\x1B[1;91mError: Failed to render output file ({s})\x1B[0m\n", .{ @errorName(err) }) catch {};
        return 1;
    };

    return 0;
}

inline fn render(stream: anytype, registry: Registry) !void {
    try stream.print(
        \\pub const Word = u32;
        \\pub const Header = opaque {{
        \\    pub const magic: Word = {s};
        \\    pub const version: Word = 0x000{d}0{d}00; // Version {d}.{d}.{d}
        \\    pub const generator: Word = 0x00000000;
        \\    pub const schema: Word = 0x00000000;
        \\    pub fn emit(bound: Word) []const Word {{
        \\        return .{{ magic, version, generator, bound, schema }};
        \\    }};
        \\}};
        \\
        ,
        .{
            registry.magic_number,
            registry.major_version,
            registry.minor_version,
            registry.major_version,
            registry.minor_version,
            registry.revision,
        },
    );
}
