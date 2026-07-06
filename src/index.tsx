import DepthHealth, {
  type DepthSensor,
  type DepthSensorHealth,
} from './NativeDepthHealth';

export type { DepthSensor, DepthSensorHealth };

export function getSensors(): DepthSensor[] {
  return DepthHealth.getSensors();
}

export function checkSensors(): Promise<DepthSensorHealth[]> {
  return DepthHealth.checkSensors();
}
