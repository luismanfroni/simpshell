const std = @import("std");
var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);

const stdin = std.io.getStdIn().reader();
const stdout = std.io.getStdOut().writer();
var last_exit: ?u32 = null;

pub fn writePrompt() !void {
    const env_map = try std.process.getEnvMap(arena.allocator());
    const pwd = env_map.get("PWD").?;
    const usr = env_map.get("USER").?;
    const is_root = std.mem.eql(u8, "root", usr);

    try stdout.print("{s} @ {s}", .{ usr, pwd });

    if (last_exit != null and last_exit.? != 0) 
        try stdout.print(" <{any}> ", .{ last_exit });

    if (is_root) {
        try stdout.print("\n# ", .{});
    } else {
        try stdout.print("\n$ ", .{});
    }
}

pub fn runCommand(file: [*:0]const u8, argv_ptr: [*:null]const ?[*:0]const u8) !void {
    const fork_pid = try std.os.fork();
    const is_child = fork_pid == 0;
    if (is_child) {
        const env = [_:null]?[*:0]u8{null};
        const execv_err = std.os.execvpeZ(file, argv_ptr, &env);
        switch(execv_err) {
            std.os.ExecveError.AccessDenied => {
                try stdout.print("Access denied\n", .{});
            },
            std.os.ExecveError.FileNotFound => {
                try stdout.print("Command not found\n", .{});
            },
            std.os.ExecveError.InvalidExe => {
                try stdout.print("Invalid Exe\n", .{});
            },
            else => {
                try stdout.print("Unknown error!\n", .{});
            }   
        }
        return;
    } else {
        const wait_result = std.os.waitpid(fork_pid, 0);
        last_exit = wait_result.status;
    }
}

pub fn interruptHandler(_: c_int) callconv(.C) void {
    _ = stdout.write("\n") catch unreachable;
    write_prompt() catch unreachable;
}

pub fn main() !u8 {
    defer arena.deinit();
    var mask: [32]u32 = .{0} ** 32;
    const sig_handle = .{
        .handler = .{
            .handler = interruptHandler
        },
        .mask = mask,
        .flags = 0
    };
    _ = std.os.linux.sigaction(std.os.linux.SIG.INT, &sig_handle, null);
    
    var run = true;
    while (run) {
        try writePrompt();

        const input = stdin.readUntilDelimiterAlloc(arena.allocator(), '\n', 2048) catch unreachable;
        if (input.len == 0) continue;

        var arguments: [40][255:0]u8 = undefined;
        var arguments_ptr: [40:null]?[*:0]u8 = undefined;

        var tokens = std.mem.split(u8, input, " ");

        var i: usize = 0;
        while (tokens.next()) |tok| {
            std.mem.copy(u8, &arguments[i], tok);
            arguments[i][tok.len] = 0;
            arguments_ptr[i] = &arguments[i];
            i += 1;
        }
        arguments_ptr[i] = null;
        const command = std.mem.span(arguments_ptr[0].?);
        if (std.mem.eql(u8, command, "exit")) {
            run = false;
            break;
        }

        try runCommand(arguments_ptr[0].?, &arguments_ptr);
    }
    return 0;
}