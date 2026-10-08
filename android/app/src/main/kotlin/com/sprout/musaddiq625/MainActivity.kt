package com.sprout.musaddiq625

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val luxChannel = "com.sprout.musaddiq625/lux"
    private val luxStreamChannel = "com.sprout.musaddiq625/lux_stream"

    private var sensorManager: SensorManager? = null
    private var luxListener: SensorEventListener? = null

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
    }
}
