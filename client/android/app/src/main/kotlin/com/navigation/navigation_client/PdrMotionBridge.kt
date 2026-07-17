package com.navigation.navigation_client

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.SystemClock
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/**
 * Android SensorManager -> typed Dart PDR boundary.
 *
 * STEP_COUNTER is the only confirmed-count authority after it becomes
 * available. STEP_DETECTOR and acceleration peaks remain timing/cadence
 * diagnostics; they must never independently extend the confirmed path.
 */
class PdrMotionBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : EventChannel.StreamHandler, MethodChannel.MethodCallHandler, SensorEventListener {
    private val sensorManager = activity.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private var sink: EventChannel.EventSink? = null

    private val rotationMatrix = FloatArray(9)
    private val orientation = FloatArray(3)
    private val gravity = FloatArray(3)
    private val linearAccel = FloatArray(3)
    private val rawAccel = FloatArray(3)
    private val gyro = FloatArray(3)
    private var hasRotation = false
    private var hasGravity = false
    private var hasLinearAccel = false
    private var rotationSource = "unavailable"

    private var rawRotationHeadingDeg = 0.0
    private var fusedHeadingDeg = 0.0
    private var gyroHeadingDeg = 0.0
    private var gyroHeadingInitialized = false
    private var selectedHeadingSource = "unavailable"
    private var deviceHeadingDeg = -1.0
    private var yawDeg = 0.0
    private var pitchDeg = 0.0
    private var rollDeg = 0.0
    private var headingStable = false
    private var rotationHeadingAccuracyDeg = -1.0
    private var magneticAccuracy = "unknown"
    private var magneticField = 0.0
    private var magneticFieldBaseline: Double? = null
    private var accelMagnitude = 0.0
    private var gyroZ = 0.0
    private var motionTimestampMs = 0.0
    private var motionHz = 0.0
    private var lastImuSensorNs = 0L
    private var lastGyroNs = 0L
    private var lastMotionEmitMs = 0.0

    private var stepSessionId = 0
    private var sessionStartMs = System.currentTimeMillis().toDouble()
    private var rawStepCounter: Float? = null
    private var stepCounterBaseline: Float? = null
    private var observedCounterSteps = 0
    private var observedCounterDelta = 0
    private var lastStepCounterAtMs = 0.0
    private var stepCounterReady = false
    private var counterLiveMode = false
    private var sessionFinalized = false
    private var steps = 0
    private var lastReportedSteps = 0
    private var detectorSteps = 0
    private var stepDetectorEvents = 0
    private var lastPedometerAtMs = 0.0
    private var lastPedometerEventAtMs = 0.0
    private var pedometerDeltaMs = 0.0
    private var cadenceHz = 0.0
    private var cadenceAvailable = false
    private var lastStepAccelAmplitudeMps2 = 0.0
    private var latestStepEventSource = "snapshot"

    // Peaks are timestamps only. They reconstruct heading timing for a
    // counter batch; they are deliberately not a second confirmed count.
    private val accelPeakTimes = ArrayList<Double>()
    private val detectorStepTimes = ArrayList<Double>()
    private var stepPeakCount = 0
    private var latestStepPeakMs = 0.0
    private var peakArmed = true
    private var lastPeakMs = 0.0
    private var envelopeInitialized = false
    private var envelopeMax = 0.0
    private var envelopeMin = 0.0
    private var stepWindowInitialized = false
    private var stepWindowMinG = 0.0
    private var stepWindowMaxG = 0.0

    private data class HorizontalSample(val bootSeconds: Double, val east: Double, val north: Double)
    private val horizontalSamples = ArrayList<HorizontalSample>()
    private var walkDirDeg = 0.0
    private var walkDirConfidence = 0.0

    init {
        EventChannel(messenger, "navigation_client/pdr_motion").setStreamHandler(this)
        MethodChannel(messenger, "navigation_client/pdr_motion_cmd").setMethodCallHandler(this)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
        startSensors()
        emit("snapshot")
    }

