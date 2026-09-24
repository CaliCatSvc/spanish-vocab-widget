#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CoreGraphics.h>
#import <AVFoundation/AVFoundation.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include <unistd.h>

@interface DesktopPanel : NSPanel
@end
@implementation DesktopPanel
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return NO; }
@end

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property DesktopPanel *panel;
@property NSTextField *flagLabel;
@property NSTextField *wordLabel;
@property NSButton *previousButton;
@property NSButton *nextButton;
@property NSView *backgroundView;
@property NSWindow *settingsWindow;
@property NSButton *autoSizeCheckbox;
@property NSPopUpButton *fontPopup;
@property NSSlider *fontSizeSlider;
@property NSTextField *fontSizeValue;
@property NSPopUpButton *weightPopup;
@property NSColorWell *textColorWell;
@property NSColorWell *backgroundColorWell;
@property NSSlider *opacitySlider;
@property NSStatusItem *statusItem;
@property NSMenuItem *pauseMenuItem;
@property NSMenuItem *showMenuItem;
@property NSMenuItem *pronunciationMenuItem;
@property NSMutableArray<NSMenuItem *> *intervalItems;
@property NSMutableArray<NSMenuItem *> *orderItems;
@property NSMutableArray<NSMenuItem *> *voiceItems;
@property NSArray<NSDictionary *> *entries;
@property NSMutableArray<NSNumber *> *deck;
@property NSInteger deckPosition;
@property NSInteger currentIndex;
@property NSMutableArray<NSNumber *> *history;
@property NSInteger historyPosition;
@property BOOL paused;
@property NSInteger intervalMinutes;
@property NSTimer *timer;
@property AVSpeechSynthesizer *speechSynthesizer;
@property NSMenuItem *registrationMenuItem;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    NSURL *iconURL = [NSBundle.mainBundle URLForResource:@"MexicanFlagIcon-1200" withExtension:@"png"];
    if (iconURL) NSApp.applicationIconImage = [[NSImage alloc] initWithContentsOfURL:iconURL];
    self.currentIndex = -1;
    self.speechSynthesizer = [AVSpeechSynthesizer new];
    self.history = [NSMutableArray array];
    self.historyPosition = -1;
    NSInteger saved = [[NSUserDefaults standardUserDefaults] integerForKey:@"intervalMinutes"];
    self.intervalMinutes = [@[@1,@3,@5,@10,@15] containsObject:@(saved)] ? saved : 5;
    [self registerAppearanceDefaults];
    [self loadVocabulary];
    [self buildPanel];
    [self buildStatusMenu];
    [self initializeShareware];
    [self refillDeck];
    [self showNextWord];
    [self scheduleTimer];
    [self.panel orderFrontRegardless];
}

- (void)registerAppearanceDefaults {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        @"autoSize": @YES,
        @"fontName": @"System",
        @"fontSize": @13.0,
        @"fontWeight": @"Semibold",
        @"textColor": @"#1F1F1FFF",
        @"backgroundColor": @"#E7E7E7FF",
        @"backgroundOpacity": @0.94,
        @"wordOrder": @"random",
        @"showPronunciation": @NO,
        @"spanishVoiceIdentifier": @""
    }];
}

