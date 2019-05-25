#import <Cephei/HBPreferences.h>
#import <MediaRemote/MediaRemote.h>
#import <Nepeta/NEPColorUtils.h>
#import <libcolorpicker.h>
#import "Tweak.h"

HBPreferences *preferences;

BOOL dpkgInvalid = false;

BOOL swapArtistAndTitle;
BOOL replaceIcons;
BOOL artworkAsBackground;
BOOL changeControlsLayout;
BOOL removeAlbumName;
BOOL hideVolumeSlider;
BOOL hideTimeLabels;
BOOL showMiddleButtonCircle;
BOOL colorizeDateAndTime;
NSInteger blurRadius = 0;
NSInteger color = 0;

NSInteger extraButtonLeft = 0;
NSInteger extraButtonRight = 0;

UIImageView *artworkView = nil;
CGFloat alpha = 1; //default 0.667

MediaControlsPanelViewController *lastController = nil;
SBFLockScreenDateView *lastDateView = nil;
SBDashBoardNotificationAdjunctListViewController *adjunctListViewController = nil;

BOOL isShuffle = 0;
int isRepeat = 0;

BOOL initialRelayout = YES;

@implementation NRDManager

+(instancetype)sharedInstance {
    static NRDManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [NRDManager alloc];
        sharedInstance.mainColor = [UIColor whiteColor];
        sharedInstance.fallbackColor = [UIColor whiteColor];
        [sharedInstance reloadColors];
    });
    return sharedInstance;
}

-(id)init {
    return [NRDManager sharedInstance];
}

-(void)reloadColors {
    NSDictionary *colors = [[NSDictionary alloc] initWithContentsOfFile:@"/var/mobile/Library/Preferences/me.nepeta.nereid-colors.plist"];
    if (!colors) return;

    if (color == 3) self.mainColor = [LCPParseColorString([colors objectForKey:@"CustomColor"], @"#ffffff:1.0") copy];
    self.fallbackColor = [LCPParseColorString([colors objectForKey:@"CustomColor"], @"#ffffff:1.0") copy];
}

@end

%group Nereid

%hook SBFLockScreenDateView

-(id)initWithFrame:(CGRect)arg1 {
    %orig;
    lastDateView = self;
    return self;
}

%new
-(void)nrdUpdate {
    if (!artworkView) return;
    
    UIColor *color = [NRDManager sharedInstance].legibilityColor;
    if (colorizeDateAndTime && artworkAsBackground && artworkView.hidden == NO) {
        color = [NRDManager sharedInstance].mainColor;
    }

    if (!color) return;

    for (id view in [self subviews]) {
        if ([view isKindOfClass:%c(SBUILegibilityLabel)]) {
            SBUILegibilityLabel *label = view;
            if (![NRDManager sharedInstance].legibilityColor) {
                [NRDManager sharedInstance].legibilityColor = label.legibilitySettings.primaryColor;
            }
            label.legibilitySettings.primaryColor = color;
            [label _updateLegibilityView];
            [label _updateLabelForLegibilitySettings];
        } else if ([view isKindOfClass:%c(SBFLockScreenDateSubtitleView)]) {
            for (id subview in [view subviews]) {
                if ([subview isKindOfClass:%c(SBUILegibilityLabel)]) {
                    SBUILegibilityLabel *label = subview;
                    if (![NRDManager sharedInstance].legibilityColor) {
                        [NRDManager sharedInstance].legibilityColor = label.legibilitySettings.primaryColor;
                    }
                    label.legibilitySettings.primaryColor = color;
                    [label _updateLegibilityView];
                    [label _updateLabelForLegibilitySettings];
                }
            }
        }
    }
}

%end

%hook SBDashBoardNotificationAdjunctListViewController

-(id)init {
    %orig;
    adjunctListViewController = self;
    return self;
}

-(void)_didUpdateDisplay {
    %orig;
    artworkView.hidden = (!artworkAsBackground || ![adjunctListViewController isShowingMediaControls]);
}

%end

%hook SBDashBoardAdjunctItemView

-(void)layoutSubviews {
    %orig;
    self.backgroundMaterialView.alpha = 0.0;
    UIView *overlayView = MSHookIvar<UIView *>(self, "_mainOverlayView");
    overlayView.alpha = 0.0;
}

%end

%hook SBMediaController

