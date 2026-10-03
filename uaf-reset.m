#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <objc/runtime.h>

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
    if (error) *error = [NSError errorWithDomain:@"AppleAIRemover.UAF" code:1 userInfo:@{NSLocalizedDescriptionKey:@"could not load UnifiedAssetFramework"}];
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

static int commandPref(NSString *domain, NSString *key) {
    CFStringRef d=(__bridge CFStringRef)domain, k=(__bridge CFStringRef)key;
    CFPreferencesAppSynchronize(d);
    Boolean forced=CFPreferencesAppValueIsForced(k,d);
    CFPropertyListRef raw=CFPreferencesCopyAppValue(k,d);
    id value=CFBridgingRelease(raw);
    NSString *rendered=@"unset";
    if ([value isKindOfClass:[NSNumber class]]) rendered=[value boolValue]?@"true":@"false";
    else if ([value isKindOfClass:[NSString class]]) rendered=value;
    printf("forced=%d\tvalue=%s\n",forced?1:0,rendered.UTF8String);
    return 0;
}

static int commandAssetType(NSString *name) {
    NSError *error=nil;
    if (!loadUAF(&error)) goto fail;
    NSString *expected=expectedAssetType(name);
    if (!expected) { fprintf(stderr,"uaf-reset: unknown asset set: %s\n",name.UTF8String); return 2; }
    NSString *actual=uafAssetType(name);
    if (!actual) { error=[NSError errorWithDomain:@"AppleAIRemover.UAF" code:2 userInfo:@{NSLocalizedDescriptionKey:@"UAF returned no asset type"}]; goto fail; }
    printf("%s\n",actual.UTF8String);
    return 0;
fail:
    fprintf(stderr,"uaf-reset: %s\n",error.localizedDescription.UTF8String);
    return 1;
}

static int commandBytes(NSString *name) {
    NSError *error=nil;
    if (!loadUAF(&error)) goto fail;
    NSString *expected=expectedAssetType(name);
    if (!expected) { fprintf(stderr,"uaf-reset: unknown asset set: %s\n",name.UTF8String); return 2; }
    NSString *actual=uafAssetType(name);
    if (!actual || ![actual isEqualToString:expected]) {
        fprintf(stderr,"uaf-reset: live UAF asset type mismatch for: %s\n",name.UTF8String);
        return 1;
    }
    Class manager=NSClassFromString(@"UAFAutoAssetManager");
    if (!manager || ![manager respondsToSelector:@selector(latestStatusForClients:error:)]) { fprintf(stderr,"uaf-reset: UAF status interface unavailable\n"); return 1; }
    id status=[manager latestStatusForClients:name error:&error];
    if (error) goto fail;
    if (!status || ![status respondsToSelector:@selector(downloadedFilesystemBytes)]) { fprintf(stderr,"uaf-reset: downloadedFilesystemBytes unavailable\n"); return 1; }
    int64_t bytes=[status downloadedFilesystemBytes];
    if (bytes<0) { fprintf(stderr,"uaf-reset: UAF reported an invalid byte count\n"); return 1; }
    printf("%lld\n",(long long)bytes);
    return 0;
fail:
    fprintf(stderr,"uaf-reset: %s\n",error.localizedDescription.UTF8String);
    return 1;
}

