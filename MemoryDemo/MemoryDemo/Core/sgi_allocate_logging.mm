//
// sgi_allocate_logging.mm
// SGIAPMAllocPlugin
//
// Created by mademao on 2020/4/21.
// Copyright © 2020 Sogou. All rights reserved.
//


#include "sgi_allocate_logging.h"

#include <assert.h>
#include <errno.h>
#include <execinfo.h>
#include <limits.h>
#include <malloc/malloc.h>
#include <string.h>
#include <sys/fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

#import "SGIDyldImagesUtil.h"
#import "SGIAPMCommonDef.h"

#include "sgi_backtrace_uniquing_table.h"
#include "sgi_inner_allocate.h"
#include "sgi_locking.h"
#include "sgi_splay_tree.h"

#define __TSD_THREAD_SELF 0

// MARK: - Constants/Globals

// vm_statistics.h
// clang-format off
static const char *vm_flags[] = {
    "0", "malloc", "malloc_small", "malloc_large", "malloc_huge", "SBRK",
    "realloc", "malloc_tiny", "malloc_large_reusable", "malloc_large_reused",
    "analysis_tool", "malloc_nano", "12", "13", "14",
    "15", "16", "17", "18", "19",
    "mach_msg", "iokit", "22", "23", "24",
    "25", "26", "27", "28", "29",
    "stack", "guard", "shared_pmap", "dylib", "objc_dispatchers",
    "unshared_pmap", "36", "37", "38", "39",
    "appkit", "foundation", "core_graphics", "carbon_or_core_services", "java",
    "coredata", "coredata_objectids", "47", "48", "49",
    "ats", "layerkit", "cgimage", "tcmalloc", "CG_raster_data(layers&images)",
    "CG_shared_images_fonts", "CG_framebuffers", "CG_backingstores", "CG_x-alloc", "59",
    "dyld", "dyld_malloc", "sqlite", "JavaScriptCore", "JIT_allocator",
    "JIT_file", "GLSL", "OpenCL", "QuartzCore", "WebCorePurgeableBuffers",
    "ImageIO", "CoreProfile", "assetsd", "os_once_alloc", "libdispatch",
    "Accelerate.framework", "CoreUI", "CoreUIFile", "GenealogyBuffers", "RawCamera",
    "CorpseInfo", "ASL", "SwiftRuntime", "SwiftMetadata", "DHMM",
    "85", "SceneKit.framework", "skywalk", "IOSurface", "libNetwork",
    "Audio", "VideoBitStream", "CoreMediaXCP", "CoreMediaRPC", "CoreMediaMemoryPool",
    "CoreMediaReadCache", "CoreMediaCrabs", "QuickLook", "Accounts.framework", "99",
};
// clang-format on

static _malloc_lock_s stack_logging_lock = _MALLOC_LOCK_INIT;
static vm_address_t thread_doing_logging = 0;

boolean_t sgi_memory_allocate_logging_enabled = false;

boolean_t sgi_allocations_need_sys_frame = false;

// single-thread access variables
sgi_allocations_record_raw *sgi_recording;

static vm_address_t *current_stack_origin;
static vm_address_t current_frames[SGI_ALLOCATIONS_MAX_STACK_SIZE];
static size_t current_frames_count = 0;

char sgi_records_cache_dir[PATH_MAX];
const char *sgi_vm_records_filename = "vm_records_raw";
const char *sgi_malloc_records_filename = "malloc_records_raw";
const char *sgi_stacks_records_filename = "stacks_records_raw";

// single chunk malloc monitor callback
static sgi_chunk_malloc_block chunk_malloc_detector_block = NULL;
static boolean_t chunk_malloc_detector_enable = false;
static size_t chunk_malloc_detector_threshold_in_bytes = 0;


// MAKR: -

static void sgi_disable_stack_logging(void) {
    SGIAPMMallocLog("stack logging disabled due to previous errors.\n");
    sgi_memory_allocate_logging_enabled = false;
}

// MARK: - stack logging

static malloc_zone_t *stack_id_zone = NULL;

