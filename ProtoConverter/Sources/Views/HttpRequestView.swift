import SwiftUI
import AppKit

enum HttpMethod: String, CaseIterable, Identifiable {
    case GET, POST, PUT, PATCH, DELETE
    var id: String { rawValue }
}

enum BodyFormat: String, CaseIterable, Identifiable {
    case json = "JSON"
    case protobuf = "Protobuf"
    var id: String { rawValue }
}

enum ScriptTab: String, CaseIterable, Identifiable {
    case preRequest = "Pre-Request"
    case postResponse = "Post-Response"
    var id: String { rawValue }
}

enum HeadersSubTab: String, CaseIterable, Identifiable {
    case headers = "Headers"
    case authorization = "Authorization"
    var id: String { rawValue }
}

enum AuthType: String, CaseIterable, Identifiable {
    case none = "No Auth"
    case bearer = "JWT Token"
    case basic = "Basic Auth"
    var id: String { rawValue }
    
    var rawKey: String {
        switch self {
        case .none: return "none"
        case .bearer: return "bearer"
        case .basic: return "basic"
        }
    }
    
    init(from raw: String) {
        switch raw {
        case "bearer": self = .bearer
        case "basic": self = .basic
        default: self = .none
        }
    }
}

struct HttpRequestView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var tabState: RequestTabState
    var onRequestSaved: ((SavedRequest) -> Void)?
    
    @State private var showSaveSheet = false
    @State private var saveRequestName: String = ""
    @State private var selectedGroupId: UUID = RequestGroup.defaultGroupId
    @State private var showScripts = false
    @State private var selectedScriptTab: ScriptTab = .preRequest
    @State private var showScriptingGuide = false
    @State private var selectedHeadersSubTab: HeadersSubTab = .headers
    
    private let conversionService = ConversionService()
    private let scriptingService = ScriptingService()
    
    // Computed properties for format enums
    private var requestFormat: BodyFormat {
        get { tabState.requestFormat == "protobuf" ? .protobuf : .json }
    }
    
    private var responseFormat: BodyFormat {
        get { tabState.responseFormat == "protobuf" ? .protobuf : .json }
    }
    
    private var method: HttpMethod {
        get { HttpMethod(rawValue: tabState.method) ?? .POST }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // URL Bar
            urlBar
            
            Divider()
            
            // Main content
            HSplitView {
                // Request side
                requestPanel
                    .frame(minWidth: 350)
                
                // Response side
                responsePanel
                    .frame(minWidth: 350)
            }
        }
        .onAppear {
            initializeFromState()
        }
        .sheet(isPresented: $showSaveSheet) {
            SaveRequestSheet(
                name: $saveRequestName,
                selectedGroupId: $selectedGroupId,
                onSave: saveAsNewRequest,
                onCancel: { showSaveSheet = false }
            )
            .environmentObject(appState)
        }
        .sheet(isPresented: $showScriptingGuide) {
            ScriptingGuideView()
        }
    }
    
    private func initializeFromState() {
        if let saved = tabState.savedRequest {
            saveRequestName = saved.name
            selectedGroupId = saved.groupId
        }
    }
    
    // MARK: - URL Bar
    
    private var urlBar: some View {
        HStack(spacing: 10) {
            Picker("", selection: Binding(
                get: { method },
                set: { newMethod in
                    tabState.method = newMethod.rawValue
                    tabState.markAsChanged()
                }
            )) {
                ForEach(HttpMethod.allCases) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .frame(width: 100)
            
            VariableTextField(
                text: Binding(
                    get: { tabState.url },
                    set: { newUrl in
                        tabState.url = newUrl
                        tabState.markAsChanged()
                    }
                ),
                placeholder: "Enter URL or use {{variables}}",
                font: .system(size: 13, design: .monospaced)
            )
            
            Button(action: sendRequest) {
                if tabState.isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 60)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 10))
                        Text("Send")
                    }
                    .frame(width: 60)
                }
            }
            .buttonStyle(AccentButtonStyle())
            .disabled(tabState.isLoading || tabState.url.isEmpty)
            .keyboardShortcut(.return, modifiers: [.command])
            
            Divider()
                .frame(height: 20)
            
            saveButtons
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.surface.opacity(0.6))
    }
    
    @ViewBuilder
    private var saveButtons: some View {
        if tabState.savedRequest == nil {
            Button("Save") {
                saveRequestName = ""
                showSaveSheet = true
            }
            .buttonStyle(HoverButtonStyle())
        } else {
            if tabState.hasUnsavedChanges {
                Button(action: resaveRequest) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10))
                        Text("Resave")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.warning)
                }
                .buttonStyle(HoverButtonStyle())
                .transition(.scale.combined(with: .opacity))
            }
            
            Button("Save As") {
                saveRequestName = (tabState.savedRequest?.name ?? "") + " Copy"
                showSaveSheet = true
            }
            .buttonStyle(HoverButtonStyle())
        }
    }
    
    // MARK: - Request Panel
    
    private var requestPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with format selector
            HStack {
                Text("Request")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                
                HStack(spacing: 4) {
                    Text("Format:")
                        .font(.caption)
                        .foregroundColor(Theme.textTertiary)
                    Picker("", selection: Binding(
                        get: { requestFormat },
                        set: { newFormat in
                            tabState.requestFormat = newFormat == .protobuf ? "protobuf" : "json"
                            tabState.markAsChanged()
                        }
                    )) {
                        ForEach(BodyFormat.allCases) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                    .frame(width: 100)
                }
            }
            .panelHeader()
            
            Divider()
            
            // Proto type selector (only for protobuf format)
            if requestFormat == .protobuf {
                protoTypeSelector(
                    title: "Request Message Type",
                    selection: Binding(
                        get: {
                            if let name = tabState.selectedRequestTypeName {
                                return appState.messageTypes.first { $0.fullName == name }
                            }
                            return nil
                        },
                        set: { newType in
                            tabState.selectedRequestTypeName = newType?.fullName
                            tabState.markAsChanged()
                        }
                    )
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
                Divider()
            }
            
            // Headers / Authorization section
            headersAndAuthSection
            
            Divider()
            
            // Body section
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Body")
                        .font(.system(size: 12, weight: .medium))
                    
                    Spacer()
                    
                    // Generate Example button
                    if requestFormat == .protobuf,
                       let typeName = tabState.selectedRequestTypeName,
                       appState.messageTypes.first(where: { $0.fullName == typeName }) != nil {
                        Button(action: generateExampleBody) {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 10))
                                Text("Generate")
                                    .font(.system(size: 11))
                            }
                        }
                        .buttonStyle(HoverButtonStyle())
                        .help("Generate example JSON from proto definition")
                    }
                    
                    // Scripts toggle button
                    Button(action: {
                        withAnimation(Theme.smooth) {
                            showScripts.toggle()
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left.forwardslash.chevron.right")
                                .font(.system(size: 10))
                            Text("Scripts")
                                .font(.system(size: 11))
                            if hasAnyScript {
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 6, height: 6)
                            }
                        }
                        .foregroundColor(showScripts ? Color.accentColor : Theme.textSecondary)
                    }
                    .buttonStyle(HoverButtonStyle())
                    .help("Toggle scripting panel")
                }
                .panelHeader()
                
                if showScripts {
                    scriptingPanel
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else {
                    SmartJsonEditor(
                        text: Binding(
                            get: { tabState.requestBody },
                            set: { newBody in
                                tabState.requestBody = newBody
                                tabState.markAsChanged()
                            }
                        ),
                        placeholder: requestFormat == .json ? "Enter JSON body..." : "Enter JSON (will be converted to protobuf)...",
                        isEditable: true
                    )
                }
            }
        }
        .background(Theme.surface.opacity(0.3))
        .animation(Theme.smooth, value: requestFormat == .protobuf)
        .animation(Theme.smooth, value: showScripts)
    }
    
    private var hasAnyScript: Bool {
        !tabState.preRequestScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !tabState.postResponseScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    // MARK: - Scripting Panel
    
    private var scriptingPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Picker("", selection: $selectedScriptTab) {
                    ForEach(ScriptTab.allCases) { tab in
                        let hasScript = tab == .preRequest
                            ? !tabState.preRequestScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            : !tabState.postResponseScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        if hasScript {
                            Text("\(tab.rawValue) *").tag(tab)
                        } else {
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
                
                Spacer()
                
                Button(action: { showScriptingGuide = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "book")
                            .font(.system(size: 10))
                        Text("Guide")
                            .font(.system(size: 11))
                    }
                }
                .buttonStyle(HoverButtonStyle())
                .help("Open Scripting Guide")
                
                Button(action: {
                    withAnimation(Theme.smooth) {
                        showScripts = false
                    }
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Theme.textTertiary)
                }
                .buttonStyle(ToolbarIconButtonStyle())
                .help("Close scripting panel")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Theme.surface.opacity(0.6))
            
            Divider()
            
            Group {
                if selectedScriptTab == .preRequest {
                    MacTextEditor(
                        text: Binding(
                            get: { tabState.preRequestScript },
                            set: { newScript in
                                tabState.preRequestScript = newScript
                                tabState.markAsChanged()
                            }
                        ),
                        placeholder: "// Pre-request script (JavaScript)\n// Runs before the request is sent\n//\n// Example:\n// pp.request.headers.add(\"X-Timestamp\", Date.now().toString());\n// pp.request.body = JSON.stringify({...JSON.parse(pp.request.body), ts: Date.now()});"
                    )
                } else {
                    MacTextEditor(
                        text: Binding(
                            get: { tabState.postResponseScript },
                            set: { newScript in
                                tabState.postResponseScript = newScript
                                tabState.markAsChanged()
                            }
                        ),
                        placeholder: "// Post-response script (JavaScript)\n// Runs after response is received\n//\n// Example:\n// const data = pp.response.json();\n// pp.workspace.setAuthToken(data.token);\n// pp.env.set(\"userId\", String(data.user.id));"
                    )
                }
            }
        }
    }
    
    private func generateExampleBody() {
        guard let typeName = tabState.selectedRequestTypeName,
              let messageType = appState.messageTypes.first(where: { $0.fullName == typeName }) else {
            return
        }
        
        let example = conversionService.generateExampleJson(for: messageType, allMessageTypes: appState.messageTypes)
        tabState.requestBody = example
        tabState.markAsChanged()
    }
    
    // MARK: - Response Panel
    
    private var responsePanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Response")
                    .font(.system(size: 13, weight: .semibold))
                
                if !tabState.responseStatus.isEmpty {
                    Text(tabState.responseStatus)
                        .statusBadge(color: Theme.statusColor(for: tabState.responseStatus))
                }
                
                if let time = tabState.responseTime {
                    Text(formatResponseTime(time))
                        .statusBadge(color: Theme.info)
                }
                
                Spacer()
                
                HStack(spacing: 4) {
                    Text("Format:")
                        .font(.caption)
                        .foregroundColor(Theme.textTertiary)
                    Picker("", selection: Binding(
                        get: { responseFormat },
                        set: { newFormat in
                            tabState.responseFormat = newFormat == .protobuf ? "protobuf" : "json"
                            tabState.markAsChanged()
                        }
                    )) {
                        ForEach(BodyFormat.allCases) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                    .frame(width: 100)
                }
            }
            .panelHeader()
            
            Divider()
            
            if responseFormat == .protobuf {
                protoTypeSelector(
                    title: "Response Message Type",
                    selection: Binding(
                        get: {
                            if let name = tabState.selectedResponseTypeName {
                                return appState.messageTypes.first { $0.fullName == name }
                            }
                            return nil
                        },
                        set: { newType in
                            tabState.selectedResponseTypeName = newType?.fullName
                            tabState.markAsChanged()
                        }
                    )
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
                Divider()
            }
            
            if let error = tabState.errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(Theme.error)
                        .font(.system(size: 12))
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.error)
                    Spacer()
                    Button("Dismiss") {
                        withAnimation(Theme.smooth) {
                            tabState.errorMessage = nil
                        }
                    }
                    .font(.caption)
                    .buttonStyle(HoverButtonStyle())
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.error.opacity(0.08))
                .transition(.opacity.combined(with: .move(edge: .top)))
                
                Divider()
            }
            
            if !tabState.responseHeaders.isEmpty {
                DisclosureGroup("Headers") {
                    ScrollView {
                        Text(tabState.responseHeaders)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .frame(maxHeight: 100)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .transition(.opacity)
                
                Divider()
            }
            
            if !tabState.scriptConsoleOutput.isEmpty {
                DisclosureGroup("Console") {
                    ScrollView {
                        Text(tabState.scriptConsoleOutput)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(Theme.jsonString)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .frame(maxHeight: 120)
                    .background(Color.black.opacity(0.03))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .transition(.opacity)
                
                Divider()
            }
            
            VStack(alignment: .leading, spacing: 0) {
                Text("Body")
                    .font(.system(size: 12, weight: .medium))
                    .panelHeader()
                
                SmartJsonEditor(
                    text: .constant(tabState.responseBody),
                    placeholder: "Response will appear here...",
                    isEditable: false
                )
            }
        }
        .background(Theme.surface.opacity(0.4))
        .animation(Theme.smooth, value: tabState.errorMessage != nil)
        .animation(Theme.smooth, value: responseFormat == .protobuf)
        .animation(Theme.smooth, value: tabState.responseHeaders.isEmpty)
        .animation(Theme.smooth, value: tabState.scriptConsoleOutput.isEmpty)
    }
    
    // MARK: - Proto Type Selector
    
    private func protoTypeSelector(title: String, selection: Binding<MessageTypeInfo?>) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundColor(Theme.textTertiary)
            
            Picker("", selection: selection) {
                Text("Select type...").tag(nil as MessageTypeInfo?)
                ForEach(groupedMessageTypes.keys.sorted(), id: \.self) { package in
                    Section(header: Text(package.isEmpty ? "No Package" : package)) {
                        ForEach(groupedMessageTypes[package] ?? []) { type in
                            Text(type.fullName).tag(type as MessageTypeInfo?)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.surface.opacity(0.5))
    }
    
    private var groupedMessageTypes: [String: [MessageTypeInfo]] {
        Dictionary(grouping: appState.messageTypes) { type in
            let components = type.fullName.components(separatedBy: ".")
            return components.count > 1 ? components.dropLast().joined(separator: ".") : ""
        }
    }
    
    // MARK: - Headers & Authorization Section
    
    private var headersAndAuthSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Tab bar: Headers | Authorization
            HStack {
                Picker("", selection: $selectedHeadersSubTab) {
                    ForEach(HeadersSubTab.allCases) { tab in
                        if tab == .authorization && tabState.authType != "none" {
                            Text("\(tab.rawValue) *").tag(tab)
                        } else {
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
                
                Spacer()
                
                if selectedHeadersSubTab == .headers {
                    // Sync auth token button
                    if let workspace = appState.selectedWorkspace,
                       !workspace.settings.authToken.isEmpty {
                        Button(action: syncAuthToken) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(ToolbarIconButtonStyle())
                        .help("Sync Authorization token from workspace settings")
                    }
                    
                    Button(action: addHeader) {
                        Image(systemName: "plus")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(ToolbarIconButtonStyle())
                }
            }
            .panelHeader()
            
            // Content
            if selectedHeadersSubTab == .headers {
                headersListView
            } else {
                authorizationView
            }
        }
        .animation(Theme.quick, value: selectedHeadersSubTab)
    }
    
    // MARK: - Headers List
    
    private var headersListView: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(tabState.headers) { header in
                    if let index = tabState.headers.firstIndex(where: { $0.id == header.id }) {
                        HeaderRow(
                            header: Binding(
                                get: {
                                    guard index < tabState.headers.count,
                                          tabState.headers[index].id == header.id else {
                                        return header
                                    }
                                    return tabState.headers[index]
                                },
                                set: { newValue in
                                    if let currentIndex = tabState.headers.firstIndex(where: { $0.id == header.id }) {
                                        tabState.headers[currentIndex] = newValue
                                        tabState.markAsChanged()
                                        // If the Authorization header was edited, sync to auth tab
                                        if newValue.key.lowercased() == "authorization" {
                                            tabState.syncHeadersToAuth()
                                        }
                                    }
                                }
                            ),
                            onRemove: {
                                if let currentIndex = tabState.headers.firstIndex(where: { $0.id == header.id }) {
                                    let wasAuth = tabState.headers[currentIndex].key.lowercased() == "authorization"
                                    removeHeader(at: currentIndex)
                                    if wasAuth {
                                        tabState.isSyncingAuth = true
                                        tabState.authType = "none"
                                        tabState.authBearerToken = ""
                                        tabState.authBasicUsername = ""
                                        tabState.authBasicPassword = ""
                                        tabState.isSyncingAuth = false
                                    }
                                }
                            }
                        )
                    }
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
        }
        .frame(maxHeight: 120)
    }
    
    // MARK: - Authorization View
    
    private var authorizationView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Auth type picker
            HStack {
                Text("Type")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
                
                Picker("", selection: Binding(
                    get: { AuthType(from: tabState.authType) },
                    set: { newType in
                        tabState.authType = newType.rawKey
                        
                        // Pre-fill basic auth from workspace defaults
                        if newType == .basic {
                            if tabState.authBasicUsername.isEmpty,
                               let workspace = appState.selectedWorkspace,
                               !workspace.settings.basicAuthUsername.isEmpty {
                                tabState.authBasicUsername = "{{basicAuthUsername}}"
                                tabState.authBasicPassword = "{{basicAuthPassword}}"
                            }
                        }
                        
                        tabState.syncAuthToHeaders()
                        tabState.markAsChanged()
                    }
                )) {
                    ForEach(AuthType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .frame(maxWidth: 160)
            }
            
            // Auth type content
            switch AuthType(from: tabState.authType) {
            case .none:
                HStack(spacing: 8) {
                    Image(systemName: "lock.open")
                        .foregroundColor(Theme.textTertiary)
                        .font(.system(size: 14))
                    Text("No authorization will be sent with this request.")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textTertiary)
                }
                
            case .bearer:
                VStack(alignment: .leading, spacing: 6) {
                    Text("Token")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.textSecondary)
                    
                    TextEditor(text: Binding(
                        get: { tabState.authBearerToken },
                        set: { newVal in
                            tabState.authBearerToken = newVal
                            tabState.syncAuthToHeaders()
                            tabState.markAsChanged()
                        }
                    ))
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(minHeight: 40, maxHeight: 60)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Theme.border, lineWidth: 1)
                            .background(RoundedRectangle(cornerRadius: 5).fill(Theme.surface))
                    )
                    
                    Text("The token will be sent as the Authorization header value")
                        .font(.caption)
                        .foregroundColor(Theme.textTertiary)
                }
                
            case .basic:
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Username")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Theme.textSecondary)
                        VariableTextField(
                            text: Binding(
                                get: { tabState.authBasicUsername },
                                set: { newVal in
                                    tabState.authBasicUsername = newVal
                                    tabState.syncAuthToHeaders()
                                    tabState.markAsChanged()
                                }
                            ),
                            placeholder: "username or {{basicAuthUsername}}"
                        )
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Password")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Theme.textSecondary)
                        VariableTextField(
                            text: Binding(
                                get: { tabState.authBasicPassword },
                                set: { newVal in
                                    tabState.authBasicPassword = newVal
                                    tabState.syncAuthToHeaders()
                                    tabState.markAsChanged()
                                }
                            ),
                            placeholder: "password or {{basicAuthPassword}}"
                        )
                    }
                    
                    Text("Credentials are Base64 encoded and sent as Basic Authorization header. Use {{basicAuthUsername}} / {{basicAuthPassword}} to reference workspace settings.")
                        .font(.caption)
                        .foregroundColor(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .frame(maxHeight: 160)
    }
    
    // MARK: - Helpers
    
    private func formatResponseTime(_ time: TimeInterval) -> String {
        if time < 1 {
            return String(format: "%.0f ms", time * 1000)
        } else {
            return String(format: "%.2f s", time)
        }
    }
    
    private func addHeader() {
        withAnimation(Theme.quick) {
            tabState.headers.append(TabHeader(key: "", value: ""))
            tabState.markAsChanged()
        }
    }
    
    private func removeHeader(at index: Int) {
        guard index < tabState.headers.count else { return }
        withAnimation(Theme.quick) {
            tabState.headers.remove(at: index)
            tabState.markAsChanged()
        }
    }
    
    private func syncAuthToken() {
        guard let workspace = appState.selectedWorkspace,
              !workspace.settings.authToken.isEmpty else { return }
        tabState.authType = "bearer"
        tabState.authBearerToken = workspace.settings.authToken
        tabState.syncAuthToHeaders()
        tabState.markAsChanged()
    }
    
    // MARK: - Send Request (with scripting)
    
    private func sendRequest() {
        guard !tabState.url.isEmpty else { return }
        
        tabState.isLoading = true
        tabState.errorMessage = nil
        tabState.responseBody = ""
        tabState.responseStatus = ""
        tabState.responseHeaders = ""
        tabState.responseTime = nil
        tabState.scriptConsoleOutput = ""
        
        Task {
            do {
                let result = try await performRequest()
                await MainActor.run {
                    withAnimation(Theme.smooth) {
                        tabState.responseBody = result.body
                        tabState.responseStatus = result.status
                        tabState.responseHeaders = result.headers
                        tabState.responseTime = result.time
                        tabState.scriptConsoleOutput = result.consoleOutput
                        tabState.isLoading = false
                    }
                    
                    applyScriptResults(result.scriptResult)
                }
            } catch {
                await MainActor.run {
                    withAnimation(Theme.smooth) {
                        tabState.errorMessage = error.localizedDescription
                        tabState.isLoading = false
                    }
                }
            }
        }
    }
    
    private struct RequestResult {
        let body: String
        let status: String
        let headers: String
        let time: TimeInterval
        let consoleOutput: String
        let scriptResult: ScriptResult?
    }
    
    private func performRequest() async throws -> RequestResult {
        let variables = appState.selectedWorkspace?.allVariables() ?? [:]
        
        var resolvedUrl = VariableService.substitute(tabState.url, variables: variables)
        var resolvedHeaders: [(key: String, value: String)] = tabState.headers
            .filter { $0.enabled && !$0.key.isEmpty }
            .map { (key: VariableService.substitute($0.key, variables: variables),
                     value: VariableService.substitute($0.value, variables: variables)) }
        var resolvedBody = VariableService.substitute(tabState.requestBody, variables: variables)
        
        var allConsoleOutput: [String] = []
        
        // For Basic Auth with variables: resolve username/password and re-encode
        if tabState.authType == "basic" {
            let resolvedUser = VariableService.substitute(tabState.authBasicUsername, variables: variables)
            let resolvedPass = VariableService.substitute(tabState.authBasicPassword, variables: variables)
            if !resolvedUser.isEmpty || !resolvedPass.isEmpty {
                let credentials = "\(resolvedUser):\(resolvedPass)"
                if let credData = credentials.data(using: .utf8) {
                    let basicValue = "Basic \(credData.base64EncodedString())"
                    // Replace the Authorization header in resolved headers
                    if let idx = resolvedHeaders.firstIndex(where: { $0.key.lowercased() == "authorization" }) {
                        resolvedHeaders[idx] = (key: "Authorization", value: basicValue)
                    } else {
                        resolvedHeaders.append((key: "Authorization", value: basicValue))
                    }
                }
            }
        }
        
        // --- Run pre-request script ---
        let preScript = tabState.preRequestScript
        if !preScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let scriptContext = ScriptContext(
                url: resolvedUrl,
                method: tabState.method,
                headers: resolvedHeaders,
                body: resolvedBody
            )
            
            let preResult = scriptingService.runPreRequestScript(preScript, context: scriptContext, variables: variables)
            allConsoleOutput.append(contentsOf: preResult.consoleOutput)
            
            if let err = preResult.error {
                allConsoleOutput.append("[Script Error] \(err)")
            }
            
            if let modUrl = preResult.modifiedUrl { resolvedUrl = modUrl }
            if let modHeaders = preResult.modifiedHeaders { resolvedHeaders = modHeaders }
            if let modBody = preResult.modifiedBody { resolvedBody = modBody }
        }
        
        // Build URLRequest
        guard let url = URL(string: resolvedUrl) else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = tabState.method
        
        for header in resolvedHeaders {
            request.setValue(header.value, forHTTPHeaderField: header.key)
        }
        
        // Prepare body
        if tabState.method != "GET" && !resolvedBody.isEmpty {
            if requestFormat == .protobuf {
                guard let typeName = tabState.selectedRequestTypeName,
                      let messageType = appState.messageTypes.first(where: { $0.fullName == typeName }) else {
                    throw RequestError.noMessageTypeSelected("request")
                }
                
                let binaryData = try conversionService.convert(
                    input: resolvedBody,
                    from: .json,
                    to: .binaryBase64,
                    messageType: messageType,
                    allMessageTypes: appState.messageTypes
                )
                
                guard let data = Data(base64Encoded: binaryData) else {
                    throw RequestError.invalidResponse
                }
                
                request.httpBody = data
                request.setValue("application/x-protobuf", forHTTPHeaderField: "Content-Type")
            } else {
                request.httpBody = resolvedBody.data(using: .utf8)
            }
        }
        
        // Execute request
        let startTime = Date()
        let (data, response) = try await URLSession.shared.data(for: request)
        let elapsed = Date().timeIntervalSince(startTime)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RequestError.invalidResponse
        }
        
        let status = "\(httpResponse.statusCode) \(HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))"
        
        var headersStr = ""
        var responseHeadersDict: [String: String] = [:]
        for (key, value) in httpResponse.allHeaderFields {
            let k = "\(key)"
            let v = "\(value)"
            headersStr += "\(k): \(v)\n"
            responseHeadersDict[k] = v
        }
        
        var bodyStr: String
        
        if responseFormat == .protobuf && (200..<400).contains(httpResponse.statusCode) {
            guard let typeName = tabState.selectedResponseTypeName,
                  let messageType = appState.messageTypes.first(where: { $0.fullName == typeName }) else {
                throw RequestError.noMessageTypeSelected("response")
            }
            
            let base64Data = data.base64EncodedString()
            bodyStr = try conversionService.convert(
                input: base64Data,
                from: .binaryBase64,
                to: .json,
                messageType: messageType,
                allMessageTypes: appState.messageTypes
            )
        } else {
            bodyStr = String(data: data, encoding: .utf8) ?? data.base64EncodedString()
            
            if let jsonData = bodyStr.data(using: .utf8),
               let jsonObject = try? JSONSerialization.jsonObject(with: jsonData),
               let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys]),
               let prettyStr = String(data: prettyData, encoding: .utf8) {
                bodyStr = prettyStr
            }
        }
        
        // --- Run post-response script ---
        var postResult: ScriptResult?
        let postScript = tabState.postResponseScript
        if !postScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let scriptContext = ScriptContext(
                url: resolvedUrl,
                method: tabState.method,
                headers: resolvedHeaders,
                body: resolvedBody,
                responseCode: httpResponse.statusCode,
                responseStatus: status,
                responseBody: bodyStr,
                responseHeaders: responseHeadersDict,
                responseTimeMs: elapsed * 1000
            )
            
            let result = scriptingService.runPostResponseScript(postScript, context: scriptContext, variables: variables)
            allConsoleOutput.append(contentsOf: result.consoleOutput)
            
            if let err = result.error {
                allConsoleOutput.append("[Script Error] \(err)")
            }
            
            postResult = result
        }
        
        let consoleText = allConsoleOutput.isEmpty ? "" : allConsoleOutput.joined(separator: "\n")
        
        return RequestResult(
            body: bodyStr,
            status: status,
            headers: headersStr,
            time: elapsed,
            consoleOutput: consoleText,
            scriptResult: postResult
        )
    }
    
    // MARK: - Apply Script Results
    
    private func applyScriptResults(_ result: ScriptResult?) {
        guard let result = result else { return }
        
        for (key, value) in result.environmentUpdates {
            if let value = value {
                appState.setEnvironmentVariable(key: key, value: value)
            } else {
                appState.unsetEnvironmentVariable(key: key)
            }
        }
        
        if let token = result.workspaceAuthToken {
            appState.updateWorkspaceAuthToken(token)
        }
        if let baseUrl = result.workspaceBaseUrl {
            appState.updateWorkspaceBaseUrl(baseUrl)
        }
    }
    
    // MARK: - Save Functions
    
    private func createSavedRequest(name: String, groupId: UUID) -> SavedRequest {
        SavedRequest(
            id: tabState.savedRequest?.id ?? UUID(),
            name: name,
            url: tabState.url,
            method: tabState.method,
            headers: tabState.headers.map { SavedHeader(key: $0.key, value: $0.value, enabled: $0.enabled) },
            requestBody: tabState.requestBody,
            requestFormat: tabState.requestFormat,
            responseFormat: tabState.responseFormat,
            requestMessageType: tabState.selectedRequestTypeName,
            responseMessageType: tabState.selectedResponseTypeName,
            groupId: groupId,
            authType: tabState.authType,
            authBearerToken: tabState.authBearerToken,
            authBasicUsername: tabState.authBasicUsername,
            authBasicPassword: tabState.authBasicPassword,
            preRequestScript: tabState.preRequestScript,
            postResponseScript: tabState.postResponseScript
        )
    }
    
    private func resaveRequest() {
        guard let saved = tabState.savedRequest else { return }
        let updated = createSavedRequest(name: saved.name, groupId: saved.groupId)
        appState.saveRequest(updated)
        tabState.markAsSaved(with: updated)
        onRequestSaved?(updated)
    }
    
    private func saveAsNewRequest(name: String, groupId: UUID) {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        
        let newRequest = SavedRequest(
            id: UUID(),
            name: trimmedName,
            url: tabState.url,
            method: tabState.method,
            headers: tabState.headers.map { SavedHeader(key: $0.key, value: $0.value, enabled: $0.enabled) },
            requestBody: tabState.requestBody,
            requestFormat: tabState.requestFormat,
            responseFormat: tabState.responseFormat,
            requestMessageType: tabState.selectedRequestTypeName,
            responseMessageType: tabState.selectedResponseTypeName,
            groupId: groupId,
            authType: tabState.authType,
            authBearerToken: tabState.authBearerToken,
            authBasicUsername: tabState.authBasicUsername,
            authBasicPassword: tabState.authBasicPassword,
            preRequestScript: tabState.preRequestScript,
            postResponseScript: tabState.postResponseScript
        )
        
        if let group = appState.selectedWorkspace?.requestGroups.first(where: { $0.id == groupId }) {
            appState.saveRequest(newRequest, inGroup: group)
        } else {
            appState.saveRequest(newRequest)
        }
        
        showSaveSheet = false
        tabState.markAsSaved(with: newRequest)
        onRequestSaved?(newRequest)
    }
}

