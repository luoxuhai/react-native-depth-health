# react-native-depth-health

Detect available iOS depth sensors and check whether their synchronized depth
stream is healthy.

> iOS only: the native implementation currently targets TrueDepth and LiDAR
> cameras through AVFoundation.

## Installation

```sh
npm install react-native-depth-health
```

For iOS, install pods after adding the package:

```sh
cd ios && pod install
```

## API

### `getSensors()`

Returns the available iOS depth sensors synchronously.

```ts
type DepthSensor = {
  type: 'structured-light' | 'time-of-flight';
  position: 'front' | 'back';
};

function getSensors(): DepthSensor[];
```

The iOS implementation maps:

- front `AVCaptureDevice.DeviceType.builtInTrueDepthCamera` to
  `{ type: 'structured-light', position: 'front' }`
- back `AVCaptureDevice.DeviceType.builtInLiDARDepthCamera` to
  `{ type: 'time-of-flight', position: 'back' }`

### `checkSensors()`

Checks each available iOS depth sensor and resolves with a health result.

```ts
type DepthSensorFilter = {
  type?: 'structured-light' | 'time-of-flight';
  position?: 'front' | 'back';
};

type DepthSensorHealth = {
  type: 'structured-light' | 'time-of-flight';
  position: 'front' | 'back';
  healthy: boolean;
};

function checkSensors(filter?: DepthSensorFilter): Promise<DepthSensorHealth[]>;
```

## Usage

```ts
import { checkSensors, getSensors } from 'react-native-depth-health';

const sensors = getSensors();
// [{ type: 'structured-light', position: 'front' }, ...]

const health = await checkSensors();
// [{ type: 'structured-light', position: 'front', healthy: true }, ...]

const frontHealth = await checkSensors({ position: 'front' });
const lidarHealth = await checkSensors({ type: 'time-of-flight' });
```

## iOS permissions

Because `checkSensors()` opens camera capture devices, your app should include an
`NSCameraUsageDescription` entry in its iOS `Info.plist`.

## Contributing

- [Development workflow](CONTRIBUTING.md#development-workflow)
- [Sending a pull request](CONTRIBUTING.md#sending-a-pull-request)
- [Code of conduct](CODE_OF_CONDUCT.md)

## License

MIT

---

Made with [create-react-native-library](https://github.com/callstack/react-native-builder-bob)
