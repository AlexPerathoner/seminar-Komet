//
//  ZGEditorWindowController.m
//  Komet
//
//  Created by Mayur Pawashe on 8/16/16.
//  Copyright © 2016 zgcoder. All rights reserved.
//

#import "ZGEditorWindowController.h"
#import "ZGCommitTextView.h"

#define ZGEditorWindowFrameNameKey @"ZGEditorWindowFrame"
#define ZGEditorFontNameKey @"ZGEditorFontName"
#define ZGEditorFontSizeKey @"ZGEditorFontSize"
#define ZGEditorRecommendedSubjectLengthLimitKey @"ZGEditorRecommendedSubjectLengthLimit"
#define ZGEditorSubjectOverflowBackgroundColorKey @"ZGEditorSubjectOverflowBackgroundColor"
#define ZGEditorCommentForegroundColorKey @"ZGEditorCommentForegroundColor"
#define ZGEditorAutomaticNewlineInsertionAfterSubjectKey @"ZGEditorAutomaticNewlineInsertionAfterSubject"

typedef NS_ENUM(NSUInteger, ZGVersionControlType)
{
	ZGVersionControlGit,
	ZGVersionControlHg,
	ZGVersionControlSvn
};

@interface ZGEditorWindowController () <NSTextStorageDelegate, NSLayoutManagerDelegate, NSTextViewDelegate>
@end

@implementation ZGEditorWindowController
{
	NSURL *_fileURL;
	IBOutlet ZGCommitTextView *_textView;
	IBOutlet NSTextField *_commitLabelTextField;
	BOOL _preventAccidentalNewline;
	BOOL _initiallyContainedEmptyContent;
	NSUInteger _commentSectionLength;
}

+ (void)initialize
{
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
		
		const CGFloat fontSize = 11.0;
		
		// This is the max subject length GitHub uses before the subject overflows
		// Not using 50 because I think it may be too irritating of a default for Mac users
		const NSUInteger maxRecommendedSubjectLengthLimit = 69;
		
		NSColor *commentColor = [[NSColor darkGrayColor] colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
		
		[defaults registerDefaults:@{ZGEditorFontNameKey : @"", ZGEditorFontSizeKey : @(fontSize), ZGEditorRecommendedSubjectLengthLimitKey : @(maxRecommendedSubjectLengthLimit), ZGEditorSubjectOverflowBackgroundColorKey : @"1.0,0.0,0.0,0.3", ZGEditorCommentForegroundColorKey : [NSString stringWithFormat:@"%f,%f,%f,%f", commentColor.redComponent, commentColor.greenComponent, commentColor.blueComponent, commentColor.alphaComponent], ZGEditorAutomaticNewlineInsertionAfterSubjectKey : @YES}];
	});
}

- (instancetype)initWithFileURL:(NSURL *)fileURL
{
	self = [super init];
	if (self != nil)
	{
		_fileURL = fileURL;
	}
	return self;
}

- (NSString *)windowNibName
{
	return @"Commit Editor";
}

- (void)saveWindowFrame
{
	[self.window saveFrameUsingName:ZGEditorWindowFrameNameKey];
}

- (NSFont *)defaultFontOfSize:(CGFloat)size
{
	NSFont *defaultFont;
	// 10.12 may have SF Mono system wide
	NSFont *sfMonoFont = [NSFont fontWithName:@"SF Mono" size:size];
	// Revert to older font face on older systems
	if (sfMonoFont != nil)
	{
		defaultFont = sfMonoFont;
	}
	else
	{
		// Default font Xcode 7 uses
		NSFont *menloFont = [NSFont fontWithName:@"Menlo" size:size];
		if (menloFont != nil)
		{
			defaultFont = menloFont;
		}
		else
		{
			// If we get here, we are especially desperate
			defaultFont = [NSFont systemFontOfSize:size];
		}
	}
	return defaultFont;
}

