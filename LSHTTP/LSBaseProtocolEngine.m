//
//  LSBaseProtocolEngine.m
//  Test1
//
//  Created by zhiwei ma on 12-3-15.
//  Copyright (c) 2012年 __MyCompanyName__. All rights reserved.
//

#import "LSBaseProtocolEngine.h"
#import "ASIDownloadCache.h"

#define LSPROTOCOLENGINE_DEBUG

//由于调用流程的原因，本地代码在[self parseResponseData:rspString]中使用假数据进行测试，需要开启LSLOCALTEST宏
//#define LSLOCALTEST

NSError* serverDataError()
{
    return [NSError errorWithDomain:LSErrorDomain 
                               code:LSErrorCode_ServerData 
                           userInfo:[NSDictionary dictionaryWithObject:LSErrorString_ServerData forKey:NSLocalizedDescriptionKey]];
}


@implementation LSBaseProtocolEngine
@synthesize delegate = _delegate;
@synthesize curRequest = _curRequest;
@synthesize op = _op;
@synthesize errorParser = _errorParser;
@synthesize forceRefresh =_forceRefresh;
@synthesize keepLastRequest = _keepLastRequest;

static id<LSProtocolErrorParser> sErrorParser = nil;
+ (void)setDefaultErrorParser:(id<LSProtocolErrorParser>)aErrorParser
{
    @synchronized(self)
    {
        sErrorParser = aErrorParser;
    }
}

- (void)dealloc
{
    self.curRequest = nil;
    self.errorParser = nil;
    [super dealloc];
}

- (void)sendRequest
{
    [self cancelRequest];
    
    self.curRequest = [self request];
    if (nil == _curRequest)
    {
        _state = LSProtocolEngineState_Pending;
        return;
    }
    
    if (_forceRefresh)//强制刷新
    {
        [_curRequest clearCache];
        _forceRefresh = NO;
    }
    
    _curRequest.delegate = self;
    [[LSHTTPKit sharedInstance] addRequest:_curRequest];
    NSLog(@"request url= %@",[_curRequest.url absoluteString]);
    _state = LSProtocolEngineState_Loading;
    if (LSProtocolEngineOp_Pending == _op)
    {
        _op = LSProtocolEngineOp_Refresh;
    }
}

- (void)cancelRequest
{
    [self.curRequest clearDelegatesAndCancel];
    _state = LSProtocolEngineState_Pending;
}

- (void)reset
{
    [self cancelRequest];
    self.curRequest = nil;
    self.op = LSProtocolEngineOp_Pending;
    _state = LSProtocolEngineState_Pending;
}

- (BOOL)isDone
{
    return (_state == LSProtocolEngineState_Finished || _state == LSProtocolEngineState_Failed) ? YES : NO;
}

- (BOOL)isFinished
{
    return (_state == LSProtocolEngineState_Finished);
}

- (BOOL)isFailed
{
    return (_state == LSProtocolEngineState_Failed);
}

- (BOOL)isLoading
{
    return (_state == LSProtocolEngineState_Loading);
}

- (LSHTTPRequest*)request
{
    //noop
    return nil;
}

- (LSBaseResponseData*)parseResponseData:(NSString*)aResponseString
{
    return [[[LSBaseResponseData alloc] init] autorelease];
}

- (BOOL)handleResponseData:(LSBaseResponseData*)aNewData
{
    return (nil == aNewData) ? NO : YES;
}

#pragma mark ASIHTTPRequestDelegate
- (void)requestFinished:(LSHTTPRequest *)request
{
    NSAssert(_curRequest == request, @"");
    NSString* rspString = request.responseString;
#ifdef LSPROTOCOLENGINE_DEBUG
    NSLog(@"%@ %@",NSStringFromClass([self class]),rspString);
    BOOL useCacheFlag = [request didUseCachedResponse];
    NSLog(@"useCache %d", useCacheFlag);
#endif
    
    //先判断是否是服务器操作失败
    LSBaseResponseData* rspData = nil;
    if (_errorParser)
    {
        rspData = [_errorParser parserError:rspString];
    }
    else 
    {
        rspData = [sErrorParser parserError:rspString];
    }
#ifdef LSLOCALTEST 
    rspData = nil;
#endif
    if (nil == rspData)
    {
        rspData = [self parseResponseData:rspString];
        BOOL ret = [self handleResponseData:rspData];
        if (NO == ret)
        {
            rspData = LSError_ServerData;
        }
    }

    if ([rspData isKindOfClass:[NSError class]])
    {
        //清楚缓存，避免下次请求还从本地获取
        [_curRequest clearCache];
        
        _state = LSProtocolEngineState_Failed;
        if (_delegate && [(NSObject*)_delegate respondsToSelector:@selector(didProtocolEngineFailed:error:)])
        {
            [_delegate didProtocolEngineFailed:self error:(NSError*)rspData];
        }
    }
    else 
    {
        _state = LSProtocolEngineState_Finished;
        if (_delegate && [(NSObject*)_delegate respondsToSelector:@selector(didProtocolEngineFinished:newData:)])
        {
            [_delegate didProtocolEngineFinished:self newData:rspData];
        }
    }
    
    if (NO == self.keepLastRequest)
    {
        self.curRequest = nil;
    }
    
    _op = LSProtocolEngineOp_Pending;
}

- (void)requestFailed:(ASIHTTPRequest *)request
{
    NSAssert(_curRequest == request, @"");
#ifdef LSPROTOCOLENGINE_DEBUG
    NSLog(@"%s %@",__FUNCTION__, request.error);
#endif
    _state = LSProtocolEngineState_Failed;
    if (_delegate && [(NSObject*)_delegate respondsToSelector:@selector(didProtocolEngineFailed:error:)])
    {
        [_delegate didProtocolEngineFailed:self error:request.error];
    }
    
    self.curRequest = nil;
    _op = LSProtocolEngineOp_Pending;
}
@end
