package org.haskovo.hrep.models

import java.util.UUID

data class Measurement(
    val label: String,
    val valueM: Float,        // distance in metres
    val display: String       // e.g. "57.1 cm"
)

data class MeasuredPhoto(
    val uuid: String = UUID.randomUUID().toString(),
    val filename: String,
    val localPath: String,    // absolute path on device
    val uploadedAt: Long = System.currentTimeMillis(),
    val photoDate: Long = System.currentTimeMillis(),
    val latitude: Double? = null,
    val longitude: Double? = null,
    val altitude: Double? = null,
    val address: String? = null,
    val measurements: List<Measurement> = emptyList(),
    val serverUrl: String? = null,   // URL after upload
    val status: String = "new",      // new / in_progress / resolved / closed
    val categoryId: Int? = null,
    val categoryName: String? = null
) {
    val measurementCount: Int get() = measurements.size

    val displayLocation: String get() = when {
        address != null -> address
        latitude != null && longitude != null ->
            "%.4f, %.4f".format(latitude, longitude)
        else -> "No location"
    }
}
