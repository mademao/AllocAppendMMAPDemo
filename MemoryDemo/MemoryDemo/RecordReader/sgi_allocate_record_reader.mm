//
// sgi_allocate_record_reader.mm
// SGIAPMAllocPlugin
//
// Created by mademao on 2020/4/21.
// Copyright © 2020 Sogou. All rights reserved.
//


#include "sgi_allocate_record_reader.h"
#include "sgi_backtrace_uniquing_table.h"

#import "SGIDyldImagesUtil.h"

#include <list>
#include <map>

using namespace SGIAPMAlloc;


const char *SGI_LOGGING_CATEGORY_MALLOC = "unknown_malloc";
const char *SGI_LOGGING_CATEGORY_VMALLOCATE = "unknown_vmallocate";
const char *SGI_LOGGING_CATEGORY_MMAP = "unknown_mmap/shared_mem";
const char *SGI_LOGGING_CATEGORY_UNKNOWN = "unknown";

typedef struct _sgi_allocate_record {
    uint64_t stack_id;
    uint32_t size;
    uint32_t count;
    void *category;
    uint32_t flag;

    bool operator()(const _sgi_allocate_record &lhs, const _sgi_allocate_record &rhs) const {
        return lhs.stack_id == rhs.stack_id;
    }
} sgi_allocate_record;

static bool sgi_compare_vm_stack_log_report_item(const AllocateRecords::InCategory *first, const AllocateRecords::InCategory *second) {
    return first->size > second->size;
}

static void merge_record_into_stacks(
    uint64_t stackid_and_flags,
    uint64_t category_and_size,
    std::map<uint64_t, sgi_allocate_record *> &stack_map) {

    uint64_t stackid = SGI_ALLOCATIONS_OFFSET(stackid_and_flags);
    uint32_t flag = SGI_ALLOCATIONS_FLAGS(stackid_and_flags);
    uint32_t size = SGI_ALLOCATIONS_SIZE(category_and_size);
    void *category = (void *)SGI_ALLOCATIONS_CATEGORY(category_and_size);

    auto m_stackid_item = stack_map.find(stackid);
    if (m_stackid_item != stack_map.end()) {
        sgi_allocate_record *log = m_stackid_item->second;
        log->size += size;
        log->count++;
        if (log->category == NULL && category != NULL) {
            log->category = category;
        }
    } else {
        sgi_allocate_record *log = new sgi_allocate_record;
        log->stack_id = stackid;
        log->flag = flag;
        log->size = size;
        log->category = category;
        log->count = 1;
        stack_map[stackid] = log;
    }
}

static void merge_stacks_into_categories(
    std::map<uint64_t, sgi_allocate_record *> &stack_map,
    std::map<uint64_t, std::list<sgi_allocate_record *> *> &category_map) {

    for (auto i = stack_map.begin(); i != stack_map.end(); ++i) {
        uint64_t category_id = (uint64_t)i->second->category;
        if (i->second->flag & sgi_allocations_type_vm_allocate) {
            if (i->second->flag & sgi_allocations_type_mapped_file_or_shared_mem) {
                printf("mdm1-*\n");
            } else {
                printf("mdm-*2\n");
            }
        }
        if (category_id == 0) {
            if (i->second->flag & sgi_allocations_type_alloc) {
                category_id = (uint64_t)SGI_LOGGING_CATEGORY_MALLOC;
            } else if (i->second->flag & sgi_allocations_type_vm_allocate) {
                category_id = (uint64_t)SGI_LOGGING_CATEGORY_VMALLOCATE;
            } else if (i->second->flag & sgi_allocations_type_mapped_file_or_shared_mem) {
                category_id = (uint64_t)SGI_LOGGING_CATEGORY_MMAP;
            } else {
                category_id = (uint64_t)SGI_LOGGING_CATEGORY_UNKNOWN;
            }
        }
        auto category = category_map.find(category_id);
        if (category != category_map.end()) {
            std::list<sgi_allocate_record *> *item = category->second;
            item->__emplace_back(i->second);
        } else {
            std::list<sgi_allocate_record *> *item = new std::list<sgi_allocate_record *>;
            item->__emplace_back(i->second);
            category_map[category_id] = item;
        }
    }
}

static void free_category_and_stackid_groups(
    std::map<uint64_t, std::list<sgi_allocate_record *> *> &log_map_by_category,
    std::map<uint64_t, sgi_allocate_record *> &log_map_by_stackid) {
    for (auto mit = std::begin(log_map_by_category); mit != std::end(log_map_by_category); ++mit) {
        std::list<sgi_allocate_record *> *logs = mit->second;
        logs->clear();
        delete logs;
        logs = nullptr;
    }

    log_map_by_category.clear();

    for (auto it = log_map_by_stackid.begin(); it != log_map_by_stackid.end(); ++it) {
        sgi_allocate_record *item = it->second;
        delete item;
    }
    log_map_by_stackid.clear();
}

static bool sgi_compare_vm_stack_log_report_item_stack(const AllocateRecords::InStackId *first, const AllocateRecords::InStackId *second) {
    return first->size > second->size;
}

