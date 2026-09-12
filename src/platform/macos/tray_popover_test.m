// Exercise the real host implementation without showing windows or menu items.
#import "appkit_host.m"
#include <assert.h>

// The standalone host harness has no Zig updater. These unrelated entry points
// must never be reached; fail rather than substituting verification behavior.
native_sdk_update_verify_result_t native_sdk_update_verify_feed(
    const char *envelope, size_t envelope_len, const char *public_key, size_t public_key_len,
    const char *bundle_id, size_t bundle_id_len, const char *current_version, size_t current_version_len,
    const char *target, size_t target_len, char *version_out, size_t version_capacity,
    char *archive_url_out, size_t archive_url_capacity, char *release_notes_out, size_t release_notes_capacity) {
    abort();
}
int native_sdk_update_verify_archive(const char *path, size_t path_len, uint64_t expected_bytes, const char *sha256, size_t sha256_len) {
    abort();
}

// NSStatusItem cannot be publicly constructed without installing a menu-bar
// item. This stand-in supplies its shell while the production updater runs.
@interface TestStatusItem : NSObject
@property(nonatomic, strong) NSButton *button;
@property(nonatomic, strong) NSMenu *menu;
@property(nonatomic, assign) CGFloat length;
@property(nonatomic, assign, getter=isVisible) BOOL visible;
@end
@implementation TestStatusItem
@end

@interface PopoverTestHost : NativeSdkAppKitHost
@property(nonatomic, strong) NSMutableArray<NSString *> *actions;
@end
@implementation PopoverTestHost
- (void)scheduleFrame {}
- (void)scheduleBridgeFrames {}
- (BOOL)allowsNavigationURL:(NSURL *)url { return [url.scheme isEqualToString:@"about"]; }
- (void)emitStatusCommand:(NSString *)command statusItemId:(uint32_t)identifier {
    (void)identifier;
    if (command.length > 0) [self.actions addObject:command];
}
- (BOOL)toggleTrayPopover { [self.actions addObject:@"toggle"]; return YES; }
- (void)openStatusMenu:(NativeSdkStatusItemEntry *)entry {
    if (entry.menu) [self.actions addObject:@"menu"];
}
@end

static PopoverTestHost *MakeHost(void) {
    PopoverTestHost *host = [[PopoverTestHost alloc] init];
    host.actions = [NSMutableArray array];
    host.statusItems = [NSMutableDictionary dictionary];
    host.windows = [NSMutableDictionary dictionary];
    host.windowLabels = [NSMutableDictionary dictionary];
    host.nativeViews = [NSMutableDictionary dictionary];
    host.nativeViewCommands = [NSMutableDictionary dictionary];
    host.webViews = [NSMutableDictionary dictionary];
    host.childWebViews = [NSMutableDictionary dictionary];
    host.bridgeScriptHandlers = [NSMutableDictionary dictionary];
    host.assetSchemeHandlers = [NSMutableDictionary dictionary];
    return host;
}

static NativeSdkStatusItemEntry *MakeStatusEntry(PopoverTestHost *host, uint32_t identifier) {
    TestStatusItem *item = [[TestStatusItem alloc] init];
    item.button = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 24, 24)];
    item.visible = YES;
    NativeSdkStatusItemEntry *entry = [[NativeSdkStatusItemEntry alloc] init];
    entry.identifier = identifier;
    entry.item = (NSStatusItem *)item;
    entry.menu = [[NSMenu alloc] initWithTitle:@"Actions"];
    entry.presentationTitle = @"T";
    entry.presentationIconOpacity = 1;
    host.statusItems[@(identifier)] = entry;
    return entry;
}

static void TestShellUpdates(void) {
    PopoverTestHost *host = MakeHost();
    NativeSdkStatusItemEntry *primary = MakeStatusEntry(host, 1);
    NativeSdkStatusItemEntry *other = MakeStatusEntry(host, 7);
    host.trayPopoverWindowLabel = @"panel";
    native_sdk_appkit_host_t *handle = (__bridge native_sdk_appkit_host_t *)host;
    // Icon/tooltip and visibility updates use the real C bridge and AppKit
    // presentation path. The menu must never reclaim a popover's left click.
    for (int visible = 0; visible <= 1; visible++) {
        native_sdk_appkit_update_tray_shell(handle, 1, "", 0, "Updated", 7, visible, "", 0, "", 0, "", 0);
        assert(primary.item.menu == nil);
        assert(primary.item.button.action == @selector(statusItemActivated:));
        assert(primary.item.visible == (visible != 0));
        assert([primary.item.button.toolTip isEqualToString:@"Updated"]);
    }
    native_sdk_appkit_update_tray_shell(handle, 7, "", 0, "Other", 5, 1, "", 0, "", 0, "", 0);
    assert(other.item.menu == other.menu);
    host.trayPopoverWindowLabel = nil;
    native_sdk_appkit_update_tray_shell(handle, 1, "", 0, "", 0, 1, "", 0, "", 0, "", 0);
    assert(primary.item.menu == primary.menu);
}

