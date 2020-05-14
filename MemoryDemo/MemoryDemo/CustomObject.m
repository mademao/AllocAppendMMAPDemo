//
//  CustomObject.m
//  MemoryDemo
//
//  Created by mademao on 2020/5/14.
//  Copyright © 2020 Sogou. All rights reserved.
//

#import "CustomObject.h"
#import "sgi_file_utils.h"
#import <sys/mman.h>

@implementation CustomObject

+ (void)testMmap
{
    NSString *dirPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
    dirPath = [dirPath stringByAppendingPathComponent:@"memory/testmmap"];
    [[NSFileManager defaultManager] createFileAtPath:dirPath contents:nil attributes:nil];
    FILE *fp = fopen(dirPath.UTF8String, "rb+");
    if (fp == NULL) {
        NSLog(@"error");
        return;
    }

    size_t size = 10 * 1024.0 * 1024.0;
    if (size <= 0) {
        int ret = ftruncate(fp, size);
//        if(0 != ret){
//            NSLog(@"error");
//            return;
//        }
    }

    void *ptr = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_FILE | MAP_SHARED, fileno(fp), 0);
    if (ptr == MAP_FAILED) {
        NSLog(@"error");
        return;
    }
}

@end