- (void)windowDidLoad
{
	[self.window setFrameUsingName:ZGEditorWindowFrameNameKey];
	
	NSData *data = [NSData dataWithContentsOfURL:_fileURL];
	if (data == nil)
	{
		printf("Error: Couldn't load data from %s\n", _fileURL.path.UTF8String);
		exit(EXIT_FAILURE);
	}
	
	// If it's a git repo, set the label to the Project folder name, otherwise just use the filename
	NSURL *parentURL = _fileURL.URLByDeletingLastPathComponent;
	ZGVersionControlType versionControlType;
	NSString *label;
	if ([parentURL.lastPathComponent isEqualToString:@".git"])
	{
		label = parentURL.URLByDeletingLastPathComponent.lastPathComponent;
		versionControlType = ZGVersionControlGit;
	}
	else
	{
		NSString *lastPathComponent = _fileURL.lastPathComponent;
		
		if ([lastPathComponent hasPrefix:@"hg-"])
		{
			versionControlType = ZGVersionControlHg;
		}
		else if ([lastPathComponent hasPrefix:@"svn-"])
		{
			versionControlType = ZGVersionControlSvn;
		}
		else
		{
			versionControlType = ZGVersionControlGit;
		}
		
		label = lastPathComponent;
	}
	
	_commitLabelTextField.stringValue = (label == nil) ? @"" : label;
	
	// Give a little vertical padding between the text and the top of the text view container
	NSSize textContainerInset = _textView.textContainerInset;
	_textView.textContainerInset = NSMakeSize(textContainerInset.width, textContainerInset.height + 2);
	
	self.window.titlebarAppearsTransparent = YES;
	
	// Hide the window titlebar buttons
	// We still want the resize functionality to work even though the button is hidden
	[[self.window standardWindowButton:NSWindowCloseButton] setHidden:YES];
	[[self.window standardWindowButton:NSWindowMiniaturizeButton] setHidden:YES];
	[[self.window standardWindowButton:NSWindowZoomButton] setHidden:YES];
	
	// Nobody ever wants these;
	// Because macOS may have some of these settings globally in System Preferences, I don't trust IB very much..
	_textView.automaticDashSubstitutionEnabled = NO;
	_textView.automaticQuoteSubstitutionEnabled = NO;
	
	// Take care of other textview settings...
	[_textView zgLoadDefaults];
	
	_textView.textStorage.delegate = self;
	_textView.layoutManager.delegate = self;
	_textView.delegate = self;
	
	NSString *fontName = [[NSUserDefaults standardUserDefaults] stringForKey:ZGEditorFontNameKey];
	CGFloat fontSize = [[NSUserDefaults standardUserDefaults] doubleForKey:ZGEditorFontNameKey];
	
	NSFont *font;
	if (fontName.length == 0)
	{
		font = [self defaultFontOfSize:fontSize];
	}
	else
	{
		NSFont *userFont = [NSFont fontWithName:fontName size:fontSize];
		if (userFont != nil)
		{
			font = userFont;
		}
		else
		{
			font = [self defaultFontOfSize:fontSize];
		}
	}
	
	NSString *plainString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	if (plainString == nil)
	{
		printf("Error: Couldn't load plain-text from %s\n", _fileURL.path.UTF8String);
		exit(EXIT_FAILURE);
	}
	
	NSAttributedString *plainAttributedString = [[NSAttributedString alloc] initWithString:plainString attributes:@{NSFontAttributeName : font}];
	
	[_textView.textStorage setAttributedString:plainAttributedString];
	
	_commentSectionLength = [self commentSectionLengthForVersionControlType:versionControlType];
	
	NSUInteger commitLength = [self commitTextLengthWithCommentLength:_commentSectionLength];
	
	NSString *content = [plainString substringToIndex:commitLength];
	_initiallyContainedEmptyContent = ([[content stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]] length] == 0);
	
	[_textView setSelectedRange:NSMakeRange(commitLength, 0)];
	if (_commentSectionLength != 0)
	{
		[_textView.textStorage addAttribute:NSForegroundColorAttributeName value:[self colorFromUserDefaultsKey:ZGEditorCommentForegroundColorKey] range:NSMakeRange(plainString.length - _commentSectionLength, _commentSectionLength)];
	}
}

- (NSColor *)colorFromUserDefaultsKey:(NSString *)userDefaultsKey
{
	NSColor *color = nil;
	NSString *colorString = [[NSUserDefaults standardUserDefaults] stringForKey:userDefaultsKey];
	if (colorString != nil)
	{
		NSArray<NSString *> *colorComponents = [colorString componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" ,"]];
		
		if (colorComponents.count == 3)
		{
			color = [NSColor colorWithRed:colorComponents[0].doubleValue green:colorComponents[1].doubleValue blue:colorComponents[2].doubleValue alpha:1.0];
		}
		else if (colorComponents.count == 4)
		{
			color = [NSColor colorWithRed:colorComponents[0].doubleValue green:colorComponents[1].doubleValue blue:colorComponents[2].doubleValue alpha:colorComponents[3].doubleValue];
		}
	}
	
	if (color == nil)
	{
		color = [NSColor colorWithRed:1.0 green:1.0 blue:1.0 alpha:1.0];
	}
	return color;
}

