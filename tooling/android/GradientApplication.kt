package com.dude555afk.gradient

import io.flutter.app.FlutterApplication
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugins.GeneratedPluginRegistrant

class GradientApplication : FlutterApplication() {
    lateinit var engine: FlutterEngine
        private set

    lateinit var backgroundRuntime: BackgroundRuntime
        private set

    override fun onCreate() {
        super.onCreate()

        engine = FlutterEngine(this)
        GeneratedPluginRegistrant.registerWith(engine)

        backgroundRuntime = BackgroundRuntime(this)
        backgroundRuntime.configure(engine.dartExecutor.binaryMessenger)

        engine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint.createDefault()
        )
    }
}
