const std = @import("std");

const ___tracy_source_location_data = extern struct {
    name: ?[*:0]const u8,
    function: [*:0]const u8,
    file: [*:0]const u8,
    line: u32,
    color: u32,
};

const ___tracy_c_zone_context = extern struct {
    id: u32,
    active: c_int,

    pub const deinit = ___tracy_emit_zone_end;
};

extern fn ___tracy_emit_zone_begin_callstack(srcloc: *const ___tracy_source_location_data, depth: c_int, active: c_int) ___tracy_c_zone_context;
extern fn ___tracy_emit_zone_end(ctx: ___tracy_c_zone_context) void;

pub inline fn init(comptime src: std.builtin.SourceLocation, comptime name: ?[*:0]const u8) ___tracy_c_zone_context {
    const callstack_depth = 16; // TODO: Consider making this a parameter.
    return ___tracy_emit_zone_begin_callstack(&.{
        .name = name,
        .function = src.fn_name.ptr,
        .file = src.file.ptr,
        .line = src.line,
        .color = 0,
    }, callstack_depth, 1);
}
