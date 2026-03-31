//
//  SettingsView.swift
//  PomodoroSwift
//

import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @State private var selectedCampfirePreset: CampfirePreset = .cracklingCampfire
    @State private var aiInputText: String = ""
    @State private var aiIsClassifying = false
    @State private var aiStatusMessage: String = ""
    @State private var aiStatusIsError = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Appearance Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Appearance")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                FontPickerButton(selectedFont: $settings.selectedNSFont)
                
                // App-wide Light/Dark Mode
                HStack {
                    Text("Appearance")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("", selection: $settings.sidebarDarkMode) {
                        Text("Dark").tag(true)
                        Text("Light").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 120)
                }
            }
            
            // Timer Settings Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Timer Settings")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                // Short Break Time
                HStack {
                    Text("Short Break")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("", selection: $settings.breakTime) {
                        ForEach([3, 5, 10, 15], id: \.self) { min in
                            Text("\(min) min").tag(min)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 100)
                }
                
                // Long Break Time
                HStack {
                    Text("Long Break")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("", selection: $settings.longBreakTime) {
                        ForEach([10, 15, 20, 30], id: \.self) { min in
                            Text("\(min) min").tag(min)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 100)
                }
            }
            
            // White Noise Section
            VStack(alignment: .leading, spacing: 12) {
                Text("White Noise")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Toggle("Enable White Noise", isOn: $settings.whiteNoiseEnabled)
                    .toggleStyle(.switch)
                    .foregroundStyle(.secondary)
                
                if settings.whiteNoiseEnabled {
                    Toggle("Only During Timer", isOn: $settings.whiteNoiseOnlyWhenTimerRunning)
                        .toggleStyle(.switch)
                        .foregroundStyle(.secondary)

                    // Noise Type Picker
                    HStack {
                        Text("Sound Type")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Picker("", selection: $settings.whiteNoiseType) {
                            ForEach(NoiseType.allCases, id: \.rawValue) { type in
                                Text(type.displayName).tag(type.rawValue)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 140)
                    }
                    
                    // Volume Slider
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Volume")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "%.0f%%", settings.whiteNoiseVolume * 100))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                        Slider(value: $settings.whiteNoiseVolume, in: 0.0...1.0, step: 0.01)
                    }
                    
                    // Campfire tuning (only when campfire is selected)
                    if settings.whiteNoiseType == "campfire" {
                        // Preset picker
                        HStack {
                            Text("Preset")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Picker("", selection: $selectedCampfirePreset) {
                                ForEach(CampfirePreset.allCases, id: \.rawValue) { preset in
                                    Text(preset.displayName).tag(preset)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 200)
                            .onChange(of: selectedCampfirePreset) { _, newPreset in
                                settings.applyCampfirePreset(newPreset)
                            }
                        }
                        
                        // Fine-tuning sliders (collapsible)
                        DisclosureGroup("Fine Tuning") {
                            VStack(alignment: .leading, spacing: 8) {
                                campfireSlider(label: "Rumble", value: $settings.campfireRumble)
                                campfireSlider(label: "Texture", value: $settings.campfireTexture)
                                campfireSlider(label: "Pop Level", value: $settings.campfireWoodyLevel)
                                campfireSlider(label: "Snap Level", value: $settings.campfireSnapLevel)
                                campfireSlider(label: "Rumble Smooth", value: $settings.campfireRumbleSmooth)
                                campfireSlider(label: "Texture Smooth", value: $settings.campfireTextureSmooth)
                                campfireSlider(label: "Pop Density", value: $settings.campfireWoodyDensity)
                                campfireSlider(label: "Snap Density", value: $settings.campfireSnapDensity)
                                campfireSlider(label: "Resonance", value: $settings.campfireResonance)
                                campfireSlider(label: "Burst Prob", value: $settings.campfireBurstProb)
                                campfireFreqSlider(label: "Low Freq", value: $settings.campfireFreqLo, range: 50...800)
                                campfireFreqSlider(label: "Mid Freq", value: $settings.campfireFreqMid, range: 200...3000)
                                campfireFreqSlider(label: "High Freq", value: $settings.campfireFreqHi, range: 500...6000)
                            }
                        }
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    }
                }
            }
            
            // To-Do Panels Section
            VStack(alignment: .leading, spacing: 12) {
                Text("To-Do Panels")
                    .font(.headline)
                    .foregroundStyle(.primary)

                VStack(spacing: 8) {
                    ForEach($settings.todoPanels) { $panel in
                        HStack {
                            TextField("Panel Title", text: $panel.title)
                                .textFieldStyle(.roundedBorder)

                            Button(action: {
                                NotificationCenter.default.post(
                                    name: .resetToDoPanel,
                                    object: nil,
                                    userInfo: ["panelId": panel.id]
                                )
                            }) {
                                Image(systemName: "arrow.counterclockwise")
                                    .foregroundColor(.blue)
                            }
                            .buttonStyle(.plain)
                            .help("Reset position and size")
                            
                            Button(action: {
                                if let index = settings.todoPanels.firstIndex(where: { $0.id == panel.id }) {
                                    settings.todoPanels.remove(at: index)
                                }
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                            .disabled(settings.todoPanels.count <= 1) // Prevent deleting the last panel
                        }
                    }
                    
                    Button(action: {
                        settings.todoPanels.append(ToDoPanel(title: "New To-Do"))
                    }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Add Panel")
                        }
                        .foregroundColor(.blue)
                        .padding(.top, 4)
                    }
                    .buttonStyle(.plain)
                }
                .padding()
                .background(Color.black.opacity(0.2))
                .cornerRadius(8)
            }
            
            // AI Task Classifier Section
            VStack(alignment: .leading, spacing: 12) {
                Text("AI Task Classifier")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                SecureField("DashScope API Key", text: $settings.aiApiKey)
                    .textFieldStyle(.roundedBorder)
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Input Tasks")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black.opacity(0.2))
                        
                        TextEditor(text: $aiInputText)
                            .font(.system(size: 13))
                            .scrollContentBackground(.hidden)
                            .background(.clear)
                            .padding(4)
                    }
                    .frame(minHeight: 90, maxHeight: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )
                }
                
                HStack(spacing: 10) {
                    Button(action: runAIClassification) {
                        HStack(spacing: 8) {
                            if aiIsClassifying {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(aiIsClassifying ? "Classifying..." : "Classify Into Existing Panels")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        aiIsClassifying ||
                        aiInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        settings.aiApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        settings.todoPanels.isEmpty
                    )
                    
                    Text("Only writes into existing panels")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                if !aiStatusMessage.isEmpty {
                    Text(aiStatusMessage)
                        .font(.caption)
                        .foregroundStyle(aiStatusIsError ? .red : .green)
                }
            }
            
            // Liquid Glass Effect Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Liquid Glass Effect")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                // Glass Variant Picker
                HStack {
                    Text("Glass Variant")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("", selection: $settings.glassVariant) {
                        ForEach(Settings.glassVariants, id: \.1) { name, value in
                            Text(name).tag(value)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 140)
                }
                
                // Color Picker
                HStack {
                    Text("Tint Color")
                        .foregroundStyle(.secondary)
                    Spacer()
                    ColorPicker("", selection: $settings.glassTintColor, supportsOpacity: false)
                        .labelsHidden()
                }
                
                // Tint Opacity Slider
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Tint Opacity")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.2f", settings.glassTintOpacity))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    Slider(value: $settings.glassTintOpacity, in: 0.0...1.0, step: 0.01)
                }
                
                // Interactive Effect Toggle
                Toggle("Interactive Shimmer", isOn: $settings.glassInteractive)
                    .foregroundStyle(.secondary)
            }
            
            // Background Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Background")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                GlassButton("Select Image...", settings: settings) {
                    selectBackgroundImage()
                }
                
                if settings.backgroundImageData != nil {
                    GlassButton("Remove Background", settings: settings, isDestructive: true) {
                        settings.backgroundImageData = nil
                    }
                }
            }
            
            Spacer()
        }
    }
    
    private func selectBackgroundImage() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                if let imageData = try? Data(contentsOf: url) {
                    settings.backgroundImageData = imageData
                }
            }
        }
    }
    
    private func runAIClassification() {
        let apiKey = settings.aiApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let input = aiInputText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !apiKey.isEmpty else {
            aiStatusIsError = true
            aiStatusMessage = "Please input DashScope API Key first."
            return
        }
        
        guard !input.isEmpty else {
            aiStatusIsError = true
            aiStatusMessage = "Please describe your tasks first."
            return
        }
        
        let panelContexts = settings.todoPanels.map {
            AIPanelContext(
                id: $0.id,
                title: $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled" : $0.title
            )
        }
        
        guard !panelContexts.isEmpty else {
            aiStatusIsError = true
            aiStatusMessage = "No available panel to classify into."
            return
        }
        
        aiIsClassifying = true
        aiStatusMessage = ""
        aiStatusIsError = false
        
        Task {
            do {
                let assignments = try await AIToDoClassifier.classifyTasks(
                    apiKey: apiKey,
                    rawInput: input,
                    panels: panelContexts
                )
                
                let inserted = await MainActor.run {
                    ToDoStore.appendAssignments(assignments)
                }
                
                await MainActor.run {
                    aiIsClassifying = false
                    aiStatusIsError = false
                    if inserted > 0 {
                        aiStatusMessage = "Added \(inserted) task(s) into existing panels."
                        aiInputText = ""
                    } else {
                        aiStatusMessage = "No valid tasks were returned by AI."
                    }
                }
            } catch {
                await MainActor.run {
                    aiIsClassifying = false
                    aiStatusIsError = true
                    aiStatusMessage = userFacingAIError(error)
                }
            }
        }
    }
    
    private func userFacingAIError(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cannotFindHost, .dnsLookupFailed, .cannotConnectToHost, .notConnectedToInternet, .networkConnectionLost, .timedOut:
                return "AI 分类失败：无法连接模型服务，请检查网络、代理或 DNS 设置。"
            default:
                return "AI 分类失败：网络请求异常（\(urlError.code.rawValue)）。"
            }
        }
        return "AI 分类失败：\(error.localizedDescription)"
    }
    
    // Helper for campfire tuning sliders (0-1 range, shown as %)
    private func campfireSlider(label: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text(String(format: "%.0f%%", value.wrappedValue * 100))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            Slider(value: value, in: 0.0...1.0, step: 0.01)
        }
    }
    
    // Helper for frequency sliders (custom Hz range)
    private func campfireFreqSlider(label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text(String(format: "%.0f Hz", value.wrappedValue))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            Slider(value: value, in: range, step: 10)
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView(settings: Settings())
    }
}

