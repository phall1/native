#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

#define NATIVE_SDK_APPKIT_CELL_GRID_TESTING 1
#include "appkit_host.m"

static void NativeSdkCellGridTestFail(NSString *message) {
    fprintf(stderr, "cell-grid-host-test: %s\n", message.UTF8String);
    exit(1);
}

static void NativeSdkCellGridTestExpect(BOOL condition, NSString *message) {
    if (!condition) NativeSdkCellGridTestFail(message);
}

static void NativeSdkCellGridAppendU8(NSMutableData *data, uint8_t value) {
    [data appendBytes:&value length:sizeof(value)];
}

static void NativeSdkCellGridAppendU16(NSMutableData *data, uint16_t value) {
    value = CFSwapInt16HostToLittle(value);
    [data appendBytes:&value length:sizeof(value)];
}

static void NativeSdkCellGridAppendU32(NSMutableData *data, uint32_t value) {
    value = CFSwapInt32HostToLittle(value);
    [data appendBytes:&value length:sizeof(value)];
}

static void NativeSdkCellGridAppendF32(NSMutableData *data, float value) {
    uint32_t bits = 0;
    memcpy(&bits, &value, sizeof(bits));
    NativeSdkCellGridAppendU32(data, bits);
}

static void NativeSdkCellGridAppendColor(NSMutableData *data, const uint8_t color[4]) {
    [data appendBytes:color length:4];
}

static void NativeSdkCellGridAppendStyle(
    NSMutableData *data,
    const uint8_t foreground[4],
    const uint8_t background[4],
    const uint8_t underline[4],
    uint16_t flags
) {
    NativeSdkCellGridAppendColor(data, foreground);
    NativeSdkCellGridAppendColor(data, background);
    NativeSdkCellGridAppendColor(data, underline);
    NativeSdkCellGridAppendU16(data, flags);
}

static void NativeSdkCellGridAppendCluster(NSMutableData *data, const char *bytes, uint8_t length) {
    NativeSdkCellGridAppendU8(data, length);
    [data appendBytes:bytes length:length];
}

static NSMutableData *NativeSdkCellGridPacket(void) {
    const uint8_t foreground[4] = {244, 247, 251, 255};
    const uint8_t background[4] = {9, 11, 15, 255};
    const uint8_t underline[4] = {102, 153, 255, 255};
    const uint16_t backgroundFlag = NativeSdkCellFlagHasBackground;
    const uint16_t decoratedFlag = NativeSdkCellFlagHasBackground |
        NativeSdkCellFlagBold |
        NativeSdkCellFlagStrikethrough |
        NativeSdkCellFlagHasUnderlineColor |
        (1u << 6);

    NSMutableData *data = [NSMutableData data];
    NativeSdkCellGridAppendU32(data, 2); /* regular font */
    NativeSdkCellGridAppendU32(data, 0); /* synthesize bold */
    NativeSdkCellGridAppendU32(data, 0); /* synthesize italic */
    NativeSdkCellGridAppendU32(data, 0); /* synthesize bold italic */
    NativeSdkCellGridAppendF32(data, 13.0f);
    NativeSdkCellGridAppendF32(data, 0.0f);
    NativeSdkCellGridAppendF32(data, 0.0f);
    NativeSdkCellGridAppendF32(data, 8.0f);
    NativeSdkCellGridAppendF32(data, 18.0f);
    NativeSdkCellGridAppendF32(data, 14.0f);
    NativeSdkCellGridAppendU16(data, 6);
    NativeSdkCellGridAppendU16(data, 1);
    NativeSdkCellGridAppendU32(data, 6);

    NativeSdkCellGridAppendU8(data, 2); /* new style + cluster */
    NativeSdkCellGridAppendStyle(data, foreground, background, underline, backgroundFlag);
    NativeSdkCellGridAppendCluster(data, "A", 1);
    NativeSdkCellGridAppendU8(data, 3); /* same style + cluster */
    NativeSdkCellGridAppendCluster(data, "B", 1);
    NativeSdkCellGridAppendU8(data, 1); /* same style + blank */
    NativeSdkCellGridAppendU8(data, 2); /* changed decorated style + cluster */
    NativeSdkCellGridAppendStyle(data, foreground, background, underline, decoratedFlag);
    NativeSdkCellGridAppendCluster(data, "A", 1);
    NativeSdkCellGridAppendU8(data, 3); /* same decorated style + cluster */
    NativeSdkCellGridAppendCluster(data, "Z", 1);
    NativeSdkCellGridAppendU8(data, 1); /* same decorated style + blank */
    return data;
}

