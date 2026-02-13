import Foundation
import JavaScriptCore

// MARK: - Script Context

struct ScriptContext {
    // Request data (can be modified by pre-request scripts)
    var url: String
    var method: String
    var headers: [(key: String, value: String)]
    var body: String
    
    // Response data (available in post-response scripts)
    var responseCode: Int?
    var responseStatus: String?
    var responseBody: String?
    var responseHeaders: [String: String]?
    var responseTimeMs: Double?
}

// MARK: - Script Result

struct ScriptResult {
    var modifiedUrl: String?
    var modifiedHeaders: [(key: String, value: String)]?
    var modifiedBody: String?
    var environmentUpdates: [String: String?] = [:]   // key -> value (nil = unset)
    var workspaceAuthToken: String?
    var workspaceBaseUrl: String?
    var consoleOutput: [String] = []
    var error: String?
}

// MARK: - Reference Wrappers (for capturing mutations from JS closures)

private class ConsoleRef {
    var output: [String] = []
}

private class EnvRef {
    var updates: [String: String?] = [:]
    var current: [String: String]
    init(variables: [String: String]) { self.current = variables }
}

private class WorkspaceRef {
    var authToken: String?
    var baseUrl: String?
}

// MARK: - Scripting Service

class ScriptingService {
    
    /// Run a pre-request script. Can modify URL, headers, body.
    func runPreRequestScript(_ script: String, context: ScriptContext, variables: [String: String]) -> ScriptResult {
        guard !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ScriptResult()
        }
        return executeScript(script, context: context, variables: variables, phase: .preRequest)
    }
    
    /// Run a post-response script. Can read response, set environment variables.
    func runPostResponseScript(_ script: String, context: ScriptContext, variables: [String: String]) -> ScriptResult {
        guard !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ScriptResult()
        }
        return executeScript(script, context: context, variables: variables, phase: .postResponse)
    }
    
    // MARK: - Private
    
    private enum ScriptPhase {
        case preRequest
        case postResponse
    }
    
    private func executeScript(_ script: String, context: ScriptContext, variables: [String: String], phase: ScriptPhase) -> ScriptResult {
        var result = ScriptResult()
        
        guard let jsContext = JSContext() else {
            result.error = "Failed to create JavaScript context"
            return result
        }
        
        // Mutable state refs captured by JS closures
        let consoleRef = ConsoleRef()
        let envRef = EnvRef(variables: variables)
        let wsRef = WorkspaceRef()
        
        // --- console ---
        setupConsole(jsContext: jsContext, ref: consoleRef)
        
        // --- exception handler ---
        var scriptError: String?
        jsContext.exceptionHandler = { _, exception in
            scriptError = exception?.toString() ?? "Unknown script error"
        }
        
        // --- pp object ---
        let ppObj = JSValue(newObjectIn: jsContext)!
        
        setupRequestObject(ppObj, context: context, jsContext: jsContext)
        setupResponseObject(ppObj, context: context, jsContext: jsContext, phase: phase)
        setupEnvObject(ppObj, jsContext: jsContext, ref: envRef)
        setupWorkspaceObject(ppObj, jsContext: jsContext, ref: wsRef)
        
        jsContext.setObject(ppObj, forKeyedSubscript: "pp" as NSString)
        
        // Execute the script
        jsContext.evaluateScript(script)
        
        // Collect results
        result.consoleOutput = consoleRef.output
        result.environmentUpdates = envRef.updates
        result.workspaceAuthToken = wsRef.authToken
        result.workspaceBaseUrl = wsRef.baseUrl
        
        if let err = scriptError {
            result.error = err
        }
        
        // Collect modified request data (for pre-request scripts)
        if phase == .preRequest {
            collectRequestModifications(ppObj, context: context, result: &result)
        }
        
        return result
    }
    
    // MARK: - console
    
    private func setupConsole(jsContext: JSContext, ref: ConsoleRef) {
        let consoleObj = JSValue(newObjectIn: jsContext)!
        let logBlock: @convention(block) () -> Void = {
            let args = JSContext.currentArguments() ?? []
            let message = args.map { val -> String in
                guard let jsVal = val as? JSValue else { return "undefined" }
                // For objects/arrays, try JSON.stringify for better output
                if jsVal.isObject && !jsVal.isString {
                    if let jsonData = try? JSONSerialization.data(
                        withJSONObject: jsVal.toObject() as Any,
                        options: [.prettyPrinted, .withoutEscapingSlashes]
                    ), let str = String(data: jsonData, encoding: .utf8) {
                        return str
                    }
                }
                return jsVal.toString() ?? "undefined"
            }.joined(separator: " ")
            ref.output.append(message)
        }
        consoleObj.setObject(logBlock, forKeyedSubscript: "log" as NSString)
        consoleObj.setObject(logBlock, forKeyedSubscript: "info" as NSString)
        consoleObj.setObject(logBlock, forKeyedSubscript: "warn" as NSString)
        consoleObj.setObject(logBlock, forKeyedSubscript: "error" as NSString)
        jsContext.setObject(consoleObj, forKeyedSubscript: "console" as NSString)
    }
    
    // MARK: - pp.request
    
    private func setupRequestObject(_ ppObj: JSValue, context: ScriptContext, jsContext: JSContext) {
        let reqObj = JSValue(newObjectIn: jsContext)!
        
        reqObj.setObject(context.url, forKeyedSubscript: "url" as NSString)
        reqObj.setObject(context.method, forKeyedSubscript: "method" as NSString)
        reqObj.setObject(context.body, forKeyedSubscript: "body" as NSString)
        
        // Build headers as JS array
        let headersArray = JSValue(newArrayIn: jsContext)!
        for (i, header) in context.headers.enumerated() {
            let entry = JSValue(newObjectIn: jsContext)!
            entry.setObject(header.key, forKeyedSubscript: "key" as NSString)
            entry.setObject(header.value, forKeyedSubscript: "value" as NSString)
            headersArray.setObject(entry, atIndexedSubscript: i)
        }
        reqObj.setObject(headersArray, forKeyedSubscript: "_headers" as NSString)
        
        // pp.request.headers helper methods
        let headersObj = JSValue(newObjectIn: jsContext)!
        
        let addHeader: @convention(block) (String, String) -> Void = { [weak reqObj] key, value in
            guard let reqObj = reqObj else { return }
            let entry = JSValue(newObjectIn: jsContext)!
            entry.setObject(key, forKeyedSubscript: "key" as NSString)
            entry.setObject(value, forKeyedSubscript: "value" as NSString)
            let arr = reqObj.objectForKeyedSubscript("_headers")!
            let len = arr.objectForKeyedSubscript("length")?.toInt32() ?? 0
            arr.setObject(entry, atIndexedSubscript: Int(len))
        }
        headersObj.setObject(addHeader, forKeyedSubscript: "add" as NSString)
        
        let getHeader: @convention(block) (String) -> String = { [weak reqObj] key in
            guard let reqObj = reqObj else { return "" }
            let arr = reqObj.objectForKeyedSubscript("_headers")!
            let len = arr.objectForKeyedSubscript("length")?.toInt32() ?? 0
            for i in 0..<len {
                if let entry = arr.objectAtIndexedSubscript(Int(i)) {
                    let k = entry.objectForKeyedSubscript("key")?.toString() ?? ""
                    if k.caseInsensitiveCompare(key) == .orderedSame {
                        return entry.objectForKeyedSubscript("value")?.toString() ?? ""
                    }
                }
            }
            return ""
        }
        headersObj.setObject(getHeader, forKeyedSubscript: "get" as NSString)
        
        let removeHeader: @convention(block) (String) -> Void = { [weak reqObj] key in
            guard let reqObj = reqObj else { return }
            let arr = reqObj.objectForKeyedSubscript("_headers")!
            let len = arr.objectForKeyedSubscript("length")?.toInt32() ?? 0
            let newArr = JSValue(newArrayIn: jsContext)!
            var idx = 0
            for i in 0..<len {
                if let entry = arr.objectAtIndexedSubscript(Int(i)) {
                    let k = entry.objectForKeyedSubscript("key")?.toString() ?? ""
                    if k.caseInsensitiveCompare(key) != .orderedSame {
                        newArr.setObject(entry, atIndexedSubscript: idx)
                        idx += 1
                    }
                }
            }
            reqObj.setObject(newArr, forKeyedSubscript: "_headers" as NSString)
        }
        headersObj.setObject(removeHeader, forKeyedSubscript: "remove" as NSString)
        
        reqObj.setObject(headersObj, forKeyedSubscript: "headers" as NSString)
        ppObj.setObject(reqObj, forKeyedSubscript: "request" as NSString)
    }
    
    // MARK: - pp.response
    
    private func setupResponseObject(_ ppObj: JSValue, context: ScriptContext, jsContext: JSContext, phase: ScriptPhase) {
        let resObj = JSValue(newObjectIn: jsContext)!
        
        if phase == .postResponse {
            resObj.setObject(context.responseCode ?? 0, forKeyedSubscript: "code" as NSString)
            resObj.setObject(context.responseStatus ?? "", forKeyedSubscript: "status" as NSString)
            resObj.setObject(context.responseBody ?? "", forKeyedSubscript: "body" as NSString)
            resObj.setObject(context.responseTimeMs ?? 0, forKeyedSubscript: "time" as NSString)
            
            // pp.response.json()
            let responseBody = context.responseBody ?? ""
            let jsonParse: @convention(block) () -> JSValue = {
                guard let data = responseBody.data(using: .utf8) else {
                    return JSValue(nullIn: jsContext)
                }
                do {
                    let jsonObj = try JSONSerialization.jsonObject(with: data)
                    return JSValue(object: jsonObj, in: jsContext)
                } catch {
                    return JSValue(nullIn: jsContext)
                }
            }
            resObj.setObject(jsonParse, forKeyedSubscript: "json" as NSString)
            
            // pp.response.headers
            let resHeadersObj = JSValue(newObjectIn: jsContext)!
            let responseHeaders = context.responseHeaders ?? [:]
            let resGetHeader: @convention(block) (String) -> String = { key in
                return responseHeaders[key] ?? responseHeaders.first(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame })?.value ?? ""
            }
            resHeadersObj.setObject(resGetHeader, forKeyedSubscript: "get" as NSString)
            resObj.setObject(resHeadersObj, forKeyedSubscript: "headers" as NSString)
        }
        
        ppObj.setObject(resObj, forKeyedSubscript: "response" as NSString)
    }
    
    // MARK: - pp.env
    
    private func setupEnvObject(_ ppObj: JSValue, jsContext: JSContext, ref: EnvRef) {
        let envObj = JSValue(newObjectIn: jsContext)!
        
        let envSet: @convention(block) (String, String) -> Void = { key, value in
            ref.updates[key] = value
            ref.current[key] = value
        }
        envObj.setObject(envSet, forKeyedSubscript: "set" as NSString)
        
        let envGet: @convention(block) (String) -> String = { key in
            return ref.current[key] ?? ""
        }
        envObj.setObject(envGet, forKeyedSubscript: "get" as NSString)
        
        let envUnset: @convention(block) (String) -> Void = { key in
            ref.updates[key] = nil as String?
            ref.current.removeValue(forKey: key)
        }
        envObj.setObject(envUnset, forKeyedSubscript: "unset" as NSString)
        
        ppObj.setObject(envObj, forKeyedSubscript: "env" as NSString)
    }
    
    // MARK: - pp.workspace
    
    private func setupWorkspaceObject(_ ppObj: JSValue, jsContext: JSContext, ref: WorkspaceRef) {
        let wsObj = JSValue(newObjectIn: jsContext)!
        
        let setAuth: @convention(block) (String) -> Void = { token in
            ref.authToken = token
        }
        wsObj.setObject(setAuth, forKeyedSubscript: "setAuthToken" as NSString)
        
        let setBaseUrl: @convention(block) (String) -> Void = { url in
            ref.baseUrl = url
        }
        wsObj.setObject(setBaseUrl, forKeyedSubscript: "setBaseUrl" as NSString)
        
        ppObj.setObject(wsObj, forKeyedSubscript: "workspace" as NSString)
    }
    
    // MARK: - Collect Request Modifications
    
    private func collectRequestModifications(_ ppObj: JSValue, context: ScriptContext, result: inout ScriptResult) {
        guard let reqObj = ppObj.objectForKeyedSubscript("request") else { return }
        
        if let modUrl = reqObj.objectForKeyedSubscript("url")?.toString(), modUrl != context.url {
            result.modifiedUrl = modUrl
        }
        if let modBody = reqObj.objectForKeyedSubscript("body")?.toString(), modBody != context.body {
            result.modifiedBody = modBody
        }
        
        // Collect modified headers
        if let headersArray = reqObj.objectForKeyedSubscript("_headers"), headersArray.isArray {
            var modHeaders: [(key: String, value: String)] = []
            let len = headersArray.objectForKeyedSubscript("length")?.toInt32() ?? 0
            for i in 0..<len {
                if let entry = headersArray.objectAtIndexedSubscript(Int(i)) {
                    let key = entry.objectForKeyedSubscript("key")?.toString() ?? ""
                    let value = entry.objectForKeyedSubscript("value")?.toString() ?? ""
                    modHeaders.append((key: key, value: value))
                }
            }
            if modHeaders.count != context.headers.count ||
                !zip(modHeaders, context.headers).allSatisfy({ $0.0.key == $0.1.key && $0.0.value == $0.1.value }) {
                result.modifiedHeaders = modHeaders
            }
        }
    }
}