static void generate_report_from_category_groups(
    std::map<uint64_t, std::list<sgi_allocate_record *> *> &log_map_by_category,
    sgi_dyld_image_info *dyld_image_info,
    std::list<AllocateRecords::InCategory *> *out_report) {
    for (auto mit = std::begin(log_map_by_category); mit != std::end(log_map_by_category); ++mit) {
        int64_t category = mit->first;
        std::list<sgi_allocate_record *> *logs = mit->second;

        std::list<AllocateRecords::InStackId *> *stacks = new std::list<AllocateRecords::InStackId *>;
        uint64_t category_size = 0;
        uint64_t object_count = 0;
        for (auto lit = logs->begin(); lit != logs->end(); ++lit) {
            sgi_allocate_record *log = (*lit);
            category_size += log->size;
            object_count += log->count;

            AllocateRecords::InStackId *stack = new AllocateRecords::InStackId;
            stack->size = log->size;
            stack->count = log->count;
            stack->stack_id = log->stack_id;
            stacks->__emplace_back(stack);
        }

        stacks->sort(sgi_compare_vm_stack_log_report_item_stack);

        AllocateRecords::InCategory *item = new AllocateRecords::InCategory;
        if ((char *)category == NULL) {
            item->name = "";
        } else {
            item->name = (char *)category;
        }
        item->size = (uint32_t)category_size;
        item->count = (uint32_t)object_count;
        item->stacks = stacks;

        out_report->__emplace_back(item);
    }
}

static void sgi_allocations_free_log_report(std::list<AllocateRecords::InCategory *> *report) {
    for (auto it = report->begin(); it != report->end(); ++it) {
        AllocateRecords::InCategory *item = *it;
        for (auto iti = item->stacks->begin(); iti != item->stacks->end(); ++iti) {
            delete (*iti);
            *iti = nullptr;
        }
        item->stacks->clear();
        delete item->stacks;
        item->stacks = nullptr;

        delete item;
        item = nullptr;
    }

    report->clear();
    delete report;
    report = nullptr;
}

// MARK: - public

AllocateRecords::~AllocateRecords() {
    freeFormedRecords();
    _dyld_image_info = NULL;
}

void AllocateRecords::freeFormedRecords(void) {
    if (_formedRecords == NULL)
        return;

    sgi_allocations_free_log_report(_formedRecords);
    _formedRecords = NULL;
}

void AllocateRecords::parseAndGroupingRawRecords(void) {
    if (_rawRecords == nil)
        return;

    std::list<AllocateRecords::InCategory *> *formedRecord = new std::list<AllocateRecords::InCategory *>();

    _recordSize = 0;
    _allocateRecordCount = 0;

    // 合并同一调用堆栈的不同内存分配记录
    std::map<uint64_t, sgi_allocate_record *> log_map_by_stackid;
    std::map<uint64_t, std::list<sgi_allocate_record *> *> log_map_by_category;

    for (uint32_t i = 0; i < _rawRecords->max_index; ++i) {
        sgi_splay_tree_node node = _rawRecords->node[i];

        if (node.stackid_and_flags == 0)
            continue;

        uint32_t size = SGI_ALLOCATIONS_SIZE(node.category_and_size);

        merge_record_into_stacks(node.stackid_and_flags, node.category_and_size, log_map_by_stackid);

        _recordSize += size;
        _allocateRecordCount += 1;
    }

    // group by category_id
    merge_stacks_into_categories(log_map_by_stackid, log_map_by_category);

    _stackRecordCount = (uint32_t)log_map_by_stackid.size();
    _categoryRecordCount = (uint32_t)log_map_by_category.size();

    // 生成 report 数据结构
    generate_report_from_category_groups(log_map_by_category, _dyld_image_info, formedRecord);

    // free data
    free_category_and_stackid_groups(log_map_by_category, log_map_by_stackid);

    formedRecord->sort(sgi_compare_vm_stack_log_report_item);
    _formedRecords = formedRecord;

    resetInCategoryIterator();
}

AllocateRecords::InCategory *AllocateRecords::firstRecordInCategory() {
    if (_formedRecords == NULL)
        return NULL;

    _recordIterator = _formedRecords->begin();
    return *_recordIterator;
}

AllocateRecords::InCategory *AllocateRecords::nextRecordInCategory() {
    if (_recordIterator == kNullIterator) {
        return NULL;
    }

    _recordIterator++;
    if (_recordIterator == _formedRecords->end()) {
        resetInCategoryIterator();
        return NULL;
    }

    return *_recordIterator;
}

void AllocateRecords::resetInCategoryIterator() {
    _recordIterator = kNullIterator;
}

uint64_t AllocateRecords::recordSize() const {
    return _recordSize;
}

uint32_t AllocateRecords::allocateRecordCount() const {
    return _allocateRecordCount;
}

uint32_t AllocateRecords::stackRecordCount() const {
    return _stackRecordCount;
}

uint32_t AllocateRecords::categoryRecordCount() const {
    return _categoryRecordCount;
}