// MARK: - Header Row

struct HeaderRow: View {
    @EnvironmentObject var appState: AppState
    @Binding var header: TabHeader
    let onRemove: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: $header.enabled)
                .labelsHidden()
                .scaleEffect(0.8)
            
            TextField("Key", text: $header.key)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
                .frame(minWidth: 100)
            
            VariableTextField(
                text: $header.value,
                placeholder: "Value"
            )
            
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(isHovering ? Theme.error : Theme.textTertiary)
            }
            .buttonStyle(.plain)
            .opacity(isHovering ? 1 : 0.5)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovering ? Theme.surfaceHover : Color.clear)
        )
        .onHover { h in
            withAnimation(Theme.quick) { isHovering = h }
        }
    }
}

// MARK: - Save Request Sheet

struct SaveRequestSheet: View {
    @EnvironmentObject var appState: AppState
    @Binding var name: String
    @Binding var selectedGroupId: UUID
    let onSave: (String, UUID) -> Void
    let onCancel: () -> Void
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Save Request")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Request Name")
                    .font(.subheadline)
                    .foregroundColor(Theme.textSecondary)
                
                TextField("Enter name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)
                
                Text("Group")
                    .font(.subheadline)
                    .foregroundColor(Theme.textSecondary)
                    .padding(.top, 8)
                
                Picker("", selection: $selectedGroupId) {
                    if let workspace = appState.selectedWorkspace {
                        ForEach(workspace.requestGroups) { group in
                            Text(group.name).tag(group.id)
                        }
                    }
                }
                .labelsHidden()
            }
            
            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("Save") {
                    onSave(name, selectedGroupId)
                }
                .buttonStyle(AccentButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 320)
        .onAppear {
            isFocused = true
        }
    }
}

enum RequestError: LocalizedError {
    case noMessageTypeSelected(String)
    case invalidResponse
    
    var errorDescription: String? {
        switch self {
        case .noMessageTypeSelected(let type):
            return "Please select a \(type) message type"
        case .invalidResponse:
            return "Invalid response from server"
        }
    }
}

#Preview {
    HttpRequestView(tabState: RequestTabState())
        .environmentObject(AppState())
        .frame(width: 900, height: 600)
}
