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
#import "ECVSTK1160Device.h"

// Other Sources
#import "ECVDebug.h"

enum {
	ECVHighFieldFlag = 1 << 6,
	ECVNewImageFlag = 1 << 7,
};

static NSString *const ECVSTK1160VideoSourceKey = @"ECVSTK1160VideoSource";
static NSString *const ECVSTK1160VideoFormatKey = @"ECVSTK1160VideoFormat";

@implementation ECVSTK1160Device

#pragma mark +NSObject

+ (void)initialize
{
	[[NSUserDefaults standardUserDefaults] registerDefaults:[NSDictionary dictionaryWithObjectsAndKeys:
		[NSNumber numberWithUnsignedInteger:ECVSTK1160Composite1Input], ECVSTK1160VideoSourceKey,
		[NSNumber numberWithUnsignedInteger:ECVSTK1160NTSCMFormat], ECVSTK1160VideoFormatKey,
		nil]];
}

#pragma mark -ECVSTK1160Device

@synthesize videoSource = _videoSource;
- (void)setVideoSource:(ECVSTK1160VideoSource)source
{
	if(source == _videoSource) return;
	ECVPauseWhile(self, { _videoSource = source; });
	[[NSUserDefaults standardUserDefaults] setInteger:source forKey:ECVSTK1160VideoSourceKey];
}
@synthesize videoFormat = _videoFormat;
- (void)setVideoFormat:(ECVSTK1160VideoFormat)format
{
	if(format == _videoFormat) return;
	ECVPauseWhile(self, { _videoFormat = format; });
	[[NSUserDefaults standardUserDefaults] setInteger:format forKey:ECVSTK1160VideoFormatKey];
}

#pragma mark -ECVCaptureDevice

- (id)initWithService:(io_service_t)service error:(out NSError **)outError
{
	if((self = [super initWithService:service error:outError])) {
		NSUserDefaults *const d = [NSUserDefaults standardUserDefaults];
		[self setVideoSource:[d integerForKey:ECVSTK1160VideoSourceKey]];
		[self setVideoFormat:[d integerForKey:ECVSTK1160VideoFormatKey]];
		_SAA711XChip = [[SAA711XChip alloc] init];
		[_SAA711XChip setDevice:self];
		[_SAA711XChip setBrightness:[[d objectForKey:ECVBrightnessKey] doubleValue]];
		[_SAA711XChip setContrast:[[d objectForKey:ECVContrastKey] doubleValue]];
		[_SAA711XChip setSaturation:[[d objectForKey:ECVSaturationKey] doubleValue]];
		[_SAA711XChip setHue:[[d objectForKey:ECVHueKey] doubleValue]];
	}
	return self;
}

#pragma mark -

- (void)threaded_readImageBytes:(UInt8 const *)bytes length:(size_t)length
{
	if(!length) return;
	size_t skip = 4;
	if(ECVNewImageFlag & bytes[0]) {
		[self threaded_startNewImageWithFieldType:ECVHighFieldFlag & bytes[0] ? ECVHighField : ECVLowField];
		skip = 8;
	}
	if(length > skip) [super threaded_readImageBytes:bytes + skip length:length - skip];
}

#pragma mark -ECVCaptureController(ECVAbstract)

- (BOOL)requiresHighSpeed
{
	return YES;
}
- (ECVPixelSize)captureSize
{
	return (ECVPixelSize){720, [self is60HzFormat] ? 480 : 576};
}
- (NSUInteger)simultaneousTransfers
{
	return 2;
}
- (NSUInteger)microframesPerTransfer
{
	return 512;
}
- (UInt8)isochReadingPipe
{
	return 2;
}
- (QTTime)frameRate
{
	return [self is60HzFormat] ? QTMakeTime(1001, 60000) : QTMakeTime(1, 50);
}

#pragma mark -

