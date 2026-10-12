package com.sprout.musaddiq625

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val luxChannel = "com.sprout.musaddiq625/lux"
    private val luxStreamChannel = "com.sprout.musaddiq625/lux_stream"
    private val accelStreamChannel = "com.sprout.musaddiq625/accel_stream"
    private val stepStreamChannel = "com.sprout.musaddiq625/step_stream"
    private val statusChannel = "com.sprout.musaddiq625/system_status"
    private val statusStreamChannel =
        "com.sprout.musaddiq625/system_status_stream"
    private val stepPermissionCode = 7101

    private var sensorManager: SensorManager? = null
    private var luxListener: SensorEventListener? = null
    private var accelListener: SensorEventListener? = null
    private var stepListener: SensorEventListener? = null
    private var pendingStepSink: EventChannel.EventSink? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var airplaneObserver: android.database.ContentObserver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager

        // Method channel: check sensor availability
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            luxChannel
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasSensor" -> {
                    val sensor =
                        sensorManager?.getDefaultSensor(Sensor.TYPE_LIGHT)
                    result.success(sensor != null)
                }
                else -> result.notImplemented()
            }
        }

        // Method channel: connectivity state for the status chips —
        // {wifi: bool, airplane: bool}. Proof the AI runs offline.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            statusChannel
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> result.success(systemStatus())
                else -> result.notImplemented()
            }
        }

        // Event channel: pushes the same map the moment wifi or
        // airplane mode flips — no polling on the Dart side.
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            statusStreamChannel
        ).setStreamHandler(object : EventChannel.StreamHandler {
            private val mainHandler = android.os.Handler(
                android.os.Looper.getMainLooper()
            )

            private fun emit(events: EventChannel.EventSink?) {
                // NetworkCallback fires on the connectivity thread —
                // EventSink must be touched on the platform thread.
                mainHandler.post {
                    events?.success(systemStatus())
                }
            }

            override fun onListen(
                arguments: Any?,
                events: EventChannel.EventSink?
            ) {
                val cm = getSystemService(
                    Context.CONNECTIVITY_SERVICE
                ) as ConnectivityManager
                val cb = object : ConnectivityManager.NetworkCallback() {
                    override fun onAvailable(
                        network: android.net.Network
                    ) = emit(events)

                    override fun onLost(
                        network: android.net.Network
                    ) = emit(events)

                    override fun onCapabilitiesChanged(
                        network: android.net.Network,
                        caps: NetworkCapabilities
                    ) = emit(events)
                }
                networkCallback = cb
                cm.registerDefaultNetworkCallback(cb)

                val observer = object : android.database.ContentObserver(
                    mainHandler
                ) {
                    override fun onChange(selfChange: Boolean) =
                        emit(events)
                }
                airplaneObserver = observer
                contentResolver.registerContentObserver(
                    Settings.Global.getUriFor(
                        Settings.Global.AIRPLANE_MODE_ON
                    ),
                    false, observer
                )
                emit(events)
            }

            override fun onCancel(arguments: Any?) {
                val cm = getSystemService(
                    Context.CONNECTIVITY_SERVICE
                ) as ConnectivityManager
                networkCallback?.let {
                    cm.unregisterNetworkCallback(it)
                }
                networkCallback = null
                airplaneObserver?.let {
                    contentResolver.unregisterContentObserver(it)
                }
                airplaneObserver = null
            }
        })

        // Event channel: stream lux readings
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            luxStreamChannel
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                val sensor =
                    sensorManager?.getDefaultSensor(Sensor.TYPE_LIGHT)
                if (sensor == null) {
                    events?.error("NO_SENSOR", "No light sensor", null)
                    return
                }
                luxListener = object : SensorEventListener {
                    override fun onSensorChanged(event: SensorEvent) {
                        events?.success(event.values[0].toDouble())
                    }

                    override fun onAccuracyChanged(
                        sensor: Sensor?, accuracy: Int
                    ) {}
                }
                sensorManager?.registerListener(
                    luxListener,
                    sensor,
                    SensorManager.SENSOR_DELAY_NORMAL
                )
            }

            override fun onCancel(arguments: Any?) {
                luxListener?.let {
                    sensorManager?.unregisterListener(it)
                }
                luxListener = null
            }
        })

        // Event channel: stream accelerometer readings [x, y, z] m/s²
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            accelStreamChannel
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                val sensor =
                    sensorManager?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
                if (sensor == null) {
                    events?.error("NO_SENSOR", "No accelerometer", null)
                    return
                }
                accelListener = object : SensorEventListener {
                    override fun onSensorChanged(event: SensorEvent) {
                        events?.success(
                            listOf(
                                event.values[0].toDouble(),
                                event.values[1].toDouble(),
                                event.values[2].toDouble()
                            )
                        )
                    }

                    override fun onAccuracyChanged(
                        sensor: Sensor?, accuracy: Int
                    ) {}
                }
                sensorManager?.registerListener(
                    accelListener,
                    sensor,
                    SensorManager.SENSOR_DELAY_GAME
                )
            }

            override fun onCancel(arguments: Any?) {
                accelListener?.let {
                    sensorManager?.unregisterListener(it)
                }
                accelListener = null
            }
        })

        // Event channel: step detector — emits 1 per detected step.
        // TYPE_STEP_DETECTOR needs ACTIVITY_RECOGNITION on API 29+;
        // requested lazily on first listen, error if denied.
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            stepStreamChannel
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                val sensor =
                    sensorManager?.getDefaultSensor(Sensor.TYPE_STEP_DETECTOR)
                if (sensor == null) {
                    events?.error("NO_SENSOR", "No step detector", null)
                    return
                }
                if (checkSelfPermission(
                        android.Manifest.permission.ACTIVITY_RECOGNITION
                    ) != android.content.pm.PackageManager.PERMISSION_GRANTED
                ) {
                    pendingStepSink = events
                    requestPermissions(
                        arrayOf(
                            android.Manifest.permission.ACTIVITY_RECOGNITION
                        ),
                        stepPermissionCode
                    )
                    return
                }
                startStepListener(sensor, events)
            }

            override fun onCancel(arguments: Any?) {
                stepListener?.let {
                    sensorManager?.unregisterListener(it)
                }
                stepListener = null
            }
        })
    }

    /// {wifi: bool, airplane: bool} — used by both the snapshot
    /// method channel and the live status stream.
    private fun systemStatus(): Map<String, Boolean> {
        val cm = getSystemService(
            Context.CONNECTIVITY_SERVICE
        ) as ConnectivityManager
        val caps = cm.getNetworkCapabilities(cm.activeNetwork)
        return mapOf(
            "wifi" to (caps?.hasTransport(
                NetworkCapabilities.TRANSPORT_WIFI
            ) == true),
            "airplane" to (Settings.Global.getInt(
                contentResolver,
                Settings.Global.AIRPLANE_MODE_ON, 0
            ) == 1)
        )
    }

    private fun startStepListener(
        sensor: Sensor,
        events: EventChannel.EventSink?
    ) {
        stepListener = object : SensorEventListener {
            override fun onSensorChanged(event: SensorEvent) {
                events?.success(1)
            }

            override fun onAccuracyChanged(
                sensor: Sensor?, accuracy: Int
            ) {}
        }
        sensorManager?.registerListener(
            stepListener,
            sensor,
            SensorManager.SENSOR_DELAY_NORMAL
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(
            requestCode, permissions, grantResults
        )
        if (requestCode == stepPermissionCode) {
            val sink = pendingStepSink
            pendingStepSink = null
            if (sink == null) return
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] ==
                    android.content.pm.PackageManager.PERMISSION_GRANTED
            if (granted) {
                val sensor = sensorManager?.getDefaultSensor(
                    Sensor.TYPE_STEP_DETECTOR
                )
                if (sensor != null) {
                    startStepListener(sensor, sink)
                } else {
                    sink.error("NO_SENSOR", "No step detector", null)
                }
            } else {
                sink.error("DENIED", "Activity recognition denied", null)
            }
        }
    }
}
