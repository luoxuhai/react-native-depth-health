#import "DepthHealth.h"

#import <AVFoundation/AVFoundation.h>

static NSString *DepthHealthSensorTypeForDeviceType(AVCaptureDeviceType deviceType)
{
  if ([deviceType isEqualToString:AVCaptureDeviceTypeBuiltInTrueDepthCamera]) {
    return @"structured-light";
  }

  return @"time-of-flight";
}

static NSString *DepthHealthSensorPositionForDevicePosition(AVCaptureDevicePosition position)
{
  return position == AVCaptureDevicePositionFront ? @"front" : @"back";
}

static NSDictionary *DepthHealthSensorDictionary(AVCaptureDeviceType deviceType, AVCaptureDevicePosition position)
{
  return @{
    @"type": DepthHealthSensorTypeForDeviceType(deviceType),
    @"position": DepthHealthSensorPositionForDevicePosition(position),
  };
}

@interface DepthHealthSensorCheck : NSObject <AVCaptureDataOutputSynchronizerDelegate>

- (instancetype)initWithDeviceType:(AVCaptureDeviceType)deviceType
                          position:(AVCaptureDevicePosition)position
                         completion:(void (^)(NSDictionary *result))completion;
- (void)start;

@end

@implementation DepthHealthSensorCheck {
  AVCaptureDeviceType _deviceType;
  AVCaptureDevicePosition _position;
  void (^_completion)(NSDictionary *result);
  AVCaptureSession *_session;
  AVCaptureDepthDataOutput *_depthOutput;
  AVCaptureDataOutputSynchronizer *_synchronizer;
  dispatch_queue_t _queue;
  BOOL _completed;
}

- (instancetype)initWithDeviceType:(AVCaptureDeviceType)deviceType
                          position:(AVCaptureDevicePosition)position
                         completion:(void (^)(NSDictionary *result))completion
{
  if ((self = [super init])) {
    _deviceType = deviceType;
    _position = position;
    _completion = [completion copy];
    _queue = dispatch_queue_create("com.depthhealth.sensor-check", DISPATCH_QUEUE_SERIAL);
  }

  return self;
}

- (void)start
{
  dispatch_async(_queue, ^{
    NSError *error = nil;
    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithDeviceType:self->_deviceType
                                                                  mediaType:AVMediaTypeVideo
                                                                   position:self->_position];
    if (device == nil) {
      [self finishWithHealthy:NO];
      return;
    }

    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
    if (input == nil || error != nil) {
      [self finishWithHealthy:NO];
      return;
    }

    self->_session = [AVCaptureSession new];
    self->_depthOutput = [AVCaptureDepthDataOutput new];
    self->_depthOutput.filteringEnabled = NO;

    [self->_session beginConfiguration];
    if ([self->_session canAddInput:input]) {
      [self->_session addInput:input];
    } else {
      [self->_session commitConfiguration];
      [self finishWithHealthy:NO];
      return;
    }

    if ([self->_session canAddOutput:self->_depthOutput]) {
      [self->_session addOutput:self->_depthOutput];
    } else {
      [self->_session commitConfiguration];
      [self finishWithHealthy:NO];
      return;
    }
    [self->_session commitConfiguration];

    self->_synchronizer = [[AVCaptureDataOutputSynchronizer alloc] initWithDataOutputs:@[ self->_depthOutput ]];
    [self->_synchronizer setDelegate:self queue:self->_queue];
    [self->_session startRunning];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), self->_queue, ^{
      [self finishWithHealthy:NO];
    });
  });
}

- (void)dataOutputSynchronizer:(AVCaptureDataOutputSynchronizer *)synchronizer
 didOutputSynchronizedDataCollection:(AVCaptureSynchronizedDataCollection *)synchronizedDataCollection
{
  AVCaptureSynchronizedDepthData *synchronizedDepthData = (AVCaptureSynchronizedDepthData *)[synchronizedDataCollection synchronizedDataForCaptureOutput:_depthOutput];
  if (synchronizedDepthData == nil) {
    return;
  }

  BOOL droppedForDiscontinuity = synchronizedDepthData.depthDataWasDropped &&
    synchronizedDepthData.droppedReason == AVCaptureOutputDataDroppedReasonDiscontinuity;
  [self finishWithHealthy:!droppedForDiscontinuity];
}

- (void)finishWithHealthy:(BOOL)healthy
{
  if (_completed) {
    return;
  }

  _completed = YES;
  [_session stopRunning];
  [_synchronizer setDelegate:nil queue:nil];

  NSMutableDictionary *result = [DepthHealthSensorDictionary(_deviceType, _position) mutableCopy];
  result[@"healthy"] = @(healthy);

  if (_completion != nil) {
    _completion(result);
  }
}

@end

@implementation DepthHealth
- (NSArray<NSDictionary *> *)getSensors
{
  NSMutableArray<NSDictionary *> *sensors = [NSMutableArray new];
  NSArray<NSDictionary *> *candidates = @[
    DepthHealthSensorDictionary(AVCaptureDeviceTypeBuiltInTrueDepthCamera, AVCaptureDevicePositionFront),
    DepthHealthSensorDictionary(AVCaptureDeviceTypeBuiltInLiDARDepthCamera, AVCaptureDevicePositionBack),
  ];

  for (NSDictionary *candidate in candidates) {
    AVCaptureDeviceType deviceType = [candidate[@"type"] isEqualToString:@"structured-light"]
      ? AVCaptureDeviceTypeBuiltInTrueDepthCamera
      : AVCaptureDeviceTypeBuiltInLiDARDepthCamera;
    AVCaptureDevicePosition position = [candidate[@"position"] isEqualToString:@"front"]
      ? AVCaptureDevicePositionFront
      : AVCaptureDevicePositionBack;

    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithDeviceType:deviceType
                                                                  mediaType:AVMediaTypeVideo
                                                                   position:position];
    if (device != nil) {
      [sensors addObject:candidate];
    }
  }

  return sensors;
}

- (void)checkSensors:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject
{
  NSArray<NSDictionary *> *sensors = [self getSensors];
  if (sensors.count == 0) {
    resolve(@[]);
    return;
  }

  NSMutableArray<NSDictionary *> *results = [NSMutableArray new];
  NSMutableArray<DepthHealthSensorCheck *> *checks = [NSMutableArray new];
  __block NSUInteger remaining = sensors.count;

  for (NSDictionary *sensor in sensors) {
    AVCaptureDeviceType deviceType = [sensor[@"type"] isEqualToString:@"structured-light"]
      ? AVCaptureDeviceTypeBuiltInTrueDepthCamera
      : AVCaptureDeviceTypeBuiltInLiDARDepthCamera;
    AVCaptureDevicePosition position = [sensor[@"position"] isEqualToString:@"front"]
      ? AVCaptureDevicePositionFront
      : AVCaptureDevicePositionBack;

    __block DepthHealthSensorCheck *check = nil;
    check = [[DepthHealthSensorCheck alloc] initWithDeviceType:deviceType
                                                      position:position
                                                     completion:^(NSDictionary *result) {
      @synchronized (results) {
        [results addObject:result];
        [checks removeObject:check];
        check = nil;
        remaining -= 1;
        if (remaining == 0) {
          resolve([results copy]);
        }
      }
    }];
    [checks addObject:check];
    [check start];
  }
}

- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
    return std::make_shared<facebook::react::NativeDepthHealthSpecJSI>(params);
}

+ (NSString *)moduleName
{
  return @"DepthHealth";
}

@end
