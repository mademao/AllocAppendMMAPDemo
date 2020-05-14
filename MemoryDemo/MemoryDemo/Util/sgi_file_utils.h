//
// sgi_file_utils.h
// SGIAPM
//
// Created by mademao on 2020/4/21.
// Copyright © 2020 Sogou. All rights reserved.
//


#ifndef sgi_file_utils_h
#define sgi_file_utils_h

#import <stdbool.h>
#include <stdio.h>

#ifdef __cplusplus
extern "C" {
#endif

bool sgi_is_file_exist(const char *filepath);

bool sgi_create_file(const char *filepath);

size_t sgi_get_file_size(int fd);

#ifdef __cplusplus
}
#endif

#endif /* sgi_file_utils_h */