static void TestClickRouting(void) {
    PopoverTestHost *host = MakeHost();
    NativeSdkStatusItemEntry *entry = MakeStatusEntry(host, 1);
    entry.activationCommand = @"activate";
    entry.alternateActivationCommand = @"alternate";
    host.trayPopoverWindowLabel = @"panel";
    const struct { NSEventType type; NSEventModifierFlags flags; NSString *actions; } cases[] = {
        {NSEventTypeLeftMouseUp, 0, @"activate,toggle"},
        {NSEventTypeLeftMouseUp, NSEventModifierFlagOption, @"alternate"},
        {NSEventTypeRightMouseUp, 0, @"menu"},
        {NSEventTypeRightMouseUp, NSEventModifierFlagOption, @"menu"},
        {NSEventTypeLeftMouseUp, NSEventModifierFlagControl, @"menu"},
        {NSEventTypeLeftMouseUp, NSEventModifierFlagControl | NSEventModifierFlagOption, @"menu"},
    };
    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        [host.actions removeAllObjects];
        NSEvent *event = [NSEvent mouseEventWithType:cases[i].type location:NSZeroPoint modifierFlags:cases[i].flags timestamp:0 windowNumber:0 context:nil eventNumber:0 clickCount:1 pressure:0];
        [host activateStatusEntry:entry event:event];
        assert([[host.actions componentsJoinedByString:@","] isEqualToString:cases[i].actions]);
    }
    host.trayPopoverWindowLabel = nil;
    [host.actions removeAllObjects];
    [host activateStatusEntry:entry event:nil];
    assert([[host.actions componentsJoinedByString:@","] isEqualToString:@"activate,menu"]);
}

static void TestBorrowedContent(void) {
    PopoverTestHost *host = MakeHost();
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 240, 180) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:YES];
    window.releasedWhenClosed = NO;
    host.windows[@1] = window;
    host.windowLabels[@1] = @"panel";
    host.window = window;
    NSView *content = window.contentView;
    assert([host contentContainerForWindow:window] == content);
    // Exercise the actual borrow/return methods without opening an NSPopover.
    [host prepareTrayPopoverContent:content window:window];
    host.trayPopoverHostedWindowId = 1;
    NSView *placeholder = window.contentView;
    assert(placeholder != content);
    placeholder.bounds = NSMakeRect(0, 0, 240, 900);
    assert([host contentContainerForWindow:window] == content);
    assert([host contentContainerForWindow:nil] == nil);
    assert([host createNativeViewInWindow:1 label:@"root" kind:NATIVE_SDK_APPKIT_VIEW_STACK parent:@"" x:0 y:0 width:40 height:30 layer:5 visible:YES enabled:YES role:@"" accessibilityLabel:@"" text:@"" command:@""]);
    NSView *root = host.nativeViews[@"1:root"];
    assert(root.superview == content);
    assert(NSMinY(root.frame) == 150);
    assert([host createNativeViewInWindow:1 label:@"nested" kind:NATIVE_SDK_APPKIT_VIEW_STACK parent:@"root" x:0 y:0 width:10 height:10 layer:0 visible:YES enabled:YES role:@"" accessibilityLabel:@"" text:@"" command:@""]);
    assert(host.nativeViews[@"1:nested"].superview == root);
    assert([host createWebViewInWindow:1 label:@"child" url:@"about:blank" x:10 y:20 width:80 height:40 layer:2 transparent:NO bridgeEnabled:NO]);
    WKWebView *child = host.childWebViews[@"1:child"];
    assert(child.superview == content);
    assert(NSMinY(child.frame) == 120);
    WKWebView *main = [host ensureMainWebViewForWindowId:1];
    assert(main.superview == content);
    [host reorderWebViewsInWindow:1];
    assert([content.subviews indexOfObjectIdenticalTo:main] < [content.subviews indexOfObjectIdenticalTo:child]);
    assert([content.subviews indexOfObjectIdenticalTo:child] < [content.subviews indexOfObjectIdenticalTo:root]);
    assert(placeholder.subviews.count == 0);
    [host popoverDidClose:[NSNotification notificationWithName:NSPopoverDidCloseNotification object:host.trayPopover]];
    assert(window.contentView == content);
    assert(root.superview == content && child.superview == content && main.superview == content);
    assert([host contentContainerForWindow:window] == content);
    [host closeWebViewsInWindow:1];
    [main.configuration.userContentController removeScriptMessageHandlerForName:@"nativeSdkBridge"];
    [window close];
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
        TestShellUpdates();
        TestClickRouting();
        TestBorrowedContent();
        puts("AppKit tray popover regressions passed");
    }
    return 0;
}
