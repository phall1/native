const std = @import("std");
const native_sdk = @import("native_sdk");
const core = @import("core");

const Adapter = native_sdk.TsUiApp(core);
const CompiledView = native_sdk.canvas.CompiledMarkupView(core.Model, core.Msg, @embedFile("app.native"));

const ExtensionCalls = struct {
    last_key: u64 = 0,

    fn binding(self: *ExtensionCalls) native_sdk.HostCallBinding {
        return .{ .context = self, .send_fn = send, .request_fn = request };
    }

    fn send(_: *anyopaque, _: []const u8, _: []const u8) void {}

    fn request(context: *anyopaque, _: []const u8, key: u64, _: []const u8) void {
        const self: *ExtensionCalls = @ptrCast(@alignCast(context));
        self.last_key = key;
    }
};

/// Stands in for the runner's own generated binding (services, persistence):
/// the mux must keep routing every name outside the extension's namespace
/// here, or a generated service silently stops answering.
const GeneratedCalls = struct {
    request_count: usize = 0,

    fn binding(self: *GeneratedCalls) native_sdk.HostCallBinding {
        return .{ .context = self, .send_fn = send, .request_fn = request };
    }

    fn send(_: *anyopaque, _: []const u8, _: []const u8) void {}

    fn request(context: *anyopaque, _: []const u8, _: u64, _: []const u8) void {
        const self: *GeneratedCalls = @ptrCast(@alignCast(context));
        self.request_count += 1;
    }
};

fn isCockpitCall(name: []const u8) bool {
    return std.mem.startsWith(u8, name, "cockpit.");
}

const CoreState = struct {
    var extension_calls = ExtensionCalls{};
    var mux: Adapter.HostCallMux = undefined;
};

fn configureCoreOptionsValue(options: *Adapter.CoreOptions) void {
    const extension_binding = CoreState.extension_calls.binding();
    if (options.host_calls) |generated| {
        CoreState.mux = .{
            .default = generated,
            .routed = extension_binding,
            .route_fn = isCockpitCall,
        };
        options.host_calls = CoreState.mux.binding();
    } else {
        options.host_calls = extension_binding;
    }
}

pub fn configureCoreOptions(options: *Adapter.CoreOptions, _: std.process.Init) void {
    configureCoreOptionsValue(options);
}

fn configureOptionsValue(options: *Adapter.Options) void {
    options.view = CompiledView.build;
    options.markup = null;
}

pub fn configureOptions(options: *Adapter.Options, _: std.process.Init) void {
    configureOptionsValue(options);
}

const DecoratingHost = struct {
    inner: native_sdk.App = undefined,
    event_count: usize = 0,

    fn wrap(self: *DecoratingHost, app_value: native_sdk.App) native_sdk.App {
        self.inner = app_value;
        self.event_count = 0;
        return .{
            .context = self,
            .name = app_value.name,
            .source = app_value.source,
            .source_fn = if (app_value.source_fn != null) source else null,
            .scene_fn = if (app_value.scene_fn != null) scene else null,
            .start_fn = if (app_value.start_fn != null) start else null,
            .event_fn = if (app_value.event_fn != null) event else null,
            .stop_fn = if (app_value.stop_fn != null) stop else null,
            .replay_fn = if (app_value.replay_fn != null) replay else null,
        };
    }

    fn source(context: *anyopaque) anyerror!native_sdk.WebViewSource {
        const self: *DecoratingHost = @ptrCast(@alignCast(context));
        return self.inner.webViewSource();
    }

    fn scene(context: *anyopaque) anyerror!native_sdk.ShellConfig {
        const self: *DecoratingHost = @ptrCast(@alignCast(context));
        return (try self.inner.scene()) orelse error.SceneUnavailable;
    }

    fn start(context: *anyopaque, runtime: *native_sdk.Runtime) anyerror!void {
        const self: *DecoratingHost = @ptrCast(@alignCast(context));
        try self.inner.start(runtime);
    }

    fn event(context: *anyopaque, runtime: *native_sdk.Runtime, event_value: native_sdk.Event) anyerror!void {
        const self: *DecoratingHost = @ptrCast(@alignCast(context));
        self.event_count += 1;
        try self.inner.event(runtime, event_value);
    }

    fn stop(context: *anyopaque, runtime: *native_sdk.Runtime) anyerror!void {
        const self: *DecoratingHost = @ptrCast(@alignCast(context));
        try self.inner.stop(runtime);
    }

    fn replay(context: *anyopaque, control: native_sdk.runtime.ReplayControl) anyerror!void {
        const self: *DecoratingHost = @ptrCast(@alignCast(context));
        try self.inner.replayControl(control);
    }
};

var decorating_host = DecoratingHost{};

pub fn app(app_state: *Adapter.App) native_sdk.App {
    return decorating_host.wrap(app_state.app());
}

const canvas_label = "extension-canvas";
const test_views = [_]native_sdk.ShellView{
    .{ .label = canvas_label, .kind = .gpu_surface, .fill = true, .gpu_backend = .metal },
};
const test_windows = [_]native_sdk.ShellWindow{.{
    .label = "main",
    .title = "Extension",
    .width = 400,
    .height = 240,
    .views = &test_views,
}};
const test_scene: native_sdk.ShellConfig = .{ .windows = &test_windows };

// GUARD: ts-native-extension
test "native extension composes host calls, replaces markup view, and intercepts app events" {
    CoreState.extension_calls = .{};
    var generated_calls = GeneratedCalls{};
    var core_options: Adapter.CoreOptions = .{ .host_calls = generated_calls.binding() };
    configureCoreOptionsValue(&core_options);

    var options: Adapter.Options = .{
        .name = "native-extension-contract",
        .scene = test_scene,
        .canvas_label = canvas_label,
        .markup = .{ .source = @embedFile("app.native") },
    };
    configureOptionsValue(&options);
    try std.testing.expect(options.view != null);
    try std.testing.expect(options.markup == null);

    const app_state = try Adapter.create(std.heap.page_allocator, core_options, options);
    defer app_state.destroy();
    const decorated = app(app_state);
    var harness = try native_sdk.TestHarness().create(std.testing.allocator, .{
        .size = native_sdk.geometry.SizeF.init(400, 240),
    });
    defer harness.destroy(std.testing.allocator);
    harness.null_platform.gpu_surfaces = true;
    try harness.start(decorated);
    try harness.runtime.dispatchPlatformEvent(decorated, .{ .gpu_surface_frame = .{
        .label = canvas_label,
        .size = native_sdk.geometry.SizeF.init(400, 240),
        .scale_factor = 1,
        .frame_index = 1,
        .timestamp_ns = 1,
    } });

    try std.testing.expectEqual(@as(usize, 1), generated_calls.request_count);
    try std.testing.expect(CoreState.extension_calls.last_key != 0);
    try app_state.effects.feedHostResult(CoreState.extension_calls.last_key, true, "extension-ok");
    try harness.runtime.dispatchPlatformEvent(decorated, .wake);
    try std.testing.expectEqualStrings("extension-ok", app_state.model.extensionResult);
    try std.testing.expect(decorating_host.event_count >= 3);
}
