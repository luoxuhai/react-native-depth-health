import { useEffect, useState } from 'react';
import { Text, View, StyleSheet } from 'react-native';
import {
  checkSensors,
  getSensors,
  type DepthSensor,
  type DepthSensorHealth,
} from 'react-native-depth-health';

export default function App() {
  const [sensors] = useState<DepthSensor[]>(() => getSensors());
  const [health, setHealth] = useState<DepthSensorHealth[]>([]);

  useEffect(() => {
    checkSensors({
      position: 'back',
      type: 'time-of-flight',
    })
      .then(setHealth)
      .catch(console.error);
  }, []);

  return (
    <View style={styles.container}>
      <Text>Depth sensors: {JSON.stringify(sensors, null, 2)}</Text>
      <Text>Depth health: {JSON.stringify(health, null, 2)}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    padding: 24,
    backgroundColor: '#fff',
  },
});
