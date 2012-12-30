#import "BVMHostViewController.h"
#import "BVMServerInfo.h"
#import "BVMServerActionPerform.h"
#import "BVMPinger.h"
#import "BVMHumanValueTransformer.h"
#import "BVMIPListViewController.h"
#import "BVMSizesListViewController.h"
#import "UIColor+BVMColors.h"
#import "MBProgressHUD.h"

typedef NS_ENUM(NSUInteger, BVMHostTableViewSections) {
    BVMHostTableViewSectionInfo = 0,
    BVMHostTableViewSectionPing,
    BVMHostTableViewSectionAction,
    BVMHostTableViewNumSections
};

typedef NS_ENUM(NSUInteger, BVMHostTableViewInfoRows) {
    BVMHostTableViewInfoRowIP = 0,
    BVMHostTableViewInfoRowBandwidth,
    BVMHostTableViewInfoRowMemory,
    BVMHostTableViewInfoRowHDD,
    BVMHostTableViewInfoNumRows
};

typedef NS_ENUM(NSUInteger, BVMHostTableViewPingRows) {
    BVMHostTableViewPingRow = 0,
    BVMHostTableViewPingNumRows
};

typedef NS_ENUM(NSUInteger, BVMHostTableViewActionRows) {
    BVMHostTableViewActionRowReboot = 0,
    BVMHostTableViewActionRowBoot,
    BVMHostTableViewActionRowShutdown,
    BVMHostTableViewActionNumRows
};

static NSString * BVMHostTableViewActionStrings[BVMHostTableViewActionNumRows];
__attribute__((constructor)) static void __BVMHostTableViewConstantsInit(void)
{
    @autoreleasepool {
        BVMHostTableViewActionStrings[BVMHostTableViewActionRowReboot] = NSLocalizedString(@"Reboot", nil);
        BVMHostTableViewActionStrings[BVMHostTableViewActionRowBoot] = NSLocalizedString(@"Boot", nil);
        BVMHostTableViewActionStrings[BVMHostTableViewActionRowShutdown] = NSLocalizedString(@"Shutdown", nil);
    }
}

@interface BVMHostViewController () <BVMPingerDelegate>

@property (nonatomic, copy) NSString *serverId;
@property (nonatomic, copy) NSString *serverName;
@property (nonatomic, strong) BVMServerInfo *serverInfo;

@property (nonatomic, copy) NSString *pingString;
@property (nonatomic, strong) BVMPinger *pinger;

@property (nonatomic, strong) UIView *headerView;
@property (nonatomic, strong) UILabel *headerHostnameLabel;
@property (nonatomic, strong) UILabel *headerStatusLabel;

@property (nonatomic, assign) BVMServerAction selectedAction;
@property (nonatomic, strong) NSTimer *navBarTintTimer;

@property (nonatomic, strong) UIAlertView *actionAlertView;
@property (nonatomic, strong) UIAlertView *loadErrorAlertView;

@property (nonatomic, strong, readonly) UIBarButtonItem *reloadButtonItem;

@property (nonatomic, strong, readonly) MBProgressHUD *progressHUD;

@property (nonatomic, assign, readonly) CGFloat headerViewSidePadding;

@end

@implementation BVMHostViewController

@synthesize reloadButtonItem = _reloadButtonItem,
            progressHUD = _progressHUD,
            headerViewSidePadding = _headerViewSidePadding
            ;

- (id)initWithServerId:(NSString *)serverId name:(NSString *)serverName
{
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) {
        self.serverId = serverId;
        self.serverName = serverName;
        self.title = serverName;
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.tableView.tableHeaderView = self.headerView;
    self.navigationItem.rightBarButtonItem = self.reloadButtonItem;

    [self reloadData];
}

#pragma mark BVM Data Management

