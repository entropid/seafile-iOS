//
//  SeafAppDelegate.m
//  seafile
//
//  Created by Wei Wang on 7/7/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <Photos/Photos.h>

#import "SeafAppDelegate.h"
#import "SVProgressHUD.h"
#import "AFNetworking.h"
#import "Debug.h"
#import "Utils.h"


@interface SeafAppDelegate () <UITabBarControllerDelegate, UIAlertViewDelegate, PHPhotoLibraryChangeObserver>

@property UIBackgroundTaskIdentifier bgTask;

@property NSInteger moduleIdx;
@property (readonly) SeafDetailViewController *detailVC;
@property (readonly) UINavigationController *disDetailNav;
@property (strong) NSArray *viewControllers;
@property (readwrite) SeafGlobal *global;

@property (strong) void (^handler_ok)();
@property (strong) void (^handler_cancel)();
@property (strong, nonatomic) dispatch_block_t expirationHandler;
@property BOOL background;
@property (strong) NSMutableArray *monitors;
@end

@implementation SeafAppDelegate
@synthesize startVC = _startVC;
@synthesize tabbarController = _tabbarController;

- (BOOL)shouldContinue
{
    for (SeafConnection *conn in SeafGlobal.sharedObject.conns) {
        if (conn.inAutoSync) return true;
    }
    return SeafGlobal.sharedObject.uploadingnum != 0 || SeafGlobal.sharedObject.downloadingnum != 0;
}

- (void)selectAccount:(SeafConnection *)conn;
{
    conn.delegate = self;
    @synchronized(self) {
        if ([[SeafGlobal sharedObject] connection] != conn) {
            [[SeafGlobal sharedObject] setConnection: conn];
            [[self masterNavController:TABBED_SEAFILE] popToRootViewControllerAnimated:NO];
            [[self masterNavController:TABBED_STARRED] popToRootViewControllerAnimated:NO];
            [[self masterNavController:TABBED_SETTINGS] popToRootViewControllerAnimated:NO];
            [[self masterNavController:TABBED_ACTIVITY] popToRootViewControllerAnimated:NO];
            self.fileVC.connection = conn;
            self.starredVC.connection = conn;
            self.settingVC.connection = conn;
            self.actvityVC.connection = conn;
        }
    }
    if (self.deviceToken)
        [conn registerDevice:self.deviceToken];
}

- (BOOL)application:(UIApplication*)application handleOpenURL:(NSURL*)url
{
    if (url != nil && [url isFileURL]) {
        NSURL *to = [NSURL fileURLWithPath:[SeafGlobal.sharedObject.uploadsDir stringByAppendingPathComponent:url.lastPathComponent]];
        Debug("Copy %@, to %@, %@, %@\n", url, to, to.absoluteString, to.path);
        [Utils copyFile:url to:to];
        if (self.window.rootViewController == self.startNav)
            if (![self.startVC selectDefaultAccount])
                return NO;
        ;
        [[self masterNavController:TABBED_SEAFILE] popToRootViewControllerAnimated:NO];
        SeafUploadFile *file = [SeafGlobal.sharedObject.connection getUploadfile:to.path];
        [self.fileVC uploadFile:file];
    }
    return YES;
}

- (void)checkPhotoChanges:(NSNotification *)notification
{
    Debug("Start check photos changes.");
    for (SeafConnection *conn in SeafGlobal.sharedObject.conns) {
        [conn checkPhotoChanges:notification];
    }
}