static int resetOne(NSString *name) {
    NSError *error=nil;
    if (!loadUAF(&error)) goto fail;
    NSString *expected=expectedAssetType(name);
    if (!expected) { error=[NSError errorWithDomain:@"AppleAIRemover.UAF" code:3 userInfo:@{NSLocalizedDescriptionKey:@"asset set is not in the allowlist"}]; goto fail; }
    NSString *actual=uafAssetType(name);
    if (!actual || ![actual isEqualToString:expected]) { error=[NSError errorWithDomain:@"AppleAIRemover.UAF" code:4 userInfo:@{NSLocalizedDescriptionKey:@"live UAF asset type does not match the supported catalog"}]; goto fail; }
    Class ifaceClass=NSClassFromString(@"UAFXPCProxyServiceInterface");
    if (!ifaceClass || ![ifaceClass respondsToSelector:@selector(defaultInterface)]) { error=[NSError errorWithDomain:@"AppleAIRemover.UAF" code:5 userInfo:@{NSLocalizedDescriptionKey:@"UAF XPC interface unavailable"}]; goto fail; }
    NSXPCInterface *iface=[ifaceClass defaultInterface];
    SEL operation=@selector(operationWithConfig:completion:);
    Protocol *protocol=iface.protocol;
    struct objc_method_description desc=protocol_getMethodDescription(protocol,operation,YES,YES);
    if (desc.name==NULL) desc=protocol_getMethodDescription(protocol,operation,NO,YES);
    if (desc.name==NULL) { error=[NSError errorWithDomain:@"AppleAIRemover.UAF" code:6 userInfo:@{NSLocalizedDescriptionKey:@"UAF XPC interface does not expose the reset operation"}]; goto fail; }
    NSXPCConnection *connection=[[NSXPCConnection alloc] initWithMachServiceName:kService options:0];
    connection.remoteObjectInterface=iface;
    [connection resume];
    dispatch_semaphore_t done=dispatch_semaphore_create(0);
    __block NSError *operationError=nil;
    __block BOOL completed=NO;
    void (^finish)(NSError *)=^(NSError *e){ @synchronized(connection){ if(completed) return; completed=YES; operationError=e; } dispatch_semaphore_signal(done); };
    id proxy=[connection remoteObjectProxyWithErrorHandler:^(NSError *e){ finish(e); }];
    [proxy operationWithConfig:@{@"Operation":@"ResetAssetSets",@"AssetSets":@[name]} completion:^(NSError *e){ finish(e); }];
    long result=dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,120LL*NSEC_PER_SEC));
    [connection invalidate];
    if (result!=0) { error=[NSError errorWithDomain:@"AppleAIRemover.UAF" code:7 userInfo:@{NSLocalizedDescriptionKey:@"timed out waiting for asset service"}]; goto fail; }
    if (operationError) { error=operationError; goto fail; }
    return 0;
fail:
    fprintf(stderr,"uaf-reset: %s\n",error.localizedDescription.UTF8String);
    return 1;
}

static int commandReset(NSArray<NSString *> *names) {
    if (names.count==0) { fprintf(stderr,"uaf-reset: refusing to reset an empty asset-set list\n"); return 2; }
    NSError *error=nil;
    if (!loadUAF(&error)) goto fail;
    for (NSString *name in names) {
        NSString *expected=expectedAssetType(name);
        if (!expected) { fprintf(stderr,"uaf-reset: unknown asset set: %s\n",name.UTF8String); return 2; }
        NSString *actual=uafAssetType(name);
        if (!actual || ![actual isEqualToString:expected]) { fprintf(stderr,"uaf-reset: asset type mismatch for %s\n",name.UTF8String); return 1; }
    }
    for (NSString *name in names) if (resetOne(name)!=0) return 1;
    return 0;
fail:
    fprintf(stderr,"uaf-reset: %s\n",error.localizedDescription.UTF8String);
    return 1;
}

int main(int argc,const char *argv[]) {
    @autoreleasepool {
        if (argc<2) return 2;
        NSString *command=[NSString stringWithUTF8String:argv[1]];
        if ([command isEqualToString:@"pref"]) return argc==4 ? commandPref([NSString stringWithUTF8String:argv[2]],[NSString stringWithUTF8String:argv[3]]) : 2;
        if ([command isEqualToString:@"asset-type"]) return argc==3 ? commandAssetType([NSString stringWithUTF8String:argv[2]]) : 2;
        if ([command isEqualToString:@"bytes"]) return argc==3 ? commandBytes([NSString stringWithUTF8String:argv[2]]) : 2;
        if ([command isEqualToString:@"reset"]) {
            NSMutableArray<NSString *> *names=[NSMutableArray arrayWithCapacity:(NSUInteger)(argc-2)];
            for (int i=2;i<argc;i++) { NSString *name=[NSString stringWithUTF8String:argv[i]]; if(!name.length) return 2; [names addObject:name]; }
            return commandReset(names);
        }
        return 2;
    }
}