-(void)setNowPlayingInfo:(id)arg1 {
    %orig;

    if (!artworkAsBackground) return;
    MRMediaRemoteGetNowPlayingInfo(dispatch_get_main_queue(), ^(CFDictionaryRef information) {
        NSDictionary *dict = (__bridge NSDictionary *)information;

        if (dict) {
            if (dict[(__bridge NSString *)kMRMediaRemoteNowPlayingInfoArtworkData]) {
                UIImage *image = [UIImage imageWithData:[dict objectForKey:(__bridge NSString*)kMRMediaRemoteNowPlayingInfoArtworkData]];
                if (blurRadius <= 0) {
                    artworkView.image = image;
                } else {
                    artworkView.image = [image stackBlur:blurRadius];
                }

                if (color == 0 || color == 2) {
                    if (color == 2) {
                        NEPPalette *palette = [NEPColorUtils averageColors:image withAlpha:1.0];
                        [NRDManager sharedInstance].mainColor = palette.background;
                    }

                    if (color == 0) {
                        CGRect croppingRect = CGRectMake(image.size.width/2 - image.size.width/10, image.size.height/2 - image.size.height/10, image.size.width/5, image.size.height/5);
                        UIGraphicsBeginImageContextWithOptions(croppingRect.size, false, [image scale]);
                        [image drawAtPoint:CGPointMake(-croppingRect.origin.x, -croppingRect.origin.y)];
                        UIImage* croppedImage = UIGraphicsGetImageFromCurrentImageContext();
                        UIGraphicsEndImageContext();
                        UIColor *color = [NEPColorUtils averageColor:croppedImage withAlpha:1.0];

                        if ([NEPColorUtils isDark:color]) {
                            [NRDManager sharedInstance].mainColor = [UIColor whiteColor];
                        } else {
                            [NRDManager sharedInstance].mainColor = [UIColor blackColor];
                        }
                    }
                }
            }
        }

        if (color == 3) {
            [NRDManager sharedInstance].mainColor = [NRDManager sharedInstance].fallbackColor;
        }

        [lastController nrdUpdate];
        [lastDateView nrdUpdate];
    });
}

%end

%hook SBDashBoardFixedFooterViewController

-(void)viewWillAppear:(BOOL)animated {
    %orig;
    if (!artworkView) {
        artworkView = [[UIImageView alloc] initWithFrame:self.view.bounds];
        artworkView.contentMode = UIViewContentModeScaleAspectFill;
        [self.view insertSubview:artworkView atIndex:0];
        artworkView.hidden = YES;
    }
    
    artworkView.hidden = (!artworkAsBackground || ![adjunctListViewController isShowingMediaControls]);

    [lastDateView nrdUpdate];

    artworkView.frame = self.view.bounds;
}

-(void)viewDidLayoutSubviews {
    %orig;
    artworkView.frame = self.view.bounds;
}

%end

%hook MediaControlsPanelViewController

%property (nonatomic, assign) BOOL nrdEnabled;

-(void)setStyle:(NSInteger)style {
    if (style == 3) { // 0 for reachit full
        self.nrdEnabled = YES;
        self.parentContainerView.mediaControlsContainerView.nrdEnabled = YES;
        self.parentContainerView.mediaControlsContainerView.mediaControlsTimeControl.nrdEnabled = YES;
        self.parentContainerView.mediaControlsContainerView.mediaControlsTransportStackView.nrdEnabled = YES;
        self.headerView.nrdEnabled = YES;

        lastController = self;
    } else {
        self.nrdEnabled = NO;
        self.parentContainerView.mediaControlsContainerView.nrdEnabled = NO;
        self.parentContainerView.mediaControlsContainerView.mediaControlsTimeControl.nrdEnabled = NO;
        self.parentContainerView.mediaControlsContainerView.mediaControlsTransportStackView.nrdEnabled = NO;
        self.headerView.nrdEnabled = NO;
    }

    %orig;
}

%new
-(void)nrdUpdate {
    if (!self.nrdEnabled) return;

    [self.parentContainerView.mediaControlsContainerView nrdUpdate];
    [self.parentContainerView.mediaControlsContainerView.mediaControlsTimeControl nrdUpdate];
    [self.parentContainerView.mediaControlsContainerView.mediaControlsTransportStackView nrdUpdate];
    [self.headerView nrdUpdate];
}

-(void)viewWillLayoutSubviews {
    %orig;
    self.volumeContainerView.hidden = (self.nrdEnabled && hideVolumeSlider);
}

