const std = @import("std");

const Language = struct {
    // TODO: don't hardcode maximum
    /// 0 to 255 are normal opcodes. The rest are dynamically-assigned
    /// 256-element chunks for two-byte opcodes.
    opcodes: [256 * 48]Opcode = .{.unknown} ** (256 * 48),
    num_nested: u8 = 0,

    fn add(self: *Language, byte: u8, name: []const u8, args: []const Arg) void {
        if (self.opcodes[byte] != .unknown)
            unreachable;

        self.opcodes[byte] = .{ .ins = .{
            .name = name,
            .args = std.BoundedArray(Arg, 2).fromSlice(args) catch unreachable,
        } };
    }

    fn addNested(
        self: *Language,
        byte1: u8,
        byte2: u8,
        name: []const u8,
        args: []const Arg,
    ) void {
        const n = switch (self.opcodes[byte1]) {
            .unknown => n: {
                self.num_nested += 1;
                self.opcodes[byte1] = .{ .nested = self.num_nested };
                break :n self.num_nested;
            },
            .nested => |n| n,
            else => unreachable,
        };

        self.opcodes[n << 8 | byte2] = .{ .ins = .{
            .name = name,
            .args = std.BoundedArray(Arg, 2).fromSlice(args) catch unreachable,
        } };
    }
};

const Opcode = union(enum) {
    unknown,
    ins: Ins,
    nested: u16,
};

const Ins = struct {
    name: []const u8,
    args: std.BoundedArray(Arg, 2),
};

const Arg = enum {
    u8,
    i16,
    i32,
    variable,
    string,
};

const Variable = struct {
    raw: u16,

    const Decoded = union(enum) {
        global: u16,
        local: u16,
        room: u16,
    };

    fn decode(self: Variable) !Decoded {
        return switch (self.raw & 0xc000) {
            0x0000 => .{ .global = self.raw & 0x3fff },
            0x4000 => .{ .local = self.raw & 0x3fff },
            0x8000 => .{ .room = self.raw & 0x3fff },
            0xc000 => error.BadData,
            else => unreachable,
        };
    }
};