private struct AIPanelContext: Codable {
    let id: UUID
    let title: String
}

private enum AIToDoClassifierError: LocalizedError {
    case invalidEndpoint
    case invalidHTTPStatus(Int, String)
    case emptyModelResponse
    case invalidModelJSON
    
    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "API endpoint is invalid."
        case .invalidHTTPStatus(let code, let body):
            let bodyText = body.trimmingCharacters(in: .whitespacesAndNewlines)
            if bodyText.isEmpty {
                return "Remote service returned HTTP \(code)."
            }
            return "Remote service returned HTTP \(code): \(bodyText)"
        case .emptyModelResponse:
            return "Model returned empty content."
        case .invalidModelJSON:
            return "Model did not return valid JSON."
        }
    }
}

private enum AIToDoClassifier {
    static func classifyTasks(
        apiKey: String,
        rawInput: String,
        panels: [AIPanelContext]
    ) async throws -> [UUID: [String]] {
        guard let endpoint = URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions") else {
            throw AIToDoClassifierError.invalidEndpoint
        }
        
        let panelsData = try JSONEncoder().encode(panels)
        let panelsJSON = String(data: panelsData, encoding: .utf8) ?? "[]"
        
        let systemPrompt = """
        你是待办事项分类助手。你必须把用户输入拆分成可执行任务，并归类到给定面板。
        只允许使用面板列表中已有的 panelId，禁止创建新分类。
        你必须只输出一个 JSON 对象，格式如下：
        {"assignments":[{"panelId":"UUID","tasks":["任务1","任务2"]}]}
        不要输出任何额外解释、注释或 Markdown。
        """
        