static NSDictionary *NativeSdkCellGridDecode(NSData *data) {
    NativeSdkBinaryPacketReader reader = {
        .bytes = data.bytes,
        .length = data.length,
        .offset = 0,
        .failed = NO,
    };
    NSDictionary *grid = NativeSdkBinaryReadCellGrid(&reader);
    NativeSdkCellGridTestExpect(grid != nil, @"valid binary grid refused");
    NativeSdkCellGridTestExpect(!reader.failed, @"valid binary grid marked failed");
    NativeSdkCellGridTestExpect(reader.offset == reader.length, @"binary grid left trailing bytes");
    return grid;
}

static NSArray *NativeSdkCellGridColor(uint8_t red, uint8_t green, uint8_t blue, uint8_t alpha) {
    return @[
        @((double)red / 255.0),
        @((double)green / 255.0),
        @((double)blue / 255.0),
        @((double)alpha / 255.0),
    ];
}

static NSDictionary *NativeSdkCellGridJsonTwin(void) {
    const uint16_t backgroundFlag = NativeSdkCellFlagHasBackground;
    const uint16_t decoratedFlag = NativeSdkCellFlagHasBackground |
        NativeSdkCellFlagBold |
        NativeSdkCellFlagStrikethrough |
        NativeSdkCellFlagHasUnderlineColor |
        (1u << 6);
    NSMutableArray *cells = [NSMutableArray arrayWithCapacity:6];
    NSArray<NSString *> *clusters = @[@"A", @"B", @"", @"A", @"Z", @""];
    for (NSUInteger index = 0; index < 6; index += 1) {
        NSMutableDictionary *cell = [NSMutableDictionary dictionary];
        cell[@"fg"] = NativeSdkCellGridColor(244, 247, 251, 255);
        cell[@"bg"] = NativeSdkCellGridColor(9, 11, 15, 255);
        cell[@"ul"] = NativeSdkCellGridColor(102, 153, 255, 255);
        cell[@"flags"] = @(index < 3 ? backgroundFlag : decoratedFlag);
        if (clusters[index].length > 0) cell[@"text"] = clusters[index];
        [cells addObject:cell];
    }
    return @{
        @"font" : @(2),
        @"boldFont" : @(0),
        @"italicFont" : @(0),
        @"boldItalicFont" : @(0),
        @"size" : @(13.0),
        @"origin" : @[@(0.0), @(0.0)],
        @"cellWidth" : @(8.0),
        @"cellHeight" : @(18.0),
        @"baseline" : @(14.0),
        @"cols" : @(6),
        @"rows" : @(1),
        @"cells" : cells,
    };
}

static NSDictionary *NativeSdkCellGridCommand(NSDictionary *grid) {
    return @{
        @"kind" : @"cell_grid",
        @"bounds" : @[@(0.0), @(0.0), @(48.0), @(18.0)],
        @"opacity" : @(1.0),
        @"cellGrid" : grid,
    };
}

static NSData *NativeSdkCellGridImageBytes(CGImageRef image) {
    CGDataProviderRef provider = image ? CGImageGetDataProvider(image) : NULL;
    CFDataRef bytes = provider ? CGDataProviderCopyData(provider) : NULL;
    NativeSdkCellGridTestExpect(bytes != NULL, @"raster has no bytes");
    return CFBridgingRelease(bytes);
}

