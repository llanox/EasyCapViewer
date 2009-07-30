/* Copyright (c) 2009, Ben Trask
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * The names of its contributors may be used to endorse or promote products
      derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY BEN TRASK ''AS IS'' AND ANY
EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL BEN TRASK BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE. */
#import "MPLWindow.h"

@interface MPLWindow (Private)

- (void)_hideCursorAfterDelay:(BOOL)flag;
- (void)_delayedHideCursor;

@end

@implementation MPLWindow

#pragma mark Private Protocol

- (void)_hideCursorAfterDelay:(BOOL)flag
{
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(_delayedHideCursor) object:nil];
	if([self isKeyWindow]) [self performSelector:@selector(_delayedHideCursor) withObject:nil afterDelay:3.0f inModes:[NSArray arrayWithObject:(NSString *)kCFRunLoopDefaultMode]];
}
- (void)_delayedHideCursor
{
	[NSCursor setHiddenUntilMouseMoves:YES];
}

#pragma mark NSMenuValidation Protocol

- (BOOL)validateMenuItem:(NSMenuItem *)anItem
{
	if([anItem action] == @selector(performClose:)) return YES;
	return [super validateMenuItem:anItem];
}

#pragma mark NSWindow

- (id)initWithContentRect:(NSRect)aRect
      styleMask:(NSUInteger)aStyle
      backing:(NSBackingStoreType)bufferingType
      defer:(BOOL)flag
{
	if((self = [super initWithContentRect:aRect styleMask:aStyle backing:bufferingType defer:flag])) {
		[self setAcceptsMouseMovedEvents:YES];
	}
	return self;
}

#pragma mark -

- (BOOL)canBecomeKeyWindow
{
	return YES;
}
- (BOOL)canBecomeMainWindow
{
	return YES;
}
- (void)resignKeyWindow
{
	[super resignKeyWindow];
	[self _hideCursorAfterDelay:NO];
}
- (void)becomeKeyWindow
{
	[super becomeKeyWindow];
	[self _hideCursorAfterDelay:YES];
}

#pragma mark -

- (IBAction)performClose:(id)sender
{
	if(NSClosableWindowMask & [self styleMask]) [super performClose:sender];
	else [self close];
}
- (void)sendEvent:(NSEvent *)anEvent
{
	if([anEvent type] == NSMouseMoved) [self _hideCursorAfterDelay:YES];
	[super sendEvent:anEvent];
}

@end
