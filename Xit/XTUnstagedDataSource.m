//
//  XTIndexDataSource.m
//  Xit
//
//  Created by German Laullon on 09/08/11.
//

#import "XTUnstagedDataSource.h"
#import "XTRepository.h"
#import "XTFileIndexInfo.h"

@implementation XTUnstagedDataSource

- (void)reload {
    [items removeAllObjects];
    if (repo == nil)
        return;

    [repo executeOffMainThread:^{
        NSData *output = [repo executeGitWithArgs:[NSArray arrayWithObjects:@"diff-files", nil] error:nil];
        NSString *filesStr = [[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding];
        filesStr = [filesStr stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSArray *files = [filesStr componentsSeparatedByString:@"\n"];
        [files enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL * stop) {
            NSString *file = (NSString *)obj;
            NSArray *info = [file componentsSeparatedByString:@"\t"];
            if (info.count > 1) {
                NSString *name = [info lastObject];
                NSString *status = [[[info objectAtIndex:0] componentsSeparatedByString:@" "] lastObject];
                status = [status substringToIndex:1];
                XTFileIndexInfo *fileInfo = [[XTFileIndexInfo alloc] initWithName:name andStatus:status];
                [items addObject:fileInfo];
            }
        }];

        output = [repo executeGitWithArgs:[NSArray arrayWithObjects:@"ls-files", @"--others", @"--exclude-standard", nil] error:nil];
        filesStr = [[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding];
        filesStr = [filesStr stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        files = [filesStr componentsSeparatedByString:@"\n"];
        [files enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL * stop) {
            NSString *file = (NSString *)obj;
            if (file.length > 0) {
                XTFileIndexInfo *fileInfo = [[XTFileIndexInfo alloc] initWithName:file andStatus:@"?"];
                [items addObject:fileInfo];
            }
        }];
    }];
}

@end
