//
//  SGIDyldImagesUtil.m
//  SGIDyldImagesUtil
//
//  Created by mademao on 2020/4/17.
//  Copyright © 2020 Sogou. All rights reserved.
//

#import "SGIDyldImagesUtil.h"
#import <mach-o/dyld.h>
#import <mach-o/nlist.h>

#ifdef __LP64__
typedef struct mach_header_64 mach_header_t;
typedef struct segment_command_64 segment_command_t;
typedef struct section_64 section_t;
#else
typedef struct mach_header mach_header_t;
typedef struct segment_command segment_command_t;
typedef struct section section_t;
#endif

#if defined(__LP64__)
#define SGI_TRACE_FMT "%-4d%-31s 0x%016lx %s + %lu"
#define SGI_POINTER_FMT "0x%016lx"
#define SGI_POINTER_SHORT_FMT "0x%lx"
#define SGI_NLIST struct nlist_64
#else
#define SGI_TRACE_FMT "%-4d%-31s 0x%08lx %s + %lu"
#define SGI_POINTER_FMT "0x%08lx"
#define SGI_POINTER_SHORT_FMT "0x%lx"
#define SGI_NLIST struct nlist
#endif


sgi_dyld_image_info * sgi_current_dyld_image_info = NULL;
char *sgi_current_app_uuid = NULL;

NSString *sgi_appBundleName();

#pragma mark - sgi_dyld_image_item

sgi_dyld_image_item sgi_dyld_image_item_init(const char *name,
                                             const char *path,
                                             const char *uuid,
                                             uint64_t headerAddr,
                                             uint64_t imageBeginAddr,
                                             uint64_t imageEndAddr,
                                             uint64_t imageVMAddr,
                                             uint64_t imageVMSize,
                                             uint64_t imageSlide,
                                             uint64_t linkeditBase,
                                             uint64_t symtabAddr) {
    sgi_dyld_image_item item;
    item.name = name;
    item.path = path;
    item.uuid = uuid;
    item.headerAddr = headerAddr;
    item.imageBeginAddr = imageBeginAddr;
    item.imageEndAddr = imageEndAddr;
    item.imageVMAddr = imageVMAddr;
    item.imageVMSize = imageVMSize;
    item.imageSlide = imageSlide;
    item.linkeditBase = linkeditBase;
    item.symtabAddr = symtabAddr;
    return item;
}

#pragma mark - sgi_sys_dyld_image_info

void sgi_sys_dyld_image_info_insert(sgi_sys_dyld_image_info *&sys_dyld_image_info, vm_address_t addr_begin, vm_address_t addr_end) {
    sgi_sys_dyld_image_info *node = (sgi_sys_dyld_image_info *)malloc(sizeof(sgi_sys_dyld_image_info));
    node->addr_begin = addr_begin;
    node->addr_end = addr_end;
    node->prev = sys_dyld_image_info;
    
    sys_dyld_image_info = node;
}

void sgi_sys_dyld_image_info_clear(sgi_sys_dyld_image_info *&sys_dyld_image_info) {
    while (sys_dyld_image_info != NULL) {
        sgi_sys_dyld_image_info *node = sys_dyld_image_info;
        sys_dyld_image_info = sys_dyld_image_info->prev;
        free(node);
        node = NULL;
    }
}

#pragma mark - sgi_dyld_image_info

sgi_dyld_image_info * sgi_dyld_image_info_create(size_t dyldImageCount) {
    sgi_dyld_image_info *info = (sgi_dyld_image_info *)malloc(sizeof(sgi_dyld_image_info));
    info->allImageInfo = (sgi_dyld_image_item *)malloc(dyldImageCount * sizeof(sgi_dyld_image_item));
    info->imageInfoCount = 0;
    info->images_begin = 0;
    info->images_end = 0;
    info->sys_dyld_image_info = NULL;
    return info;
}

void sgi_dyld_image_info_clear(sgi_dyld_image_info *&dyld_image_info) {
    if (dyld_image_info) {
        if (dyld_image_info->allImageInfo) {
            free(dyld_image_info->allImageInfo);
        }
        sgi_sys_dyld_image_info_clear(dyld_image_info->sys_dyld_image_info);
        free(dyld_image_info);
        dyld_image_info = NULL;
        sgi_current_app_uuid = NULL;
    }
}

