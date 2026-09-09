//! The automation CLI's checked source-write pipeline. Transport only obtains
//! the provenance response; this module owns every refusal before disk write.
const std = @import("std");
const markup = @import("ui_markup.zig");

pub const Result = struct {
    file_path: []const u8,
    span_start: usize,
};

const Anchor = struct {
    file_path: []const u8,
    root_path: []const u8,
    hash: u64,
    span_start: usize,
};

/// Response/result strings borrow `response`; temporary edited bytes belong
/// to `arena`. The file is written only after all provenance and edit checks.
pub fn apply(arena: std.mem.Allocator, io: std.Io, response: []const u8, op: markup.edit.EditOp) !Result {
    const anchor = try parseAnchor(response);
    const source = try readCurrentSource(arena, io, anchor);
    var diagnostic: markup.MarkupErrorInfo = .{};
    const edited = markup.edit.applyChecked(arena, source, anchor.span_start, op, &diagnostic) catch {
        std.debug.print("error: edit refused at {s}:{d}:{d}: {s}\n", .{ anchor.file_path, diagnostic.line, diagnostic.column, diagnostic.message });
        return error.AutomationCommandFailed;
    };
    try validateEditedClosure(arena, io, anchor.root_path, anchor.file_path, edited);
    std.Io.Dir.cwd().writeFile(io, .{ .sub_path = anchor.file_path, .data = edited }) catch {
        std.debug.print("error: could not write {s}\n", .{anchor.file_path});
        return error.AutomationCommandFailed;
    };
    return .{ .file_path = anchor.file_path, .span_start = anchor.span_start };
}

fn requireWritable(response: []const u8) !void {
    if (std.mem.startsWith(u8, response, "provenance error")) return fail(response);
    const authored = responseField(response, "authored=") orelse return fail(response);
    if (!std.mem.eql(u8, authored, "markup")) return fail(response);
    const watching = responseField(response, "watching=") orelse "false";
    if (!std.mem.eql(u8, watching, "true")) {
        return fail("the app is not watching markup sources - write-back needs the dev hot-reload watch so the edit can land in the running app\n");
    }
}

fn parseAnchor(response: []const u8) !Anchor {
    try requireWritable(response);
    const node = responseLine(response, "node ") orelse return fail(response);
    const file_path = responseField(node, "file=") orelse return fail(response);
    const hash = responseField(node, "hash=") orelse return fail(response);
    const span = responseField(node, "span=") orelse return fail(response);
    if (file_path.len == 0) return fail("provenance names no on-disk file for this widget's source - write-back has nothing to edit\n");
    const separator = std.mem.indexOf(u8, span, "..") orelse return fail(response);
    return .{
        .file_path = file_path,
        .root_path = responseField(response, "root=") orelse file_path,
        .hash = std.fmt.parseUnsigned(u64, hash, 16) catch return fail(response),
        .span_start = std.fmt.parseUnsigned(usize, span[0..separator], 10) catch return fail(response),
    };
}

fn readCurrentSource(arena: std.mem.Allocator, io: std.Io, anchor: Anchor) ![]u8 {
    const source = readFile(arena, io, anchor.file_path) catch {
        std.debug.print("error: cannot read {s} - run this command from the app project's working directory (the same place the app runs from)\n", .{anchor.file_path});
        return error.AutomationCommandFailed;
    };
    if (std.hash.Wyhash.hash(0, source) != anchor.hash) {
        std.debug.print(
            "error: {s} changed on disk since the app loaded it - the provenance spans no longer describe these bytes.\n" ++
                "       save your editor, let the app's hot-reload watch catch up (it polls every 500ms), and retry;\n" ++
                "       this command never overwrites concurrent edits.\n",
            .{anchor.file_path},
        );
        return error.AutomationCommandFailed;
    }
    return source;
}

fn validateEditedClosure(arena: std.mem.Allocator, io: std.Io, root_path: []const u8, edited_path: []const u8, edited: []const u8) !void {
    var loader = EditOverlayLoader{ .io = io, .edited_path = edited_path, .edited = edited };
    const root_source = if (std.mem.eql(u8, root_path, edited_path))
        edited
    else
        readFile(arena, io, root_path) catch {
            std.debug.print("error: cannot read the markup root {s} for closure validation\n", .{root_path});
            return error.AutomationCommandFailed;
        };
    var diagnostic: markup.MarkupErrorInfo = .{};
    const document = markup.resolveImports(arena, root_path, root_source, loader.loader(), &diagnostic) catch {
        std.debug.print("error: the edit would break the markup closure ({s}:{d}:{d}): {s}\n", .{ diagnostic.path, diagnostic.line, diagnostic.column, diagnostic.message });
        return error.AutomationCommandFailed;
    };
    if (markup.validate(document)) |info| {
        std.debug.print("error: the edit would fail validation ({s}:{d}:{d}): {s}\n", .{ info.path, info.line, info.column, info.message });
        return error.AutomationCommandFailed;
    }
}

const EditOverlayLoader = struct {
    io: std.Io,
    edited_path: []const u8,
    edited: []const u8,

    fn loader(self: *EditOverlayLoader) markup.ImportLoader {
        return .{ .context = self, .load = load };
    }

    fn load(context: *const anyopaque, arena: std.mem.Allocator, path: []const u8) ?[]const u8 {
        const self: *const EditOverlayLoader = @ptrCast(@alignCast(context));
        if (std.mem.eql(u8, path, self.edited_path)) return self.edited;
        var file = std.Io.Dir.cwd().openFile(self.io, path, .{}) catch return null;
        defer file.close(self.io);
        const buffer = arena.alloc(u8, 256 * 1024) catch return null;
        const len = file.readPositionalAll(self.io, buffer, 0) catch return null;
        return buffer[0..len];
    }
};

fn readFile(arena: std.mem.Allocator, io: std.Io, path: []const u8) ![]u8 {
    var file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);
    var buffer: [4096]u8 = undefined;
    var reader = file.reader(io, &buffer);
    return reader.interface.allocRemaining(arena, .limited(1024 * 1024));
}

fn fail(response: []const u8) error{AutomationCommandFailed} {
    std.debug.print("error: {s}", .{response});
    if (response.len == 0 or response[response.len - 1] != '\n') std.debug.print("\n", .{});
    return error.AutomationCommandFailed;
}

fn responseField(text: []const u8, marker: []const u8) ?[]const u8 {
    var search: usize = 0;
    while (std.mem.indexOfPos(u8, text, search, marker)) |index| {
        search = index + marker.len;
        if (index > 0 and text[index - 1] != ' ' and text[index - 1] != '\n') continue;
        var end = search;
        while (end < text.len and text[end] != ' ' and text[end] != '\n') end += 1;
        return text[search..end];
    }
    return null;
}

fn responseLine(text: []const u8, prefix: []const u8) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, prefix)) return line;
    }
    return null;
}
