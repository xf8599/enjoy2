#ifndef enjoy3_Bridging_Header_h
#define enjoy3_Bridging_Header_h

#import <Cocoa/Cocoa.h>
#import <IOKit/hid/IOHIDLib.h>
#import <Carbon/Carbon.h>

// AXIsProcessTrustedWithOptions / kAXTrustedCheckOptionPrompt 在这里
#import <ApplicationServices/ApplicationServices.h>

// Sparkle 1.x 是 OC 框架, 直接 import 主头即可被 Swift 调用
#import <Sparkle/Sparkle.h>

#endif