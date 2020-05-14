//
//  sgi_stack_backtrace.h
//  sgi_stack_backtrace
//
//  Created by mademao on 2020/2/14.
//  Copyright © 2020 Sogou. All rights reserved.
//


#ifndef sgi_stack_backtrace_h
#define sgi_stack_backtrace_h

#include <mach/mach.h>
#include <stdio.h>


#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    uintptr_t *frames;
    size_t frames_size;
} sgi_stack_backtrace;

sgi_stack_backtrace *sgi_malloc_stack_backtrace(void);
void sgi_free_stack_backtrace(sgi_stack_backtrace *stack_backtrace);

bool sgi_stack_backtrace_of_thread(thread_t thread, sgi_stack_backtrace *stack_backtrace, const size_t backtrace_depth_max, uintptr_t top_frames_to_skip);

#ifdef __cplusplus
}
#endif

#endif /* sgi_stack_backtrace_h */