- (void)reloadData
{
    // flow: reloadData reloads all data in the background, without erasing whatever is there now.
    //       anything that is available instantly tells the table view to refresh that row.
    //       async requests should tell the table view to refresh the appropriate row later.
    //       cellForRowAtIndexPath: adds appropriate data if available.

    [self.progressHUD show:YES];
    self.navigationItem.rightBarButtonItem = nil;

    [BVMServerInfo requestInfoForServerId:self.serverId withBlock:^(BVMServerInfo *info, NSError *error) {
        [self.progressHUD hide:YES];
        self.navigationItem.rightBarButtonItem = self.reloadButtonItem;

        if (error) {
            self.loadErrorAlertView = [[UIAlertView alloc] initWithTitle:@"Error"
                                                             message:[BVMHumanValueTransformer shortErrorFromError:error]
                                                            delegate:self
                                                   cancelButtonTitle:@":("
                                                   otherButtonTitles:nil];
            [self.loadErrorAlertView show];
            if (!self.serverInfo) self.headerHostnameLabel.text = @"";
            return;
        }
        self.serverInfo = info;

        if (self.serverInfo.status == BVMServerStatusOnline) {
            [self.pinger startPinging];
            self.pingString = nil;
        } else {
            self.pingString = @"";
            self.pinger = nil;
        }

        [self.tableView beginUpdates];
        [self.tableView reloadRowsAtIndexPaths:@[
            [NSIndexPath indexPathForRow:BVMHostTableViewInfoRowBandwidth inSection:BVMHostTableViewSectionInfo],
            [NSIndexPath indexPathForRow:BVMHostTableViewInfoRowHDD inSection:BVMHostTableViewSectionInfo],
            [NSIndexPath indexPathForRow:BVMHostTableViewInfoRowIP inSection:BVMHostTableViewSectionInfo],
            [NSIndexPath indexPathForRow:BVMHostTableViewInfoRowMemory inSection:BVMHostTableViewSectionInfo],
            [NSIndexPath indexPathForRow:BVMHostTableViewPingRow inSection:BVMHostTableViewSectionPing]
         ] withRowAnimation:UITableViewRowAnimationAutomatic];
        [self.tableView endUpdates];

        [self refreshHeaderView];
    }];
}

- (void)refreshHeaderView
{
    self.headerHostnameLabel.text = self.serverInfo.hostname;
    if (self.serverInfo.status == BVMServerStatusOnline) {
        self.headerStatusLabel.text = NSLocalizedString(@"Online", nil);
        self.headerStatusLabel.textColor = [UIColor bvm_onlineTextColor];
    } else {
        self.headerStatusLabel.text = NSLocalizedString(@"Offline", nil);
        self.headerStatusLabel.textColor = [UIColor redColor];
    }
}

#pragma mark BVMPingerDelegate methods

- (void)pinger:(BVMPinger *)pinger didUpdateWithTime:(double)seconds
{
    self.pingString = [NSString stringWithFormat:@"%.f ms", seconds*1000];

    [self.tableView beginUpdates];
    [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:0 inSection:BVMHostTableViewSectionPing]]
                          withRowAnimation:UITableViewRowAnimationAutomatic];
    [self.tableView endUpdates];
}

- (void)pinger:(BVMPinger *)pinger didEncounterError:(NSError *)error
{
    if (pinger != self.pinger) return;

    [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Ping Error", nil)
                                message:[BVMHumanValueTransformer shortErrorFromError:error]
                               delegate:nil
                      cancelButtonTitle:@":("
                      otherButtonTitles:nil]
     show];
    [self.pinger stopPinging];
    self.pinger = nil;
    self.pingString = @"";
}

- (void)pingerDidFinishPingSequence:(BVMPinger *)pinger
{
    self.pinger = nil;
}

