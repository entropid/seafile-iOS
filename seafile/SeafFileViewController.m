//
//  SeafMasterViewController.m
//  seafile
//
//  Created by Wei Wang on 7/7/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import "SeafAppDelegate.h"
#import "SeafFileViewController.h"
#import "SeafDetailViewController.h"
#import "SeafUploadDirViewController.h"
#import "SeafDirViewController.h"
#import "SeafFile.h"
#import "SeafRepos.h"
#import "SeafCell.h"
#import "SeafUploadingFileCell.h"

#import "FileSizeFormatter.h"
#import "SeafDateFormatter.h"
#import "ExtentedString.h"
#import "UIViewController+Extend.h"
#import "SVProgressHUD.h"
#import "Debug.h"

#import "QBImagePickerController.h"

enum {
    STATE_INIT = 0,
    STATE_LOADING,
    STATE_DELETE,
    STATE_MKDIR,
    STATE_CREATE,
    STATE_RENAME,
    STATE_PASSWORD,
    STATE_MOVE,
    STATE_COPY,
    STATE_SHARE_EMAIL,
    STATE_SHARE_LINK,
};


@interface SeafFileViewController ()<QBImagePickerControllerDelegate, UIPopoverControllerDelegate, SeafUploadDelegate, EGORefreshTableHeaderDelegate, SeafDirDelegate, SeafShareDelegate, UIActionSheetDelegate, MFMailComposeViewControllerDelegate>
- (UITableViewCell *)getSeafFileCell:(SeafFile *)sfile forTableView:(UITableView *)tableView;
- (UITableViewCell *)getSeafDirCell:(SeafDir *)sdir forTableView:(UITableView *)tableView;
- (UITableViewCell *)getSeafRepoCell:(SeafRepo *)srepo forTableView:(UITableView *)tableView;

@property (strong, nonatomic) SeafDir *directory;
@property (strong) id<SeafItem> curEntry;
@property (strong, nonatomic) IBOutlet UIActivityIndicatorView *loadingView;

@property (strong) UIBarButtonItem *selectAllItem;
@property (strong) UIBarButtonItem *selectNoneItem;
@property (strong) UIBarButtonItem *photoItem;
@property (strong) UIBarButtonItem *doneItem;
@property (strong) UIBarButtonItem *editItem;
@property (strong) NSArray *rightItems;

@property (readonly) EGORefreshTableHeaderView* refreshHeaderView;

@property (retain) NSIndexPath *selectedindex;
@property (readonly) UIView *shadowView;
@property (readonly) UITableView *editToolTable;
@property (readonly) NSArray *editToolTableCells;

@property (strong) UIActionSheet *actionSheet;

@property int state;

@property(nonatomic,strong) UIPopoverController *popoverController;
@property (retain) NSDateFormatter *formatter;

@end

@implementation SeafFileViewController

@synthesize connection = _connection;
@synthesize directory = _directory;
@synthesize curEntry = _curEntry;
@synthesize selectAllItem = _selectAllItem, selectNoneItem = _selectNoneItem;
@synthesize selectedindex = _selectedindex;
@synthesize editToolTable = _editToolTable;
@synthesize editToolTableCells = _editToolTableCells;

@synthesize popoverController;


- (SeafDetailViewController *)detailViewController
{
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    return (SeafDetailViewController *)[appdelegate detailViewControllerAtIndex:TABBED_SEAFILE];
}

- (UITableView *)editToolTable
{
    if (!_editToolTable) {
         _editToolTable = [[UITableView alloc] initWithFrame:(CGRect){0, 0, 0, 0}];
        _editToolTable.delegate = self;
        _editToolTable.dataSource = self;
        
        _editToolTable.scrollEnabled = NO;
        
        _shadowView = [[UIView alloc] initWithFrame:self.tableView.frame];
        _shadowView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.35];
        _shadowView.hidden = YES;
        _shadowView.alpha = 0.0;
        
        UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(hideEditSheet)];
        [_shadowView addGestureRecognizer:tapGesture];
    }
    return _editToolTable;
}

- (NSArray *)editToolTableCells
{
    if (!_editToolTableCells) {
        NSArray *actions = @[S_NEWFILE, S_MKDIR, S_EDIT, S_SORT_NAME, S_SORT_MTIME];
        NSDictionary *images = @{S_NEWFILE: @"action-new-file",
                                 S_MKDIR: @"action-new-folder",
                                 S_EDIT: @"action-edit",
                                 S_SORT_NAME: @"action-sort",
                                 S_SORT_MTIME: @"action-sort"};
        
        NSMutableArray *tableCells = [NSMutableArray arrayWithCapacity:actions.count];
        for (NSString *label in actions) {
            UITableViewCell *cell = [[UITableViewCell alloc] init];
            cell.textLabel.text = label;
            cell.imageView.image = [UIImage imageNamed:images[label]];
            cell.backgroundColor = [UIColor whiteColor];
            
            [tableCells addObject:cell];
        }
        
        _editToolTableCells = [NSArray arrayWithArray:tableCells];
    }
    return _editToolTableCells;
}

- (void)setConnection:(SeafConnection *)conn
{
    [self.detailViewController setPreViewItem:nil master:nil];
    [conn loadRepos:self];
    [self setDirectory:(SeafDir *)conn.rootFolder];
}

- (void)showLoadingView
{
    if (!self.loadingView) {
        self.loadingView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
        self.loadingView.color = [UIColor darkTextColor];
        self.loadingView.hidesWhenStopped = YES;
        [self.tableView addSubview:self.loadingView];
    }
    self.loadingView.center = self.view.center;
    self.loadingView.frame = CGRectMake(self.loadingView.frame.origin.x, (self.view.frame.size.height-self.loadingView.frame.size.height)/2, self.loadingView.frame.size.width, self.loadingView.frame.size.height);
    [self.loadingView startAnimating];
}

- (void)dismissLoadingView
{
    [self.loadingView stopAnimating];
}

- (void)awakeFromNib
{
    if (IsIpad()) {
        self.preferredContentSize = CGSizeMake(320.0, 600.0);
    }
    [super awakeFromNib];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    if([self respondsToSelector:@selector(edgesForExtendedLayout)])
        self.edgesForExtendedLayout = UIRectEdgeNone;
    if ([self.tableView respondsToSelector:@selector(setSeparatorInset:)])
        [self.tableView setSeparatorInset:UIEdgeInsetsMake(0, 0, 0, 0)];
    self.formatter = [[NSDateFormatter alloc] init];
    [self.formatter setDateFormat:@"yyyy-MM-dd HH.mm.ss"];
    self.tableView.rowHeight = 50;

    self.state = STATE_INIT;
    _refreshHeaderView = [[EGORefreshTableHeaderView alloc] initWithFrame:CGRectMake(0.0f, 0.0f - self.tableView.bounds.size.height, self.view.frame.size.width, self.tableView.bounds.size.height)];
    _refreshHeaderView.delegate = self;
    [_refreshHeaderView refreshLastUpdatedDate];
    [self.tableView addSubview:_refreshHeaderView];
    
    self.navigationController.navigationBar.tintColor = BAR_COLOR;
    [self.navigationController setToolbarHidden:YES animated:NO];
}

