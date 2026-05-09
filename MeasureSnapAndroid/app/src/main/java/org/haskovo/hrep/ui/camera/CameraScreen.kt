package org.haskovo.hrep.ui.camera

import android.Manifest
import android.view.MotionEvent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Build
import androidx.compose.material.icons.filled.Camera
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Straighten
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.google.ar.core.Plane
import com.google.ar.core.Point
import com.google.accompanist.permissions.ExperimentalPermissionsApi
import com.google.accompanist.permissions.rememberMultiplePermissionsState
import org.haskovo.hrep.viewmodels.CameraViewModel
import org.haskovo.hrep.viewmodels.MeasurementState
import io.github.sceneview.ar.ARScene

@OptIn(ExperimentalPermissionsApi::class)
@Composable
fun CameraScreen(viewModel: CameraViewModel) {
    val context = LocalContext.current

    // null = checking, true = strong, false = potato
    var arAvailable by remember { mutableStateOf<Boolean?>(null) }
    var forcePeasantMode by remember { mutableStateOf(false) }

    // 🕵️‍♂️ THE SOVIET HARDWARE INSPECTION 🕵️‍♂️
    LaunchedEffect(Unit) {
        val sensorManager = context.getSystemService(android.content.Context.SENSOR_SERVICE) as android.hardware.SensorManager
        val gyro = sensorManager.getDefaultSensor(android.hardware.Sensor.TYPE_GYROSCOPE)

        // 1. CHECK FOR PHYSICAL GYROSCOPE
        // Budget phones like Poco C85 use "Virtual Gyros" which return null or are weak.
        val hasPhysicalGyro = gyro != null && !gyro.isWakeUpSensor

        // 2. CHECK RAM (ARCore needs at least 4GB to not crash like a drunk uncle)
        val activityManager = context.getSystemService(android.content.Context.ACTIVITY_SERVICE) as android.app.ActivityManager
        val memInfo = android.app.ActivityManager.MemoryInfo()
        activityManager.getMemoryInfo(memInfo)
        val totalRamGB = memInfo.totalMem / (1024 * 1024 * 1024)

        // 3. ASK GOOGLE (But don't trust them blindly!)
        val arCore = com.google.ar.core.ArCoreApk.getInstance()
        var googleStatus = arCore.checkAvailability(context)
        while (googleStatus.isTransient) {
            kotlinx.coroutines.delay(200)
            googleStatus = arCore.checkAvailability(context)
        }

        // 🚨 THE VERDICT 🚨
        // If it has no gyro, or less than 4GB RAM, it's a POTATO.
        // We don't care if Google says 'Supported'.
        if (!hasPhysicalGyro || totalRamGB < 3.5) {
            arAvailable = false
            viewModel.setStatusMessage("Телефонът не поддържа AR. Превключване към нормална камера.")
        } else {
            arAvailable = googleStatus.isSupported
        }
    }

    val permissionsState = rememberMultiplePermissionsState(
        listOf(Manifest.permission.CAMERA, Manifest.permission.ACCESS_FINE_LOCATION)
    )

    LaunchedEffect(Unit) {
        if (!permissionsState.allPermissionsGranted) permissionsState.launchMultiplePermissionRequest()
    }

    if (!permissionsState.allPermissionsGranted) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp)) {
                Text("Необходими са права за камера и локация!", style = MaterialTheme.typography.bodyLarge)
                Button(onClick = { permissionsState.launchMultiplePermissionRequest() }) { Text("Даване на права") }
            }
        }
        return
    }

    val measureState   by viewModel.measureState.collectAsState()
    val measurements   by viewModel.measurements.collectAsState()
    val currentMeas    by viewModel.currentMeasurement.collectAsState()
    val statusMessage  by viewModel.statusMessage.collectAsState()
    val isCapturing    by viewModel.isCapturing.collectAsState()
    val location       by viewModel.location.collectAsState()

    var arFrame by remember { mutableStateOf<com.google.ar.core.Frame?>(null) }
    var pendingTapX by remember { mutableFloatStateOf(-1f) }
    var pendingTapY by remember { mutableFloatStateOf(-1f) }
    var arViewWidth by remember { mutableIntStateOf(0) }
    var arViewHeight by remember { mutableIntStateOf(0) }

    // Final decision: Are we using AR or Peasant Camera?
    val useArCamera = arAvailable == true && !forcePeasantMode

    if (isCapturing) {
        val activity = context as? android.app.Activity
        LaunchedEffect(Unit) {
            kotlinx.coroutines.delay(150)
            val root = activity?.window?.decorView

            if (root != null) {
                // Try the new Peasant Camera extraction first!
                val previewView = findPreviewView(root)
                if (previewView != null && previewView.bitmap != null) {
                    viewModel.savePhoto(previewView.bitmap!!)
                } else {
                    // Fallback to the old AR SurfaceView PixelCopy
                    val surfaceView = findSurfaceView(root)
                    if (surfaceView != null) {
                        try {
                            val bitmap = android.graphics.Bitmap.createBitmap(
                                surfaceView.width, surfaceView.height, android.graphics.Bitmap.Config.ARGB_8888
                            )
                            val handler = android.os.Handler(android.os.Looper.getMainLooper())
                            android.view.PixelCopy.request(surfaceView, bitmap, { result ->
                                if (result == android.view.PixelCopy.SUCCESS) viewModel.savePhoto(bitmap)
                                else viewModel.captureFailed()
                            }, handler)
                        } catch (e: Exception) {
                            viewModel.captureFailed()
                        }
                    } else {
                        viewModel.captureFailed()
                    }
                }
            } else {
                viewModel.captureFailed()
            }
        }
    }

    Box(
        Modifier
            .fillMaxSize()
            .onGloballyPositioned { coordinates ->
                arViewWidth = coordinates.size.width
                arViewHeight = coordinates.size.height
            }
    ) {
        // ==========================================
        // LAYER 1: THE CAMERA (BACKGROUND)
        // ==========================================
        if (arAvailable == null) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text("Проверка на телефона...", color = Color.White)
            }
        } else if (useArCamera) {
            // 🚀 THE GLORIOUS VIP AR CAMERA 🚀
            ARScene(
                modifier = Modifier.fillMaxSize(),
                sessionConfiguration = { session, config ->
                    config.planeFindingMode = com.google.ar.core.Config.PlaneFindingMode.HORIZONTAL_AND_VERTICAL
                    config.instantPlacementMode = com.google.ar.core.Config.InstantPlacementMode.LOCAL_Y_UP
                    if (session.isDepthModeSupported(com.google.ar.core.Config.DepthMode.AUTOMATIC)) {
                        config.depthMode = com.google.ar.core.Config.DepthMode.AUTOMATIC
                    }
                },
                onSessionUpdated = { _, frame ->
                    arFrame = frame
                    if (pendingTapX >= 0f && pendingTapY >= 0f) {
                        val tapX = pendingTapX
                        val tapY = pendingTapY
                        pendingTapX = -1f
                        pendingTapY = -1f

                        if (viewModel.measureState.value == MeasurementState.IDLE) {
                            viewModel.setStatusMessage("Моля натиснете 'Измерване'!")
                        } else if (frame.camera.trackingState != com.google.ar.core.TrackingState.TRACKING) {
                            viewModel.setStatusMessage("Калибриране на камерата. Моля изчакайте!")
                        } else {
                            val regularHits = frame.hitTest(tapX, tapY)
                            val instantHits = frame.hitTestInstantPlacement(tapX, tapY, 1.5f)
                            val allHits = regularHits + instantHits

                            if (allHits.isEmpty()) {
                                viewModel.setStatusMessage("Проблем! Преместете телефона леко!")
                            } else {
                                val planeHit = allHits.firstOrNull { it.trackable is Plane }
                                val depthHit = allHits.firstOrNull { it.trackable is com.google.ar.core.DepthPoint }
                                val instantHit = allHits.firstOrNull { it.trackable is com.google.ar.core.InstantPlacementPoint }
                                val pointHit = allHits.firstOrNull { it.trackable is Point }

                                val bestHit = planeHit ?: depthHit ?: instantHit ?: pointHit
                                if (bestHit != null) viewModel.handleTap(bestHit, frame)
                                else viewModel.setStatusMessage("Грешка! Пробвайте отново.")
                            }
                        }
                    }
                },
                onTouchEvent = { motionEvent, _ ->
                    if (motionEvent.action == MotionEvent.ACTION_DOWN) {
                        pendingTapX = if (arViewWidth > 0) arViewWidth / 2f else motionEvent.x
                        pendingTapY = if (arViewHeight > 0) arViewHeight / 2f else motionEvent.y
                        if (viewModel.measureState.value != MeasurementState.IDLE) {
                            viewModel.setStatusMessage("Калибриране...")
                        }
                    }
                    true
                }
            )

            // AR Graphics Overlay
            arFrame?.camera?.let { camera ->
                if (camera.trackingState == com.google.ar.core.TrackingState.TRACKING) {
                    val sw = arViewWidth.toFloat()
                    val sh = arViewHeight.toFloat()
                    if (sw > 0f && sh > 0f) {
                        androidx.compose.foundation.Canvas(modifier = Modifier.fillMaxSize()) {
                            val viewMatrix = FloatArray(16)
                            camera.getViewMatrix(viewMatrix, 0)
                            val projMatrix = FloatArray(16)
                            camera.getProjectionMatrix(projMatrix, 0, 0.1f, 100f)

                            val project = { pose: com.google.ar.core.Pose ->
                                val anchorPoint = floatArrayOf(pose.tx(), pose.ty(), pose.tz(), 1f)
                                val viewPoint = FloatArray(4)
                                android.opengl.Matrix.multiplyMV(viewPoint, 0, viewMatrix, 0, anchorPoint, 0)
                                if (viewPoint[2] <= 0f) {
                                    val projPoint = FloatArray(4)
                                    android.opengl.Matrix.multiplyMV(projPoint, 0, projMatrix, 0, viewPoint, 0)
                                    if (projPoint[3] != 0f) {
                                        val ndcX = projPoint[0] / projPoint[3]
                                        val ndcY = projPoint[1] / projPoint[3]
                                        val xPixel = (ndcX + 1f) * sw / 2f
                                        val yPixel = (1f - ndcY) * sh / 2f
                                        androidx.compose.ui.geometry.Offset(xPixel, yPixel)
                                    } else null
                                } else null
                            }

                            val drawPoint = { pt: org.haskovo.hrep.viewmodels.MeasurementPoint ->
                                if (pt.anchor.trackingState == com.google.ar.core.TrackingState.TRACKING) {
                                    project(pt.anchor.pose)?.let { offset ->
                                        drawCircle(color = Color.Red, radius = 20f, center = offset)
                                        drawCircle(color = Color.White, radius = 14f, center = offset)
                                    }
                                }
                            }

                            val drawLine3D = { pt1: org.haskovo.hrep.viewmodels.MeasurementPoint, pt2: org.haskovo.hrep.viewmodels.MeasurementPoint ->
                                if (pt1.anchor.trackingState == com.google.ar.core.TrackingState.TRACKING &&
                                    pt2.anchor.trackingState == com.google.ar.core.TrackingState.TRACKING
                                ) {
                                    val off1 = project(pt1.anchor.pose)
                                    val off2 = project(pt2.anchor.pose)
                                    if (off1 != null && off2 != null) {
                                        drawLine(color = Color.Yellow, start = off1, end = off2, strokeWidth = 8f)
                                    }
                                }
                            }

                            measurements.forEach { m ->
                                drawPoint(m.first)
                                m.second?.let {
                                    drawPoint(it)
                                    drawLine3D(m.first, it)
                                }
                            }
                            currentMeas?.first?.let { firstPt -> drawPoint(firstPt) }
                        }
                    }
                }
            }

            // Crosshair
            Box(
                Modifier
                    .fillMaxSize()
                    .pointerInput(Unit) {
                        detectTapGestures { offset ->
                            pendingTapX = if (arViewWidth > 0) arViewWidth / 2f else offset.x
                            pendingTapY = if (arViewHeight > 0) arViewHeight / 2f else offset.y
                        }
                    },
                contentAlignment = Alignment.Center
            ) {
                if (measureState != MeasurementState.IDLE) {
                    Box(Modifier.size(24.dp).background(Color.White.copy(alpha = 0.8f), CircleShape))
                }
            }

        } else {
            // 🚨 THE PEASANT Poco C85 CAMERA (CAMERA X) 🚨
            val lifecycleOwner = LocalLifecycleOwner.current
            androidx.compose.ui.viewinterop.AndroidView(
                modifier = Modifier.fillMaxSize(),
                factory = { ctx ->
                    val previewView = androidx.camera.view.PreviewView(ctx).apply {
                        // FIX FOR XIAOMI/POCO BLACK SCREEN: Use COMPATIBLE (TextureView) instead of PERFORMANCE!
                        implementationMode = androidx.camera.view.PreviewView.ImplementationMode.COMPATIBLE
                    }
                    val cameraProviderFuture = androidx.camera.lifecycle.ProcessCameraProvider.getInstance(ctx)
                    cameraProviderFuture.addListener({
                        val cameraProvider = cameraProviderFuture.get()
                        val preview = androidx.camera.core.Preview.Builder().build().also {
                            it.setSurfaceProvider(previewView.surfaceProvider)
                        }
                        val cameraSelector = androidx.camera.core.CameraSelector.DEFAULT_BACK_CAMERA
                        try {
                            cameraProvider.unbindAll()
                            cameraProvider.bindToLifecycle(lifecycleOwner, cameraSelector, preview)
                        } catch (e: Exception) {
                            viewModel.setStatusMessage("Грешка с нормалната камера!")
                        }
                    }, androidx.core.content.ContextCompat.getMainExecutor(ctx))
                    previewView
                }
            )
        }

        // ==========================================
        // LAYER 2: THE UI (VISIBLE TO EVERYONE!)
        // ==========================================

        // Manual Override Button (Top Left)
        if (arAvailable == true) {
            IconButton(
                onClick = {
                    forcePeasantMode = !forcePeasantMode
                    viewModel.clearMeasurements()
                    viewModel.setStatusMessage(if (forcePeasantMode) "Смяна към нормална камера!" else "Смяна към AR камера!")
                },
                modifier = Modifier.align(Alignment.TopStart).padding(top = 88.dp, start = 16.dp)
                    .background(Color.Black.copy(alpha = 0.5f), CircleShape)
            ) {
                Icon(Icons.Default.Build, contentDescription = "Toggle Camera", tint = if (forcePeasantMode) Color.Red else Color.White)
            }
        }

        // Top HUD
        Column(Modifier.fillMaxWidth().padding(top = 16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            location?.let { loc ->
                Surface(shape = RoundedCornerShape(20.dp), color = Color.Black.copy(alpha = 0.55f), modifier = Modifier.padding(bottom = 8.dp)) {
                    Text(loc.address ?: "%.4f, %.4f".format(loc.latitude, loc.longitude), color = Color.White, fontSize = 12.sp, modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp))
                }
            }
            statusMessage?.let { msg ->
                Surface(shape = RoundedCornerShape(12.dp), color = Color.Black.copy(alpha = 0.65f)) {
                    Text(msg, color = Color.White, fontSize = 13.sp, modifier = Modifier.padding(horizontal = 14.dp, vertical = 8.dp))
                }
            }
        }

        // Measurement list
        if (measurements.isNotEmpty()) {
            Column(Modifier.align(Alignment.TopEnd).padding(top = 80.dp, end = 12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                measurements.forEachIndexed { i, m ->
                    Surface(shape = RoundedCornerShape(8.dp), color = Color.Black.copy(alpha = 0.65f)) {
                        Text("M${i + 1}: ${m.displayString ?: "…"}", color = Color(0xFFfbbf24), fontSize = 14.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(8.dp))
                    }
                }
            }
        }

        // Bottom controls
        if (!isCapturing) {
            Column(Modifier.align(Alignment.BottomCenter).padding(bottom = 32.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                    if (measureState != MeasurementState.IDLE || measurements.isNotEmpty()) {
                        OutlinedButton(onClick = { viewModel.clearMeasurements() }, colors = ButtonDefaults.outlinedButtonColors(contentColor = Color.White)) {
                            Icon(Icons.Default.Close, contentDescription = "Clear")
                            Spacer(Modifier.width(4.dp))
                            Text("Изчистване")
                        }
                    }
                    Button(
                        onClick = {
                            if (useArCamera) viewModel.startMeasuring()
                            else viewModel.setStatusMessage("Нормалната камера може само да прави снимки, без мерене!")
                        },
                        enabled = measureState == MeasurementState.IDLE
                    ) {
                        Icon(Icons.Default.Straighten, contentDescription = "Measure")
                        Spacer(Modifier.width(6.dp))
                        Text("Измерване")
                    }
                }
                IconButton(
                    onClick = { viewModel.startCapture() },
                    enabled = !isCapturing,
                    modifier = Modifier.size(72.dp).background(if (isCapturing) Color.Gray else Color.White, CircleShape)
                ) {
                    Icon(Icons.Default.Camera, contentDescription = "Capture", tint = Color.Black, modifier = Modifier.size(36.dp))
                }
            }
        }
    }
}

private fun findSurfaceView(view: android.view.View): android.view.SurfaceView? {
    if (view is android.view.SurfaceView) return view
    if (view is android.view.ViewGroup) {
        for (i in 0 until view.childCount) findSurfaceView(view.getChildAt(i))?.let { return it }
    }
    return null
}

private fun findPreviewView(view: android.view.View): androidx.camera.view.PreviewView? {
    if (view is androidx.camera.view.PreviewView) return view
    if (view is android.view.ViewGroup) {
        for (i in 0 until view.childCount) findPreviewView(view.getChildAt(i))?.let { return it }
    }
    return null
}