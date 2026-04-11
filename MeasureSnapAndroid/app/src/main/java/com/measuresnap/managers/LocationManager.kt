package com.measuresnap.managers

import android.annotation.SuppressLint
import android.content.Context
import android.location.Address
import android.location.Geocoder
import android.os.Build
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume
import kotlin.math.asin
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

data class LocationData(
    val latitude: Double,
    val longitude: Double,
    val altitude: Double,
    val address: String? = null
)

class LocationManager(private val context: Context) {

    private val fusedClient: FusedLocationProviderClient =
        LocationServices.getFusedLocationProviderClient(context)

    private val _location = MutableStateFlow<LocationData?>(null)
    val location: StateFlow<LocationData?> = _location

    private var lastGeocodedLat = Double.NaN
    private var lastGeocodedLng = Double.NaN
    private var lastGeocodeTime = 0L

    private val locationCallback = object : LocationCallback() {
        override fun onLocationResult(result: LocationResult) {
            val loc = result.lastLocation ?: return
            val lat = loc.latitude
            val lng = loc.longitude
            val alt = loc.altitude

            // Throttle geocoding: only re-geocode after 50m movement or 60s
            val dist = if (!lastGeocodedLat.isNaN()) haversineMetres(lat, lng, lastGeocodedLat, lastGeocodedLng) else Double.MAX_VALUE
            val elapsed = System.currentTimeMillis() - lastGeocodeTime
            if (dist > 50 || elapsed > 60_000) {
                lastGeocodedLat = lat; lastGeocodedLng = lng; lastGeocodeTime = System.currentTimeMillis()
                reverseGeocode(lat, lng) { addr ->
                    _location.value = LocationData(lat, lng, alt, addr)
                }
            } else {
                _location.value = _location.value?.copy(latitude = lat, longitude = lng, altitude = alt)
                    ?: LocationData(lat, lng, alt)
            }
        }
    }

    @SuppressLint("MissingPermission")
    fun startUpdates() {
        val req = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 5_000L)
            .setMinUpdateIntervalMillis(2_000L)
            .build()
        fusedClient.requestLocationUpdates(req, locationCallback, null)
    }

    fun stopUpdates() {
        fusedClient.removeLocationUpdates(locationCallback)
    }

    /** One-shot geocode at capture moment */
    @SuppressLint("MissingPermission")
    suspend fun geocodeOnce(): LocationData? = suspendCancellableCoroutine { cont ->
        fusedClient.lastLocation.addOnSuccessListener { loc ->
            if (loc == null) { cont.resume(null); return@addOnSuccessListener }
            val lat = loc.latitude; val lng = loc.longitude; val alt = loc.altitude
            reverseGeocode(lat, lng) { addr ->
                cont.resume(LocationData(lat, lng, alt, addr))
            }
        }.addOnFailureListener { cont.resume(null) }
    }

    private fun reverseGeocode(lat: Double, lng: Double, callback: (String?) -> Unit) {
        val geocoder = Geocoder(context)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            geocoder.getFromLocation(lat, lng, 1) { addresses ->
                callback(addresses.firstOrNull()?.toDisplayString())
            }
        } else {
            @Suppress("DEPRECATION")
            val addresses = try { geocoder.getFromLocation(lat, lng, 1) } catch (e: Exception) { null }
            callback(addresses?.firstOrNull()?.toDisplayString())
        }
    }

    private fun Address.toDisplayString(): String {
        val parts = mutableListOf<String>()
        if (thoroughfare != null) parts += thoroughfare + (if (subThoroughfare != null) " $subThoroughfare" else "")
        if (locality != null) parts += locality
        if (countryName != null) parts += countryName
        return parts.joinToString(", ")
    }

    private fun haversineMetres(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
        val R = 6_371_000.0
        val dLat = Math.toRadians(lat2 - lat1)
        val dLon = Math.toRadians(lon2 - lon1)
        val a = sin(dLat / 2).let { it * it } +
                cos(Math.toRadians(lat1)) * cos(Math.toRadians(lat2)) *
                sin(dLon / 2).let { it * it }
        return R * 2 * asin(sqrt(a))
    }
}
