const builtin = @import("builtin");
const std = @import("std");

const build = @import("build.zig");
const extract = @import("extract.zig");
const talkie_build = @import("talkie_build.zig");
const talkie_extract = @import("talkie_extract.zig");

const version = "0.5.0";

pub fn main() !u8 {
    runCli() catch |err| {
        if (err == error.CommandLine) {
            try std.io.getStdErr().writeAll(usage);
            return 1;
        }
        if (err == error.CommandLineReported) {
            return 1;
        }
        return err;
    };
    return 0;
}

fn runCli() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 1 + 1)
        return error.CommandLine;

    const command = args[1];

    if (std.mem.eql(u8, command, "-h") or std.mem.eql(u8, command, "--help"))
        return std.io.getStdOut().writeAll(usage);

    if (std.mem.eql(u8, command, "build")) {
        try build.runCli(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "extract")) {
        try extract.runCli(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "talkie")) {
        if (args.len < 1 + 2)
            return error.CommandLine;
        const subcommand = args[2];
        if (std.mem.eql(u8, subcommand, "build")) {
            try talkie_build.runCli(allocator, args[3..]);
        } else if (std.mem.eql(u8, subcommand, "extract")) {
            try talkie_extract.runCli(allocator, args[3..]);
        } else {
            return error.CommandLine;
        }
    } else if (std.mem.eql(u8, command, "version")) {
        try std.io.getStdOut().writeAll(version);
    } else {
        return error.CommandLine;
    }
}

const usage =
    \\Baller <https://github.com/whatisaphone/baller> licensed under AGPL 3.0
    \\
    \\A modding tool for Backyard Sports games.
    \\
    \\Usage:
    \\
    \\baller extract <index> <output>
    \\
    \\    <index>       Path to index file ending in .he0
    \\    <output>      Path to output directory
    \\    [--symbols=]  Path to symbols.ini
    \\
    \\baller build <project> <output>
    \\
    \\    <project>     Path to project.txt, typically generated by baller
    \\                  extract
    \\    <output>      Path to output file ending in .he0
    \\
    \\baller talkie extract <input> <output>
    \\
    \\    <input>       Path to talkie file ending in .he2
    \\    <output>      Path to output directory
    \\
    \\baller talkie build <manifest> <output>
    \\
    \\    <manifest>    Path to talkies.txt, typically generated by baller
    \\                  talkie extract
    \\    <output>      Path to output file ending in .he2
    \\
    \\baller version
;

comptime {
    // Sorry, IBM mainframe users
    std.debug.assert(builtin.cpu.arch.endian() == .little);
}

test {
    _ = @import("tests.zig");
}
