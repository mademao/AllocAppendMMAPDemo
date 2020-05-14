//
// sgi_inner_allocate.h
// SGIAPMAllocPlugin
//
// Created by mademao on 2020/4/21.
// Copyright © 2020 Sogou. All rights reserved.
//


#ifndef sgi_inner_allocate_h
#define sgi_inner_allocate_h

#include <malloc/malloc.h>
#include <stdio.h>
#include <sys/types.h>

#define VM_AMKE_TAG_UNIQUING_TABLE 200 //

#ifdef __cplusplus
extern "C" {
#endif

void sgi_setup_alloc_malloc_zone(malloc_zone_t *zone);

void *sgi_allocate_page(uint64_t memSize);
int sgi_deallocate_pages(void *memPointer, uint64_t memSize);

void *sgi_malloc(size_t size);
void *sgi_realloc(void *ptr, size_t size);
void sgi_free(void *ptr);

#ifdef __cplusplus
}
#endif

#endif /* sgi_inner_allocate_h */