#pragma mark - C private method

static inline int qcompare(const void *a, const void *b) {
    if ((*(sgi_dyld_image_item *)a).imageBeginAddr > (*(sgi_dyld_image_item *)b).imageBeginAddr) {
        return 1;
    } else {
        return -1;
    }
}

uintptr_t sgi_firstCmdAfterHeader(const mach_header_t *header) {
    switch(header->magic) {
        case MH_MAGIC:
        case MH_CIGAM:
            return (uintptr_t)(header + 1);
        case MH_MAGIC_64:
        case MH_CIGAM_64:
            return (uintptr_t)(((struct mach_header_64*)header) + 1);
        default:
            return 0;  // Header is corrupt
    }
}

bool is_sys_image(const char *path) {
#if TARGET_IPHONE_SIMULATOR
            /*
             For simulator, the order of the dyld images is quick radom(for user frameworks)
             a index set is needed for this case, here we just care about the main execution.

             dyld image: 4384235520, /Users/mademao/Library/Dev ~~~/aaaa.app/aaaa   // <---
             dyld image: 4641890304, /Library/Developer/CoreS ~~~ /Frameworks/ImageIO.framework/ImageIO
             dyld image: 4648280064, /Users/mademao/Library/Dev ~~~ /aaaa.app/Frameworks/Manis.framework/Manis // <---
             dyld image: 4771450880, /Users/mademao/Library/Dev ~~~ /aaaa.app/Frameworks/libswiftARKit.dylib
             ...
             */
            bool is_sys_image = true;
            if (strncmp(path, "/Users/", 7) == 0 && (strstr(path, "libswift")) == NULL) {
                is_sys_image = false;
            }
            return is_sys_image;
#else
            /*
             dyld image: 4295786496, /var/containers/Bundle/Appl ~~~ /aaaa.app/aaaa  // <---
             dyld image: 4478582784, /Developer/Library/PrivateFrameworks/libViewDebuggerSupport.dylib
             dyld image: 4483235840, /private/var/containers/Bun ~~~ aaaa.app/Frameworks/Manis.framework/Manis  // <---
             dyld image: 4501782528, /private/var/containers/Bun ~~~ aaaa.app/Frameworks/libswiftMapKit.dylib
             dyld image: 6628442112, /usr/lib/libobjc.A.dylib
             ...
             */
            bool is_sys_image = true;
            if ((strncmp(path, "/var/", 5) == 0)) {
                is_sys_image = false;
            } else if ((strncmp(path, "/private/var/", 13) == 0)) {
                if (strstr(path, "libswift") == NULL) {
                    is_sys_image = false;
                }
            }
            return is_sys_image;
#endif
}

// 查找 address 在哪个 image 内（二分 log n）
uint32_t getImageInfoIndexByAddress(sgi_dyld_image_info *dyld_image_info, const uintptr_t address) {
    if (dyld_image_info == NULL ||
        dyld_image_info->imageInfoCount == 0) {
        return UINT_MAX;
    }

    uint32_t start = 0;
    uint32_t end = dyld_image_info->imageInfoCount - 1; // bug: 多线程下 imageInfoLen = 0  uint32 的 0 - 1 = 0xFFFFFFFF
    uint32_t mid = 0;
    while (start <= end) {
        mid = (start + end) >> 1;
        if (mid >= dyld_image_info->imageInfoCount) { // fix bug: mid 超范围
            return UINT_MAX;
        }
        if (address < dyld_image_info->allImageInfo[mid].imageBeginAddr) {
            end = mid - 1;
        } else if (address > dyld_image_info->allImageInfo[mid].imageEndAddr) {
            start = mid + 1;
        } else {
            return mid;
        }
    }
    return UINT_MAX;
}


#pragma mark - C public method

