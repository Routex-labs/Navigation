import CoreMotion
import Flutter
import Foundation

/// CoreMotion/CMPedometer 센서 융합 데이터를 Dart로 스트리밍한다.
///
/// 연구 앱 `PdrMotionBridge.swift`의 최소 이식판이다. 제품 코어가 쓰는
/// CoreMotion DeviceMotion(heading/attitude/walkDir/step-peak/gyro)과 CMPedometer만
/// 남기고, 연구 전용이던 GPS(CLLocationManager)와 IMU v3 100Hz export 버퍼,
/// JSON export는 제거했다.
///
/// 이벤트는 `kind`로 태그된다:
///   - "motion": DeviceMotion attitude/pose (~33 Hz로 throttle)
///   - "pedometer": CMPedometer step 필드(iOS가 1~2.5s로 배치)
///   - "snapshot": 초기 listen/reset 시 둘 다
///   - "altitude": CMAltimeter 기압/상대고도(~1 Hz). 층 전이 판정 전용이며
///     heading·pedometer 필드를 함께 싣지 않는다(아래 emitAltitude 주석 참고)
///
/// Dart 경로 계산: 거리는 CMPedometer step/distance, 방향은 DeviceMotion attitude에서
/// 유도한 fusedHeadingDeg + walkDirDeg. accelMagnitude/gyroZ/magneticField 스칼라와
/// stepPeakTimes/motionTimestamp는 타이밍/진단 신호다.
final class PdrMotionStreamHandler: NSObject, FlutterStreamHandler {
  private let motionManager = CMMotionManager()
  private let pedometer = CMPedometer()
  private let altimeter = CMAltimeter()
  private let motionQueue = OperationQueue()
  private let altimeterQueue = OperationQueue()

  private var sink: FlutterEventSink?

  // 아래 필드는 전부 main queue에서만 변경된다.
  private var stepSessionId = 0
  private var latestSteps = 0
  private var latestStepDelta = 0
  private var latestDistanceM = 0.0
  private var latestDistanceAvailable = false
  private var latestPedometerTimestampMs = 0.0
  private var latestPedometerGapMs = 0.0
  private var latestCadence = 0.0
  private var latestPace = 0.0
  private var latestCadenceAvailable = false
  private var latestPaceAvailable = false
  private var pedometerSessionStartMs = 0.0
  private var lastPedometerCallbackAt: Date?
  private var pedometerFinalized = false

  private var hasMotionSample = false
  private var latestFusedHeadingDeg = 0.0
  private var latestDeviceHeadingDeg = -1.0
  private var headingStable = false
  private var headingSource = "unavailable"
  private var latestYawDeg = 0.0
  private var latestPitchDeg = 0.0
  private var latestRollDeg = 0.0
  private var latestMotionTimestampMs = 0.0
  private var latestMotionHz = 0.0
  private var lastMotionBootTimestamp: TimeInterval?
  private var lastMotionEmitMs = 0.0
  private let motionEmitIntervalMs = 30.0

  private var latestMagneticField = 0.0
  private var latestMagneticAccuracy = "unknown"
  private var latestAccelMagnitude = 0.0
  private var latestGyroZ = 0.0

  // 보행 방향 추정(accel-PCA). 시간 기반 ~1.3s window의 수평 world-frame user accel.
  private var accelTimes: [TimeInterval] = []
  private var accelEast: [Double] = []
  private var accelNorth: [Double] = []
  private let accelWindowSeconds: TimeInterval = 1.3
  private var latestWalkDirDeg = 0.0
  private var latestWalkDirConfidence = 0.0

  // 실시간 step-peak 시각(unix ms). accel로 걸음을 "세지" 않고(그건 CMPedometer),
  // 늦게 온 배치의 step을 실제 발생 시각에 배치하도록 시각만 기록한다.
  private var stepPeakTimesMs: [Double] = []
  private var stepPeakCount = 0
  private var latestStepPeakMs = 0.0
  private var peakArmed = true
  private var lastPeakMs = 0.0
  private let peakRefractoryMs = 380.0
  private var accelEnvMax = 0.0
  private var accelEnvMin = 0.0
  private var envInitialized = false
  private let envReleaseAlpha = 0.007
  private let peakHighRatio = 0.55
  private let peakLowRatio = 0.30
  private let minPeakSwingG = 0.03
  private let minPeakHighG = 0.06

