//
//  SGIAPMCommonDef.h
//  BaseKeyboard
//
//  Created by kingsword on 2020/3/4.
//  Copyright © 2020 Sogou.Inc. All rights reserved.
//

#ifndef SGIAPMCommonDef_h
#define SGIAPMCommonDef_h

#import "SGIAPMUtility.h"

#ifdef SOGOU_TEST
#define SGIAPMLog(FORMAT, ...) \
{\
NSString *log = [[NSString alloc] initWithFormat:@"---- [DEBUG][APM]%@", [NSString stringWithFormat:FORMAT, ##__VA_ARGS__, nil]]; \
NSLog(@"%@", log);\
}

#import <malloc/malloc.h>
#define SGIAPMMallocLog(FORMAT, ...) malloc_printf(FORMAT, ##__VA_ARGS__);
#else
#define SGIAPMLog(FORMAT, ...)
#define SGIAPMMallocLog(FORMAT, ...)
#endif

#endif /* SGIAPMCommonDef_h */
