//
// sgi_allocate_logging.h
// SGIAPMAllocPlugin
//
// Created by mademao on 2020/4/21.
// Copyright © 2020 Sogou. All rights reserved.
//


#ifndef sgi_memory_allocate_logging_h
#define sgi_memory_allocate_logging_h

#include <mach/mach.h>
#include <stdbool.h>
#include <stdio.h>
#include <sys/syslimits.h>

#include "sgi_backtrace_uniquing_table.h"
#include "sgi_splay_tree.h"

#import "SGIDyldImagesUtil.h"


#define SGI_ALLOCATIONS_MAX_STACK_SIZE 200

#define sgi_allocations_type_free 0
#define sgi_allocations_type_generic 1        /* anything that is not allocation/deallocation */
#define sgi_allocations_type_alloc 2          /* malloc, realloc, etc... */
#define sgi_allocations_type_dealloc 4        /* free, realloc, etc... */
#define sgi_allocations_type_vm_allocate 16   /* vm_allocate or mmap */
#define sgi_allocations_type_vm_deallocate 32 /* vm_deallocate or munmap */
#define sgi_allocations_type_mapped_file_or_shared_mem 128


// The valid flags include those from VM_FLAGS_ALIAS_MASK, which give the user_tag of allocated VM regions.
#define sgi_allocations_valid_type_flags ( \
    sgi_allocations_type_generic | sgi_allocations_type_alloc | sgi_allocations_type_dealloc | sgi_allocations_type_vm_allocate | sgi_allocations_type_vm_deallocate | sgi_allocations_type_mapped_file_or_shared_mem | VM_FLAGS_ALIAS_MASK);


// Following flags are absorbed by stack_logging_log_stack()
#define sgi_allocations_flag_zone 8     /* NSZoneMalloc, etc... */
#define sgi_allocations_flag_cleared 64 /* for NewEmptyHandle */


#ifdef __cplusplus
extern "C" {
#endif


// MARK: - Record files info
extern char sgi_records_cache_dir[PATH_MAX];    /**< the directory to cache all the records, should be set before start. */
extern const char *sgi_malloc_records_filename; /**< the heap records filename */
extern const char *sgi_vm_records_filename;     /**< the vm records filename */
extern const char *sgi_stacks_records_filename; /**< the backtrace records filename */


// MARK: - Allocations Logging

extern boolean_t sgi_memory_allocate_logging_enabled; /* when clear, no logging takes place */

extern boolean_t sgi_allocations_need_sys_frame;        /**< record system libraries frames when record backtrace, default false*/

// for storing/looking up allocations that haven't yet be written to disk; consistent size across 32/64-bit processes.
// It's important that these fields don't change alignment due to the architecture because they may be accessed from an
// analyzing process with a different arch - hence the pragmas.
#pragma pack(push, 4)
typedef struct {
    sgi_splay_tree *malloc_records = NULL;                  /**< store Heap memory allocations info, each item contains ptr,size,stackid */
    sgi_splay_tree *vm_records = NULL;                      /**< store other vm memory allocations info, each item contains ptr,size,stackid */
    sgi_backtrace_uniquing_table *backtrace_records = NULL; /**< store the stacks when allocate memory */
} sgi_allocations_record_raw;
#pragma pack(pop)

extern sgi_allocations_record_raw *sgi_recording; /**< single-thread access variables */

boolean_t sgi_prepare_memory_allocate_logging(void); /**< prepare logging before start */

void sgi_clear_memory_allocate_logging(void);  /**< clear loggin after stop*/

/*
 when operating `sgi_recording`, you should make sure it's thread safe.
 use locking method below to keep it safe.
 */
void sgi_memory_allocate_logging_lock(void);
void sgi_memory_allocate_logging_unlock(void);


typedef void(sgi_malloc_logger_t)(uint32_t type_flags, uintptr_t zone_ptr, uintptr_t arg2, uintptr_t arg3, uintptr_t return_val, uint32_t num_hot_to_skip);

extern sgi_malloc_logger_t *malloc_logger;
extern sgi_malloc_logger_t *__syscall_logger;

void sgi_allocate_logging(uint32_t type_flags, uintptr_t zone_ptr, uintptr_t size, uintptr_t ptr_arg, uintptr_t return_val, uint32_t num_hot_to_skip);

// MARK: - Single chunk malloc detect
typedef void (^sgi_chunk_malloc_block)(size_t bytes, vm_address_t *stack_frames, size_t frames_count);
void sgi_start_single_chunk_malloc_detector(size_t threshold_in_bytes, sgi_chunk_malloc_block callback);
void sgi_config_single_chunk_malloc_threshold(size_t threshold_in_bytes);
void sgi_stop_single_chunk_malloc_detector(void);


#ifdef __cplusplus
}
#endif

#endif /* sgi_memory_allocate_logging_h */