boolean_t sgi_prepare_memory_allocate_logging(void) {
    sgi_memory_allocate_logging_lock();

    if (!sgi_recording) {
        size_t full_shared_mem_size = sizeof(sgi_allocations_record_raw);
        sgi_recording = (sgi_allocations_record_raw *)mmap(0, full_shared_mem_size, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE, VM_MAKE_TAG(VM_AMKE_TAG_UNIQUING_TABLE), 0);
        if (MAP_FAILED == sgi_recording) {
            SGIAPMMallocLog("[APM][Alloc] error creating VM region for stack logging output buffers.\n");
            sgi_disable_stack_logging();
            goto fail;
        }

        // create the backtrace uniquing table
        char uniquing_table_file_path[PATH_MAX];
        strcpy(uniquing_table_file_path, sgi_records_cache_dir);
        strcat(uniquing_table_file_path, "/");
        strcat(uniquing_table_file_path, sgi_stacks_records_filename);

        size_t page_size = sgi_allocations_need_sys_frame ? SGI_VM_DEFAULT_UNIQUING_PAGE_SIZE_WITH_SYS : SGI_VM_DEFAULT_UNIQUING_PAGE_SIZE_WITHOUT_SYS;
        sgi_recording->backtrace_records = sgi_create_uniquing_table(uniquing_table_file_path, page_size);
        if (!sgi_recording->backtrace_records) {
            SGIAPMMallocLog("[APM][Alloc] error while allocating stack uniquing table.\n");
            sgi_disable_stack_logging();
            goto fail;
        }

        sgi_recording->vm_records = NULL;

        uint64_t stack_buffer_sz = (uint64_t)round_page(sizeof(vm_address_t) * SGI_ALLOCATIONS_MAX_STACK_SIZE);
        current_stack_origin = (vm_address_t *)sgi_allocate_page(stack_buffer_sz);
        if (!current_stack_origin) {
            SGIAPMMallocLog("[APM][Alloc] error while allocating stack trace buffer.\n");
            sgi_disable_stack_logging();
            goto fail;
        }

        if (stack_id_zone == NULL) {
            stack_id_zone = malloc_create_zone(0, 0);
            malloc_set_zone_name(stack_id_zone, "com.sogou.apm.allocations");
            sgi_setup_alloc_malloc_zone(stack_id_zone);
        }

        if (sgi_recording) {
            char vm_filepath[PATH_MAX], malloc_filepath[PATH_MAX];
            strcpy(vm_filepath, sgi_records_cache_dir);
            strcpy(malloc_filepath, sgi_records_cache_dir);
            strcat(vm_filepath, "/");
            strcat(malloc_filepath, "/");
            strcat(vm_filepath, sgi_vm_records_filename);
            strcat(malloc_filepath, sgi_malloc_records_filename);
            sgi_recording->vm_records = sgi_splay_tree_create_on_mmapfile(5000, vm_filepath);
            sgi_recording->malloc_records = sgi_splay_tree_create_on_mmapfile(200000, malloc_filepath);
        }
    }

    sgi_memory_allocate_logging_unlock();
    return true;

fail:
    sgi_memory_allocate_logging_unlock();
    return false;
}

void sgi_clear_memory_allocate_logging(void) {
    sgi_memory_allocate_logging_lock();
    
    if (sgi_recording) {
        if (sgi_recording->malloc_records) {
            sgi_splay_tree_close(sgi_recording->malloc_records);
            sgi_recording->malloc_records = nullptr;
        }
        if (sgi_recording->vm_records) {
            sgi_splay_tree_close(sgi_recording->vm_records);
            sgi_recording->vm_records = nullptr;
        }
        if (sgi_recording->backtrace_records) {
            sgi_destroy_uniquing_table(sgi_recording->backtrace_records);
            sgi_recording->backtrace_records = nullptr;
        }
        sgi_recording = nullptr;
    }
    
    sgi_memory_allocate_logging_unlock();
}

void sgi_start_single_chunk_malloc_detector(size_t threshold_in_bytes, sgi_chunk_malloc_block callback) {
    chunk_malloc_detector_enable = true;
    chunk_malloc_detector_block = callback;
    chunk_malloc_detector_threshold_in_bytes = threshold_in_bytes;
}

void sgi_config_single_chunk_malloc_threshold(size_t threshold_in_bytes) {
    chunk_malloc_detector_threshold_in_bytes = threshold_in_bytes;
}

