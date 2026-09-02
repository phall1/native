//! Default implementation of the TypeScript runner extension contract.
//!
//! An app opts in with:
//!
//!   .native_extension = "src/native_extension.zig"
//!
//! Its module receives `native_sdk` and the generated `core` as imports and
//! must export these three functions with these signatures. The runner calls
//! them in order after generated service/persistence setup and before launch:
//!
//!   configureCoreOptions(*Adapter.CoreOptions, std.process.Init)
//!   configureOptions(*Adapter.Options, std.process.Init)
//!   app(*Adapter.App) native_sdk.App
//!
//! `configureCoreOptions` may compose `host_calls` with Adapter.HostCallMux;
//! `configureOptions` may replace or compose `view`, `markup`, and other
//! UiApp options; `app` may return `app_state.app()` or a wrapper whose storage
//! outlives `runner.runWithOptions`. Generated service/result and persistence
//! fields are already populated, so extensions should preserve fields they do
//! not own.

const std = @import("std");
const native_sdk = @import("native_sdk");
const core = @import("core");

const Adapter = native_sdk.TsUiApp(core);

pub fn configureCoreOptions(_: *Adapter.CoreOptions, _: std.process.Init) void {}

pub fn configureOptions(_: *Adapter.Options, _: std.process.Init) void {}

pub fn app(app_state: *Adapter.App) native_sdk.App {
    return app_state.app();
}
