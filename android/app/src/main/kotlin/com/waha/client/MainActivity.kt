package com.waha.client

import io.flutter.embedding.android.FlutterActivity

// waha_client has no kiosk hardware (no payment terminal, no USB serial, no
// diagnostics/trace-log pipeline) — plain FlutterActivity, nothing native to
// wire up.
class MainActivity : FlutterActivity()