void sgi_dyld_load_current_dyld_image_info() {
    if (sgi_current_dyld_image_info != NULL) {
        return;
    }
    
    uint32_t count = _dyld_image_count();
    sgi_current_dyld_image_info = sgi_dyld_image_info_create(count);
    
    for (uint32_t i = 0; i < count; i++) {
        const mach_header_t *header = (const mach_header_t *)_dyld_get_image_header(i);
        const char *path = _dyld_get_image_name(i);
        const char *name = "";
        const char *tmp = strrchr(path, '/');
        if (tmp) {
            name = tmp + 1;
        }
        char *uuidstr = (char *)malloc(64 * sizeof(char));
        uintptr_t cmdPtr = sgi_firstCmdAfterHeader(header);
        uint64_t slide = _dyld_get_image_vmaddr_slide(i);
        uint64_t begin = 0;
        uint64_t end = 0;
        uint64_t vmAddr = 0;
        uint64_t vmSize = 0;
        uint64_t linkeditBase = 0;
        uint64_t symtabAddr = 0;
        bool isFindText = false;
        bool isFindLink = false;
        bool isFindSymtab = false;
        bool isFindUuid = false;
        
        for (unsigned int i = 0; i < header->ncmds; i++) {
            const load_command *loadCmd = (const load_command *)cmdPtr;
            if (loadCmd->cmd == LC_SEGMENT) {
                const struct segment_command *segment = (const struct segment_command *)cmdPtr;
                if (!isFindText && strcmp(segment->segname, SEG_TEXT) == 0) {
                    isFindText = true;
                    vmAddr = (uint64_t)segment->vmaddr;
                    vmSize = (uint64_t)segment->vmsize;
                    vmSize = vmSize == 0 ? 1 : vmSize;
                    begin = vmAddr + slide;
                    end = begin + vmSize - 1;
                }
                
                if (!isFindLink && strcmp(segment->segname, SEG_LINKEDIT) == 0) {
                    isFindLink = true;
                    linkeditBase = (uint64_t)(segment->vmaddr - segment->fileoff + slide);
                }
            } else if (loadCmd->cmd == LC_SEGMENT_64) {
                const struct segment_command_64 *segment64 = (const struct segment_command_64 *)cmdPtr;
                if (!isFindText && strcmp(segment64->segname, SEG_TEXT) == 0) {
                    isFindText = true;
                    vmAddr = (uint64_t)segment64->vmaddr;
                    vmSize = (uint64_t)segment64->vmsize;
                    vmSize = vmSize == 0 ? 1 : vmSize;
                    begin = vmAddr + slide;
                    end = begin + vmSize - 1;
                }
                
                if (!isFindLink && strcmp(segment64->segname, SEG_LINKEDIT) == 0) {
                    isFindLink = true;
                    linkeditBase = (uint64_t)(segment64->vmaddr - segment64->fileoff + slide);
                }
            }
            
            if (!isFindSymtab && loadCmd->cmd == LC_SYMTAB) {
                isFindSymtab = true;
                symtabAddr = (uint64_t)loadCmd;
            }
            
            if (!isFindUuid && loadCmd->cmd == LC_UUID) {
                if (loadCmd->cmdsize == sizeof(struct uuid_command)) {
                    isFindUuid = true;
                    const struct uuid_command *uuid = (const struct uuid_command *)cmdPtr;
                    for (int i = 0; i < 16; i++) {
                        sprintf(&uuidstr[2 * i], "%02x", uuid->uuid[i]);
                    }
                }
            }
            
            if (isFindText && isFindLink && isFindSymtab && isFindUuid) {
                break;
            }
            
            cmdPtr += loadCmd->cmdsize;
        }
        
        NSString * pathString = [NSString stringWithUTF8String:path];
        if (sgi_current_app_uuid == NULL && [pathString containsString:sgi_appBundleName()]) {
            sgi_current_app_uuid = uuidstr;
        }
        
        sgi_dyld_image_item item = sgi_dyld_image_item_init(name, path, uuidstr, (uint64_t)header, begin, end, vmAddr, vmSize, slide, linkeditBase, symtabAddr);

        sgi_current_dyld_image_info->allImageInfo[i] = item;
        
        sgi_current_dyld_image_info->imageInfoCount++;
    }
    
    qsort(sgi_current_dyld_image_info->allImageInfo, count, sizeof(sgi_dyld_image_item), qcompare);
    
    if (count > 0) {
        sgi_current_dyld_image_info->images_begin = sgi_current_dyld_image_info->allImageInfo[0].imageBeginAddr;
        sgi_current_dyld_image_info->images_end = sgi_current_dyld_image_info->allImageInfo[count - 1].imageEndAddr;
    }
    
    bool lastImageIsSys = false;
    for (int i = 0; i < count; i++) {
        bool is_sys = is_sys_image(sgi_current_dyld_image_info->allImageInfo[i].path);
        if (is_sys) {
            if (lastImageIsSys) {
                sgi_current_dyld_image_info->sys_dyld_image_info->addr_end = sgi_current_dyld_image_info->allImageInfo[i].imageEndAddr;
            } else {
                sgi_sys_dyld_image_info_insert(sgi_current_dyld_image_info->sys_dyld_image_info, sgi_current_dyld_image_info->allImageInfo[i].imageBeginAddr, sgi_current_dyld_image_info->allImageInfo[i].imageEndAddr);
            }
        }
        lastImageIsSys = is_sys;
    }
}

