# TxemAI MLX — Task 5: File & Image Attachments

## Project context
TxemAI MLX is a native macOS SwiftUI app frontend for oMLX (localhost:8000).
This task adds file and image attachment support to the chat.

## Auth
- /v1/* uses Authorization: Bearer <api_key>
- /admin/api/* uses session cookie

## Relevant existing files
- `Views/Chat/ChatView.swift` — main chat view, has sendMessage() and input area
- `Services/APIClient.swift` — has streamChat(model:messages:) 
- `Models/ServerModels.swift` — has ChatMessage struct
- `Models/ChatModels.swift` — has PersistedMessage struct

## Swift conventions
- macOS 26, Swift 6, SwiftUI only
- @MainActor for ViewModels
- async/await, no Combine except @Published
- No new SPM dependencies

---

## TASK 5 — File & image attachments

### Step 1 — Create AttachmentItem enum in Models/ChatModels.swift

Add to the BOTTOM of ChatModels.swift (do not modify existing structs):

```swift
enum AttachmentItem: Identifiable {
    case text(filename: String, content: String)
    case image(filename: String, base64: String, mimeType: String)

    var id: String {
        switch self {
        case .text(let filename, _): return filename
        case .image(let filename, _, _): return filename
        }
    }

    var filename: String {
        switch self {
        case .text(let f, _): return f
        case .image(let f, _, _): return f
        }
    }

    var isImage: Bool {
        if case .image = self { return true }
        return false
    }
}
```

### Step 2 — Update APIClient.swift streamChat to accept attachments

Find streamChat(model:messages:) and update its signature to:

```swift
func streamChat(
    model: String,
    messages: [ChatMessage],
    attachments: [AttachmentItem] = []
) -> AsyncThrowingStream<String, Error>
```

The last user message needs to be modified to include attachments.
If there are text attachments, prepend their content to the last user message content:
```
[filename.swift]
```swift
<file content>
```
```

If there are image attachments AND the model supports vision, use the OpenAI
multimodal content format for the last user message:

```json
{
  "role": "user",
  "content": [
    {"type": "text", "text": "user message text"},
    {"type": "image_url", "url": "data:image/jpeg;base64,<base64data>"}
  ]
}
```

Vision model detection — check if model name (lowercased) contains any of:
"vl", "vision", "vlm", "pixtral", "llava", "qwen-vl", "glm-4v", "minicpm-v"

For the API call, create separate Encodable structs for text-only vs multimodal content:
```swift
// Text-only message (existing)
struct TextMessage: Encodable { let role: String; let content: String }

// Multimodal message
struct MultimodalMessage: Encodable {
    let role: String
    let content: [ContentPart]
}
struct ContentPart: Encodable {
    let type: String      // "text" or "image_url"
    let text: String?
    let imageUrl: ImageURL?
    enum CodingKeys: String, CodingKey {
        case type, text
        case imageUrl = "image_url"
    }
}
struct ImageURL: Encodable { let url: String }
```

Use a type-erased encoding approach — encode each message individually and combine,
or use a wrapper with custom Encodable implementation.

### Step 3 — Add attachment UI to ChatView.swift

In the input area HStack, add a paperclip button to the LEFT of the TextField:

```swift
@State private var attachments: [AttachmentItem] = []

// Paperclip button
Button {
    openFilePicker()
} label: {
    Image(systemName: "paperclip")
        .font(.system(size: 16))
        .foregroundStyle(attachments.count >= 3 ? Color.secondary : Color.primary)
}
.buttonStyle(.plain)
.disabled(attachments.count >= 3)
```

Add an attachment chips area ABOVE the input HStack (only shown when attachments.count > 0):

```swift
if !attachments.isEmpty {
    ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 6) {
            ForEach(attachments) { attachment in
                AttachmentChip(attachment: attachment) {
                    attachments.removeAll { $0.id == attachment.id }
                }
            }
        }
        .padding(.horizontal, 16)
    }
    .frame(height: 32)
}
```

### Step 4 — Create AttachmentChip view (add to bottom of ChatView.swift)

```swift
private struct AttachmentChip: View {
    let attachment: AttachmentItem
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: attachment.isImage ? "photo" : "doc.text")
                .font(.system(size: 10))
            Text(attachment.filename)
                .font(.system(size: 11))
                .lineLimit(1)
                .frame(maxWidth: 120)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(NSColor.separatorColor), lineWidth: 0.5))
    }
}
```

### Step 5 — Implement openFilePicker() in ChatView

```swift
private func openFilePicker() {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = true
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowedContentTypes = [
        .plainText, .sourceCode, .json, .commaSeparatedText,
        .jpeg, .png, .gif, .webP, .pdf,
        UTType(filenameExtension: "swift")!,
        UTType(filenameExtension: "py")!,
        UTType(filenameExtension: "js")!,
        UTType(filenameExtension: "ts")!,
        UTType(filenameExtension: "md")!,
    ].compactMap { $0 }

    panel.begin { response in
        guard response == .OK else { return }
        let urls = panel.urls.prefix(3 - self.attachments.count)

        for url in urls {
            let ext = url.pathExtension.lowercased()
            let imageExts = ["jpg", "jpeg", "png", "gif", "webp"]

            if imageExts.contains(ext) {
                // Image: encode as base64
                guard let data = try? Data(contentsOf: url) else { continue }
                let base64 = data.base64EncodedString()
                let mimeType = ext == "jpg" || ext == "jpeg" ? "image/jpeg"
                    : ext == "png" ? "image/png"
                    : ext == "gif" ? "image/gif"
                    : "image/webp"
                self.attachments.append(.image(filename: url.lastPathComponent, base64: base64, mimeType: mimeType))
            } else {
                // Text file: read as string
                guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
                self.attachments.append(.text(filename: url.lastPathComponent, content: content))
            }
        }
    }
}
```

### Step 6 — Update sendMessage() to pass attachments

In sendMessage(), update the APIClient call to pass attachments, and clear them after sending:

```swift
let currentAttachments = attachments
attachments = []  // clear immediately

streamTask = Task {
    for try await token in APIClient.shared.streamChat(
        model: model,
        messages: apiMessages,
        attachments: currentAttachments
    ) { ... }
}
```

## Implementation order
Step 1 → Step 2 → Step 3 → Step 4 → Step 5 → Step 6
Compile after Step 2 (hardest part) before continuing.
Do NOT change any other views or files not mentioned above.
