//
//  YVLGLView.m
//  yyvideolibtest
//
//  Created by ashawn on 2021/7/29.
//

#import "YVLGLView.h"
#import <OpenGLES/ES3/gl.h>

#define GLES_SILENCE_DEPRECATION
//方便定义shader字符串的宏
#define STRINGIZE(x) #x
#define STRINGIZE2(x) STRINGIZE(x)
#define SHADER_STRING(text) @ STRINGIZE2(text)

//顶点着色器
NSString *const nv12vertexShaderString = SHADER_STRING
(
 //attribute 关键字用来描述传入shader的变量
 attribute vec4 vertexPosition; //传入的顶点坐标
 attribute vec2 textureCoords;//要获取的纹理坐标
 //传给片段着色器参数
 varying  vec2 textureCoordsOut;
 void main(void) {
     gl_Position = vertexPosition; // gl_Position是vertex shader的内建变量，gl_Position中的顶点值最终输出到渲染管线中
     textureCoordsOut = textureCoords;
 }
 );
//片段着色器
NSString *const nv12fragmentShaderString = SHADER_STRING
(
 varying highp vec2 textureCoordsOut;
 
 uniform highp sampler2D y_texture;
 uniform highp sampler2D uv_texture;
 
 void main(void) {
     
     highp float y = float(texture2D(y_texture, textureCoordsOut).r);
     highp float u = texture2D(uv_texture, textureCoordsOut).r - 0.5 ;
     highp float v = texture2D(uv_texture, textureCoordsOut).a -0.5;

     highp float r = y +             1.402 * v;
     highp float g = y - 0.344 * u - 0.714 * v;
     highp float b = y + 1.772 * u;

     gl_FragColor = vec4(y,y,y,1.0);
 }
 );

@interface YVLGLView ()
{
    GLuint _renderBuffer;
    GLuint _framebuffer;
    
    //纹理缓冲
    CVOpenGLESTextureRef _lumaTexture;
    CVOpenGLESTextureRef _chromaTexture;
    CVOpenGLESTextureCacheRef _textureCache;
    
    GLuint _yTexture;
    GLuint _uvTexture;
    
    //着色器程序
    GLuint _glprogram;
    //记录renderbuffer的宽高
    GLint           _backingWidth;
    GLint           _backingHeight;
    
    
    dispatch_queue_t _renderQueue;
    
    //纹理参数
    GLint _y_texture;
    GLint _uv_texture;
    //顶点参数
    GLint _vertexPosition;
    //纹理坐标参数
    GLint _textureCoords;
}
@property(nonatomic,strong)CAEAGLLayer*eaglLayer;
@property(nonatomic,strong)EAGLContext*context;

@end

@implementation YVLGLView

-(instancetype)initWithCoder:(NSCoder *)aDecoder
{
    if (self = [super initWithCoder:aDecoder]) {
        [self commonInit];
    }
    
    return self;
}
-(instancetype)initWithFrame:(CGRect)frame
{
    if (self = [super initWithFrame:frame]) {
        [self commonInit];
    }
    return self;
}
+(Class)layerClass
{
    return [CAEAGLLayer class];
}

-(void)commonInit{
    
    _renderQueue = dispatch_queue_create("renderQueue", DISPATCH_QUEUE_SERIAL);
    
    
    [self prepareLayer];
    dispatch_sync(_renderQueue, ^{
        [self prepareContext];
        [self prepareShader];
        [self prepareRenderBuffer];
        [self prepareFrameBuffer];
    });
    
    
}

- (void)dealloc
{
    if (_framebuffer) {
        glDeleteFramebuffers(1, &_framebuffer);
        _framebuffer = 0;
    }
    
    if (_renderBuffer) {
        glDeleteRenderbuffers(1, &_renderBuffer);
        _renderBuffer = 0;
    }
    
    if (_glprogram) {
        glDeleteProgram(_glprogram);
        _glprogram = 0;
    }
    
    if ([EAGLContext currentContext] == _context) {
        [EAGLContext setCurrentContext:nil];
    }
    
    _context = nil;
}
#pragma mark - private methods
-(void)prepareLayer
{
    self.eaglLayer = (CAEAGLLayer*)self.layer;
    self.eaglLayer.opaque = YES;
    self.eaglLayer.drawableProperties = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:NO], kEAGLDrawablePropertyRetainedBacking, kEAGLColorFormatRGBA8, kEAGLDrawablePropertyColorFormat, nil];
}

-(void)prepareContext
{
    self.context = [[EAGLContext alloc]initWithAPI:kEAGLRenderingAPIOpenGLES3];
    [EAGLContext setCurrentContext:self.context];
    CVReturn result = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, NULL, self.context, NULL, &_textureCache);
    if (result != kCVReturnSuccess) {
        NSLog(@"CVOpenGLESTextureCacheCreate fail %d",result);
    }
}

