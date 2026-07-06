import AVFoundation
import Foundation
import React

@objcMembers public class NativeDepthHealth: NSObject {
  public func getSensors() -> [[String: Any]] {
    return Self.availableCandidates().map { candidate in
      Self.sensorDictionary(deviceType: candidate.deviceType, position: candidate.position)
    }
  }

  public func checkSensors(
    filter: NSDictionary,
    resolve: @escaping RCTPromiseResolveBlock,
    rejecter reject: @escaping RCTPromiseRejectBlock
  ) {
    let candidates = Self.availableCandidates(filter: filter)
    guard candidates.isEmpty == false else {
      resolve([])
      return
    }

    let lock = NSLock()
    var checks: [DepthHealthSensorCheck] = []
    var results: [[String: Any]] = []
    var remaining = candidates.count

    for candidate in candidates {
      let check = DepthHealthSensorCheck(
        deviceType: candidate.deviceType,
        position: candidate.position
      ) { completedCheck, result in
        lock.lock()
        results.append(result)
        checks.removeAll { $0 === completedCheck }
        remaining -= 1
        let shouldResolve = remaining == 0
        let resolvedResults = results
        lock.unlock()

        if shouldResolve {
          resolve(resolvedResults)
        }
      }

      checks.append(check)
      check.start()
    }
  }

  private static func availableCandidates(filter: NSDictionary? = nil) -> [DepthHealthSensorCandidate] {
    return candidateSensors().filter { candidate in
      if let type = filter?["type"] as? String, sensorType(for: candidate.deviceType) != type {
        return false
      }

      if let position = filter?["position"] as? String, sensorPosition(for: candidate.position) != position {
        return false
      }

      return AVCaptureDevice.default(candidate.deviceType, for: .video, position: candidate.position) != nil
    }
  }

  private static func candidateSensors() -> [DepthHealthSensorCandidate] {
    let candidates = [
      DepthHealthSensorCandidate(deviceType: .builtInTrueDepthCamera, position: .front),
      DepthHealthSensorCandidate(deviceType: .builtInLiDARDepthCamera, position: .back)
    ]

    return candidates
  }

  fileprivate static func sensorDictionary(
    deviceType: AVCaptureDevice.DeviceType,
    position: AVCaptureDevice.Position
  ) -> [String: Any] {
    return [
      "type": sensorType(for: deviceType),
      "position": sensorPosition(for: position),
    ]
  }

  private static func sensorType(for deviceType: AVCaptureDevice.DeviceType) -> String {
    if deviceType == .builtInTrueDepthCamera {
      return "structured-light"
    }

    return "time-of-flight"
  }

  private static func sensorPosition(for position: AVCaptureDevice.Position) -> String {
    return position == .front ? "front" : "back"
  }
}

private struct DepthHealthSensorCandidate {
  let deviceType: AVCaptureDevice.DeviceType
  let position: AVCaptureDevice.Position
}

private final class DepthHealthSensorCheck: NSObject, AVCaptureDataOutputSynchronizerDelegate {
  private let deviceType: AVCaptureDevice.DeviceType
  private let position: AVCaptureDevice.Position
  private let completion: (DepthHealthSensorCheck, [String: Any]) -> Void
  private let queue = DispatchQueue(label: "com.depthhealth.sensor-check")

  private var session: AVCaptureSession?
  private var depthOutput: AVCaptureDepthDataOutput?
  private var synchronizer: AVCaptureDataOutputSynchronizer?
  private var completed = false

  init(
    deviceType: AVCaptureDevice.DeviceType,
    position: AVCaptureDevice.Position,
    completion: @escaping (DepthHealthSensorCheck, [String: Any]) -> Void
  ) {
    self.deviceType = deviceType
    self.position = position
    self.completion = completion
    super.init()
  }

  func start() {
    queue.async { [weak self] in
      self?.startOnQueue()
    }
  }

  private func startOnQueue() {
    guard let device = AVCaptureDevice.default(deviceType, for: .video, position: position) else {
      finish(healthy: false)
      return
    }

    let input: AVCaptureDeviceInput
    do {
      input = try AVCaptureDeviceInput(device: device)
    } catch {
      finish(healthy: false)
      return
    }

    let session = AVCaptureSession()
    let depthOutput = AVCaptureDepthDataOutput()
    depthOutput.isFilteringEnabled = false

    session.beginConfiguration()
    guard session.canAddInput(input) else {
      session.commitConfiguration()
      finish(healthy: false)
      return
    }
    session.addInput(input)

    guard session.canAddOutput(depthOutput) else {
      session.commitConfiguration()
      finish(healthy: false)
      return
    }
    session.addOutput(depthOutput)
    session.commitConfiguration()

    self.session = session
    self.depthOutput = depthOutput

    let synchronizer = AVCaptureDataOutputSynchronizer(dataOutputs: [depthOutput])
    synchronizer.setDelegate(self, queue: queue)
    self.synchronizer = synchronizer

    session.startRunning()

    queue.asyncAfter(deadline: .now() + 5) { [weak self] in
      self?.finish(healthy: false)
    }
  }

  func dataOutputSynchronizer(
    _ synchronizer: AVCaptureDataOutputSynchronizer,
    didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection
  ) {
    guard let depthOutput else {
      return
    }

    guard
      let synchronizedDepthData = synchronizedDataCollection.synchronizedData(for: depthOutput)
        as? AVCaptureSynchronizedDepthData
    else {
      return
    }

    let droppedForDiscontinuity =
      synchronizedDepthData.depthDataWasDropped &&
      synchronizedDepthData.droppedReason == .discontinuity
    finish(healthy: droppedForDiscontinuity == false)
  }

  private func finish(healthy: Bool) {
    guard completed == false else {
      return
    }

    completed = true
    session?.stopRunning()
    synchronizer?.setDelegate(nil, queue: nil)

    var result = NativeDepthHealth.sensorDictionary(deviceType: deviceType, position: position)
    result["healthy"] = healthy
    completion(self, result)
  }
}
