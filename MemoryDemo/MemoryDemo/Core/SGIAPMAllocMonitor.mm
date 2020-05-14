//
// SGIAPMAllocMonitor.mm
// SGIAPMAllocPlugin
//
// Created by mademao on 2020/4/21.
// Copyright © 2020 Sogou. All rights reserved.
//


#import "SGIAPMAllocMonitor.h"

#import "SGIDyldImagesUtil.h"
#import "SGIAPMCommonDef.h"

#import "NSObject+SGIAPMAlloc.h"
#import "sgi_thread_utils.h"
#import "sgi_allocate_logging.h"

#import <list>

// MARK: - Malloc Category Record
extern bool __CFOASafe;
extern void (*__CFObjectAllocSetLastAllocEventNameFunction)(void *, const char *);
void (*SGI_ORIGINAL___CFObjectAllocSetLastAllocEventNameFunction)(void *, const char *) = NULL;

extern void sgi_cfobject_alloc_set_last_alloc_event_name_function(void *, const char *);

extern void observeObjcObjectAllocationEventName(void);

extern void sgi_set_last_allocation_event_name(void *ptr, const char *classname);

// MARK: allication event name
void sgi_set_last_allocation_event_name(void *ptr, const char *classname) {
    if (!sgi_memory_allocate_logging_enabled || sgi_recording == nullptr) {
        return;
    }

    sgi_memory_allocate_logging_lock();
    // find record and set category.
    uint32_t idx = 0;
    if (sgi_recording->malloc_records != nullptr)
        idx = sgi_splay_tree_search(sgi_recording->malloc_records, (vm_address_t)ptr, false);

    if (idx > 0) {
        sgi_splay_tree_node *node = &sgi_recording->malloc_records->node[idx];
        size_t size = SGI_ALLOCATIONS_SIZE(node->category_and_size);
        node->category_and_size = SGI_ALLOCATIONS_CATEGORY_AND_SIZE((uint64_t)classname, size);
    } else {
        uint32_t vm_idx = 0;
        if (sgi_recording->vm_records != nullptr)
            vm_idx = sgi_splay_tree_search(sgi_recording->vm_records, (vm_address_t)ptr, false);

        if (vm_idx > 0) {
            sgi_splay_tree_node *node = &sgi_recording->vm_records->node[vm_idx];
            size_t size = SGI_ALLOCATIONS_SIZE(node->category_and_size);
            node->category_and_size = SGI_ALLOCATIONS_CATEGORY_AND_SIZE((uint64_t)classname, size);
        }
    }
    sgi_memory_allocate_logging_unlock();
}

void sgi_cfobject_alloc_set_last_alloc_event_name_function(void *ptr, const char *classname) {
    if (SGI_ORIGINAL___CFObjectAllocSetLastAllocEventNameFunction) {
        SGI_ORIGINAL___CFObjectAllocSetLastAllocEventNameFunction(ptr, classname);
    }

    sgi_set_last_allocation_event_name(ptr, classname);
}

// MARK: -

@interface SGIAPMAllocMonitor ()

@property (nonatomic, copy) NSString *logDir;
@property (nonatomic, strong) dispatch_source_t timer;
@property (nonatomic, strong) dispatch_queue_t timerQueue;

@end


@implementation SGIAPMAllocMonitor

//- (instancetype)init
//{
//    if (self = [super init]) {
//        dispatch_queue_attr_t attr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_DEFAULT, 0);
//        self.timerQueue = dispatch_queue_create("com.sogou.input.apm.memory.use", attr);
//
//        self.timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self.timerQueue);
//        dispatch_source_set_timer(self.timer, DISPATCH_TIME_NOW, 1.0 * NSEC_PER_SEC, 0);
//
//
//        dispatch_source_set_event_handler(self.timer, ^{
//            @autoreleasepool {
//                [self getMemory];
//            }
//        });
//        dispatch_resume(self.timer);
//    }
//    return self;
//}
//
//- (void)getMemory
//{
//    printf("mdm memory --- %.2f\n", [SGDeviceUtil usedSizeOfMemory]);
//}

+ (NSString *)logDir
{
    return g_monitor.logDir;
}

static SGIAPMAllocMonitor *g_monitor = nil;

