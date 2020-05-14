//
// SGIAPMAllocRecordReader.h
// SGIAPMAllocPlugin
//
// Created by mademao on 2020/4/21.
// Copyright © 2020 Sogou. All rights reserved.
//


#import <Foundation/Foundation.h>
#import "SGIDyldImagesUtil.h"
#import "sgi_splay_tree.h"
#import "sgi_backtrace_uniquing_table.h"

NS_ASSUME_NONNULL_BEGIN

@interface SGIAPMAllocRecordReader : NSObject

- (instancetype)initWithMallocRecord:(sgi_splay_tree *)mallocRecord
                            vmRecord:(sgi_splay_tree *)vmRecord
                          stackTable:(sgi_backtrace_uniquing_table *)stackTable
                     dyld_image_info:(sgi_dyld_image_info *)dyld_image_info
                collectionStackFrame:(BOOL)collectionStackFrame;

- (NSDictionary *)generateReport;

- (NSArray *)generateStackFrameReportWithStackID:(NSNumber *)stackID;

@end

NS_ASSUME_NONNULL_END
