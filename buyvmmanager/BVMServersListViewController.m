#import "BVMServersListViewController.h"
#import "BVMServersManager.h"
#import "BVMServerInfo.h"
#import "BVMAddEditServerViewController.h"
#import "BVMServerViewController.h"
#import "BVMAboutSettingsViewController.h"
#import "BVMNotifications.h"
#import "NSError+BVMErrors.h"
#import "UIColor+BVMColors.h"

@interface BVMServersListViewController () <UIPopoverControllerDelegate>

@property (nonatomic, copy) NSDictionary *servers;
@property (nonatomic, strong) NSArray *orderedServerIds;

@property (nonatomic, weak) UINavigationController *detailNavigationVC;

@property (nonatomic, strong, readonly) UIBarButtonItem *addItem;
@property (nonatomic, strong, readonly) UIBarButtonItem *settingsItem;

@property (nonatomic, assign) BOOL showedFirstLaunchAddScreen;

@property (nonatomic, strong, readonly) BVMAddEditServerViewController *addVC;
@property (nonatomic, strong, readonly) UIPopoverController *addVCPopoverController;

@property (nonatomic, strong, readonly) BVMAboutSettingsViewController *settingsVC;
@property (nonatomic, strong, readonly) UIPopoverController *settingsVCPopoverController;

@property (nonatomic, strong) UIPopoverController *currentEditingPopoverController;

@property (nonatomic, strong) NSString *serverIdSelectedBeforeEdit;

@end

@implementation BVMServersListViewController

@synthesize addItem = _addItem,
            settingsItem = _settingsItem,
            addVC = _addVC,
            addVCPopoverController = _addVCPopoverController,
            settingsVC = _settingsVC,
            settingsVCPopoverController = _settingsVCPopoverController
            ;

- (id)initWithDetailNavigationController:(UINavigationController *)navigationController
{
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) {
        self.detailNavigationVC = navigationController;
        self.showedFirstLaunchAddScreen = NO;
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.title = NSLocalizedString(@"My VMs", nil);

    self.navigationItem.rightBarButtonItem = self.editButtonItem;

    self.toolbarItems = @[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil],
                          self.settingsItem
                          ];

    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:nil action:@selector(refreshControlActivated:) forControlEvents:UIControlEventValueChanged];

    self.tableView.allowsSelectionDuringEditing = YES;

    [self subscribeToNotifications];
    [self reloadData];
}

- (void)viewDidUnload
{
    [self unsubscribeFromNotifications];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    [self.navigationController setToolbarHidden:NO animated:NO];
    
    NSIndexPath *selectedRowIndexPath = [self.tableView indexPathForSelectedRow];
    if (selectedRowIndexPath) {
        [self.tableView deselectRowAtIndexPath:selectedRowIndexPath animated:YES];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];

    [self.navigationController setToolbarHidden:YES animated:NO];
}

-(void)viewDidAppear:(BOOL)animated
{
    if (self.servers.count == 0 && !self.showedFirstLaunchAddScreen) {
        self.showedFirstLaunchAddScreen = YES;
        self.editing = YES;
        [self addButtonTouched];
    }
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated
{
    if (editing) {
        [self saveSelection];
    }

    [super setEditing:editing animated:animated];

    if (editing) {
        self.navigationItem.leftBarButtonItem = self.addItem;
    } else {
        self.navigationItem.leftBarButtonItem = nil;
        [self restoreSelection];
    }
}

- (void)addButtonTouched
{
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        CDZWeakSelf weakSelf = self;
        self.addVC.dismissBlock = ^() {
            [weakSelf.addVCPopoverController dismissPopoverAnimated:YES];
        };
        [self.addVCPopoverController presentPopoverFromBarButtonItem:self.addItem
                                                permittedArrowDirections:UIPopoverArrowDirectionAny
                                                                animated:YES];
    } else {
        UIViewController *vc = [[UINavigationController alloc] initWithRootViewController:self.addVC];
        self.addVC.dismissBlock = ^() {
            [vc dismissViewControllerAnimated:YES completion:nil];
        };
        [self presentViewController:vc animated:YES completion:nil];
    }
}

- (void)settingsButtonTouched
{
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        CDZWeakSelf weakSelf = self;
        self.settingsVC.dismissBlock = ^() {
            // not necessary for this iteration of the about/settings popover
            [weakSelf.settingsVCPopoverController dismissPopoverAnimated:YES];
        };
        [self.settingsVCPopoverController presentPopoverFromBarButtonItem:self.settingsItem
                                                 permittedArrowDirections:UIPopoverArrowDirectionAny
                                                                 animated:YES];
    } else {
        UIViewController *vc = [[UINavigationController alloc] initWithRootViewController:self.settingsVC];
        self.settingsVC.dismissBlock = ^() {
            [vc dismissViewControllerAnimated:YES completion:nil];
        };
        [self presentViewController:vc animated:YES completion:nil];
    }
}

