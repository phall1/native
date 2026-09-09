//! Source anchors for watched fragments, staged in the document's arena.
//! Embedded and disk documents use the same registered paths, so a reload
//! never changes the meaning of a retained source location.
const std = @import("std");
const canvas = @import("canvas");
const provenance = @import("ui_app_provenance.zig");

pub const EmbeddedLoader = struct {
    spec: canvas.MarkupFragment,

    pub fn loader(self: *EmbeddedLoader) canvas.ui_markup.ImportLoader {
        return .{ .context = self, .load = load };
    }

    fn load(context: *const anyopaque, arena: std.mem.Allocator, path: []const u8) ?[]const u8 {
        const self: *const EmbeddedLoader = @ptrCast(@alignCast(context));
        const disk_dir = std.fs.path.dirname(self.spec.path) orelse "";
        const relative = if (disk_dir.len > 0) path[disk_dir.len + 1 ..] else path;
        const source_dir = std.fs.path.dirname(self.spec.root_path) orelse "";
        const embedded = if (source_dir.len > 0)
            std.fmt.allocPrint(arena, "{s}/{s}", .{ source_dir, relative }) catch return null
        else
            relative;
        var source_set = canvas.ui_markup.SourceSetLoader{ .set = self.spec.sources };
        return source_set.loader().load(source_set.loader().context, arena, embedded);
    }
};

pub fn capture(arena: std.mem.Allocator, root: []const u8, source: []const u8, closure: *const provenance.ClosureFiles) ![]const provenance.FileEntry {
    const files = try arena.alloc(provenance.FileEntry, closure.len + 1);
    files[0] = fileEntry(root, std.hash.Wyhash.hash(0, source));
    for (closure.entries[0..closure.len], files[1..]) |*entry, *file| {
        file.* = fileEntry(entry.path[0..entry.path_len], entry.hash);
    }
    return files;
}

fn fileEntry(path: []const u8, hash: u64) provenance.FileEntry {
    var entry: provenance.FileEntry = .{ .hash = hash };
    // An overlong path must not turn into a writable truncated path.
    if (path.len > entry.file_storage.len) return entry;
    entry.stamped_len = path.len;
    entry.file_len = path.len;
    @memcpy(entry.stamped_storage[0..path.len], path);
    @memcpy(entry.file_storage[0..path.len], path);
    return entry;
}

pub fn appendFiles(table: *provenance.ProvenanceTable, files: []const provenance.FileEntry) void {
    for (files) |*entry| {
        if (table.fileIndexOf(entry.stamped())) |index| {
            // Two retained fragment closures can disagree after a failed
            // shared-import reload. Refuse write-back rather than choose
            // one generation's hash for the other generation's spans.
            if (table.files[index].hash != entry.hash) table.files[index].file_len = 0;
            continue;
        }
        table.addFile(entry.stamped(), entry.file(), entry.hash) catch {};
    }
}
