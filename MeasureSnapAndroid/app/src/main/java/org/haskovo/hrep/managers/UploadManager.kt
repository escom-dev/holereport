package org.haskovo.hrep.managers

import android.content.Context
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.google.gson.Gson
import org.haskovo.hrep.models.MeasuredPhoto
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.asRequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.TimeUnit
import androidx.datastore.preferences.core.edit
import kotlinx.coroutines.flow.map

val Context.dataStore by preferencesDataStore(name = "settings")

object PrefsKeys {
    val SERVER_URL = stringPreferencesKey("server_url")
    val API_KEY    = stringPreferencesKey("api_key")
    val DEVICE_ID  = stringPreferencesKey("device_id")
}

sealed class UploadResult {
    data class Success(val photoUrl: String) : UploadResult()
    data class Error(val message: String)    : UploadResult()
}

class UploadManager(private val context: Context) {

    companion object {
        const val DEFAULT_SERVER_URL = "https://hrep.haskovo.org"
        const val DEFAULT_API_KEY    = "api-key"
    }

    private val client = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .writeTimeout(120, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .build()

    private val gson = Gson()
    private val isoFmt = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US)

    suspend fun getServerUrl(): String =
        context.dataStore.data.map { it[PrefsKeys.SERVER_URL] ?: DEFAULT_SERVER_URL }.first()

    suspend fun getApiKey(): String =
        context.dataStore.data.map { it[PrefsKeys.API_KEY] ?: DEFAULT_API_KEY }.first()

    suspend fun getDeviceId(): String {
        val existing = context.dataStore.data.map { it[PrefsKeys.DEVICE_ID] ?: "" }.first()
        if (existing.isNotBlank()) return existing
        val newId = java.util.UUID.randomUUID().toString()
        context.dataStore.edit { it[PrefsKeys.DEVICE_ID] = newId }
        return newId
    }

    suspend fun saveSettings(serverUrl: String, apiKey: String) {
        context.dataStore.edit { prefs ->
            prefs[PrefsKeys.SERVER_URL] = serverUrl.trimEnd('/')
            prefs[PrefsKeys.API_KEY]    = apiKey
        }
    }

    data class Category(
        val id: Int,
        val slug: String,
        val name: String,
        @com.google.gson.annotations.SerializedName("name_en") val nameEn: String,
        val color: String
    )

    suspend fun fetchCategories(): List<Category> = withContext(Dispatchers.IO) {
        val serverUrl = getServerUrl()
        if (serverUrl.isBlank()) return@withContext emptyList()
        try {
            val req  = Request.Builder().url("$serverUrl/api/categories.php").build()
            val resp = client.newCall(req).execute()
            val body = resp.body?.string() ?: return@withContext emptyList()
            @Suppress("UNCHECKED_CAST")
            val map  = gson.fromJson(body, Map::class.java) as? Map<String, Any>
            val list = map?.get("categories") as? List<*> ?: return@withContext emptyList()
            list.mapNotNull { item ->
                if (item is Map<*, *>) {
                    val id    = (item["id"] as? Double)?.toInt() ?: return@mapNotNull null
                    Category(
                        id     = id,
                        slug   = item["slug"]    as? String ?: "",
                        name   = item["name"]    as? String ?: "",
                        nameEn = item["name_en"] as? String ?: "",
                        color  = item["color"]   as? String ?: "#3b82f6"
                    )
                } else null
            }
        } catch (e: Exception) { emptyList() }
    }

    sealed class CreateUserResult {
        data class Success(val action: String, val userType: String) : CreateUserResult()
        data class Error(val message: String) : CreateUserResult()
    }

