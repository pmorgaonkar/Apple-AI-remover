#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <objc/runtime.h>

static NSString *const kFramework =
    @"/System/Library/PrivateFrameworks/UnifiedAssetFramework.framework/UnifiedAssetFramework";
static NSString *const kService =
    @"com.apple.siri.uaf.subscription.service";

@interface NSObject (RemoveMacAI_UAF)
+ (NSXPCInterface *)defaultInterface;
- (oneway void)operationWithConfig:(NSDictionary *)configuration
                        completion:(void (^)(NSError *_Nullable))completion;
@end

static int fail(NSString *message) {
    fprintf(stderr, "uaf-reset: %s\n", message.UTF8String);
    return 1;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 2) {
            fprintf(stderr, "Usage: %s ASSET_SET [ASSET_SET ...]\n", argv[0]);
            return 2;
        }

        if (dlopen(kFramework.fileSystemRepresentation, RTLD_NOW) == NULL) {
            return fail(@"could not load UnifiedAssetFramework");
        }

        Class interfaceClass = NSClassFromString(@"UAFXPCProxyServiceInterface");
        if (!interfaceClass ||
            ![interfaceClass respondsToSelector:@selector(defaultInterface)]) {
            return fail(@"UAF XPC interface unavailable");
        }

        NSXPCConnection *connection =
            [[NSXPCConnection alloc] initWithMachServiceName:kService options:0];

        connection.remoteObjectInterface = [interfaceClass defaultInterface];
        [connection resume];

        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        __block NSError *operationError = nil;

        id proxy = [connection remoteObjectProxyWithErrorHandler:^(NSError *error) {
            operationError = error;
            dispatch_semaphore_signal(sem);
        }];

        NSMutableArray *sets = [NSMutableArray arrayWithCapacity:(NSUInteger)(argc - 1)];
        for (int i = 1; i < argc; i++) {
            NSString *name = [NSString stringWithUTF8String:argv[i]];
            if (name.length == 0) {
                [connection invalidate];
                return fail(@"empty asset-set name");
            }
            [sets addObject:name];
        }

        NSDictionary *config = @{
            @"Operation": @"ResetAssetSets",
            @"AssetSets": [sets copy]
        };

        [proxy operationWithConfig:config completion:^(NSError *error) {
            operationError = error;
            dispatch_semaphore_signal(sem);
        }];

        // The service is asynchronous. Give it a bounded amount of time.
        long result = dispatch_semaphore_wait(
            sem,
            dispatch_time(DISPATCH_TIME_NOW, 120LL * NSEC_PER_SEC));

        [connection invalidate];

        if (result != 0) {
            return fail(@"timed out waiting for asset service");
        }

        if (operationError) {
            fprintf(stderr, "uaf-reset: %s\n", operationError.localizedDescription.UTF8String);
            return 1;
        }

        return 0;
    }
}
