#import <UIKit/UIKit.h>

CFStringRef kPrefsAppID = CFSTR("applebetas.ios.tweak.craigmode");

#define kCraigModeOnImagePath @"/Library/Application Support/CraigMode/CraigOn.png"
#define kCraigModeOffImagePath @"/Library/Application Support/CraigMode/CraigOff.png"

#define kVolumeUpButtonType 102
#define kVolumeDownButtonType 103

static NSTimeInterval lastVolumeUpPressTime = -1;
static NSTimeInterval lastVolumeDownPressTime = -1;
static BOOL volumeUpPressed = NO;
static BOOL volumeDownPressed = NO;

@interface SBHUDController : NSObject
+ (instancetype)sharedHUDController;
- (void)presentHUDView:(id)arg1 autoDismissWithDelay:(double)arg2;
@end

@interface SBVolumeHardwareButton : NSObject
-(void)removeVolumePressBandit:(id)arg1;
@end

@interface SBPrototypeController : NSObject
@property (nonatomic,retain) id activeTestRecipe;
@property (assign,nonatomic) SBVolumeHardwareButton * volumeHardwareButton;
+ (instancetype)sharedInstance;
- (void)_installVolumeBanditIfNeeded;
- (void)_updateEventRouters;
- (void)setActiveTestRecipe:(id)arg1;
@end

@interface SBPrototypeController (CraigMode)
- (void)onCraigModeEnabledChanged;
@end

@interface SBHUDView : UIView
- (id)initWithHUDViewLevel:(int)arg1;
@property (nonatomic,retain) NSString * title;
@property (nonatomic,retain) NSString * subtitle;
@property (nonatomic,retain) UIImage * image;
@end

@interface DDCraigModeHUDView : SBHUDView
@property (nonatomic, retain) UIImageView *imageView;
@end

%subclass DDCraigModeHUDView : SBHUDView
%property (nonatomic, retain) UIImageView *imageView;

- (id)initWithHUDViewLevel:(int)arg1 {
    self = %orig;
    if (self) {
        self.imageView = [[UIImageView alloc] initWithFrame:self.bounds];
        self.imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.imageView.contentMode = UIViewContentModeCenter;
        [self addSubview:self.imageView];
    }
    return self;
}

- (void)setImage:(UIImage *)image {
    self.imageView.image = image;
}

%end

@interface SpringBoard : UIApplication
@end

%hook SBVolumeHardwareButton

- (void)_handleVolumeButtonWithType:(long long)buttonType down:(BOOL)down {
    %orig;
    switch (buttonType) {
    case kVolumeUpButtonType:
        volumeUpPressed = down;
        lastVolumeUpPressTime = CACurrentMediaTime();
        break;
    case kVolumeDownButtonType:
        volumeDownPressed = down;
        lastVolumeDownPressTime = CACurrentMediaTime();
        break;
    }
    NSTimeInterval delta = fabs(lastVolumeUpPressTime - lastVolumeDownPressTime);
    if (delta < 0.03f && lastVolumeUpPressTime != -1 && lastVolumeDownPressTime != -1 && (volumeDownPressed || volumeUpPressed)) {
        // Toggle status
        BOOL oldEnabled = [[[%c(SBPrototypeController) sharedInstance] valueForKey:@"_isEnabled"] boolValue];
        [[%c(SBPrototypeController) sharedInstance] setValue:@(!oldEnabled) forKey:@"_isEnabled"];
        BOOL enabled = [[[%c(SBPrototypeController) sharedInstance] valueForKey:@"_isEnabled"] boolValue];
        [[%c(SBPrototypeController) sharedInstance] onCraigModeEnabledChanged];

        // Save status
        NSDictionary *dict = [NSDictionary dictionaryWithObject:@(enabled) forKey:@"Enabled"];
        CFPreferencesSetMultiple((__bridge CFDictionaryRef)dict, nil, kPrefsAppID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        CFPreferencesAppSynchronize(kPrefsAppID);

        // Show status HUD
        DDCraigModeHUDView *hud = [[%c(DDCraigModeHUDView) alloc] initWithHUDViewLevel:0];
        hud.image = [[UIImage alloc] initWithContentsOfFile:enabled ? kCraigModeOnImagePath : kCraigModeOffImagePath];
        hud.title = [NSString stringWithFormat:@"Craig Mode %@", enabled ? @"On" : @"Off"];
        hud.subtitle = enabled ? @"Press volume up" : @"Again, innovation";
        [[%c(SBHUDController) sharedHUDController] presentHUDView:hud autoDismissWithDelay:3];

        // Forget last press times
        lastVolumeUpPressTime = -1;
        lastVolumeDownPressTime = -1;
    }
}

%end

%hook SBPrototypeController

- (BOOL)isPrototypingEnabled {
    return YES;
}

%new
- (void)onCraigModeEnabledChanged {
    if(self.activeTestRecipe) [self.volumeHardwareButton removeVolumePressBandit:self.activeTestRecipe];
    [self _installVolumeBanditIfNeeded];
    [self _updateEventRouters];
    [self setActiveTestRecipe:self.activeTestRecipe];
}

%end

%hook SBPrototypeControllerSettings

-(void)setTestRecipeClassName:(NSString *)arg1 {
    %orig;
    [[%c(SBPrototypeController) sharedInstance] onCraigModeEnabledChanged];
}

%end

static BOOL shouldBeEnabled = YES;

%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)arg1 {
    %orig;
    [[%c(SBPrototypeController) sharedInstance] onCraigModeEnabledChanged];
}

%end

%ctor {
    // Load last enabled state from preferences
    shouldBeEnabled = YES;
    NSDictionary *settings = nil;
    CFPreferencesAppSynchronize(kPrefsAppID);
    CFArrayRef keyList = CFPreferencesCopyKeyList(kPrefsAppID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (keyList) {
        settings = (NSDictionary *)CFBridgingRelease(CFPreferencesCopyMultiple(keyList, kPrefsAppID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
        CFRelease(keyList);
    }
    if (settings && settings[@"Enabled"]) shouldBeEnabled = [settings[@"Enabled"] boolValue];
    [[%c(SBPrototypeController) sharedInstance] setValue:@(shouldBeEnabled) forKey:@"_isEnabled"];
}
