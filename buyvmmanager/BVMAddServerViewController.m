#import "BVMAddServerViewController.h"
#import "BVMTextFieldTableViewCell.h"
#import "BVMServersManager.h"
#import "UIColor+BVMColors.h"
#import "ZBarSDK.h"

typedef NS_ENUM(NSUInteger, BVMAddServerTableViewRow) {
    BVMAddServerTableViewRowName = 0,
    BVMAddServerTableViewRowAPIKey,
    BVMAddServerTableViewRowAPIHash,
    BVMAddServerTableViewNumRows
};

@interface BVMAddServerViewController () <UITextFieldDelegate, ZBarReaderDelegate>

@property (nonatomic, weak) UITextField *serverNameField;
@property (nonatomic, weak) UITextField *apiKeyField;
@property (nonatomic, weak) UITextField *apiHashField;

@property (nonatomic, strong, readonly) UIView *footerView;
@property (nonatomic, weak, readonly) UILabel *footerLabel;

@property (nonatomic, strong) ZBarReaderViewController *readerVc;
@property (nonatomic, weak) UITextField *currentReadingTextField;

@end

@implementation BVMAddServerViewController

@synthesize footerView = _footerView,
            footerLabel = _footerLabel
            ;

- (id)init
{
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) {
        self.title = NSLocalizedString(@"Add VM", nil);
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.tableView.allowsSelection = NO;
    self.tableView.tableFooterView = self.footerView;

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(doneButtonTouched)];

    self.contentSizeForViewInPopover = CGSizeMake(320, self.footerView.frame.origin.y + self.footerView.frame.size.height);
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    if (!self.myPopoverController) {
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancelButtonTouched)];
    } else {
        self.navigationItem.leftBarButtonItem = nil;
    }
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation
{
    [self.footerLabel sizeToFit];
}

#pragma mark Interface Actions

- (void)scanQRForApiKey
{
    [self scanQRForField:self.apiKeyField];
}

- (void)scanQRForApiHash
{
    [self scanQRForField:self.apiHashField];
}

- (void)scanQRForField:(UITextField *)field
{
    self.currentReadingTextField = field;
    [field becomeFirstResponder];
    [self presentViewController:self.readerVc animated:YES completion:nil];
}

- (void)cancelButtonTouched
{
    [self dismiss];
}

- (void)doneButtonTouched
{
    [self saveData];
}

- (void)dismiss
{
    if (!self.myPopoverController) {
        [self.navigationController dismissModalViewControllerAnimated:YES];
    } else {
        [self.myPopoverController dismissPopoverAnimated:YES];
    }
}

#pragma mark Data

- (void)saveData
{
    NSArray *fields = @[self.serverNameField, self.apiKeyField, self.apiHashField];
    BOOL valid = YES;
    for (UITextField *field in fields) {
        if (!field.text || [field.text isEqualToString:@""]) {
            field.superview.superview.backgroundColor = [UIColor bvm_fieldErrorBackgroundColor];
            valid = NO;
        } else {
            field.superview.superview.backgroundColor = [UIColor whiteColor];
        }
    }

    if (!valid) return;

    NSArray *serverNames = [BVMServersManager serverNames];
    for (NSString *name in serverNames) {
        if ([name isEqualToString:self.serverNameField.text]) {
            self.serverNameField.superview.superview.backgroundColor = [UIColor bvm_fieldErrorBackgroundColor];
            valid = NO;
        } else {
            self.serverNameField.superview.superview.backgroundColor = [UIColor whiteColor];
        }
    }

    if (!valid) return;

    [BVMServersManager saveServerName:self.serverNameField.text key:self.apiKeyField.text hash:self.apiHashField.text];

    id afterAddTarget = self.afterAddTarget;
    if (afterAddTarget && self.afterAddAction && [afterAddTarget respondsToSelector:self.afterAddAction]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [afterAddTarget performSelector:self.afterAddAction];
#pragma clang diagnostic pop
    }

    for (UITextField *field in fields) {
        field.text = nil;
    }

    [self dismiss];
}

#pragma mark ZBarReaderDelegate methods

- (void)imagePickerController:(UIImagePickerController*)reader didFinishPickingMediaWithInfo:(NSDictionary*)info
{
    [self.readerVc dismissModalViewControllerAnimated:YES];

    id<NSFastEnumeration> results = [info objectForKey:ZBarReaderControllerResults];
    ZBarSymbol *bestResult = nil;
    for (ZBarSymbol *result in results) {
        if (result.quality > bestResult.quality) bestResult = result;
    }

    self.readerVc = nil;
    self.currentReadingTextField.text = bestResult.data;
}