- (BOOL)threaded_play
{
	dev_stk0408_initialize_device(self);
	if(![_SAA711XChip initializeRegisters]) return NO;
	if([self videoSource] != ECVSTK1160SECAMFormat) dev_stk0408_write0(self, 1 << 7 | 0x3 << 3, 1 << 7 | (4 - [self videoSource]) << 3);
	dev_stk0408_init_camera(self);
	dev_stk0408_set_resolution(self);
	dev_stk11xx_camera_on(self);
	dev_stk0408_set_streaming(self, YES);
	return YES;
}
- (BOOL)threaded_pause
{
	dev_stk0408_set_streaming(self, NO);
	dev_stk11xx_camera_off(self);
	return YES;
}
- (BOOL)threaded_watchdog
{
	SInt32 value;
	if(![self readValue:&value atIndex:0x01]) return NO;
	if(0x03 != value) {
		ECVLog(ECVError, @"Device watchdog was 0x%02x (should be 0x03).", value);
		return NO;
	}
	return YES;
}

#pragma mark -NSObject

- (void)dealloc
{
	[_SAA711XChip setDevice:nil];
	[_SAA711XChip release];
	[super dealloc];
}

#pragma mark -<ECVCaptureControllerConfiguring>

- (NSArray *)allVideoSourceObjects
{
	return [NSArray arrayWithObjects:
		[NSNumber numberWithUnsignedInteger:ECVSTK1160SVideoInput],
		[NSNumber numberWithUnsignedInteger:ECVSTK1160Composite1Input],
		[NSNumber numberWithUnsignedInteger:ECVSTK1160Composite2Input],
		[NSNumber numberWithUnsignedInteger:ECVSTK1160Composite3Input],
		[NSNumber numberWithUnsignedInteger:ECVSTK1160Composite4Input],
		nil];
}
- (id)videoSourceObject
{
	return [NSNumber numberWithUnsignedInteger:[self videoSource]];
}
- (void)setVideoSourceObject:(id)obj
{
	[self setVideoSource:[obj unsignedIntegerValue]];
}
- (NSString *)localizedStringForVideoSourceObject:(id)obj
{
	switch([obj unsignedIntegerValue]) {
		case ECVSTK1160SVideoInput: return NSLocalizedString(@"S-Video", nil);
		case ECVSTK1160Composite1Input: return NSLocalizedString(@"Composite 1", nil);
		case ECVSTK1160Composite2Input: return NSLocalizedString(@"Composite 2", nil);
		case ECVSTK1160Composite3Input: return NSLocalizedString(@"Composite 3", nil);
		case ECVSTK1160Composite4Input: return NSLocalizedString(@"Composite 4", nil);
	}
	return nil;
}
- (BOOL)isValidVideoSourceObject:(id)obj
{
	return YES;
}
- (NSInteger)indentationLevelForVideoSourceObject:(id)obj
{
	return 0;
}

#pragma mark -