- (void)noneSelected:(BOOL)none
{
    if (none) {
        self.navigationItem.leftBarButtonItem = _selectAllItem;
        NSArray *items = self.toolbarItems;
        [[items objectAtIndex:0] setEnabled:NO];
        [[items objectAtIndex:1] setEnabled:NO];
        [[items objectAtIndex:3] setEnabled:NO];
    } else {
        self.navigationItem.leftBarButtonItem = _selectNoneItem;
        NSArray *items = self.toolbarItems;
        [[items objectAtIndex:0] setEnabled:YES];
        [[items objectAtIndex:1] setEnabled:YES];
        [[items objectAtIndex:3] setEnabled:YES];
    }
}

- (void)checkPreviewFileExist
{
    if ([self.detailViewController.preViewItem isKindOfClass:[SeafFile class]]) {
        SeafFile *sfile = (SeafFile *)self.detailViewController.preViewItem;
        NSString *parent = [sfile.path stringByDeletingLastPathComponent];
        BOOL deleted = YES;
        if (![_directory isKindOfClass:[SeafRepos class]] && _directory.repoId == sfile.repoId && [parent isEqualToString:_directory.path]) {
            for (SeafBase *entry in _directory.allItems) {
                if (entry == sfile) {
                    deleted = NO;
                    break;
                }
            }
            if (deleted)
                [self.detailViewController setPreViewItem:nil master:nil];
        }
    }
}
- (void)refreshView
{
    for (SeafUploadFile *file in _directory.uploadItems) {
        file.delegate = self;
    }
    [self.tableView reloadData];
    if (IsIpad() && self.detailViewController.preViewItem) {
        [self checkPreviewFileExist];
    }
    if (self.editing) {
        if (![self.tableView indexPathsForSelectedRows])
            [self noneSelected:YES];
        else
            [self noneSelected:NO];
    }
}

- (void)viewDidUnload
{
    [self setLoadingView:nil];
    [super viewDidUnload];
    _refreshHeaderView = nil;
    _directory = nil;
    _curEntry = nil;
}

- (void)selectAll:(id)sender
{
    int row;
    long count = _directory.allItems.count;
    for (row = 0; row < count; ++row) {
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:row inSection:0];
        NSObject *entry  = [self getDentrybyIndexPath:indexPath tableView:self.tableView];
        if (![entry isKindOfClass:[SeafUploadFile class]])
            [self.tableView selectRowAtIndexPath:indexPath animated:YES scrollPosition:UITableViewScrollPositionNone];
    }
    [self noneSelected:NO];
}

- (void)selectNone:(id)sender
{
    long count = _directory.allItems.count;
    for (int row = 0; row < count; ++row) {
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:row inSection:0];
        [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
    }
    [self noneSelected:YES];
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated
{
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    if (editing) {
        if (![appdelegate checkNetworkStatus]) return;
        [self.navigationController.toolbar sizeToFit];
        
        UIBarButtonItem *copyButton = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Copy", @"Seafile") style:UIBarButtonItemStylePlain target:self action:@selector(copyFiles:)];
        UIBarButtonItem *moveButton = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Move", @"Seafile") style:UIBarButtonItemStylePlain target:self action:@selector(moveFiles:)];
        UIBarButtonItem *flexibleSpace = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:self action:nil];
        UIBarButtonItem *deleteButton = [[UIBarButtonItem alloc] initWithTitle:S_DELETE style:UIBarButtonItemStylePlain target:self action:@selector(deleteFiles:)];
        [deleteButton setTitleTextAttributes:@{NSForegroundColorAttributeName:[UIColor redColor]} forState:UIControlStateNormal];
        
        [self setToolbarItems:@[copyButton, moveButton, flexibleSpace, deleteButton]];
        
        [self noneSelected:YES];
        [self.photoItem setEnabled:NO];
        [self.navigationController setToolbarHidden:NO animated:YES];
    } else {
        self.navigationItem.leftBarButtonItem = nil;
        [self.navigationController setToolbarHidden:YES animated:YES];
        //if(!IsIpad())  self.tabBarController.tabBar.hidden = NO;
        [self.photoItem setEnabled:YES];
    }

    [super setEditing:editing animated:animated];
    [self.tableView setEditing:editing animated:animated];
}

- (void)addPhotos:(id)sender
{
    if(self.popoverController)
        return;
    if (![QBImagePickerController isAccessible]) {
        Warning("Error: Source is not accessible.");
        [self alertWithTitle:NSLocalizedString(@"Photos are not accessible", @"Seafile")];
        return;
    }
    QBImagePickerController *imagePickerController = [[QBImagePickerController alloc] init];
    imagePickerController.title = NSLocalizedString(@"Photos", @"Seafile");
    imagePickerController.delegate = self;
    imagePickerController.allowsMultipleSelection = YES;
    imagePickerController.filterType = QBImagePickerControllerFilterTypeNone;

    if (IsIpad()) {
        UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:imagePickerController];
        self.popoverController = [[UIPopoverController alloc] initWithContentViewController:navigationController];
        self.popoverController.delegate = self;
        [self.popoverController presentPopoverFromBarButtonItem:self.photoItem permittedArrowDirections:UIPopoverArrowDirectionAny animated:YES];
    } else {
        SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
        [appdelegate showDetailView:imagePickerController];
    }
}

- (void)editDone:(id)sender
{
    [self setEditing:NO animated:YES];
    self.navigationItem.rightBarButtonItem = nil;
    self.navigationItem.rightBarButtonItems = self.rightItems;
}

- (void)editStart:(id)sender
{
    [self setEditing:YES animated:YES];
    if (self.editing) {
        self.navigationItem.rightBarButtonItems = nil;
        self.navigationItem.rightBarButtonItem = self.doneItem;
        if (IsIpad() && self.popoverController) {
            [self.popoverController dismissPopoverAnimated:YES];
            self.popoverController = nil;
        }
    }
}

- (void)showEditSheet:(id)sender
{
    if (!self.editToolTable.superview) {
        [self.view.superview addSubview:self.shadowView];
        [self.view.superview addSubview:self.editToolTable];
        
        self.editToolTable.frame = (CGRect){0, 64.0, self.tableView.frame.size.width, 0};
        self.editToolTable.hidden = YES;
    }
    
    if (!self.editToolTable.hidden) {
        [self hideEditSheet];
        return;
    }
    
    [self.editToolTable reloadData];
    
    self.editToolTable.hidden = NO;
    self.shadowView.hidden = NO;
    
    [UIView animateWithDuration:0.25f animations:^{
        CGRect newFrame = (CGRect){0, self.editToolTable.frame.origin.y, self.editToolTable.frame.size.width, [self.editToolTable numberOfRowsInSection:0] * 50};
        self.editToolTable.frame = newFrame;
        self.shadowView.alpha = 1.0;
    }];
}

