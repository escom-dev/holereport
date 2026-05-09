package org.haskovo.hrep.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val DarkColorScheme = darkColorScheme(
    primary         = Color(0xFF4f8ef7),
    onPrimary       = Color.White,
    primaryContainer= Color(0xFF1e3a5f),
    background      = Color(0xFF0f1117),
    surface         = Color(0xFF1a1d27),
    onSurface       = Color(0xFFe2e8f0),
    onBackground    = Color(0xFFe2e8f0),
)

@Composable
fun HoleReportTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = DarkColorScheme, content = content)
}