static NativeSdkMetalSurfaceView *NativeSdkCellGridTestView(void) {
    NativeSdkMetalSurfaceView *view = [[NativeSdkMetalSurfaceView alloc] initWithFrame:NSMakeRect(0, 0, 48, 18)];
    [view stopDisplayTimer];
    if (!view.canvasColorSpace) view.canvasColorSpace = CGColorSpaceCreateDeviceRGB();
    NativeSdkCellGridTestExpect(view.canvasColorSpace != NULL, @"could not create device RGB color space");
    return view;
}

static void NativeSdkCellGridTestAsciiCache(void) {
    NSArray<NSString *> *first = NativeSdkCellAsciiClusters();
    NSArray<NSString *> *second = NativeSdkCellAsciiClusters();
    NativeSdkCellGridTestExpect(first == second, @"ASCII cache identity changed");
    NativeSdkCellGridTestExpect(first.count == 128, @"ASCII cache exceeded its fixed bound");
    for (NSUInteger value = 0; value < first.count; value += 1) {
        NativeSdkCellGridTestExpect(first[value].length == 1, @"ASCII cache entry length changed");
        NativeSdkCellGridTestExpect([first[value] characterAtIndex:0] == value, @"ASCII cache entry maps the wrong scalar");
    }
}

static void NativeSdkCellGridTestDecodeSharing(void) {
    NSDictionary *grid = NativeSdkCellGridDecode(NativeSdkCellGridPacket());
    NSArray *cells = grid[@"cells"];
    NativeSdkCellGridTestExpect(cells.count == 6, @"decoded the wrong cell count");
    NSDictionary *first = NativeSdkPacketDictionary(cells[0]);
    NSDictionary *second = NativeSdkPacketDictionary(cells[1]);
    NSDictionary *third = NativeSdkPacketDictionary(cells[2]);
    NSDictionary *fourth = NativeSdkPacketDictionary(cells[3]);
    NativeSdkCellGridTestExpect(first[@"fg"] == second[@"fg"], @"same-style foreground was copied");
    NativeSdkCellGridTestExpect(second[@"fg"] == third[@"fg"], @"same-style blank lost run identity");
    NativeSdkCellGridTestExpect(third[@"fg"] != fourth[@"fg"], @"changed style reused prior run identity");
    NativeSdkCellGridTestExpect(first[@"text"] == fourth[@"text"], @"ASCII clusters were not interned");

    const uint8_t invalid[] = {1}; /* same-style first cell */
    NativeSdkBinaryPacketReader reader;
    /* Enter at the cell stream by spelling the fixed header first. */
    NSMutableData *packet = [NativeSdkCellGridPacket() mutableCopy];
    const NSUInteger headerLength = 48;
    [packet replaceBytesInRange:NSMakeRange(headerLength, packet.length - headerLength) withBytes:invalid length:sizeof(invalid)];
    uint32_t one = CFSwapInt32HostToLittle(1);
    [packet replaceBytesInRange:NSMakeRange(44, 4) withBytes:&one length:4];
    reader = (NativeSdkBinaryPacketReader){
        .bytes = packet.bytes,
        .length = packet.length,
        .offset = 0,
        .failed = NO,
    };
    NSDictionary *refused = NativeSdkBinaryReadCellGrid(&reader);
    NativeSdkCellGridTestExpect(refused == nil && reader.failed, @"same-style first cell was accepted");

    NSMutableData *oversized = [NativeSdkCellGridPacket() mutableCopy];
    uint32_t tooMany = CFSwapInt32HostToLittle(4097);
    [oversized replaceBytesInRange:NSMakeRange(44, 4) withBytes:&tooMany length:4];
    reader = (NativeSdkBinaryPacketReader){
        .bytes = oversized.bytes,
        .length = oversized.length,
        .offset = 0,
        .failed = NO,
    };
    NativeSdkCellGridTestExpect(NativeSdkBinaryReadCellGrid(&reader) == nil && reader.failed, @"cell resource bound was not enforced");
}