- (void)hideEditSheet
{
    [UIView animateWithDuration:0.25f animations:^{
        CGRect newFrame = (CGRect){0, self.editToolTable.frame.origin.y, self.editToolTable.frame.size.width, 0.0};
        self.editToolTable.frame = newFrame;
        self.shadowView.alpha = 0.0;
    } completion:^(BOOL finished) {
        self.shadowView.hidden = YES;
        self.editToolTable.hidden = YES;
    }];
}

- (void)initNavigationItems:(SeafDir *)directory
{
    if (![directory isKindOfClass:[SeafRepos class]]) {
        if (directory.editable) {
            self.photoItem = [self getBarItem:@"plus".navItemImgName action:@selector(addPhotos:)size:20];
            self.doneItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(editDone:)];
            self.editItem = [self getBarItemAutoSize:@"ellipsis".navItemImgName action:@selector(showEditSheet:)];
            UIBarButtonItem *space = [self getSpaceBarItem:16.0];
            self.rightItems = [NSArray arrayWithObjects: self.editItem, space, self.photoItem, nil];
            self.navigationItem.rightBarButtonItems = self.rightItems;

            _selectAllItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Select All", @"Seafile") style:UIBarButtonItemStylePlain target:self action:@selector(selectAll:)];
            _selectNoneItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Select None", @"Seafile") style:UIBarButtonItemStylePlain target:self action:@selector(selectNone:)];
        }
    }
}

- (SeafDir *)directory
{
    return _directory;
}

- (void)setDirectory:(SeafDir *)directory
{
    if (!_directory)
        [self initNavigationItems:directory];

    _connection = directory->connection;
    _directory = directory;
    self.title = directory.name;
    [_directory loadContent:NO];
    Debug("%@, %@, loading ... %d %@\n", _directory.repoId, _directory.path, _directory.hasCache, _directory.ooid);
    if (![_directory isKindOfClass:[SeafRepos class]])
        self.tableView.sectionHeaderHeight = 0;
    [_connection checkSyncDst:_directory];
    [self refreshView];
    [_directory setDelegate:self];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    if (!_directory.hasCache) {
        [self showLoadingView];
        self.state = STATE_LOADING;
    }
    [_connection checkSyncDst:_directory];
#if DEBUG
    if (_directory.uploadItems.count > 0)
        Debug("Upload %lu, state=%d", (unsigned long)_directory.uploadItems.count, self.state);
#endif
    dispatch_time_t time = dispatch_time(DISPATCH_TIME_NOW, 0.5);
    dispatch_after(time, dispatch_get_main_queue(), ^(void){
        for (SeafUploadFile *file in _directory.uploadItems) {
            file.delegate = self;
            if (!file.uploaded && !file.uploading) {
                Debug("background upload %@", file.name);
                [[SeafGlobal sharedObject] addUploadTask:file];
            }
        }
    });
}

- (void)viewWillDisappear:(BOOL)animated
{
    if (IsIpad() && self.popoverController) {
        [self.popoverController dismissPopoverAnimated:YES];
        self.popoverController = nil;
    }
    
    [self.editToolTable removeFromSuperview];
}
#pragma mark - Table View

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    if ([tableView isEqual:self.editToolTable]) {
        return 1;
    }
    
    if (![_directory isKindOfClass:[SeafRepos class]]) {
        return 1;
    }
    return [[((SeafRepos *)_directory)repoGroups] count];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if ([tableView isEqual:self.editToolTable]) {
        return self.editToolTableCells.count - 1;
    }
    
    if (![_directory isKindOfClass:[SeafRepos class]]) {
        return _directory.allItems.count;
    }
    NSArray *repos =  [[((SeafRepos *)_directory) repoGroups] objectAtIndex:section];
    return repos.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if ([tableView isEqual:self.editToolTable]) {
        return 50;
    }
    
    return [super tableView:tableView heightForRowAtIndexPath:indexPath];
}

- (UITableViewCell *)getCell:(NSString *)CellIdentifier forTableView:(UITableView *)tableView
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        NSArray *cells = [[NSBundle mainBundle] loadNibNamed:CellIdentifier owner:self options:nil];
        cell = [cells objectAtIndex:0];
    }
    return cell;
}

- (UITableViewCell *)getSeafUploadFileCell:(SeafUploadFile *)file forTableView:(UITableView *)tableView
{
    file.delegate = self;
    MGSwipeTableCell *c;
    if (file.uploading) {
        SeafUploadingFileCell *cell = (SeafUploadingFileCell *)[self getCell:@"SeafUploadingFileCell" forTableView:tableView];
        cell.nameLabel.text = file.name;
        cell.imageView.image = file.icon;
        
        cell.leftButtons = [self buttonsForUploadFileCell];
        cell.leftSwipeSettings.transition = MGSwipeTransitionStatic;
        
        [cell.progressView setProgress:file.uProgress * 1.0/100];
        c = cell;
    } else {
        SeafCell *cell = (SeafCell *)[self getCell:@"SeafCell" forTableView:tableView];
        cell.textLabel.text = file.name;
        cell.imageView.image = file.icon;
        cell.badgeLabel.text = nil;
        
        cell.leftButtons = [self buttonsForFileCell];
        cell.leftSwipeSettings.transition = MGSwipeTransitionStatic;

        NSString *sizeStr = [FileSizeFormatter stringFromNumber:[NSNumber numberWithLongLong:file.filesize ] useBaseTen:NO];
        NSDictionary *dict = [file uploadAttr];
        cell.accessoryView = nil;
        if (dict) {
            int utime = [[dict objectForKey:@"utime"] intValue];
            BOOL result = [[dict objectForKey:@"result"] boolValue];
            if (result)
                cell.detailTextLabel.text = [NSString stringWithFormat:NSLocalizedString(@"%@, Uploaded %@", @"Seafile"), sizeStr, [SeafDateFormatter stringFromLongLong:utime]];
            else {
                cell.detailTextLabel.text = [NSString stringWithFormat:NSLocalizedString(@"%@, waiting to upload", @"Seafile"), sizeStr];
            }
        } else {
            cell.detailTextLabel.text = [NSString stringWithFormat:NSLocalizedString(@"%@, waiting to upload", @"Seafile"), sizeStr];
        }
        c = cell;
    }
    
    return c;
}