void sgi_dyld_clear_current_dyld_image_info() {
    if (sgi_current_dyld_image_info) {
        sgi_dyld_image_info_clear(sgi_current_dyld_image_info);
    }
}

bool sgi_dyld_save_dyld_image_info(sgi_dyld_image_info *dyld_image_info, const char *filePath)
{
    if (dyld_image_info == NULL) {
        return false;
    }
    
    NSString *nsFilePath = [NSString stringWithUTF8String:filePath];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager createFileAtPath:nsFilePath contents:nil attributes:nil] == NO) {
        NSString *nsPath = [nsFilePath stringByDeletingLastPathComponent];
        if ([nsPath length] > 1 && ![fileManager createDirectoryAtPath:nsPath withIntermediateDirectories:YES attributes:nil error:nil]) {
            return false;
        }
        
        if (![fileManager createFileAtPath:nsFilePath contents:nil attributes:nil]) {
            return false;
        }
    }
    
    NSMutableDictionary *rootDict = [NSMutableDictionary dictionary];
    [rootDict setObject:@(dyld_image_info->images_begin) forKey:@"images_begin"];
    [rootDict setObject:@(dyld_image_info->images_end) forKey:@"images_end"];
    [rootDict setObject:@(dyld_image_info->imageInfoCount) forKey:@"imageInfoCount"];
    
    NSMutableArray *imageArray = [NSMutableArray arrayWithCapacity:dyld_image_info->imageInfoCount];
    for (int i = 0; i < dyld_image_info->imageInfoCount; i++) {
        NSDictionary *itemDict = @{
            @"path" : [NSString stringWithUTF8String:sgi_current_dyld_image_info->allImageInfo[i].path],
            @"uuid" : [NSString stringWithUTF8String:sgi_current_dyld_image_info->allImageInfo[i].uuid],
            @"vm_addr" : @(sgi_current_dyld_image_info->allImageInfo[i].imageVMAddr),
            @"vm_size" : @(sgi_current_dyld_image_info->allImageInfo[i].imageVMSize),
            @"slide" : @(sgi_current_dyld_image_info->allImageInfo[i].imageSlide),
            @"linkedit_base" : @(sgi_current_dyld_image_info->allImageInfo[i].linkeditBase),
            @"symtabl_addr" : @(sgi_current_dyld_image_info->allImageInfo[i].symtabAddr)
        };
        [imageArray addObject:itemDict];
    }
    [rootDict setObject:imageArray forKey:@"allImageInfo"];
    
    NSMutableArray *sysImageArray = [NSMutableArray array];
    sgi_sys_dyld_image_info *node = dyld_image_info->sys_dyld_image_info;
    while (node) {
        NSDictionary *sysImageDict = @{
            @"begin" : @(node->addr_begin),
            @"end" : @(node->addr_end)
        };
        [sysImageArray addObject:sysImageDict];
        node = node->prev;
    }
    [rootDict setObject:sysImageArray forKey:@"sys_dyld_image_info"];
    
    NSData *data = [NSJSONSerialization dataWithJSONObject:rootDict options:NSJSONWritingFragmentsAllowed error:nil];
    return [data writeToFile:nsFilePath atomically:YES];
}