static void NativeSdkCellGridTestPixelsAndLookups(void) {
    NativeSdkMetalSurfaceView *view = NativeSdkCellGridTestView();
    NSDictionary *binaryCommand = NativeSdkCellGridCommand(NativeSdkCellGridDecode(NativeSdkCellGridPacket()));
    NSDictionary *jsonCommand = NativeSdkCellGridCommand(NativeSdkCellGridJsonTwin());

    NativeSdkCellGridFontResolutionCount = 0;
    NativeSdkPacketCommandRaster *binaryRaster = [view rasterCacheBuildEntryForCommand:binaryCommand
                                                                                  kind:@"cell_grid"
                                                                                 scale:2
                                                                            pixelWidth:96
                                                                           pixelHeight:36];
    NativeSdkCellGridTestExpect(binaryRaster.image != NULL, @"binary grid did not rasterize");
    NativeSdkCellGridTestExpect(NativeSdkCellGridFontResolutionCount == 1, @"one-face row resolved its font more than once");

    NativeSdkCellGridFontResolutionCount = 0;
    NativeSdkPacketCommandRaster *jsonRaster = [view rasterCacheBuildEntryForCommand:jsonCommand
                                                                                kind:@"cell_grid"
                                                                               scale:2
                                                                          pixelWidth:96
                                                                         pixelHeight:36];
    NativeSdkCellGridTestExpect(jsonRaster.image != NULL, @"JSON grid did not rasterize");
    NativeSdkCellGridTestExpect(NativeSdkCellGridFontResolutionCount == 1, @"JSON row repeated font resolution per cell");
    NativeSdkCellGridTestExpect(NSEqualRects(binaryRaster.destination, jsonRaster.destination), @"decode paths changed raster destination");
    NativeSdkCellGridTestExpect(
        [NativeSdkCellGridImageBytes(binaryRaster.image) isEqualToData:NativeSdkCellGridImageBytes(jsonRaster.image)],
        @"binary run sharing changed CoreText pixels");
}

static void NativeSdkCellGridTestRasterCacheLifecycle(void) {
    NativeSdkMetalSurfaceView *view = NativeSdkCellGridTestView();
    [view rasterCacheEnsureScale:2 pixelWidth:96 pixelHeight:36];
    const NSUInteger entryBytes = 1024 * 1024;
    for (NSUInteger index = 0; index < 65; index += 1) {
        NativeSdkPacketCommandRaster *entry = [[NativeSdkPacketCommandRaster alloc] init];
        entry.command = @{};
        entry.byteCount = entryBytes;
        entry.lastUseTick = index + 1;
        [view rasterCacheStoreEntry:entry forKey:@(index)];
    }
    NativeSdkCellGridTestExpect(view.canvasCommandRasterCacheBytes <= NativeSdkPacketRasterCacheMaxBytes, @"raster cache exceeded its byte bound");
    NativeSdkCellGridTestExpect(view.canvasCommandRasterCache.count == 64, @"raster cache retained too many entries");
    NativeSdkCellGridTestExpect(view.canvasCommandRasterCache[@(0)] == nil, @"raster cache did not evict deterministic LRU");

    [view rasterCacheEnsureScale:2 pixelWidth:96 pixelHeight:36];
    NativeSdkCellGridTestExpect(view.canvasCommandRasterCache.count == 64, @"unchanged surface invalidated raster cache");
    [view rasterCacheEnsureScale:1 pixelWidth:48 pixelHeight:18];
    NativeSdkCellGridTestExpect(view.canvasCommandRasterCache.count == 0, @"scale change did not invalidate raster cache");
    NativeSdkCellGridTestExpect(view.canvasCommandRasterCacheBytes == 0, @"scale invalidation retained byte accounting");
}

int main(void) {
    @autoreleasepool {
        NativeSdkCellGridTestAsciiCache();
        NativeSdkCellGridTestDecodeSharing();
        NativeSdkCellGridTestPixelsAndLookups();
        NativeSdkCellGridTestRasterCacheLifecycle();
        fprintf(stdout, "cell-grid-host-test: ok\n");
    }
    return 0;
}
