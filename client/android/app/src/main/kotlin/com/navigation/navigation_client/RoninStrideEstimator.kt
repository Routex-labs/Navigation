package com.navigation.navigation_client

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import android.content.Context
import java.nio.FloatBuffer
import java.util.ArrayDeque
import java.util.concurrent.Executors
import kotlin.math.max
import kotlin.math.sqrt

/**
 * Android IMU를 공식 RoNIN TCN 입력(200Hz, 세계 좌표계 6축)으로 바꿔
 * 최근 수평 속도만 추정한다.
 *
 * 이 클래스는 위치를 직접 갱신하지 않는다. [PdrMotionBridge]가 추정 속도를
 * STEP_DETECTOR cadence로 나눠 자동 보폭 후보를 만들고, Dart 코어는 그 후보를
 * 기존 heading/step timing에 적용한 별도 비교 경로만 누적한다.
 */
class RoninStrideEstimator(context: Context) {
    data class Estimate(
        val speedMps: Double,
        val speedStdMps: Double,
        val inferredAtSensorNs: Long,
    )

    private data class ImuSample(
        val sensorNs: Long,
        val values: FloatArray,
    )

    companion object {
        const val MODEL_NAME = "ronin-tcn-200hz"
        private const val MODEL_ASSET = "ronin/ronin_tcn_200hz.onnx"
        private const val CHANNELS = 6
        private const val WINDOW_SAMPLES = 400
        private const val OUTPUT_AVERAGE_SAMPLES = 100
        private const val SAMPLE_PERIOD_NS = 5_000_000L
        private const val WINDOW_SPAN_NS = (WINDOW_SAMPLES - 1) * SAMPLE_PERIOD_NS
        private const val RAW_HISTORY_NS = 3_000_000_000L
        private const val INFERENCE_INTERVAL_NS = 500_000_000L
        private const val MAX_INPUT_GAP_NS = 40_000_000L
    }