sgi_dyld_image_info * sgi_dyld_load_dyld_image_info(const char *filePath)
{
    NSString *nsFilePath = [NSString stringWithUTF8String:filePath];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:nsFilePath] == NO) {
        return NULL;
    }
    
    NSData *jsonData = [NSData dataWithContentsOfFile:nsFilePath];
    NSDictionary *jsonDict = [NSJSONSerialization JSONObjectWithData:jsonData options:NSJSONReadingAllowFragments error:nil];
    if (jsonDict == nil) {
        return NULL;
    }
    
    uint32_t imageInfoCount = 0;
    if ([[jsonDict objectForKey:@"imageInfoCount"] isKindOfClass:[NSNumber class]]) {
        imageInfoCount = (uint32_t)[[jsonDict objectForKey:@"imageInfoCount"] integerValue];
    } else {
        return NULL;
    }
    
    sgi_dyld_image_info *dyld_image_info = sgi_current_dyld_image_info = sgi_dyld_image_info_create(imageInfoCount);
    dyld_image_info->imageInfoCount = imageInfoCount;
    
    if ([[jsonDict objectForKey:@"images_begin"] isKindOfClass:[NSNumber class]] &&
        [[jsonDict objectForKey:@"images_end"] isKindOfClass:[NSNumber class]]) {
        dyld_image_info->images_begin = (vm_address_t)[[jsonDict objectForKey:@"images_begin"] integerValue];
        dyld_image_info->images_end = (vm_address_t)[[jsonDict objectForKey:@"images_end"] integerValue];
    } else {
        sgi_dyld_image_info_clear(dyld_image_info);
        return NULL;
    }
    
    if ([[jsonDict objectForKey:@"allImageInfo"] isKindOfClass:[NSArray class]]) {
        NSArray *imageInfoArray = [jsonDict objectForKey:@"allImageInfo"];
        if (imageInfoArray.count > dyld_image_info->imageInfoCount) {
            sgi_dyld_image_info_clear(dyld_image_info);
            return NULL;
        }
        
        for (int i = 0; i < imageInfoArray.count; i++) {
            NSDictionary *imageInfoDict = [imageInfoArray objectAtIndex:i];
            if ([imageInfoDict isKindOfClass:[NSDictionary class]] == NO) {
                sgi_dyld_image_info_clear(dyld_image_info);
                return NULL;
            }
            
            NSString *path = nil;
            if ([[imageInfoDict objectForKey:@"path"] isKindOfClass:[NSString class]]) {
                path = [imageInfoDict objectForKey:@"path"];
            } else {
                sgi_dyld_image_info_clear(dyld_image_info);
                return NULL;
            }
            
            NSString *uuid = nil;
            if ([[imageInfoDict objectForKey:@"uuid"] isKindOfClass:[NSString class]]) {
                uuid = [imageInfoDict objectForKey:@"uuid"];
            } else {
                sgi_dyld_image_info_clear(dyld_image_info);
                return NULL;
            }
            
            uint64_t vm_addr = 0;
            if ([[imageInfoDict objectForKey:@"vm_addr"] isKindOfClass:[NSNumber class]]) {
                vm_addr = (uint64_t)[[imageInfoDict objectForKey:@"vm_addr"] integerValue];
            } else {
                sgi_dyld_image_info_clear(dyld_image_info);
                return NULL;
            }
            
            uint64_t vm_size = 0;
            if ([[imageInfoDict objectForKey:@"vm_size"] isKindOfClass:[NSNumber class]]) {
                vm_size = (uint64_t)[[imageInfoDict objectForKey:@"vm_size"] integerValue];
                vm_size = vm_size == 0 ? 1 : vm_size;
            } else {
                sgi_dyld_image_info_clear(dyld_image_info);
                return NULL;
            }
            
            uint64_t slide = 0;
            if ([[imageInfoDict objectForKey:@"slide"] isKindOfClass:[NSNumber class]]) {
                slide = (uint64_t)[[imageInfoDict objectForKey:@"slide"] integerValue];
            } else {
                sgi_dyld_image_info_clear(dyld_image_info);
                return NULL;
            }
            
            uint64_t linkedit_base = 0;
            if ([[imageInfoDict objectForKey:@"linkedit_base"] isKindOfClass:[NSNumber class]]) {
                linkedit_base = (uint64_t)[[imageInfoDict objectForKey:@"linkedit_base"] integerValue];
            } else {
                sgi_dyld_image_info_clear(dyld_image_info);
                return NULL;
            }
            
            uint64_t symtabl_addr = 0;
            if ([[imageInfoDict objectForKey:@"symtabl_addr"] isKindOfClass:[NSNumber class]]) {
                symtabl_addr = (uint64_t)[[imageInfoDict objectForKey:@"symtabl_addr"] integerValue];
            } else {
                sgi_dyld_image_info_clear(dyld_image_info);
                return NULL;
            }
            
            NSString *name = [path lastPathComponent];
            if (name.length == 0) {
                sgi_dyld_image_info_clear(dyld_image_info);
                return NULL;
            }
            
            sgi_dyld_image_item item = sgi_dyld_image_item_init(name.UTF8String, path.UTF8String, uuid.UTF8String, (uint64_t)(vm_addr + slide), (uint64_t)(vm_addr + slide), (uint64_t)(vm_addr + slide + vm_size - 1), vm_addr, vm_size, slide, linkedit_base, symtabl_addr);
            
            dyld_image_info->allImageInfo[i] = item;
        }
        
    } else {
        sgi_dyld_image_info_clear(dyld_image_info);
        return NULL;
    }
    
    sgi_sys_dyld_image_info *sys_dyld_image_info = NULL;
    if ([[jsonDict objectForKey:@"sys_dyld_image_info"] isKindOfClass:[NSArray class]]) {
        NSArray *sysImageInfoArray = [jsonDict objectForKey:@"sys_dyld_image_info"];
        
        for (NSInteger i = sysImageInfoArray.count - 1; i >= 0; i--) {
            NSDictionary *sysImageInfoDict = [sysImageInfoArray objectAtIndex:i];
            if ([sysImageInfoDict isKindOfClass:[NSDictionary class]] == NO) {
                sgi_dyld_image_info_clear(dyld_image_info);
                return NULL;
            }
            
            vm_address_t begin = 0;
            if ([[sysImageInfoDict objectForKey:@"begin"] isKindOfClass:[NSNumber class]]) {
                begin = (vm_address_t)[[sysImageInfoDict objectForKey:@"begin"] integerValue];
            } else {
                sgi_dyld_image_info_clear(dyld_image_info);
                return NULL;
            }
            
            vm_address_t end = 0;
            if ([[sysImageInfoDict objectForKey:@"end"] isKindOfClass:[NSNumber class]]) {
                end = (vm_address_t)[[sysImageInfoDict objectForKey:@"end"] integerValue];
            } else {
                sgi_dyld_image_info_clear(dyld_image_info);
                return NULL;
            }
            
            sgi_sys_dyld_image_info_insert(sys_dyld_image_info, begin, end);
        }
        
    } else {
        sgi_dyld_image_info_clear(dyld_image_info);
        return NULL;
    }
    dyld_image_info->sys_dyld_image_info = sys_dyld_image_info;
    
    return dyld_image_info;
}