- (NSString *)appName { return [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleDisplayName"] ?: @"Spanish Vocab Widget"; }
- (NSString *)vocabularyFolderName { return [NSBundle.mainBundle objectForInfoDictionaryKey:@"VocabularyFolderName"] ?: [self appName]; }

- (NSURL *)editableVocabularyURL {
    NSURL *documents = [[[NSFileManager defaultManager] homeDirectoryForCurrentUser] URLByAppendingPathComponent:@"Documents" isDirectory:YES];
    return [[documents URLByAppendingPathComponent:[self vocabularyFolderName] isDirectory:YES] URLByAppendingPathComponent:@"Vocabulary.csv"];
}

- (void)prepareEditableVocabulary {
    NSURL *target = [self editableVocabularyURL];
    [[NSFileManager defaultManager] createDirectoryAtURL:[target URLByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];
    if (![[NSFileManager defaultManager] fileExistsAtPath:target.path]) {
        NSURL *source = [[NSBundle mainBundle] URLForResource:@"Vocabulary" withExtension:@"csv"];
        if (source) [[NSFileManager defaultManager] copyItemAtURL:source toURL:target error:nil];
    }
}

- (NSArray<NSArray<NSString *> *> *)parseCSV:(NSString *)text {
    NSMutableArray *records = [NSMutableArray array];
    NSMutableArray *row = [NSMutableArray array];
    NSMutableString *field = [NSMutableString string];
    BOOL quoted = NO;
    for (NSUInteger i = 0; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        if (quoted) {
            if (c == '"') {
                if (i + 1 < text.length && [text characterAtIndex:i + 1] == '"') {
                    [field appendString:@"\""];
                    i++;
                } else {
                    quoted = NO;
                }
            } else {
                [field appendFormat:@"%C", c];
            }
        } else if (c == '"') {
            quoted = YES;
        } else if (c == ',') {
            [row addObject:[field copy]];
            [field setString:@""];
        } else if (c == '\n') {
            NSString *clean = [field stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\r"]];
            [row addObject:clean];
            BOOL hasValue = NO;
            for (NSString *value in row) if (value.length) { hasValue = YES; break; }
            if (hasValue) [records addObject:[row copy]];
            [row removeAllObjects];
            [field setString:@""];
        } else {
            [field appendFormat:@"%C", c];
        }
    }
    if (field.length || row.count) {
        [row addObject:[field copy]];
        [records addObject:[row copy]];
    }
    return records;
}

- (NSString *)normalized:(NSString *)value {
    return [[[value stringByFoldingWithOptions:(NSDiacriticInsensitiveSearch | NSCaseInsensitiveSearch) locale:[NSLocale currentLocale]]
             stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
}

- (void)loadVocabulary {
    [self prepareEditableVocabulary];
    NSError *error = nil;
    NSString *text = [NSString stringWithContentsOfURL:[self editableVocabularyURL] encoding:NSUTF8StringEncoding error:&error];
    NSArray *records = text ? [self parseCSV:text] : @[];
    if (records.count < 2) { [self fatalError:@"The vocabulary file has no usable entries."]; return; }
    NSArray *header = records[0];
    NSMutableDictionary *columns = [NSMutableDictionary dictionary];
    for (NSUInteger i = 0; i < header.count; i++) columns[[self normalized:header[i]]] = @(i);
    for (NSString *required in @[@"spanish", @"english"]) {
        if (!columns[required]) { [self fatalError:@"Vocabulary.csv must include Spanish and English columns."]; return; }
    }
    NSMutableArray *loaded = [NSMutableArray array];
    for (NSUInteger r = 1; r < records.count; r++) {
        NSArray *row = records[r];
        NSInteger si = [columns[@"spanish"] integerValue], ei = [columns[@"english"] integerValue];
        NSInteger ri = columns[@"room"] ? [columns[@"room"] integerValue] : -1;
        NSInteger ci = columns[@"category"] ? [columns[@"category"] integerValue] : -1;
        NSInteger pi = columns[@"pronunciation"] ? [columns[@"pronunciation"] integerValue] : -1;
        NSInteger ni = columns[@"notes"] ? [columns[@"notes"] integerValue] : -1;
        if (row.count <= MAX(si, ei)) continue;
        NSString *spanish = [row[si] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *english = [row[ei] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!spanish.length || !english.length) continue;
        NSString *room = ri >= 0 && row.count > ri ? row[ri] : @"";
        NSString *category = ci >= 0 && row.count > ci ? row[ci] : @"";
        NSString *pronunciation = pi >= 0 && row.count > pi ? row[pi] : @"";
        [loaded addObject:@{@"spanish":spanish, @"english":english, @"pronunciation":pronunciation, @"room":room, @"category":category, @"note":(ni >= 0 && row.count > ni ? row[ni] : @"")}];
    }
    if (!loaded.count) { [self fatalError:@"The vocabulary file has no usable entries."]; return; }
    self.entries = loaded;
}

- (NSTextField *)labelWithSize:(CGFloat)size weight:(NSFontWeight)weight color:(NSColor *)color {
    NSTextField *field = [NSTextField labelWithString:@""];
    field.font = [NSFont systemFontOfSize:size weight:weight];
    field.textColor = color;
    field.selectable = YES;
    field.translatesAutoresizingMaskIntoConstraints = NO;
    return field;
}

- (void)buildPanel {
    NSSize size = NSMakeSize(200, 40);
    NSScreen *screen = NSScreen.mainScreen;
    NSRect visible = screen ? screen.visibleFrame : NSMakeRect(40, 40, 900, 700);
    NSPoint origin = NSMakePoint(NSMaxX(visible) - size.width - 28, NSMaxY(visible) - size.height - 28);
    self.panel = [[DesktopPanel alloc] initWithContentRect:NSMakeRect(origin.x, origin.y, size.width, size.height)
                                                 styleMask:(NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel)
                                                   backing:NSBackingStoreBuffered defer:NO];
    self.panel.opaque = NO;
    self.panel.backgroundColor = NSColor.clearColor;
    self.panel.hasShadow = YES;
    self.panel.movableByWindowBackground = YES;
    self.panel.hidesOnDeactivate = NO;
    self.panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorStationary | NSWindowCollectionBehaviorIgnoresCycle;
    self.panel.level = (NSWindowLevel)(CGWindowLevelForKey(kCGDesktopIconWindowLevelKey) + 1);
    self.panel.releasedWhenClosed = NO;

    self.backgroundView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, size.width, size.height)];
    self.backgroundView.wantsLayer = YES;
    self.backgroundView.layer.cornerRadius = 12;
    self.backgroundView.layer.masksToBounds = YES;
    self.panel.contentView = self.backgroundView;

    self.flagLabel = [self labelWithSize:12 weight:NSFontWeightRegular color:NSColor.labelColor];
    self.flagLabel.stringValue = @"🇲🇽";
    self.flagLabel.font = [NSFont fontWithName:@"Apple Color Emoji" size:12] ?: [NSFont systemFontOfSize:12];
    self.flagLabel.selectable = NO;
    [self.flagLabel setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    self.previousButton = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"chevron.left" accessibilityDescription:@"Previous word"] target:self action:@selector(previousPressed:)];
    self.previousButton.bezelStyle = NSBezelStyleInline;
    self.previousButton.bordered = NO;
    self.previousButton.toolTip = @"Previous word";
    self.previousButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.nextButton = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"chevron.right" accessibilityDescription:@"Next word"] target:self action:@selector(nextPressed:)];
    self.nextButton.bezelStyle = NSBezelStyleInline;
    self.nextButton.bordered = NO;
    self.nextButton.toolTip = @"Next word";
    self.nextButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.wordLabel = [self labelWithSize:12 weight:NSFontWeightRegular color:NSColor.labelColor];
    self.wordLabel.maximumNumberOfLines = 1;
    self.wordLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.wordLabel.alignment = NSTextAlignmentCenter;
    self.wordLabel.selectable = NO;
    [self.backgroundView addSubview:self.flagLabel];
    [self.backgroundView addSubview:self.previousButton];
    [self.backgroundView addSubview:self.nextButton];
    [self.backgroundView addSubview:self.wordLabel];
    NSClickGestureRecognizer *click = [[NSClickGestureRecognizer alloc] initWithTarget:self action:@selector(speakPressed:)];
    [self.wordLabel addGestureRecognizer:click];
    [NSLayoutConstraint activateConstraints:@[
        [self.flagLabel.leadingAnchor constraintEqualToAnchor:self.backgroundView.leadingAnchor constant:10],
        [self.flagLabel.centerYAnchor constraintEqualToAnchor:self.backgroundView.centerYAnchor],
        [self.previousButton.leadingAnchor constraintEqualToAnchor:self.flagLabel.trailingAnchor constant:4],
        [self.previousButton.centerYAnchor constraintEqualToAnchor:self.backgroundView.centerYAnchor],
        [self.previousButton.widthAnchor constraintEqualToConstant:18],
        [self.previousButton.heightAnchor constraintEqualToConstant:24],
        [self.nextButton.leadingAnchor constraintEqualToAnchor:self.previousButton.trailingAnchor constant:1],
        [self.nextButton.centerYAnchor constraintEqualToAnchor:self.backgroundView.centerYAnchor],
        [self.nextButton.widthAnchor constraintEqualToConstant:18],
        [self.nextButton.heightAnchor constraintEqualToConstant:24],
        [self.wordLabel.leadingAnchor constraintEqualToAnchor:self.nextButton.trailingAnchor constant:5],
        [self.wordLabel.trailingAnchor constraintEqualToAnchor:self.backgroundView.trailingAnchor constant:-10],
        [self.wordLabel.centerYAnchor constraintEqualToAnchor:self.backgroundView.centerYAnchor]
    ]];
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([defaults objectForKey:@"windowX"] && [defaults objectForKey:@"windowY"]) {
        [self.panel setFrameOrigin:NSMakePoint([defaults doubleForKey:@"windowX"], [defaults doubleForKey:@"windowY"] )];
    }
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(windowMoved:) name:NSWindowDidMoveNotification object:self.panel];
    [self applyAppearance];
}

- (void)buildStatusMenu {
    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSSquareStatusItemLength];
    self.statusItem.button.image = [NSImage imageWithSystemSymbolName:@"character.book.closed" accessibilityDescription:[self appName]];
    NSMenu *menu = [NSMenu new];
    [menu addItemWithTitle:@"Next Word" action:@selector(nextPressed:) keyEquivalent:@"n"].target = self;
    self.pauseMenuItem = [menu addItemWithTitle:@"Pause" action:@selector(pausePressed:) keyEquivalent:@"p"]; self.pauseMenuItem.target = self;
    self.showMenuItem = [menu addItemWithTitle:@"Hide Widget" action:@selector(toggleWidget:) keyEquivalent:@"h"]; self.showMenuItem.target = self;
    self.pronunciationMenuItem = [menu addItemWithTitle:@"Show Pronunciation" action:@selector(togglePronunciation:) keyEquivalent:@""];
    self.pronunciationMenuItem.target = self;
    self.pronunciationMenuItem.state = [[NSUserDefaults standardUserDefaults] boolForKey:@"showPronunciation"] ? NSControlStateValueOn : NSControlStateValueOff;
    NSMenuItem *voiceMenuItem = [[NSMenuItem alloc] initWithTitle:@"Spanish Voice" action:nil keyEquivalent:@""];
    NSMenu *voiceMenu = [NSMenu new];
    self.voiceItems = [NSMutableArray array];
    NSString *selectedVoice = [[NSUserDefaults standardUserDefaults] stringForKey:@"spanishVoiceIdentifier"] ?: @"";
    NSMenuItem *automaticVoice = [[NSMenuItem alloc] initWithTitle:@"Automatic Mexican Spanish" action:@selector(setSpanishVoice:) keyEquivalent:@""];
    automaticVoice.target = self;
    automaticVoice.representedObject = @"";
    automaticVoice.state = selectedVoice.length == 0 ? NSControlStateValueOn : NSControlStateValueOff;
    [voiceMenu addItem:automaticVoice];
    [self.voiceItems addObject:automaticVoice];
    NSArray<AVSpeechSynthesisVoice *> *mexicanVoices = [[[AVSpeechSynthesisVoice speechVoices] filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(AVSpeechSynthesisVoice *voice, NSDictionary *bindings) {
        return [voice.language.lowercaseString hasPrefix:@"es-mx"];
    }]] sortedArrayUsingComparator:^NSComparisonResult(AVSpeechSynthesisVoice *left, AVSpeechSynthesisVoice *right) {
        return [left.name localizedCaseInsensitiveCompare:right.name];
    }];
    if (mexicanVoices.count) {
        [voiceMenu addItem:NSMenuItem.separatorItem];
        for (AVSpeechSynthesisVoice *voice in mexicanVoices) {
            NSString *gender = @"Voice";
            if (voice.gender == AVSpeechSynthesisVoiceGenderFemale) gender = @"Woman";
            else if (voice.gender == AVSpeechSynthesisVoiceGenderMale) gender = @"Man";
            NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"%@ (%@)", voice.name, gender] action:@selector(setSpanishVoice:) keyEquivalent:@""];
            item.target = self;
            item.representedObject = voice.identifier;
            item.state = [selectedVoice isEqualToString:voice.identifier] ? NSControlStateValueOn : NSControlStateValueOff;
            [voiceMenu addItem:item];
            [self.voiceItems addObject:item];
        }
    } else {
        NSMenuItem *unavailable = [[NSMenuItem alloc] initWithTitle:@"No Mexican Spanish voices installed" action:nil keyEquivalent:@""];
        unavailable.enabled = NO;
        [voiceMenu addItem:unavailable];
    }
    voiceMenuItem.submenu = voiceMenu;
    [menu addItem:voiceMenuItem];
    [menu addItem:NSMenuItem.separatorItem];
    [menu addItemWithTitle:@"Import Vocabulary CSV…" action:@selector(importVocabularyFile:) keyEquivalent:@"i"].target = self;
    [menu addItemWithTitle:@"Open Vocabulary File" action:@selector(openVocabularyFile:) keyEquivalent:@"o"].target = self;
    [menu addItemWithTitle:@"Reload Vocabulary" action:@selector(reloadVocabulary:) keyEquivalent:@"r"].target = self;
    [menu addItemWithTitle:@"Appearance Settings" action:@selector(openSettings:) keyEquivalent:@","].target = self;
    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *changeEvery = [[NSMenuItem alloc] initWithTitle:@"Change Every" action:nil keyEquivalent:@""];
    NSMenu *intervalMenu = [NSMenu new]; self.intervalItems = [NSMutableArray array];
    for (NSNumber *minutes in @[@1,@3,@5,@10,@15]) {
        NSString *title = minutes.integerValue == 1 ? @"1 Minute" : [NSString stringWithFormat:@"%@ Minutes", minutes];
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:@selector(setInterval:) keyEquivalent:@""];
        item.target = self; item.representedObject = minutes; item.state = minutes.integerValue == self.intervalMinutes ? NSControlStateValueOn : NSControlStateValueOff;
        [intervalMenu addItem:item]; [self.intervalItems addObject:item];
    }
    changeEvery.submenu = intervalMenu; [menu addItem:changeEvery];
    NSMenuItem *wordOrder = [[NSMenuItem alloc] initWithTitle:@"Word Order" action:nil keyEquivalent:@""];
    NSMenu *orderMenu = [NSMenu new]; self.orderItems = [NSMutableArray array];
    NSString *savedOrder = [[NSUserDefaults standardUserDefaults] stringForKey:@"wordOrder"] ?: @"random";
    for (NSDictionary *choice in @[@{@"title":@"Random", @"value":@"random"}, @{@"title":@"Grouped by Theme", @"value":@"theme"}]) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:choice[@"title"] action:@selector(setWordOrder:) keyEquivalent:@""];
        item.target = self; item.representedObject = choice[@"value"];
        item.state = [choice[@"value"] isEqualToString:savedOrder] ? NSControlStateValueOn : NSControlStateValueOff;
        [orderMenu addItem:item]; [self.orderItems addObject:item];
    }
    wordOrder.submenu = orderMenu; [menu addItem:wordOrder];
    [menu addItem:NSMenuItem.separatorItem];
    if ([[NSBundle.mainBundle objectForInfoDictionaryKey:@"AutomaticUpdatesEnabled"] boolValue]) {
        [menu addItemWithTitle:@"Update…" action:@selector(checkForUpdates:) keyEquivalent:@"u"].target = self;
    }
    self.registrationMenuItem = [menu addItemWithTitle:@"Purchase License…" action:@selector(showRegistration:) keyEquivalent:@""];
    self.registrationMenuItem.target = self;
    [menu addItemWithTitle:@"Help: Add More Vocabulary…" action:@selector(openVocabularyHelp:) keyEquivalent:@"?"].target = self;
    [menu addItemWithTitle:@"Shareware Terms" action:@selector(openSharewareTerms:) keyEquivalent:@""].target = self;
    [menu addItemWithTitle:@"Privacy Notice" action:@selector(openPrivacyNotice:) keyEquivalent:@""].target = self;
    [menu addItemWithTitle:[NSString stringWithFormat:@"About %@", [self appName]] action:@selector(showAbout:) keyEquivalent:@""].target = self;
    [menu addItem:NSMenuItem.separatorItem];
    [menu addItemWithTitle:[NSString stringWithFormat:@"Quit %@", [self appName]] action:@selector(quitApp:) keyEquivalent:@"q"].target = self;
    self.statusItem.menu = menu;
}