  // gyro-only heading: 중력축 기준 각속도 적분(tilt 보정). 자력계와 독립인 진단값.
  private var gyroHeadingDeg = 0.0
  private var gyroHeadingInitialized = false

  // 기압계(CMAltimeter). 층 전이 판정용이며 PDR 경로 계산에는 개입하지 않는다.
  // relativeAltitude는 startRelativeAltitudeUpdates 시점 기준 누적 상대고도이고,
  // pressure는 kPa다. Dart는 hPa 기압에서 고도를 직접 계산하므로(양 플랫폼 공통
  // 경로) relativeAltitude는 그 계산을 실측으로 검증하는 대조값으로만 쓴다.
  private var altimeterAvailable = false
  private var hasAltitudeSample = false
  private var latestRelativeAltitudeM = 0.0
  private var latestPressureHpa = 0.0
  private var latestAltitudeTimestampMs = 0.0
  private var lastAltitudeCallbackAt: Date?
  private var altimeterWatchdog: Timer?

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    sink = events
    motionQueue.qualityOfService = .userInteractive
    startPedometer()
    startDeviceMotion()
    startAltimeter()
    emit(kind: "snapshot")
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    pedometer.stopUpdates()
    motionManager.stopDeviceMotionUpdates()
    stopAltimeter()
    sink = nil
    return nil
  }

  /// CMPedometer를 "지금"부터 재시작해 세션 step을 0으로 되돌린다. 새 세션 id를
  /// 반환해 Dart가 이전 세션의 stale 업데이트를 버리게 한다. main thread에서만 호출.
  func resetPedometerBaseline() -> Int {
    dispatchPrecondition(condition: .onQueue(.main))
    pedometer.stopUpdates()
    stepSessionId += 1
    latestSteps = 0
    latestStepDelta = 0
    latestDistanceM = 0
    latestDistanceAvailable = false
    latestPedometerTimestampMs = 0
    latestPedometerGapMs = 0
    latestCadence = 0
    latestPace = 0
    latestCadenceAvailable = false
    latestPaceAvailable = false
    lastPedometerCallbackAt = nil
    pedometerFinalized = false
    accelTimes.removeAll(keepingCapacity: true)
    accelEast.removeAll(keepingCapacity: true)
    accelNorth.removeAll(keepingCapacity: true)
    latestWalkDirConfidence = 0
    stepPeakTimesMs.removeAll(keepingCapacity: true)
    stepPeakCount = 0
    latestStepPeakMs = 0
    peakArmed = true
    lastPeakMs = 0
    envInitialized = false
    accelEnvMax = 0
    accelEnvMin = 0
    gyroHeadingDeg = 0
    gyroHeadingInitialized = false
    startPedometer()
    emit(kind: "snapshot")
    return stepSessionId
  }

  /// 안내 종료 시점의 마지막 CMPedometer 상태를 동결한다. iOS의 후속 callback은
  /// stop() 전에 도착할 수 있으므로, 이 호출 뒤에는 세션 path를 바꾸지 않는다.
  /// 세션 구간을 사후 재조회한 결과를 함께 돌려준다(진단 전용, 보정 없음).
  ///
  /// `startUpdates`의 live stream은 첫 batch가 10초 이상 늦게 오면서 그 구간을
  /// 적게 세는 일이 관측됐다(실측: 14.9초 구간에 5걸음). 같은 구간을
  /// `queryPedometerData`로 다시 물었을 때 더 큰 값이 나오는지가, 걸음이
  /// "OS에 늦게 도착한 것"인지 "OS가 아예 못 본 것"인지를 가른다.
  ///
  /// 지금은 판단 근거만 모은다. `queriedSteps`가 `steps`보다 크다고 확인되기
  /// 전까지는 이 값으로 경로를 보정하지 않는다.
  func finalizePedometer(completion: @escaping ([String: Any]) -> Void) {
    dispatchPrecondition(condition: .onQueue(.main))
    let stoppedAtMs = Date().timeIntervalSince1970 * 1000.0
    pedometerFinalized = true
    emit(kind: "snapshot")

    var payload: [String: Any] = [
      "stepSessionId": stepSessionId,
      "sessionStartMs": pedometerSessionStartMs,
      "stoppedAtMs": stoppedAtMs,
      "steps": latestSteps,
      "distanceAvailable": latestDistanceAvailable,
    ]

    guard pedometerSessionStartMs > 0, CMPedometer.isStepCountingAvailable()
    else {
      payload["queryAvailable"] = false
      completion(payload)
      return
    }

    let from = Date(timeIntervalSince1970: pedometerSessionStartMs / 1000.0)
    let to = Date(timeIntervalSince1970: stoppedAtMs / 1000.0)
    pedometer.queryPedometerData(from: from, to: to) { data, error in
      DispatchQueue.main.async {
        payload["queryAvailable"] = true
        if let error {
          payload["queryError"] = error.localizedDescription
        } else if let data {
          payload["queriedSteps"] = data.numberOfSteps.intValue
          if let distance = data.distance?.doubleValue {
            payload["queriedDistanceM"] = distance
          }
        }
        completion(payload)
      }
    }
  }

  private func startPedometer() {
    guard CMPedometer.isStepCountingAvailable() else {
      sendError("Pedometer is not available on this device.")
      return
    }

    let sessionAtStart = stepSessionId
    let sessionStart = Date()
    pedometerSessionStartMs = sessionStart.timeIntervalSince1970 * 1000.0
    pedometer.startUpdates(from: sessionStart) { [weak self] data, error in
      guard let self else { return }
      DispatchQueue.main.async {
        guard sessionAtStart == self.stepSessionId else { return }
        guard !self.pedometerFinalized else { return }
        if let error {
          self.sendError("Pedometer: \(error.localizedDescription)")
          return
        }
        guard let data else { return }
        let steps = data.numberOfSteps.intValue
        self.latestStepDelta = max(0, steps - self.latestSteps)
        self.latestSteps = steps
        if let distance = data.distance?.doubleValue {
          self.latestDistanceM = distance
          self.latestDistanceAvailable = true
        } else {
          self.latestDistanceAvailable = false
        }
        if let cadence = data.currentCadence?.doubleValue {
          self.latestCadence = cadence
          self.latestCadenceAvailable = true
        } else {
          self.latestCadenceAvailable = false
        }
        if let pace = data.currentPace?.doubleValue {
          self.latestPace = pace
          self.latestPaceAvailable = true
        } else {
          self.latestPaceAvailable = false
        }
        self.latestPedometerTimestampMs =
          data.endDate.timeIntervalSince1970 * 1000.0
        let now = Date()
        if let last = self.lastPedometerCallbackAt {
          self.latestPedometerGapMs = now.timeIntervalSince(last) * 1000.0
        }
        self.lastPedometerCallbackAt = now
        self.emit(kind: "pedometer")
      }
    }
  }

  /// 기압계 스트림을 켠다. 없는 기기(iPhone 5s 이하)면 조용히 비활성 상태로 남고,
  /// Dart는 `altimeterAvailable=false`를 보고 층 전이 판정 자체를 끈다.
  ///
  /// pedometer reset에서 이 스트림을 다시 시작하지 않는다. 기압 시계열이 끊기면
  /// Dart의 baseline과 이동평균이 매 층 전환마다 처음부터 채워져야 하고, 그
  /// 공백 구간의 상승을 놓친다. 세션 baseline은 Dart가 관리한다.
  private func startAltimeter() {
    guard CMAltimeter.isRelativeAltitudeAvailable() else {
      altimeterAvailable = false
      return
    }
    guard !altimeterAvailable else { return }
    altimeterAvailable = true
    lastAltitudeCallbackAt = nil
    altimeterQueue.qualityOfService = .utility
    startAltimeterWatchdog()
    altimeter.startRelativeAltitudeUpdates(to: altimeterQueue) { [weak self] data, error in
      guard let self else { return }
      if let error {
        self.sendError("Altimeter: \(error.localizedDescription)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
          self?.restartAltimeter()
        }
        return
      }
      guard let data else { return }
      // CMAltitudeData.pressure는 kPa다. 1 kPa = 10 hPa.
      let pressureHpa = data.pressure.doubleValue * 10.0
      let relativeAltitudeM = data.relativeAltitude.doubleValue
      let timestampMs =
        (Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime
          + data.timestamp) * 1000.0
      DispatchQueue.main.async {
        self.lastAltitudeCallbackAt = Date()
        self.hasAltitudeSample = true
        self.latestPressureHpa = pressureHpa
        self.latestRelativeAltitudeM = relativeAltitudeM
        self.latestAltitudeTimestampMs = timestampMs
        self.emitAltitude()
      }
    }
  }

  /// EventChannel 재구독과 CMAltimeter의 드문 callback 정지를 함께 복구한다.
  ///
  /// 예전 onCancel은 native update만 멈추고 `altimeterAvailable`을 true로
  /// 남겼다. 그 결과 앱 background/foreground 뒤 startAltimeter의 guard가
  /// 재시작을 건너뛰어, 로그에는 첫 몇 샘플만 있고 이후 영구 정지했다.
  private func stopAltimeter() {
    altimeter.stopRelativeAltitudeUpdates()
    altimeterWatchdog?.invalidate()
    altimeterWatchdog = nil
    altimeterAvailable = false
    lastAltitudeCallbackAt = nil
  }

  private func restartAltimeter() {
    dispatchPrecondition(condition: .onQueue(.main))
    guard sink != nil else {
      stopAltimeter()
      return
    }
    stopAltimeter()
    startAltimeter()
  }

  private func startAltimeterWatchdog() {
    altimeterWatchdog?.invalidate()
    altimeterWatchdog = Timer.scheduledTimer(
      withTimeInterval: 2.0,
      repeats: true
    ) { [weak self] _ in
      guard let self, self.sink != nil, self.altimeterAvailable else { return }
      let silence = self.lastAltitudeCallbackAt.map { Date().timeIntervalSince($0) }
        ?? .infinity
      if silence >= 4.0 {
        self.restartAltimeter()
      }
    }
  }

  private func startDeviceMotion() {
    guard motionManager.isDeviceMotionAvailable else {
      sendError("DeviceMotion is not available on this device.")
      return
    }

    let frame: CMAttitudeReferenceFrame =
      CMMotionManager.availableAttitudeReferenceFrames()
        .contains(.xMagneticNorthZVertical)
      ? .xMagneticNorthZVertical
      : .xArbitraryCorrectedZVertical
    headingSource =
      frame == .xMagneticNorthZVertical
      ? "device_motion/xMagneticNorthZVertical"
      : "device_motion/xArbitraryCorrectedZVertical"

    motionManager.deviceMotionUpdateInterval = 1.0 / 100.0
    motionManager.startDeviceMotionUpdates(using: frame, to: motionQueue) {
      [weak self] motion, error in
      guard let self else { return }
      if let error {
        self.sendError("DeviceMotion: \(error.localizedDescription)")
        return
      }
      guard let motion else { return }

      // 정면 방향 = 기기 top축(+Y)의 수평 투영을, top이 충분히 기울면 후면 카메라
      // 축(-Z) 투영과 블렌딩. rotationMatrix는 reference->device라 ROW가 기기축의
      // reference 표현이다(row2=top=north,west,up; row3=+Z, 후면=-row3).
      let r = motion.attitude.rotationMatrix
      let topUp = r.m23
      let backWeight = min(1.0, max(0.0, (topUp - 0.5) / 0.37))
      let forwardNorth = r.m21 - backWeight * r.m31
      let forwardWest = r.m22 - backWeight * r.m32
      let horizontal =
        (forwardNorth * forwardNorth + forwardWest * forwardWest).squareRoot()

      var newHeadingDeg: Double?
      if horizontal > 0.4 {
        newHeadingDeg =
          normalizeDegrees(atan2(-forwardWest, forwardNorth) * 180.0 / .pi)
      }

      let attitude = motion.attitude
      let deviceHeading = motion.heading
      let accel = motion.userAcceleration
      let field = motion.magneticField.field
      let yawDeg = normalizeDegrees(attitude.yaw * 180.0 / .pi)
      let pitchDeg = attitude.pitch * 180.0 / .pi
      let rollDeg = attitude.roll * 180.0 / .pi
      let accelMagnitude =
        (accel.x * accel.x + accel.y * accel.y + accel.z * accel.z)
        .squareRoot()
      let gyroZ = motion.rotationRate.z
      let rotationRate = motion.rotationRate
      let gravity = motion.gravity
      let magneticField =
        (field.x * field.x + field.y * field.y + field.z * field.z)
        .squareRoot()
      let magneticAccuracy = magneticAccuracyLabel(motion.magneticField.accuracy)

      // world-frame 수평 user accel. v_ref = Rᵀ·v_device (col1=north, col2=west).
      // heading 블록과 같은 규약 유지(east = -west).
      let aNorth = r.m11 * accel.x + r.m21 * accel.y + r.m31 * accel.z
      let aWest = r.m12 * accel.x + r.m22 * accel.y + r.m32 * accel.z
      let aEast = -aWest
      let motionTimestampMs =
        (Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime
          + motion.timestamp) * 1000.0
      let bootTimestamp = motion.timestamp

      DispatchQueue.main.async {
        self.hasMotionSample = true
        if let newHeadingDeg {
          self.latestFusedHeadingDeg = newHeadingDeg
          self.headingStable = true
          if !self.gyroHeadingInitialized {
            self.gyroHeadingDeg = newHeadingDeg
            self.gyroHeadingInitialized = true
          }
        } else {
          self.headingStable = false
        }
        self.latestDeviceHeadingDeg = deviceHeading
        self.latestYawDeg = yawDeg
        self.latestPitchDeg = pitchDeg
        self.latestRollDeg = rollDeg
        self.latestAccelMagnitude = accelMagnitude
        self.latestGyroZ = gyroZ
        self.latestMagneticField = magneticField
        self.latestMagneticAccuracy = magneticAccuracy
        self.updateWalkingDirection(east: aEast, north: aNorth, at: bootTimestamp)
        self.detectStepPeak(accelMagnitude: accelMagnitude, atMs: motionTimestampMs)
        self.latestMotionTimestampMs = motionTimestampMs
        if let last = self.lastMotionBootTimestamp {
          let interval = bootTimestamp - last
          if interval > 0 {
            let hz = 1.0 / interval
            self.latestMotionHz =
              self.latestMotionHz == 0
              ? hz
              : self.latestMotionHz * 0.9 + hz * 0.1
            let gMag =
              (gravity.x * gravity.x + gravity.y * gravity.y + gravity.z
                * gravity.z).squareRoot()
            if interval < 0.5, gMag > 0, self.gyroHeadingInitialized {
              let headingRate =
                (rotationRate.x * gravity.x + rotationRate.y * gravity.y
                  + rotationRate.z * gravity.z) / gMag
              self.gyroHeadingDeg = normalizeDegrees(
                self.gyroHeadingDeg + headingRate * interval * 180.0 / .pi)
            }
          }
        }
        self.lastMotionBootTimestamp = bootTimestamp
        if motionTimestampMs - self.lastMotionEmitMs >= self.motionEmitIntervalMs {
          self.lastMotionEmitMs = motionTimestampMs
          self.emit(kind: "motion")
        }
      }
    }
  }

  /// 수평 world-frame accel window의 2x2 PCA로 보행 방향을 추정한다. 주축이 보행선
  /// (180도 모호성은 Dart가 해소), confidence는 이방성×에너지. main queue에서 실행.
  private func updateWalkingDirection(
    east: Double, north: Double, at timestamp: TimeInterval
  ) {
    accelTimes.append(timestamp)
    accelEast.append(east)
    accelNorth.append(north)
    var drop = 0
    while drop < accelTimes.count,
      accelTimes[drop] < timestamp - accelWindowSeconds
    {
      drop += 1
    }
    if drop > 0 {
      accelTimes.removeFirst(drop)
      accelEast.removeFirst(drop)
      accelNorth.removeFirst(drop)
    }
    let n = accelEast.count
    guard n >= 15 else {
      latestWalkDirConfidence = 0
      return
    }

    var meanE = 0.0
    var meanN = 0.0
    for i in 0..<n {
      meanE += accelEast[i]
      meanN += accelNorth[i]
    }
    meanE /= Double(n)
    meanN /= Double(n)

    var see = 0.0
    var snn = 0.0
    var sen = 0.0
    for i in 0..<n {
      let e = accelEast[i] - meanE
      let m = accelNorth[i] - meanN
      see += e * e
      snn += m * m
      sen += e * m
    }
    see /= Double(n)
    snn /= Double(n)
    sen /= Double(n)

    let trace = see + snn
    let disc = max(0.0, trace * trace / 4.0 - (see * snn - sen * sen))
    let l1 = trace / 2.0 + disc.squareRoot()
    let l2 = trace / 2.0 - disc.squareRoot()

    var vEast = sen
    var vNorth = l1 - see
    if abs(vEast) + abs(vNorth) < 1e-9 {
      vEast = l1 - snn
      vNorth = sen
    }
    latestWalkDirDeg = normalizeDegrees(atan2(vEast, vNorth) * 180.0 / .pi)

    let anisotropy = l1 > 1e-9 ? (l1 - max(0.0, l2)) / l1 : 0.0
    let energyConf = min(1.0, trace.squareRoot() / 0.06)
    latestWalkDirConfidence = anisotropy * energyConf
  }

  /// user-accel magnitude의 Schmitt 트리거 step-peak 검출. 카운트가 아니라 각 peak의
  /// 시각만 기록한다(Dart 배치 타이밍용).
  private func detectStepPeak(accelMagnitude mag: Double, atMs: Double) {
    if !envInitialized {
      accelEnvMax = mag
      accelEnvMin = mag
      envInitialized = true
    } else {
      accelEnvMax =
        mag > accelEnvMax ? mag : accelEnvMax + envReleaseAlpha * (mag - accelEnvMax)
      accelEnvMin =
        mag < accelEnvMin ? mag : accelEnvMin + envReleaseAlpha * (mag - accelEnvMin)
    }

    let swing = accelEnvMax - accelEnvMin
    if swing < minPeakSwingG {
      peakArmed = true
      return
    }
    let highThresh = max(minPeakHighG, accelEnvMin + peakHighRatio * swing)
    let lowThresh = accelEnvMin + peakLowRatio * swing

    if peakArmed,
      mag > highThresh,
      atMs - lastPeakMs > peakRefractoryMs
    {
      stepPeakTimesMs.append(atMs)
      stepPeakCount += 1
      latestStepPeakMs = atMs
      lastPeakMs = atMs
      peakArmed = false
      let cutoff = atMs - 20000
      while let first = stepPeakTimesMs.first, first < cutoff {
        stepPeakTimesMs.removeFirst()
      }
    } else if mag < lowThresh {
      peakArmed = true
    }
  }

  private func emit(kind: String) {
    guard let sink else { return }
    var payload: [String: Any] = [
      "source": "ios_core_motion",
      "kind": kind,
      "stepSessionId": stepSessionId,
    ]
    if kind == "snapshot" {
      // 첫 기압 샘플이 오기 전에도 Dart가 기능 가용 여부를 알아야 한다. 센서가
      // 없는 기기에서 "판정 대기 중"으로 오해하지 않게 하는 값이다.
      payload["altimeterAvailable"] = altimeterAvailable
      payload["altimeterSource"] =
        altimeterAvailable ? "ios_cmaltimeter" : "unavailable"
    }
    if kind != "pedometer" && hasMotionSample {
      payload["fusedHeadingDeg"] = latestFusedHeadingDeg
      payload["deviceHeadingDeg"] = latestDeviceHeadingDeg
      payload["headingStable"] = headingStable
      payload["headingSource"] = headingSource
      payload["yawDeg"] = latestYawDeg
      payload["gyroHeadingDeg"] = gyroHeadingDeg
      payload["pitchDeg"] = latestPitchDeg
      payload["rollDeg"] = latestRollDeg
      payload["magneticAccuracy"] = latestMagneticAccuracy
      payload["walkDirDeg"] = latestWalkDirDeg
      payload["walkDirConfidence"] = latestWalkDirConfidence
      payload["motionTimestamp"] = latestMotionTimestampMs
      payload["motionHz"] = latestMotionHz
      payload["stepPeakCount"] = stepPeakCount
      payload["latestStepPeakMs"] = latestStepPeakMs
      payload["thermalState"] = thermalStateLabel(
        ProcessInfo.processInfo.thermalState)
      payload["lowPowerMode"] = ProcessInfo.processInfo.isLowPowerModeEnabled
      payload["magneticField"] = latestMagneticField
      payload["accelMagnitude"] = latestAccelMagnitude
      payload["gyroZ"] = latestGyroZ
    }
    if kind != "motion" {
      payload["steps"] = latestSteps
      payload["stepDelta"] = latestStepDelta
      payload["pedometerDistance"] = latestDistanceM
      payload["pedometerDistanceAvailable"] = latestDistanceAvailable
      payload["pedometerTimestamp"] = latestPedometerTimestampMs
      payload["pedometerDeltaMs"] = latestPedometerGapMs
      payload["pedometerCadence"] = latestCadence
      payload["pedometerPace"] = latestPace
      payload["pedometerCadenceAvailable"] = latestCadenceAvailable
      payload["pedometerPaceAvailable"] = latestPaceAvailable
      payload["pedometerSessionStartMs"] = pedometerSessionStartMs
      payload["stepPeakTimes"] = stepPeakTimesMs
    }
    sink(payload)
  }

  /// 기압 샘플만 담은 이벤트. `emit(kind:)`을 재사용하지 않는 이유는 그쪽이
  /// `kind != "motion"`일 때 pedometer 블록을 함께 싣기 때문이다. 기압은 초당 한 번
  /// 오므로 그대로 태우면 같은 step 값이 계속 pedometer 배치로 재입력되고,
  /// Android쪽 대응 코드에서는 stepDelta 회계(lastReportedSteps)까지 흔든다.
  /// 층 전이 판정은 PDR 걸음 파이프라인과 완전히 분리해 둔다.
  private func emitAltitude() {
    guard let sink, hasAltitudeSample else { return }
    sink([
      "source": "ios_core_motion",
      "kind": "altitude",
      "stepSessionId": stepSessionId,
      "altimeterAvailable": altimeterAvailable,
      "altimeterSource": "ios_cmaltimeter",
      "pressureHpa": latestPressureHpa,
      "relativeAltitudeM": latestRelativeAltitudeM,
      "altitudeTimestamp": latestAltitudeTimestampMs,
    ])
  }

  private func sendError(_ message: String) {
    DispatchQueue.main.async { [weak self] in
      self?.sink?(FlutterError(code: "PDR_SENSOR", message: message, details: nil))
    }
  }
}

private func normalizeDegrees(_ degrees: Double) -> Double {
  let normalized = degrees.truncatingRemainder(dividingBy: 360.0)
  return normalized < 0 ? normalized + 360.0 : normalized
}

private func thermalStateLabel(_ state: ProcessInfo.ThermalState) -> String {
  switch state {
  case .nominal: return "nominal"
  case .fair: return "fair"
  case .serious: return "serious"
  case .critical: return "critical"
  @unknown default: return "unknown"
  }
}

private func magneticAccuracyLabel(
  _ accuracy: CMMagneticFieldCalibrationAccuracy
) -> String {
  switch accuracy {
  case .uncalibrated: return "uncalibrated"
  case .low: return "low"
  case .medium: return "medium"
  case .high: return "high"
  @unknown default: return "unknown"
  }
}
