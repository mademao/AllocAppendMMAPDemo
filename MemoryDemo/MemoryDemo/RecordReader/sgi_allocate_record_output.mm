//
// sgi_allocate_record_output.mm
// SGIAPMAllocPlugin
//
// Created by mademao on 2020/4/21.
// Copyright © 2020 Sogou. All rights reserved.
//


#include "sgi_allocate_record_output.h"

#import "SGIDyldImagesUtil.h"
#import "SGIAPMCommonDef.h"

#import <malloc/malloc.h>

using namespace SGIAPMAlloc;

// MARK: - public

RecordOutput::~RecordOutput() {
    _dyld_image_info = NULL;
}

NSDictionary * RecordOutput::flushReportToDictionary(uint32_t thresholdInBytes) {
    AllocateRecords::InCategory *log = _allocationRecords->firstRecordInCategory();
    if (log == NULL) {
        return nil;
    }
    
    NSMutableArray *categories = [NSMutableArray array];
    
    do {
        NSMutableDictionary *category = [NSMutableDictionary dictionary];
        category[@"size"] = @(log->size);
        category[@"record_count"] = @(log->count);
        category[@"stack_id_count"] = @(log->stacks->size());
        
        uint64_t categoryPtr = (uint64_t)log->name;
        char *categoryName = (char *)categoryPtr;
        if (categoryName != NULL && strnlen(categoryName, 10) != 0 && categoryName[0] > '?') {
            category[@"name"] = [NSString stringWithUTF8String:categoryName];
        } else {
            category[@"name"] = @"";
        }
        
        NSMutableArray *stackArr = [NSMutableArray array];

        std::list<AllocateRecords::InStackId *> *stacks = log->stacks;
        for (auto sit = stacks->begin(); sit != stacks->end(); ++sit) {
            AllocateRecords::InStackId *stack = *sit;
            if (stack->size < thresholdInBytes)
                break;

            NSMutableDictionary *stackDict = [NSMutableDictionary dictionary];
            stackDict[@"size"] = @(stack->size);
            stackDict[@"count"] = @(stack->count);
            stackDict[@"stack_id"] = @(stack->stack_id);
            
            [stackArr addObject:stackDict];
        }
        category[@"stacks"] = stackArr;
        
        if (log->size >= thresholdInBytes || log->count >= _categoryElementCountThreshold) {
            [categories addObject:category];
        }

        log = _allocationRecords->nextRecordInCategory();
        
    } while (log != NULL);
    
    NSDictionary *report = @{
        @"total_size" : @(_allocationRecords->recordSize()),
        @"allocate_record_count" : @(_allocationRecords->allocateRecordCount()),
        @"stack_record_count" : @(_allocationRecords->stackRecordCount()),
        @"category_record_count" : @(_allocationRecords->categoryRecordCount()),
        @"categories" : categories ?: @[],
    };
    return report;
}