fn buildLanguage() Language {
    var lang = Language{};

    lang.add(0x00, "push", &.{.u8});
    lang.add(0x01, "push", &.{.i16});
    lang.add(0x02, "push", &.{.i32});
    lang.add(0x03, "push", &.{.variable});
    lang.add(0x04, "push", &.{.string});
    lang.add(0x07, "get-array-item", &.{.variable});
    lang.add(0x0b, "get-array-item-2d", &.{.variable});
    lang.add(0x0c, "dup", &.{});
    lang.add(0x0d, "not", &.{});
    lang.add(0x0e, "compare-equal", &.{});
    lang.add(0x0f, "compare-not-equal", &.{});
    lang.add(0x10, "compare-greater", &.{});
    lang.add(0x11, "compare-less", &.{});
    lang.add(0x12, "compare-less-or-equal", &.{});
    lang.add(0x13, "compare-greater-or-equal", &.{});
    lang.add(0x14, "add", &.{});
    lang.add(0x15, "sub", &.{});
    lang.add(0x16, "mul", &.{});
    lang.add(0x17, "div", &.{});
    lang.add(0x18, "and", &.{});
    lang.add(0x19, "or", &.{});
    lang.add(0x1a, "pop", &.{});
    lang.add(0x1b, "in-list", &.{});

    lang.addNested(0x1c, 0x20, "image-set-width", &.{});
    lang.addNested(0x1c, 0x21, "image-set-height", &.{});
    lang.addNested(0x1c, 0x30, "image-draw", &.{});
    lang.addNested(0x1c, 0x34, "image-set-state", &.{});
    lang.addNested(0x1c, 0x39, "image-select", &.{});
    lang.addNested(0x1c, 0x41, "image-set-pos", &.{});
    lang.addNested(0x1c, 0x56, "image-set-palette", &.{});
    lang.addNested(0x1c, 0x85, "image-set-draw-box", &.{});
    lang.addNested(0x1c, 0x89, "image-set-render-image", &.{});
    lang.addNested(0x1c, 0x9a, "image-set-hotspot", &.{});
    lang.addNested(0x1c, 0xd9, "image-new", &.{});
    lang.addNested(0x1c, 0xff, "image-commit", &.{});

    lang.add(0x1d, "min", &.{});
    lang.add(0x1e, "max", &.{});
    lang.add(0x1f, "sin", &.{});
    lang.add(0x20, "cos", &.{});
    lang.add(0x22, "angle-from-delta", &.{});
    lang.add(0x23, "angle-from-line", &.{});

    lang.addNested(0x24, 0x1c, "line-length-2d", &.{});
    lang.addNested(0x24, 0x1d, "line-length-3d", &.{});

    lang.addNested(0x25, 0x1f, "sprite-get-object-y", &.{});
    lang.addNested(0x25, 0x2d, "find-sprite", &.{});
    lang.addNested(0x25, 0x34, "sprite-get-state", &.{});
    lang.addNested(0x25, 0x3f, "sprite-get-image", &.{});
    lang.addNested(0x25, 0x7d, "sprite-class", &.{});

    lang.addNested(0x26, 0x25, "sprite-set-group", &.{});
    lang.addNested(0x26, 0x2b, "sprite-set-order", &.{});
    lang.addNested(0x26, 0x2c, "sprite-move", &.{});
    lang.addNested(0x26, 0x34, "sprite-set-state", &.{});
    lang.addNested(0x26, 0x39, "sprite-select-range", &.{});
    lang.addNested(0x26, 0x3f, "sprite-set-image", &.{});
    lang.addNested(0x26, 0x41, "sprite-set-position", &.{});
    lang.addNested(0x26, 0x52, "sprite-set-animation-type", &.{});
    lang.addNested(0x26, 0x56, "sprite-set-palette", &.{});
    lang.addNested(0x26, 0x7c, "sprite-set-update-type", &.{});
    lang.addNested(0x26, 0x7d, "sprite-set-class", &.{});
    lang.addNested(0x26, 0x9e, "sprite-restart", &.{});
    lang.addNested(0x26, 0xd9, "sprite-new", &.{});

    lang.addNested(0x27, 0x08, "sprite-group-get", &.{});

    lang.addNested(0x28, 0x39, "sprite-group-select", &.{});
    lang.addNested(0x28, 0xd9, "sprite-group-new", &.{});

    lang.addNested(0x29, 0x1e, "image-get-object-x", &.{});
    lang.addNested(0x29, 0x1f, "image-get-object-y", &.{});
    lang.addNested(0x29, 0x20, "image-get-width", &.{});
    lang.addNested(0x29, 0x21, "image-get-height", &.{});
    lang.addNested(0x29, 0x42, "image-get-state-color-at", &.{});

    lang.add(0x30, "mod", &.{});
    lang.add(0x31, "shl", &.{});
    lang.add(0x32, "shr", &.{});
    lang.add(0x34, "find-all-objects", &.{});
    lang.add(0x36, "iif", &.{});
    lang.add(0x37, "dim-array", &.{ .u8, .variable });

    lang.addNested(0x3a, 0x81, "array-sort", &.{.variable});

    lang.add(0x43, "assign", &.{.variable});
    lang.add(0x47, "set-array-item", &.{.variable});
    lang.add(0x48, "string-number", &.{});
    lang.add(0x4b, "set-array-item-2d", &.{.variable});

    lang.addNested(0x4d, 0x06, "read-ini-int", &.{});
    lang.addNested(0x4d, 0x07, "read-ini-string", &.{});

    lang.addNested(0x4e, 0x06, "write-ini-int", &.{});
    lang.addNested(0x4e, 0x07, "write-ini-string", &.{});

    lang.add(0x4f, "inc", &.{.variable});
    lang.add(0x53, "inc-array-item", &.{.variable});
    lang.add(0x57, "dec", &.{.variable});
    lang.add(0x5a, "sound-position", &.{});
    lang.add(0x5b, "dec-array-item", &.{.variable});
    lang.add(0x5c, "jump-if", &.{.i16});
    lang.add(0x5d, "jump-unless", &.{.i16});

    lang.addNested(0x5e, 0x01, "start-script", &.{});
    lang.addNested(0x5e, 0xc3, "start-script-rec", &.{});

    lang.addNested(0x60, 0x01, "start-object", &.{});
    lang.addNested(0x60, 0xc3, "start-object-rec", &.{});

    lang.addNested(0x63, 0x01, "array-get-dim", &.{.variable});
    lang.addNested(0x63, 0x02, "array-get-dim-2d-height", &.{.variable});
    lang.addNested(0x63, 0x03, "array-get-dim-2d-width", &.{.variable});

    lang.add(0x64, "free-arrays", &.{});
    lang.add(0x66, "end", &.{});

    lang.addNested(0x69, 0x39, "window-select", &.{});
    lang.addNested(0x69, 0x3a, "window-set-script", &.{});
    lang.addNested(0x69, 0x3f, "window-set-image", &.{});
    lang.addNested(0x69, 0xd9, "window-new", &.{});
    lang.addNested(0x69, 0xf3, "window-set-title-bar", &.{});
    lang.addNested(0x69, 0xff, "window-commit", &.{});

    lang.addNested(0x6b, 0x13, "cursor-bw", &.{});
    lang.addNested(0x6b, 0x14, "cursor-color", &.{});
    lang.addNested(0x6b, 0x90, "cursor-on", &.{});
    lang.addNested(0x6b, 0x91, "cursor-off", &.{});
    lang.addNested(0x6b, 0x93, "userput-off", &.{});
    lang.addNested(0x6b, 0x9c, "charset", &.{});

    lang.add(0x6c, "break-here", &.{});
    lang.add(0x6d, "class-of", &.{});
    lang.add(0x6e, "object-set-class", &.{});
    lang.add(0x73, "jump", &.{.i16});

    lang.addNested(0x74, 0x09, "sound-soft", &.{});
    lang.addNested(0x74, 0xe6, "sound-channel", &.{});
    lang.addNested(0x74, 0xe7, "sound-at", &.{});
    lang.addNested(0x74, 0xe8, "sound-select", &.{});
    lang.addNested(0x74, 0xff, "sound-start", &.{});

    lang.add(0x75, "stop-sound", &.{});
    lang.add(0x7b, "current-room", &.{});
    lang.add(0x7c, "end-script", &.{});
    lang.add(0x7f, "put-actor", &.{});
    lang.add(0x82, "do-animation", &.{});
    lang.add(0x87, "random", &.{});
    lang.add(0x88, "random-between", &.{});
    lang.add(0x8b, "script-running", &.{});
    lang.add(0x8c, "actor-room", &.{});

    lang.addNested(0x94, 0x42, "palette-color", &.{});
    lang.addNested(0x94, 0xd9, "rgb", &.{});

    lang.add(0x98, "sound-running", &.{});

    lang.addNested(0x9b, 0x64, "load-script", &.{});
    lang.addNested(0x9b, 0x65, "load-sound", &.{});
    lang.addNested(0x9b, 0x67, "load-room", &.{});
    lang.addNested(0x9b, 0x6c, "lock-script", &.{});
    lang.addNested(0x9b, 0x75, "load-charset", &.{});
    lang.addNested(0x9b, 0xc0, "nuke-image", &.{});
    lang.addNested(0x9b, 0xc9, "load-image", &.{});

    lang.addNested(0x9c, 0xb5, "fades", &.{});

    lang.addNested(0x9d, 0x4c, "actor-set-costume", &.{});
    lang.addNested(0x9d, 0xc5, "actor-select", &.{});
    lang.addNested(0x9d, 0xc6, "actor-set-var", &.{});
    lang.addNested(0x9d, 0xd9, "actor-new", &.{});

    lang.addNested(0x9e, 0x39, "palette-select", &.{});
    lang.addNested(0x9e, 0x3f, "palette-from-image", &.{});
    lang.addNested(0x9e, 0xd9, "palette-new", &.{});
    lang.addNested(0x9e, 0xff, "palette-commit", &.{});

    lang.add(0x9f, "find-actor", &.{});
    lang.add(0xa0, "find-object", &.{});
    lang.add(0xa3, "valid-verb", &.{});

    lang.addNested(0xa4, 0x07, "assign-string", &.{.variable});
    lang.addNested(0xa4, 0x7e, "array-assign-list", &.{.variable});
    lang.addNested(0xa4, 0x7f, "array-assign-slice", &.{ .variable, .variable });
    lang.addNested(0xa4, 0x80, "array-assign-range", &.{.variable});
    lang.addNested(0xa4, 0xc2, "sprintf", &.{.variable});
    lang.addNested(0xa4, 0xd0, "array-assign", &.{.variable});

    lang.add(0xa6, "draw-box", &.{});
    lang.add(0xa7, "debug", &.{});

    lang.addNested(0xa9, 0xa9, "wait-for-message", &.{});

    lang.add(0xad, "in2", &.{});
    lang.add(0xb3, "stop-sentence", &.{});

    lang.addNested(0xb5, 0x41, "print-text-position", &.{});
    lang.addNested(0xb5, 0x45, "print-text-center", &.{});
    lang.addNested(0xb5, 0xc2, "print-text-printf", &.{.string});
    lang.addNested(0xb5, 0xfe, "print-text-start", &.{});

    lang.addNested(0xb6, 0x4b, "print-debug-string", &.{.string});
    lang.addNested(0xb6, 0xc2, "print-debug-printf", &.{.string});
    lang.addNested(0xb6, 0xfe, "print-debug-start", &.{});

    lang.addNested(0xb7, 0x4b, "print-system-string", &.{.string});
    lang.addNested(0xb7, 0xfe, "print-system-start", &.{});

    // TODO: first arg is item size; 0xcc means undim
    lang.add(0xbc, "dim-array", &.{ .u8, .variable });

    lang.add(0xbd, "return", &.{});
    lang.add(0xbf, "call-script", &.{});
    lang.add(0xc0, "dim-array-2d", &.{ .u8, .variable });
    lang.add(0xc1, "debug-string", &.{});
    lang.add(0xc4, "abs", &.{});
    lang.add(0xc9, "kludge", &.{});
    lang.add(0xca, "break-here-multi", &.{});
    lang.add(0xcb, "pick", &.{});
    lang.add(0xcf, "debug-input", &.{});
    lang.add(0xd0, "get-time-date", &.{});
    lang.add(0xd1, "stop-line", &.{});
    lang.add(0xd4, "shuffle", &.{.variable});

    lang.addNested(0xd5, 0x01, "chain-script", &.{});
    lang.addNested(0xd5, 0xc3, "chain-script-rec", &.{});

    lang.add(0xd6, "band", &.{});
    lang.add(0xd7, "bor", &.{});
    lang.add(0xd9, "close-file", &.{});
    lang.add(0xda, "open-file", &.{});

    lang.addNested(0xdb, 0x08, "read-file-int8", &.{.u8});

    lang.addNested(0xdc, 0x08, "write-file-int8", &.{.u8});

    lang.add(0xe2, "what", &.{});
    lang.add(0xe3, "pick-random", &.{.variable});
    lang.add(0xea, "redim-array", &.{ .u8, .variable });
    lang.add(0xec, "string-copy", &.{});
    lang.add(0xed, "string-width", &.{});
    lang.add(0xee, "string-length", &.{});
    lang.add(0xef, "string-substr", &.{});

    lang.addNested(0xf3, 0x06, "read-ini-int", &.{});
    lang.addNested(0xf3, 0x07, "read-ini-string", &.{});

    lang.addNested(0xf4, 0x06, "write-ini-int", &.{});
    lang.addNested(0xf4, 0x07, "write-ini-string", &.{});

    lang.add(0xf5, "string-margin", &.{});
    lang.add(0xf6, "string-search", &.{});

    lang.addNested(0xf8, 0x0d, "sound-size", &.{});

    lang.addNested(0xfa, 0xf3, "title-bar", &.{});

    lang.add(0xfc, "find-polygon", &.{});

    return lang;
}