+ (void)startPlugin
{
    if (g_monitor == nil) {
        g_monitor = [[SGIAPMAllocMonitor alloc] init];
        NSString *dirPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
        dirPath = [dirPath stringByAppendingPathComponent:@"memory"];
        [g_monitor setupPersistanceDirectory:dirPath];
        [g_monitor setIsStackLogNeedSysFrame:NO];
    }
    [g_monitor startMallocLogging:YES vmLogging:YES];
}

+ (void)stopPlugin
{
    if (g_monitor == nil) {
        return;
    }
    [g_monitor stopMallocLogging:YES vmLogging:YES];
    g_monitor = nil;
}

+ (BOOL)isRunning
{
    if (g_monitor == nil) {
        return NO;
    }
    return [g_monitor isLoggingOn];
}

+ (SGIAPMAllocRecordReader *)createRecordReader
{
//    if ([self isRunning] == NO) {
//        return nil;
//    }
    SGIAPMAllocRecordReader *recordReader = [[SGIAPMAllocRecordReader alloc] initWithMallocRecord:sgi_recording->malloc_records
                                                                                         vmRecord:sgi_recording->vm_records
                                                                                       stackTable:sgi_recording->backtrace_records
                                                                                  dyld_image_info:sgi_current_dyld_image_info
                                                                             collectionStackFrame:sgi_allocations_need_sys_frame];
    return recordReader;
}

+ (void)clearAllocMonitorMmapFileIfNeeded
{
    if ([self isRunning] == NO) {
        sgi_clear_memory_allocate_logging();
    }
}

- (void)setIsStackLogNeedSysFrame:(BOOL)isStackLogNeedSysFrame {
    if ([self isLoggingOn]) {
        return;
    }
    sgi_allocations_need_sys_frame = isStackLogNeedSysFrame;
}

- (BOOL)setupPersistanceDirectory:(NSString *)dir {
    if ([self isLoggingOn]) {
        return NO;
    }
    self.logDir = dir;

    NSError *error;
    if (![[NSFileManager defaultManager] fileExistsAtPath:self.logDir]) {
        if (![[NSFileManager defaultManager] createDirectoryAtPath:self.logDir withIntermediateDirectories:YES attributes:nil error:&error]) {
            SGIAPMLog(@"create directory %@ failed, %@ %@", self.logDir, @(error.code), error.localizedDescription);
            return NO;
        }
    }

    return YES;
}

- (BOOL)isLoggingOn {
    return sgi_memory_allocate_logging_enabled;
}

- (BOOL)startMallocLogging:(BOOL)mallocLogOn vmLogging:(BOOL)vmLogOn {
    if ([self isLoggingOn]) {
        return YES;
    }
#if TARGET_IPHONE_SIMULATOR
    return NO;
    // Only for device
#else // TARGET_IPHONE_SIMULATOR
    NSAssert(self.logDir.length > 0, @"You should conigure persistance directory before start malloc logging");

    strcpy(sgi_records_cache_dir, [self.logDir UTF8String]);
    
    sgi_clear_memory_allocate_logging();

    sgi_prepare_memory_allocate_logging();

    if (mallocLogOn) {
        malloc_logger = (sgi_malloc_logger_t *)sgi_allocate_logging;
    }

    if (vmLogOn) {
        __syscall_logger = sgi_allocate_logging;
    }

    if (mallocLogOn || vmLogOn) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            __CFOASafe = true;
            SGI_ORIGINAL___CFObjectAllocSetLastAllocEventNameFunction = __CFObjectAllocSetLastAllocEventNameFunction;
            __CFObjectAllocSetLastAllocEventNameFunction = sgi_cfobject_alloc_set_last_alloc_event_name_function;

            sgi_allocation_event_logger = sgi_set_last_allocation_event_name;
            [NSObject sgi_startAllocTrack];

            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.f * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                NSString *dyldDumperPath = [self.logDir stringByAppendingPathComponent:@"dyld-images"];
                sgi_dyld_save_dyld_image_info(sgi_current_dyld_image_info, dyldDumperPath.UTF8String);
            });
        });
    }
    
    sgi_memory_allocate_logging_enabled = true;

    return YES;
#endif
}

- (BOOL)stopMallocLogging:(BOOL)mallocLogOff vmLogging:(BOOL)vmLogOff {
    if ([self isLoggingOn] == NO) {
        return YES;
    }
    
    sgi_memory_allocate_logging_enabled = false;

    if (mallocLogOff) {
        malloc_logger = nullptr;
    }

    if (vmLogOff) {
        __syscall_logger = nullptr;
    }

    return YES;
}

@end