- (void)delayedInit
{
    NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
    NSString *version = [infoDictionary objectForKey:@"CFBundleVersion"];
    Debug("Current app version is %@\n%@\n", version, infoDictionary);
    [SeafGlobal.sharedObject setObject:version forKey:@"VERSION"];
    [SeafGlobal.sharedObject synchronize];
    [self cycleTheGlobalMailComposer];
    [SeafGlobal.sharedObject startTimer];
    [SeafGlobal.sharedObject clearRepoPasswords];
    [Utils clearAllFiles:SeafGlobal.sharedObject.tempDir];

    for (SeafConnection *conn in SeafGlobal.sharedObject.conns) {
        [conn checkAutoSync];
    }
    [SVProgressHUD setBackgroundColor:[UIColor colorWithRed:250.0/256 green:250.0/256 blue:250.0/256 alpha:1.0]];
    if (ios8)
         [[PHPhotoLibrary sharedPhotoLibrary] registerChangeObserver:self];
    else
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(checkPhotoChanges:) name:ALAssetsLibraryChangedNotification object:SeafGlobal.sharedObject.assetsLibrary];
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    Debug("%@", [[NSBundle mainBundle] infoDictionary]);
    _global = [SeafGlobal sharedObject];
    [_global migrate];
    [self initTabController];

    if (ios7)
        [[UITabBar appearance] setTintColor:[UIColor colorWithRed:238.0f/256 green:136.0f/256 blue:51.0f/255 alpha:1.0]];
    else
        [[UITabBar appearance] setSelectedImageTintColor:[UIColor colorWithRed:238.0f/256 green:136.0f/256 blue:51.0f/255 alpha:1.0]];

    [SeafGlobal.sharedObject loadAccounts];

    _monitors = [[NSMutableArray alloc] init];
    _startNav = (UINavigationController *)self.window.rootViewController;
    _startVC = (StartViewController *)_startNav.topViewController;

    [Utils checkMakeDir:[[SeafGlobal.sharedObject applicationDocumentsDirectory] stringByAppendingPathComponent:OBJECTS_DIR]];
    [Utils checkMakeDir:[[SeafGlobal.sharedObject applicationDocumentsDirectory] stringByAppendingPathComponent:AVATARS_DIR]];
    [Utils checkMakeDir:[[SeafGlobal.sharedObject applicationDocumentsDirectory] stringByAppendingPathComponent:CERTS_DIR]];
    [Utils checkMakeDir:[[SeafGlobal.sharedObject applicationDocumentsDirectory] stringByAppendingPathComponent:BLOCKS_DIR]];
    [Utils checkMakeDir:[[SeafGlobal.sharedObject applicationDocumentsDirectory] stringByAppendingPathComponent:UPLOADS_DIR]];
    [Utils checkMakeDir:[[SeafGlobal.sharedObject applicationDocumentsDirectory] stringByAppendingPathComponent:EDIT_DIR]];
    [Utils checkMakeDir:[[SeafGlobal.sharedObject applicationDocumentsDirectory] stringByAppendingPathComponent:THUMB_DIR]];

    [Utils checkMakeDir:SeafGlobal.sharedObject.tempDir];

    [self.startVC selectDefaultAccount];
    [[AFNetworkReachabilityManager sharedManager] startMonitoring];

    self.bgTask = UIBackgroundTaskInvalid;
    __weak typeof(self) weakSelf = self;
    self.expirationHandler = ^{
        Debug("Expired, Time Remain = %f, restart background task.", [application backgroundTimeRemaining]);
        [weakSelf startBackgroundTask];
    };

    [self performSelector:@selector(delayedInit) withObject:nil afterDelay:2.0];
    return YES;
}

- (void)enterBackground
{
    Debug("Enter background");
    self.background = YES;
    [self startBackgroundTask];
}

- (void)startBackgroundTask
{
    // Start the long-running task.
    Debug("start background task");
    UIApplication* app = [UIApplication sharedApplication];
    if (UIBackgroundTaskInvalid != self.bgTask) {
        [app endBackgroundTask:self.bgTask];
        self.bgTask = UIBackgroundTaskInvalid;
    }
    if (!self.shouldContinue) return;

    self.bgTask = [app beginBackgroundTaskWithExpirationHandler:self.expirationHandler];
}

- (void)applicationWillResignActive:(UIApplication *)application
{
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    [self enterBackground];
    for (id <SeafBackgroundMonitor> monitor in _monitors) {
        [monitor enterBackground];
    }
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    Debug("Seafile will enter foreground");
    // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
    [SeafGlobal.sharedObject loadSettings:[NSUserDefaults standardUserDefaults]];
    [self checkPhotoChanges:nil];
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    self.background = false;
    for (id <SeafBackgroundMonitor> monitor in _monitors) {
        [monitor enterForeground];
    }
}


- (void)applicationWillTerminate:(UIApplication *)application
{
    // Saves changes in the application's managed object context before the application terminates.
    [[SeafGlobal sharedObject] saveContext];
}


- (BOOL)tabBarController:(UITabBarController *)tabBarController shouldSelectViewController:(UIViewController *)viewController
{
    if (IsIpad() && [self.viewControllers indexOfObject:viewController] == TABBED_ACCOUNTS) {
        self.window.rootViewController = _startNav;
        [self.window makeKeyAndVisible];
        return NO;
    }
    return YES;
}