void sgi_stop_single_chunk_malloc_detector(void) {
    chunk_malloc_detector_enable = false;
    chunk_malloc_detector_block = NULL;
}

void sgi_memory_allocate_logging_lock(void) {
    _malloc_lock_lock(&stack_logging_lock);
}

void sgi_memory_allocate_logging_unlock(void) {
    _malloc_lock_unlock(&stack_logging_lock);
}


// returns the stack id or invalid_stack_id if any kind of error
// this needs to be done while stack_logging_lock is locked)

static inline boolean_t isInAppAddress(vm_address_t addr) {
    return !sgi_dyld_check_in_sys_libraries(sgi_current_dyld_image_info, addr);
}

uint64_t sgi_enter_stack_into_table_while_locked(vm_address_t self_thread, uint32_t num_hot_to_skip, boolean_t add_thread_id, size_t ptr_size) {
    // gather stack
    uint32_t count = backtrace((void **)current_stack_origin, SGI_ALLOCATIONS_MAX_STACK_SIZE - 1); // only gather up to STACK_LOGGING_MAX_STACK_SIZE-1 since we append thread id
    
    if (add_thread_id) {
        current_stack_origin[count++] = self_thread + 1; // stuffing thread # in the coldest slot. Add 1 to match what the old stack logging did.
    }

    // skip stack frames after the malloc call
    num_hot_to_skip += 3; // __disk_stack_logging_log_stack | __enter_stack_into_table_while_locked | thread_stack_pcs

    if (count <= num_hot_to_skip) {
        return sgi_vm_invalid_stack_id;
    }

    bool need_skip_sys_frame = !sgi_allocations_need_sys_frame;
    size_t offset = 0, j = num_hot_to_skip;
    boolean_t exist_app_frame = false;
    vm_address_t last_frame = 0;
    for (; j < count; j++) {
        if (!exist_app_frame) {
            if (isInAppAddress(current_stack_origin[j])) {
                // exclude main() | dylib start
                if (j < count - 2) {
                    exist_app_frame = true;
                }

                if (last_frame != 0) {
                    current_frames[offset++] = last_frame;
                }
                current_frames[offset++] = current_stack_origin[j];
            } else {
                if (need_skip_sys_frame) {
                    last_frame = current_stack_origin[j];
                } else {
                    current_frames[offset++] = current_stack_origin[j];
                }
            }
        } else {
            if (!need_skip_sys_frame || isInAppAddress(current_stack_origin[j]) || j == count - 1) {
                current_frames[offset++] = current_stack_origin[j];
            }
        }
    }

    current_frames_count = offset;

    uint64_t uniqueStackIdentifier = sgi_vm_invalid_stack_id;
    if (need_skip_sys_frame && !exist_app_frame) {
        return uniqueStackIdentifier;
    }

    if (!sgi_enter_frames_in_table(sgi_recording->backtrace_records, &uniqueStackIdentifier, current_frames, (uint32_t)current_frames_count)) {
        sgi_recording->backtrace_records = sgi_expand_uniquing_table(sgi_recording->backtrace_records);
        if (sgi_recording->backtrace_records) {
            if (!sgi_enter_frames_in_table(sgi_recording->backtrace_records, &uniqueStackIdentifier, current_frames, (uint32_t)current_frames_count))
                return sgi_vm_invalid_stack_id;
        } else {
            return sgi_vm_invalid_stack_id;
        }
    }

    return uniqueStackIdentifier;
}