pub fn disasm(bytecode: []const u8, out: anytype) !void {
    const lang = buildLanguage(); // TODO: cache this

    var reader = std.io.fixedBufferStream(bytecode);

    while (reader.pos < bytecode.len) {
        const b1 = try reader.reader().readByte();
        switch (lang.opcodes[b1]) {
            .unknown => try flushUnknownBytes(&reader, out, 1),
            .ins => |*ins| try disasmIns(ins, &reader, out),
            .nested => |n| {
                const b2 = try reader.reader().readByte();
                switch (lang.opcodes[n << 8 | b2]) {
                    .unknown => try flushUnknownBytes(&reader, out, 2),
                    .ins => |*ins| try disasmIns(ins, &reader, out),
                    .nested => unreachable,
                }
            },
        }
    }
}

fn flushUnknownBytes(reader: anytype, out: anytype, leading: u8) !void {
    reader.pos -= leading;
    while (reader.pos < reader.buffer.len) {
        const b = try reader.reader().readByte();
        try out.print(".db 0x{x:0>2}\n", .{b});
    }
}

fn disasmIns(ins: *const Ins, reader: anytype, out: anytype) !void {
    try out.writeAll(ins.name);
    for (ins.args.slice()) |*arg| {
        try out.writeByte(' ');
        try disasmArg(arg, reader, out);
    }
    try out.writeByte('\n');
}

