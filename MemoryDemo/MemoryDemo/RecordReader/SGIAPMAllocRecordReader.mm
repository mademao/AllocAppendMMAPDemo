//
// SGIAPMAllocRecordReader.mm
// SGIAPMAllocPlugin
//
// Created by mademao on 2020/4/21.
// Copyright © 2020 Sogou. All rights reserved.
//


#import "SGIAPMAllocRecordReader.h"
#import "SGIAPMCommonDef.h"

#import "sgi_thread_utils.h"
#import "sgi_allocate_logging.h"
#import "sgi_allocate_record_output.h"
#import "sgi_allocate_record_reader.h"

#import <list>


using namespace SGIAPMAlloc;

@interface SGIAPMAllocRecordReader ()

@property (nonatomic, assign) sgi_splay_tree *mallocRecord;
@property (nonatomic, assign) sgi_splay_tree *vmRecord;
@property (nonatomic, assign) sgi_backtrace_uniquing_table *stackTable;
@property (nonatomic, assign) sgi_dyld_image_info *dyld_image_info;
@property (nonatomic, assign) BOOL collectionStackFrame;

@end


@implementation SGIAPMAllocRecordReader

#pragma mark - public methods

- (instancetype)initWithMallocRecord:(sgi_splay_tree *)mallocRecord
                            vmRecord:(sgi_splay_tree *)vmRecord
                          stackTable:(sgi_backtrace_uniquing_table *)stackTable
                     dyld_image_info:(sgi_dyld_image_info *)dyld_image_info
                collectionStackFrame:(BOOL)collectionStackFrame {
    if ((self = [super init])) {
        _mallocRecord = mallocRecord;
        _vmRecord = vmRecord;
        _stackTable = stackTable;
        _dyld_image_info = dyld_image_info;
        _collectionStackFrame = collectionStackFrame;
    }
    return self;
}

- (NSDictionary *)generateReport {
    bool loggingRunning = sgi_memory_allocate_logging_enabled;
    if (loggingRunning) {
        sgi_memory_allocate_logging_lock();
        sgi_memory_allocate_logging_enabled = false;
    }
    
    sgi_suspend_all_child_threads();

    // generate malloc report
    NSDictionary *mallocReportDict = nil;
    if (self.mallocRecord) {
        mallocReportDict = [self generateFromMemoryRecords:self.mallocRecord];
    }

    // generate vm report
    NSDictionary *vmReportDict = nil;
    if (self.vmRecord) {
        vmReportDict = [self generateFromMemoryRecords:self.vmRecord];
    }

    sgi_resume_all_child_threads();
    
    if (loggingRunning) {
        sgi_memory_allocate_logging_enabled = true;
        sgi_memory_allocate_logging_unlock();
    }
    
    return @{@"malloc_report" : mallocReportDict ? mallocReportDict : @{},
             @"vm_report" : vmReportDict ? vmReportDict : @{}
    };
}

- (NSArray *)generateStackFrameReportWithStackID:(NSNumber *)stackID
{
    if (stackID == nil) {
        return @[];
    }
    
    uint64_t stack_id = (uint64_t)[stackID integerValue];
    vm_address_t frames[SGI_ALLOCATIONS_MAX_STACK_SIZE];
    uint32_t frame_count = 0;
    sgi_unwind_stack_from_table_index(self.stackTable, stack_id, frames, &frame_count, SGI_ALLOCATIONS_MAX_STACK_SIZE);
    
    NSMutableArray *frameArr = [NSMutableArray array];
    for (uint32_t i = 0; i < frame_count; i++) {
        vm_address_t addr = frames[i];
        
        NSString *transformString = [self transformToStackFrameAddressInfoWithAddress:addr];
        if (transformString) {
            [frameArr addObject:transformString];
        } else {
            [frameArr addObject:[NSString stringWithFormat:@"%p", (void *)addr]];
        }
    }
    return frameArr;
}

#pragma mark - private methods

- (NSDictionary *)generateFromMemoryRecords:(sgi_splay_tree *)rawRecords {

    AllocateRecords allocateRecords(rawRecords, self.dyld_image_info);
    allocateRecords.parseAndGroupingRawRecords();

    RecordOutput output(allocateRecords, self.stackTable, self.dyld_image_info, self.collectionStackFrame);
    NSDictionary *dict = output.flushReportToDictionary(0);
    
    return dict ? dict : @{};
}

- (NSString *)transformToStackFrameAddressInfoWithAddress:(vm_address_t)address
{
    NSString *title = nil;
    
    Dl_info dlinfo = {NULL, NULL, NULL, NULL};
    sgi_dyld_get_DLInfo(sgi_current_dyld_image_info, address, &dlinfo);
    
    if (dlinfo.dli_sname) {
        title = [NSString stringWithFormat:@"%s", dlinfo.dli_sname];
    } else {
        title = [NSString stringWithFormat:@"%s %p %p", dlinfo.dli_fname, dlinfo.dli_fbase, dlinfo.dli_saddr];
    }
    
    return title;
}

- (void)dealloc
{
    _dyld_image_info = NULL;
    _mallocRecord = NULL;
    _vmRecord = NULL;
    _stackTable = NULL;
}

@end
