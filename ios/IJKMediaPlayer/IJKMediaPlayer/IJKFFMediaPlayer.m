/*
 * IJKFFMoviePlayerDef.m
 *
 * Copyright (c) 2019 Befovy <befovy@gmail.com>
 *
 * This file is part of fijkPlayer.
 *
 * ijkPlayer is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * ijkPlayer is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with ijkPlayer; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */

#import "IJKFFMediaPlayer.h"

#import "IJKFFMoviePlayerDef.h"
#import "IJKAudioKit.h"
#import "IJKFFOptions.h"
#import "ijkplayer/ijkplayer.h"


@interface IJKFFWeakHolder : NSObject
@property (nonatomic, weak) id object;
@end

@implementation IJKFFWeakHolder
@end


@implementation IJKFFMediaPlayer {
    IjkMediaPlayer* _nativeMediaPlayer;
    IJKFFMoviePlayerMessagePool *_msgPool;

    NSMutableSet<id<IJKMPEventHandler>> *_eventHandlers;
    id<IJKCVPBViewProtocol> _cvPBView;

    NSString *_dataSource;

    CFDictionaryRef _optionsDictionary;
}


@synthesize fps = _fps;
@synthesize isThirdGLView = _isThirdGLView;
@synthesize scaleFactor = _scaleFactor;

- (IJKFFMoviePlayerMessage *) obtainMessage {
    return [_msgPool obtain];
}

inline static IJKFFMediaPlayer *ffplayerRetain(void *arg) {
    return (__bridge_transfer IJKFFMediaPlayer *) arg;
}

int ff_media_player_msg_loop(void* arg)
{
    @autoreleasepool {
        IjkMediaPlayer *mp = (IjkMediaPlayer*)arg;
        __weak IJKFFMediaPlayer *ffPlayer = ffplayerRetain(ijkmp_set_weak_thiz(mp, NULL));
        while (ffPlayer) {
            @autoreleasepool {
                IJKFFMoviePlayerMessage *msg = [ffPlayer obtainMessage];
                if (!msg)
                    break;
                
                int retval = ijkmp_get_msg(mp, &msg->_msg, 1);
                if (retval < 0)
                    break;
                
                // block-get should never return 0
                assert(retval > 0);
                [ffPlayer performSelectorOnMainThread:@selector(postEvent:) withObject:msg waitUntilDone:NO];
            }
        }
        
        // retained in prepare_async, before SDL_CreateThreadEx
        ijkmp_dec_ref_p(&mp);
        return 0;
    }
}

- (IJKFFMediaPlayer *)init
{
    self = [super init];
    if (self) {
        ijkmp_global_init();
        _msgPool = [[IJKFFMoviePlayerMessagePool alloc] init];
        _eventHandlers = [[NSMutableSet alloc] init];
        [self nativeSetup];
        
        ijkmp_set_option(_nativeMediaPlayer, IJKMP_OPT_CATEGORY_PLAYER, "overlay-format", "fcc-_es2");
        
        [[IJKAudioKit sharedInstance] setupAudioSession];
        _optionsDictionary = nil;
        _isThirdGLView = true;
        _scaleFactor = 1.0f;
        _fps = 1.0f;
    }
    return self;
}

- (void) nativeSetup
{
    _nativeMediaPlayer = ijkmp_ios_create(ff_media_player_msg_loop);
    
    IJKFFWeakHolder *weakHolder = [[IJKFFWeakHolder alloc] init];
    weakHolder.object = self;
    
    ijkmp_set_weak_thiz(_nativeMediaPlayer, (__bridge_retained void *) self);
    ijkmp_set_inject_opaque(_nativeMediaPlayer, (__bridge_retained void *) weakHolder);
    ijkmp_set_ijkio_inject_opaque(_nativeMediaPlayer, (__bridge_retained void *) weakHolder);
}

- (void)postEvent: (IJKFFMoviePlayerMessage *)msg
{
    if (!msg)
        return;
    
    AVMessage *avmsg = &msg->_msg;
    for (id<IJKMPEventHandler> handler in _eventHandlers) {
        [handler onEvent4Player:self withType:avmsg->what andArg1:avmsg->arg1 andArg2:avmsg->arg2 andExtra:avmsg->obj];
    }
    [_msgPool recycle:msg];
}

- (int) prepareAsync
{
    return ijkmp_prepare_async(_nativeMediaPlayer);
}

- (int) setDataSource:(NSString *)url
{
    _dataSource = url;
    return ijkmp_set_data_source(_nativeMediaPlayer, [url UTF8String]);
}

- (int) start
{
    return ijkmp_start(_nativeMediaPlayer);
}

- (int) stop
{
    return ijkmp_stop(_nativeMediaPlayer);
}

- (int) pause
{
    return ijkmp_pause(_nativeMediaPlayer);
}

- (BOOL) isPlaying
{
    return ijkmp_is_playing(_nativeMediaPlayer);
}

- (long) getCurrentPosition
{
    return ijkmp_get_current_position(_nativeMediaPlayer);
}

- (long) getDuration
{
    return ijkmp_get_duration(_nativeMediaPlayer);
}

- (int) seekTo:(long) msec
{
    return ijkmp_seek_to(_nativeMediaPlayer, msec);
}