fn disasmArg(arg: *const Arg, reader: anytype, out: anytype) !void {
    switch (arg.*) {
        .u8 => {
            const n = try reader.reader().readInt(u8, .little);
            try out.print("{}", .{n});
        },
        .i16 => {
            const n = try reader.reader().readInt(i16, .little);
            try out.print("{}", .{n});
        },
        .i32 => {
            const n = try reader.reader().readInt(i32, .little);
            try out.print("{}", .{n});
        },
        .variable => {
            const variable = try readVariable(reader);
            try emitVariable(out, variable);
        },
        .string => {
            // TODO: escaping
            try out.writeByte('"');
            try out.writeAll(try readString(reader));
            try out.writeByte('"');
        },
    }
}

fn readVariable(reader: anytype) !Variable {
    const raw = try reader.reader().readInt(u16, .little);
    return .{ .raw = raw };
}

fn emitVariable(out: anytype, variable: Variable) !void {
    switch (try variable.decode()) {
        .global => |num| try out.print("global{}", .{num}),
        .local => |num| try out.print("local{}", .{num}),
        .room => |num| try out.print("room{}", .{num}),
    }
}

fn readString(reader: anytype) ![]const u8 {
    const start = reader.pos;
    const null_pos = std.mem.indexOfScalarPos(u8, reader.buffer, start, 0) orelse
        return error.BadData;
    reader.pos = null_pos + 1;
    return reader.buffer[start..null_pos];
}