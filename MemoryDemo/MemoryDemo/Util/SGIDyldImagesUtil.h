//
//  SGIDyldImagesUtil.h
//  SGIDyldImagesUtil
//
//  Created by mademao on 2020/4/17.
//  Copyright © 2020 Sogou. All rights reserved.
//

#import <Foundation/Foundation.h>

#import <mach/vm_types.h>
#import <dlfcn.h>

#pragma mark - sgi_dyld_image_item

typedef struct _sgi_dyld_image_item_ {
    const char *name;           //image 名称
    const char *path;           //image 路径
    const char *uuid;           //image uuid
    uint64_t headerAddr;        //运行时header地址
    uint64_t imageBeginAddr;    //运行时image起始地址，理论上与headerAddr相同
    uint64_t imageEndAddr;      //运行时image结束地址，值等于 imageBeginAddr + imageVMSize
    uint64_t imageVMAddr;       //image真实起始地址，根据不同架构有不同值。imageVMAddr + imageSlide = headerAddr
    uint64_t imageVMSize;       //image在内存中占用大小
    uint64_t imageSlide;        //ASLR为image提供的偏移量
    uint64_t linkeditBase;      //linkeditBase地址，常规上是该镜像在虚拟内存中的起始地址，但系统库该值与起始地址不一致
    uint64_t symtabAddr;        //LC_SYMTAB起始地址
} sgi_dyld_image_item;

#pragma mark - sgi_sys_dyld_image_info

typedef struct _sgi_sys_dyld_image_info_ {
    vm_address_t addr_begin;
    vm_address_t addr_end;
    struct _sgi_sys_dyld_image_info_ *prev;
} sgi_sys_dyld_image_info;

#pragma mark - sgi_dyld_image_info

typedef struct _sgi_dyld_image_info_ {
    sgi_dyld_image_item *allImageInfo;
    uint32_t imageInfoCount;
    
    vm_address_t images_begin;
    vm_address_t images_end;
    sgi_sys_dyld_image_info *sys_dyld_image_info;
} sgi_dyld_image_info;


#pragma mark - C method

extern sgi_dyld_image_info * sgi_current_dyld_image_info;

extern char *sgi_current_app_uuid;

void sgi_dyld_load_current_dyld_image_info();

void sgi_dyld_clear_current_dyld_image_info();

bool sgi_dyld_save_dyld_image_info(sgi_dyld_image_info *dyld_image_info, const char *filePath);

sgi_dyld_image_info * sgi_dyld_load_dyld_image_info(const char *filePath);

void sgi_dyld_print_info(sgi_dyld_image_info *dyld_image_info);

bool sgi_dyld_check_in_sys_libraries(sgi_dyld_image_info *dyld_image_info, vm_address_t address);

bool sgi_dyld_check_in_all_Libraries(sgi_dyld_image_info *dyld_image_info, vm_address_t address);

bool sgi_dyld_get_DLInfo(sgi_dyld_image_info *dyld_image_info, vm_address_t addr, Dl_info *const info);

bool sgi_dyld_get_addr_offset(sgi_dyld_image_info *dyld_image_info, vm_address_t addr, vm_address_t *addrOffset, NSString **uuid);
