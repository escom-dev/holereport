import SwiftUI

struct SettingsView: View {
    @ObservedObject private var languageManager = LanguageManager.shared

    @State private var testResult: TestResult?
    @State private var isTesting = false

    // Create User form
    @State private var newEmail    = ""
    @State private var newPassword = ""
    @State private var newUserType = "user"
    @State private var isCreating  = false
    @State private var createResult: CreateResult?

    enum TestResult   { case success(String), failure(String) }
    enum CreateResult { case success(String), failure(String) }

    private let userTypes = ["user"]  //, "admin", "cityadmin", "superadmin"
    
    var body: some View {
        NavigationStack {
            Form {
                // ── Language ──────────────────────────────────────────────────
                Section {
                    Picker(selection: Binding(
                        get: { languageManager.currentLanguage },
                        set: { languageManager.select($0) }
                    )) {
                        ForEach(languageManager.supported, id: \.code) { lang in
                            Text(lang.displayName).tag(lang.code)
                        }
                    } label: {
                        Label(loc("Language"), systemImage: "globe")
                    }
                    .pickerStyle(.segmented)
                }

                // ── Server config ─────────────────────────────────────────────
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(loc("Server URL"), systemImage: "server.rack")
                            .font(.caption).foregroundColor(.secondary)
                        Text(UploadManager.serverURL)
                            .font(.system(.body, design: .monospaced))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Label(loc("API Key"), systemImage: "key.fill")
                            .font(.caption).foregroundColor(.secondary)
                        Text(String(repeating: "•", count: UploadManager.apiKey.count))
                            .font(.system(.body, design: .monospaced))
                    }
                } header: {
                    Text(loc("Server Configuration"))
                } footer: {
                    Text(loc("Server URL and API key are built into the app."))
                }

                // ── Connection test ───────────────────────────────────────────
                Section {
                    Button { testConnection() } label: {
                        HStack {
                            if isTesting { ProgressView().scaleEffect(0.8) }
                            else { Image(systemName: "antenna.radiowaves.left.and.right") }
                            Text(loc(isTesting ? "Testing…" : "Test Connection"))
                        }
                    }
                    .disabled(isTesting)

                    if let result = testResult {
                        switch result {
                        case .success(let msg):
                            Label(msg, systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green).font(.footnote)
                        case .failure(let msg):
                            Label(msg, systemImage: "xmark.circle.fill")
                                .foregroundColor(.red).font(.footnote)
                        }
                    }
                } header: { Text(loc("Connection")) }

                // ── Create User ───────────────────────────────────────────────
                Section {
                    HStack {
                        Image(systemName: "envelope")
                            .foregroundColor(.secondary).frame(width: 20)
                        TextField(loc("Email"), text: $newEmail)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                    }

                    HStack {
                        Image(systemName: "lock")
                            .foregroundColor(.secondary).frame(width: 20)
                        SecureField(loc("Password"), text: $newPassword)
                    }

                    Picker(loc("User Type"), selection: $newUserType) {
                        ForEach(userTypes, id: \.self) { type in
                            Text(type).tag(type)
                        }
                    }

                    Button {
                        createUser()
                    } label: {
                        HStack {
                            if isCreating { ProgressView().scaleEffect(0.8) }
                            else { Image(systemName: "person.badge.plus") }
                            Text(loc(isCreating ? "Creating…" : "Create User"))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(isCreating || newEmail.isEmpty || newPassword.isEmpty)
                    .buttonStyle(.borderedProminent)

                    if let result = createResult {
                        switch result {
                        case .success(let msg):
                            Label(msg, systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green).font(.footnote)
                        case .failure(let msg):
                            Label(msg, systemImage: "xmark.circle.fill")
                                .foregroundColor(.red).font(.footnote)
                        }
                    }
                } header: {
                    Text(loc("Create User"))
                } footer: {
                    Text(loc("Creates a web login account in the server database."))
                }
            }
            .navigationTitle(loc("Settings"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // ── Test connection ────────────────────────────────────────────────────────
    private func testConnection() {
        isTesting = true
        testResult = nil
        guard let url = URL(string: "\(UploadManager.serverURL)/api/list.php?limit=1") else {
            testResult = .failure(NSLocalizedString("Invalid URL", comment: "")); isTesting = false; return
        }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue(UploadManager.apiKey, forHTTPHeaderField: "X-API-Key")
        URLSession.shared.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                isTesting = false
                if let error = error { testResult = .failure(error.localizedDescription); return }
                if let http = response as? HTTPURLResponse {
                    if http.statusCode == 200 {
                        if let data = data,
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let total = json["total"] as? Int {
                            testResult = .success(String(format: NSLocalizedString("Connected! %d photo(s) on server.", comment: ""), total))
                        } else {
                            testResult = .success(NSLocalizedString("Connected to server ✓", comment: ""))
                        }
                    } else {
                        testResult = .failure(String(format: NSLocalizedString("HTTP %d — check server", comment: ""), http.statusCode))
                    }
                }
            }
        }.resume()
    }

    // ── Create user ────────────────────────────────────────────────────────────
    private func createUser() {
        isCreating   = true
        createResult = nil

        guard let url = URL(string: "\(UploadManager.serverURL)/api/create_user.php") else {
            createResult = .failure(NSLocalizedString("Invalid server URL", comment: "")); isCreating = false; return
        }

        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/json",  forHTTPHeaderField: "Content-Type")
        req.setValue(UploadManager.apiKey, forHTTPHeaderField: "X-API-Key")

        let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? ""
        let payload: [String: String] = [
            "email":     newEmail.trimmingCharacters(in: .whitespaces),
            "password":  newPassword,
            "user_type": newUserType,
            "device_id": deviceId
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        URLSession.shared.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                isCreating = false
                if let error = error {
                    createResult = .failure(error.localizedDescription); return
                }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    createResult = .failure(NSLocalizedString("Invalid server response", comment: "")); return
                }
                if let errMsg = json["error"] as? String {
                    createResult = .failure(errMsg)
                } else if json["ok"] as? Bool == true {
                    let type   = json["user_type"] as? String ?? newUserType
                    let action = json["action"]    as? String ?? "created"
                    let key    = action == "updated" ? "Updated ✓ (%@)" : "Created ✓ (%@)"
                    createResult = .success(String(format: NSLocalizedString(key, comment: ""), type))
                    newEmail    = ""
                    newPassword = ""
                    newUserType = "user"
                } else {
                    createResult = .failure(NSLocalizedString("Unexpected response", comment: ""))
                }
            }
        }.resume()
    }
}