- (NSArray *)allVideoFormatObjects
{
	return [NSArray arrayWithObjects:
		NSLocalizedString(@"60Hz", nil),
		[NSNumber numberWithUnsignedInteger:ECVSTK1160NTSCMFormat],
		[NSNumber numberWithUnsignedInteger:ECVSTK1160PAL60Format],
		[NSNumber numberWithUnsignedInteger:ECVSTK1160PALMFormat],
		[NSNumber numberWithUnsignedInteger:ECVSTK1160NTSC44360HzFormat],
		[NSNumber numberWithUnsignedInteger:ECVSTK1160NTSCJFormat],
		NSLocalizedString(@"50Hz", nil),
		[NSNumber numberWithUnsignedInteger:ECVSTK1160PALBGDHIFormat],
		[NSNumber numberWithUnsignedInteger:ECVSTK1160PALNFormat],
		[NSNumber numberWithUnsignedInteger:ECVSTK1160NTSCNFormat],
		[NSNumber numberWithUnsignedInteger:ECVSTK1160NTSC44350HzFormat],
		[NSNumber numberWithUnsignedInteger:ECVSTK1160SECAMFormat],
		nil];
}
- (id)videoFormatObject
{
	return [NSNumber numberWithUnsignedInteger:[self videoFormat]];
}
- (void)setVideoFormatObject:(id)obj
{
	[self setVideoFormat:[obj unsignedIntegerValue]];
}
- (NSString *)localizedStringForVideoFormatObject:(id)obj
{
	if(![obj isKindOfClass:[NSNumber class]]) return [obj description];
	switch([obj unsignedIntegerValue]) {
		case ECVSTK1160Auto60HzFormat   : return NSLocalizedString(@"Auto-detect", nil);
		case ECVSTK1160NTSCMFormat      : return NSLocalizedString(@"NTSC", nil);
		case ECVSTK1160PAL60Format      : return NSLocalizedString(@"PAL-60", nil);
		case ECVSTK1160PALMFormat       : return NSLocalizedString(@"PAL-M", nil);
		case ECVSTK1160NTSC44360HzFormat: return NSLocalizedString(@"NTSC 4.43", nil);
		case ECVSTK1160NTSCJFormat      : return NSLocalizedString(@"NTSC-J", nil);

		case ECVSTK1160Auto50HzFormat   : return NSLocalizedString(@"Auto-detect", nil);
		case ECVSTK1160PALBGDHIFormat   : return NSLocalizedString(@"PAL", nil);
		case ECVSTK1160PALNFormat       : return NSLocalizedString(@"PAL-N", nil);
		case ECVSTK1160NTSC44350HzFormat: return NSLocalizedString(@"NTSC 4.43", nil);
		case ECVSTK1160NTSCNFormat      : return NSLocalizedString(@"NTSC-N", nil);
		case ECVSTK1160SECAMFormat      : return NSLocalizedString(@"SECAM", nil);
		default: return nil;
	}
}
- (BOOL)isValidVideoFormatObject:(id)obj
{
	return [obj isKindOfClass:[NSNumber class]];
}
- (NSInteger)indentationLevelForVideoFormatObject:(id)obj
{
	return [self isValidVideoFormatObject:obj] ? 1 : 0;
}

#pragma mark -

- (CGFloat)brightness
{
	return [_SAA711XChip brightness];
}
- (void)setBrightness:(CGFloat)val
{
	[_SAA711XChip setBrightness:val];
	[[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithDouble:val] forKey:ECVBrightnessKey];
}
- (CGFloat)contrast
{
	return [_SAA711XChip contrast];
}
- (void)setContrast:(CGFloat)val
{
	[_SAA711XChip setContrast:val];
	[[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithDouble:val] forKey:ECVContrastKey];
}
- (CGFloat)saturation
{
	return [_SAA711XChip saturation];
}
- (void)setSaturation:(CGFloat)val
{
	[_SAA711XChip setSaturation:val];
	[[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithDouble:val] forKey:ECVSaturationKey];
}
- (CGFloat)hue
{
	return [_SAA711XChip hue];
}
- (void)setHue:(CGFloat)val
{
	[_SAA711XChip setHue:val];
	[[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithDouble:val] forKey:ECVHueKey];
}

#pragma mark -<ECVComponentConfiguring>

- (long)inputCapabilityFlags
{
	return digiInDoesNTSC | digiInDoesPAL | digiInDoesSECAM | digiInDoesColor | digiInDoesComposite | digiInDoesSVideo;
}

#pragma mark -

- (short)numberOfInputs
{
	return [[self allVideoSourceObjects] count];
}
- (short)inputIndex
{
	return [[self allVideoSourceObjects] indexOfObject:[self videoSourceObject]];
}
- (void)setInputIndex:(short)i
{
	[self setVideoSourceObject:[[self allVideoSourceObjects] objectAtIndex:i]];
}
- (short)inputFormatForInputAtIndex:(short)i
{
	switch([[[self allVideoSourceObjects] objectAtIndex:i] unsignedIntegerValue]) {
		case ECVSTK1160SVideoInput:
			return sVideoIn;
		case ECVSTK1160Composite1Input:
		case ECVSTK1160Composite2Input:
		case ECVSTK1160Composite3Input:
		case ECVSTK1160Composite4Input:
			return compositeIn;
		default:
			ECVAssertNotReached(@"Invalid input %hi.", i);
			return 0;
	}
}
- (NSString *)localizedStringForInputAtIndex:(long)i
{
	return [self localizedStringForVideoSourceObject:[[self allVideoSourceObjects] objectAtIndex:i]];
}