-(void)viewWillAppear:(BOOL)animated {
    %orig;
    if (artworkView) artworkView.hidden = !(self.nrdEnabled && artworkAsBackground);
    [lastDateView nrdUpdate];
    [self.parentContainerView setNeedsLayout];
    [self.parentContainerView layoutIfNeeded];
}

-(void)viewDidAppear:(BOOL)animated {
    %orig;
    [self.parentContainerView setNeedsLayout];
    [self.parentContainerView layoutIfNeeded];
    [self.parentContainerView.mediaControlsContainerView setNeedsLayout];
    [self.parentContainerView.mediaControlsContainerView layoutIfNeeded];
    [self.parentContainerView.mediaControlsContainerView.mediaControlsTransportStackView setNeedsLayout];
    [self.parentContainerView.mediaControlsContainerView.mediaControlsTransportStackView layoutIfNeeded];
}

-(void)viewWillDisppear:(BOOL)animated {
    %orig;
    if (artworkView) artworkView.hidden = YES;
    [lastDateView nrdUpdate];
}

%end

%hook MediaControlsContainerView

%property (nonatomic, assign) BOOL nrdEnabled;

-(void)layoutSubviews {
    %orig;
    /*if (!self.nrdEnabled || !changeControlsLayout) return;

    CGRect frame = self.mediaControlsTransportStackView.frame;
    CGFloat width = 220;
    if (replaceIcons) width = 180;
    self.mediaControlsTransportStackView.frame = CGRectMake(frame.origin.x + frame.size.width/2.0 - width/2.0, frame.origin.y, width, frame.size.height);*/
}

%new
-(void)nrdUpdate {

}

%end

%hook MediaControlsHeaderView

%property (nonatomic, assign) BOOL nrdEnabled;

-(void)setSecondaryString:(NSString *)arg1 {
    if (self.nrdEnabled && removeAlbumName && [arg1 containsString:@" — "]) {
        NSArray *split = [arg1 componentsSeparatedByString:@" — "];
        arg1 = split[0];
    }

    %orig;
}

-(void)_updateStyle {
    %orig;
    [self nrdUpdate];
}

-(CGSize)layoutTextInAvailableBounds:(CGRect)arg1 setFrames:(BOOL)arg2 {
    CGSize orig = %orig;
    [self nrdUpdate];
    return orig;
}

-(void)layoutSubviews {
    %orig;
    if (!self.nrdEnabled) return;
    
    /* Remove routing stuff */
    [self.routingButton removeFromSuperview];
    [self.routeLabel removeFromSuperview];

    /* Remove artwork view */
    [self.artworkView removeFromSuperview];
    [self.placeholderArtworkView removeFromSuperview];
    if ([self respondsToSelector:@selector(artworkBackgroundView)]) [self.artworkBackgroundView removeFromSuperview];
    if ([self respondsToSelector:@selector(artworkBackground)]) [self.artworkBackground removeFromSuperview];
    [self.shadow removeFromSuperview];

    /* Remove scrolling text */
    [self.primaryMarqueeView removeFromSuperview];
    [self.secondaryMarqueeView removeFromSuperview];
    [self.primaryLabel removeFromSuperview];
    [self.secondaryLabel removeFromSuperview];

    self.primaryLabel.textAlignment = NSTextAlignmentCenter;
    self.secondaryLabel.textAlignment = NSTextAlignmentCenter;

    self.primaryLabel.frame = CGRectMake(0, self.primaryMarqueeView.frame.origin.y, self.bounds.size.width, self.primaryMarqueeView.frame.size.height);
    self.secondaryLabel.frame = CGRectMake(0, self.secondaryMarqueeView.frame.origin.y, self.bounds.size.width, self.secondaryMarqueeView.frame.size.height);

    if (swapArtistAndTitle) {
        CGRect temp = self.primaryLabel.frame;
        self.primaryLabel.frame = self.secondaryLabel.frame;
        self.secondaryLabel.frame = temp;
    }

    [self addSubview:self.primaryLabel];
    [self addSubview:self.secondaryLabel];

    [self nrdUpdate];
}

-(void)didMoveToWindow {
    %orig;
    [self nrdUpdate];
}

