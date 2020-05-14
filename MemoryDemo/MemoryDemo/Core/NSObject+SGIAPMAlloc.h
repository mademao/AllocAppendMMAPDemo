//
// NSObject+SGIAPMAlloc.h
// SGIAPMAllocPlugin
//
// Created by mademao on 2020/4/21.
// Copyright © 2020 Sogou. All rights reserved.
//


#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void(sgi_set_last_allocation_event_name_t)(void *ptr, const char *classname);

extern sgi_set_last_allocation_event_name_t *sgi_allocation_event_logger;

@interface NSObject (SGIAPMAlloc)

+ (void)sgi_startAllocTrack;
+ (void)sgi_endAllocTrack;

@end

NS_ASSUME_NONNULL_END