#pragma mark UITableViewDataSource methods

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return 3;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    BVMTextFieldTableViewCell *cell = [[BVMTextFieldTableViewCell alloc] initWithReuseIdentifier:@"Cell"];
    UITextField *tf = cell.textField;

    if (indexPath.row == BVMAddServerTableViewRowName) {
        tf.placeholder = NSLocalizedString(@"Server Name", nil);
        tf.returnKeyType = UIReturnKeyNext;
        self.serverNameField = tf;
    }
    else if (indexPath.row == BVMAddServerTableViewRowAPIKey) {
        tf.placeholder = NSLocalizedString(@"API Key", nil);
        tf.returnKeyType = UIReturnKeyNext;
        CGFloat height = [tableView.delegate tableView:tableView heightForRowAtIndexPath:indexPath];
        tf.rightView = [self buildCameraViewWithHeight:/*44*/height
                                                tapSelector:@selector(scanQRForApiKey)];
        tf.rightViewMode = UITextFieldViewModeUnlessEditing;
        self.apiKeyField = tf;
    }
    else if (indexPath.row == BVMAddServerTableViewRowAPIHash) {
        tf.placeholder = NSLocalizedString(@"API Hash", nil);
        tf.returnKeyType = UIReturnKeyDone;
        CGFloat height = [tableView.delegate tableView:tableView heightForRowAtIndexPath:indexPath];
        tf.rightView = [self buildCameraViewWithHeight:/*44*/height
                                                tapSelector:@selector(scanQRForApiHash)];
        tf.rightViewMode = UITextFieldViewModeUnlessEditing;
        self.apiHashField = tf;
    }

    tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
    tf.autocorrectionType = UITextAutocorrectionTypeNo;
    tf.delegate = self;

    return cell;
}

#pragma mark UITableViewDelegate methods

// n/a

#pragma mark UITextFieldDelegate methods

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (textField == self.serverNameField) {
        [self.apiKeyField becomeFirstResponder];
        return NO;
    }
    if (textField == self.apiKeyField) {
        [self.apiHashField becomeFirstResponder];
        return NO;
    }
    if (textField == self.apiHashField) {
        [self.apiHashField resignFirstResponder];
        [self saveData];
        return NO;
    }
    return YES;
}

#pragma mark UI Help

- (UIView *)buildCameraViewWithHeight:(CGFloat)height tapSelector:(SEL)aSelector
{
    UIImage *cameraImage = [UIImage imageNamed:@"119-Camera"];
    UIView *view = [[UIView alloc] initWithFrame:(CGRect){ CGPointZero, { cameraImage.size.width * 1.6 , height } }];

    view.userInteractionEnabled = YES;
    UITapGestureRecognizer *tapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:aSelector];
    tapRecognizer.numberOfTapsRequired = 1;
    [view addGestureRecognizer:tapRecognizer];

    UIImageView *iv = [[UIImageView alloc] initWithImage:cameraImage];
    iv.center = view.center;
    [view addSubview:iv];

    return view;
}

#pragma mark Property Overrides

- (UIView *)footerView
{
    if (!_footerView) {
        NSString *notes = NSLocalizedString(@"Server name may be anything you like.\nAPI Key and API Hash must be entered exactly as they appear in the VPS Control Panel at https://manage.buyvm.net/ clientapi.php.\nCopying these from elsewhere - an email, for example - is easiest.\nYou may scan QR codes for these fields by tapping the camera icon.", nil);
        UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(18, 0, self.view.bounds.size.width-36, 170)];
        label.textAlignment = NSTextAlignmentCenter;
        label.textColor = [UIColor bvm_darkTableViewTextColor];
        label.shadowColor = [UIColor whiteColor];
        label.shadowOffset = CGSizeMake(0, 1.0);
        label.text = notes;
        label.lineBreakMode = UILineBreakModeWordWrap;
        label.numberOfLines = 0;
        label.font = [UIFont systemFontOfSize:15.0];
        label.backgroundColor = [UIColor clearColor];
        label.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        _footerLabel = label;

        _footerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, label.bounds.size.height)];
        _footerView.backgroundColor = [UIColor clearColor];
        _footerView.autoresizesSubviews = YES;
        _footerView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [_footerView addSubview:label];
    }
    return _footerView;
}

- (ZBarReaderViewController *)readerVc
{
    if (!_readerVc) {
        _readerVc = [ZBarReaderViewController new];
        _readerVc.readerDelegate = self;
        _readerVc.cameraFlashMode = UIImagePickerControllerCameraFlashModeOff;

        [_readerVc.scanner setSymbology:0 config:ZBAR_CFG_ENABLE to:0];
        [_readerVc.scanner setSymbology:ZBAR_QRCODE config:ZBAR_CFG_ENABLE to:1];

        _readerVc.readerView.zoom = 1.0;
    }
    return _readerVc;
}

@end