- (void)refreshControlActivated:(id)sender
{
    [self reloadData];
}

- (void)displayEditorForIndexPath:(NSIndexPath *)indexPath
{
    NSString *serverId = [self serverIdForIndexPath:indexPath];
    UIView *presentingCell = [self.tableView cellForRowAtIndexPath:indexPath];

    BVMAddEditServerViewController *editVc = [[BVMAddEditServerViewController alloc] initForServerId:serverId];
    UIViewController *vc = [[UINavigationController alloc] initWithRootViewController:editVc];

    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        self.currentEditingPopoverController = [[UIPopoverController alloc] initWithContentViewController:vc];
        editVc.dismissBlock = ^() {
            [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
            [self.currentEditingPopoverController dismissPopoverAnimated:YES];
        };
        self.currentEditingPopoverController.delegate = self;
        [self.currentEditingPopoverController presentPopoverFromRect:presentingCell.frame
                                                              inView:self.tableView
                                            permittedArrowDirections:UIPopoverArrowDirectionAny
                                                            animated:YES];
    } else {
        editVc.dismissBlock = ^() {
            [vc dismissViewControllerAnimated:YES completion:nil];
        };
        [self presentViewController:vc animated:YES completion:nil];
    }
}

#pragma mark Selection save/restore

- (void)saveSelection
{
    NSIndexPath *selectedIP = [self.tableView indexPathForSelectedRow];
    if (selectedIP == nil) self.serverIdSelectedBeforeEdit = nil;
    else self.serverIdSelectedBeforeEdit = [self serverIdForIndexPath:selectedIP];
}

- (void)restoreSelection
{
    NSIndexPath *ipToSelect = [self indexPathForServerId:self.serverIdSelectedBeforeEdit];
    [self.tableView selectRowAtIndexPath:ipToSelect animated:YES scrollPosition:UITableViewScrollPositionMiddle];
}

#pragma mark Data

- (void)configureCell:(UITableViewCell *)cell forIndexPath:(NSIndexPath *)indexPath
{
    NSString *serverId = [self serverIdForIndexPath:indexPath];
    NSString *serverName = [self serverNameForIndexPath:indexPath];

    cell.textLabel.text = serverName;
    cell.textLabel.textColor = [UIColor blackColor];
    cell.detailTextLabel.text = @"";

    [BVMServerInfo requestInfoForServerId:serverId success:^(BVMServerInfo *info) {
        BVMServerStatus status = info.status;
        if (status == BVMServerStatusOffline) {
            cell.textLabel.textColor = [UIColor redColor];
            cell.textLabel.text = [NSString stringWithFormat:NSLocalizedString(@"%@ [offline]", nil), cell.textLabel.text];
        } else if (status == BVMServerStatusIndeterminate) {
            cell.textLabel.textColor = [UIColor blueColor];
            cell.textLabel.text = [NSString stringWithFormat:NSLocalizedString(@"%@ [unknown]", nil), cell.textLabel.text];
        }
        if (info.mainIpAddress && info.hostname) {
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ (%@)", info.mainIpAddress, info.hostname];
        } else if (info.mainIpAddress) {
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@", info.mainIpAddress];
        } else if (info.hostname) {
            cell.detailTextLabel.text = [NSString stringWithFormat:@"(%@)", info.hostname];
        }
    } error:^(NSError *error) {
        cell.textLabel.textColor = [UIColor blueColor];
        cell.textLabel.text = [NSString stringWithFormat:NSLocalizedString(@"%@ [unknown]", nil), cell.textLabel.text];
    } completion:^{
        [cell setNeedsLayout];
        [self.refreshControl endRefreshing];
    }];
}

- (void)reloadData
{
    // Store current selection:
    NSIndexPath *selectedIP = [self.tableView indexPathForSelectedRow];
    NSString *selectedServerId = (selectedIP == nil) ? nil : [self serverIdForIndexPath:selectedIP];

    // Reload underlying data structures and table view:
    self.servers = [BVMServersManager servers];
    [self.tableView reloadData];

    // Attempt to restore saved selection
    if (selectedServerId != nil) {
        [self.orderedServerIds enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            if ([selectedServerId isEqualToString:obj]) {
                NSIndexPath *ip = [NSIndexPath indexPathForRow:(NSInteger)idx inSection:0];
                [self.tableView selectRowAtIndexPath:ip animated:NO scrollPosition:UITableViewScrollPositionMiddle];
                if (stop!= NULL) *stop = YES;
            }
        }];
    }
}

- (void)reloadDataFromNotification:(NSNotification *)notification
{
    [self reloadData];
}