#pragma mark -

- (short)inputStandard
{
	switch([self videoFormat]) {
		case ECVSTK1160NTSCMFormat: return ntscReallyIn;
		case ECVSTK1160PALBGDHIFormat: return palIn;
		case ECVSTK1160SECAMFormat: return secamIn;
		default: return currentIn;
	}
}
- (void)setInputStandard:(short)standard
{
	ECVSTK1160VideoFormat format;
	switch(standard) {
		case ntscReallyIn: format = ECVSTK1160NTSCMFormat; break;
		case palIn: format = ECVSTK1160PALBGDHIFormat; break;
		case secamIn: format = ECVSTK1160SECAMFormat; break;
		default: return;
	}
	[self setVideoFormat:format];
}

#pragma mark -<SAA711XDevice>

- (BOOL)writeSAA711XRegister:(u_int8_t)reg value:(int16_t)val
{
	usb_stk11xx_write_registry(self, 0x0204, reg);
	usb_stk11xx_write_registry(self, 0x0205, val);
	usb_stk11xx_write_registry(self, 0x0200, 0x0001);
	return dev_stk0408_check_device(self) == 0;
}
- (SAA711XMODESource)SAA711XMODESource
{
	switch([self videoSource]) {
		case ECVSTK1160SVideoInput: return SAA711XMODESVideoAI12_YGain;
		default: return SAA711XMODECompositeAI11;
	}
}
- (BOOL)SVideo
{
	return ECVSTK1160SVideoInput == [self videoSource];
}
- (SAA711XCSTDFormat)SAA711XCSTDFormat
{
	switch([self videoFormat]) {
		case ECVSTK1160Auto60HzFormat:    return SAA711XAUTO0AutomaticChrominanceStandardDetection;
		case ECVSTK1160NTSCMFormat:       return SAA711XCSTDNTSCM;
		case ECVSTK1160PAL60Format:       return SAA711XCSTDPAL60Hz;
		case ECVSTK1160PALMFormat:        return SAA711XCSTDPALM;
		case ECVSTK1160NTSC44360HzFormat: return SAA711XCSTDNTSC44360Hz;
		case ECVSTK1160NTSCJFormat:       return SAA711XCSTDNTSCJ;

		case ECVSTK1160Auto50HzFormat:    return SAA711XAUTO0AutomaticChrominanceStandardDetection;
		case ECVSTK1160PALBGDHIFormat:    return SAA711XCSTDPAL_BGDHI;
		case ECVSTK1160PALNFormat:        return SAA711XCSTDPALN;
		case ECVSTK1160NTSC44350HzFormat: return SAA711XCSTDNTSC44350Hz;
		case ECVSTK1160NTSCNFormat:       return SAA711XCSTDNTSCN;
		case ECVSTK1160SECAMFormat:       return SAA711XCSTDSECAM;
		default: return 0;
	}
}
- (BOOL)is60HzFormat
{
	switch([self videoFormat]) {
		case ECVSTK1160Auto60HzFormat:
		case ECVSTK1160NTSCMFormat:
		case ECVSTK1160PAL60Format:
		case ECVSTK1160PALMFormat:
		case ECVSTK1160NTSC44360HzFormat:
		case ECVSTK1160NTSCJFormat:
			return YES;
		case ECVSTK1160Auto50HzFormat:
		case ECVSTK1160PALBGDHIFormat:
		case ECVSTK1160PALNFormat:
		case ECVSTK1160NTSCNFormat:
		case ECVSTK1160NTSC44350HzFormat:
		case ECVSTK1160SECAMFormat:
			return NO;
		default:
			ECVAssertNotReached(@"Invalid video format.");
			return NO;
	}
}
- (BOOL)SAA711XRTP0OutputPolarityInverted
{
	return YES;
}

@end