void sgi_dyld_print_info(sgi_dyld_image_info *dyld_image_info)
{
#if DEBUG
    if (dyld_image_info) {
        for (int i = 0; i < dyld_image_info->imageInfoCount; i++) {
            printf("0x%llx 0x%llx %s %s\n", dyld_image_info->allImageInfo[i].imageBeginAddr, dyld_image_info->allImageInfo[i].imageEndAddr, dyld_image_info->allImageInfo[i].uuid, dyld_image_info->allImageInfo[i].name);
        }
        printf("images_begin:0x%llx images_end:0x%llx\n", (uint64_t)dyld_image_info->images_begin, (uint64_t)dyld_image_info->images_end);
        sgi_sys_dyld_image_info *node = dyld_image_info->sys_dyld_image_info;
        while (node) {
            printf("sys_dyld:0x%llx 0x%llx\n", (uint64_t)node->addr_begin, (uint64_t)node->addr_end);
            node = node->prev;
        }
    } else {
        printf("not exist\n");
    }
#endif
}

bool sgi_dyld_check_in_sys_libraries(sgi_dyld_image_info *dyld_image_info, vm_address_t address) {
    if (dyld_image_info == NULL) {
        return false;
    }
    
    sgi_sys_dyld_image_info *node = dyld_image_info->sys_dyld_image_info;
    bool isIn = false;
    while (node) {
        if (address >= node->addr_begin &&
            address <= node->addr_end) {
            isIn = true;
            break;
        }
        node = node->prev;
    }
    return isIn;
}

