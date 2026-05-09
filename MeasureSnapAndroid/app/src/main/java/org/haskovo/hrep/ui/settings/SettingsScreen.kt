package org.haskovo.hrep.ui.settings

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import org.haskovo.hrep.managers.UploadManager
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(uploadManager: UploadManager) {
    val scope = rememberCoroutineScope()

    var serverUrl by remember { mutableStateOf("") }
    var apiKey    by remember { mutableStateOf("") }
    var showKey   by remember { mutableStateOf(false) }
    var testResult by remember { mutableStateOf<String?>(null) }
    var isTesting  by remember { mutableStateOf(false) }

    // Create User state
    var newEmail      by remember { mutableStateOf("") }
    var newPassword   by remember { mutableStateOf("") }
    var showPassword  by remember { mutableStateOf(false) }
    var newUserType   by remember { mutableStateOf("user") }
    var userTypeExpanded by remember { mutableStateOf(false) }
    var isCreating    by remember { mutableStateOf(false) }
    var createResult  by remember { mutableStateOf<String?>(null) }
    var createIsError by remember { mutableStateOf(false) }

    // Load saved values
    LaunchedEffect(Unit) {
        serverUrl = uploadManager.getServerUrl()
        apiKey    = uploadManager.getApiKey()
    }

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Text("Settings", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)

        Card {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text("Server Configuration", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)

                OutlinedTextField(
                    value = serverUrl,
                    onValueChange = { serverUrl = it; testResult = null },
                    label = { Text("Server URL") },
                    placeholder = { Text("http://192.168.1.x") },
                    modifier = Modifier.fillMaxWidth(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri, imeAction = ImeAction.Next),
                    singleLine = true
                )

                OutlinedTextField(
                    value = apiKey,
                    onValueChange = { apiKey = it; testResult = null },
                    label = { Text("API Key") },
                    modifier = Modifier.fillMaxWidth(),
                    visualTransformation = if (showKey) VisualTransformation.None else PasswordVisualTransformation(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password, imeAction = ImeAction.Done),
                    trailingIcon = {
                        TextButton(onClick = { showKey = !showKey }) {
                            Text(if (showKey) "Hide" else "Show")
                        }
                    },
                    singleLine = true
                )

                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(
                        modifier = Modifier.weight(1f),
                        onClick = {
                            scope.launch { uploadManager.saveSettings(serverUrl.trim(), apiKey.trim()) }
                        }
                    ) { Text("Save") }

                    OutlinedButton(
                        modifier = Modifier.weight(1f),
                        enabled = !isTesting,
                        onClick = {
                            scope.launch {
                                uploadManager.saveSettings(serverUrl.trim(), apiKey.trim())
                                isTesting = true
                                testResult = uploadManager.testConnection()
                                isTesting = false
                            }
                        }
                    ) { Text(if (isTesting) "Testing…" else "Test Connection") }
                }

                testResult?.let { result ->
                    Surface(
                        shape = MaterialTheme.shapes.small,
                        color = if (result.startsWith("Connected"))
                            MaterialTheme.colorScheme.primaryContainer
                        else MaterialTheme.colorScheme.errorContainer
                    ) {
                        Text(result,
                            modifier = Modifier.fillMaxWidth().padding(10.dp),
                            color = if (result.startsWith("Connected"))
                                MaterialTheme.colorScheme.onPrimaryContainer
                            else MaterialTheme.colorScheme.onErrorContainer,
                            style = MaterialTheme.typography.bodySmall)
                    }
                }
            }
        }

        // ── Create User card ──────────────────────────────────────────────────
        Card {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text("Create User", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)

                OutlinedTextField(
                    value = newEmail,
                    onValueChange = { newEmail = it; createResult = null },
                    label = { Text("Email") },
                    placeholder = { Text("user@example.com") },
                    modifier = Modifier.fillMaxWidth(),
                    keyboardOptions = KeyboardOptions(
                        keyboardType = KeyboardType.Email,
                        imeAction = ImeAction.Next
                    ),
                    singleLine = true
                )

                OutlinedTextField(
                    value = newPassword,
                    onValueChange = { newPassword = it; createResult = null },
                    label = { Text("Password") },
                    modifier = Modifier.fillMaxWidth(),
                    visualTransformation = if (showPassword) VisualTransformation.None else PasswordVisualTransformation(),
                    keyboardOptions = KeyboardOptions(
                        keyboardType = KeyboardType.Password,
                        imeAction = ImeAction.Done
                    ),
                    trailingIcon = {
                        TextButton(onClick = { showPassword = !showPassword }) {
                            Text(if (showPassword) "Hide" else "Show")
                        }
                    },
                    singleLine = true
                )

                // User type dropdown
                ExposedDropdownMenuBox(
                    expanded = userTypeExpanded,
                    onExpandedChange = { userTypeExpanded = it }
                ) {
                    OutlinedTextField(
                        value = newUserType,
                        onValueChange = {},
                        readOnly = true,
                        label = { Text("User Type") },
                        trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = userTypeExpanded) },
                        modifier = Modifier.fillMaxWidth().menuAnchor()
                    )
                    ExposedDropdownMenu(
                        expanded = userTypeExpanded,
                        onDismissRequest = { userTypeExpanded = false }
                    ) {
                        listOf("user").forEach { type -> // , "admin", "cityadmin", "superadmin"
                            DropdownMenuItem(
                                text = { Text(type) },
                                onClick = { newUserType = type; userTypeExpanded = false }
                            )
                        }
                    }
                }

                Button(
                    modifier = Modifier.fillMaxWidth(),
                    enabled = !isCreating && newEmail.isNotBlank() && newPassword.isNotBlank(),
                    onClick = {
                        scope.launch {
                            isCreating = true
                            createResult = null
                            val result = uploadManager.createUser(
                                email    = newEmail.trim(),
                                password = newPassword,
                                userType = newUserType
                            )
                            when (result) {
                                is UploadManager.CreateUserResult.Success -> {
                                    val verb = if (result.action == "updated") "Updated" else "Created"
                                    createResult  = "$verb ✓ (${result.userType})"
                                    createIsError = false
                                    newEmail    = ""
                                    newPassword = ""
                                    newUserType = "user"
                                }
                                is UploadManager.CreateUserResult.Error -> {
                                    createResult  = result.message
                                    createIsError = true
                                }
                            }
                            isCreating = false
                        }
                    }
                ) {
                    Text(if (isCreating) "Creating…" else "Create User")
                }

                createResult?.let { msg ->
                    Surface(
                        shape = MaterialTheme.shapes.small,
                        color = if (createIsError) MaterialTheme.colorScheme.errorContainer
                                else MaterialTheme.colorScheme.primaryContainer
                    ) {
                        Text(
                            msg,
                            modifier = Modifier.fillMaxWidth().padding(10.dp),
                            color = if (createIsError) MaterialTheme.colorScheme.onErrorContainer
                                    else MaterialTheme.colorScheme.onPrimaryContainer,
                            style = MaterialTheme.typography.bodySmall
                        )
                    }
                }
            }
        }

        Card {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("About", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                Text("Hole Report Android", style = MaterialTheme.typography.bodyMedium)
                Text("ARCore-based AR measurement app", style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text("Requires: Android 8.0+, ARCore-compatible device",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}
