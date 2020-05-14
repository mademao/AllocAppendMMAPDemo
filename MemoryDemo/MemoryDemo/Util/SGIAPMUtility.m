//
//  SGIAPMUtility.m
//  BaseKeyboard
//
//  Created by kingsword on 2020/3/9.
//  Copyright © 2020 Sogou.Inc. All rights reserved.
//

#import "SGIAPMUtility.h"
#import <sys/time.h>
#import <mach/mach.h>

@implementation SGIAPMUtility

+ (double)currentTime
{
    struct timeval t0;
    gettimeofday(&t0, NULL);
    return t0.tv_sec + t0.tv_usec * 1e-6;
}

+ (NSUInteger)currentThreadCount
{
    thread_act_array_t threads;
    mach_msg_type_number_t threadCount;

    if (task_threads(mach_task_self(), &threads, &threadCount) != KERN_SUCCESS) {
        return 0;
    }

    for (mach_msg_type_number_t i = 0; i < threadCount; i++) {
        mach_port_deallocate(mach_task_self(), threads[i]);
    }
    vm_deallocate(mach_task_self(), (vm_address_t)threads, sizeof(thread_t) * threadCount);

    return threadCount;
}

+ (float)getCurrentCPUUsage
{
    kern_return_t kr;
    task_info_data_t tinfo;
    mach_msg_type_number_t task_info_count;
    
    task_info_count = TASK_INFO_MAX;
    kr = task_info(mach_task_self(), TASK_BASIC_INFO, (task_info_t) tinfo, &task_info_count);
    if (kr != KERN_SUCCESS) {
        return -1;
    }
    
    thread_array_t thread_list;
    mach_msg_type_number_t thread_count;
    kr = task_threads(mach_task_self(), &thread_list, &thread_count);
    if (kr != KERN_SUCCESS) {
        return -1;
    }
    
    float tot_cpu = 0;
    
    for (int j = 0; j < thread_count; j++) {
        thread_info_data_t thinfo;
        mach_msg_type_number_t thread_info_count = THREAD_INFO_MAX;
        kr = thread_info(thread_list[j], THREAD_BASIC_INFO, (thread_info_t)thinfo, &thread_info_count);
        if (kr != KERN_SUCCESS) {
            return -1;
        }
        thread_basic_info_t basic_info_th = (thread_basic_info_t)thinfo;
        if (!(basic_info_th->flags & TH_FLAGS_IDLE)) {
            tot_cpu = tot_cpu + basic_info_th->cpu_usage / (float) TH_USAGE_SCALE * 100.0;
        }
    }
    
    kr = vm_deallocate(mach_task_self(), (vm_offset_t) thread_list, thread_count * sizeof(thread_t));
    return tot_cpu;
}

@end