bool sgi_dyld_check_in_all_Libraries(sgi_dyld_image_info *dyld_image_info, vm_address_t address) {
    if (dyld_image_info == NULL) {
        return false;
    }
    return (address >= dyld_image_info->images_begin && address <= dyld_image_info->images_end);
}

bool sgi_dyld_get_DLInfo(sgi_dyld_image_info *dyld_image_info, vm_address_t addr, Dl_info *const info) {
    const uint32_t index = getImageInfoIndexByAddress(dyld_image_info, addr);
    if (index == UINT_MAX) {
        info->dli_saddr = (void *)addr;
        return false;
    }

    const uintptr_t imageSlide = dyld_image_info->allImageInfo[index].imageSlide;

    const SGI_NLIST *bestMatch = NULL;
    uint64_t stringTable = 0;
    const uintptr_t addressWithSlide = addr - imageSlide; // ASLR 随机地址偏移
    const uint64_t linkeditBase = dyld_image_info->allImageInfo[index].linkeditBase;

    uintptr_t bestDistance = ULONG_MAX;
    const struct symtab_command *symtabCmd = (struct symtab_command *)dyld_image_info->allImageInfo[index].symtabAddr;
    const SGI_NLIST *symbolTable = (SGI_NLIST *)(linkeditBase + symtabCmd->symoff);
    stringTable = linkeditBase + symtabCmd->stroff;

    // optimize: iSym 循环能去到百万次，待优化
    // 搜索离 addressWithSlide 最近的符号地址
    for (uint32_t iSym = 0; iSym < symtabCmd->nsyms; iSym++) {
        // n_value == 0 表示这个符号是 extern 的，外部的符号
        if (symbolTable[iSym].n_value != 0) {
            uintptr_t symbolBase = symbolTable[iSym].n_value;
            uintptr_t currentDistance = addressWithSlide - symbolBase;
            if ((addressWithSlide >= symbolBase) && (currentDistance <= bestDistance)) {
                bestMatch = symbolTable + iSym;
                bestDistance = currentDistance;
            }
        }
    }

    if (bestMatch != NULL) {
        const mach_header_t *header = (mach_header_t *)dyld_image_info->allImageInfo[index].headerAddr;
        info->dli_fname = dyld_image_info->allImageInfo[index].name;
        info->dli_fbase = (void *)header;
        info->dli_sname = nullptr;
        
        if (bestMatch != NULL) {
            info->dli_saddr = (void *)(bestMatch->n_value + imageSlide);
            info->dli_sname = (char *)((intptr_t)stringTable + (intptr_t)bestMatch->n_un.n_strx);

            if (*(info->dli_sname) == '_') {
                info->dli_sname++;
            } else if (*(info->dli_sname) == '<') {
                // 简单处理 <redacted> 符号，外部获取到时，使用 dli_addr 展示。
                info->dli_sname = NULL;
            }

            // n_type == 3 所有符号被删去
            if (info->dli_saddr == info->dli_fbase && bestMatch->n_type == 3) {
                info->dli_sname = nullptr;
            }
        } else {
            info->dli_saddr = (void *)addr;
        }
    }

    return true;
}

bool sgi_dyld_get_addr_offset(sgi_dyld_image_info *dyld_image_info, vm_address_t addr, vm_address_t *addrOffset, NSString **uuid) {
    const uint32_t index = getImageInfoIndexByAddress(dyld_image_info, addr);
    if (index == UINT_MAX) {
        return false;
    }
    
    if (addrOffset) {
        *addrOffset = addr - dyld_image_info->allImageInfo[index].headerAddr;
    }
    
    if (uuid) {
        *uuid = [NSString stringWithCString:dyld_image_info->allImageInfo[index].uuid encoding:NSUTF8StringEncoding];
    }
    return true;
}

#pragma mark - private method
NSString *sgi_appBundleName() {
    NSString *bundleName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"];
    if (!bundleName) {
        return @"";
    }
    if ([NSBundle.mainBundle.infoDictionary objectForKey:@"NSExtension"]) {
        return [NSString stringWithFormat:@"/%@.appex/", bundleName];
    }
    return [NSString stringWithFormat:@"/%@.app/", bundleName];
}
