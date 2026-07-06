#import "DepthHealth.h"
#if __has_include(<DepthHealth/DepthHealth-Swift.h>)
#import <DepthHealth/DepthHealth-Swift.h>
#else
#import "DepthHealth-Swift.h"
#endif

@implementation DepthHealth {
  NativeDepthHealth *_nativeDepthHealth;
}

- (instancetype)init
{
  self = [super init];
  if (self) {
    _nativeDepthHealth = [NativeDepthHealth new];
  }
  return self;
}

- (NSArray<NSDictionary *> *)getSensors
{
  return [_nativeDepthHealth getSensors];
}

- (void)checkSensors:(JS::NativeDepthHealth::DepthSensorFilter &)filter
             resolve:(RCTPromiseResolveBlock)resolve
              reject:(RCTPromiseRejectBlock)reject
{
  NSMutableDictionary *sensorFilter = [NSMutableDictionary dictionary];

  NSString *type = filter.type();
  if (type != nil) {
    sensorFilter[@"type"] = type;
  }

  NSString *position = filter.position();
  if (position != nil) {
    sensorFilter[@"position"] = position;
  }

  [_nativeDepthHealth checkSensorsWithFilter:sensorFilter resolve:resolve rejecter:reject];
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
