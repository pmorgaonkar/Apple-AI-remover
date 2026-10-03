#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <objc/runtime.h>

@interface NSObject (AppleAIRemoverUAFPrivate)
+ (id)defaultManager;
+ (NSXPCInterface *)defaultInterface;
+ (id)latestStatusForClients:(NSString *)name error:(NSError **)error;
- (id)getAssetSet:(NSString *)name;
- (NSString *)autoAssetType;
- (int64_t)downloadedFilesystemBytes;
- (oneway void)operationWithConfig:(NSDictionary *)configuration
                        completion:(void (^)(NSError *_Nullable error))completion;
@end

static NSString * const kFramework = @"/System/Library/PrivateFrameworks/UnifiedAssetFramework.framework/UnifiedAssetFramework";
static NSString * const kService = @"com.apple.siri.uaf.subscription.service";

static NSString *expectedAssetType(NSString *name) {
    NSDictionary *map = @{
        @"com.apple.modelcatalog": @"com.apple.MobileAsset.UAF.FM.GenerativeModels",
        @"com.apple.MobileAsset.UAF.FM.Visual": @"com.apple.MobileAsset.UAF.FM.Visual",
        @"com.apple.MobileAsset.UAF.Photos.SpatialPhotosRelive": @"com.apple.MobileAsset.UAF.Photos.SpatialPhotosRelive",
        @"com.apple.MobileAsset.UAF.Photos.MagicCleanup": @"com.apple.MobileAsset.UAF.Photos.MagicCleanup",
        @"com.apple.MobileAsset.UAF.FM.CodeLM": @"com.apple.MobileAsset.UAF.FM.CodeLM",
    };
    return map[name];
}

static BOOL loadUAF(NSError **error) {
    if (dlopen(kFramework.fileSystemRepresentation, RTLD_NOW) != NULL) return YES;
    if (error) {
        *error = [NSError errorWithDomain:@"AppleAIRemover.UAF"
                                      code:1
                                  userInfo:@{NSLocalizedDescriptionKey:@"could not load UnifiedAssetFramework"}];
    }
    return NO;
}

static id UAFAsset(NSString *name) {
    Class manager = NSClassFromString(@"UAFConfigurationManager");
    if (!manager || ![manager respondsToSelector:@selector(defaultManager)]) return nil;
    id instance = [manager defaultManager];
    if (!instance || ![instance respondsToSelector:@selector(getAssetSet:)]) return nil;
    return [instance getAssetSet:name];
}