- (SeafCell *)getSeafFileCell:(SeafFile *)sfile forTableView:(UITableView *)tableView
{
    SeafCell *cell = (SeafCell *)[self getCell:@"SeafCell" forTableView:tableView];
    cell.textLabel.text = sfile.name;
    cell.detailTextLabel.text = sfile.detailText;
    cell.imageView.image = sfile.icon;
    cell.badgeLabel.text = nil;
    
    cell.leftButtons = [self buttonsForFileCell];
    cell.leftSwipeSettings.transition = MGSwipeTransitionStatic;
    
    sfile.delegate = self;
    sfile.udelegate = self;
    return cell;
}

- (SeafCell *)getSeafDirCell:(SeafDir *)sdir forTableView:(UITableView *)tableView
{
    SeafCell *cell = (SeafCell *)[self getCell:@"SeafDirCell" forTableView:tableView];
    cell.textLabel.text = sdir.name;
    cell.detailTextLabel.text = nil;
    cell.imageView.image = sdir.icon;
    
    cell.leftButtons = [self buttonsForDirCell];
    cell.leftSwipeSettings.transition = MGSwipeTransitionStatic;
    
    sdir.delegate = self;
    return cell;
}

- (SeafCell *)getSeafRepoCell:(SeafRepo *)srepo forTableView:(UITableView *)tableView
{
    SeafCell *cell = (SeafCell *)[self getCell:@"SeafCell" forTableView:tableView];
    NSString *detail = [NSString stringWithFormat:@"%@, %@", [FileSizeFormatter stringFromNumber:[NSNumber numberWithUnsignedLongLong:srepo.size ] useBaseTen:NO], [SeafDateFormatter stringFromLongLong:srepo.mtime]];
    cell.detailTextLabel.text = detail;
    cell.imageView.image = srepo.icon;
    cell.textLabel.text = srepo.name;
    cell.badgeLabel.text = nil;
    srepo.delegate = self;
    return cell;
}

- (NSArray *)buttonsForUploadFileCell
{
    MGSwipeButton *deleteAction = [MGSwipeButton buttonWithTitle:@"" icon:[UIImage imageNamed:@"action-delete"] backgroundColor:[UIColor groupTableViewBackgroundColor] callback:^BOOL(MGSwipeTableCell *sender) {
        SeafBase *entry = (SeafBase *)[self getDentrybyIndexPath:[self.tableView indexPathForCell:sender] tableView:self.tableView];
        
        if (self.detailViewController.preViewItem == entry)
            self.detailViewController.preViewItem = nil;
        
        [self.directory removeUploadFile:(SeafUploadFile *)entry];
        [self.tableView reloadData];
        
        return YES;
    }];
    
    return @[deleteAction];
}

- (NSArray *)buttonsForFileCell
{
    MGSwipeButton *deleteAction = [MGSwipeButton buttonWithTitle:@"" icon:[UIImage imageNamed:@"action-delete"] backgroundColor:[UIColor groupTableViewBackgroundColor] callback:^BOOL(MGSwipeTableCell *sender) {
        _selectedindex = [self.tableView indexPathForCell:sender];
        SeafFile *file = (SeafFile *)[self getDentrybyIndexPath:[self.tableView indexPathForCell:sender] tableView:self.tableView];
        [self deleteFile:file];
        
        return YES;
    }];
    
    MGSwipeButton *renameAction = [MGSwipeButton buttonWithTitle:@"" icon:[UIImage imageNamed:@"action-rename"] backgroundColor:[UIColor groupTableViewBackgroundColor] callback:^BOOL(MGSwipeTableCell *sender) {
        SeafFile *file = (SeafFile *)[self getDentrybyIndexPath:[self.tableView indexPathForCell:sender] tableView:self.tableView];
        [self renameFile:file];
        
        return YES;
    }];
    
    MGSwipeButton *moveAction = [MGSwipeButton buttonWithTitle:@"" icon:[UIImage imageNamed:@"action-move"] backgroundColor:[UIColor groupTableViewBackgroundColor] callback:^BOOL(MGSwipeTableCell *sender) {
        _selectedindex = [self.tableView indexPathForCell:sender];
        [self popupDirChooseView:nil];
        
        return YES;
    }];
    
    MGSwipeButton *downloadAction = [MGSwipeButton buttonWithTitle:@"" icon:[UIImage imageNamed:@"action-download"] backgroundColor:[UIColor groupTableViewBackgroundColor] callback:^BOOL(MGSwipeTableCell *sender) {
        SeafFile *file = (SeafFile *)[self getDentrybyIndexPath:[self.tableView indexPathForCell:sender] tableView:self.tableView];
        [self redownloadFile:file];
        
        return YES;
    }];
    
    MGSwipeButton *shareAction = [MGSwipeButton buttonWithTitle:@"" icon:[UIImage imageNamed:@"action-share"] backgroundColor:[UIColor groupTableViewBackgroundColor] callback:^BOOL(MGSwipeTableCell *sender) {
        _selectedindex = [self.tableView indexPathForCell:sender];
        SeafBase *entry = (SeafBase *)[self getDentrybyIndexPath:_selectedindex tableView:self.tableView];
        
        if (!entry.shareLink) {
            [SVProgressHUD showWithStatus:NSLocalizedString(@"Generate share link ...", @"Seafile")];
            [entry generateShareLink:self];
        } else {
            [self generateSharelink:entry WithResult:YES];
        }
        
        return YES;
    }];
    
    return @[deleteAction, renameAction, moveAction, downloadAction, shareAction];
}