%new
-(void)nrdUpdate {
    if (!self.nrdEnabled) return;
    self.secondaryLabel.font = [UIFont systemFontOfSize:13];

    if (color == 1) return;
    self.primaryLabel.layer.compositingFilter = nil;
    self.primaryLabel.alpha = alpha;
    self.primaryLabel.textColor = [[NRDManager sharedInstance].mainColor copy];

    self.secondaryLabel.layer.compositingFilter = nil;
    self.secondaryLabel.alpha = alpha;
    self.secondaryLabel.textColor = [[NRDManager sharedInstance].mainColor copy];
}

%end

%hook MediaControlsTimeControl

%property (nonatomic, assign) BOOL nrdEnabled;

-(void)layoutSubviews {
    %orig;
    if (!self.nrdEnabled || color == 1) return;

    [self nrdUpdate];

    self.elapsedTimeLabel.hidden = hideTimeLabels;
    self.remainingTimeLabel.hidden = hideTimeLabels;
}

%new
-(void)nrdUpdate {
    self.elapsedTrack.layer.compositingFilter = nil;
    self.remainingTrack.layer.compositingFilter = nil;
    self.knobView.layer.compositingFilter = nil;
    self.elapsedTimeLabel.layer.compositingFilter = nil;
    self.remainingTimeLabel.layer.compositingFilter = nil;

    [self.elapsedTrack setBackgroundColor:[[NRDManager sharedInstance].mainColor copy]];
    [self.remainingTrack setBackgroundColor:[[NRDManager sharedInstance].mainColor copy]];
    [self.knobView setBackgroundColor:[[NRDManager sharedInstance].mainColor copy]];
    [self.elapsedTimeLabel setTextColor:[[NRDManager sharedInstance].mainColor copy]];
    [self.remainingTimeLabel setTextColor:[[NRDManager sharedInstance].mainColor copy]];
}

%end

%hook MediaControlsTransportStackView

%property (nonatomic, retain) MediaControlsTransportButton * nrdLeftButton;
%property (nonatomic, retain) MediaControlsTransportButton * nrdRightButton;
%property (nonatomic, retain) UIView * nrdCircleView;
%property (nonatomic, assign) BOOL nrdEnabled;

