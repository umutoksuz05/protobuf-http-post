import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case environments = "Environments"
    case importExport = "Import/Export"
    
    var id: String { rawValue }
}

struct WorkspaceSettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @AppStorage("appAppearance") private var appearance: String = "system"
    
    @State private var selectedTab: SettingsTab = .general
    @State private var baseUrl: String = ""
    @State private var authToken: String = ""
    @State private var basicAuthUsername: String = ""
    @State private var basicAuthPassword: String = ""
    
    // Environment editing
    @State private var selectedEnvironmentId: UUID?
    @State private var showNewEnvironmentSheet = false
    @State private var newEnvironmentName = ""
    
    // Import/Export
    @State private var showExportSuccess = false
    @State private var showImportPicker = false
    @State private var importExportError: String?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Workspace Settings")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button("Done") {
                    saveAndDismiss()
                }
                .buttonStyle(AccentButtonStyle())
                .keyboardShortcut(.return)
            }
            .padding()
            .background(Theme.windowBackground)
            
            Divider()
            
            // Tab selector
            Picker("", selection: $selectedTab) {
                ForEach(SettingsTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            
            Divider()
            
            // Tab content
            switch selectedTab {
            case .general:
                generalSettingsView
            case .environments:
                environmentsView
            case .importExport:
                importExportView
            }
        }
        .frame(width: 550, height: 450)
        .onAppear {
            loadSettings()
        }
        .sheet(isPresented: $showNewEnvironmentSheet) {
            NewEnvironmentSheet(name: $newEnvironmentName) {
                createEnvironment()
            } onCancel: {
                newEnvironmentName = ""
                showNewEnvironmentSheet = false
            }
        }
        .fileImporter(
            isPresented: $showImportPicker,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
    }
    
    // MARK: - General Settings
    
    private var generalSettingsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Appearance
                VStack(alignment: .leading, spacing: 8) {
                    Text("Appearance")
                        .font(.system(size: 13, weight: .semibold))
                    
                    Picker("Theme", selection: $appearance) {
                        Label("System", systemImage: "circle.lefthalf.filled").tag("system")
                        Label("Light", systemImage: "sun.max.fill").tag("light")
                        Label("Dark", systemImage: "moon.fill").tag("dark")
                    }
                    .pickerStyle(.segmented)
                }
                
                Divider()
                
                // Default Request Settings
                VStack(alignment: .leading, spacing: 16) {
                    Text("Default Request Settings")
                        .font(.system(size: 13, weight: .semibold))
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Base URL")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Theme.textSecondary)
                        TextField("https://api.example.com", text: $baseUrl)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                        Text("Available as {{baseUrl}} or {{base_url}} in requests")
                            .font(.caption)
                            .foregroundColor(Theme.textTertiary)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Authorization Token")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Theme.textSecondary)
                        TextEditor(text: $authToken)
                            .font(.system(size: 12, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .padding(6)
                            .frame(minHeight: 50, maxHeight: 80)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(Theme.border, lineWidth: 1)
                                    .background(RoundedRectangle(cornerRadius: 5).fill(Theme.surface))
                            )
                        Text("Available as {{authToken}} or {{auth_token}} in requests. Use the sync button on request headers to apply.")
                            .font(.caption)
                            .foregroundColor(Theme.textTertiary)
                    }
                }
                
                Divider()
                
                // Basic Auth
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Text("Basic Authentication")
                            .font(.system(size: 13, weight: .semibold))
                        
                        if !basicAuthUsername.isEmpty && !basicAuthPassword.isEmpty {
                            Text("Configured")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(Theme.success)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.success.opacity(0.12))
                                .cornerRadius(4)
                        }
                    }
                    
                    Text("When enabled on a request, a Basic auth header will be generated from these credentials.")
                        .font(.caption)
                        .foregroundColor(Theme.textTertiary)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Username")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Theme.textSecondary)
                        TextField("username", text: $basicAuthUsername)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Password")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Theme.textSecondary)
                        TextField("password", text: $basicAuthPassword)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                    }
                    
                    Text("Available as {{basicAuthUsername}} and {{basicAuthPassword}} in requests")
                        .font(.caption)
                        .foregroundColor(Theme.textTertiary)
                }
            }
            .padding(20)
        }
    }
    
    // MARK: - Environments View
    
    private var environmentsView: some View {
        HSplitView {
            // Environment list
            VStack(spacing: 0) {
                HStack {
                    Text("Environments")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Theme.textTertiary)
                    Spacer()
                    Button(action: { showNewEnvironmentSheet = true }) {
                        Image(systemName: "plus")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.borderless)
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
                
                Divider()
                
                List(selection: $selectedEnvironmentId) {
                    if let workspace = appState.selectedWorkspace {
                        ForEach(workspace.environments) { env in
                            HStack {
                                if workspace.selectedEnvironmentId == env.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(Theme.success)
                                        .font(.system(size: 12))
                                } else {
                                    Image(systemName: "circle")
                                        .foregroundColor(.secondary)
                                        .font(.system(size: 12))
                                }
                                Text(env.name)
                                Spacer()
                                Text("\(env.variables.count) vars")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .tag(env.id)
                            .contextMenu {
                                Button("Set as Active") {
                                    appState.selectEnvironment(env)
                                }
                                if env.id != WorkspaceEnvironment.defaultEnvironmentId {
                                    Divider()
                                    Button("Delete", role: .destructive) {
                                        appState.deleteEnvironment(env)
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
            .frame(minWidth: 150, idealWidth: 180)
            
            // Environment editor
            VStack(spacing: 0) {
                if let envId = selectedEnvironmentId,
                   let workspace = appState.selectedWorkspace,
                   let env = workspace.environments.first(where: { $0.id == envId }) {
                    EnvironmentEditorView(environment: env) { updated in
                        appState.updateEnvironment(updated)
                    }
                } else {
                    VStack {
                        Spacer()
                        Text("Select an environment to edit")
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
            }
            .frame(minWidth: 300)
        }
    }
    
    // MARK: - Import/Export View
    
    private var importExportView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            // Export section
            VStack(spacing: 12) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 36))
                    .foregroundColor(Theme.info)
                
                Text("Export Workspace")
                    .font(.headline)
                
                Text("Save your workspace configuration (requests, groups, environments) to a JSON file.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
                
                Button("Export to File...") {
                    exportWorkspace()
                }
                .buttonStyle(.borderedProminent)
            }
            
            Divider()
                .padding(.vertical)
            
            // Import section
            VStack(spacing: 12) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 36))
                    .foregroundColor(Theme.success)
                
                Text("Import Workspace")
                    .font(.headline)
                
                Text("Import a workspace from a JSON file. Proto files will need to be re-added manually.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
                
                Button("Import from File...") {
                    showImportPicker = true
                }
                .buttonStyle(.bordered)
            }
            
            if let error = importExportError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding()
            }
            
            if showExportSuccess {
                Text("Workspace exported successfully!")
                    .font(.caption)
                    .foregroundColor(Theme.success)
                    .padding()
            }
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Actions
    
    private func loadSettings() {
        guard let workspace = appState.selectedWorkspace else { return }
        baseUrl = workspace.settings.baseUrl
        authToken = workspace.settings.authToken
        basicAuthUsername = workspace.settings.basicAuthUsername
        basicAuthPassword = workspace.settings.basicAuthPassword
        selectedEnvironmentId = workspace.environments.first?.id
    }
    
    private func saveAndDismiss() {
        let settings = WorkspaceSettings(
            baseUrl: baseUrl.trimmingCharacters(in: .whitespaces),
            authToken: authToken.trimmingCharacters(in: .whitespacesAndNewlines),
            basicAuthUsername: basicAuthUsername.trimmingCharacters(in: .whitespaces),
            basicAuthPassword: basicAuthPassword.trimmingCharacters(in: .whitespaces)
        )
        appState.updateWorkspaceSettings(settings)
        dismiss()
    }
    
    private func createEnvironment() {
        let name = newEnvironmentName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        appState.createEnvironment(name: name)
        newEnvironmentName = ""
        showNewEnvironmentSheet = false
    }
    
    private func exportWorkspace() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(appState.selectedWorkspace?.name ?? "workspace").json"
        panel.title = "Export Workspace"
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    try appState.exportWorkspace(to: url)
                    showExportSuccess = true
                    importExportError = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        showExportSuccess = false
                    }
                } catch {
                    importExportError = error.localizedDescription
                }
            }
        }
    }
    
    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                try appState.importWorkspace(from: url)
                importExportError = nil
                dismiss()
            } catch {
                importExportError = error.localizedDescription
            }
        case .failure(let error):
            importExportError = error.localizedDescription
        }
    }
}

