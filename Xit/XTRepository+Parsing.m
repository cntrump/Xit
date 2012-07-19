//
//  XTRepository+Parsing.m
//  Xit
//
//  Created by David Catmull on 7/13/12.
//

#import "XTRepository+Parsing.h"


@implementation XTRepository (Reading)

- (BOOL)readRefsWithLocalBlock:(void (^)(NSString *name, NSString *commit))localBlock
                   remoteBlock:(void (^)(NSString *remoteName, NSString *branchName, NSString *commit))remoteBlock
                      tagBlock:(void (^)(NSString *name, NSString *commit))tagBlock {
    NSError *error = nil;
    NSData *output = [self executeGitWithArgs:[NSArray arrayWithObjects:@"show-ref", @"-d", nil] error:&error];

    if (output != nil) {
        NSString *refs = [[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding];
        NSScanner *scan = [NSScanner scannerWithString:refs];
        NSString *commit;
        NSString *name;

        while ([scan scanUpToString:@" " intoString:&commit]) {
            [scan scanUpToString:@"\n" intoString:&name];
            if ([name hasPrefix:@"refs/heads/"]) {
                localBlock([name lastPathComponent], commit);
            } else if ([name hasPrefix:@"refs/tags/"]) {
                tagBlock([name lastPathComponent], commit);
            } else if ([name hasPrefix:@"refs/remotes/"]) {
                NSString *remoteName = [[name pathComponents] objectAtIndex:2];
                NSString *branchName = [name lastPathComponent];

                remoteBlock(remoteName, branchName, commit);
            }
        }
    }
    return error == nil;
}

- (BOOL)readStagedFilesWithBlock:(void (^)(NSString *, NSString *))block {
    NSError *error = nil;
    NSData *output = [self executeGitWithArgs:[NSArray arrayWithObjects:@"diff-index", @"--cached", [self parentTree], nil] error:&error];

    if ((output == nil) || (error != nil))
        return NO;

    NSString *filesStr = [[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding];
    filesStr = [filesStr stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSArray *files = [filesStr componentsSeparatedByString:@"\n"];

    for (NSString *file in files) {
        NSArray *info = [file componentsSeparatedByString:@"\t"];
        if (info.count > 1) {
            NSString *name = [info lastObject];
            NSString *status = [[[info objectAtIndex:0] componentsSeparatedByString:@" "] lastObject];
            status = [status substringToIndex:1];
            block(name, status);
        }
    }
    return YES;
}

- (BOOL)readStashesWithBlock:(void (^)(NSString *, NSString *))block {
    NSError *error = nil;
    NSData *output = [self executeGitWithArgs:[NSArray arrayWithObjects:@"stash", @"list", @"--pretty=%H %gd %gs", nil] error:&error];

    if (output != nil) {
        NSString *refs = [[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding];
        NSScanner *scanner = [NSScanner scannerWithString:refs];
        NSString *commit, *name;

        while ([scanner scanUpToString:@" " intoString:&commit]) {
            [scanner scanUpToString:@"\n" intoString:&name];
            block(commit, name);
        }
    }
    return error == nil;
}

@end