-(void)prepareRenderBuffer{
    glGenRenderbuffers(1, &_renderBuffer);
    glBindRenderbuffer(GL_RENDERBUFFER, _renderBuffer);
    //调用这个方法来创建一块空间用于存储缓冲数据，替代了glRenderbufferStorage
    [self.context renderbufferStorage:GL_RENDERBUFFER fromDrawable:self.eaglLayer];
    
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &_backingWidth);
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &_backingHeight);
}

-(void)prepareFrameBuffer
{
    glGenFramebuffers(1, &_framebuffer);
    glBindFramebuffer(GL_FRAMEBUFFER, _framebuffer);
    
    //设置gl渲染窗口大小
    glViewport(0, 0, _backingWidth, _backingHeight);
    //附加之前的_renderBuffer
    //GL_COLOR_ATTACHMENT0指定第一个颜色缓冲区附着点
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                              GL_RENDERBUFFER, _renderBuffer);
    
    glGenTextures(1, &_yTexture);
   
    glGenTextures(1, &_uvTexture);
}

-(void)prepareShader
{
    //创建顶点着色器
    GLuint vertexShader = glCreateShader(GL_VERTEX_SHADER);
    
    const GLchar* const vertexShaderSource =  (GLchar*)[nv12vertexShaderString UTF8String];
    GLint vertexShaderLength = (GLint)[nv12vertexShaderString length];
    //读取shader字符串
    glShaderSource(vertexShader, 1, &vertexShaderSource, &vertexShaderLength);
    //编译shader
    glCompileShader(vertexShader);
    
    GLint logLength;
    glGetShaderiv(vertexShader, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0)
    {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetShaderInfoLog(vertexShader, logLength, &logLength, log);
        NSLog(@"%s\n",log);
        free(log);
    }
    
    //创建片元着色器
    GLuint fragmentShader = glCreateShader(GL_FRAGMENT_SHADER);
    const GLchar* const fragmentShaderSource = (GLchar*)[nv12fragmentShaderString UTF8String];
    GLint fragmentShaderLength = (GLint)[nv12fragmentShaderString length];
    glShaderSource(fragmentShader, 1, &fragmentShaderSource, &fragmentShaderLength);
    glCompileShader(fragmentShader);
    
    glGetShaderiv(fragmentShader, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0)
    {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetShaderInfoLog(fragmentShader, logLength, &logLength, log);
        NSLog(@"%s\n",log);
        free(log);
    }
    
    //创建glprogram
    _glprogram = glCreateProgram();
    
    //绑定shader
    glAttachShader(_glprogram, vertexShader);
    glAttachShader(_glprogram, fragmentShader);
    //链接program
    glLinkProgram(_glprogram);
    
    //选择程序对象为当前使用的程序，类似setCurrentContext
    glUseProgram(_glprogram);
    
    //获取并保存参数位置
    _y_texture = glGetUniformLocation(_glprogram, "y_texture");
    _uv_texture = glGetUniformLocation(_glprogram, "uv_texture");
    _vertexPosition = glGetAttribLocation(_glprogram, "vertexPosition");
    _textureCoords = glGetAttribLocation(_glprogram, "textureCoords");
    
    
    //使参数可见
    glEnableVertexAttribArray(_vertexPosition);
    glEnableVertexAttribArray(_textureCoords);
}

- (void)mappingTexture:(GLenum)textureUnit imageBuffer:(CVPixelBufferRef)imageBuffer textureFormat:(GLint)textureFormat width:(GLsizei)width height:(GLsizei)height planeIndex:(size_t)planeIndex {
    CVReturn err = kCVReturnSuccess;

    CVOpenGLESTextureRef textureRef = NULL;
    glActiveTexture(textureUnit);
    err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                       _textureCache,
                                                       imageBuffer,
                                                       NULL,
                                                       GL_TEXTURE_2D,
                                                       textureFormat,
                                                       width,
                                                       height,
                                                       textureFormat,
                                                       GL_UNSIGNED_BYTE,
                                                       planeIndex,
                                                       &textureRef);

    if (err) {
        NSLog(@"error at CVOpenGLESTextureCacheCreateTextureFromImage %d", err);
    } else {
        if (planeIndex == 0) {
            _lumaTexture = textureRef;
        } else {
            _chromaTexture = textureRef;
        }

        glBindTexture(CVOpenGLESTextureGetTarget(textureRef), CVOpenGLESTextureGetName(textureRef));
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    }
}

- (void)convertBufferToUIImage:(void*)rawImagePixels width:(int)width height:(int)height

{

    CGContextRef context = CGBitmapContextCreate(rawImagePixels,
                                                 width,
                                                 height,
                                                 16,
                                                 7680,
                                                 CGColorSpaceCreateDeviceGray(),
                                                 kCGImageByteOrderDefault);
    CGImageRef retImage = CGBitmapContextCreateImage(context);
    UIImage* image = [UIImage imageWithCGImage: retImage];

    NSLog(@"");
}

