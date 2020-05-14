//
// SGIAPMAllocMonitor.h
// SGIAPMAllocPlugin
//
// Created by mademao on 2020/4/21.
// Copyright © 2020 Sogou. All rights reserved.
//


#import <Foundation/Foundation.h>
#import <mach/vm_types.h>
#import "SGIDyldImagesUtil.h"
#import "SGIAPMAllocRecordReader.h"

NS_ASSUME_NONNULL_BEGIN


@interface SGIAPMAllocMonitor : NSObject

+ (void)startPlugin;

+ (void)stopPlugin;

+ (BOOL)isRunning;

+ (void)clearAllocMonitorMmapFileIfNeeded;

+ (SGIAPMAllocRecordReader *)createRecordReader;

@end

NS_ASSUME_NONNULL_END
