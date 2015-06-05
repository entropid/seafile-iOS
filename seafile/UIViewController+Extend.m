//
//  UIViewController+AlertMessage.m
//  seafile
//
//  Created by Wang Wei on 10/11/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <objc/runtime.h>
#import "UIViewController+Extend.h"
#import "Utils.h"
#import "Debug.h"

#define ADD_DYNAMIC_PROPERTY(PROPERTY_TYPE,PROPERTY_NAME,SETTER_NAME) \
@dynamic PROPERTY_NAME ; \
static char kProperty##PROPERTY_NAME; \
- ( PROPERTY_TYPE ) PROPERTY_NAME \
{ \
return ( PROPERTY_TYPE ) objc_getAssociatedObject(self, &(kProperty##PROPERTY_NAME ) ); \
} \
\
- (void) SETTER_NAME :( PROPERTY_TYPE ) PROPERTY_NAME \
{ \
objc_setAssociatedObject(self, &kProperty##PROPERTY_NAME , PROPERTY_NAME , OBJC_ASSOCIATION_RETAIN); \
} \

@implementation UIViewController (Extend)

ADD_DYNAMIC_PROPERTY(void (^)(),handler_ok,setHandler_ok);
ADD_DYNAMIC_PROPERTY(void (^)(),handler_cancel,setHandler_cancel);
ADD_DYNAMIC_PROPERTY(void (^)(NSString *),handler_input,setHandler_input);


- (id)initWithAutoNibName
{
    return [self initWithNibName:(NSStringFromClass ([self class])) bundle:nil];
}

- (id)initWithAutoPlatformNibName
{
    NSString* className = NSStringFromClass ([self class]);
    NSString* plaformSuffix;
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone) {
        plaformSuffix = @"iPhone";
    } else {
        plaformSuffix = @"iPad";
    }
    return [self initWithNibName:[NSString stringWithFormat:@"%@_%@", className, plaformSuffix] bundle:nil];
}

- (id)initWithAutoPlatformLangNibName:(NSString *)lang
{
    NSString* className = NSStringFromClass ([self class]);
    NSString* plaformSuffix;
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone) {
        plaformSuffix = @"iPhone";
    } else {
        plaformSuffix = @"iPad";
    }
    return [self initWithNibName:[NSString stringWithFormat:@"%@_%@_%@", className, plaformSuffix, lang] bundle:nil];
}

- (void)alertWithTitle:(NSString*)title message:(NSString*)message handler:(void (^)())handler;
{
    [Utils alertWithTitle:title message:message handler:handler from:self];
}

- (void)alertWithTitle:(NSString*)title message:(NSString*)message
{
    [self alertWithTitle:title message:message handler:nil];
}

- (void)alertWithTitle:(NSString*)title
{
    [self alertWithTitle:title message:nil];
}

- (void)alertWithTitle:(NSString*)title handler:(void (^)())handler
{
    [self alertWithTitle:title message:nil handler:handler];
}


- (void)alertWithTitle:(NSString *)title message:(NSString*)message yes:(void (^)())yes no:(void (^)())no
{
    [Utils alertWithTitle:title message:message yes:yes no:no from:self];
}

- (void)popupInputView:(NSString *)title placeholder:(NSString *)tip secure:(BOOL)secure handler:(void (^)(NSString *input))handler
{
    [self popupInputView:title placeholder:tip prefilled:NO secure:secure handler:handler];
}

- (void)popupInputView:(NSString *)title placeholder:(NSString *)tip prefilled:(BOOL)prefilled secure:(BOOL)secure handler:(void (^)(NSString *input))handler
{
    [Utils popupInputView:title placeholder:tip prefilled:prefilled secure:secure handler:handler from:self];
}

- (UIBarButtonItem *)getBarItem:(NSString *)imageName action:(SEL)action size:(float)size;
{
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = CGRectMake(0,0,size,size);
    UIImage *img = [UIImage imageNamed:imageName];
    [btn setImage:img forState:UIControlStateNormal];
    btn.showsTouchWhenHighlighted = YES;
    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithCustomView:btn];
    return item;
}

- (UIBarButtonItem *)getBarItemAutoSize:(NSString *)imageName action:(SEL)action
{
    return [self getBarItem:imageName action:action size:22];
}

- (UIBarButtonItem *)getSpaceBarItem:(float)width
{
    UIBarButtonItem *space = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace target:self action:nil];
    space.width = width;
    return space;
}

- (BOOL)isVisible
{
    return [self isViewLoaded] && self.view.window;
}

#pragma mark - UIAlertViewDelegate

- (void)alertView:(UIAlertView *)alertView willDismissWithButtonIndex:(NSInteger)buttonIndex
{
    if (buttonIndex != alertView.cancelButtonIndex) {
        if (self.handler_ok) {
            self.handler_ok();
        } else if (self.handler_input) {
            UITextField *textfiled = [alertView textFieldAtIndex:0];
            NSString *input = textfiled.text;
            self.handler_input(input);
        }
    } else {
        if (self.handler_cancel)
            self.handler_cancel();
    }
}

@end
