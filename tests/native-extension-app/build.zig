const std = @import("std");
const native_sdk = @import("native_sdk");

pub fn build(b: *std.Build) void {
    const dep = b.dependency("native_sdk", .{});
    native_sdk.addApp(b, dep, .{
        .name = "native-extension-contract",
        .native_extension = "src/native_extension.zig",
    });
}
