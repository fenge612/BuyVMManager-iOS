#import "BVMEmptyDetailViewController.h"
#import "BVMServersManager.h"
#import "UIColor+BVMColors.h"

@interface BVMEmptyDetailViewController ()

@property (weak, nonatomic) IBOutlet UILabel *textLabel;

@end

@implementation BVMEmptyDetailViewController

- (id)init
{
    self = [super initWithNibName:@"BVMEmptyDetailViewController" bundle:[NSBundle mainBundle]];
    if (self) { }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.textLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;

    if ([BVMServersManager servers].count == 0) {
        self.textLabel.numberOfLines = 0;
        self.textLabel.text = NSLocalizedString(@"Tap the \"+\" button to add a VM.\n(If there's no \"+\" button, tap \"Edit\".)", nil);

        CGRect labelFrame = self.textLabel.frame;
        labelFrame.size.height *= 3;
        self.textLabel.frame = labelFrame;
    }
}

@end