- (NSArray *)buttonsForDirCell
{
    MGSwipeButton *deleteAction = [MGSwipeButton buttonWithTitle:@"" icon:[UIImage imageNamed:@"action-delete"] backgroundColor:[UIColor groupTableViewBackgroundColor] callback:^BOOL(MGSwipeTableCell *sender) {
        _selectedindex = [self.tableView indexPathForCell:sender];
        SeafDir *dir = (SeafDir *)[self getDentrybyIndexPath:[self.tableView indexPathForCell:sender] tableView:self.tableView];
        [self deleteDir:dir];
        
        return YES;
    }];
    
    MGSwipeButton *renameAction = [MGSwipeButton buttonWithTitle:@"" icon:[UIImage imageNamed:@"action-rename"] backgroundColor:[UIColor groupTableViewBackgroundColor] callback:^BOOL(MGSwipeTableCell *sender) {
        SeafFile *file = (SeafFile *)[self getDentrybyIndexPath:[self.tableView indexPathForCell:sender] tableView:self.tableView];
        [self renameFile:file];
        
        return YES;
    }];
    
    MGSwipeButton *moveAction = [MGSwipeButton buttonWithTitle:@"" icon:[UIImage imageNamed:@"action-move"] backgroundColor:[UIColor groupTableViewBackgroundColor] callback:^BOOL(MGSwipeTableCell *sender) {
        _selectedindex = [self.tableView indexPathForCell:sender];
        [self popupDirChooseView:nil];
        
        return YES;
    }];
    
    MGSwipeButton *shareAction = [MGSwipeButton buttonWithTitle:@"" icon:[UIImage imageNamed:@"action-share"] backgroundColor:[UIColor groupTableViewBackgroundColor] callback:^BOOL(MGSwipeTableCell *sender) {
        _selectedindex = [self.tableView indexPathForCell:sender];
        SeafBase *entry = (SeafBase *)[self getDentrybyIndexPath:_selectedindex tableView:self.tableView];
        
        if (!entry.shareLink) {
            [SVProgressHUD showWithStatus:NSLocalizedString(@"Generate share link ...", @"Seafile")];
            [entry generateShareLink:self];
        } else {
            [self generateSharelink:entry WithResult:YES];
        }
        
        return YES;
    }];
    
    return @[deleteAction, renameAction, moveAction, shareAction];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if ([tableView isEqual:self.editToolTable]) {
        switch (indexPath.row) {
            case 0:
                return self.editToolTableCells[indexPath.row];
                
            case 1:
                return self.editToolTableCells[indexPath.row];
                
            case 2:
                return self.editToolTableCells[indexPath.row];
                
            case 3:
            {
                NSString *key = [SeafGlobal.sharedObject objectForKey:@"SORT_KEY"];
                if ([@"NAME" caseInsensitiveCompare:key] != NSOrderedSame) {
                    return self.editToolTableCells[indexPath.row];
                }
                else {
                    return self.editToolTableCells[indexPath.row + 1];
                }
            }
                
            default:
                return nil;
        }
    }
    
    NSObject *entry = [self getDentrybyIndexPath:indexPath tableView:tableView];
    if (!entry) return [[UITableViewCell alloc] init];
    
    if ([entry isKindOfClass:[SeafRepo class]]) {
        return [self getSeafRepoCell:(SeafRepo *)entry forTableView:tableView];
    } else if ([entry isKindOfClass:[SeafFile class]]) {
        return [self getSeafFileCell:(SeafFile *)entry forTableView:tableView];
    } else if ([entry isKindOfClass:[SeafDir class]]) {
        return [self getSeafDirCell:(SeafDir *)entry forTableView:tableView];
    } else {
        return [self getSeafUploadFileCell:(SeafUploadFile *)entry forTableView:tableView];
    }
}

- (NSIndexPath *)tableView:(UITableView *)tableView willSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if ([tableView isEqual:self.editToolTable]) {
        return indexPath;
    }
    
    NSObject *entry  = [self getDentrybyIndexPath:indexPath tableView:tableView];
    if (tableView.editing && [entry isKindOfClass:[SeafUploadFile class]])
        return nil;
    return indexPath;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    if ([tableView isEqual:self.editToolTable]) {
        return NO;
    }
    
    NSObject *entry  = [self getDentrybyIndexPath:indexPath tableView:tableView];
    return ![entry isKindOfClass:[SeafUploadFile class]];
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath
{
    return NO;
}

- (void)popupSetRepoPassword:(SeafRepo *)repo
{
    self.state = STATE_PASSWORD;
    [self popupInputView:NSLocalizedString(@"Password of this library", @"Seafile") placeholder:nil secure:true handler:^(NSString *input) {
        if (!input || input.length == 0) {
            [self alertWithTitle:NSLocalizedString(@"Password must not be empty", @"Seafile")handler:^{
                [self popupSetRepoPassword:repo];
            }];
            return;
        }
        if (input.length < 3 || input.length  > 100) {
            [self alertWithTitle:NSLocalizedString(@"The length of password should be between 3 and 100", @"Seafile") handler:^{
                [self popupSetRepoPassword:repo];
            }];
            return;
        }
        [SVProgressHUD showWithStatus:NSLocalizedString(@"Checking library password ...", @"Seafile")];
        [repo setDelegate:self];
        if ([repo->connection localDecrypt:repo.repoId])
            [repo checkRepoPassword:input];
        else
            [repo setRepoPassword:input];
    }];
}

- (void)popupMkdirView
{
    self.state = STATE_MKDIR;
    _directory.delegate = self;
    [self popupInputView:S_MKDIR placeholder:NSLocalizedString(@"New folder name", @"Seafile") secure:false handler:^(NSString *input) {
        if (!input || input.length == 0) {
            [self alertWithTitle:NSLocalizedString(@"Folder name must not be empty", @"Seafile")];
            return;
        }
        if (![input isValidFileName]) {
            [self alertWithTitle:NSLocalizedString(@"Folder name invalid", @"Seafile")];
            return;
        }
        [_directory mkdir:input];
        [SVProgressHUD showWithStatus:NSLocalizedString(@"Creating folder ...", @"Seafile")];
    }];
}

- (void)popupCreateView
{
    self.state = STATE_CREATE;
    _directory.delegate = self;
    [self popupInputView:S_NEWFILE placeholder:NSLocalizedString(@"New file name", @"Seafile") secure:false handler:^(NSString *input) {
        if (!input || input.length == 0) {
            [self alertWithTitle:NSLocalizedString(@"File name must not be empty", @"Seafile")];
            return;
        }
        if (![input isValidFileName]) {
            [self alertWithTitle:NSLocalizedString(@"File name invalid", @"Seafile")];
            return;
        }
        [_directory createFile:input];
        [SVProgressHUD showWithStatus:NSLocalizedString(@"Creating file ...", @"Seafile")];
    }];
}

- (void)popupRenameView:(NSString *)newName
{
    self.state = STATE_RENAME;
    [self popupInputView:S_RENAME placeholder:newName prefilled:YES secure:false handler:^(NSString *input) {
        if (!input || input.length == 0) {
            [self alertWithTitle:NSLocalizedString(@"File name must not be empty", @"Seafile")];
            return;
        }
        if (![input isValidFileName]) {
            [self alertWithTitle:NSLocalizedString(@"File name invalid", @"Seafile")];
            return;
        }
        [_directory renameFile:(SeafFile *)_curEntry newName:input];
        [SVProgressHUD showWithStatus:NSLocalizedString(@"Renaming file ...", @"Seafile")];
    }];
}

- (void)popupDirChooseView:(id<SeafPreView>)file
{
    UIViewController *controller = nil;
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    if (file)
        controller = [[SeafUploadDirViewController alloc] initWithSeafConnection:_connection uploadFile:file];
    else
        controller = [[SeafDirViewController alloc] initWithSeafDir:self.connection.rootFolder delegate:self chooseRepo:false];

    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:controller];
    [navController setModalPresentationStyle:UIModalPresentationFormSheet];
    [appdelegate.tabbarController presentViewController:navController animated:YES completion:nil];
    if (IsIpad()) {
        CGRect frame = navController.view.superview.frame;
        navController.view.superview.frame = CGRectMake(frame.origin.x+frame.size.width/2-320/2, frame.origin.y+frame.size.height/2-500/2, 320, 500);
    }
}

