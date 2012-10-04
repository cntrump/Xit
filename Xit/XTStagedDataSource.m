//
//  XTStagedDataSource.m
//  Xit
//
//  Created by German Laullon on 10/08/11.
//

#import "XTStagedDataSource.h"
#import "XTModDateTracker.h"
#import "XTRepository+Parsing.h"
#import "XTFileIndexInfo.h"

@implementation XTStagedDataSource

- (BOOL)shouldReloadForPaths:(NSArray *)paths {
    return [indexTracker hasDateChanged];
}

- (void)reload {
    [repo executeOffMainThread:^{
        [items removeAllObjects];

        [repo readStagedFilesWithBlock:^(NSString *name, NSString *status) {
            XTFileIndexInfo *fileInfo = [[XTFileIndexInfo alloc] initWithName:name andStatus:status];
            [items addObject:fileInfo];
        }];
        [table reloadData];
    }];
}

@end
