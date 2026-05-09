package org.haskovo.hrep.viewmodels

import android.graphics.Bitmap
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.google.ar.core.Anchor
import com.google.ar.core.Frame
import com.google.ar.core.HitResult
import org.haskovo.hrep.managers.LocationData
import org.haskovo.hrep.managers.LocationManager
import org.haskovo.hrep.managers.PhotoStore
import org.haskovo.hrep.managers.UploadManager
import org.haskovo.hrep.managers.UploadResult
import org.haskovo.hrep.models.MeasuredPhoto
import org.haskovo.hrep.models.Measurement
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import java.io.File
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.sqrt

enum class MeasurementState { IDLE, PLACING_FIRST, PLACING_SECOND }

data class MeasurementPoint(
    val anchor: Anchor,
    val x: Float, val y: Float, val z: Float   // world position
)

data class ActiveMeasurement(
    val first: MeasurementPoint,
    val second: MeasurementPoint? = null
) {
    val distanceM: Float? get() {
        val s = second ?: return null
        val dx = s.x - first.x; val dy = s.y - first.y; val dz = s.z - first.z
        return sqrt(dx * dx + dy * dy + dz * dz)
    }
    val displayString: String? get() {
        val d = distanceM ?: return null
        return if (d >= 1f) "%.2f m".format(d) else "%.1f cm".format(d * 100)
    }
}

class CameraViewModel(
    private val photoStore: PhotoStore,
    private val uploadManager: UploadManager,
    private val locationManager: LocationManager
) : ViewModel() {

    val location: StateFlow<LocationData?> = locationManager.location

    private val _measureState = MutableStateFlow(MeasurementState.IDLE)
    val measureState: StateFlow<MeasurementState> = _measureState

    private val _measurements = MutableStateFlow<List<ActiveMeasurement>>(emptyList())
    val measurements: StateFlow<List<ActiveMeasurement>> = _measurements

    private val _currentMeasurement = MutableStateFlow<ActiveMeasurement?>(null)
    val currentMeasurement: StateFlow<ActiveMeasurement?> = _currentMeasurement

    private val _statusMessage = MutableStateFlow<String?>(null)
    val statusMessage: StateFlow<String?> = _statusMessage

    private val _isCapturing = MutableStateFlow(false)
    val isCapturing: StateFlow<Boolean> = _isCapturing

    private val _uploadProgress = MutableStateFlow<String?>(null)
    val uploadProgress: StateFlow<String?> = _uploadProgress

    private val _categories = MutableStateFlow<List<UploadManager.Category>>(emptyList())
    val categories: StateFlow<List<UploadManager.Category>> = _categories

    init {
        viewModelScope.launch { _categories.value = uploadManager.fetchCategories() }
    }

    fun setStatusMessage(msg: String) {
        _statusMessage.value = msg
    }

    fun startMeasuring() {
        clearMeasurements()
        _measureState.value = MeasurementState.PLACING_FIRST
        _statusMessage.value = "Tap a surface to place first point"
    }

    fun clearMeasurements() {
        _measurements.value.forEach { m ->
            m.first.anchor.detach()
            m.second?.anchor?.detach()
        }
        _currentMeasurement.value?.let { m ->
            m.first.anchor.detach()
            m.second?.anchor?.detach()
        }
        _measurements.value = emptyList()
        _currentMeasurement.value = null
        _measureState.value = MeasurementState.IDLE
        _statusMessage.value = null
    }

    fun handleTap(hitResult: HitResult, frame: Frame) {

        val anchor = hitResult.createAnchor()
        val pose   = anchor.pose
        val point  = MeasurementPoint(anchor, pose.tx(), pose.ty(), pose.tz())

        when (_measureState.value) {
            MeasurementState.PLACING_FIRST -> {
                _currentMeasurement.value = ActiveMeasurement(first = point)
                _measureState.value = MeasurementState.PLACING_SECOND
                _statusMessage.value = "Tap second point to complete measurement"
            }
            MeasurementState.PLACING_SECOND -> {
                val current = _currentMeasurement.value ?: return
                val completed = current.copy(second = point)
                _measurements.value += completed
                _currentMeasurement.value = null
                // Loop back to place another
                _measureState.value = MeasurementState.PLACING_FIRST
                _statusMessage.value = "${completed.displayString} — tap for next measurement"
            }
            MeasurementState.IDLE -> { /* do nothing */ }
        }
    }

    fun startCapture() {
        if (_isCapturing.value) return
        _statusMessage.value = "Capturing..."
        _isCapturing.value = true
    }

    fun captureFailed() {
        _statusMessage.value = "Capture failed"
        _isCapturing.value = false
    }

    fun savePhoto(bitmap: Bitmap) {
        viewModelScope.launch {
            try {
                val location = locationManager.geocodeOnce()

                val filename = "photo_${SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())}.jpg"
                val dir      = photoStore.imageDir()
                val file     = File(dir, filename)
                FileOutputStream(file).use { bitmap.compress(Bitmap.CompressFormat.JPEG, 90, it) }

                val measurementList = _measurements.value.mapIndexed { i, m ->
                    Measurement(
                        label   = "Measurement ${i + 1}",
                        valueM  = m.distanceM ?: 0f,
                        display = m.displayString ?: "—"
                    )
                }

                val photo = MeasuredPhoto(
                    filename     = filename,
                    localPath    = file.absolutePath,
                    latitude     = location?.latitude,
                    longitude    = location?.longitude,
                    altitude     = location?.altitude,
                    address      = location?.address,
                    measurements = measurementList
                )
                photoStore.save(photo)
                clearMeasurements()
                _statusMessage.value = "Photo saved (${measurementList.size} measurements)"
            } catch (e: Exception) {
                _statusMessage.value = "Capture error: ${e.message}"
            } finally {
                _isCapturing.value = false
            }
        }
    }

    fun uploadPhoto(photo: MeasuredPhoto, categoryId: Int? = null) {
        viewModelScope.launch {
            _uploadProgress.value = "Uploading…"
            when (val result = uploadManager.upload(photo, categoryId)) {
                is UploadResult.Success -> {
                    val updated = photo.copy(serverUrl = result.photoUrl)
                    photoStore.save(updated)
                    _uploadProgress.value = "Uploaded!"
                }
                is UploadResult.Error -> {
                    _uploadProgress.value = "Failed: ${result.message}"
                }
            }
        }
    }

    fun deletePhoto(uuid: String) {
        viewModelScope.launch { photoStore.delete(uuid) }
    }



    override fun onCleared() {
        super.onCleared()
        clearMeasurements()
    }
}