// Don't allow editing the comment section
- (BOOL)textView:(NSTextView *)textView shouldChangeTextInRanges:(NSArray<NSValue *> *)affectedRanges replacementStrings:(NSArray<NSString *> *)__unused replacementStrings
{
	NSUInteger plainTextLength = textView.textStorage.string.length;
	for (NSValue *rangeValue in affectedRanges)
	{
		NSRange range = rangeValue.rangeValue;
		if (range.location + range.length >= plainTextLength - _commentSectionLength)
		{
			return NO;
		}
	}
	return YES;
}

- (void)textStorage:(NSTextStorage *)textStorage didProcessEditing:(NSTextStorageEditActions)editedMask range:(NSRange)__unused editedRange changeInLength:(NSInteger)__unused delta
{
	if ((editedMask & NSTextStorageEditedCharacters) != 0)
	{
		NSUInteger maxRecommendedSubjectLength = (NSUInteger)[[NSUserDefaults standardUserDefaults] integerForKey:ZGEditorRecommendedSubjectLengthLimitKey];
		
		if (maxRecommendedSubjectLength > 0)
		{
			// I am trying to highlight text on the first line if it exceeds certain number of characters (similar to a Twitter mesage overflowing).
			NSString *plainText = textStorage.string;
			if (plainText.length > 0)
			{
				// Remove the attribute everywhere. Might be "inefficient" but it's the easiest most reliable approach I know how to do
				[_textView.textStorage removeAttribute:NSBackgroundColorAttributeName range:NSMakeRange(0, plainText.length)];
				
				// Then get the content line range
				NSUInteger startLineIndex = 0;
				NSUInteger contentEndIndex = 0;
				
				[plainText getLineStart:&startLineIndex end:NULL contentsEnd:&contentEndIndex forRange:NSMakeRange(0, 1)];
				
				NSRange lineContentRange = NSMakeRange(startLineIndex, contentEndIndex - startLineIndex);
				
				// Then get the overflow range
				if (lineContentRange.length > maxRecommendedSubjectLength)
				{
					NSRange overflowRange = NSMakeRange(maxRecommendedSubjectLength, lineContentRange.length - maxRecommendedSubjectLength);
					
					// Highlight the overflow background
					NSColor *overflowColor = [self colorFromUserDefaultsKey:ZGEditorSubjectOverflowBackgroundColorKey];
					[_textView.textStorage addAttribute:NSBackgroundColorAttributeName value:overflowColor range:overflowRange];
				}
			}
		}
	}
}

- (NSDictionary<NSString *,id> *)layoutManager:(NSLayoutManager *)__unused layoutManager shouldUseTemporaryAttributes:(NSDictionary<NSString *, id> *)attrs forDrawingToScreen:(BOOL)toScreen atCharacterIndex:(NSUInteger)__unused charIndex effectiveRange:(NSRangePointer)effectiveCharRange
{
	NSDictionary<NSString *,id> * attributes;
	if (!toScreen)
	{
		attributes = nil;
	}
	else
	{
		// Disable temporary attributes like spell checking if they are in the comment section
		NSUInteger plainTextLength = _textView.textStorage.string.length;
		if (effectiveCharRange->location + effectiveCharRange->length >= plainTextLength - _commentSectionLength)
		{
			attributes = nil;
		}
		else
		{
			attributes = attrs;
		}
	}
	return attributes;
}

- (BOOL)textView:(NSTextView *)__unused textView doCommandBySelector:(SEL)selector
{
	if (selector == @selector(insertNewline:))
	{
		// After the user enters a new line in the first line, we want to insert another newline due to commit'ing conventions
		// for leaving a blank line right after the subject (first) line
		// We will also have some prevention if the user performs a new line more than once consecutively
		BOOL insertsAutomaticNewline = [[NSUserDefaults standardUserDefaults] boolForKey:ZGEditorAutomaticNewlineInsertionAfterSubjectKey];
		
		if (insertsAutomaticNewline)
		{
			if (_preventAccidentalNewline)
			{
				return YES;
			}
			else
			{
				NSArray<NSValue *> *selectedRanges = _textView.selectedRanges;
				if (selectedRanges.count == 1)
				{
					NSRange range = [selectedRanges[0] rangeValue];
					
					NSUInteger lineStartIndex = 0;
					NSString *plainText = _textView.textStorage.string;
					[plainText getLineStart:&lineStartIndex end:NULL contentsEnd:NULL forRange:range];
					
					if (lineStartIndex == 0)
					{
						// By telling NSTextView we are begin/end editing and changed text,
						// the text view will have better undo behavior
						[_textView insertNewline:nil];
						[_textView insertNewline:nil];
						
						_preventAccidentalNewline = YES;
						dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
							self->_preventAccidentalNewline = NO;
						});
						return YES;
					}
				}
			}
		}
	}
	return NO;
}

