//
//  SGIAPMUtility.h
//  BaseKeyboard
//
//  Created by kingsword on 2020/3/9.
//  Copyright © 2020 Sogou.Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SGIAPMUtility : NSObject

+ (double)currentTime;

+ (NSUInteger)currentThreadCount;

+ (float)getCurrentCPUUsage;

@end

NS_ASSUME_NONNULL_END