    suspend fun createUser(email: String, password: String, userType: String): CreateUserResult =
        withContext(Dispatchers.IO) {
            val serverUrl = getServerUrl()
            val apiKey    = getApiKey()
            val deviceId  = getDeviceId()
            if (serverUrl.isBlank()) return@withContext CreateUserResult.Error("Server URL not configured")
            if (apiKey.isBlank())    return@withContext CreateUserResult.Error("API key not configured")

            try {
                val payload = gson.toJson(mapOf(
                    "email"     to email,
                    "password"  to password,
                    "user_type" to userType,
                    "device_id" to deviceId
                ))
                val body = payload.toRequestBody("application/json".toMediaType())
                val req = Request.Builder()
                    .url("$serverUrl/api/create_user.php")
                    .addHeader("X-API-Key", apiKey)
                    .post(body)
                    .build()

                val resp    = client.newCall(req).execute()
                val bodyStr = resp.body?.string() ?: ""
                @Suppress("UNCHECKED_CAST")
                val map = gson.fromJson(bodyStr, Map::class.java) as? Map<String, Any>

                if (map?.get("ok") == true) {
                    CreateUserResult.Success(
                        action = map["action"] as? String ?: "created",
                        userType = map["user_type"] as? String ?: userType
                    )
                } else {
                    CreateUserResult.Error(
                        map?.get("error") as? String ?: "Server error ${resp.code}"
                    )
                }
            } catch (e: Exception) {
                CreateUserResult.Error("Network error: ${e.message}")
            }
        }

    suspend fun testConnection(): String = withContext(Dispatchers.IO) {
        val url = getServerUrl()
        if (url.isBlank()) return@withContext "Server URL not configured"
        try {
            val req = Request.Builder().url("$url/api/list.php?limit=1").build()
            val resp = client.newCall(req).execute()
            if (resp.isSuccessful) "Connected! (HTTP ${resp.code})" else "HTTP ${resp.code}"
        } catch (e: Exception) { "Connection failed: ${e.message}" }
    }

    suspend fun upload(photo: MeasuredPhoto, categoryId: Int? = null): UploadResult = withContext(Dispatchers.IO) {
        val serverUrl = getServerUrl()
        val apiKey    = getApiKey()
        val deviceId  = getDeviceId()
        if (serverUrl.isBlank()) return@withContext UploadResult.Error("Server URL not configured")
        if (apiKey.isBlank())    return@withContext UploadResult.Error("API key not configured")

        val file = File(photo.localPath)
        if (!file.exists()) return@withContext UploadResult.Error("Image file not found")

        try {
            val measJson = gson.toJson(photo.measurements.map { m ->
                mapOf("label" to m.label, "value_m" to m.valueM, "display" to m.display)
            })

            val body = MultipartBody.Builder().setType(MultipartBody.FORM)
                .addFormDataPart("photo", file.name, file.asRequestBody("image/jpeg".toMediaType()))
                .addFormDataPart("device_id", deviceId)
                .addFormDataPart("measurements", measJson)
                .apply {
                    photo.latitude?.let  { addFormDataPart("latitude",  it.toString()) }
                    photo.longitude?.let { addFormDataPart("longitude", it.toString()) }
                    photo.altitude?.let  { addFormDataPart("altitude",  it.toString()) }
                    photo.address?.let   { addFormDataPart("address",   it) }
                    addFormDataPart("photo_date", isoFmt.format(Date(photo.photoDate)))
                    categoryId?.let      { addFormDataPart("category_id", it.toString()) }
                }
                .build()

            val req = Request.Builder()
                .url("$serverUrl/api/upload.php")
                .addHeader("X-API-Key", apiKey)
                .post(body)
                .build()

            val resp = client.newCall(req).execute()
            val bodyStr = resp.body?.string() ?: ""

            if (resp.isSuccessful) {
                @Suppress("UNCHECKED_CAST")
                val map = gson.fromJson(bodyStr, Map::class.java) as? Map<String, Any>
                val url = map?.get("photo_url") as? String ?: "$serverUrl/uploads/${file.name}"
                UploadResult.Success(url)
            } else {
                UploadResult.Error("Server error ${resp.code}: $bodyStr")
            }
        } catch (e: Exception) {
            UploadResult.Error("Upload failed: ${e.message}")
        }
    }
}
