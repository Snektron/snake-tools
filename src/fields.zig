const std = @import("std");
const Allocator = std.mem.Allocator;

const FieldSpecifier = enum(usize) {
    const max_fields = std.math.maxInt(usize);

    end = max_fields,
    _,
};

const FieldRange = struct {
    begin: FieldSpecifier,
    end: FieldSpecifier,
};

const Options = struct {
    prog: []const u8,
    delimiters: []const u8,
    help: bool,
    fields: []const FieldRange,

    fn parseFieldSpecifier(str: []const u8) !usize {
        invalid: {
            const field = std.fmt.parseInt(usize, str, 0) catch return error.InvalidFormat;
            if (field == 0) break :invalid;
            return field - 1;
        }

        return error.InvalidFormat;
    }

    fn parseFieldRange(str: []const u8) !FieldRange {
        const split = std.mem.indexOfScalar(u8, str, ':') orelse {
            const field = try parseFieldSpecifier(str);
            return FieldRange{
                .begin = @enumFromInt(field),
                .end = @enumFromInt(field),
            };
        };

        const begin = if (split == 0) 0 else try parseFieldSpecifier(str[0..split]);
        const end: FieldSpecifier = if (split == str.len - 1)
            .end
        else
            @enumFromInt(try parseFieldSpecifier(str[split + 1..]));

        if (begin >= FieldSpecifier.max_fields or begin > @intFromEnum(end)) {
            return error.InvalidFormat;
        }

        return FieldRange{
            .begin = @enumFromInt(begin),
            .end = end,
        };
    }

    fn parse(allocator: Allocator) !Options {
        const stderr = std.io.getStdErr().writer(); // TODO: Buffered?
        var args = std.process.args();

        const prog = args.next() orelse return error.ExecutableNameMissing;

        var delimiters: ?[]const u8 = null;
        var help = false;
        var fields = std.ArrayList(FieldRange).init(allocator);
        defer fields.deinit();

        invalid: {
            while (args.next()) |arg| {
                if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
                    help = true;
                } else if (std.mem.eql(u8, arg, "-d") or std.mem.eql(u8, arg, "--delimiters")) {
                    delimiters = args.next() orelse {
                        try stderr.print("error: option '{s}' requires argument <delim>\n", .{ arg });
                        break :invalid;
                    };
                    if (delimiters.?.len == 0) {
                        try stderr.print("error: <delim> must be 1 character or more\n", .{});
                        break :invalid;
                    }
                } else if (arg.len >= 1 and arg[0] == '-') {
                    try stderr.print("error: invalid option '{s}'\n", .{ arg });
                    break :invalid;
                } else {
                    const range = parseFieldRange(arg) catch {
                        try stderr.print("error: invalid field range '{s}'\n", .{ arg });
                        break :invalid;
                    };
                    try fields.append(range);
                }
            }

            if (fields.items.len == 0) {
                try fields.append(.{
                    .begin = @enumFromInt(0),
                    .end = .end,
                });
            }

            return Options {
                .prog = prog,
                .delimiters = delimiters orelse " \t",
                .help = help,
                .fields = try fields.toOwnedSlice(),
            };
        }

        try stderr.print("Try '{s} --help'\n", .{ prog });
        return error.InvalidUsageReported;
    }

    fn deinit(self: *Options, allocator: Allocator) void {
        allocator.free(self.fields);
        self.* = undefined;
    }
};

pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() != .ok) {
        unreachable; // Memory leaked
    };
    const allocator = gpa.allocator();

    const stdout_file = std.io.getStdOut();
    var bw = std.io.bufferedWriter(stdout_file.writer());
    const stdout = bw.writer();

    var options = Options.parse(allocator) catch |err| switch (err) {
        error.InvalidUsageReported => return 1,
        else => |others| return others,
    };
    defer options.deinit(allocator);

    if (options.help) {
        try stdout.print(
            \\Usage: {s} [options...] <fields...>
            \\Prints selected fields from standard input to standard output.
            \\
            \\Options:
            \\-d --delimiters <delim>   Delimiters to split fields by. Fields are separated by
            \\                          any number of delimiters. By default, fields are split
            \\                          on whitespace (space and tab).
            \\
            \\Fields to select are given in the following formats:
            \\  N    Picks the N'th field, counting from 1.
            \\  N:   From the N'th field to the end of the line.
            \\  N:M  From the N'th field to and including the M'th field.
            \\  :M   From the start of the line until and including the M'th field.
            \\
            , .{options.prog},
        );
        try bw.flush();
        return 0;
    }


    const stdin_file = std.io.getStdIn();
    var br = std.io.bufferedReader(stdin_file.reader());
    const stdin = br.reader();

    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();

    // TODO: This can be optimized
    var fields = std.ArrayList([]const u8).init(allocator);
    defer fields.deinit();

    var stop = false;
    while (!stop) {
        buf.items.len = 0;
        fields.items.len = 0;
        stdin.streamUntilDelimiter(buf.writer(), '\n', null) catch |err| switch (err) {
            error.EndOfStream => stop = true,
            else => |others| return others,
        };

        if (buf.items.len == 0) {
            break;
        }

        var it = std.mem.tokenizeAny(u8, buf.items, options.delimiters);
        while (it.next()) |field| {
            try fields.append(field);
        }

        if (fields.items.len != 0) {
            for (options.fields) |range| {
                const begin = @intFromEnum(range.begin);
                const end = switch (range.end) {
                    .end => fields.items.len - 1,
                    else => |field| @intFromEnum(field),
                };

                for (begin..end + 1) |field| {
                    if (field < fields.items.len) {
                        try stdout.writeAll(fields.items[field]);
                        try stdout.writeByte(' ');
                    }
                }
            }
        }

        try stdout.writeByte('\n');
    }

    try bw.flush();
    return 0;
}