#pragma mark - ViewController
- (void)initTabController
{
    UITabBarController *tabs;
    if (IsIpad()) {
        tabs = [[UIStoryboard storyboardWithName:@"FolderView_iPad" bundle:nil] instantiateViewControllerWithIdentifier:@"TABVC"];
    } else {
        tabs = [[UIStoryboard storyboardWithName:@"FolderView_iPhone" bundle:nil] instantiateViewControllerWithIdentifier:@"TABVC"];
    }
    UIViewController *fileController = [tabs.viewControllers objectAtIndex:TABBED_SEAFILE];
    UIViewController *starredController = [tabs.viewControllers objectAtIndex:TABBED_STARRED];
    UIViewController *settingsController = [tabs.viewControllers objectAtIndex:TABBED_SETTINGS];
    UINavigationController *activityController = [tabs.viewControllers objectAtIndex:TABBED_ACTIVITY];
    UIViewController *accountvc = [tabs.viewControllers objectAtIndex:TABBED_ACCOUNTS];

    fileController.tabBarItem.title = NSLocalizedString(@"Libraries", @"Seafile");
    fileController.tabBarItem.image = [UIImage imageNamed:@"tab-home.png"];
    starredController.tabBarItem.title = NSLocalizedString(@"Starred", @"Seafile");
    starredController.tabBarItem.image = [UIImage imageNamed:@"tab-star.png"];
    settingsController.tabBarItem.title = NSLocalizedString(@"Settings", @"Seafile");
    settingsController.tabBarItem.image = [UIImage imageNamed:@"tab-settings.png"];
    activityController.tabBarItem.title = NSLocalizedString(@"Activity", @"Seafile");
    activityController.tabBarItem.image = [UIImage imageNamed:@"tab-modify.png"];
    accountvc.tabBarItem.title = NSLocalizedString(@"Accounts", @"Seafile");
    accountvc.tabBarItem.image = [UIImage imageNamed:@"tab-account.png"];

    if (IsIpad()) {
        ((UISplitViewController *)fileController).delegate = (id)[[((UISplitViewController *)fileController).viewControllers lastObject] topViewController];
        ((UISplitViewController *)starredController).delegate = (id)[[((UISplitViewController *)starredController).viewControllers lastObject] topViewController];
        ((UISplitViewController *)settingsController).delegate = (id)[[((UISplitViewController *)settingsController).viewControllers lastObject] topViewController];
    }
    self.viewControllers = [NSArray arrayWithArray:tabs.viewControllers];
    _tabbarController = tabs;
    _tabbarController.delegate = self;
    if (ios7)
        _tabbarController.view.backgroundColor = [UIColor colorWithRed:150.0f/255 green:150.0f/255 blue:150.0f/255 alpha:1];
}

- (UITabBarController *)tabbarController
{
    if (!_tabbarController)
        [self initTabController];
    return _tabbarController;
}

- (StartViewController *)startVC
{
    if (!_startVC)
        _startVC = [[StartViewController alloc] init];
    return _startVC;
}

- (UINavigationController *)masterNavController:(int)index
{
    if (!IsIpad())
        return [self.viewControllers objectAtIndex:index];
    else {
        return (index == TABBED_ACTIVITY)? [self.viewControllers objectAtIndex:index] : [[[self.viewControllers objectAtIndex:index] viewControllers] objectAtIndex:0];
    }
}

- (SeafFileViewController *)fileVC
{
    return (SeafFileViewController *)[[self masterNavController:TABBED_SEAFILE] topViewController];
}

- (UIViewController *)detailViewControllerAtIndex:(int)index
{
    if (IsIpad()) {
        return [[[[self.viewControllers objectAtIndex:index] viewControllers] lastObject] topViewController];
    } else {
        if (!_detailVC)
            _detailVC = [[UIStoryboard storyboardWithName:@"FolderView_iPhone" bundle:nil] instantiateViewControllerWithIdentifier:@"DETAILVC"];
        return _detailVC;
    }
}

- (SeafStarredFilesViewController *)starredVC
{
    return (SeafStarredFilesViewController *)[[self masterNavController:TABBED_STARRED] topViewController];
}

- (SeafSettingsViewController *)settingVC
{
    return (SeafSettingsViewController *)[[self masterNavController:TABBED_SETTINGS] topViewController];
}

