//
//  HLSEventProducer.m
//  CameraTest
//
//  Created by Camillus Gerard Cai on 30/3/13.
//  Copyright (c) 2013 nus.cs3217. All rights reserved.
//

#import "HLSEventProducer.h"

NSInteger const cInvalidId = -1;
CGFloat const cMaxIntervalOffset = 1.;
NSString *const cPlaylistNameFormat = @"rec-%d.m3u8";
NSString *const cMediaDirectoryFormat = @"mdir-%d";
NSString *const cMediaItemRelativePathFormat = @"%@/%@";

@interface HLSEventProducer ()
// Internal.
@property (strong) NSString *_playlistDirectory;
@property (atomic) CGFloat _chunkInterval;
@property (strong) NSString *_preset;
@property (atomic) NSInteger _curRecordingId;

// Serious business.
@property (strong) TimedChunkingVideoRecorder *_timedRecorder;
@property (strong) HLSEventPlaylistHelper *_playlistHelper;

- (NSString *) relativePathFromURL:(NSURL *)url;
- (NSString *) currentMediaDirectory;

@end

@implementation HLSEventProducer
// External.
@synthesize delegate;
@synthesize previewLayer;

// Internal.
@synthesize _playlistDirectory;
@synthesize _chunkInterval;
@synthesize _preset;
@synthesize _curRecordingId;

// Serious business.
@synthesize _timedRecorder;
@synthesize _playlistHelper;

#pragma mark Constructors
- (id) initWithDelegate:(id<HLSEventProducerDelegate>)del playlistDirectory:(NSString *)dir chunkDuration:(CGFloat)interval videoPreset:(NSString *)preset{
    if (self = [super init]) {
        delegate = del;
        _playlistDirectory = dir;
        _chunkInterval = interval;
        _preset = preset;
        _curRecordingId = cInvalidId;
        
        _timedRecorder = [[TimedChunkingVideoRecorder alloc] initWithPreset:_preset];
        _timedRecorder.delegate = self;
        [_timedRecorder startPreview];
        
        _playlistHelper = nil; // The playlist helper class should be instantiated per playlist.
    }
    return self;
}

#pragma mark Production Operations
// TODO: Refactor.
- (NSInteger) startNewRecording {
    if (_timedRecorder.isRecording) {
        // Do not take action if this method was called when a recording is in progress.
        return cInvalidId;
    }
    
    _curRecordingId = [delegate newRecordingId];
    
    // Initialize the playlist.
    NSString *playlistName = [NSString stringWithFormat:cPlaylistNameFormat, _curRecordingId];
    NSString *playlistPath = [_playlistDirectory stringByAppendingPathComponent:playlistName];
    NSLog(@"playlistPath=%@", playlistPath); // Debug.
    NSURL *playlistURL = [NSURL fileURLWithPath:playlistPath];
    _playlistHelper = [[HLSEventPlaylistHelper alloc] initWithFileURL:playlistURL];
    [_playlistHelper beginPlaylistWithTargetInterval:(_chunkInterval + cMaxIntervalOffset)]; // Add a small offset to _chunkInterval in case the chunking exceeds the maximum allowed HLS chunk size by a tiny bit.
    
    // Create media content directory.
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *mediaDirectory = [_playlistDirectory stringByAppendingPathComponent:[self currentMediaDirectory]];
    NSLog(@"mediaDirectory=%@", mediaDirectory); // Debug.
    BOOL isDirectory = NO;
    if ([fm fileExistsAtPath:mediaDirectory isDirectory:&isDirectory] && isDirectory) {
        [fm removeItemAtPath:mediaDirectory error:nil];
    }
    [fm createDirectoryAtPath:mediaDirectory withIntermediateDirectories:NO attributes:nil error:nil];
    
    // Start recording.
    [_timedRecorder startTimedRecordingToDirectory:mediaDirectory chunkInterval:_chunkInterval];
    
    return _curRecordingId;
}

- (void) endRecording {
    [_timedRecorder stopRecording];
}

#pragma mark ChunkingVideoRecorderDelegate Methods
- (void) recorder:(ChunkingVideoRecorder *)recorder didChunk:(NSURL *)chunk index:(NSUInteger)index duration:(NSTimeInterval)duration {
    NSLog(@"Recording chunked."); // Debug.
    
    [_playlistHelper appendItem:[self relativePathFromURL:chunk] withDuration:duration];
}

- (void) recorder:(ChunkingVideoRecorder *)recorder didStopRecordingWithChunk:(NSURL *)chunk index:(NSUInteger)index duration:(NSTimeInterval)duration {
    NSLog(@"Recording ended (last chunk)."); // Debug.
    
    [_playlistHelper appendItem:[self relativePathFromURL:chunk] withDuration:duration];
    [_playlistHelper endPlaylist];
    
    _curRecordingId = cInvalidId;
    _playlistHelper = nil;
}

- (void) recorderDidStartRecording:(ChunkingVideoRecorder *)recorder {
    NSLog(@"Recording started."); // Debug.
}

#pragma mark Custom Accessors
// The following accessors pass-through to the underlying video recording object.
- (BOOL) isPreviewing {
    if (_timedRecorder) {
        return _timedRecorder.isPreviewing;
    } else {
        return NO;
    }
}

- (BOOL) isRecording {
    if (_timedRecorder) {
        return _timedRecorder.isRecording;
    } else {
        return NO;
    }
}

- (AVCaptureVideoPreviewLayer *) previewLayer {
    if (_timedRecorder) {
        return _timedRecorder.previewLayer;
    } else {
        return nil;
    }
}

#pragma mark Utility
- (NSString *) relativePathFromURL:(NSURL *)url {
    NSString *fileName = [url lastPathComponent];
    NSString *relPath = [NSString stringWithFormat:cMediaItemRelativePathFormat, [self currentMediaDirectory], fileName];
    return relPath;
}

- (NSString *) currentMediaDirectory {
    return [NSString stringWithFormat:cMediaDirectoryFormat, _curRecordingId];
}

@end