- (void) setLoop:(int) loop
{
    ijkmp_set_loop(_nativeMediaPlayer, loop);
}

- (int) getLoop
{
    return ijkmp_get_loop(_nativeMediaPlayer);
}

- (void) setSpeed:(float) speed
{
    ijkmp_set_property_float(_nativeMediaPlayer, FFP_PROP_FLOAT_PLAYBACK_RATE, speed);
}

- (void) setStreamSelected:(int) stream selected:(BOOL) selected
{
    ijkmp_set_stream_selected(_nativeMediaPlayer, stream, selected);
}

- (float) getFloatProperty:(int) property defalut:(float) value
{
    return ijkmp_get_property_float(_nativeMediaPlayer, property, value);
}

- (int64_t) getLongProperty:(int) property default:(int64_t) value
{
    return ijkmp_get_property_int64(_nativeMediaPlayer, property, value);
}


- (void)setPlaybackVolume:(float)volume
{
    if (!_nativeMediaPlayer)
        return;
    ijkmp_set_playback_volume(_nativeMediaPlayer, volume);
}

- (float)playbackVolume
{
    if (!_nativeMediaPlayer)
        return 0.0f;
    return ijkmp_get_property_float(_nativeMediaPlayer, FFP_PROP_FLOAT_PLAYBACK_VOLUME, 1.0f);
}

- (void) shutdown
{
    ijkmp_shutdown(_nativeMediaPlayer);
    
    __unused id weakPlayer = (__bridge_transfer IJKFFMediaPlayer*)ijkmp_set_weak_thiz(_nativeMediaPlayer, NULL);
    __unused id weakHolder = (__bridge_transfer IJKFFWeakHolder*)ijkmp_set_inject_opaque(_nativeMediaPlayer, NULL);
    __unused id weakijkHolder = (__bridge_transfer IJKFFWeakHolder*)ijkmp_set_ijkio_inject_opaque(_nativeMediaPlayer, NULL);

    if (_optionsDictionary)
        CFRelease(_optionsDictionary);

    [_eventHandlers removeAllObjects];
    ijkmp_dec_ref_p(&_nativeMediaPlayer);
}

- (int) reset
{
    ijkmp_stop(_nativeMediaPlayer);
    ijkmp_reset(_nativeMediaPlayer);
    return 0;
}


- (void)setOptionValue:(NSString *)value
                forKey:(NSString *)key
            ofCategory:(IJKFFOptionCategory)category
{
    ijkmp_set_option(_nativeMediaPlayer, category, [key UTF8String], [value UTF8String]);
}

- (void)setOptionIntValue:(int64_t)value
                   forKey:(NSString *)key
               ofCategory:(IJKFFOptionCategory)category
{
    ijkmp_set_option_int(_nativeMediaPlayer, category, [key UTF8String], value);
}



- (void) addIJKMPEventHandler:(id<IJKMPEventHandler>) handler
{
    [_eventHandlers addObject:handler];
}

- (void) removeIJKMPEventHandler:(id<IJKMPEventHandler>) handler
{
    [_eventHandlers removeObject:handler];
}

- (void) display_pixels:(IJKOverlay *)overlay
{
    if (overlay->pixel_buffer != nil && _cvPBView != nil) {
        [_cvPBView display_pixelbuffer:overlay->pixel_buffer];
    } else if (_cvPBView != nil && overlay->format == SDL_FCC_BGRA){
        CVPixelBufferRef pixelBuffer;
        
        // CVPixelBufferCreateWithBytes lead to crash if reset player
        // and then setDataSource and play again.
        /*
        int retval = CVPixelBufferCreateWithBytes(
                                            kCFAllocatorDefault,
                                            (size_t) overlay->w,
                                            (size_t) overlay->h,
                                            kCVPixelFormatType_32BGRA,
                                            overlay->pixels[0],
                                            overlay->pitches[0],
                                            NULL, NULL, _optionsDictionary,
                                            &pixelBuffer);
         */
        int retval = CVPixelBufferCreate(kCFAllocatorDefault,
                                         (size_t) overlay->w,
                                         (size_t) overlay->h,
                                         kCVPixelFormatType_32BGRA,
                                         _optionsDictionary,
                                         &pixelBuffer);
        if (retval == kCVReturnSuccess) {
            CVPixelBufferLockBaseAddress(pixelBuffer, 0);
            uint8_t *dst = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);
            memcpy(dst, overlay->pixels[0], overlay->pitches[0] * overlay->h);
            CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
            [_cvPBView display_pixelbuffer:pixelBuffer];
            CVPixelBufferRelease(pixelBuffer);
        }
    }
}

- (void) setupCVPixelBufferView:(id<IJKCVPBViewProtocol>) cvPBView
{
    _cvPBView = cvPBView;
    
    const void *keys[] = {
        kCVPixelBufferOpenGLESCompatibilityKey,
        kCVPixelBufferIOSurfacePropertiesKey,
    };
    const void *values[] = {
        (__bridge const void *) (@YES),
        (__bridge const void *) ([NSDictionary dictionary]),
    };
    
    _optionsDictionary = CFDictionaryCreate(kCFAllocatorDefault, keys, values, 2,
                                            &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    ijkmp_ios_set_glview(_nativeMediaPlayer, self);
}

- (UIImage *)snapshot
{
    return nil;
}

@end