- (NSString *)serverIdForIndexPath:(NSIndexPath *)indexPath
{
    NSParameterAssert(indexPath.section == 0);
    return self.orderedServerIds[(NSUInteger) indexPath.row];
}

- (NSString *)serverNameForIndexPath:(NSIndexPath *)indexPath
{
    NSString *serverId = [self serverIdForIndexPath:indexPath];
    return self.servers[serverId];
}

- (NSIndexPath *)indexPathForServerId:(NSString *)serverId
{
    if (serverId == nil) return nil;

    NSUInteger idIndex = [self.orderedServerIds indexOfObjectPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
        if ([serverId isEqualToString:obj]) {
            if (stop != NULL) *stop = YES;
            return YES;
        }
        return NO;
    }];

    NSAssert(idIndex != NSNotFound, @"Could not find index path for server ID");
    return [NSIndexPath indexPathForItem:(NSInteger)idIndex inSection:0];
}

- (void)subscribeToNotifications
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reloadDataFromNotification:)
                                                 name:BVMServerStatusDidChangeNotification
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reloadDataFromNotification:)
                                                 name:BVMServersListDidChangeNotification
                                               object:nil];
}

- (void)unsubscribeFromNotifications
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark UIPopoverControllerDelegate methods

- (BOOL)popoverControllerShouldDismissPopover:(UIPopoverController *)popoverController
{
    if (popoverController != self.currentEditingPopoverController) return YES;

    NSIndexPath *indexPath = [self.tableView indexPathForSelectedRow];
    if (indexPath) [self.tableView deselectRowAtIndexPath:indexPath animated:YES];

    return YES;
}

#pragma mark UITableViewDataSource methods

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return (NSInteger) self.servers.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *CellIdentifier = @"Cell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellIdentifier];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.editingAccessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.selectionStyle = UITableViewCellSelectionStyleGray;
    }

    [self configureCell:cell forIndexPath:indexPath];

    return cell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    return YES;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        NSString *serverId = [self serverIdForIndexPath:indexPath];
        [BVMServersManager removeServerId:serverId];
        self.servers = [BVMServersManager servers];
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
    }
}

#pragma mark UITableViewDelegate methods

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *serverId = [self serverIdForIndexPath:indexPath];
    NSString *serverName = [self serverNameForIndexPath:indexPath];

    if (tableView.editing) {
        [self displayEditorForIndexPath:indexPath];
        return;
    }

    UIViewController *hostVC = [[BVMServerViewController alloc] initWithServerId:serverId name:serverName];

    if (!self.detailNavigationVC || self.detailNavigationVC == self.navigationController) {
        [self.navigationController pushViewController:hostVC animated:YES];
    } else {
        [self.detailNavigationVC setViewControllers:@[hostVC] animated:NO];
    }
}

- (void)tableView:(UITableView *)tableView willBeginEditingRowAtIndexPath:(NSIndexPath *)indexPath
{
    [self saveSelection];
}

- (void)tableView:(UITableView *)tableView didEndEditingRowAtIndexPath:(NSIndexPath *)indexPath
{
    [self restoreSelection];
}

- (NSString *)tableView:(UITableView *)tableView titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return NSLocalizedString(@"Forget", nil);
}

#pragma mark Property Overrides

- (void)setServers:(NSDictionary *)servers
{
    _servers = [servers copy];
    self.orderedServerIds = [_servers keysSortedByValueUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

- (UIBarButtonItem *)addItem
{
    if (!_addItem) {
        _addItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addButtonTouched)];
    }
    return _addItem;
}

- (UIBarButtonItem *)settingsItem
{
    if (!_settingsItem) {
        _settingsItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"072-Settings"] style:UIBarButtonItemStylePlain target:self action:@selector(settingsButtonTouched)];
    }
    return _settingsItem;
}

- (UIPopoverController *)addVCPopoverController
{
    if (!_addVCPopoverController) {
        UIViewController *vc = [[UINavigationController alloc] initWithRootViewController:self.addVC];
        _addVCPopoverController = [[UIPopoverController alloc] initWithContentViewController:vc];
    }
    return _addVCPopoverController;
}

- (BVMAddEditServerViewController *)addVC
{
    if (!_addVC) {
        _addVC = [[BVMAddEditServerViewController alloc] initForServerId:nil];
    }
    return _addVC;
}

- (UIPopoverController *)settingsVCPopoverController
{
    if (!_settingsVCPopoverController) {
        UIViewController *vc = [[UINavigationController alloc] initWithRootViewController:self.settingsVC];
        _settingsVCPopoverController = [[UIPopoverController alloc] initWithContentViewController:vc];
    }
    return _settingsVCPopoverController;
}

- (BVMAboutSettingsViewController *)settingsVC
{
    if (!_settingsVC) {
        _settingsVC = [[BVMAboutSettingsViewController alloc] init];
    }
    return _settingsVC;
}

@end