- (void)openBundledTextDocument:(NSString *)name {
    NSURL *url = [NSBundle.mainBundle URLForResource:name withExtension:@"txt"];
    if (url) [[NSWorkspace sharedWorkspace] openURL:url];
}

- (void)openSharewareTerms:(id)sender { [self openBundledTextDocument:@"Shareware Terms"]; }
- (void)openPrivacyNotice:(id)sender { [self openBundledTextDocument:@"Privacy"]; }
- (void)openVocabularyHelp:(id)sender { [self openBundledTextDocument:@"Adding More Vocabulary"]; }

- (NSInteger)trialDays {
    NSInteger days = [[NSBundle.mainBundle objectForInfoDictionaryKey:@"TrialDays"] integerValue];
    return days > 0 ? days : 30;
}

- (BOOL)isRegistered { return [[NSUserDefaults standardUserDefaults] boolForKey:@"sharewareRegistered"]; }

- (NSInteger)daysUsed {
    NSDate *firstRun = [[NSUserDefaults standardUserDefaults] objectForKey:@"sharewareFirstRun"];
    if (![firstRun isKindOfClass:NSDate.class]) return 1;
    NSInteger elapsed = (NSInteger)floor([[NSDate date] timeIntervalSinceDate:firstRun] / 86400.0) + 1;
    return MAX(1, elapsed);
}

- (void)initializeShareware {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if (![defaults objectForKey:@"sharewareFirstRun"]) [defaults setObject:[NSDate date] forKey:@"sharewareFirstRun"];
    [self updateRegistrationMenu];
    if (![self isRegistered] && [self daysUsed] > [self trialDays]) {
        [self performSelector:@selector(showTrialReminder) withObject:nil afterDelay:1.0];
    }
}

- (void)updateRegistrationMenu {
    self.registrationMenuItem.title = [self isRegistered] ? @"Licensed, Thank You" : @"Purchase License…";
    self.registrationMenuItem.enabled = ![self isRegistered];
}