    override fun onCancel(arguments: Any?) {
        sensorManager.unregisterListener(this)
        sink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "resetPedometer" -> result.success(resetPedometer())
            "finalizePedometer" -> result.success(finalizePedometer())
            else -> result.notImplemented()
        }
    }

    private fun startSensors() {
        sensorManager.unregisterListener(this)
        val rotation = sensorManager.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
            ?: sensorManager.getDefaultSensor(Sensor.TYPE_GAME_ROTATION_VECTOR)
        rotationSource = when (rotation?.type) {
            Sensor.TYPE_ROTATION_VECTOR -> "sensor_manager/rotation_vector"
            Sensor.TYPE_GAME_ROTATION_VECTOR -> "sensor_manager/game_rotation_vector"
            else -> "unavailable"
        }
        register(rotation, 10_000)
        register(sensorManager.getDefaultSensor(Sensor.TYPE_LINEAR_ACCELERATION), 10_000)
        register(sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER), 10_000)
        register(sensorManager.getDefaultSensor(Sensor.TYPE_GRAVITY), 10_000)
        register(sensorManager.getDefaultSensor(Sensor.TYPE_GYROSCOPE), 10_000)
        register(sensorManager.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD), 20_000)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q ||
            ContextCompat.checkSelfPermission(activity, Manifest.permission.ACTIVITY_RECOGNITION) == PackageManager.PERMISSION_GRANTED
        ) {
            register(sensorManager.getDefaultSensor(Sensor.TYPE_STEP_COUNTER), SensorManager.SENSOR_DELAY_NORMAL)
            register(sensorManager.getDefaultSensor(Sensor.TYPE_STEP_DETECTOR), SensorManager.SENSOR_DELAY_FASTEST)
        }
    }

    private fun register(sensor: Sensor?, periodUs: Int) {
        if (sensor != null) sensorManager.registerListener(this, sensor, periodUs)
    }

    override fun onSensorChanged(event: SensorEvent) {
        when (event.sensor.type) {
            Sensor.TYPE_ROTATION_VECTOR, Sensor.TYPE_GAME_ROTATION_VECTOR -> updateRotation(event)
            Sensor.TYPE_LINEAR_ACCELERATION -> {
                copy3(event.values, linearAccel)
                hasLinearAccel = true
                captureImu(event.timestamp)
            }
            Sensor.TYPE_ACCELEROMETER -> {
                copy3(event.values, rawAccel)
                if (!hasLinearAccel) captureImu(event.timestamp)
            }
            Sensor.TYPE_GRAVITY -> {
                copy3(event.values, gravity)
                hasGravity = true
            }
            Sensor.TYPE_GYROSCOPE -> updateGyro(event)
            Sensor.TYPE_MAGNETIC_FIELD -> magneticField = magnitude(event.values)
            Sensor.TYPE_STEP_COUNTER -> updateStepCounter(event.values[0], event.timestamp)
            Sensor.TYPE_STEP_DETECTOR -> updateStepDetector(event.timestamp)
        }
    }

    private fun updateRotation(event: SensorEvent) {
        SensorManager.getRotationMatrixFromVector(rotationMatrix, event.values)
        SensorManager.getOrientation(rotationMatrix, orientation)
        hasRotation = true
        rotationHeadingAccuracyDeg = event.values.getOrNull(4)?.toDouble()?.takeIf { it >= 0 }
            ?.let { Math.toDegrees(it) } ?: -1.0

        // +Y(top) is the usual forward axis. When upright, smoothly use the
        // rear-camera (-Z) direction so portrait and held-flat walks agree.
        val topUp = rotationMatrix[7].toDouble()
        val cameraWeight = ((topUp - 0.5) / 0.37).coerceIn(0.0, 1.0)
        val forwardEast = rotationMatrix[1].toDouble() - cameraWeight * rotationMatrix[2]
        val forwardNorth = rotationMatrix[4].toDouble() - cameraWeight * rotationMatrix[5]
        if (sqrt(forwardEast * forwardEast + forwardNorth * forwardNorth) > 0.4) {
            rawRotationHeadingDeg = normalizeDegrees(Math.toDegrees(atan2(forwardEast, forwardNorth)))
            deviceHeadingDeg = rawRotationHeadingDeg
            if (!gyroHeadingInitialized) {
                gyroHeadingDeg = rawRotationHeadingDeg
                gyroHeadingInitialized = true
            }
        }
        yawDeg = normalizeDegrees(Math.toDegrees(orientation[0].toDouble()))
        pitchDeg = Math.toDegrees(orientation[1].toDouble())
        rollDeg = Math.toDegrees(orientation[2].toDouble())
    }

    private fun updateGyro(event: SensorEvent) {
        copy3(event.values, gyro)
        gyroZ = gyro[2].toDouble()
        if (lastGyroNs != 0L && gyroHeadingInitialized) {
            val dt = (event.timestamp - lastGyroNs) / 1_000_000_000.0
            if (dt in 0.0..0.5) {
                val g = if (hasGravity) gravity else floatArrayOf(0f, 0f, SensorManager.GRAVITY_EARTH)
                val gMagnitude = magnitude(g)
                if (gMagnitude > 0) {
                    val rate = (gyro[0] * g[0] + gyro[1] * g[1] + gyro[2] * g[2]) / gMagnitude
                    gyroHeadingDeg = normalizeDegrees(gyroHeadingDeg - Math.toDegrees(rate * dt))
                }
            }
        }
        lastGyroNs = event.timestamp
    }

    private fun captureImu(sensorNs: Long) {
        if (!hasRotation) return
        val epochMs = sensorNsToEpochMs(sensorNs)
        val user = if (hasLinearAccel) linearAccel else {
            val g = if (hasGravity) gravity else floatArrayOf(0f, 0f, SensorManager.GRAVITY_EARTH)
            floatArrayOf(rawAccel[0] - g[0], rawAccel[1] - g[1], rawAccel[2] - g[2])
        }
        val userXG = user[0] / SensorManager.GRAVITY_EARTH
        val userYG = user[1] / SensorManager.GRAVITY_EARTH
        val userZG = user[2] / SensorManager.GRAVITY_EARTH
        val worldEast = rotationMatrix[0] * userXG + rotationMatrix[1] * userYG + rotationMatrix[2] * userZG
        val worldNorth = rotationMatrix[3] * userXG + rotationMatrix[4] * userYG + rotationMatrix[5] * userZG
        accelMagnitude = sqrt(userXG * userXG + userYG * userYG + userZG * userZG).toDouble()
        if (!stepWindowInitialized) {
            stepWindowInitialized = true
            stepWindowMinG = accelMagnitude
            stepWindowMaxG = accelMagnitude
        } else {
            stepWindowMinG = min(stepWindowMinG, accelMagnitude)
            stepWindowMaxG = max(stepWindowMaxG, accelMagnitude)
        }
        motionTimestampMs = epochMs
        if (lastImuSensorNs != 0L) {
            val dt = (sensorNs - lastImuSensorNs) / 1_000_000_000.0
            if (dt > 0) {
                val hz = 1.0 / dt
                motionHz = if (motionHz == 0.0) hz else motionHz * 0.9 + hz * 0.1
            }
        }
        lastImuSensorNs = sensorNs

        selectHeading()
        updateWalkingDirection(sensorNs / 1_000_000_000.0, worldEast.toDouble(), worldNorth.toDouble())
        detectPeak(accelMagnitude, epochMs)
        if (epochMs - lastMotionEmitMs >= 30.0) {
            lastMotionEmitMs = epochMs
            emit("motion")
        }
    }

    /** A short gyro hold avoids a sudden magnetic jump; healthy rotation-vector
     * values relock immediately. SensorManager still supplies the base fusion. */
    private fun selectHeading() {
        val baseline = magneticFieldBaseline
        val fieldDeviation = if (baseline != null && baseline > 1 && magneticField > 1) {
            abs(magneticField - baseline) / baseline
        } else 0.0
        val innovation = angularDistance(rawRotationHeadingDeg, gyroHeadingDeg)
        val poorMagnetic = magneticAccuracy == "low" || magneticAccuracy == "uncalibrated"
        val inaccurate = rotationHeadingAccuracyDeg > 35
        val useGyroHold = rotationSource.contains("game_rotation_vector") || poorMagnetic ||
            fieldDeviation > 0.35 || innovation > 35 || inaccurate
        if (useGyroHold && gyroHeadingInitialized) {
            fusedHeadingDeg = gyroHeadingDeg
            // TYPE_ROTATION_VECTOR는 자력계까지 포함한 9-axis fusion이라
            // gyro hold 중에도 마지막 절대 북 기준 frame을 이어받는다. hold는
            // "정확도가 낮다"는 뜻이지, heading frame 자체가 arbitrary로
            // 바뀐다는 뜻은 아니다. 반대로 game rotation vector는 처음부터
            // 자력계를 쓰지 않으므로 기존처럼 absolute heading으로 선언하지
            // 않는다.
            selectedHeadingSource = if (rotationSource.contains("rotation_vector") &&
                !rotationSource.contains("game")) {
                "sensor_manager/rotation_vector+gyro_hold"
            } else {
                "sensor_manager/gyro_hold"
            }
            headingStable = false
            return
        }
        fusedHeadingDeg = rawRotationHeadingDeg
        selectedHeadingSource = rotationSource
        headingStable = rotationSource.contains("rotation_vector") && !rotationSource.contains("game")
        if (magneticField > 1) {
            magneticFieldBaseline = (magneticFieldBaseline ?: magneticField) * 0.985 + magneticField * 0.015
        }
    }

    private fun updateStepCounter(value: Float, sensorNs: Long) {
        rawStepCounter = value
        if (sessionFinalized) return
        if (stepCounterBaseline == null) stepCounterBaseline = value
        val counterSteps = max(0, (value - (stepCounterBaseline ?: value)).toInt())
        observedCounterDelta = max(0, counterSteps - observedCounterSteps)
        observedCounterSteps = counterSteps
        lastStepCounterAtMs = sensorNsToEpochMs(sensorNs)
        if (counterSteps <= 0) return
        stepCounterReady = true
        counterLiveMode = true
        if (counterSteps > steps) {
            steps = counterSteps
            latestStepEventSource = "step_counter+accel_timestamps"
            lastPedometerEventAtMs = lastStepCounterAtMs
            emit("pedometer")
        }
    }

    private fun updateStepDetector(sensorNs: Long) {
        if (sessionFinalized) return
        val atMs = sensorNsToEpochMs(sensorNs)
        stepDetectorEvents += 1
        val monotonicAtMs = if (lastPedometerAtMs > 0) max(atMs, lastPedometerAtMs + 0.001) else atMs
        pedometerDeltaMs = if (lastPedometerAtMs > 0) monotonicAtMs - lastPedometerAtMs else 0.0
        if (pedometerDeltaMs in 200.0..3_000.0) {
            cadenceHz = 1_000.0 / pedometerDeltaMs
            cadenceAvailable = true
        }
        lastPedometerAtMs = monotonicAtMs
        detectorSteps += 1
        detectorStepTimes.add(atMs)
        detectorStepTimes.removeAll { it < atMs - 20_000.0 }
        lastStepAccelAmplitudeMps2 = if (stepWindowInitialized) {
            max(0.0, stepWindowMaxG - stepWindowMinG) * SensorManager.GRAVITY_EARTH
        } else 0.0
        stepWindowMinG = accelMagnitude
        stepWindowMaxG = accelMagnitude
        stepWindowInitialized = true
        if (!counterLiveMode) {
            steps = detectorSteps
            latestStepEventSource = "step_detector_fallback"
            lastPedometerEventAtMs = atMs
            emit("pedometer")
        }
    }

    private fun resetPedometer(): Int {
        stepSessionId += 1
        sessionStartMs = System.currentTimeMillis().toDouble()
        stepCounterBaseline = rawStepCounter
        observedCounterSteps = 0
        observedCounterDelta = 0
        lastStepCounterAtMs = 0.0
        stepCounterReady = false
        counterLiveMode = false
        sessionFinalized = false
        steps = 0
        lastReportedSteps = 0
        detectorSteps = 0
        stepDetectorEvents = 0
        lastPedometerAtMs = 0.0
        lastPedometerEventAtMs = 0.0
        pedometerDeltaMs = 0.0
        cadenceHz = 0.0
        cadenceAvailable = false
        lastStepAccelAmplitudeMps2 = 0.0
        latestStepEventSource = "snapshot"
        accelPeakTimes.clear()
        detectorStepTimes.clear()
        stepPeakCount = 0
        latestStepPeakMs = 0.0
        peakArmed = true
        lastPeakMs = 0.0
        envelopeInitialized = false
        stepWindowInitialized = false
        horizontalSamples.clear()
        walkDirConfidence = 0.0
        gyroHeadingInitialized = false
        magneticFieldBaseline = null
        emit("snapshot")
        return stepSessionId
    }

    private fun finalizePedometer(): Map<String, Any> {
        val stoppedAtMs = System.currentTimeMillis().toDouble()
        if (stepCounterReady && observedCounterSteps > steps) {
            steps = observedCounterSteps
            latestStepEventSource = "step_counter+accel_timestamps"
            lastPedometerEventAtMs = if (lastStepCounterAtMs > 0) lastStepCounterAtMs else stoppedAtMs
        }
        sessionFinalized = true
        emit("snapshot")
        return linkedMapOf(
            "stepSessionId" to stepSessionId,
            "sessionStartMs" to sessionStartMs,
            "stoppedAtMs" to stoppedAtMs,
            "steps" to steps,
            "stepCounterSteps" to observedCounterSteps,
            "distanceAvailable" to false,
        )
    }

    private fun updateWalkingDirection(bootSeconds: Double, east: Double, north: Double) {
        horizontalSamples.add(HorizontalSample(bootSeconds, east, north))
        horizontalSamples.removeAll { it.bootSeconds < bootSeconds - 1.3 }
        if (horizontalSamples.size < 15) {
            walkDirConfidence = 0.0
            return
        }
        val meanEast = horizontalSamples.sumOf { it.east } / horizontalSamples.size
        val meanNorth = horizontalSamples.sumOf { it.north } / horizontalSamples.size
        var see = 0.0; var snn = 0.0; var sen = 0.0
        for (sample in horizontalSamples) {
            val e = sample.east - meanEast; val n = sample.north - meanNorth
            see += e * e; snn += n * n; sen += e * n
        }
        see /= horizontalSamples.size; snn /= horizontalSamples.size; sen /= horizontalSamples.size
        val trace = see + snn
        val disc = max(0.0, trace * trace / 4.0 - (see * snn - sen * sen))
        val l1 = trace / 2.0 + sqrt(disc)
        val l2 = trace / 2.0 - sqrt(disc)
        var vEast = sen; var vNorth = l1 - see
        if (abs(vEast) + abs(vNorth) < 1e-9) { vEast = l1 - snn; vNorth = sen }
        walkDirDeg = normalizeDegrees(Math.toDegrees(atan2(vEast, vNorth)))
        val anisotropy = if (l1 > 1e-9) (l1 - max(0.0, l2)) / l1 else 0.0
        walkDirConfidence = anisotropy * min(1.0, sqrt(trace) / 0.06)
    }

    private fun detectPeak(magnitude: Double, atMs: Double) {
        if (!envelopeInitialized) {
            envelopeInitialized = true; envelopeMax = magnitude; envelopeMin = magnitude
        } else {
            envelopeMax = if (magnitude > envelopeMax) magnitude else envelopeMax + 0.007 * (magnitude - envelopeMax)
            envelopeMin = if (magnitude < envelopeMin) magnitude else envelopeMin + 0.007 * (magnitude - envelopeMin)
        }
        val swing = envelopeMax - envelopeMin
        if (swing < 0.03) { peakArmed = true; return }
        val high = max(0.06, envelopeMin + 0.55 * swing)
        val low = envelopeMin + 0.30 * swing
        if (peakArmed && magnitude > high && atMs - lastPeakMs > 380.0) {
            accelPeakTimes.add(atMs)
            accelPeakTimes.removeAll { it < atMs - 20_000.0 }
            stepPeakCount += 1
            latestStepPeakMs = atMs
            lastPeakMs = atMs
            peakArmed = false
        } else if (magnitude < low) {
            peakArmed = true
        }
    }

    private fun emit(kind: String) {
        val eventSink = sink ?: return
        val payload = linkedMapOf<String, Any>(
            "source" to "android_sensor_manager",
            "kind" to kind,
            "stepSessionId" to stepSessionId,
        )
        if (kind != "pedometer" && hasRotation) {
            payload.putAll(linkedMapOf(
                "fusedHeadingDeg" to fusedHeadingDeg,
                "deviceHeadingDeg" to deviceHeadingDeg,
                "gyroHeadingDeg" to gyroHeadingDeg,
                "headingStable" to headingStable,
                "rotationHeadingAccuracyDeg" to rotationHeadingAccuracyDeg,
                "headingSource" to selectedHeadingSource,
                "yawDeg" to yawDeg, "pitchDeg" to pitchDeg, "rollDeg" to rollDeg,
                "magneticAccuracy" to magneticAccuracy, "magneticField" to magneticField,
                "walkDirDeg" to walkDirDeg, "walkDirConfidence" to walkDirConfidence,
                "motionTimestamp" to motionTimestampMs, "motionHz" to motionHz,
                "stepPeakCount" to stepPeakCount, "latestStepPeakMs" to latestStepPeakMs,
                "accelMagnitude" to accelMagnitude, "gyroZ" to gyroZ,
            ))
        }
        if (kind != "motion") {
            val reportedDelta = max(0, steps - lastReportedSteps)
            lastReportedSteps = steps
            val source = when {
                sessionFinalized && stepCounterReady -> "android_step_counter_final"
                counterLiveMode -> "android_step_counter_live"
                else -> "android_step_detector_fallback"
            }
            payload.putAll(linkedMapOf(
                "steps" to steps, "stepDelta" to reportedDelta,
                "stepCountSource" to source, "detectorSteps" to detectorSteps,
                "pedometerDistance" to 0.0, "pedometerDistanceAvailable" to false,
                "pedometerTimestamp" to lastPedometerEventAtMs, "pedometerDeltaMs" to pedometerDeltaMs,
                "pedometerCadence" to cadenceHz, "pedometerCadenceAvailable" to cadenceAvailable,
                "pedometerPace" to 0.0, "pedometerPaceAvailable" to false,
                "pedometerSessionStartMs" to sessionStartMs,
                "stepPeakTimes" to ArrayList(if (counterLiveMode) accelPeakTimes else detectorStepTimes),
                "accelPeakTimes" to ArrayList(accelPeakTimes),
                "stepEventSource" to latestStepEventSource,
                "stepAccelAmplitudeMps2" to lastStepAccelAmplitudeMps2,
                "stepCounterSteps" to observedCounterSteps, "stepCounterDelta" to observedCounterDelta,
                "counterLastEventAtMs" to lastStepCounterAtMs,
                "stepDetectorEvents" to stepDetectorEvents,
            ))
            if (sessionFinalized && stepCounterReady) payload["authoritativeSteps"] = observedCounterSteps
        }
        activity.runOnUiThread { eventSink.success(payload) }
    }

    override fun onAccuracyChanged(sensor: Sensor, accuracy: Int) {
        if (sensor.type == Sensor.TYPE_MAGNETIC_FIELD) {
            magneticAccuracy = when (accuracy) {
                SensorManager.SENSOR_STATUS_UNRELIABLE -> "uncalibrated"
                SensorManager.SENSOR_STATUS_ACCURACY_LOW -> "low"
                SensorManager.SENSOR_STATUS_ACCURACY_MEDIUM -> "medium"
                SensorManager.SENSOR_STATUS_ACCURACY_HIGH -> "high"
                else -> "unknown"
            }
        }
    }

    private fun sensorNsToEpochMs(sensorNs: Long): Double =
        System.currentTimeMillis().toDouble() - (SystemClock.elapsedRealtimeNanos() - sensorNs) / 1_000_000.0

    private fun copy3(from: FloatArray, to: FloatArray) {
        to[0] = from[0]; to[1] = from[1]; to[2] = from[2]
    }

    private fun magnitude(values: FloatArray): Double =
        sqrt(values.sumOf { value -> value.toDouble() * value.toDouble() })

    private fun angularDistance(a: Double, b: Double): Double =
        abs(((a - b + 540.0) % 360.0) - 180.0)

    private fun normalizeDegrees(degrees: Double): Double =
        ((degrees % 360.0) + 360.0) % 360.0
}
