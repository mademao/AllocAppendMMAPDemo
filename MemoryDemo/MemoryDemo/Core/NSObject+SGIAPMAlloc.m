//
// NSObject+SGIAPMAlloc.m
// SGIAPMAllocPlugin
//
// Created by mademao on 2020/4/21.
// Copyright © 2020 Sogou. All rights reserved.
//


#import <objc/message.h>
#import <objc/runtime.h>
#import "SGI_RSSwizzle.h"
#import "NSObject+SGIAPMAlloc.h"


#if __has_feature(objc_arc)
#error This file must be compiled without ARC. Use -fno-objc-arc flag.
#endif

sgi_set_last_allocation_event_name_t *sgi_allocation_event_logger = NULL;

static BOOL sgi_isAllocTracking = NO;

@implementation NSObject (SGIAPMAlloc)

+ (void)sgi_startAllocTrack {
    if (!sgi_isAllocTracking) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            sgi_isAllocTracking = YES;

            SEL allocSEL = @selector(alloc);

            id (^allocImpFactory)(SGI_RSSwizzleInfo *swizzleInfo) = ^id(SGI_RSSwizzleInfo *swizzleInfo) {
                return Block_copy(^id(__unsafe_unretained id self) {
                    id (*originalIMP)(__unsafe_unretained id, SEL);
                    originalIMP = (__typeof(originalIMP))[swizzleInfo getOriginalImplementation];
                    id obj = originalIMP(self, allocSEL);
                    const char *name = class_getName([obj class]);
                    if (sgi_isAllocTracking && sgi_allocation_event_logger) {
                        sgi_allocation_event_logger(obj, name);
                    }

                    return obj;
                });
            };
            [SGI_RSSwizzle swizzleClassMethod:allocSEL inClass:NSObject.class newImpFactory:allocImpFactory];
        });
    }
}

+ (void)sgi_endAllocTrack {
    sgi_isAllocTracking = NO;
}

@end