- (void)showTrialReminder {
    NSString *price = [NSBundle.mainBundle objectForInfoDictionaryKey:@"SharewarePrice"] ?: @"$9.99 USD";
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"Your evaluation period has ended";
    alert.informativeText = [NSString stringWithFormat:@"Spanish Vocab Widget is honor-system shareware. A one-time %@ license supports continued development. Your vocabulary and app features remain available.", price];
    [alert addButtonWithTitle:@"Purchase License"];
    [alert addButtonWithTitle:@"Continue Evaluation"];
    [NSApp activateIgnoringOtherApps:YES];
    if ([alert runModal] == NSAlertFirstButtonReturn) [self showRegistration:nil];
}

- (void)showRegistration:(id)sender {
    if ([self isRegistered]) return;
    NSString *price = [NSBundle.mainBundle objectForInfoDictionaryKey:@"SharewarePrice"] ?: @"$9.99 USD";
    NSString *purchaseURL = [NSBundle.mainBundle objectForInfoDictionaryKey:@"PurchaseURL"] ?: @"";
    NSString *supportEmail = [NSBundle.mainBundle objectForInfoDictionaryKey:@"SupportEmail"] ?: @"";
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"Purchase Spanish Vocab Widget";
    alert.informativeText = [NSString stringWithFormat:@"License: %@, one time, for one person. There is no subscription. After paying, return here and select I Have Paid.\n\nSupport: %@", price, supportEmail];
    if (purchaseURL.length) [alert addButtonWithTitle:@"Pay with PayPal"];
    [alert addButtonWithTitle:@"I Have Paid"];
    [alert addButtonWithTitle:@"Not Now"];
    [NSApp activateIgnoringOtherApps:YES];
    NSModalResponse response = [alert runModal];
    if (purchaseURL.length && response == NSAlertFirstButtonReturn) {
        [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:purchaseURL]];
        return;
    }
    NSInteger paidButton = purchaseURL.length ? NSAlertSecondButtonReturn : NSAlertFirstButtonReturn;
    if (response == paidButton) {
        NSAlert *confirm = [NSAlert new];
        confirm.messageText = @"Confirm Purchase";
        confirm.informativeText = @"Select Confirm only if you completed payment for your personal license.";
        [confirm addButtonWithTitle:@"Confirm"];
        [confirm addButtonWithTitle:@"Cancel"];
        if ([confirm runModal] == NSAlertFirstButtonReturn) {
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"sharewareRegistered"];
            [self updateRegistrationMenu];
        }
    }
}

- (void)refillDeck {
    self.deck = [NSMutableArray array];
    for (NSInteger i = 0; i < self.entries.count; i++) [self.deck addObject:@(i)];
    NSString *order = [[NSUserDefaults standardUserDefaults] stringForKey:@"wordOrder"] ?: @"random";
    if ([order isEqualToString:@"theme"]) {
        [self.deck sortUsingComparator:^NSComparisonResult(NSNumber *left, NSNumber *right) {
            NSDictionary *a = self.entries[left.integerValue], *b = self.entries[right.integerValue];
            NSComparisonResult roomResult = [a[@"room"] localizedCaseInsensitiveCompare:b[@"room"]];
            if (roomResult != NSOrderedSame) return roomResult;
            NSComparisonResult categoryResult = [a[@"category"] localizedCaseInsensitiveCompare:b[@"category"]];
            if (categoryResult != NSOrderedSame) return categoryResult;
            return [left compare:right];
        }];
    } else {
        for (NSInteger i = self.deck.count - 1; i > 0; i--) [self.deck exchangeObjectAtIndex:i withObjectAtIndex:arc4random_uniform((uint32_t)(i + 1))];
        if (self.currentIndex >= 0 && self.deck.count > 1 && self.deck[0].integerValue == self.currentIndex) [self.deck exchangeObjectAtIndex:0 withObjectAtIndex:1];
    }
    self.deckPosition = 0;
}

- (NSString *)simpleRoom:(NSString *)room {
    NSDictionary *names = @{@"Family Room / Den":@"family room", @"Hallway / General Household":@"household", @"Closets / Storage":@"storage", @"Patio / Backyard":@"outdoor", @"Cleaning Supplies":@"cleaning", @"Pet Area":@"pet"};
    return names[room] ?: room.lowercaseString;
}

- (NSString *)contextualEnglish:(NSDictionary *)entry {
    NSString *key = [self normalized:entry[@"english"]];
    NSMutableSet *spanish = [NSMutableSet set];
    for (NSDictionary *candidate in self.entries) if ([[self normalized:candidate[@"english"]] isEqual:key]) [spanish addObject:[self normalized:candidate[@"spanish"]]];
    if (spanish.count <= 1) return entry[@"english"];
    NSString *room = [self simpleRoom:entry[@"room"]];
    if (!room.length) return entry[@"english"];
    if ([key containsString:[self normalized:room]]) return entry[@"english"];
    return [NSString stringWithFormat:@"%@ %@", room, entry[@"english"]];
}

- (NSColor *)colorFromHex:(NSString *)hex fallback:(NSColor *)fallback {
    NSString *clean = [hex stringByReplacingOccurrencesOfString:@"#" withString:@""];
    if (clean.length != 8) return fallback;
    unsigned int value = 0;
    if (![[NSScanner scannerWithString:clean] scanHexInt:&value]) return fallback;
    return [NSColor colorWithSRGBRed:((value >> 24) & 255) / 255.0
                               green:((value >> 16) & 255) / 255.0
                                blue:((value >> 8) & 255) / 255.0
                               alpha:(value & 255) / 255.0];
}

- (NSString *)hexFromColor:(NSColor *)color {
    NSColor *rgb = [color colorUsingColorSpace:NSColorSpace.sRGBColorSpace] ?: color;
    return [NSString stringWithFormat:@"#%02X%02X%02X%02X",
            (int)round(rgb.redComponent * 255), (int)round(rgb.greenComponent * 255),
            (int)round(rgb.blueComponent * 255), (int)round(rgb.alphaComponent * 255)];
}

- (NSFontWeight)selectedWeight {
    NSString *weight = [[NSUserDefaults standardUserDefaults] stringForKey:@"fontWeight"];
    if ([weight isEqualToString:@"Regular"]) return NSFontWeightRegular;
    if ([weight isEqualToString:@"Medium"]) return NSFontWeightMedium;
    if ([weight isEqualToString:@"Bold"]) return NSFontWeightBold;
    return NSFontWeightSemibold;
}

- (NSFont *)selectedFontWithSize:(CGFloat)size weight:(NSFontWeight)weight {
    NSString *name = [[NSUserDefaults standardUserDefaults] stringForKey:@"fontName"];
    if (!name.length || [name isEqualToString:@"System"]) return [NSFont systemFontOfSize:size weight:weight];
    NSFont *base = [NSFont fontWithName:name size:size];
    if (!base) return [NSFont systemFontOfSize:size weight:weight];
    return [[NSFontManager sharedFontManager] convertFont:base toHaveTrait:(weight >= NSFontWeightSemibold ? NSBoldFontMask : NSUnboldFontMask)];
}

- (void)applyAppearance {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSColor *textColor = [self colorFromHex:[defaults stringForKey:@"textColor"] fallback:NSColor.labelColor];
    NSColor *background = [self colorFromHex:[defaults stringForKey:@"backgroundColor"] fallback:NSColor.windowBackgroundColor];
    CGFloat opacity = [defaults doubleForKey:@"backgroundOpacity"];
    self.backgroundView.layer.backgroundColor = [background colorWithAlphaComponent:opacity].CGColor;
    self.wordLabel.textColor = textColor;
    if (self.currentIndex >= 0 && self.currentIndex < self.entries.count) [self displayEntry:self.entries[self.currentIndex]];
}

