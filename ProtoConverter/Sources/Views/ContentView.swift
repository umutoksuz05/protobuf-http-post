import SwiftUI

enum LeftPanelTab: String, CaseIterable, Identifiable {
    case protoFiles = "Proto Files"
    case savedRequests = "Requests"
    
    var id: String { rawValue }
}

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("appAppearance") private var appearance: String = "system"
    @State private var selectedLeftPanelTab: LeftPanelTab = .protoFiles
    
    // Multiple request tabs with persistent state
    @State private var requestTabStates: [RequestTabState] = []
    @State private var selectedTabId: UUID?
    
    var body: some View {
        NavigationSplitView {
            WorkspaceSidebar()
        } detail: {
            HSplitView {
                // Left panel - Proto files or Saved requests
                leftPanel
                    .frame(minWidth: 280, idealWidth: 320, maxWidth: 450)
                
                // Main content area
                mainContentArea
                    .frame(minWidth: 600)
            }
        }
        .navigationSplitViewStyle(.prominentDetail)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                if let workspace = appState.selectedWorkspace {
                    HStack(spacing: 6) {
                        Image(systemName: "folder.fill")
                            .foregroundColor(.accentColor)
                            .font(.system(size: 13))
                        Text(workspace.name)
                            .fontWeight(.semibold)
                    }
                }
            }
            
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 8) {
                    if appState.isLoading {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                    
                    // Environment selector
                    if let workspace = appState.selectedWorkspace {
                        HStack(spacing: 4) {
                            Image(systemName: "globe")
                                .font(.system(size: 11))
                                .foregroundColor(Theme.textSecondary)
                            
                            Picker("", selection: Binding(
                                get: { workspace.selectedEnvironmentId ?? WorkspaceEnvironment.defaultEnvironmentId },
                                set: { newId in
                                    if let env = workspace.environments.first(where: { $0.id == newId }) {
                                        appState.selectEnvironment(env)
                                    }
                                }
                            )) {
                                ForEach(workspace.environments) { env in
                                    Text(env.name).tag(env.id)
                                }
                            }
                            .frame(width: 120)
                        }
                        .help("Select Environment")
                    }
                    
                    // Dark mode toggle
                    Button(action: toggleAppearance) {
                        Image(systemName: appearanceIcon)
                            .font(.system(size: 13))
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(ToolbarIconButtonStyle())
                    .help("Toggle Appearance")
                    
                    Button(action: { appState.showWorkspaceSettings = true }) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(ToolbarIconButtonStyle())
                    .help("Workspace Settings")
                }
            }
        }
        .sheet(isPresented: $appState.showWorkspaceSettings) {
            WorkspaceSettingsView()
                .environmentObject(appState)
        }
        .onAppear {
            initializeTabs()
        }
        .onChange(of: appState.selectedWorkspace) { _, _ in
            initializeTabs()
        }
    }
    
    // MARK: - Appearance
    
    private var appearanceIcon: String {
        switch appearance {
        case "dark": return "moon.fill"
        case "light": return "sun.max.fill"
        default: return "circle.lefthalf.filled"
        }
    }
    
    private func toggleAppearance() {
        withAnimation(Theme.smooth) {
            switch appearance {
            case "system": appearance = "dark"
            case "dark": appearance = "light"
            case "light": appearance = "system"
            default: appearance = "system"
            }
        }
    }
    
    // MARK: - Tab Initialization
    
    private func initializeTabs() {
        if requestTabStates.isEmpty {
            let newTab = createNewTabState()
            requestTabStates = [newTab]
            selectedTabId = newTab.id
        }
    }
    
    private func createNewTabState() -> RequestTabState {
        let state = RequestTabState()
        
        // Apply workspace defaults
        if let workspace = appState.selectedWorkspace {
            state.applyWorkspaceDefaults(
                baseUrl: workspace.settings.baseUrl,
                authToken: workspace.settings.authToken
            )
        }
        
        return state
    }
    
    // MARK: - Left Panel
    
    private var leftPanel: some View {
        VStack(spacing: 0) {
            // Tab picker for left panel
            Picker("", selection: $selectedLeftPanelTab) {
                ForEach(LeftPanelTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(10)
            
            Divider()
            
            // Content based on selected tab with transition
            Group {
                switch selectedLeftPanelTab {
                case .protoFiles:
                    ProtoFileListView()
                        .transition(.opacity)
                case .savedRequests:
                    RequestsCollectionView(onOpenRequest: openSavedRequest)
                        .transition(.opacity)
                }
            }
            .animation(Theme.smooth, value: selectedLeftPanelTab)
        }
    }
    
    // MARK: - Main Content Area
    
    private var mainContentArea: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack(spacing: 12) {
                Text("Requests")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.textSecondary)
                
                Spacer()
                
                // Add new request tab button
                Button(action: addNewRequestTab) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .medium))
                        Text("New")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .buttonStyle(HoverButtonStyle())
                .help("New Request Tab")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Theme.surface.opacity(0.5))
            
            Divider()
            
            requestsTabContent
        }
    }
    
    // MARK: - Requests Tab Content
    
    private var requestsTabContent: some View {
        VStack(spacing: 0) {
            // Request tabs bar
            if requestTabStates.count > 1 || requestTabStates.first?.savedRequest != nil {
                requestTabsBar
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            // Current request view
            if let selectedId = selectedTabId,
               let tabState = requestTabStates.first(where: { $0.id == selectedId }) {
                HttpRequestView(
                    tabState: tabState,
                    onRequestSaved: { saved in
                        handleRequestSaved(tabId: selectedId, saved: saved)
                    }
                )
                .id(selectedId)
                .transition(.opacity)
            } else if let firstState = requestTabStates.first {
                HttpRequestView(
                    tabState: firstState,
                    onRequestSaved: { saved in
                        handleRequestSaved(tabId: firstState.id, saved: saved)
                    }
                )
            }
        }
        .animation(Theme.smooth, value: selectedTabId)
    }
    
    // MARK: - Request Tabs Bar
    
    private var requestTabsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(requestTabStates) { tabState in
                    RequestTabButton(
                        tabState: tabState,
                        isSelected: selectedTabId == tabState.id,
                        canClose: requestTabStates.count > 1,
                        onSelect: { selectedTabId = tabState.id },
                        onClose: { closeRequestTab(tabState) }
                    )
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .background(Theme.surface)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
    
    // MARK: - Tab Management
    
    private func addNewRequestTab() {
        let newTab = createNewTabState()
        withAnimation(Theme.snappy) {
            requestTabStates.append(newTab)
            selectedTabId = newTab.id
        }
    }
    
    private func closeRequestTab(_ tabState: RequestTabState) {
        guard requestTabStates.count > 1 else { return }
        
        if let index = requestTabStates.firstIndex(where: { $0.id == tabState.id }) {
            // Select another tab if the closed one was selected
            if selectedTabId == tabState.id {
                if index > 0 {
                    selectedTabId = requestTabStates[index - 1].id
                } else {
                    selectedTabId = requestTabStates.count > 1 ? requestTabStates[1].id : nil
                }
            }
            
            let _ = withAnimation(Theme.snappy) {
                requestTabStates.remove(at: index)
            }
        }
    }
    
    private func openSavedRequest(_ request: SavedRequest) {
        // Check if already open
        if let existingTab = requestTabStates.first(where: { $0.savedRequest?.id == request.id }) {
            withAnimation(Theme.smooth) {
                selectedTabId = existingTab.id
            }
            return
        }
        
        // Open in new tab
        let newTab = RequestTabState(savedRequest: request)
        withAnimation(Theme.snappy) {
            requestTabStates.append(newTab)
            selectedTabId = newTab.id
        }
    }
    
    private func handleRequestSaved(tabId: UUID, saved: SavedRequest) {
        if let tabState = requestTabStates.first(where: { $0.id == tabId }) {
            tabState.markAsSaved(with: saved)
        }
    }
}

// MARK: - Request Tab Button

struct RequestTabButton: View {
    let tabState: RequestTabState
    let isSelected: Bool
    let canClose: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    
    @State private var isHovering = false
    @State private var closeHovering = false
    
    var body: some View {
        HStack(spacing: 6) {
            // Method indicator
            Text(tabState.method)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(Theme.textOnAccent)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.methodGradient(tabState.method))
                )
            
            Text(tabState.displayTitle)
                .font(.system(size: 11, weight: isSelected ? .medium : .regular))
                .lineLimit(1)
                .foregroundColor(isSelected ? Theme.textPrimary : Theme.textSecondary)
            
            // Unsaved changes indicator
            if tabState.hasUnsavedChanges {
                Circle()
                    .fill(Theme.warning)
                    .frame(width: 6, height: 6)
                    .transition(.scale.combined(with: .opacity))
                    .help("Unsaved changes")
            }
            
            // Close button - visible on hover
            if canClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(closeHovering ? Theme.textPrimary : Theme.textTertiary)
                        .frame(width: 16, height: 16)
                        .background(
                            Circle()
                                .fill(closeHovering ? Theme.surfaceHover : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .opacity(isHovering || isSelected ? 1 : 0)
                .onHover { h in closeHovering = h }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Theme.surfaceActive : isHovering ? Theme.surfaceHover : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isSelected ? Theme.borderActive : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onHover { h in
            withAnimation(Theme.quick) { isHovering = h }
        }
        .animation(Theme.smooth, value: isSelected)
        .animation(Theme.quick, value: tabState.hasUnsavedChanges)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
        .frame(width: 1200, height: 700)
}
