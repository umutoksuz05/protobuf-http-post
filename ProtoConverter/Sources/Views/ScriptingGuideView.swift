import SwiftUI

struct ScriptingGuideView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("ProtoPost Scripting Guide")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(AccentButtonStyle())
                    .keyboardShortcut(.return)
            }
            .padding()
            .background(Theme.windowBackground)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    
                    // Overview
                    guideSection(title: "Overview") {
                        Text("ProtoPost supports JavaScript scripting on each request. Scripts run in a sandboxed environment using the built-in JavaScriptCore engine.")
                        
                        guideBullet("Pre-Request scripts", detail: "Run before the request is sent. Use them to modify the URL, headers, or body dynamically.")
                        guideBullet("Post-Response scripts", detail: "Run after the response is received. Use them to extract values, set environment variables, or update workspace settings.")
                        
                        Text("All scripting APIs are available under the **pp** (ProtoPost) namespace.")
                            .padding(.top, 4)
                    }
                    
                    Divider()
                    
                    // pp.request
                    guideSection(title: "pp.request") {
                        Text("Access and modify the outgoing request. Available in pre-request scripts.")
                            .foregroundColor(Theme.textSecondary)
                        
                        apiEntry(name: "pp.request.url", type: "string", rw: "read/write",
                                 description: "The resolved request URL. Modify it to change where the request is sent.")
                        apiEntry(name: "pp.request.method", type: "string", rw: "read-only",
                                 description: "The HTTP method (GET, POST, PUT, PATCH, DELETE).")
                        apiEntry(name: "pp.request.body", type: "string", rw: "read/write",
                                 description: "The request body as a string. Modify it to change the payload.")
                        apiEntry(name: "pp.request.headers.add(key, value)", type: "function", rw: "",
                                 description: "Add a new header to the request.")
                        apiEntry(name: "pp.request.headers.get(key)", type: "function", rw: "",
                                 description: "Get a header value by key (case-insensitive).")
                        apiEntry(name: "pp.request.headers.remove(key)", type: "function", rw: "",
                                 description: "Remove a header by key (case-insensitive).")
                        
                        codeBlock("""
                        // Add a dynamic header
                        pp.request.headers.add("X-Request-ID", crypto.randomUUID?.() ?? Date.now().toString());
                        
                        // Modify the URL
                        pp.request.url = pp.request.url + "?ts=" + Date.now();
                        """)
                    }
                    
                    Divider()
                    
                    // pp.response
                    guideSection(title: "pp.response") {
                        Text("Access the response data. Available in post-response scripts.")
                            .foregroundColor(Theme.textSecondary)
                        
                        apiEntry(name: "pp.response.code", type: "number", rw: "read-only",
                                 description: "The HTTP status code (e.g. 200, 404, 500).")
                        apiEntry(name: "pp.response.status", type: "string", rw: "read-only",
                                 description: "The full status string (e.g. \"200 OK\").")
                        apiEntry(name: "pp.response.body", type: "string", rw: "read-only",
                                 description: "The raw response body as a string.")
                        apiEntry(name: "pp.response.json()", type: "function", rw: "",
                                 description: "Parse the response body as JSON. Returns a JavaScript object, or null if parsing fails.")
                        apiEntry(name: "pp.response.headers.get(key)", type: "function", rw: "",
                                 description: "Get a response header value by key (case-insensitive).")
                        apiEntry(name: "pp.response.time", type: "number", rw: "read-only",
                                 description: "The response time in milliseconds.")
                        
                        codeBlock("""
                        const data = pp.response.json();
                        console.log("Status:", pp.response.code);
                        console.log("Response time:", pp.response.time, "ms");
                        console.log("Body keys:", Object.keys(data));
                        """)
                    }
                    
                    Divider()
                    
                    // pp.env
                    guideSection(title: "pp.env") {
                        Text("Manage environment variables for the active environment. Changes are saved immediately and persist across requests.")
                            .foregroundColor(Theme.textSecondary)
                        
                        apiEntry(name: "pp.env.set(key, value)", type: "function", rw: "",
                                 description: "Set an environment variable. Creates it if it doesn't exist, updates it if it does.")
                        apiEntry(name: "pp.env.get(key)", type: "function", rw: "",
                                 description: "Get the value of an environment variable. Returns empty string if not found.")
                        apiEntry(name: "pp.env.unset(key)", type: "function", rw: "",
                                 description: "Remove an environment variable.")
                        
                        codeBlock("""
                        // Store a value from the response
                        const data = pp.response.json();
                        pp.env.set("userId", String(data.user.id));
                        pp.env.set("sessionId", data.sessionId);
                        
                        // Read a variable
                        const userId = pp.env.get("userId");
                        console.log("Current user:", userId);
                        """)
                    }
                    
                    Divider()
                    
                    // pp.workspace
                    guideSection(title: "pp.workspace") {
                        Text("Update workspace-level settings. These affect all requests in the workspace.")
                            .foregroundColor(Theme.textSecondary)
                        
                        apiEntry(name: "pp.workspace.setAuthToken(token)", type: "function", rw: "",
                                 description: "Set the workspace authorization token. This token is automatically available as {{authToken}} in all requests.")
                        apiEntry(name: "pp.workspace.setBaseUrl(url)", type: "function", rw: "",
                                 description: "Set the workspace base URL. Available as {{baseUrl}} in all requests.")
                        
                        codeBlock("""
                        // Auto-save auth token from login response
                        const data = pp.response.json();
                        if (data.token) {
                            pp.workspace.setAuthToken(data.token);
                            console.log("Auth token updated!");
                        }
                        """)
                    }
                    
                    Divider()
                    
                    // console
                    guideSection(title: "console.log") {
                        Text("Log messages to the Console panel in the response area. Useful for debugging scripts.")
                            .foregroundColor(Theme.textSecondary)
                        
                        apiEntry(name: "console.log(...args)", type: "function", rw: "",
                                 description: "Log one or more values. Objects and arrays are automatically formatted as JSON.")
                        
                        Text("Also available: console.info(), console.warn(), console.error() -- all behave identically.")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textTertiary)
                            .padding(.top, 4)
                    }
                    
                    Divider()
                    
                    // Recipes
                    guideSection(title: "Common Recipes") {
                        
                        recipeCard(
                            title: "Auto-save auth token from login",
                            code: """
                            // Post-response script on your login request
                            const data = pp.response.json();
                            if (pp.response.code === 200 && data.token) {
                                pp.workspace.setAuthToken(data.token);
                                console.log("Token saved successfully");
                            } else {
                                console.log("Login failed:", pp.response.status);
                            }
                            """
                        )
                        
                        recipeCard(
                            title: "Add dynamic headers",
                            code: """
                            // Pre-request script
                            pp.request.headers.add("X-Timestamp", new Date().toISOString());
                            pp.request.headers.add("X-Client", "ProtoPost/1.0");
                            """
                        )
                        
                        recipeCard(
                            title: "Extract and store response values",
                            code: """
                            // Post-response script
                            const data = pp.response.json();
                            
                            // Store pagination cursor for next request
                            if (data.nextCursor) {
                                pp.env.set("cursor", data.nextCursor);
                            }
                            
                            // Store user info
                            pp.env.set("userId", String(data.user.id));
                            pp.env.set("username", data.user.name);
                            """
                        )
                        
                        recipeCard(
                            title: "Conditional logic based on status",
                            code: """
                            // Post-response script
                            if (pp.response.code >= 200 && pp.response.code < 300) {
                                const data = pp.response.json();
                                pp.env.set("lastSuccess", JSON.stringify(data));
                                console.log("Request succeeded");
                            } else {
                                console.log("Request failed with status:", pp.response.code);
                                console.log("Error body:", pp.response.body);
                            }
                            """
                        )
                        
                        recipeCard(
                            title: "Modify request body dynamically",
                            code: """
                            // Pre-request script
                            const body = JSON.parse(pp.request.body);
                            body.timestamp = Date.now();
                            body.requestId = Math.random().toString(36).substring(2);
                            pp.request.body = JSON.stringify(body);
                            """
                        )
                    }
                    
                    Divider()
                    
                    // Tips
                    guideSection(title: "Tips") {
                        guideBullet("Variables in scripts", detail: "Use pp.env.get(\"key\") to access variables. The {{key}} syntax only works in URL, headers, and body fields -- not in scripts.")
                        guideBullet("Error handling", detail: "Script errors are shown in the Console panel with a [Script Error] prefix. The request still completes even if a script fails.")
                        guideBullet("JSON parsing", detail: "pp.response.json() returns null if the body isn't valid JSON. Always check for null before accessing properties.")
                        guideBullet("String conversion", detail: "When storing numeric values with pp.env.set(), convert them to strings first: pp.env.set(\"id\", String(data.id)).")
                        guideBullet("Execution order", detail: "Pre-request runs first, then the HTTP request, then post-response. Environment changes from pre-request are visible in post-response.")
                    }
                }
                .padding(24)
            }
        }
        .frame(width: 650, height: 600)
    }
    
    // MARK: - Helper Views
    
    private func guideSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(.accentColor)
            
            content()
        }
    }
    
    private func apiEntry(name: String, type: String, rw: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(name)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(Theme.jsonKey)
                
                if !type.isEmpty {
                    Text(type)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Theme.jsonNumber)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Theme.jsonNumber.opacity(0.1))
                        .cornerRadius(3)
                }
                
                if !rw.isEmpty {
                    Text(rw)
                        .font(.system(size: 10))
                        .foregroundColor(Theme.textTertiary)
                }
            }
            
            Text(description)
                .font(.system(size: 12))
                .foregroundColor(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }
    
    private func codeBlock(_ code: String) -> some View {
        Text(code)
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(Theme.textPrimary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Theme.border, lineWidth: 0.5)
            )
            .textSelection(.enabled)
    }
    
    private func guideBullet(_ title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("*")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.accentColor)
                .frame(width: 12)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    
    private func recipeCard(title: String, code: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            
            codeBlock(code)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ScriptingGuideView()
        .frame(width: 650, height: 600)
}