- (void)displayEntry:(NSDictionary *)entry {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSString *spanish = entry[@"spanish"];
    NSString *english = [self contextualEnglish:entry];
    NSString *pronunciation = entry[@"pronunciation"] ?: @"";
    BOOL showPronunciation = [defaults boolForKey:@"showPronunciation"] && pronunciation.length > 0;
    NSString *text = showPronunciation
        ? [NSString stringWithFormat:@"%@  ·  %@  ·  %@", spanish, pronunciation, english]
        : [NSString stringWithFormat:@"%@  ·  %@", spanish, english];
    CGFloat size = [defaults doubleForKey:@"fontSize"];
    NSFontWeight weight = [self selectedWeight];
    NSFont *spanishFont = [self selectedFontWithSize:size weight:weight];
    NSFont *englishFont = [self selectedFontWithSize:MAX(9, size - 1) weight:NSFontWeightRegular];
    NSFont *pronunciationFont = [[NSFontManager sharedFontManager] convertFont:englishFont toHaveTrait:NSItalicFontMask];
    NSColor *textColor = [self colorFromHex:[defaults stringForKey:@"textColor"] fallback:NSColor.labelColor];
    NSColor *secondary = [textColor colorWithAlphaComponent:0.72];
    NSMutableAttributedString *styled = [[NSMutableAttributedString alloc] initWithString:text attributes:@{NSFontAttributeName:englishFont, NSForegroundColorAttributeName:secondary}];
    [styled addAttributes:@{NSFontAttributeName:spanishFont, NSForegroundColorAttributeName:textColor} range:NSMakeRange(0, spanish.length)];
    if (showPronunciation) {
        NSRange pronunciationRange = NSMakeRange(spanish.length + 5, pronunciation.length);
        [styled addAttributes:@{NSFontAttributeName:pronunciationFont, NSForegroundColorAttributeName:secondary} range:pronunciationRange];
    }
    self.wordLabel.attributedStringValue = styled;
    self.wordLabel.toolTip = text;

    BOOL autoSize = [defaults boolForKey:@"autoSize"];
    CGFloat width = 200, height = 40;
    if (autoSize) {
        NSRect natural = [styled boundingRectWithSize:NSMakeSize(CGFLOAT_MAX, 40) options:NSStringDrawingUsesLineFragmentOrigin];
        width = MIN(600, MAX(190, ceil(natural.size.width) + 94));
    }
    self.wordLabel.maximumNumberOfLines = 1;
    self.wordLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    NSRect frame = self.panel.frame;
    CGFloat top = NSMaxY(frame);
    frame.size = NSMakeSize(width, height);
    frame.origin.y = top - height;
    [self.panel setFrame:frame display:YES animate:YES];
    self.backgroundView.layer.cornerRadius = MIN(14, height / 2.0);
    [self updateNavigationButtons];
}

- (void)openSettings:(id)sender {
    if (!self.settingsWindow) [self buildSettingsWindow];
    [NSApp activateIgnoringOtherApps:YES];
    [self.settingsWindow center];
    [self.settingsWindow makeKeyAndOrderFront:nil];
}

- (NSTextField *)settingsLabel:(NSString *)text {
    NSTextField *label = [NSTextField labelWithString:text];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

- (void)buildSettingsWindow {
    self.settingsWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,390,330)
                                                      styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
                                                        backing:NSBackingStoreBuffered defer:NO];
    self.settingsWindow.title = [NSString stringWithFormat:@"🇲🇽 %@ Appearance", [self appName]];
    self.settingsWindow.releasedWhenClosed = NO;
    NSView *content = self.settingsWindow.contentView;
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;

    self.autoSizeCheckbox = [NSButton checkboxWithTitle:@"Automatically fit the strip to the words" target:self action:@selector(settingsChanged:)];
    self.autoSizeCheckbox.state = [defaults boolForKey:@"autoSize"] ? NSControlStateValueOn : NSControlStateValueOff;
    self.fontPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [self.fontPopup addItemsWithTitles:@[@"System", @"Helvetica Neue", @"Avenir Next", @"Georgia", @"Menlo"]];
    [self.fontPopup selectItemWithTitle:[defaults stringForKey:@"fontName"]]; self.fontPopup.target = self; self.fontPopup.action = @selector(settingsChanged:);
    self.fontSizeSlider = [NSSlider sliderWithValue:[defaults doubleForKey:@"fontSize"] minValue:10 maxValue:22 target:self action:@selector(settingsChanged:)];
    self.fontSizeSlider.continuous = YES;
    self.fontSizeValue = [NSTextField labelWithString:[NSString stringWithFormat:@"%.0f pt", self.fontSizeSlider.doubleValue]];
    self.weightPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [self.weightPopup addItemsWithTitles:@[@"Regular", @"Medium", @"Semibold", @"Bold"]];
    [self.weightPopup selectItemWithTitle:[defaults stringForKey:@"fontWeight"]]; self.weightPopup.target = self; self.weightPopup.action = @selector(settingsChanged:);
    self.textColorWell = [[NSColorWell alloc] init]; self.textColorWell.color = [self colorFromHex:[defaults stringForKey:@"textColor"] fallback:NSColor.labelColor]; self.textColorWell.target = self; self.textColorWell.action = @selector(settingsChanged:);
    self.backgroundColorWell = [[NSColorWell alloc] init]; self.backgroundColorWell.color = [self colorFromHex:[defaults stringForKey:@"backgroundColor"] fallback:NSColor.windowBackgroundColor]; self.backgroundColorWell.target = self; self.backgroundColorWell.action = @selector(settingsChanged:);
    self.opacitySlider = [NSSlider sliderWithValue:[defaults doubleForKey:@"backgroundOpacity"] minValue:0.25 maxValue:1 target:self action:@selector(settingsChanged:)]; self.opacitySlider.continuous = YES;
    NSButton *reset = [NSButton buttonWithTitle:@"Reset Defaults" target:self action:@selector(resetAppearance:)];

    NSArray *views = @[self.autoSizeCheckbox,self.fontPopup,self.fontSizeSlider,self.fontSizeValue,self.weightPopup,self.textColorWell,self.backgroundColorWell,self.opacitySlider,reset];
    for (NSView *view in views) { view.translatesAutoresizingMaskIntoConstraints = NO; [content addSubview:view]; }
    NSTextField *fontLabel = [self settingsLabel:@"Font"];
    NSTextField *sizeLabel = [self settingsLabel:@"Text size"];
    NSTextField *weightLabel = [self settingsLabel:@"Text style"];
    NSTextField *textColorLabel = [self settingsLabel:@"Text color"];
    NSTextField *backgroundLabel = [self settingsLabel:@"Background color"];
    NSTextField *opacityLabel = [self settingsLabel:@"Background opacity"];
    for (NSView *view in @[fontLabel,sizeLabel,weightLabel,textColorLabel,backgroundLabel,opacityLabel]) [content addSubview:view];
    [NSLayoutConstraint activateConstraints:@[
        [self.autoSizeCheckbox.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:24], [self.autoSizeCheckbox.topAnchor constraintEqualToAnchor:content.topAnchor constant:22],
        [fontLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:24], [fontLabel.topAnchor constraintEqualToAnchor:self.autoSizeCheckbox.bottomAnchor constant:22],
        [self.fontPopup.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:170], [self.fontPopup.centerYAnchor constraintEqualToAnchor:fontLabel.centerYAnchor], [self.fontPopup.widthAnchor constraintEqualToConstant:180],
        [sizeLabel.leadingAnchor constraintEqualToAnchor:fontLabel.leadingAnchor], [sizeLabel.topAnchor constraintEqualToAnchor:fontLabel.bottomAnchor constant:24],
        [self.fontSizeSlider.leadingAnchor constraintEqualToAnchor:self.fontPopup.leadingAnchor], [self.fontSizeSlider.centerYAnchor constraintEqualToAnchor:sizeLabel.centerYAnchor], [self.fontSizeSlider.widthAnchor constraintEqualToConstant:130],
        [self.fontSizeValue.leadingAnchor constraintEqualToAnchor:self.fontSizeSlider.trailingAnchor constant:8], [self.fontSizeValue.centerYAnchor constraintEqualToAnchor:sizeLabel.centerYAnchor],
        [weightLabel.leadingAnchor constraintEqualToAnchor:fontLabel.leadingAnchor], [weightLabel.topAnchor constraintEqualToAnchor:sizeLabel.bottomAnchor constant:24],
        [self.weightPopup.leadingAnchor constraintEqualToAnchor:self.fontPopup.leadingAnchor], [self.weightPopup.centerYAnchor constraintEqualToAnchor:weightLabel.centerYAnchor], [self.weightPopup.widthAnchor constraintEqualToConstant:180],
        [textColorLabel.leadingAnchor constraintEqualToAnchor:fontLabel.leadingAnchor], [textColorLabel.topAnchor constraintEqualToAnchor:weightLabel.bottomAnchor constant:24],
        [self.textColorWell.leadingAnchor constraintEqualToAnchor:self.fontPopup.leadingAnchor], [self.textColorWell.centerYAnchor constraintEqualToAnchor:textColorLabel.centerYAnchor],
        [backgroundLabel.leadingAnchor constraintEqualToAnchor:fontLabel.leadingAnchor], [backgroundLabel.topAnchor constraintEqualToAnchor:textColorLabel.bottomAnchor constant:24],
        [self.backgroundColorWell.leadingAnchor constraintEqualToAnchor:self.fontPopup.leadingAnchor], [self.backgroundColorWell.centerYAnchor constraintEqualToAnchor:backgroundLabel.centerYAnchor],
        [opacityLabel.leadingAnchor constraintEqualToAnchor:fontLabel.leadingAnchor], [opacityLabel.topAnchor constraintEqualToAnchor:backgroundLabel.bottomAnchor constant:24],
        [self.opacitySlider.leadingAnchor constraintEqualToAnchor:self.fontPopup.leadingAnchor], [self.opacitySlider.centerYAnchor constraintEqualToAnchor:opacityLabel.centerYAnchor], [self.opacitySlider.widthAnchor constraintEqualToConstant:180],
        [reset.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-24], [reset.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-18]
    ]];
}