- (SeafActivityViewController *)actvityVC
{
    return (SeafActivityViewController *)[[self.viewControllers objectAtIndex:TABBED_ACTIVITY] topViewController];
}

- (BOOL)checkNetworkStatus
{
    NSLog(@"network status=%@\n", [[AFNetworkReachabilityManager sharedManager] localizedNetworkReachabilityStatusString]);
    if (![[AFNetworkReachabilityManager sharedManager] isReachable]) {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Network unavailable", @"Seafile")
                                                        message:nil
                                                       delegate:nil
                                              cancelButtonTitle:NSLocalizedString(@"OK", @"Seafile")
                                              otherButtonTitles:nil];
        [alert show];
        return NO;
    }
    return YES;
}

- (void)showDetailView:(UIViewController *) c
{
    UINavigationController *nc = [[UINavigationController alloc] initWithRootViewController:c];
    [nc setModalPresentationStyle:UIModalPresentationFullScreen];
    nc.navigationBar.tintColor = BAR_COLOR;
    [self.window.rootViewController presentViewController:nc animated:YES completion:nil];
}

-(void)cycleTheGlobalMailComposer
{
    // we are cycling the damned GlobalMailComposer... due to horrible iOS issue
    // http://stackoverflow.com/questions/25604552/i-have-real-misunderstanding-with-mfmailcomposeviewcontroller-in-swift-ios8-in/25864182#25864182
    _globalMailComposer = nil;
    
    // Do not try to initialise the Mail Composer if there is not account set up
    if ([MFMailComposeViewController canSendMail]) {
        _globalMailComposer = [[MFMailComposeViewController alloc] init];
    }
}

#pragma - SeafConnectionDelegate
- (void)loginRequired:(SeafConnection *)connection
{
    Debug("Token expired, should login again.");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5), dispatch_get_main_queue(), ^(void){
        self.window.rootViewController = _startNav;
        [self.window makeKeyAndVisible];
        [self.startVC performSelector:@selector(selectAccount:) withObject:connection afterDelay:0.5f];
    });
}

- (void)continueWithInvalidCert:(NSURLProtectionSpace *)protectionSpace yes:(void (^)())yes no:(void (^)())no
{
    NSString *title = [NSString stringWithFormat:NSLocalizedString(@"%@ can't verify the identity of the website \"%@\"", @"Seafile"), APP_NAME, protectionSpace.host];
    NSString *message = NSLocalizedString(@"The certificate from this website is invalid. Would you like to connect to the server anyway?", @"Seafile");

    UIViewController *c = self.window.rootViewController;
    if (self.window.rootViewController.presentedViewController) {
        c = self.window.rootViewController.presentedViewController;
    }
    if (ios8)
        [Utils alertWithTitle:title message:message yes:yes no:no from:c];
    else {
        self.handler_ok = yes;
        self.handler_cancel = no;
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:title message:message delegate:self cancelButtonTitle:NSLocalizedString(@"Cancel", @"Seafile") otherButtonTitles:NSLocalizedString(@"OK", @"Seafile"), nil];
        alert.alertViewStyle = UIAlertViewStyleDefault;
        [alert show];
    }
}

- (BOOL)continueWithInvalidCert:(NSURLProtectionSpace *)protectionSpace
{
    __block BOOL ret = false;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    dispatch_block_t block = ^{
        [self continueWithInvalidCert:protectionSpace yes:^{
            ret = true;
            dispatch_semaphore_signal(semaphore);
        } no:^{
            ret = false;
            dispatch_semaphore_signal(semaphore);
        }];
    };
    block();
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    return ret;
}
#pragma mark - UIAlertViewDelegate
- (void)alertView:(UIAlertView *)alertView willDismissWithButtonIndex:(NSInteger)buttonIndex
{
    if (buttonIndex != alertView.cancelButtonIndex) {
        if (self.handler_ok) {
            self.handler_ok();
        }
    } else {
        if (self.handler_cancel)
            self.handler_cancel();
    }
}

#pragma mark - PHPhotoLibraryChangeObserver
- (void)photoLibraryDidChange:(PHChange *)changeInstance
{
    Debug("Photos library changed.");
    // Call might come on any background queue. Re-dispatch to the main queue to handle it.
    dispatch_async(dispatch_get_main_queue(), ^{
        [self checkPhotoChanges:nil];
    });
}

- (void)addBackgroundMonitor:(id<SeafBackgroundMonitor>)monitor
{
    [_monitors addObject:monitor];
}


@end