#pragma mark UITableViewDataSource methods

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    NSParameterAssert(tableView == self.tableView);
    return BVMHostTableViewNumSections;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    NSParameterAssert(tableView == self.tableView);
    switch(section) {
        case BVMHostTableViewSectionInfo:
            return BVMHostTableViewInfoNumRows;
        case BVMHostTableViewSectionPing:
            return BVMHostTableViewPingNumRows;
        case BVMHostTableViewSectionAction:
            return BVMHostTableViewActionNumRows;
        default:
            NSLog(@"Unknown section %d in %s", section, __PRETTY_FUNCTION__);
    }
    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString * CellIdentifiers[BVMHostTableViewNumSections] = {
        @"UITableViewCellStyleValue2",
        @"UITableViewCellStyleValue2",
        @"UITableViewCellStyleDefault"
    };
    UITableViewCellStyle style = indexPath.section == BVMHostTableViewSectionAction ? UITableViewCellStyleDefault : UITableViewCellStyleValue2;
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:style reuseIdentifier:CellIdentifiers[indexPath.section]];
    
    switch(indexPath.section) {
        case BVMHostTableViewSectionInfo:
            if (self.serverInfo && self.serverInfo.status == BVMServerStatusOnline) {
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            } else {
                cell.accessoryType = UITableViewCellAccessoryNone;
            }

            switch(indexPath.row) {
                case BVMHostTableViewInfoRowBandwidth:
                    cell.textLabel.text = NSLocalizedString(@"Bandwidth", nil);
                    if (!self.serverInfo) cell.detailTextLabel.text = nil;
                    else cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ used (%d%%)",
                                                      [BVMHumanValueTransformer humanSizeValueFromBytes:self.serverInfo.bwUsed],
                                                      self.serverInfo.bwPercentUsed];
                    break;
                case BVMHostTableViewInfoRowHDD:
                    cell.textLabel.text = NSLocalizedString(@"HDD", nil);
                    if (self.serverInfo.status != BVMServerStatusOnline) cell.detailTextLabel.text = nil;
                    else cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ used (%d%%)",
                                                      [BVMHumanValueTransformer humanSizeValueFromBytes:self.serverInfo.hddUsed],
                                                      self.serverInfo.hddPercentUsed];
                    break;
                case BVMHostTableViewInfoRowIP:
                    cell.textLabel.text = NSLocalizedString(@"IP", nil);
                    cell.detailTextLabel.text = self.serverInfo.mainIpAddress;
                    break;
                case BVMHostTableViewInfoRowMemory:
                    cell.textLabel.text = NSLocalizedString(@"Memory", nil);
                    if (self.serverInfo.status != BVMServerStatusOnline) cell.detailTextLabel.text = nil;
                    else cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ used (%d%%)",
                                                      [BVMHumanValueTransformer humanSizeValueFromBytes:self.serverInfo.memUsed],
                                                      self.serverInfo.memPercentUsed];
                    break;
            }
            break;
        case BVMHostTableViewSectionPing:
            NSParameterAssert(indexPath.row == 0);
            cell.textLabel.text = NSLocalizedString(@"Ping", nil);
            if (self.pingString) {
                cell.detailTextLabel.text = self.pingString;
            }
            else {
                cell.detailTextLabel.text = nil;
                if (self.serverInfo) {
                    UIActivityIndicatorView *indicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
                    [indicator startAnimating];
                    CGRect indicatorFrame = indicator.frame;
                    indicatorFrame.origin.x = 85;
                    indicatorFrame.origin.y = cell.bounds.size.height/2 - indicator.bounds.size.height/2 - 1;
                    indicator.frame = indicatorFrame;
                    [cell.contentView addSubview:indicator];
                }
            }
            break;
        case BVMHostTableViewSectionAction:
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.textLabel.text = BVMHostTableViewActionStrings[indexPath.row];
            break;
    }
    
    return cell;
}