- (void)settingsChanged:(id)sender {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setBool:self.autoSizeCheckbox.state == NSControlStateValueOn forKey:@"autoSize"];
    [defaults setObject:self.fontPopup.titleOfSelectedItem forKey:@"fontName"];
    [defaults setDouble:round(self.fontSizeSlider.doubleValue) forKey:@"fontSize"];
    self.fontSizeValue.stringValue = [NSString stringWithFormat:@"%.0f pt", round(self.fontSizeSlider.doubleValue)];
    [defaults setObject:self.weightPopup.titleOfSelectedItem forKey:@"fontWeight"];
    [defaults setObject:[self hexFromColor:self.textColorWell.color] forKey:@"textColor"];
    [defaults setObject:[self hexFromColor:self.backgroundColorWell.color] forKey:@"backgroundColor"];
    [defaults setDouble:self.opacitySlider.doubleValue forKey:@"backgroundOpacity"];
    [self applyAppearance];
}

- (void)resetAppearance:(id)sender {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    for (NSString *key in @[@"autoSize",@"fontName",@"fontSize",@"fontWeight",@"textColor",@"backgroundColor",@"backgroundOpacity"]) [defaults removeObjectForKey:key];
    [self registerAppearanceDefaults];
    self.autoSizeCheckbox.state = NSControlStateValueOn;
    [self.fontPopup selectItemWithTitle:@"System"];
    self.fontSizeSlider.doubleValue = 13;
    self.fontSizeValue.stringValue = @"13 pt";
    [self.weightPopup selectItemWithTitle:@"Semibold"];
    self.textColorWell.color = [self colorFromHex:@"#1F1F1FFF" fallback:NSColor.labelColor];
    self.backgroundColorWell.color = [self colorFromHex:@"#E7E7E7FF" fallback:NSColor.windowBackgroundColor];
    self.opacitySlider.doubleValue = 0.94;
    [self settingsChanged:nil];
}

- (void)showNextWord {
    if (!self.entries.count) return;
    if (self.historyPosition + 1 < self.history.count) {
        self.historyPosition++;
        self.currentIndex = self.history[self.historyPosition].integerValue;
        [self displayEntry:self.entries[self.currentIndex]];
        return;
    }
    if (self.deckPosition >= self.deck.count) [self refillDeck];
    NSInteger index = self.deck[self.deckPosition++].integerValue;
    self.currentIndex = index;
    [self.history addObject:@(index)];
    self.historyPosition = self.history.count - 1;
    [self displayEntry:self.entries[index]];
}

- (void)showPreviousWord {
    if (self.historyPosition <= 0) return;
    self.historyPosition--;
    self.currentIndex = self.history[self.historyPosition].integerValue;
    [self displayEntry:self.entries[self.currentIndex]];
}

- (void)updateNavigationButtons {
    self.previousButton.enabled = self.historyPosition > 0;
    self.nextButton.enabled = self.entries.count > 0;
}