- (void)exitWithSuccess:(BOOL)success __attribute__((noreturn))
{
	[self saveWindowFrame];
	
	if (success)
	{
		exit(EXIT_SUCCESS);
	}
	else
	{
		// Empty commits should be treated as a success
		// Version control software will be able to handle it as an abort
		if (_initiallyContainedEmptyContent)
		{
			exit(EXIT_SUCCESS);
		}
		else
		{
			exit(EXIT_FAILURE);
		}
	}
}

- (void)windowWillClose:(NSNotification *)__unused notification
{
	[self exitWithSuccess:NO];
}

- (IBAction)commit:(id)__unused sender
{
	NSError *writeError = nil;
	if (![_textView.textStorage.string writeToURL:_fileURL atomically:YES encoding:NSUTF8StringEncoding error:&writeError])
	{
		// Fatal error
		printf("Failed to write to %s because of: %s\n", _fileURL.path.UTF8String, writeError.localizedDescription.UTF8String);
		exit(EXIT_FAILURE);
	}
	
	[self exitWithSuccess:YES];
}

- (IBAction)cancel:(id)__unused sender
{
	[self exitWithSuccess:NO];
}

- (IBAction)selectAllCommitText:(id)__unused sender
{
	NSUInteger commitTextLength = [self commitTextLengthWithCommentLength:_commentSectionLength];
	[_textView setSelectedRange:NSMakeRange(0, commitTextLength)];
}

// The comment range should begin at the first line that starts with a comment string and go to the end of the file
// Make sure to scan from the bottom to top
- (NSUInteger)commentSectionLengthForVersionControlType:(ZGVersionControlType)versionControlType
{
	NSUInteger commentSectionLength = 0;
	
	NSString *plainText = _textView.textStorage.string;
	NSUInteger plainTextLength = plainText.length;
	
	NSUInteger firstCommentLineIndex = 0;
	
	BOOL foundFirstCommentLine = NO;
	
	NSString *prefixCommentString;
	NSString *suffixCommentString;
	switch (versionControlType)
	{
		case ZGVersionControlGit:
			prefixCommentString = @"#";
			suffixCommentString = @"";
			break;
		case ZGVersionControlHg:
			prefixCommentString = @"HG:";
			suffixCommentString = @"";
			break;
		case ZGVersionControlSvn:
			prefixCommentString = @"--";
			suffixCommentString = @"--";
			break;
	}
	
	// Find the first comment line starting from the end of the document to get the comment range to the end of the document
	NSUInteger characterIndex = plainTextLength;
	while (characterIndex > 0)
	{
		characterIndex--;
		
		NSUInteger lineStartIndex = 0;
		NSUInteger contentEndIndex = 0;
		[plainText getLineStart:&lineStartIndex end:NULL contentsEnd:&contentEndIndex forRange:NSMakeRange(characterIndex, 0)];
		
		NSString *line = [plainText substringWithRange:NSMakeRange(lineStartIndex, contentEndIndex - lineStartIndex)];
		
		// See if we don't have a comment
		// Note a line that is "--" could have the prefix and suffix the same, but we want to make sure it's at least "--...--"
		// Also empty strings don't yield the expected behavior for hasSuffix:/hasPrefix:
		if (![line hasPrefix:prefixCommentString] || (line.length < prefixCommentString.length + suffixCommentString.length) ||  (suffixCommentString.length > 0 && ![line hasSuffix:suffixCommentString]))
		{
			if (foundFirstCommentLine)
			{
				commentSectionLength = plainTextLength - firstCommentLineIndex;
				break;
			}
		}
		else
		{
			foundFirstCommentLine = YES;
			firstCommentLineIndex = lineStartIndex;
		}
		
		characterIndex = lineStartIndex;
	}
	
	return commentSectionLength;
}

// The content range should extend to before the comments, only allowing one trailing newline in between the comments and content
// The comment range should begin at the first line that starts with '#' and end to end of the file
// Make sure to scan from the bottom to top
- (NSUInteger)commitTextLengthWithCommentLength:(NSUInteger)commentLength
{
	NSString *plainText = _textView.textStorage.string;
	
	// Find the first real character or anything past the 1st newline before the comment section
	NSUInteger bestEndCharacterIndex = plainText.length - commentLength;
	BOOL passedNewline = NO;
	while (bestEndCharacterIndex > 0)
	{
		bestEndCharacterIndex--;
		
		unichar character = [plainText characterAtIndex:bestEndCharacterIndex];
		if (character == '\n')
		{
			if (passedNewline)
			{
				break;
			}
			passedNewline = YES;
		}
		else
		{
			bestEndCharacterIndex++;
			break;
		}
	}
	
	return bestEndCharacterIndex;
}

@end
