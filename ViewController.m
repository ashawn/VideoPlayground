//
//  ViewController.m
//  yyvideolibtest
//
//  Created by ashawn on 2021/7/27.
//

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>
#import "YVLGLView.h"

@interface ViewController ()

@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) AVPlayerItemVideoOutput *playerItemOutput;
@property (nonatomic, strong) CADisplayLink *displayLink;
@property(nonatomic, strong) NSRunLoop * runloop;
@property(nonatomic, strong) NSPort * port;
@property(nonatomic, assign) BOOL stopLoopRunning;

@property (nonatomic, strong) UIButton *playBtn;
@property (nonatomic, strong) YVLGLView *glView;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(displayLinkCallback:)];
    self.displayLink.paused = YES;
    
    self.view.backgroundColor = [UIColor blackColor];
    
    self.playBtn = [[UIButton alloc] initWithFrame:CGRectMake(100, 100, 100, 100)];
    self.playBtn.backgroundColor = [UIColor redColor];
    [self.playBtn addTarget:self action:@selector(playClick) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.playBtn];
    
    self.glView = [[YVLGLView alloc] initWithFrame:CGRectMake(50, 300, 320, 180)];
    [self.view addSubview:self.glView];
        
    [self loadHDRVideoAsset];
    
    [self initDisplayLink];
}

- (void)playClick {
    [self.player play];
    [self startDisplayLink];
}

- (void)loadHDRVideoAsset {
    NSURL *hdrurl = [[NSBundle mainBundle] URLForResource:@"HDRMovie" withExtension:@"mov"];
    AVAsset *hdrAsset = [AVAsset assetWithURL:hdrurl];
    AVPlayerItem *hdritem = [AVPlayerItem playerItemWithAsset:hdrAsset];
    self.playerItemOutput = [[AVPlayerItemVideoOutput alloc] init];
    [hdritem addOutput:self.playerItemOutput];
    self.player = [AVPlayer playerWithPlayerItem:hdritem];
}

- (void)initDisplayLink
{
    _runloop = [NSRunLoop currentRunLoop];
    _port = [NSPort port];
    // 先暂停，开启条件由接入的视频流的个数决定
    _displayLink.preferredFramesPerSecond = 30;
    [_displayLink addToRunLoop:_runloop forMode:NSDefaultRunLoopMode];
    [_runloop addPort:_port forMode:NSDefaultRunLoopMode];
}

- (void)deinitDisplayLink
{
    NSRunLoop * runloop = [NSRunLoop currentRunLoop];
    if (_displayLink)
    {
        _displayLink.paused = YES;
        [_displayLink removeFromRunLoop:runloop forMode:NSDefaultRunLoopMode];
        [_displayLink invalidate];
        _displayLink = nil;
        
    }
    // 停止 RunLoop
    if (_runloop != nil) {
        [_runloop removePort:_port forMode:NSDefaultRunLoopMode];
        CFRunLoopStop([_runloop getCFRunLoop]);
        _port = nil;
        _runloop = nil;
    }
}

- (void)startDisplayLink
{
    if (_displayLink && _displayLink.paused == YES)
    {
        _displayLink.paused = NO;
    }
}

- (void)stopDisplayLink
{
    if (_displayLink && _displayLink.paused == NO)
    {
        _displayLink.paused = YES;
    }
}

- (void)displayLinkCallback:(CADisplayLink *) sender {
    CMTime atTime = [self.playerItemOutput itemTimeForHostTime:CACurrentMediaTime()];

    BOOL hasBuffer = [self.playerItemOutput hasNewPixelBufferForItemTime:atTime];
    if (hasBuffer) {
        CMTime outputTime            = kCMTimeInvalid;
        CVPixelBufferRef pixelBuffer = [self.playerItemOutput copyPixelBufferForItemTime:atTime itemTimeForDisplay:&outputTime];
        if (pixelBuffer) {
            //[self.glView renderWithBuffer:pixelBuffer width:CVPixelBufferGetWidth(pixelBuffer) height:CVPixelBufferGetHeight(pixelBuffer)];
            
            if(CVPixelBufferLockBaseAddress(pixelBuffer, 0) == kCVReturnSuccess)
            {
                //图像宽度（像素）
                int pixelWidth = (int)CVPixelBufferGetWidth(pixelBuffer);
                //图像高度（像素）
                int pixelHeight = (int)CVPixelBufferGetHeight(pixelBuffer);
                //获取CVImageBufferRef中的y数据
                uint16_t *y_frame = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);
                //获取CMVImageBufferRef中的uv数据
                uint16_t *uv_frame = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1);
                
                [self.glView renderWithYBuffer:y_frame UVBuffer:uv_frame width:pixelWidth height:pixelHeight];
            }
            CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
            CFRelease(pixelBuffer);
        }
    }
}

@end
