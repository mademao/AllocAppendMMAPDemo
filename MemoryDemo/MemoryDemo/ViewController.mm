//
//  ViewController.m
//  MemoryDemo
//
//  Created by mademao on 2020/5/14.
//  Copyright © 2020 Sogou. All rights reserved.
//

#import "ViewController.h"
#import "SGIAPMAllocMonitor.h"
#import <YYWebImage.h>
#import "sgi_file_utils.h"
#import <sys/mman.h>
#import "CustomObject.h"

@interface ViewController () {
    SGIAPMAllocRecordReader *allocMonitor;
}

@property (nonatomic, strong) YYAnimatedImageView *imageView;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
        
    sgi_dyld_load_current_dyld_image_info();
    
    self.imageView = [[YYAnimatedImageView alloc] initWithFrame:CGRectMake(0, 0, 200, 200)];
    self.imageView.center = self.view.center;
    self.imageView.layer.borderWidth = 1.0;
    [self.view addSubview:self.imageView];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    
    
//    [self testMalloc];
//    [CustomObject testMmap];
    
    [self testVMMalloc];
}

- (void)testMalloc
{
    [SGIAPMAllocMonitor startPlugin];
    
    size_t size = 10 * 1024.0 * 1024.0;
    void *p = malloc(size);
    memset(p, 0, size);
    
    [SGIAPMAllocMonitor stopPlugin];
    
    allocMonitor = [SGIAPMAllocMonitor createRecordReader];
    NSDictionary *reportDict = [allocMonitor generateReport];
    NSLog(@"%@", reportDict);
    
    [self symbolWithDict:reportDict[@"malloc_report"]];
    [self symbolWithDict:reportDict[@"vm_report"]];
    
    
    [SGIAPMAllocMonitor clearAllocMonitorMmapFileIfNeeded];
}

- (void)testMmap
{
    [SGIAPMAllocMonitor startPlugin];
    
    [CustomObject testMmap];
    
    [SGIAPMAllocMonitor stopPlugin];
    
    allocMonitor = [SGIAPMAllocMonitor createRecordReader];
    NSDictionary *reportDict = [allocMonitor generateReport];
    NSLog(@"%@", reportDict);
    
    [self symbolWithDict:reportDict[@"malloc_report"]];
    [self symbolWithDict:reportDict[@"vm_report"]];
    
    
    [SGIAPMAllocMonitor clearAllocMonitorMmapFileIfNeeded];
}

- (void)testVMMalloc
{

    [SGIAPMAllocMonitor startPlugin];
    
    [self.imageView yy_setImageWithURL:[NSURL URLWithString:@"https://img95.699pic.com/photo/50055/5642.jpg_wh860.jpg"] placeholder:nil options:kNilOptions completion:^(UIImage * _Nullable image, NSURL * _Nonnull url, YYWebImageFromType from, YYWebImageStage stage, NSError * _Nullable error) {
        
        [SGIAPMAllocMonitor stopPlugin];
        
        allocMonitor = [SGIAPMAllocMonitor createRecordReader];
        NSDictionary *reportDict = [allocMonitor generateReport];
        NSLog(@"%@", reportDict);
        
        [self symbolWithDict:reportDict[@"malloc_report"]];
        [self symbolWithDict:reportDict[@"vm_report"]];
        
        
        [SGIAPMAllocMonitor clearAllocMonitorMmapFileIfNeeded];
        
    }];
}




- (void)symbolWithDict:(NSDictionary *)dict
{
    NSArray *categories = [dict objectForKey:@"categories"];
    for (NSDictionary *categoryDict in categories) {
        NSArray *stacks = [categoryDict objectForKey:@"stacks"];
        for (NSDictionary *stackDict in stacks) {
            NSNumber *stack_id_num = [stackDict objectForKey:@"stack_id"];
            if (stack_id_num) {
                NSLog(@"%@----------------\n%@", stack_id_num, [allocMonitor generateStackFrameReportWithStackID:stack_id_num]);
            }
        }
    }
}

@end