void sgi_allocate_logging(uint32_t type_flags, uintptr_t zone_ptr, uintptr_t arg2, uintptr_t arg3, uintptr_t return_val, uint32_t num_hot_to_skip) {
    if (!sgi_memory_allocate_logging_enabled)
        return;
    
    if (type_flags & sgi_allocations_type_mapped_file_or_shared_mem) {
        printf("123\n");
    }

    uintptr_t size = 0;
    uintptr_t ptr_arg = 0;
    uint64_t stackid_and_flags = 0;
    uint64_t category_and_size = 0;

#if SGI_ALLOCATIONS_DEBUG
    static uint64_t malloc_size_counter = 0;
    static uint64_t vm_allocate_size_counter = 0;
    static uint64_t count = 0;
    static uint64_t alive_ptr_count = 0;
#endif

    // check incoming data
    if (type_flags & sgi_allocations_type_alloc && type_flags & sgi_allocations_type_dealloc) {
        size = arg3;
        ptr_arg = arg2; // the original pointer
        if (ptr_arg == return_val) {
            return; // realloc had no effect, skipping
        }
        if (ptr_arg == 0) { // realloc(NULL, size) same as malloc(size)
            type_flags ^= sgi_allocations_type_dealloc;
        } else {
            // realloc(arg1, arg2) -> result is same as free(arg1); malloc(arg2) -> result
            sgi_allocate_logging(sgi_allocations_type_dealloc, zone_ptr, ptr_arg, (uintptr_t)0, (uintptr_t)0, num_hot_to_skip + 1);
            sgi_allocate_logging(sgi_allocations_type_alloc, zone_ptr, size, (uintptr_t)0, return_val, num_hot_to_skip + 1);
            return;
        }
    }

    if (type_flags & sgi_allocations_type_dealloc || type_flags & sgi_allocations_type_vm_deallocate) {
        // For VM deallocations we need to know the size, since they don't always match the
        // VM allocations.  It would be nice if arg2 was the size, for consistency with alloc and
        // realloc events.  However we can't easily make that change because all projects
        // (malloc.c, GC auto_zone, and gmalloc) have historically put the pointer in arg2 and 0 as
        // the size in arg3.  We'd need to change all those projects in lockstep, which isn't worth
        // the trouble.
        ptr_arg = arg2;
        size = arg3;
        if (ptr_arg == 0) {
            return; // free(nil)
        }
    }
    if (type_flags & sgi_allocations_type_alloc || type_flags & sgi_allocations_type_vm_allocate) {
        if (return_val == 0 || return_val == (uintptr_t)MAP_FAILED) {
            return; // alloc that failed
        }
        size = arg2;
    }

    if (type_flags & sgi_allocations_type_vm_allocate || type_flags & sgi_allocations_type_vm_deallocate) {
        mach_port_t targetTask = (mach_port_t)zone_ptr;
        // For now, ignore "injections" of VM into other tasks.
        if (targetTask != mach_task_self()) {
            return;
        }
    }

    //    type_flags &= sgi_allocations_valid_type_flags;

    vm_address_t self_thread = (vm_address_t)_os_tsd_get_direct(__TSD_THREAD_SELF);
    if (thread_doing_logging == self_thread) {
        // Prevent a thread from deadlocking against itself if vm_allocate() or malloc()
        // is called below here, from __prepare_to_log_stacks() or _prepare_to_log_stacks_stage2(),
        // or if we are logging an event and need to call __expand_uniquing_table() which calls
        // vm_allocate() to grow stack logging data structures.  Any such "administrative"
        // vm_allocate or malloc calls would attempt to recursively log those events.
        return;
    }

    // lock and enter
    sgi_memory_allocate_logging_lock();

    thread_doing_logging = self_thread; // for preventing deadlock'ing on stack logging on a single thread

    uint64_t uniqueStackIdentifier = sgi_vm_invalid_stack_id;

    // for single chunk malloc detector
    vm_address_t frames_for_chunk_malloc[SGI_ALLOCATIONS_MAX_STACK_SIZE];
    size_t frames_count_for_chunk_malloc = 0;

    if (type_flags & sgi_allocations_type_vm_deallocate) {
        if (sgi_recording && sgi_recording->vm_records) {
            sgi_splay_tree_node removed = sgi_splay_tree_delete(sgi_recording->vm_records, ptr_arg);
            if (removed.category_and_size > 0) {
                size = SGI_ALLOCATIONS_SIZE(removed.category_and_size);
            }
        }
        goto out;
    } else if (type_flags & sgi_allocations_type_dealloc) {
        if (sgi_recording && sgi_recording->malloc_records) {
            sgi_splay_tree_node removed = sgi_splay_tree_delete(sgi_recording->malloc_records, ptr_arg);
            if (removed.category_and_size > 0) {
                size = SGI_ALLOCATIONS_SIZE(removed.category_and_size);
            }
        }
        goto out;
    }

    // now actually begin

    // since there could have been a fatal (to stack logging) error such as the log files not being created, check these variables before continuing
    if (!sgi_memory_allocate_logging_enabled) {
        goto out;
    }

    if (((type_flags & sgi_allocations_type_vm_allocate) || (type_flags & sgi_allocations_type_alloc)) && size > 0) {
        uniqueStackIdentifier = sgi_enter_stack_into_table_while_locked(self_thread, num_hot_to_skip, false, 1);
    }

    if (uniqueStackIdentifier == sgi_vm_invalid_stack_id) {
        goto out;
    }

    // store ptr, size, & stack_id
    stackid_and_flags = SGI_ALLOCATIONS_OFFSET_AND_FLAGS(uniqueStackIdentifier, type_flags);
    if (type_flags & sgi_allocations_type_vm_allocate) {
        uint32_t type = (type_flags & ~sgi_allocations_type_vm_allocate);
        type = type >> 24;
        const char *flag = "unknown";
        if (type <= 99)
            flag = vm_flags[type];
        category_and_size = SGI_ALLOCATIONS_CATEGORY_AND_SIZE(flag, size);
    } else {
        category_and_size = SGI_ALLOCATIONS_CATEGORY_AND_SIZE(0, size);
    }

    if (type_flags & sgi_allocations_type_vm_allocate) {
        if (!sgi_splay_tree_insert(sgi_recording->vm_records, return_val, stackid_and_flags, category_and_size)) {
            sgi_recording->vm_records = sgi_expand_splay_tree(sgi_recording->vm_records);
            if (sgi_recording->vm_records) {
                sgi_splay_tree_insert(sgi_recording->vm_records, return_val, stackid_and_flags, category_and_size);
            } else {
                sgi_disable_stack_logging();
            }
        }
    } else if (type_flags & sgi_allocations_type_alloc) {
        if (!sgi_splay_tree_insert(sgi_recording->malloc_records, return_val, stackid_and_flags, category_and_size)) {
            sgi_recording->malloc_records = sgi_expand_splay_tree(sgi_recording->malloc_records);
            if (sgi_recording->malloc_records) {
                sgi_splay_tree_insert(sgi_recording->malloc_records, return_val, stackid_and_flags, category_and_size);
            } else {
                sgi_disable_stack_logging();
            }
        }
        // 此处若直接回调让外部处理，需要处理死锁问题。故此处延后到 sgi_malloc_unlock_stack_logging 锁结束后处理
        if (chunk_malloc_detector_enable && chunk_malloc_detector_threshold_in_bytes < size && chunk_malloc_detector_block != NULL) {
            memcpy(frames_for_chunk_malloc, current_frames, current_frames_count * sizeof(vm_address_t));
            frames_count_for_chunk_malloc = current_frames_count;
        }
    }

out:

#if SGI_ALLOCATIONS_DEBUG
    if (type_flags & sgi_allocations_type_alloc) {
        if (uniqueStackIdentifier != sgi_vm_invalid_stack_id)
            malloc_size_counter += size;
        alive_ptr_count++;
    } else if (type_flags & sgi_allocations_type_dealloc) {
        malloc_size_counter -= size;
        alive_ptr_count--;
    } else if (type_flags & sgi_allocations_type_vm_allocate) {
        vm_allocate_size_counter += size;
        alive_ptr_count++;
    } else if (type_flags & sgi_allocations_type_vm_deallocate) {
        vm_allocate_size_counter -= size;
        alive_ptr_count--;
    }

    if (++count % 500000 == 0) {
        struct task_basic_info info;
        mach_msg_type_number_t size = (sizeof(task_basic_info_data_t) / sizeof(natural_t));
        task_info(mach_task_self(), TASK_BASIC_INFO, (task_info_t)&info, &size);
        int64_t memoryAppUsedInByte = info.resident_size;

        SGIAPMMallocLog("malloc: %y, vm: %y, api: %y, alive_ptr: %d, call_count: %d\n", malloc_size_counter, vm_allocate_size_counter, memoryAppUsedInByte, alive_ptr_count, count);
    }

#endif

    thread_doing_logging = 0;
    sgi_memory_allocate_logging_unlock();

    if (chunk_malloc_detector_enable && chunk_malloc_detector_threshold_in_bytes < size && chunk_malloc_detector_block != NULL && frames_count_for_chunk_malloc > 0) {
        chunk_malloc_detector_block(size, frames_for_chunk_malloc, frames_count_for_chunk_malloc);
    }
}
