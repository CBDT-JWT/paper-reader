import AppKit
import WebKit
import PaperCore

@MainActor enum MarkdownInputSelfTest {
    static func run(model: AppModel) async throws -> [String] {
        var checks: [String] = []
        func check(_ script: String, _ message: String) async throws {
            guard (try await model.editor.webView.evaluateJavaScript(script)) as? Bool == true else {
                throw IntegrationSelfTest.Failure(message: message)
            }
            checks.append(message)
        }
        let web = model.editor.webView
        _ = try await web.evaluateJavaScript(#"""
        window.noteInputFixture = {
          editor() { return document.querySelector('.tiptap').editor },
          reset() {
            const e = this.editor(); e.commands.setContent({type:'doc',content:[{type:'paragraph'}]});
            e.commands.setTextSelection(1); return true;
          },
          type(text) {
            const e=this.editor();
            for(const character of text) {
              const {from,to}=e.state.selection;
              const handled=e.view.someProp('handleTextInput',f=>f(e.view,from,to,character));
              if(!handled) e.view.dispatch(e.state.tr.insertText(character,from,to));
            }
            return true;
          },
          paste(text) {
            const e=this.editor(), event={clipboardData:{getData:type=>type==='text/plain'?text:''}};
            return !!e.view.someProp('handlePaste',f=>f(e.view,event));
          }
        }; true
        """#)
        _ = try await web.evaluateJavaScript(#"noteInputFixture.reset(); noteInputFixture.type('公式$x^2$和$E=mc^2$，中文**粗体***斜体*==高亮==~~删除~~`代码`')"#)
        try await check("document.querySelectorAll('[data-type=\"inline-math\"] .katex').length === 2", "Typing single-dollar equations renders KaTeX immediately in WKWebView")
        try await check("Number(getComputedStyle(document.querySelector('.tiptap strong')).fontWeight) >= 600", "Chinese-adjacent bold input renders bold text")
        try await check("getComputedStyle(document.querySelector('.tiptap em')).fontStyle === 'italic'", "Chinese-adjacent italic input renders italic text")
        try await check("document.querySelector('.tiptap mark')?.textContent === '高亮'", "Chinese-adjacent highlight input renders a highlight")
        try await check("document.querySelector('.tiptap s')?.textContent === '删除'", "Chinese-adjacent strike input renders strikethrough")
        try await check("document.querySelector('.tiptap code')?.textContent === '代码'", "Chinese-adjacent backticks render inline code")
        try await check("paperEditor.validate(paperEditor.getMarkdown()).ok", "The live formatted paragraph survives Markdown round-trip validation")

        _ = try await web.evaluateJavaScript("document.querySelector('[data-type=\"inline-math\"]').click(); true")
        try await check("!document.querySelector('#math-panel').hidden && document.querySelector('#math-input').value === 'x^2'", "A typed formula reopens its LaTeX source on click")
        _ = try await web.evaluateJavaScript("document.querySelector('#math-input').value='x^3'; document.querySelector('#math-form').dispatchEvent(new Event('submit',{bubbles:true,cancelable:true})); true")
        try await check("document.querySelector('[data-type=\"inline-math\"]').dataset.latex === 'x^3' && document.querySelectorAll('.katex').length === 2", "Editing formula source updates the rendered equation")
        _ = try await web.evaluateJavaScript("noteInputFixture.editor().commands.undo(); true")
        try await check("document.querySelector('[data-type=\"inline-math\"]').dataset.latex === 'x^2'", "The formula source change is undoable")

        _ = try await web.evaluateJavaScript(#"noteInputFixture.reset(); noteInputFixture.type('$$x^2+y^2=z^2$$')"#)
        try await check("!!document.querySelector('[data-type=\"block-math\"] .katex-display')", "Typing double-dollar display math uses display-mode KaTeX")
        _ = try await web.evaluateJavaScript(#"noteInputFixture.reset(); noteInputFixture.type('前文 '); noteInputFixture.paste('$x^2$ **粗体** 和 *斜体*')"#)
        try await check("noteInputFixture.editor().state.doc.childCount === 1 && !!document.querySelector('.katex') && !!document.querySelector('strong') && !!document.querySelector('em')", "Plain Markdown paste renders inline syntax inside the current paragraph")

        _ = try await web.evaluateJavaScript(#"noteInputFixture.reset(); noteInputFixture.editor().commands.setCodeBlock(); noteInputFixture.type('$x^2$')"#)
        try await check("!document.querySelector('.katex') && noteInputFixture.editor().state.doc.firstChild.textContent === '$x^2$'", "Code-block input preserves dollar syntax as code")
        _ = try await web.evaluateJavaScript(#"noteInputFixture.reset(); noteInputFixture.type('`$x^2$`')"#)
        try await check("!document.querySelector('.katex') && document.querySelector('.tiptap code')?.textContent === '$x^2$'", "Inline-code input preserves literal math syntax")

        _ = try await web.evaluateJavaScript(#"noteInputFixture.reset(); noteInputFixture.editor().view.dom.dispatchEvent(new CompositionEvent('compositionstart',{bubbles:true})); noteInputFixture.type('公式$x^2$')"#)
        try await check("!document.querySelector('.katex')", "IME composition retains the uncommitted equation source")
        _ = try await web.evaluateJavaScript("noteInputFixture.editor().view.dom.dispatchEvent(new CompositionEvent('compositionend',{bubbles:true})); true")
        try await Task.sleep(for: .milliseconds(100))
        try await check("!!document.querySelector('.katex')", "Committing IME composition renders the completed equation")

        _ = try await web.evaluateJavaScript(#"noteInputFixture.reset(); noteInputFixture.type('保存公式$x^2$和中文**粗体**')"#)
        await model.save()
        guard let id = model.activeNoteID else { throw IntegrationSelfTest.Failure(message: "Active note missing") }
        let saved = try await model.store.readNote(id)
        guard saved.markdown.contains("$x^2$"), saved.markdown.contains("**") else {
            throw IntegrationSelfTest.Failure(message: "Live inline Markdown was not saved to disk")
        }
        checks.append("Native note saving persists editable dollar-delimited Markdown")
        try await model.editor.setDocument(id: id, markdown: saved.markdown)
        try await check("!!document.querySelector('.katex') && !!document.querySelector('strong')", "Reopening the saved note restores math and inline formatting")
        return checks
    }
}
