//
// sgi_allocate_record_output.h
// SGIAPMAllocPlugin
//
// Created by mademao on 2020/4/21.
// Copyright © 2020 Sogou. All rights reserved.
//


#ifndef sgi_report_output_h
#define sgi_report_output_h

#include <stdio.h>
#include "sgi_allocate_record_reader.h"

#import <Foundation/Foundation.h>

namespace SGIAPMAlloc {

class RecordOutput
{
  public:
    RecordOutput(AllocateRecords &allocateRecords, sgi_backtrace_uniquing_table *stackRecords, sgi_dyld_image_info *dyld_image_info, uint32_t categoryElementCountThreshold = 0)
        : _stackRecords(stackRecords)
        , _dyld_image_info(dyld_image_info)
        , _categoryElementCountThreshold(categoryElementCountThreshold) {
        _allocationRecords = &allocateRecords;
    };

    ~RecordOutput();
    
    NSDictionary *flushReportToDictionary(uint32_t thresholdInBytes);

  private:
    AllocateRecords *_allocationRecords = NULL;
    sgi_backtrace_uniquing_table *_stackRecords = NULL;
    sgi_dyld_image_info *_dyld_image_info = NULL;

    uint32_t _categoryElementCountThreshold = 0; /**< only when the category element count exceed the limit, output to report */
    
  private:
    RecordOutput(const RecordOutput &);
    RecordOutput &operator=(const RecordOutput &);
};

}

#endif /* sgi_report_output_h */
