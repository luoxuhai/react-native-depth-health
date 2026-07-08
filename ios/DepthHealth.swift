import AVFoundation
import CoreMedia
import CoreVideo
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

    var results: [[String: Any]] = []
    var currentIndex = 0
    var activeCheck: DepthHealthSensorCheck?

    func runNextCheck() {
      guard currentIndex < candidates.count else {
        resolve(results)
        return
      }

      let candidate = candidates[currentIndex]
      currentIndex += 1

      activeCheck = DepthHealthSensorCheck(
        deviceType: candidate.deviceType,
        position: candidate.position
      ) { completedCheck, result in
        results.append(result)
        if activeCheck === completedCheck {
          activeCheck = nil
        }
        runNextCheck()
      }

      activeCheck?.start()
    }

    runNextCheck()
  }

  private static func availableCandidates(filter: NSDictionary? = nil) -> [DepthHealthSensorCandidate] {
    return candidateSensors().filter { candidate in
      if let type = filter?["type"] as? String, sensorType(for: candidate.deviceType) != type {
        return false
      }

      if let position = filter?["position"] as? String, sensorPosition(for: candidate.position) != position {
        return false
      }

      guard let device = AVCaptureDevice.default(candidate.deviceType, for: .video, position: candidate.position) else {
        return false
      }

      return device.formats.contains { format in
        format.supportedDepthDataFormats.contains { depthFormat in
          CMFormatDescriptionGetMediaSubType(depthFormat.formatDescription) == kCVPixelFormatType_DepthFloat32
        }
      }
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
  private static let maximumFrameAttempts = 5

  private let deviceType: AVCaptureDevice.DeviceType
  private let position: AVCaptureDevice.Position
  private let completion: (DepthHealthSensorCheck, [String: Any]) -> Void
  private let queue = DispatchQueue(label: "com.depthhealth.sensor-check")

  private var session: AVCaptureSession?
  private var depthOutput: AVCaptureDepthDataOutput?
  private var synchronizer: AVCaptureDataOutputSynchronizer?
  private var timeoutWorkItem: DispatchWorkItem?
  private var frameAttempts = 0
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

    guard configureDepthFormat(for: device) else {
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
    depthOutput.alwaysDiscardsLateDepthData = true

    session.beginConfiguration()
    session.sessionPreset = .inputPriority

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
    depthOutput.connection(with: .depthData)?.isEnabled = true
    session.commitConfiguration()

    self.session = session
    self.depthOutput = depthOutput

    let synchronizer = AVCaptureDataOutputSynchronizer(dataOutputs: [depthOutput])
    synchronizer.setDelegate(self, queue: queue)
    self.synchronizer = synchronizer

    session.startRunning()

    let timeoutWorkItem = DispatchWorkItem { [weak self] in
      self?.finish(healthy: false)
    }
    self.timeoutWorkItem = timeoutWorkItem
    queue.asyncAfter(deadline: .now() + 5, execute: timeoutWorkItem)
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
      recordUnhealthyFrameAttempt()
      return
    }

    guard synchronizedDepthData.depthDataWasDropped == false else {
      recordUnhealthyFrameAttempt()
      return
    }

    if Self.containsValidDepthData(in: synchronizedDepthData.depthData.depthDataMap) {
      finish(healthy: true)
    } else {
      recordUnhealthyFrameAttempt()
    }
  }

  private func configureDepthFormat(for device: AVCaptureDevice) -> Bool {
    guard
      let videoFormat = Self.preferredVideoFormat(for: device),
      let depthFormat = Self.preferredDepthDataFormat(from: videoFormat.supportedDepthDataFormats)
    else {
      return false
    }

    do {
      try device.lockForConfiguration()
      device.activeFormat = videoFormat
      device.activeDepthDataFormat = depthFormat
      device.unlockForConfiguration()
      return true
    } catch {
      return false
    }
  }

  private static func preferredVideoFormat(for device: AVCaptureDevice) -> AVCaptureDevice.Format? {
    let depthVideoFormats = device.formats.filter { format in
      format.supportedDepthDataFormats.contains { depthFormat in
        CMFormatDescriptionGetMediaSubType(depthFormat.formatDescription) == kCVPixelFormatType_DepthFloat32
      }
    }

    if device.activeFormat.supportedDepthDataFormats.contains(where: { depthFormat in
      CMFormatDescriptionGetMediaSubType(depthFormat.formatDescription) == kCVPixelFormatType_DepthFloat32
    }) {
      return device.activeFormat
    }

    return depthVideoFormats.min { firstFormat, secondFormat in
      let firstDimensions = CMVideoFormatDescriptionGetDimensions(firstFormat.formatDescription)
      let secondDimensions = CMVideoFormatDescriptionGetDimensions(secondFormat.formatDescription)
      let firstArea = Int(firstDimensions.width) * Int(firstDimensions.height)
      let secondArea = Int(secondDimensions.width) * Int(secondDimensions.height)

      if firstArea != secondArea {
        return firstArea < secondArea
      }

      return firstFormat.supportedDepthDataFormats.count > secondFormat.supportedDepthDataFormats.count
    }
  }

  private static func preferredDepthDataFormat(
    from depthDataFormats: [AVCaptureDevice.Format]
  ) -> AVCaptureDevice.Format? {
    return depthDataFormats.last { depthFormat in
      CMFormatDescriptionGetMediaSubType(depthFormat.formatDescription) == kCVPixelFormatType_DepthFloat32
    }
  }

  private static func containsValidDepthData(in depthMap: CVPixelBuffer) -> Bool {
    let width = CVPixelBufferGetWidth(depthMap)
    let height = CVPixelBufferGetHeight(depthMap)

    guard width > 0, height > 0 else {
      return false
    }

    guard CVPixelBufferLockBaseAddress(depthMap, .readOnly) == kCVReturnSuccess else {
      return false
    }
    defer {
      CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
    }

    guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
      return false
    }

    let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)

    for y in 0..<height {
      let row = baseAddress.advanced(by: y * bytesPerRow).assumingMemoryBound(to: Float32.self)
      for x in 0..<width {
        let value = row[x]
        if value.isFinite && value > 0 {
          return true
        }
      }
    }

    return false
  }

  private func recordUnhealthyFrameAttempt() {
    frameAttempts += 1
    if frameAttempts >= Self.maximumFrameAttempts {
      finish(healthy: false)
    }
  }

  private func finish(healthy: Bool) {
    guard completed == false else {
      return
    }

    completed = true
    timeoutWorkItem?.cancel()
    session?.stopRunning()
    synchronizer?.setDelegate(nil, queue: nil)
    session = nil
    depthOutput = nil
    synchronizer = nil
    timeoutWorkItem = nil

    var result = NativeDepthHealth.sensorDictionary(deviceType: deviceType, position: position)
    result["healthy"] = healthy
    completion(self, result)
  }
}