- (void)scheduleTimer {
    [self.timer invalidate]; self.timer = nil;
    if (self.paused) return;
    self.timer = [NSTimer scheduledTimerWithTimeInterval:self.intervalMinutes * 60 target:self selector:@selector(timerFired:) userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
}

- (void)timerFired:(NSTimer *)timer { [self showNextWord]; }
- (void)speakPressed:(id)sender {
    if (self.currentIndex < 0 || self.currentIndex >= self.entries.count) return;
    NSString *spanish = self.entries[self.currentIndex][@"spanish"];
    if (!spanish.length) return;
    if (self.speechSynthesizer.isSpeaking) [self.speechSynthesizer stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
    AVSpeechUtterance *utterance = [AVSpeechUtterance speechUtteranceWithString:spanish];
    NSString *identifier = [[NSUserDefaults standardUserDefaults] stringForKey:@"spanishVoiceIdentifier"] ?: @"";
    AVSpeechSynthesisVoice *selectedVoice = identifier.length ? [AVSpeechSynthesisVoice voiceWithIdentifier:identifier] : nil;
    utterance.voice = selectedVoice ?: [AVSpeechSynthesisVoice voiceWithLanguage:@"es-MX"] ?: [AVSpeechSynthesisVoice voiceWithLanguage:@"es-US"] ?: [AVSpeechSynthesisVoice voiceWithLanguage:@"es-ES"];
    utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.88;
    [self.speechSynthesizer speakUtterance:utterance];
}
- (void)setSpanishVoice:(NSMenuItem *)sender {
    NSString *identifier = sender.representedObject ?: @"";
    [[NSUserDefaults standardUserDefaults] setObject:identifier forKey:@"spanishVoiceIdentifier"];
    for (NSMenuItem *item in self.voiceItems) item.state = item == sender ? NSControlStateValueOn : NSControlStateValueOff;
    [self speakPressed:nil];
}
- (void)previousPressed:(id)sender { [self showPreviousWord]; [self scheduleTimer]; }
- (void)nextPressed:(id)sender { [self showNextWord]; [self scheduleTimer]; }
- (void)pausePressed:(id)sender { self.paused = !self.paused; self.pauseMenuItem.title = self.paused ? @"Resume" : @"Pause"; [self scheduleTimer]; }
- (void)toggleWidget:(id)sender { if (self.panel.visible) { [self.panel orderOut:nil]; self.showMenuItem.title = @"Show Widget"; } else { [self.panel orderFrontRegardless]; self.showMenuItem.title = @"Hide Widget"; } }
- (void)togglePronunciation:(id)sender { BOOL show = ![[NSUserDefaults standardUserDefaults] boolForKey:@"showPronunciation"]; [[NSUserDefaults standardUserDefaults] setBool:show forKey:@"showPronunciation"]; self.pronunciationMenuItem.state = show ? NSControlStateValueOn : NSControlStateValueOff; if (self.currentIndex >= 0 && self.currentIndex < self.entries.count) [self displayEntry:self.entries[self.currentIndex]]; }
- (void)setInterval:(NSMenuItem *)sender { self.intervalMinutes = [sender.representedObject integerValue]; [[NSUserDefaults standardUserDefaults] setInteger:self.intervalMinutes forKey:@"intervalMinutes"]; for (NSMenuItem *item in self.intervalItems) item.state = item == sender ? NSControlStateValueOn : NSControlStateValueOff; [self scheduleTimer]; }
- (void)setWordOrder:(NSMenuItem *)sender { [[NSUserDefaults standardUserDefaults] setObject:sender.representedObject forKey:@"wordOrder"]; for (NSMenuItem *item in self.orderItems) item.state = item == sender ? NSControlStateValueOn : NSControlStateValueOff; [self refillDeck]; [self showNextWord]; [self scheduleTimer]; }
- (void)importVocabularyFile:(id)sender {
    [NSApp activateIgnoringOtherApps:YES];
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.title = @"Import Vocabulary CSV";
    panel.prompt = @"Import";
    panel.allowedContentTypes = @[[UTType typeWithFilenameExtension:@"csv"]];
    panel.allowsMultipleSelection = NO;
    panel.canChooseDirectories = NO;
    if ([panel runModal] != NSModalResponseOK) return;
    NSError *error = nil;
    NSString *text = [NSString stringWithContentsOfURL:panel.URL encoding:NSUTF8StringEncoding error:&error];
    NSArray *records = text ? [self parseCSV:text] : @[];
    if (records.count < 2) { [self showImportError:@"The CSV must contain a header row and at least one vocabulary row."]; return; }
    NSMutableSet *headers = [NSMutableSet set];
    for (NSString *header in records[0]) [headers addObject:[self normalized:header]];
    if (![headers containsObject:@"spanish"] || ![headers containsObject:@"english"]) { [self showImportError:@"The CSV must include Spanish and English columns."]; return; }
    [self prepareEditableVocabulary];
    if (![text writeToURL:[self editableVocabularyURL] atomically:YES encoding:NSUTF8StringEncoding error:&error]) { [self showImportError:error.localizedDescription ?: @"The vocabulary file could not be saved."]; return; }
    [self loadVocabulary];
    [self.history removeAllObjects]; self.historyPosition = -1; self.currentIndex = -1;
    [self refillDeck]; [self showNextWord]; [self scheduleTimer];
}
- (void)showImportError:(NSString *)message { NSAlert *alert = [NSAlert new]; alert.messageText = @"Import Vocabulary CSV"; alert.informativeText = message; [alert runModal]; }
- (void)openVocabularyFile:(id)sender { [self prepareEditableVocabulary]; [[NSWorkspace sharedWorkspace] openURL:[self editableVocabularyURL]]; }
- (void)checkForUpdates:(id)sender {
    NSString *feedString = [NSBundle.mainBundle objectForInfoDictionaryKey:@"UpdateFeedURL"];
    NSURL *feedURL = feedString.length ? [NSURL URLWithString:feedString] : nil;
    if (!feedURL) { [self showUpdateMessage:@"The update service is not configured."]; return; }
    self.statusItem.button.toolTip = @"Checking for updates…";
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:feedURL];
    [request setValue:@"Spanish-Vocab-Widget" forHTTPHeaderField:@"User-Agent"];
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data.length) { dispatch_async(dispatch_get_main_queue(), ^{ [self showUpdateMessage:@"The update check could not be completed. Please check your internet connection."]; }); return; }
        NSDictionary *release = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
        NSString *tag = [release[@"tag_name"] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"vV"]];
        NSString *current = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"0";
        if (!tag.length || [tag compare:current options:NSNumericSearch] != NSOrderedDescending) {
            dispatch_async(dispatch_get_main_queue(), ^{ [self showUpdateMessage:[NSString stringWithFormat:@"You are using the latest version of %@.", [self appName]]]; });
            return;
        }
        NSString *assetName = [NSBundle.mainBundle objectForInfoDictionaryKey:@"UpdateAssetName"];
        NSString *downloadString = nil;
        for (NSDictionary *asset in release[@"assets"]) {
            if ([asset[@"name"] isEqualToString:assetName]) { downloadString = asset[@"browser_download_url"]; break; }
        }
        NSURL *downloadURL = downloadString.length ? [NSURL URLWithString:downloadString] : nil;
        if (!downloadURL) { dispatch_async(dispatch_get_main_queue(), ^{ [self showUpdateMessage:@"An update is available, but the installer for this edition is not attached to the release yet."]; }); return; }
        dispatch_async(dispatch_get_main_queue(), ^{ self.statusItem.button.toolTip = @"Downloading update…"; });
        [[[NSURLSession sharedSession] downloadTaskWithURL:downloadURL completionHandler:^(NSURL *location, NSURLResponse *downloadResponse, NSError *downloadError) {
            if (downloadError || !location) { dispatch_async(dispatch_get_main_queue(), ^{ [self showUpdateMessage:@"The update could not be downloaded."]; }); return; }
            [self installDownloadedUpdate:location version:tag];
        }] resume];
    }] resume];
}
- (void)installDownloadedUpdate:(NSURL *)downloadURL version:(NSString *)version {
    NSFileManager *files = NSFileManager.defaultManager;
    NSURL *working = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"spanish-vocab-update-%@", NSUUID.UUID.UUIDString]] isDirectory:YES];
    NSError *error = nil;
    [files createDirectoryAtURL:working withIntermediateDirectories:YES attributes:nil error:&error];
    NSURL *zipURL = [working URLByAppendingPathComponent:@"update.zip"];
    if (error || ![files copyItemAtURL:downloadURL toURL:zipURL error:&error]) { dispatch_async(dispatch_get_main_queue(), ^{ [self showUpdateMessage:@"The downloaded update could not be prepared."]; }); return; }
    NSTask *unzip = [NSTask new];
    unzip.executableURL = [NSURL fileURLWithPath:@"/usr/bin/ditto"];
    unzip.arguments = @[@"-x", @"-k", zipURL.path, working.path];
    [unzip launchAndReturnError:&error];
    [unzip waitUntilExit];
    if (error || unzip.terminationStatus != 0) { dispatch_async(dispatch_get_main_queue(), ^{ [self showUpdateMessage:@"The downloaded update could not be opened."]; }); return; }
    NSURL *replacement = nil;
    NSDirectoryEnumerator *enumerator = [files enumeratorAtURL:working includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles errorHandler:nil];
    for (NSURL *candidate in enumerator) {
        if ([candidate.pathExtension.lowercaseString isEqualToString:@"app"]) { replacement = candidate; [enumerator skipDescendants]; break; }
    }
    NSString *expectedIdentifier = NSBundle.mainBundle.bundleIdentifier;
    NSBundle *replacementBundle = replacement ? [NSBundle bundleWithURL:replacement] : nil;
    BOOL codeOnlyUpdate = [[NSBundle.mainBundle objectForInfoDictionaryKey:@"CodeOnlyUpdates"] boolValue];
    NSString *genericIdentifier = @"com.momalley.spanishvocabwidget";
    BOOL identityMatches = replacementBundle && [replacementBundle.bundleIdentifier isEqualToString:expectedIdentifier];
    BOOL trustedGenericCode = replacementBundle && codeOnlyUpdate && [replacementBundle.bundleIdentifier isEqualToString:genericIdentifier];
    if (!identityMatches && !trustedGenericCode) { dispatch_async(dispatch_get_main_queue(), ^{ [self showUpdateMessage:@"The downloaded app does not match this edition."]; }); return; }
    NSTask *verify = [NSTask new];
    verify.executableURL = [NSURL fileURLWithPath:@"/usr/bin/codesign"];
    verify.arguments = @[@"--verify", @"--deep", @"--strict", replacement.path];
    [verify launchAndReturnError:&error];
    [verify waitUntilExit];
    if (error || verify.terminationStatus != 0) { dispatch_async(dispatch_get_main_queue(), ^{ [self showUpdateMessage:@"The downloaded app did not pass its integrity check."]; }); return; }
    if (trustedGenericCode) {
        NSURL *replacementInfoURL = [replacement URLByAppendingPathComponent:@"Contents/Info.plist"];
        NSMutableDictionary *replacementInfo = [NSMutableDictionary dictionaryWithContentsOfURL:replacementInfoURL];
        NSDictionary *currentInfo = NSBundle.mainBundle.infoDictionary;
        NSArray *preservedKeys = @[@"CFBundleName", @"CFBundleDisplayName", @"CFBundleIdentifier", @"VocabularyFolderName", @"UpdateURL", @"UpdateFeedURL", @"UpdateAssetName", @"AutomaticUpdatesEnabled", @"CodeOnlyUpdates", @"PurchaseURL", @"SupportEmail", @"SharewarePrice", @"TrialDays"];
        if (!replacementInfo) { dispatch_async(dispatch_get_main_queue(), ^{ [self showUpdateMessage:@"The downloaded update could not preserve this edition’s identity."]; }); return; }
        for (NSString *key in preservedKeys) {
            id value = currentInfo[key];
            if (value) replacementInfo[key] = value;
            else [replacementInfo removeObjectForKey:key];
        }
        if (![replacementInfo writeToURL:replacementInfoURL atomically:YES]) { dispatch_async(dispatch_get_main_queue(), ^{ [self showUpdateMessage:@"The downloaded update could not preserve this edition’s identity."]; }); return; }
        NSTask *resign = [NSTask new];
        resign.executableURL = [NSURL fileURLWithPath:@"/usr/bin/codesign"];
        resign.arguments = @[@"--force", @"--deep", @"--sign", @"-", replacement.path];
        [resign launchAndReturnError:&error];
        [resign waitUntilExit];
        if (error || resign.terminationStatus != 0) { dispatch_async(dispatch_get_main_queue(), ^{ [self showUpdateMessage:@"The downloaded update could not be prepared for this edition."]; }); return; }
    }
    NSString *destination = NSBundle.mainBundle.bundleURL.path;
    if (![files isWritableFileAtPath:destination.stringByDeletingLastPathComponent]) { dispatch_async(dispatch_get_main_queue(), ^{ [self showUpdateMessage:@"The app cannot replace itself in its current folder. Move it to your personal Applications folder first."]; }); return; }
    NSURL *scriptURL = [working URLByAppendingPathComponent:@"finish-update.sh"];
    NSString *script = [NSString stringWithFormat:@"#!/bin/sh\nwhile kill -0 %d 2>/dev/null; do sleep 0.2; done\nrm -rf %@\n/usr/bin/ditto %@ %@\n/usr/bin/open %@\nrm -rf %@\n", getpid(), [self shellQuoted:destination], [self shellQuoted:replacement.path], [self shellQuoted:destination], [self shellQuoted:destination], [self shellQuoted:working.path]];
    if (![script writeToURL:scriptURL atomically:YES encoding:NSUTF8StringEncoding error:&error]) { dispatch_async(dispatch_get_main_queue(), ^{ [self showUpdateMessage:@"The update helper could not be created."]; }); return; }
    [files setAttributes:@{NSFilePosixPermissions:@0700} ofItemAtPath:scriptURL.path error:&error];
    NSTask *helper = [NSTask new];
    helper.executableURL = [NSURL fileURLWithPath:@"/bin/sh"];
    helper.arguments = @[scriptURL.path];
    [helper launchAndReturnError:&error];
    if (error) { dispatch_async(dispatch_get_main_queue(), ^{ [self showUpdateMessage:@"The update could not be installed."]; }); return; }
    dispatch_async(dispatch_get_main_queue(), ^{ [NSApp terminate:nil]; });
}
- (NSString *)shellQuoted:(NSString *)value { return [NSString stringWithFormat:@"'%@'", [value stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"]]; }
- (void)showUpdateMessage:(NSString *)message {
    self.statusItem.button.toolTip = [self appName];
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"Software Update";
    alert.informativeText = message;
    [NSApp activateIgnoringOtherApps:YES];
    [alert runModal];
}
- (void)reloadVocabulary:(id)sender { [self loadVocabulary]; [self refillDeck]; [self showNextWord]; [self scheduleTimer]; }
- (void)showAbout:(id)sender {
    [self loadVocabulary];
    NSBundle *bundle = NSBundle.mainBundle;
    NSString *version = [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"Unknown";
    NSString *build = [bundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"Unknown";
    NSURL *vocabularyURL = [self editableVocabularyURL];
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:vocabularyURL.path error:nil];
    NSDate *modified = attributes[NSFileModificationDate];
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.dateStyle = NSDateFormatterLongStyle;
    formatter.timeStyle = NSDateFormatterShortStyle;
    NSString *updated = modified ? [formatter stringFromDate:modified] : @"Unknown";
    NSString *licenseStatus = [self isRegistered] ? @"Licensed" : [NSString stringWithFormat:@"Evaluation, day %ld of %ld", (long)[self daysUsed], (long)[self trialDays]];
    NSString *details = [NSString stringWithFormat:
        @"Created by Michael O’Malley\n\nShareware status: %@\nVocabulary entries: %ld\nVocabulary updated: %@\nVocabulary file: %@\n\nMexican Spanish vocabulary for practical everyday use.",
        licenseStatus, (long)self.entries.count, updated, vocabularyURL.path];
    NSDictionary *options = @{
        NSAboutPanelOptionApplicationName: [self appName],
        NSAboutPanelOptionApplicationVersion: version,
        NSAboutPanelOptionVersion: [NSString stringWithFormat:@"Build %@, released September 24, 2026", build],
        NSAboutPanelOptionCredits: [[NSAttributedString alloc] initWithString:details],
        @"Copyright": @"Copyright © 2026 Michael O’Malley"
    };
    [NSApp activateIgnoringOtherApps:YES];
    [NSApp orderFrontStandardAboutPanelWithOptions:options];
}
- (void)quitApp:(id)sender { [NSApp terminate:nil]; }
- (void)windowMoved:(NSNotification *)notification { NSPoint p = self.panel.frame.origin; [[NSUserDefaults standardUserDefaults] setDouble:p.x forKey:@"windowX"]; [[NSUserDefaults standardUserDefaults] setDouble:p.y forKey:@"windowY"]; }
- (void)fatalError:(NSString *)message { NSAlert *alert = [NSAlert new]; alert.messageText = [self appName]; alert.informativeText = message; [alert runModal]; [NSApp terminate:nil]; }
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *application = NSApplication.sharedApplication;
        AppDelegate *delegate = [AppDelegate new];
        application.delegate = delegate;
        [application run];
    }
    return 0;
}
