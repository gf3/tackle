const std = @import("std");
const glib = @import("glib");
const c = @cImport({
    @cInclude("time.h");
});

pub const Error = error{
    InvalidLength,
    InvalidCharacter,
};

const bytes_time = 10;
const bytes_entropy = 16;
const alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";

fn fromBase32(ch: u8) !u5 {
    return switch (ch) {
        '0'...'9' => @as(u5, @intCast(ch - '0')),
        'A'...'H' => @as(u5, @intCast(ch - 'A' + 10)),
        'J'...'K' => @as(u5, @intCast(ch - 'J' + 18)),
        'M'...'N' => @as(u5, @intCast(ch - 'M' + 20)),
        'P'...'T' => @as(u5, @intCast(ch - 'P' + 22)),
        'V'...'Z' => @as(u5, @intCast(ch - 'V' + 27)),
        else => Error.InvalidCharacter,
    };
}

pub const Ulid = struct {
    time: u48 = 0,
    entropy: u80 = 0,

    pub fn time_str(self: Ulid, allocator: std.mem.Allocator) ![:0]const u8 {
        var buf: [64]u8 = undefined;
        const time = @as(c.time_t, @intCast(self.time / 1000));
        const tm: *c.struct_tm = c.localtime(&time);
        const written = c.strftime(&buf, 64, "%B %d, %Y %H:%M:%S", tm);

        const output = buf[0..written :0];

        var copy = try allocator.allocSentinel(u8, written + 1, 0);

        std.mem.copyForwards(u8, copy, output);
        copy[written] = 0;

        return copy;
    }

    pub fn uuid(self: Ulid) u128 {
        return @as(u128, self.time) << 80 | @as(u128, self.entropy);
    }

    pub fn uuid_str(self: Ulid, allocator: std.mem.Allocator) ![:0]u8 {
        const part1 = @as(u32, @intCast(self.time >> 16));
        const part2 = @as(u16, @truncate(self.time));
        const part3 = @as(u16, @intCast(self.entropy >> 64));
        const part4 = @as(u16, @truncate(self.entropy >> 48));
        const part5 = @as(u48, @truncate(self.entropy));

        var output = try allocator.allocSentinel(u8, 37, 0);
        _ = try std.fmt.bufPrint(@ptrCast(output), "{X:0>8}-{X:0>4}-{X:0>4}-{X:0>4}-{X:0>12}", .{ part1, part2, part3, part4, part5 });

        output[36] = 0;

        return output;
    }
};

pub fn decode(ulid: [:0]u8) !Ulid {
    if (ulid.len != 26) {
        return Error.InvalidLength;
    }

    var uuid: u128 = 0;

    for (ulid) |ch| {
        uuid = (uuid << 5) | try fromBase32(ch);
    }

    const time = @as(u48, @truncate(uuid >> 80));
    const entropy = @as(u80, @truncate(uuid));

    return .{
        .time = time,
        .entropy = entropy,
    };
}

test "decode" {
    const str = "01ARYZ6S41TSV4RRFFQ69G5FAV"; // 01563DF3-6481-D676-4C61-EFB99302BD5B
    const result = try decode(@constCast(str));

    try std.testing.expect(result.time == 1469918176385);
}

test "Ulid.uuid" {
    const str = "01ARYZ6S41TSV4RRFFQ69G5FAV"; // 01563DF3-6481-D676-4C61-EFB99302BD5B
    const result = try decode(@constCast(str));

    try std.testing.expect(result.uuid() == 1777022036153689948599198395857550683);
}

test "Ulid.uuid_str" {
    const allocator = std.testing.allocator;
    const str = "01ARYZ6S41TSV4RRFFQ69G5FAV"; // 01563DF3-6481-D676-4C61-EFB99302BD5B
    const result = try decode(@constCast(str));
    const uuid_str = try result.uuid_str(allocator);
    defer allocator.free(uuid_str);
    const expected_uuid_str = [37:0]u8{ '0', '1', '5', '6', '3', 'D', 'F', '3', '-', '6', '4', '8', '1', '-', 'D', '6', '7', '6', '-', '4', 'C', '6', '1', '-', 'E', 'F', 'B', '9', '9', '3', '0', '2', 'B', 'D', '5', 'B', 0 };

    try std.testing.expect(std.mem.eql(u8, uuid_str, &expected_uuid_str));
}

test "Ulid.time_str" {
    const allocator = std.testing.allocator;
    const str = "01ARYZ6S41TSV4RRFFQ69G5FAV"; // 01563DF3-6481-D676-4C61-EFB99302BD5B
    const result = try decode(@constCast(str));
    const time_str = try result.time_str(allocator);
    defer allocator.free(time_str);
    const expected_time_str = [23:0]u8{ 'J', 'u', 'l', 'y', ' ', '3', '0', ',', ' ', '2', '0', '1', '6', ' ', '2', '2', ':', '3', '6', ':', '1', '6', 0 };

    try std.testing.expect(std.mem.eql(u8, time_str, &expected_time_str));
}
