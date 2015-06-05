//
//  DownloadingProgressView.m
//  seafile
//
//  Created by Wang Wei on 10/11/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import "DownloadingProgressView.h"
#import "Debug.h"

@interface DownloadingProgressView ()
@property id<SeafPreView> item;
@end

@implementation DownloadingProgressView


- (id)initWithCoder:(NSCoder *)decoder
{
    self = [super initWithCoder:decoder];
    for (UIView *v in self.subviews) {
        v.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin| UIViewAutoresizingFlexibleRightMargin| UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleTopMargin;
    }
    self.autoresizesSubviews = YES;
    self.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    
    self.cancelBt.reversesTitleShadowWhenHighlighted = NO;
    self.cancelBt.tintColor=[UIColor whiteColor];
    
    _cancelBt.titleLabel.text = NSLocalizedString(@"Cancel download", @"Seafile");
    return self;
}

- (void)configureViewWithItem:(id<QLPreviewItem, SeafPreView>)item completeness:(int)percent
{
    if (_item != item) {
        _item = item;
        self.imageView.image = item.icon;
        self.nameLabel.text = item.previewItemTitle;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        _progress.progress = percent * 1.0f/100;
    });
}


@end