// MARK: - Environment Editor

struct EnvironmentEditorView: View {
    let environment: WorkspaceEnvironment
    let onSave: (WorkspaceEnvironment) -> Void
    
    @State private var name: String = ""
    @State private var variables: [EnvironmentVariable] = []
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                TextField("Environment Name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
                
                Spacer()
                
                Button("Save") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // Variables header
            HStack {
                Text("Variables")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: addVariable) {
                    Image(systemName: "plus")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            // Variables list
            List {
                ForEach(Array(variables.enumerated()), id: \.element.id) { index, variable in
                    HStack(spacing: 8) {
                        Toggle("", isOn: Binding(
                            get: { variables[index].enabled },
                            set: { variables[index].enabled = $0 }
                        ))
                        .labelsHidden()
                        .scaleEffect(0.8)
                        
                        TextField("Key", text: Binding(
                            get: { variables[index].key },
                            set: { variables[index].key = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 80)
                        
                        TextField("Value", text: Binding(
                            get: { variables[index].value },
                            set: { variables[index].value = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        
                        Button(action: { removeVariable(at: index) }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            .listStyle(.plain)
            
            // Usage hint
            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(Theme.textTertiary)
                Text("Use {{key}} in URL, headers, or body to reference variables")
                    .font(.caption)
                    .foregroundColor(Theme.textTertiary)
            }
            .padding()
        }
        .onAppear {
            name = environment.name
            variables = environment.variables
        }
        .onChange(of: environment.id) { _, _ in
            name = environment.name
            variables = environment.variables
        }
    }
    
    private func addVariable() {
        variables.append(EnvironmentVariable(key: "", value: ""))
    }
    
    private func removeVariable(at index: Int) {
        guard index < variables.count else { return }
        variables.remove(at: index)
    }
    
    private func save() {
        var updated = environment
        updated.name = name.trimmingCharacters(in: .whitespaces)
        updated.variables = variables.filter { !$0.key.isEmpty }
        onSave(updated)
    }
}

// MARK: - New Environment Sheet

struct NewEnvironmentSheet: View {
    @Binding var name: String
    let onSave: () -> Void
    let onCancel: () -> Void
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(spacing: 16) {
            Text("New Environment")
                .font(.headline)
            
            TextField("Environment Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit {
                    if !name.trimmingCharacters(in: .whitespaces).isEmpty {
                        onSave()
                    }
                }
            
            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create", action: onSave)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 280)
        .onAppear { isFocused = true }
    }
}

#Preview {
    WorkspaceSettingsView()
        .environmentObject(AppState())
}
