#pragma once
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, SubPopChineseTextMode) {
    SubPopChineseTextKeep = 0,
    SubPopChineseTextSimplified = 1,
    SubPopChineseTextTraditional = 2,
};

NS_ASSUME_NONNULL_BEGIN

// Converts text only. Callers retain the original text and all subtitle timing.
// Uses the bundled, offline OpenCC standard s2t/t2s dictionaries. Failure never
// returns a partial string or silently changes the requested conversion mode.
FOUNDATION_EXPORT NSString * _Nullable SubPopChineseConvert(
    NSString *text, SubPopChineseTextMode mode, NSError * _Nullable * _Nullable error);

NS_ASSUME_NONNULL_END