        let userPrompt = """
        面板列表(JSON):
        \(panelsJSON)
        
        用户输入:
        \(rawInput)
        """
        
        let primaryPayload = ChatCompletionRequest(
            model: "qwen-plus",
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: userPrompt)
            ],
            temperature: 0.2,
            responseFormat: .init(type: "json_object")
        )
        
        let classification: AIClassificationOutput
        do {
            classification = try await requestClassification(
                endpoint: endpoint,
                apiKey: apiKey,
                payload: primaryPayload
            )
        } catch AIToDoClassifierError.invalidModelJSON {
            // Retry once with stricter JSON instruction.
            let retryPayload = ChatCompletionRequest(
                model: "qwen-plus",
                messages: [
                    .init(role: "system", content: systemPrompt + "\n再次强调：只返回一个合法 JSON 对象。"),
                    .init(role: "user", content: userPrompt + "\n请只返回 JSON，不要包含任何其他字符。")
                ],
                temperature: 0.1,
                responseFormat: .init(type: "json_object")
            )
            classification = try await requestClassification(
                endpoint: endpoint,
                apiKey: apiKey,
                payload: retryPayload
            )
        }
        
        let validPanelIds = Set(panels.map { $0.id })
        
        var result: [UUID: [String]] = [:]
        for assignment in classification.assignments {
            guard let panelId = UUID(uuidString: assignment.panelId),
                  validPanelIds.contains(panelId) else {
                continue
            }
            
            let normalizedTasks = assignment.tasks
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            
            guard !normalizedTasks.isEmpty else { continue }
            result[panelId, default: []].append(contentsOf: normalizedTasks)
        }
        
        return result
    }
    
    private static func requestClassification(
        endpoint: URL,
        apiKey: String,
        payload: ChatCompletionRequest
    ) async throws -> AIClassificationOutput {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIToDoClassifierError.invalidHTTPStatus(-1, "")
        }
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AIToDoClassifierError.invalidHTTPStatus(httpResponse.statusCode, body)
        }
        
        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIToDoClassifierError.emptyModelResponse
        }
        
        let directText = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if let directData = directText.data(using: .utf8),
           let directOutput = try? JSONDecoder().decode(AIClassificationOutput.self, from: directData) {
            return directOutput
        }
        
        let extractedText = extractJSONObject(from: content)
        guard let extractedData = extractedText.data(using: .utf8),
              let extractedOutput = try? JSONDecoder().decode(AIClassificationOutput.self, from: extractedData) else {
            throw AIToDoClassifierError.invalidModelJSON
        }
        
        return extractedOutput
    }
    
    private static func extractJSONObject(from content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmed.hasPrefix("```") {
            let lines = trimmed.components(separatedBy: .newlines)
            if lines.count >= 3 {
                let body = lines.dropFirst().dropLast().joined(separator: "\n")
                return extractJSONObject(from: body)
            }
        }
        
        if let first = trimmed.firstIndex(of: "{"),
           let last = trimmed.lastIndex(of: "}") {
            return String(trimmed[first...last])
        }
        
        return trimmed
    }
}

private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double
    let responseFormat: ResponseFormat?
    
    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case responseFormat = "response_format"
    }
}

private struct ResponseFormat: Encodable {
    let type: String
}

private struct ChatMessage: Encodable {
    let role: String
    let content: String
}

private struct ChatCompletionResponse: Decodable {
    let choices: [Choice]
    
    struct Choice: Decodable {
        let message: ResponseMessage
    }
    
    struct ResponseMessage: Decodable {
        let content: String?
    }
}

private struct AIClassificationOutput: Decodable {
    let assignments: [Assignment]
    
    struct Assignment: Decodable {
        let panelId: String
        let tasks: [String]
    }
}
