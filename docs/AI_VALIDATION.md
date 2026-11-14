# AI interaction update — 2026-11-14

Version 0.4.8 adds source-linked PDF selection quotes and AI-answer selection actions. Quotes are persisted separately from the question text and included in both provider transports. Old conversation records decode with no quote. The native composer checks marked text before handling Return and explicitly inserts Shift-Return newlines. Its placeholder uses the same AppKit layout engine, font and container origin as entered text. Workspace download tools accept HTTP(S) input and contained relative destinations, publish a complete file with an exclusive hard link, preserve filename collisions and expose a Finder location in the conversation.

The initial run passed 54 Swift core tests, 12 editor tests and 167 English native checks, including actual NSTextView composition, native PDF selection actions, rendered conversation quotes, WebKit answer selection bridging, undoable excerpts, a real loopback HTTP tool download, duplicate filename preservation, path rejection and HTTP failure cleanup. The Chinese run exposed a Shift-Return difference and the implementation now calls the native newline action explicitly. Earlier Chinese passes also encountered an intermittent annotation-undo assertion and a foreground focus-animation timeout. The publisher requested stopping tests before the final footer/full-screen and input refinements completed their rerun. The final version is built, with the final native interaction regression pending.

The existing provider and transport evidence follows.

# AI workspace validation — 2026-11-11

Expanded conversations use the fourth, collapsible item of the native `NSSplitViewController`. The note editor stays visible beside the conversation. Its closed state releases the space to the reading workspace. Connection controls expose provider selection, model catalogues, custom model names and connection settings. Each provider stores its own model and endpoint. Requests take an immutable configuration snapshot at send time.

The transcript shares the note editor's Tiptap Markdown parser and schema serialization. Static HTML renders headings, emphasis, lists, tables, code and links. KaTeX renders formula nodes from their preserved LaTeX attributes. Assets and fonts ship in the application. The transcript's content security policy restricts scripts to packaged resources and blocks network resource loading. Supported node serialization restricts HTML attributes. Page links route through the application's existing PDF navigation handler. Copy actions use the original Markdown message.

Codex runs as an owned stdio child process. Its PATH includes the configured executable's directory and common Node installation locations. This fixes the reproduced Finder environment failure, which previously exited with code 127 when the npm entry point could not find Node. Stderr diagnostics are bounded in memory. Cancellation resolves pending RPC continuations, cancels their timers and closes the owned process. Connection generations isolate stale output during restart. Successful turn completion is retained when EOF follows it. Failed and interrupted turns propagate their respective errors or cancellation.

## Coverage

- Real native drawer geometry checks verify that the conversation is right of the visible note editor. Collapsing the drawer leaves the note available.
- Real WKWebView checks verify bold and italic computed font styles in both the note and conversation, plus table and KaTeX output. A streamed HTTP response also renders emphasis in the mounted drawer.
- Loopback cloud and local HTTP fixtures exercise model discovery and tool-backed streaming through `AIController.send`. The local endpoint checks that cloud authorization is omitted. Provider switching restores separate model/endpoint profiles. Connection changes invalidate stale catalogues.
- A failed Codex launch retains its question and exposes retry. Retrying through a configured provider produces one question entry and preserves an unsent draft.
- JSONL subprocess fixtures check startup exit codes, cancellation during initialization, restarting the same RPC object, research tool calls, declined shell/permission requests, completion followed by EOF, failed turns, interrupted turns and mid-turn disconnection. Executable fixtures are copied into the disposable test directory for GUI process access.
- The real installed Codex CLI 0.167.0 initializes and lists models using a deliberately minimal Finder PATH. Live inference uses the synthetic prompt `PAPER_READER_LIVE_OK`. User research files are excluded from live AI tests.

The standalone AI test runs through the native application with `--self-test --ai-self-test`, an isolated `PAPER_READER_LIBRARY`, a report path and loopback/subprocess fixtures. The full `scripts/test.sh` sets up those fixtures and invokes these checks alongside reader, editor, storage and workspace validation. Production API keys and AI settings are isolated from self-test preferences.

The combined native run passed 150 checks in English and 150 in Simplified Chinese, including the optional external-PDF regression and live Codex inference. Swift core tests passed 39 cases and editor tests passed 12 cases. A subsequent native AI-only run passed 21 checks after custom model entry moved into the control row. Manual native interaction verified sending a real question, following its page-2 citation, selecting a listed model and saving a custom model name through the inline field. The App Server lifecycle follows the official [Codex App Server documentation](https://learn.chatgpt.com/docs/app-server).

Actual third-party cloud model access and local model inference require their configured services. The loopback fixtures validate their HTTP contracts. Local model weights and a local inference engine remain separately managed services.
