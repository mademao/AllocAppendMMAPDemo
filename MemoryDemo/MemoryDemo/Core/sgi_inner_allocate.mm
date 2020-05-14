//
// sgi_inner_allocate.mm
// SGIAPMAllocPlugin
//
// Created by mademao on 2020/4/21.
// Copyright © 2020 Sogou. All rights reserved.
//


#include "sgi_inner_allocate.h"
#include <mach/mach.h>
#import "SGIAPMCommonDef.h"

static malloc_zone_t *mem_zone = nullptr;

void sgi_setup_alloc_malloc_zone(malloc_zone_t *zone) {
    mem_zone = zone;
}

void *sgi_allocate_page(uint64_t memSize) {
    vm_address_t allocatedMem = 0ull;
    if (vm_allocate(mach_task_self(), &allocatedMem, (vm_size_t)memSize, VM_FLAGS_ANYWHERE | VM_MAKE_TAG(VM_AMKE_TAG_UNIQUING_TABLE)) != KERN_SUCCESS) {
        SGIAPMMallocLog("[error] allocate_pages(): virtual memory exhausted!\n");
    }
    return (void *)(uintptr_t)allocatedMem;
}

int sgi_deallocate_pages(void *memPointer, uint64_t memSize) {
    return vm_deallocate(mach_task_self(), (vm_address_t)(uintptr_t)memPointer, (vm_size_t)memSize);
}

void *sgi_malloc(size_t size) {
    return mem_zone->malloc(mem_zone, size);
}

void *sgi_realloc(void *ptr, size_t size) {
    return mem_zone->realloc(mem_zone, ptr, size);
}

void sgi_free(void *ptr) {
    mem_zone->free(mem_zone, ptr);
}