static NSString *uafAssetType(NSString *name) {
    id set = UAFAsset(name);
    if (!set || ![set respondsToSelector:@selector(autoAssetType)]) return nil;
    id value = [set autoAssetType];
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

static int printNSError(NSError *error) {
    NSString *message = error.localizedDescription ?: @"unknown error";
    fprintf(stderr, "uaf-reset: %s\n", message.UTF8String);
    return 1;
}

static int commandPref(NSString *domain, NSString *key) {
    CFStringRef d = (__bridge CFStringRef)domain;
    CFStringRef k = (__bridge CFStringRef)key;
    CFPreferencesAppSynchronize(d);
    Boolean forced = CFPreferencesAppValueIsForced(k, d);
    CFPropertyListRef raw = CFPreferencesCopyAppValue(k, d);
    id value = CFBridgingRelease(raw);

    NSString *rendered = @"unset";
    if ([value isKindOfClass:[NSNumber class]]) {
        rendered = [value boolValue] ? @"true" : @"false";
    } else if ([value isKindOfClass:[NSString class]]) {
        rendered = value;
    }

    printf("forced=%d\tvalue=%s\n", forced ? 1 : 0, rendered.UTF8String);
    return 0;
}

static int commandAssetType(NSString *name) {
    NSString *expected = expectedAssetType(name);
    if (!expected) {
        fprintf(stderr, "uaf-reset: unknown asset set: %s\n", name.UTF8String);
        return 2;
    }

    NSError *error = nil;
    if (!loadUAF(&error)) return printNSError(error);

    NSString *actual = uafAssetType(name);
    if (!actual) {
        error = [NSError errorWithDomain:@"AppleAIRemover.UAF"
                                     code:2
                                 userInfo:@{NSLocalizedDescriptionKey:@"UAF returned no asset type"}];
        return printNSError(error);
    }

    printf("%s\n", actual.UTF8String);
    return 0;
}

static int commandBytes(NSString *name) {
    NSString *expected = expectedAssetType(name);
    if (!expected) {
        fprintf(stderr, "uaf-reset: unknown asset set: %s\n", name.UTF8String);
        return 2;
    }

    NSError *error = nil;
    if (!loadUAF(&error)) return printNSError(error);

    NSString *actual = uafAssetType(name);
    if (!actual || ![actual isEqualToString:expected]) {
        fprintf(stderr, "uaf-reset: live UAF asset type mismatch for: %s\n", name.UTF8String);
        return 1;
    }

    Class manager = NSClassFromString(@"UAFAutoAssetManager");
    if (!manager || ![manager respondsToSelector:@selector(latestStatusForClients:error:)]) {
        fprintf(stderr, "uaf-reset: UAF status interface unavailable\n");
        return 1;
    }

    id status = [manager latestStatusForClients:name error:&error];
    if (error) return printNSError(error);
    if (!status || ![status respondsToSelector:@selector(downloadedFilesystemBytes)]) {
        fprintf(stderr, "uaf-reset: downloadedFilesystemBytes unavailable\n");
        return 1;
    }

    int64_t bytes = [status downloadedFilesystemBytes];
    if (bytes < 0) {
        fprintf(stderr, "uaf-reset: UAF reported an invalid byte count\n");
        return 1;
    }

    printf("%lld\n", (long long)bytes);
    return 0;
}

static int resetOne(NSString *name) {
    NSString *expected = expectedAssetType(name);
    if (!expected) {
        fprintf(stderr, "uaf-reset: asset set is not in the allowlist: %s\n", name.UTF8String);
        return 2;
    }

    NSError *error = nil;
    if (!loadUAF(&error)) return printNSError(error);

    NSString *actual = uafAssetType(name);
    if (!actual || ![actual isEqualToString:expected]) {
        fprintf(stderr, "uaf-reset: live UAF asset type mismatch for: %s\n", name.UTF8String);
        return 1;
    }

    Class ifaceClass = NSClassFromString(@"UAFXPCProxyServiceInterface");
    if (!ifaceClass || ![ifaceClass respondsToSelector:@selector(defaultInterface)]) {
        fprintf(stderr, "uaf-reset: UAF XPC interface unavailable\n");
        return 1;
    }

    NSXPCInterface *iface = [ifaceClass defaultInterface];
    if (!iface) {
        fprintf(stderr, "uaf-reset: UAF returned no XPC interface\n");
        return 1;
    }

    SEL operation = @selector(operationWithConfig:completion:);
    Protocol *protocol = iface.protocol;
    struct objc_method_description description =
        protocol_getMethodDescription(protocol, operation, YES, YES);
    if (description.name == NULL) {
        description = protocol_getMethodDescription(protocol, operation, NO, YES);
    }
    if (description.name == NULL) {
        fprintf(stderr, "uaf-reset: XPC interface does not expose the reset operation\n");
        return 1;
    }

    NSXPCConnection *connection =
        [[NSXPCConnection alloc] initWithMachServiceName:kService options:0];
    if (!connection) {
        fprintf(stderr, "uaf-reset: could not create XPC connection\n");
        return 1;
    }

    connection.remoteObjectInterface = iface;
    [connection resume];

    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    NSObject *completionState = [NSObject new];
    __block BOOL completed = NO;
    __block NSError *operationError = nil;

    void (^finish)(NSError *) = ^(NSError *incomingError) {
        @synchronized (completionState) {
            if (completed) return;
            completed = YES;
            operationError = incomingError;
        }
        dispatch_semaphore_signal(done);
    };

    id proxy = [connection remoteObjectProxyWithErrorHandler:^(NSError *incomingError) {
        finish(incomingError);
    }];

    [proxy operationWithConfig:@{
        @"Operation": @"ResetAssetSets",
        @"AssetSets": @[name]
    } completion:^(NSError *incomingError) {
        finish(incomingError);
    }];

    long waitResult =
        dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 120LL * NSEC_PER_SEC));

    [connection invalidate];

    if (waitResult != 0) {
        fprintf(stderr, "uaf-reset: timed out waiting for asset service\n");
        return 1;
    }
    if (operationError) return printNSError(operationError);
    return 0;
}

static int commandReset(NSArray<NSString *> *names) {
    if (names.count == 0) {
        fprintf(stderr, "uaf-reset: refusing to reset an empty asset-set list\n");
        return 2;
    }

    for (NSString *name in names) {
        if (!expectedAssetType(name)) {
            fprintf(stderr, "uaf-reset: unknown asset set: %s\n", name.UTF8String);
            return 2;
        }
    }

    NSError *error = nil;
    if (!loadUAF(&error)) return printNSError(error);

    for (NSString *name in names) {
        NSString *expected = expectedAssetType(name);
        NSString *actual = uafAssetType(name);
        if (!actual || ![actual isEqualToString:expected]) {
            fprintf(stderr, "uaf-reset: live UAF asset type mismatch for: %s\n", name.UTF8String);
            return 1;
        }
    }

    for (NSString *name in names) {
        int result = resetOne(name);
        if (result != 0) return result;
    }

    return 0;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 2) return 2;

        NSString *command = [NSString stringWithUTF8String:argv[1]];
        if ([command isEqualToString:@"pref"]) {
            return argc == 4
                ? commandPref([NSString stringWithUTF8String:argv[2]],
                              [NSString stringWithUTF8String:argv[3]])
                : 2;
        }
        if ([command isEqualToString:@"asset-type"]) {
            return argc == 3
                ? commandAssetType([NSString stringWithUTF8String:argv[2]])
                : 2;
        }
        if ([command isEqualToString:@"bytes"]) {
            return argc == 3
                ? commandBytes([NSString stringWithUTF8String:argv[2]])
                : 2;
        }
        if ([command isEqualToString:@"reset"]) {
            NSMutableArray<NSString *> *names =
                [NSMutableArray arrayWithCapacity:(NSUInteger)(argc - 2)];
            for (int i = 2; i < argc; i++) {
                NSString *name = [NSString stringWithUTF8String:argv[i]];
                if (!name.length) return 2;
                [names addObject:name];
            }
            return commandReset(names);
        }
        return 2;
    }
}
