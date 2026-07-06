import { TurboModuleRegistry, type TurboModule } from 'react-native';

export type DepthSensorType = 'structured-light' | 'time-of-flight';
export type DepthSensorPosition = 'front' | 'back';

export type DepthSensor = {
  type: DepthSensorType;
  position: DepthSensorPosition;
};

export type DepthSensorHealth = DepthSensor & {
  healthy: boolean;
};

export type DepthSensorFilter = {
  type?: DepthSensorType;
  position?: DepthSensorPosition;
};

export interface Spec extends TurboModule {
  getSensors(): DepthSensor[];
  checkSensors(filter: DepthSensorFilter): Promise<DepthSensorHealth[]>;
}

export default TurboModuleRegistry.getEnforcing<Spec>('DepthHealth');