-(void)layoutSubviews {
    %orig;
    if (!self.nrdEnabled) {
        if (self.nrdCircleView) self.nrdCircleView.hidden = YES;
        return;
    }

    self.layer.masksToBounds = NO;
    self.clipsToBounds = NO;

    if (!self.nrdCircleView) {
        self.nrdCircleView = [[UIView alloc] initWithFrame:CGRectMake(0,0,58,58)];
        self.nrdCircleView.layer.cornerRadius = 28;
        self.nrdCircleView.layer.borderWidth = 2.0f;
        self.nrdCircleView.layer.borderColor = [NRDManager sharedInstance].mainColor.CGColor;

        [self addSubview:self.nrdCircleView];
        [self sendSubviewToBack:self.nrdCircleView];
    }

    if (!self.nrdLeftButton) {
        self.nrdLeftButton = [[%c(MediaControlsTransportButton) alloc] initWithFrame:self.middleButton.frame];
        self.nrdLeftButton.imageEdgeInsets = UIEdgeInsetsMake(2.5f, 5.0f, 2.5f, 5.0f);
        self.nrdLeftButton.imageView.contentMode = UIViewContentModeScaleAspectFit;
        [self.nrdLeftButton addTarget:self action:@selector(nrdLeftButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:self.nrdLeftButton];
    }

    if (!self.nrdRightButton) {
        self.nrdRightButton = [[%c(MediaControlsTransportButton) alloc] initWithFrame:self.middleButton.frame];
        self.nrdRightButton.imageEdgeInsets = UIEdgeInsetsMake(2.5f, 5.0f, 2.5f, 5.0f);
        self.nrdRightButton.imageView.contentMode = UIViewContentModeScaleAspectFit;
        [self.nrdRightButton addTarget:self action:@selector(nrdRightButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:self.nrdRightButton];
    }

    self.nrdLeftButton.hidden = extraButtonLeft == 0;
    self.nrdRightButton.hidden = extraButtonRight == 0;

    [self _updateButtonImage:nil button:self.nrdLeftButton];
    [self _updateButtonImage:nil button:self.nrdRightButton];

    self.nrdCircleView.frame = CGRectMake(self.middleButton.frame.origin.x + self.middleButton.frame.size.width/2 - 28,
                                            self.middleButton.frame.origin.y + self.middleButton.frame.size.height/2 - 28,
                                            56, 56);

    self.nrdCircleView.hidden = !showMiddleButtonCircle;
    
    self.leftButton.imageEdgeInsets = UIEdgeInsetsMake(2.5f, 5.0f, 2.5f, 5.0f);

    self.middleButton.imageView.contentMode = UIViewContentModeScaleAspectFit;
    self.middleButton.imageEdgeInsets = UIEdgeInsetsMake(5.0f, 5.0f, 5.0f, 5.0f);

    self.rightButton.imageEdgeInsets = UIEdgeInsetsMake(2.5f, 5.0f, 2.5f, 5.0f);

    self.leftButton.frame = CGRectMake(self.nrdCircleView.frame.origin.x - self.leftButton.frame.size.width * 2.0, self.leftButton.frame.origin.y, self.leftButton.frame.size.width, self.leftButton.frame.size.height);
    self.rightButton.frame = CGRectMake(self.nrdCircleView.frame.origin.x + self.nrdCircleView.frame.size.width + self.rightButton.frame.size.width, self.rightButton.frame.origin.y, self.rightButton.frame.size.width, self.rightButton.frame.size.height);

    self.nrdLeftButton.frame = CGRectMake(self.nrdCircleView.frame.origin.x - self.leftButton.frame.size.width * 2.0 - self.nrdLeftButton.frame.size.width * 1.5, self.middleButton.frame.origin.y, self.nrdLeftButton.frame.size.width, self.nrdLeftButton.frame.size.height);
    self.nrdRightButton.frame = CGRectMake(self.nrdCircleView.frame.origin.x + self.nrdCircleView.frame.size.width + self.rightButton.frame.size.width * 2.0 + self.nrdRightButton.frame.size.width * 0.5, self.middleButton.frame.origin.y, self.nrdRightButton.frame.size.width, self.nrdRightButton.frame.size.height);

    [self nrdUpdate];
}

-(void)buttonHoldBegan:(MediaControlsTransportButton *)button {
    %orig;
    if (!self.nrdEnabled || color == 1) return;
    [button setTintColor:[[NRDManager sharedInstance].mainColor copy]];
}

-(void)buttonHoldReleased:(MediaControlsTransportButton *)button {
    %orig;
    if (!self.nrdEnabled || color == 1) return;
    [button setTintColor:[[NRDManager sharedInstance].mainColor copy]];
}

-(void)_updateButtonImage:(UIImage *)image button:(MediaControlsTransportButton *)button {
    if (self.nrdEnabled && ((replaceIcons && !button.shouldPresentActionSheet) || button == self.nrdLeftButton || button == self.nrdRightButton)) {
        UIImage *newImage = nil;
        if (button == self.leftButton) {
            newImage = [[UIImage imageWithContentsOfFile:@"/Library/Nereid/back.png"]
                            imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        } else if (button == self.rightButton) {
            newImage = [[UIImage imageWithContentsOfFile:@"/Library/Nereid/forward.png"]
                            imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        } else if (button == self.nrdLeftButton) {
            switch (extraButtonLeft) {
                case 1:
                    newImage = [[UIImage imageWithContentsOfFile:@"/Library/Nereid/shuffle.png"]
                                    imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
                    break;
                case 2:
                    if (isRepeat == 2 || isRepeat == 0) {
                        newImage = [[UIImage imageWithContentsOfFile:@"/Library/Nereid/repeat.png"]
                                        imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
                    } else {
                        newImage = [[UIImage imageWithContentsOfFile:@"/Library/Nereid/repeatonce.png"]
                                        imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
                    }
                    break;
                case 3:
                    newImage = [[UIImage imageWithContentsOfFile:@"/Library/Nereid/back15.png"]
                                    imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
                    break;
            }
        } else if (button == self.nrdRightButton) {
            switch (extraButtonRight) {
                case 1:
                    newImage = [[UIImage imageWithContentsOfFile:@"/Library/Nereid/shuffle.png"]
                                    imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
                    break;
                case 2:
                    if (isRepeat == 2 || isRepeat == 0) {
                        newImage = [[UIImage imageWithContentsOfFile:@"/Library/Nereid/repeat.png"]
                                        imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
                    } else {
                        newImage = [[UIImage imageWithContentsOfFile:@"/Library/Nereid/repeatonce.png"]
                                        imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
                    }
                    break;
                case 3:
                    newImage = [[UIImage imageWithContentsOfFile:@"/Library/Nereid/forward15.png"]
                                    imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
                    break;
            }
        }
        
        if (newImage) {
            CGFloat height = self.middleButton.imageView.frame.size.height;
            CGFloat ratio = height/(newImage.size.height);
            CGFloat width = newImage.size.width * ratio;
            CGSize newSize = CGSizeMake(width, height);

            UIGraphicsBeginImageContextWithOptions(newSize, NO, 0.0);
            [newImage drawInRect:CGRectMake(0, 0, newSize.width, newSize.height)];
            image = UIGraphicsGetImageFromCurrentImageContext();    
            UIGraphicsEndImageContext();
        }
    }
 
    %orig;
    if (!self.nrdEnabled || color == 1) return;
    button.imageView.alpha = alpha;
    button.imageView.layer.filters = nil;
    button.imageView.layer.compositingFilter = nil;
    [button setTintColor:[[NRDManager sharedInstance].mainColor copy]];
}

-(void)_updateButtonBlendMode:(MediaControlsTransportButton *)button {
    if (!self.nrdEnabled || color == 1) %orig;
    button.imageView.alpha = alpha;
    button.imageView.layer.filters = nil;
    button.imageView.layer.compositingFilter = nil;
    [button setTintColor:[[NRDManager sharedInstance].mainColor copy]];
}

%new
-(void)nrdLeftButtonPressed:(id)sender {
    switch (extraButtonLeft) {
        case 1:
            MRMediaRemoteSendCommand(MRMediaRemoteCommandAdvanceShuffleMode, nil);
            break;
        case 2:
            MRMediaRemoteSendCommand(MRMediaRemoteCommandAdvanceRepeatMode, nil);
            break;
        case 3:
            MRMediaRemoteGetNowPlayingInfo(dispatch_get_main_queue(), ^(CFDictionaryRef information) {
                NSDictionary *dict = (__bridge NSDictionary *)information;

                if (dict && dict[(__bridge NSString *)kMRMediaRemoteNowPlayingInfoElapsedTime]) {
                    int elapsedTime = [dict[(__bridge NSString *)kMRMediaRemoteNowPlayingInfoElapsedTime] intValue];
                    MRMediaRemoteSetElapsedTime(elapsedTime - 15);
                }
            });
            break;
    }
}

%new
-(void)nrdRightButtonPressed:(id)sender {
    switch (extraButtonRight) {
        case 1:
            MRMediaRemoteSendCommand(MRMediaRemoteCommandAdvanceShuffleMode, nil);
            break;
        case 2:
            MRMediaRemoteSendCommand(MRMediaRemoteCommandAdvanceRepeatMode, nil);
            break;
        case 3:
            MRMediaRemoteGetNowPlayingInfo(dispatch_get_main_queue(), ^(CFDictionaryRef information) {
                NSDictionary *dict = (__bridge NSDictionary *)information;

                if (dict && dict[(__bridge NSString *)kMRMediaRemoteNowPlayingInfoElapsedTime]) {
                    int elapsedTime = [dict[(__bridge NSString *)kMRMediaRemoteNowPlayingInfoElapsedTime] intValue];
                    MRMediaRemoteSetElapsedTime(elapsedTime + 15);
                }
            });
            break;
    }
}

%new
-(void)nrdUpdate {
    if (color != 1) {
        self.leftButton.imageView.layer.filters = nil;
        self.leftButton.imageView.layer.compositingFilter = nil;
        self.leftButton.imageView.alpha = alpha;
        [self.leftButton.imageView setTintColor:[[NRDManager sharedInstance].mainColor copy]];

        self.middleButton.imageView.layer.filters = nil;
        self.middleButton.imageView.layer.compositingFilter = nil;
        self.middleButton.imageView.alpha = alpha;
        self.middleButton.imageView.contentMode = UIViewContentModeScaleAspectFit;
        [self.middleButton.imageView setTintColor:[[NRDManager sharedInstance].mainColor copy]];

        self.rightButton.imageView.layer.filters = nil;
        self.rightButton.imageView.layer.compositingFilter = nil;
        self.rightButton.imageView.alpha = alpha;
        [self.rightButton.imageView setTintColor:[[NRDManager sharedInstance].mainColor copy]];

        if (self.nrdCircleView) {
            self.nrdCircleView.layer.borderColor = self.middleButton.imageView.tintColor.CGColor;
            self.nrdCircleView.alpha = self.middleButton.imageView.alpha;
        }
    }

    isShuffle = NO;
    isRepeat = 0;
    MPCPlayerResponseTracklist *tracklist;

    if ([lastController respondsToSelector:@selector(response)]) {
        tracklist = [[lastController response] tracklist];
    } else if ([lastController respondsToSelector:@selector(endpointController)]) {
        tracklist = [[[lastController endpointController] response] tracklist];
    }
    
    isRepeat = [tracklist repeatType];
    isShuffle = [tracklist shuffleType];

    if (self.nrdLeftButton) {
        [self.nrdLeftButton.imageView setTintColor:[self.middleButton.imageView.tintColor copy]];
        self.nrdLeftButton.imageView.alpha = 1.0;
        if ((extraButtonLeft == 1 && !isShuffle) || (extraButtonLeft == 2 && isRepeat == 0)) {
            self.nrdLeftButton.imageView.alpha = 0.5;
        }
    }

    if (self.nrdRightButton) {
        [self.nrdRightButton.imageView setTintColor:[self.middleButton.imageView.tintColor copy]];
        if ((extraButtonRight == 1 && !isShuffle) || (extraButtonRight == 2 && isRepeat == 0)) {
            self.nrdRightButton.imageView.alpha = 0.5;
        }
    }
}

%end

%end

%group NereidIntegrityFail

%hook SpringBoard

-(void)applicationDidFinishLaunching:(id)arg1 {
    %orig;
    if (!dpkgInvalid) return;
    UIAlertController *alertController = [UIAlertController
        alertControllerWithTitle:@"😡😡😡"
        message:@"The build of Nereid you're using comes from an untrusted source. Pirate repositories can distribute malware and you will get subpar user experience using any tweaks from them.\nRemember: Nereid is free. Uninstall this build and install the proper version of Nereid from:\nhttps://repo.nepeta.me/\n(it's free, damnit, why would you pirate that!?)"
        preferredStyle:UIAlertControllerStyleAlert
    ];

    [alertController addAction:[UIAlertAction actionWithTitle:@"Damn!" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [((UIApplication*)self).keyWindow.rootViewController dismissViewControllerAnimated:YES completion:NULL];
    }]];

    [((UIApplication*)self).keyWindow.rootViewController presentViewController:alertController animated:YES completion:NULL];
}

%end

%end

void reloadColors() {
    [[NRDManager sharedInstance] reloadColors];
}

%ctor {
    dpkgInvalid = ![[NSFileManager defaultManager] fileExistsAtPath:@"/var/lib/dpkg/info/me.nepeta.nereid.list"];

    if (dpkgInvalid) {
        %init(NereidIntegrityFail);
        return;
    }
    
    preferences = [[HBPreferences alloc] initWithIdentifier:@"me.nepeta.nereid"];
    
    [preferences registerBool:&artworkAsBackground default:YES forKey:@"ArtworkAsBackground"];
    [preferences registerBool:&changeControlsLayout default:YES forKey:@"ChangeControlsLayout"];
    [preferences registerBool:&removeAlbumName default:YES forKey:@"RemoveAlbumName"];
    [preferences registerBool:&hideVolumeSlider default:YES forKey:@"HideVolumeSlider"];
    [preferences registerBool:&hideTimeLabels default:YES forKey:@"HideTimeLabels"];
    [preferences registerBool:&showMiddleButtonCircle default:YES forKey:@"ShowMiddleButtonCircle"];
    [preferences registerBool:&replaceIcons default:YES forKey:@"ReplaceIcons"];
    [preferences registerBool:&colorizeDateAndTime default:YES forKey:@"ColorizeDateAndTime"];
    [preferences registerBool:&swapArtistAndTitle default:NO forKey:@"SwapArtistAndTitle"];
    [preferences registerInteger:&extraButtonLeft default:0 forKey:@"ExtraButtonLeft"];
    [preferences registerInteger:&extraButtonRight default:0 forKey:@"ExtraButtonRight"];
    [preferences registerInteger:&blurRadius default:0 forKey:@"BlurRadius"];
    [preferences registerInteger:&color default:0 forKey:@"Color"];

    %init(Nereid);

    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)reloadColors, (CFStringRef)@"me.nepeta.flashyhud/ReloadColors", NULL, (CFNotificationSuspensionBehavior)kNilOptions);
}
