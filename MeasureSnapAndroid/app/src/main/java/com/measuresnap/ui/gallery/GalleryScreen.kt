package com.measuresnap.ui.gallery

import androidx.compose.foundation.clickable
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CloudUpload
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import coil.request.ImageRequest
import com.measuresnap.managers.PhotoStore
import com.measuresnap.managers.UploadManager
import com.measuresnap.models.MeasuredPhoto
import com.measuresnap.viewmodels.CameraViewModel
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@Composable
fun GalleryScreen(viewModel: CameraViewModel, photoStore: PhotoStore) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val photos by photoStore.photos.collectAsState()
    val uploadProgress by viewModel.uploadProgress.collectAsState()
    val categories by viewModel.categories.collectAsState()
    var selectedPhoto by remember { mutableStateOf<MeasuredPhoto?>(null) }

    LaunchedEffect(Unit) { photoStore.load() }

    Column(Modifier.fillMaxSize()) {
        // Header
        Surface(shadowElevation = 4.dp) {
            Row(
                Modifier.fillMaxWidth().padding(16.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text("Gallery", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                Spacer(Modifier.weight(1f))
                Text("${photos.size} photos", style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }

        uploadProgress?.let { msg ->
            Surface(color = MaterialTheme.colorScheme.primaryContainer) {
                Text(msg, modifier = Modifier.fillMaxWidth().padding(12.dp),
                    color = MaterialTheme.colorScheme.onPrimaryContainer)
            }
        }

        if (photos.isEmpty()) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text("No photos yet.\nCapture using the Camera tab.",
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        } else {
            LazyVerticalGrid(
                columns = GridCells.Fixed(2),
                contentPadding = PaddingValues(8.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier.fillMaxSize()
            ) {
                items(photos, key = { it.uuid }) { photo ->
                    PhotoCard(photo = photo, onClick = { selectedPhoto = photo })
                }
            }
        }
    }

    // Detail dialog
    selectedPhoto?.let { photo ->
        PhotoDetailDialog(
            photo      = photo,
            categories = categories,
            onDismiss  = { selectedPhoto = null },
            onUpload   = { p, catId -> viewModel.uploadPhoto(p, catId); selectedPhoto = null },
            onDelete   = {
                viewModel.deletePhoto(photo.uuid)
                selectedPhoto = null
            }
        )
    }
}

@Composable
fun PhotoCard(photo: MeasuredPhoto, onClick: () -> Unit) {
    Card(
        modifier = Modifier.fillMaxWidth().aspectRatio(1f).clickable(onClick = onClick),
        shape = RoundedCornerShape(8.dp)
    ) {
        Box {
            AsyncImage(
                model = ImageRequest.Builder(LocalContext.current)
                    .data(File(photo.localPath)).crossfade(true).build(),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize()
            )
            if (photo.measurementCount > 0) {
                Surface(
                    modifier = Modifier.align(Alignment.BottomEnd).padding(6.dp),
                    shape = RoundedCornerShape(4.dp),
                    color = MaterialTheme.colorScheme.primary.copy(alpha = 0.85f)
                ) {
                    Text("📐 ${photo.measurementCount}",
                        fontSize = 11.sp, modifier = Modifier.padding(4.dp),
                        color = MaterialTheme.colorScheme.onPrimary)
                }
            }
        }
    }
}

@Composable
fun PhotoDetailDialog(
    photo: MeasuredPhoto,
    categories: List<UploadManager.Category>,
    onDismiss: () -> Unit,
    onUpload: (MeasuredPhoto, Int?) -> Unit,
    onDelete: () -> Unit
) {
    val dateFmt = SimpleDateFormat("dd MMM yyyy HH:mm", Locale.getDefault())
    var selectedCategoryId by remember { mutableStateOf<Int?>(null) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(photo.displayLocation, maxLines = 2) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Date: ${dateFmt.format(Date(photo.photoDate))}", fontSize = 13.sp)
                photo.address?.let { Text("Address: $it", fontSize = 13.sp) }
                if (photo.latitude != null)
                    Text("GPS: %.5f, %.5f".format(photo.latitude, photo.longitude), fontSize = 12.sp)
                if (photo.measurements.isNotEmpty()) {
                    Divider()
                    Text("Measurements", fontWeight = FontWeight.Bold, fontSize = 13.sp)
                    photo.measurements.forEach { m ->
                        Text("${m.label}: ${m.display}", fontSize = 12.sp)
                    }
                }
                if (photo.serverUrl != null) {
                    Divider()
                    Text("Uploaded ✓", color = MaterialTheme.colorScheme.primary, fontSize = 12.sp)
                }
                // Category picker (only when not yet uploaded)
                if (photo.serverUrl == null && categories.isNotEmpty()) {
                    Divider()
                    Text("Category", fontWeight = FontWeight.Bold, fontSize = 13.sp)
                    Row(
                        Modifier.horizontalScroll(rememberScrollState()),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        // "None" chip
                        CategoryChip(
                            label = "None",
                            color = Color.Gray,
                            isSelected = selectedCategoryId == null,
                            onClick = { selectedCategoryId = null }
                        )
                        categories.forEach { cat ->
                            CategoryChip(
                                label = cat.nameEn.ifBlank { cat.name },
                                color = parseHexColor(cat.color),
                                isSelected = selectedCategoryId == cat.id,
                                onClick = { selectedCategoryId = cat.id }
                            )
                        }
                    }
                }
            }
        },
        confirmButton = {
            if (photo.serverUrl == null) {
                Button(onClick = { onUpload(photo, selectedCategoryId) }) {
                    Icon(Icons.Default.CloudUpload, contentDescription = null)
                    Spacer(Modifier.width(4.dp))
                    Text("Upload")
                }
            }
        },
        dismissButton = {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(onClick = onDelete) {
                    Icon(Icons.Default.Delete, contentDescription = null)
                    Spacer(Modifier.width(4.dp))
                    Text("Delete")
                }
                TextButton(onClick = onDismiss) { Text("Close") }
            }
        }
    )
}

@Composable
private fun CategoryChip(label: String, color: Color, isSelected: Boolean, onClick: () -> Unit) {
    val bg     = if (isSelected) color.copy(alpha = 0.25f) else Color.Transparent
    val border = if (isSelected) color else Color.Gray.copy(alpha = 0.4f)
    Surface(
        shape = RoundedCornerShape(50),
        color = bg,
        border = androidx.compose.foundation.BorderStroke(1.dp, border),
        modifier = Modifier.clickable(onClick = onClick)
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 5.dp)
        ) {
            Box(Modifier.size(8.dp).background(color, CircleShape))
            Spacer(Modifier.width(5.dp))
            Text(label, fontSize = 12.sp, fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Normal)
        }
    }
}

private fun parseHexColor(hex: String): Color {
    return try {
        val h = hex.trimStart('#')
        val v = h.toLong(16)
        if (h.length == 6) Color(0xFF000000 or v) else Color(v)
    } catch (e: Exception) { Color(0xFF3b82f6) }
}