- (SeafBase *)getDentrybyIndexPath:(NSIndexPath *)indexPath tableView:(UITableView *)tableView
{
    if (!indexPath) return nil;
    @try {
        if (![_directory isKindOfClass:[SeafRepos class]])
            return [_directory.allItems objectAtIndex:[indexPath row]];
        NSArray *repos = [[((SeafRepos *)_directory)repoGroups] objectAtIndex:[indexPath section]];
        return [repos objectAtIndex:[indexPath row]];
    } @catch(NSException *exception) {
        return nil;
    }
}

- (BOOL)isCurrentFileImage:(NSMutableArray **)imgs
{
    if (![_curEntry conformsToProtocol:@protocol(SeafPreView)])
        return NO;
    id<SeafPreView> pre = (id<SeafPreView>)_curEntry;
    if (!pre.isImageFile) return NO;

    NSMutableArray *arr = [[NSMutableArray alloc] init];
    for (id entry in _directory.allItems) {
        if ([entry conformsToProtocol:@protocol(SeafPreView)]
            && [(id<SeafPreView>)entry isImageFile])
            [arr addObject:entry];
    }
    *imgs = arr;
    return YES;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if ([tableView isEqual:self.editToolTable]) {
        switch (indexPath.row) {
            case 0:
                [self popupCreateView];
                break;
                
            case 1:
                [self popupMkdirView];
                break;
                
            case 2:
                [self editStart:nil];
                break;
                
            case 3:
            {
                NSString *key = [SeafGlobal.sharedObject objectForKey:@"SORT_KEY"];
                if ([@"NAME" caseInsensitiveCompare:key] != NSOrderedSame) {
                    [SeafGlobal.sharedObject setObject:@"NAME" forKey:@"SORT_KEY"];
                }
                else {
                    [SeafGlobal.sharedObject setObject:@"MTIME" forKey:@"SORT_KEY"];
                }
                
                [_directory reSortItems];
                [self.tableView reloadData];
                
                break;
            }
            
            default:
                break;
        }
        
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        [self hideEditSheet];
        
        return;
    }
    
    if (self.navigationController.topViewController != self)   return;
    _selectedindex = indexPath;
    if (tableView.editing == YES) {
        [self noneSelected:NO];
        return;
    }
    _curEntry = [self getDentrybyIndexPath:indexPath tableView:tableView];
    if (!_curEntry) {
        [self performSelector:@selector(reloadData) withObject:nil afterDelay:0.1];
        return;
    }
    [_curEntry setDelegate:self];
    if ([_curEntry isKindOfClass:[SeafRepo class]] && [(SeafRepo *)_curEntry passwordRequired]) {
        [self popupSetRepoPassword:_curEntry];
        return;
    }

    if ([_curEntry conformsToProtocol:@protocol(SeafPreView)]) {
        if (!IsIpad()) {
            SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
            [appdelegate showDetailView:self.detailViewController];
        }
        NSMutableArray *arr = nil;
        if ([self isCurrentFileImage:&arr]) {
            [self.detailViewController setPreViewItems:arr current:(id<SeafPreView>)_curEntry master:self];
        } else {
            id<SeafPreView> item = (id<SeafPreView>)_curEntry;
            [self.detailViewController setPreViewItem:item master:self];
        }
    } else if ([_curEntry isKindOfClass:[SeafDir class]]) {
        SeafFileViewController *controller = [[UIStoryboard storyboardWithName:@"FolderView_iPad" bundle:nil] instantiateViewControllerWithIdentifier:@"MASTERVC"];
        [controller setDirectory:(SeafDir *)_curEntry];
        [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
        [self.navigationController pushViewController:controller animated:YES];
    }
}

- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath
{
    [self tableView:tableView didSelectRowAtIndexPath:indexPath];
}

- (void)tableView:(UITableView *)tableView didDeselectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if ([tableView isEqual:self.editToolTable]) {
        return;
    }
    
    if (tableView.editing == YES) {
        if (![tableView indexPathsForSelectedRows])
            [self noneSelected:YES];
    }
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    if ([tableView isEqual:self.editToolTable]) {
        return nil;
    }
    
    if (![_directory isKindOfClass:[SeafRepos class]])
        return nil;

    NSString *text = nil;
    if (section == 0) {
        text = NSLocalizedString(@"My Own Libraries", @"Seafile");
    } else {
        NSArray *repos =  [[((SeafRepos *)_directory)repoGroups] objectAtIndex:section];
        SeafRepo *repo = (SeafRepo *)[repos objectAtIndex:0];
        text = repo ? repo.owner: @"";
    }
    UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 30)];
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(10, 3, tableView.bounds.size.width - 10, 18)];
    label.text = text;
    label.textColor = [UIColor whiteColor];
    label.backgroundColor = [UIColor clearColor];
    [headerView setBackgroundColor:HEADER_COLOR];
    [headerView addSubview:label];
    return headerView;
}

#pragma mark - SeafDentryDelegate
- (void)entry:(SeafBase *)entry updated:(BOOL)updated progress:(int)percent
{
    if (entry == _directory) {
        [self dismissLoadingView];
        [SVProgressHUD dismiss];
        [self doneLoadingTableViewData];
        if (updated)  [self refreshView];
        self.state = STATE_INIT;
    } else if ([entry isKindOfClass:[SeafFile class]]) {
        if (percent == 100) [self updateEntryCell:(SeafFile *)entry];
        if (entry == self.detailViewController.preViewItem)
            [self.detailViewController entry:entry updated:updated progress:percent];
    }
}