-(void)renderWithBuffer:(CVPixelBufferRef)pixelBuffer width:(int)width height:(int)height
{
    dispatch_sync(_renderQueue, ^{
        //检查context
        if ([EAGLContext currentContext] != self.context)
        {
            [EAGLContext setCurrentContext:self.context];
        }
        
        [self mappingTexture:GL_TEXTURE0 imageBuffer:pixelBuffer textureFormat:GL_LUMINANCE width:width height:height planeIndex:0];
        glUniform1i(_y_texture,0);
        [self mappingTexture:GL_TEXTURE1 imageBuffer:pixelBuffer textureFormat:GL_LUMINANCE_ALPHA width:width >> 1 height:height >> 1 planeIndex:1];
        glUniform1i(_uv_texture,1);
        
        GLfloat vertices[] = {
            -1,1,
            1,1,
            -1,-1,
            1,-1,
            
        };
        GLfloat textCoord[] = {
            0,0,
            1,0,
            0,1,
            1,1,
        };
        
        
        glVertexAttribPointer(_vertexPosition, 2, GL_FLOAT, GL_FALSE, 0, vertices);
        glVertexAttribPointer(_textureCoords, 2, GL_FLOAT, GL_FALSE,0, textCoord);
        
        //清屏为白色
        glClearColor(1.0, 0.0, 0.0, 1.0);
        glClear(GL_COLOR_BUFFER_BIT);
        
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
        //EACAGLContext 渲染OpenGL绘制好的图像到EACAGLLayer
        [_context presentRenderbuffer:GL_RENDERBUFFER];
        
        [self cleanUpTextures];
    });
}

-(void)renderWithYUVBuffer:(CVPixelBufferRef)pixelBuffer width:(int)width height:(int)height
{
    dispatch_sync(_renderQueue, ^{
        //检查context
        if ([EAGLContext currentContext] != self.context)
        {
            [EAGLContext setCurrentContext:self.context];
        }
        
        [self mappingTexture:GL_TEXTURE0 imageBuffer:pixelBuffer textureFormat:GL_LUMINANCE width:width height:height planeIndex:0];
        glUniform1i(_y_texture,0);
        [self mappingTexture:GL_TEXTURE1 imageBuffer:pixelBuffer textureFormat:GL_LUMINANCE_ALPHA width:width >> 1 height:height >> 1 planeIndex:1];
        glUniform1i(_uv_texture,1);
        
        GLfloat vertices[] = {
            -1,1,
            1,1,
            -1,-1,
            1,-1,
            
        };
        GLfloat textCoord[] = {
            0,0,
            1,0,
            0,1,
            1,1,
        };
        
        
        glVertexAttribPointer(_vertexPosition, 2, GL_FLOAT, GL_FALSE, 0, vertices);
        glVertexAttribPointer(_textureCoords, 2, GL_FLOAT, GL_FALSE,0, textCoord);
        
        //清屏为白色
        glClearColor(1.0, 0.0, 0.0, 1.0);
        glClear(GL_COLOR_BUFFER_BIT);
        
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
        //EACAGLContext 渲染OpenGL绘制好的图像到EACAGLLayer
        [_context presentRenderbuffer:GL_RENDERBUFFER];
        
        [self cleanUpTextures];
    });
}

-(void)renderWithYBuffer:(uint16_t*)YData UVBuffer:(uint16_t*)UVData width:(int)width height:(int)height
{
    dispatch_sync(_renderQueue, ^{
        //检查context
        if ([EAGLContext currentContext] != self.context)
        {
            [EAGLContext setCurrentContext:self.context];
        }
        
        GLfloat vertices[] = {
            -1,1,
            1,1,
            -1,-1,
            1,-1,
            
        };
        GLfloat textCoord[] = {
            0,1,
            1,1,
            0,0,
            1,0,
        };
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, _yTexture);
        //确定采样器对应的哪个纹理，由于只使用一个，所以这句话可以不写
        glUniform1i(_y_texture,0);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_R16F, width, height, 0, GL_RED, GL_UNSIGNED_SHORT, YData);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        
        
        glActiveTexture(GL_TEXTURE1);

        glBindTexture(GL_TEXTURE_2D, _uvTexture);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_LUMINANCE_ALPHA, width/2, height/2, 0, GL_LUMINANCE_ALPHA, GL_UNSIGNED_SHORT, UVData);
        glUniform1i(_uv_texture,1);
        
        
        //设置一些边缘的处理
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        
        
        
        
        glVertexAttribPointer(_vertexPosition, 2, GL_FLOAT, GL_FALSE, 0, vertices);
        glVertexAttribPointer(_textureCoords, 2, GL_FLOAT, GL_FALSE,0, textCoord);
        
        //清屏为白色
        glClearColor(1.0, 1.0, 1.0, 1.0);
        glClear(GL_COLOR_BUFFER_BIT);
        
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
        //EACAGLContext 渲染OpenGL绘制好的图像到EACAGLLayer
        [_context presentRenderbuffer:GL_RENDERBUFFER];
    });
}

- (void)cleanUpTextures {
    if (_lumaTexture) {
        CFRelease(_lumaTexture);
        _lumaTexture = NULL;
    }

    if (_chromaTexture) {
        CFRelease(_chromaTexture);
        _chromaTexture = NULL;
    }
}

@end
