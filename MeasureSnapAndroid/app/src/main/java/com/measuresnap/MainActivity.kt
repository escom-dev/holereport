package com.measuresnap

import android.os.Bundle
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.Collections
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.measuresnap.managers.LocationManager
import com.measuresnap.managers.PhotoStore
import com.measuresnap.managers.UploadManager
import com.measuresnap.ui.camera.CameraScreen
import com.measuresnap.ui.gallery.GalleryScreen
import com.measuresnap.ui.settings.SettingsScreen
import com.measuresnap.ui.theme.MeasureSnapTheme
import com.measuresnap.viewmodels.CameraViewModel

sealed class Screen(val route: String, val label: String, val icon: ImageVector) {
    object Camera  : Screen("camera",   "Camera",   Icons.Default.CameraAlt)
    object Gallery : Screen("gallery",  "Gallery",  Icons.Default.Collections)
    object Settings: Screen("settings", "Settings", Icons.Default.Settings)
}

class MainActivity : ComponentActivity() {

    private lateinit var locationManager: LocationManager
    private lateinit var photoStore: PhotoStore
    private lateinit var uploadManager: UploadManager

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        locationManager = LocationManager(this)
        photoStore      = PhotoStore(this)
        uploadManager   = UploadManager(this)

        // Ensure stable device ID in DataStore
        val androidId = Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID)
        // Saved asynchronously in UploadManager preference if needed

        setContent {
            MeasureSnapTheme {
                MeasureSnapApp(locationManager, photoStore, uploadManager)
            }
        }
    }

    override fun onResume()  { super.onResume();  locationManager.startUpdates() }
    override fun onPause()   { super.onPause();   locationManager.stopUpdates()  }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MeasureSnapApp(
    locationManager: LocationManager,
    photoStore: PhotoStore,
    uploadManager: UploadManager
) {
    val navController = rememberNavController()
    val items = listOf(Screen.Camera, Screen.Gallery, Screen.Settings)

    val viewModel: CameraViewModel = viewModel(
        factory = object : androidx.lifecycle.ViewModelProvider.Factory {
            @Suppress("UNCHECKED_CAST")
            override fun <T : androidx.lifecycle.ViewModel> create(modelClass: Class<T>): T =
                CameraViewModel(photoStore, uploadManager, locationManager) as T
        }
    )

    Scaffold(
        bottomBar = {
            NavigationBar {
                val backstackEntry by navController.currentBackStackEntryAsState()
                val currentRoute = backstackEntry?.destination?.route
                items.forEach { screen ->
                    NavigationBarItem(
                        selected = currentRoute == screen.route,
                        onClick  = {
                            navController.navigate(screen.route) {
                                popUpTo(navController.graph.findStartDestination().id) { saveState = true }
                                launchSingleTop = true; restoreState = true
                            }
                        },
                        icon  = { Icon(screen.icon, contentDescription = screen.label) },
                        label = { Text(screen.label) }
                    )
                }
            }
        }
    ) { innerPadding ->
        NavHost(
            navController = navController,
            startDestination = Screen.Camera.route,
            modifier = Modifier.padding(innerPadding)
        ) {
            composable(Screen.Camera.route)   { CameraScreen(viewModel) }
            composable(Screen.Gallery.route)  { GalleryScreen(viewModel, photoStore) }
            composable(Screen.Settings.route) { SettingsScreen(uploadManager) }
        }
    }
}