    private val lock = Any()
    private val rawSamples = ArrayDeque<ImuSample>()
    private val executor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "ronin-inference").apply { isDaemon = true }
    }

    private val environment: OrtEnvironment?
    private val session: OrtSession?
    private val inputName: String?

    @Volatile
    var latestEstimate: Estimate? = null
        private set

    @Volatile
    var status: String = "loading"
        private set

    private var inferenceRunning = false
    private var lastInferenceScheduledNs = 0L
    private var generation = 0

    init {
        var loadedEnvironment: OrtEnvironment? = null
        var loadedSession: OrtSession? = null
        var loadedInputName: String? = null
        try {
            val env = OrtEnvironment.getEnvironment()
            loadedEnvironment = env
            val model = context.assets.open(MODEL_ASSET).use { it.readBytes() }
            val createdSession = OrtSession.SessionOptions().use { options ->
                options.setIntraOpNumThreads(1)
                options.setInterOpNumThreads(1)
                options.setOptimizationLevel(OrtSession.SessionOptions.OptLevel.ALL_OPT)
                env.createSession(model, options)
            }
            loadedSession = createdSession
            loadedInputName = createdSession.inputNames.single()
            status = "warming"
        } catch (error: Throwable) {
            status = "load-error:${error.javaClass.simpleName}"
        }
        environment = loadedEnvironment
        session = loadedSession
        inputName = loadedInputName
    }

    val supported: Boolean
        get() = session != null && inputName != null

    /**
     * calibrated gyro(rad/s)와 gravity를 포함한 accelerometer(m/s²)를
     * SensorManager rotation matrix로 세계 동/북/상 축에 회전해 저장한다.
     */
    fun addDeviceSample(
        sensorNs: Long,
        gyro: FloatArray,
        accelerometer: FloatArray,
        rotationMatrix: FloatArray,
    ) {
        if (!supported) return
        val sample = ImuSample(
            sensorNs = sensorNs,
            values = floatArrayOf(
                rotateX(rotationMatrix, gyro),
                rotateY(rotationMatrix, gyro),
                rotateZ(rotationMatrix, gyro),
                rotateX(rotationMatrix, accelerometer),
                rotateY(rotationMatrix, accelerometer),
                rotateZ(rotationMatrix, accelerometer),
            ),
        )
        var snapshot: List<ImuSample>? = null
        var snapshotGeneration = 0
        synchronized(lock) {
            rawSamples.addLast(sample)
            val oldestAllowed = sensorNs - RAW_HISTORY_NS
            while (rawSamples.isNotEmpty() && rawSamples.first().sensorNs < oldestAllowed) {
                rawSamples.removeFirst()
            }
            val covered = rawSamples.isNotEmpty() &&
                sensorNs - rawSamples.first().sensorNs >= WINDOW_SPAN_NS
            if (
                covered &&
                !inferenceRunning &&
                sensorNs - lastInferenceScheduledNs >= INFERENCE_INTERVAL_NS
            ) {
                inferenceRunning = true
                lastInferenceScheduledNs = sensorNs
                snapshot = rawSamples.toList()
                snapshotGeneration = generation
            }
        }
        val captured = snapshot ?: return
        val capturedGeneration = snapshotGeneration
        executor.execute {
            try {
                infer(captured, capturedGeneration)
            } catch (error: Throwable) {
                synchronized(lock) {
                    if (capturedGeneration == generation) {
                        status = "inference-error:${error.javaClass.simpleName}"
                    }
                }
            } finally {
                synchronized(lock) {
                    inferenceRunning = false
                }
            }
        }
    }

    fun resetSession() {
        synchronized(lock) {
            generation += 1
            latestEstimate = null
            status = if (supported) "warming" else status
            rawSamples.clear()
            lastInferenceScheduledNs = 0L
        }
    }

    private fun infer(samples: List<ImuSample>, inferenceGeneration: Int) {
        val activeEnvironment = environment ?: return
        val activeSession = session ?: return
        val activeInputName = inputName ?: return
        val input = resample(samples) ?: run {
            synchronized(lock) {
                if (inferenceGeneration == generation) {
                    status = "input-gap"
                }
            }
            return
        }
        val tensor = OnnxTensor.createTensor(
            activeEnvironment,
            FloatBuffer.wrap(input),
            longArrayOf(1, WINDOW_SAMPLES.toLong(), CHANNELS.toLong()),
        )
        tensor.use {
            activeSession.run(mapOf(activeInputName to tensor)).use { result ->
                @Suppress("UNCHECKED_CAST")
                val velocity = result[0].value as Array<Array<FloatArray>>
                val frames = velocity[0]
                val start = max(0, frames.size - OUTPUT_AVERAGE_SAMPLES)
                var speedSum = 0.0
                var speedSquareSum = 0.0
                for (index in start until frames.size) {
                    val vx = frames[index][0].toDouble()
                    val vy = frames[index][1].toDouble()
                    val speed = sqrt(vx * vx + vy * vy)
                    speedSum += speed
                    speedSquareSum += speed * speed
                }
                val count = max(1, frames.size - start)
                val mean = speedSum / count
                val variance = max(0.0, speedSquareSum / count - mean * mean)
                synchronized(lock) {
                    if (inferenceGeneration == generation) {
                        latestEstimate = Estimate(
                            speedMps = mean,
                            speedStdMps = sqrt(variance),
                            inferredAtSensorNs = samples.last().sensorNs,
                        )
                        status = "ready"
                    }
                }
            }
        }
    }

    private fun resample(samples: List<ImuSample>): FloatArray? {
        if (samples.size < 2) return null
        val endNs = samples.last().sensorNs
        val startNs = endNs - WINDOW_SPAN_NS
        if (samples.first().sensorNs > startNs) return null

        val output = FloatArray(WINDOW_SAMPLES * CHANNELS)
        var right = 1
        for (frame in 0 until WINDOW_SAMPLES) {
            val targetNs = startNs + frame * SAMPLE_PERIOD_NS
            while (right < samples.size && samples[right].sensorNs < targetNs) {
                right += 1
            }
            if (right >= samples.size) return null
            val before = samples[right - 1]
            val after = samples[right]
            val gapNs = after.sensorNs - before.sensorNs
            if (gapNs <= 0L || gapNs > MAX_INPUT_GAP_NS) return null
            val ratio = (targetNs - before.sensorNs).toDouble() / gapNs
            for (channel in 0 until CHANNELS) {
                val left = before.values[channel]
                val value = left + (after.values[channel] - left) * ratio
                output[frame * CHANNELS + channel] = value.toFloat()
            }
        }
        return output
    }

    private fun rotateX(matrix: FloatArray, vector: FloatArray): Float =
        matrix[0] * vector[0] + matrix[1] * vector[1] + matrix[2] * vector[2]

    private fun rotateY(matrix: FloatArray, vector: FloatArray): Float =
        matrix[3] * vector[0] + matrix[4] * vector[1] + matrix[5] * vector[2]

    private fun rotateZ(matrix: FloatArray, vector: FloatArray): Float =
        matrix[6] * vector[0] + matrix[7] * vector[1] + matrix[8] * vector[2]
}