#pragma mark UITableViewDelegate methods

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == BVMHostTableViewSectionInfo) {
        UIViewController *vc = nil;
        switch (indexPath.row) {
            case BVMHostTableViewInfoRowIP: {
                vc = [[BVMIPListViewController alloc] initWithServer:self.serverName
                                                                 ips:self.serverInfo.ipAddresses];
                break;
            }
            case BVMHostTableViewInfoRowBandwidth: {
                vc = [[BVMSizesListViewController alloc] initWithServer:self.serverName
                                                              statistic:NSLocalizedString(@"Bandwidth", nil)
                                                                  total:self.serverInfo.bwTotal
                                                                   used:self.serverInfo.bwUsed
                                                                   free:self.serverInfo.bwFree
                                                            percentUsed:self.serverInfo.bwPercentUsed];
                break;
            }
            case BVMHostTableViewInfoRowHDD: {
                vc = [[BVMSizesListViewController alloc] initWithServer:self.serverName
                                                              statistic:NSLocalizedString(@"HDD", nil)
                                                                  total:self.serverInfo.hddTotal
                                                                   used:self.serverInfo.hddUsed
                                                                   free:self.serverInfo.hddFree
                                                            percentUsed:self.serverInfo.hddPercentUsed];
                break;
            }
            case BVMHostTableViewInfoRowMemory: {
                vc = [[BVMSizesListViewController alloc] initWithServer:self.serverName
                                                              statistic:NSLocalizedString(@"Memory", nil)
                                                                  total:self.serverInfo.memTotal
                                                                   used:self.serverInfo.memUsed
                                                                   free:self.serverInfo.memFree
                                                            percentUsed:self.serverInfo.memPercentUsed];
                break;
            }
        }
        if (vc) [self.navigationController pushViewController:vc animated:YES];
    }
    else if (indexPath.section == BVMHostTableViewSectionAction) {
        switch (indexPath.row) {
            case BVMHostTableViewActionRowBoot:
                self.selectedAction = BVMServerActionBoot;
                break;
            case BVMHostTableViewActionRowReboot:
                self.selectedAction = BVMServerActionReboot;
                break;
            case BVMHostTableViewActionRowShutdown:
                self.selectedAction = BVMServerActionShutdown;
                break;
        }
        [self displayActionAlertView];
        [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
    }
    else if (indexPath.section == BVMHostTableViewSectionPing) {
        // this section only contains the Ping row, so let's just assume that row was selected
        [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
        self.pingString = nil;
        [self.pinger startPinging];
        [self.tableView beginUpdates];
        [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
        [self.tableView endUpdates];
    }
}

- (NSIndexPath *)tableView:(UITableView *)tableView willSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (!self.serverInfo || self.serverInfo.status != BVMServerStatusOnline) {
        if (indexPath.section == BVMHostTableViewSectionInfo
            || indexPath.section == BVMHostTableViewSectionPing) {
            return nil;
        }
    }

    return indexPath;
}

#pragma mark UIAlertViewDelegate methods

- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex
{
    if (alertView == self.actionAlertView) {
        NSString *hostname = [[alertView textFieldAtIndex:0] text];
        [self actionAlertViewDidDismissWithButtonIndex:buttonIndex enteredHostname:hostname];
    }

    if (alertView == self.loadErrorAlertView) {
        if (UI_USER_INTERFACE_IDIOM() != UIUserInterfaceIdiomPad) {
            [self.navigationController popToRootViewControllerAnimated:YES];
        }
    }
}

#pragma mark Server Actions

- (void)displayActionAlertView
{
    NSString *message;
    switch (self.selectedAction) {
        case BVMServerActionBoot:
            message = NSLocalizedString(@"You are attempting to boot a VM.\nEnter the hostname to confirm:", nil);
            break;
        case BVMServerActionReboot:
            message = NSLocalizedString(@"Attempting to REBOOT a VM.\nEnter the hostname to confirm:", nil);
            break;
        case BVMServerActionShutdown:
            message = NSLocalizedString(@"Attempting to SHUT DOWN a VM.\nEnter the hostname to confirm:", nil);
            break;
    }

    self.actionAlertView = [[UIAlertView alloc] initWithTitle:@""
                                                      message:message
                                                     delegate:self
                                            cancelButtonTitle:NSLocalizedString(@"Cancel", nil)
                                            otherButtonTitles:@"OK", nil];
    self.actionAlertView.alertViewStyle = UIAlertViewStylePlainTextInput;
    [self.actionAlertView show];

    self.navBarTintTimer = [NSTimer scheduledTimerWithTimeInterval:0.6
                                                            target:self
                                                          selector:@selector(toggleNavBarTint)
                                                          userInfo:nil
                                                           repeats:YES];
}

- (void)toggleNavBarTint
{
    if (self.navigationController.navigationBar.tintColor) {
        self.navigationController.navigationBar.tintColor = nil;
    } else {
        self.navigationController.navigationBar.tintColor = [UIColor redColor];
    }
}

- (void)actionAlertViewDidDismissWithButtonIndex:(NSInteger)buttonIndex enteredHostname:(NSString *)hostname
{
    static NSInteger cancelButtonIndex = 0;

    self.navigationController.navigationBar.tintColor = nil;
    [self.navBarTintTimer invalidate];
    self.navBarTintTimer = nil;
    if (buttonIndex == cancelButtonIndex) return;

    if ([[hostname lowercaseString] isEqualToString:[self.serverInfo.hostname lowercaseString]]) {
        [BVMServerActionPerform performAction:self.selectedAction forServerId:self.serverId withBlock:^(BVMServerActionStatus status, NSError *error) {
            if (error || status == BVMServerActionStatusIndeterminate) {
                [[[UIAlertView alloc] initWithTitle:@"Error"
                                            message:[BVMHumanValueTransformer shortErrorFromError:error]
                                           delegate:nil
                                  cancelButtonTitle:@":("
                                  otherButtonTitles:nil]
                 show];
            } else {
                [self reportServerActionStatus:status];
            }
        }];
    } else {
        [[[UIAlertView alloc] initWithTitle:@""
                                    message:NSLocalizedString(@"The hostname entered was incorrect.", nil)
                                   delegate:nil
                          cancelButtonTitle:@"OK"
                          otherButtonTitles:nil]
         show];
    }
}

- (void)reportServerActionStatus:(BVMServerActionStatus)status
{
    switch (status) {
        case BVMServerActionStatusBooted:
            self.headerStatusLabel.text = NSLocalizedString(@"Booting...", nil);
            break;
        case BVMServerActionStatusRebooted:
            self.headerStatusLabel.text = NSLocalizedString(@"Rebooting...", nil);
            break;
        case BVMServerActionStatusShutdown:
            self.headerStatusLabel.text = NSLocalizedString(@"Shutting down...", nil);
            break;
        default: break;
    }

    self.headerStatusLabel.textColor = [UIColor blackColor];
    self.pinger = nil;
    self.pingString = @"";
    self.serverInfo.status = BVMServerStatusIndeterminate;
    [self.tableView reloadData];
    [self.tableView scrollRectToVisible:self.headerView.frame animated:YES];
    [self.progressHUD show:YES];

    [self performSelector:@selector(reloadData) withObject:nil afterDelay:6.0];
}

#pragma mark Pasteboard Copying

-(void)tableView:(UITableView*)tableView performAction:(SEL)action forRowAtIndexPath:(NSIndexPath*)indexPath withSender:(id)sender
{
    if (action == @selector(copy:)) {
        UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
        pasteboard.string = [tableView cellForRowAtIndexPath:indexPath].detailTextLabel.text;
    }
}

-(BOOL)tableView:(UITableView*)tableView canPerformAction:(SEL)action forRowAtIndexPath:(NSIndexPath*)indexPath withSender:(id)sender
{
    if (indexPath.section == BVMHostTableViewSectionInfo || indexPath.section == BVMHostTableViewSectionPing) {
        if (action == @selector(copy:)) {
            return YES;
        }
    }
    return NO;
}

-(BOOL)tableView:(UITableView*)tableView shouldShowMenuForRowAtIndexPath:(NSIndexPath*)indexPath
{
    if (indexPath.section == BVMHostTableViewSectionInfo || indexPath.section == BVMHostTableViewSectionPing) {
        return YES;
    }
    return NO;
}

#pragma mark Property overrides

- (UIView *)headerView {
    if (!_headerView) {
        _headerView = [[UIView alloc] initWithFrame:(CGRect){ CGPointZero, { self.view.bounds.size.width, 65 } }];
        _headerView.autoresizesSubviews = YES;
        _headerView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        _headerView.backgroundColor = [UIColor clearColor];

        self.headerHostnameLabel = [[UILabel alloc] initWithFrame:(CGRect){ {self.headerViewSidePadding, 10} , { _headerView.bounds.size.width-2*self.headerViewSidePadding, 35 }}];
        self.headerHostnameLabel.font = [UIFont boldSystemFontOfSize:22.0];
        self.headerHostnameLabel.backgroundColor = [UIColor clearColor];
        self.headerHostnameLabel.text = NSLocalizedString(@"Loading...", nil);
        self.headerHostnameLabel.shadowColor = [UIColor whiteColor];
        self.headerHostnameLabel.shadowOffset = CGSizeMake(0, 1.0);
        [_headerView addSubview:self.headerHostnameLabel];

        self.headerStatusLabel = [[UILabel alloc] initWithFrame:(CGRect){ {self.headerViewSidePadding, 41} , { self.headerHostnameLabel.bounds.size.width, 20 }}];
        self.headerStatusLabel.font = [UIFont boldSystemFontOfSize:18.0];
        self.headerStatusLabel.backgroundColor = [UIColor clearColor];
        self.headerStatusLabel.shadowColor = self.headerHostnameLabel.shadowColor;
        self.headerStatusLabel.shadowOffset = self.headerHostnameLabel.shadowOffset;
        [_headerView addSubview:self.headerStatusLabel];
    }
    return _headerView;
}

- (BVMPinger *)pinger
{
    if (!_pinger) {
        _pinger = [[BVMPinger alloc] initWithHost:self.serverInfo.mainIpAddress];
        _pinger.delegate = self;
    }
    return _pinger;
}

- (UIBarButtonItem *)reloadButtonItem
{
    if (!_reloadButtonItem) {
        _reloadButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(reloadData)];
    }
    return _reloadButtonItem;
}

- (MBProgressHUD *)progressHUD
{
    if (!_progressHUD) {
        _progressHUD = [[MBProgressHUD alloc] initWithView:self.view];
        [self.view addSubview:_progressHUD];
    }
    return _progressHUD;
}

- (CGFloat)headerViewSidePadding
{
    if (!_headerViewSidePadding) {
        if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
            _headerViewSidePadding = 36;
        } else {
            _headerViewSidePadding = 18;
        }
    }
    return _headerViewSidePadding;
}

@end
