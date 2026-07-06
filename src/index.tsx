import DepthHealth, {
  type DepthSensor,
  type DepthSensorFilter,
  type DepthSensorHealth,
} from './NativeDepthHealth';

export type { DepthSensor, DepthSensorFilter, DepthSensorHealth };

export function getSensors(): DepthSensor[] {
  return DepthHealth.getSensors();
}

export function checkSensors(
  filter: DepthSensorFilter = {}
): Promise<DepthSensorHealth[]> {
  return DepthHealth.checkSensors(filter);
}
