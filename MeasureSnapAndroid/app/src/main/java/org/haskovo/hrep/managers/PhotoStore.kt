package org.haskovo.hrep.managers

import android.content.Context
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import org.haskovo.hrep.models.MeasuredPhoto
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.withContext
import java.io.File

class PhotoStore(private val context: Context) {

    private val gson = Gson()
    private val metaFile: File get() = File(context.filesDir, "photos.json")
    private val imageDir: File get() = File(context.filesDir, "CapturedImages").also { it.mkdirs() }

    private val _photos = MutableStateFlow<List<MeasuredPhoto>>(emptyList())
    val photos: StateFlow<List<MeasuredPhoto>> = _photos

    init { /* load is async — call load() from coroutine scope */ }

    suspend fun load() = withContext(Dispatchers.IO) {
        val list = if (metaFile.exists()) {
            try {
                val type = object : TypeToken<List<MeasuredPhoto>>() {}.type
                gson.fromJson<List<MeasuredPhoto>>(metaFile.readText(), type) ?: emptyList()
            } catch (e: Exception) { emptyList() }
        } else emptyList()
        _photos.value = list
    }

    suspend fun save(photo: MeasuredPhoto) = withContext(Dispatchers.IO) {
        val updated = listOf(photo) + _photos.value.filter { it.uuid != photo.uuid }
        persist(updated)
        _photos.value = updated
    }

    suspend fun delete(uuid: String) = withContext(Dispatchers.IO) {
        val photo = _photos.value.find { it.uuid == uuid } ?: return@withContext
        File(photo.localPath).takeIf { it.exists() }?.delete()
        val updated = _photos.value.filter { it.uuid != uuid }
        persist(updated)
        _photos.value = updated
    }

    fun imageDir(): File = imageDir

    private fun persist(list: List<MeasuredPhoto>) {
        metaFile.writeText(gson.toJson(list))
    }
}