- (void)entry:(SeafBase *)entry downloadingFailed:(NSUInteger)errCode;
{
    if (errCode == HTTP_ERR_REPO_PASSWORD_REQUIRED) {
        NSAssert(0, @"Here should never be reached");
    }
    if ([entry isKindOfClass:[SeafFile class]]) {
        [self.detailViewController entry:entry downloadingFailed:errCode];
        return;
    }

    NSCAssert([entry isKindOfClass:[SeafDir class]], @"entry must be SeafDir");
    Debug("state=%d %@,%@, %@\n", self.state, entry.path, entry.repoId, _directory.path);
    if (entry == _directory) {
        [self doneLoadingTableViewData];
        switch (self.state) {
            case STATE_DELETE:
                [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to delete files", @"Seafile")];
                break;
            case STATE_MKDIR:
                [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to create folder", @"Seafile")];
                [self performSelector:@selector(popupMkdirView) withObject:nil afterDelay:1.0];
                break;
            case STATE_CREATE:
                [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to create file", @"Seafile")];
                [self performSelector:@selector(popupCreateView) withObject:nil afterDelay:1.0];
                break;
            case STATE_COPY:
                [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to copy files", @"Seafile")];
                break;
            case STATE_MOVE:
                [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to move files", @"Seafile")];
                break;
            case STATE_RENAME: {
                [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to rename file", @"Seafile")];
                SeafFile *file = (SeafFile *)_curEntry;
                [self performSelector:@selector(popupRenameView:) withObject:file.name afterDelay:1.0];
                break;
            }
            case STATE_LOADING:
                if (!_directory.hasCache) {
                    [self dismissLoadingView];
                    [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to load files", @"Seafile")];
                } else
                    [SVProgressHUD dismiss];
                break;
            default:
                break;
        }
        self.state = STATE_INIT;
        [self dismissLoadingView];
    }
}

- (void)entry:(SeafBase *)entry repoPasswordSet:(BOOL)success;
{
    if (entry != _curEntry)  return;

    NSAssert([entry isKindOfClass:[SeafRepo class]], @"entry must be a repo\n");
    if (success) {
        [SVProgressHUD dismiss];
        self.state = STATE_INIT;
        SeafFileViewController *controller = [[UIStoryboard storyboardWithName:@"FolderView_iPad" bundle:nil] instantiateViewControllerWithIdentifier:@"MASTERVC"];
        [self.navigationController pushViewController:controller animated:YES];
        [controller setDirectory:(SeafDir *)entry];
    } else {
        [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Wrong library password", @"Seafile")];
        [self performSelector:@selector(popupSetRepoPassword:) withObject:entry afterDelay:1.0];
    }
}

- (void)doneLoadingTableViewData
{
    [_refreshHeaderView egoRefreshScrollViewDataSourceDidFinishedLoading:self.tableView];
}

#pragma mark - mark UIScrollViewDelegate Methods
- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    [_refreshHeaderView egoRefreshScrollViewDidScroll:scrollView];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate
{
    [_refreshHeaderView egoRefreshScrollViewDidEndDragging:scrollView];
}

#pragma mark - EGORefreshTableHeaderDelegate Methods
- (void)egoRefreshTableHeaderDidTriggerRefresh:(EGORefreshTableHeaderView*)view
{
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    if (![appdelegate checkNetworkStatus]) {
        [self performSelector:@selector(doneLoadingTableViewData) withObject:nil afterDelay:0.1];
        return;
    }

    _directory.delegate = self;
    [_directory loadContent:YES];
}

- (BOOL)egoRefreshTableHeaderDataSourceIsLoading:(EGORefreshTableHeaderView*)view
{
    return [_directory state] == SEAF_DENTRY_LOADING;
}

- (NSDate*)egoRefreshTableHeaderDataSourceLastUpdated:(EGORefreshTableHeaderView*)view
{
    return [NSDate date];
}

#pragma mark - edit files
- (void)copyFiles:(id)sender
{
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    
    if (self != appdelegate.fileVC) {
        return [appdelegate.fileVC copyFiles:sender];
    }
    
    self.state = STATE_COPY;
    [self popupDirChooseView:nil];
}

- (void)moveFiles:(id)sender
{
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    
    if (self != appdelegate.fileVC) {
        return [appdelegate.fileVC moveFiles:sender];
    }
    
    self.state = STATE_MOVE;
    [self popupDirChooseView:nil];
}

- (void)deleteFiles:(id)sender
{
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    
    if (self != appdelegate.fileVC) {
        return [appdelegate.fileVC deleteFiles:sender];
    }
    
    NSArray *idxs = [self.tableView indexPathsForSelectedRows];
    if (!idxs) return;
    NSMutableArray *entries = [[NSMutableArray alloc] init];
    for (NSIndexPath *indexPath in idxs) {
        [entries addObject:[_directory.allItems objectAtIndex:indexPath.row]];
    }
    self.state = STATE_DELETE;
    [_directory delEntries:entries];
    [SVProgressHUD showWithStatus:NSLocalizedString(@"Deleting files ...", @"Seafile")];
}

- (void)deleteFile:(SeafFile *)file
{
    NSArray *entries = [NSArray arrayWithObject:file];
    self.state = STATE_DELETE;
    [SVProgressHUD showWithStatus:NSLocalizedString(@"Deleting file ...", @"Seafile")];
    [_directory delEntries:entries];
}

- (void)deleteDir:(SeafDir *)dir
{
    NSArray *entries = [NSArray arrayWithObject:dir];
    self.state = STATE_DELETE;
    [SVProgressHUD showWithStatus:NSLocalizedString(@"Deleting directory ...", @"Seafile")];
    [_directory delEntries:entries];
}

- (void)redownloadFile:(SeafFile *)file
{
    [file deleteCache];
    [self.detailViewController setPreViewItem:nil master:nil];
    [self tableView:self.tableView didSelectRowAtIndexPath:_selectedindex];
}

- (void)renameFile:(SeafFile *)file
{
    _curEntry = file;
    [self popupRenameView:file.name];
}

- (void)backgroundUpload:(SeafUploadFile *)ufile
{
    [[SeafGlobal sharedObject] addUploadTask:ufile];
}

- (void)chooseUploadDir:(SeafDir *)dir file:(SeafUploadFile *)ufile replace:(BOOL)replace
{
    SeafUploadFile *uploadFile = (SeafUploadFile *)ufile;
    uploadFile.update = replace;
    [dir addUploadFile:uploadFile flush:true];
    [NSThread detachNewThreadSelector:@selector(backgroundUpload:) toTarget:self withObject:ufile];
}

- (void)uploadFile:(SeafUploadFile *)file
{
    file.delegate = self;
    [self popupDirChooseView:file];
}

#pragma mark - SeafDirDelegate
- (void)chooseDir:(UIViewController *)c dir:(SeafDir *)dir
{
    [c.navigationController dismissViewControllerAnimated:YES completion:nil];
    NSArray *idxs = [self.tableView indexPathsForSelectedRows];
    if (!idxs && _selectedindex) {
        idxs = @[_selectedindex];
    }
    if (!idxs) return;
    NSMutableArray *entries = [[NSMutableArray alloc] init];
    for (NSIndexPath *indexPath in idxs) {
        [entries addObject:[_directory.allItems objectAtIndex:indexPath.row]];
    }
    Debug("_directory.delegate=%@", _directory.delegate);
    _directory.delegate = self;
    if (self.state == STATE_COPY) {
        [_directory copyEntries:entries dstDir:dir];
        [SVProgressHUD showWithStatus:NSLocalizedString(@"Copying files ...", @"Seafile")];
    } else {
        [_directory moveEntries:entries dstDir:dir];
        [SVProgressHUD showWithStatus:NSLocalizedString(@"Moving files ...", @"Seafile")];
    }
}
- (void)cancelChoose:(UIViewController *)c
{
    [c.navigationController dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - QBImagePickerControllerDelegate
- (BOOL)filenameExist:(NSString *)filename
{
    NSArray *arr = _directory.allItems;
    NSUInteger idx = [arr indexOfObjectPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
        NSString *name = nil;
        if ([obj conformsToProtocol:@protocol(SeafPreView)]) {
            name = ((id<SeafPreView>)obj).name;
        } else if ([obj isKindOfClass:[SeafBase class]]) {
            name = ((SeafBase *)obj).name;
        }
        if (name && [name isEqualToString:filename]) {
            *stop = true;
            return true;
        }
        return false;
    }];
    return (idx != NSNotFound);
}

- (void)uploadPickedAssets:(NSArray *)assets
{
    NSMutableArray *files = [[NSMutableArray alloc] init];
    NSString *date = [self.formatter stringFromDate:[NSDate date]];
    for (ALAsset *asset in assets) {
        NSString *filename = asset.defaultRepresentation.filename;
        if ([self filenameExist:filename]) {
            NSString *name = filename.stringByDeletingPathExtension;
            NSString *ext = filename.pathExtension;
            filename = [NSString stringWithFormat:@"%@-%@.%@", name, date, ext];
        }
        NSString *path = [SeafGlobal.sharedObject.uploadsDir stringByAppendingPathComponent:filename];
        SeafUploadFile *file =  [self.connection getUploadfile:path];
        file.asset = asset;
        file.delegate = self;
        [files addObject:file];
        [self.directory addUploadFile:file flush:false];
    }
    [self.tableView reloadData];
    for (SeafUploadFile *file in files) {
        [[SeafGlobal sharedObject] addUploadTask:file];
    }
    [SeafUploadFile saveAttrs];
}

- (void)uploadPickedAssetsUrl:(NSArray *)urls
{
    if (urls.count == 0) return;
    NSMutableArray *assets = [[NSMutableArray alloc] init];
    NSURL *last = [urls objectAtIndex:urls.count-1];
    for (NSURL *url in urls) {
        [SeafGlobal.sharedObject assetForURL:url
                                  resultBlock:^(ALAsset *asset) {
                                      if (assets) [assets addObject:asset];
                                      if (url == last) [self uploadPickedAssets:assets];
                                  } failureBlock:^(NSError *error) {
                                      if (url == last) [self uploadPickedAssets:assets];
                                  }];
    }
}

- (void)dismissImagePickerController:(QBImagePickerController *)imagePickerController
{
    if (IsIpad()) {
        [self.popoverController dismissPopoverAnimated:YES];
        self.popoverController = nil;
    } else {
        [imagePickerController.navigationController dismissViewControllerAnimated:YES completion:NULL];
    }
}

- (void)qb_imagePickerControllerDidCancel:(QBImagePickerController *)imagePickerController
{
    [self dismissImagePickerController:imagePickerController];
}

- (void)qb_imagePickerController:(QBImagePickerController *)imagePickerController didSelectAssets:(NSArray *)assets
{
    if (assets.count == 0) return;
    NSMutableArray *urls = [[NSMutableArray alloc] init];
    for (ALAsset *asset in assets) {
        [urls addObject:asset.defaultRepresentation.url];
    }
    [self uploadPickedAssetsUrl:urls];
    [self dismissImagePickerController:imagePickerController];
}

#pragma mark - UIPopoverControllerDelegate
- (void)popoverControllerDidDismissPopover:(UIPopoverController *)popoverController
{
    self.popoverController = nil;
}

#pragma mark - SeafFileUpdateDelegate
- (void)updateProgress:(SeafFile *)file result:(BOOL)res completeness:(int)percent
{
    NSUInteger index = [_directory.allItems indexOfObject:file];
    if (index == NSNotFound)
        return;
    @try {
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:0];
        UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
        if (res && [cell isKindOfClass:[SeafUploadingFileCell class]]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [((SeafUploadingFileCell *)cell).progressView setProgress:percent*1.0f/100];
            });
        } else
            [self.tableView reloadRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationAutomatic ];
    } @catch(NSException *exception) {
    }
}

#pragma mark - SeafUploadDelegate
- (void)uploadProgress:(SeafUploadFile *)file result:(BOOL)res progress:(int)percent
{
    long index = [_directory.allItems indexOfObject:file];
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:0];
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
    if (!cell) return;
    if (res && percent < 100 && [cell isKindOfClass:[SeafUploadingFileCell class]]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [((SeafUploadingFileCell *)cell).progressView setProgress:percent*1.0f/100];
        });
    } else {
        [self.tableView reloadData];
        //[self.tableView reloadRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
    }
}

- (void)uploadSucess:(SeafUploadFile *)file oid:(NSString *)oid
{
    [self uploadProgress:file result:YES progress:100];
    if (self.isVisible) {
        [SVProgressHUD showSuccessWithStatus:[NSString stringWithFormat:NSLocalizedString(@"File '%@' uploaded success", @"Seafile"), file.name]];
    }

}

- (void)photoSelectedChanged:(id<SeafPreView>)from to:(id<SeafPreView>)to;
{
    NSUInteger index = [_directory.allItems indexOfObject:to];
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:0];

    [self.tableView selectRowAtIndexPath:indexPath animated:NO scrollPosition:UITableViewScrollPositionMiddle];
}

- (void)updateEntryCell:(SeafFile *)entry
{
    if (!self.isVisible) return;
    NSUInteger index = [_directory.allItems indexOfObject:entry];
    if (index == NSNotFound)
        return;
    @try {
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:0];
        UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
        if (cell){
            cell.detailTextLabel.text = entry.detailText;
            cell.imageView.image = entry.icon;
        }
    } @catch(NSException *exception) {
    }
}

#pragma mark - SeafShareDelegate
- (void)generateSharelink:(SeafBase *)entry WithResult:(BOOL)success
{
    SeafBase *base = (SeafBase *)[self getDentrybyIndexPath:_selectedindex tableView:self.tableView];
    if (entry != base) {
        [SVProgressHUD dismiss];
        return;
    }

    if (!success) {
        if ([entry isKindOfClass:[SeafFile class]])
            [SVProgressHUD showErrorWithStatus:[NSString stringWithFormat:NSLocalizedString(@"Failed to generate share link of file '%@'", @"Seafile"), entry.name]];
        else
            [SVProgressHUD showErrorWithStatus:[NSString stringWithFormat:NSLocalizedString(@"Failed to generate share link of directory '%@'", @"Seafile"), entry.name]];
        return;
    }
    
    [SVProgressHUD dismiss];
    
    NSURL *shareURL = [NSURL URLWithString:entry.shareLink];
    UIActivityViewController *activityController = [[UIActivityViewController alloc] initWithActivityItems:@[shareURL] applicationActivities:nil];
    [self presentViewController:activityController animated:YES completion:nil];
}

@end
