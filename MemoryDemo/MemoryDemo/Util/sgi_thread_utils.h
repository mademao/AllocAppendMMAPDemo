//
// sgi_thread_utils.h
// SGIAPM
//
// Created by mademao on 2020/4/21.
// Copyright © 2020 Sogou. All rights reserved.
//


#ifndef sgi_thread_utils_h
#define sgi_thread_utils_h

#include <stdbool.h>
#include <stdio.h>


#ifdef __cplusplus
extern "C" {
#endif // __cplusplus


bool sgi_suspend_all_child_threads(void);
bool sgi_resume_all_child_threads(void);


#ifdef __cplusplus
}
#endif // __cplusplus


#endif /* sgi_thread_utils_h */
