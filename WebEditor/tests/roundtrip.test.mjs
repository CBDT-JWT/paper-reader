import { JSDOM } from 'jsdom'
import test from 'node:test'
import assert from 'node:assert/strict'
const dom = new JSDOM('<!doctype html><html><body></body></html>', {url: 'https://test.invalid/'})
for (const key of ['window', 'document', 'navigator', 'Node', 'HTMLElement', 'Element', 'MutationObserver', 'DOMParser', 'getComputedStyle']) {
  Object.defineProperty(globalThis, key, {value: key === 'getComputedStyle' ? dom.window.getComputedStyle.bind(dom.window) : dom.window[key], configurable: true})
}
globalThis.requestAnimationFrame = fn => setTimeout(fn, 0)
globalThis.cancelAnimationFrame = clearTimeout
const {createEditor, validateMarkdown, canonicalDocument} = await import('../src/schema.js')
const fixtures = [
  ['formatting', '# Heading\n\nA **bold** and *italic* and ~~deleted~~ and ==highlighted== paragraph.\n\n## Section\n\n`inline code` and [link](https://example.org).\n\n> a quote\n\n---'],
  ['lists', '- first\n  - nested\n- second\n\n1. one\n2. two\n\n- [ ] pending\n- [x] done'],
  ['code', '```swift\nlet formula = "$x$"\nprint("<p>")\n```'],
  ['math', 'Inline $E = mc^2$ equation.\n\n$$\n\\int_0^1 x^2 \\, dx = \\frac{1}{3}\n$$'],
  ['table', '| Method | Score |\n| --- | --- |\n| Ours | **0.95** |\n| Baseline | 0.81 |'],
  ['resources', '![Curve](assets/figure.png)\n\n[来源 · 第 2 页](paperreader://source/11111111-1111-1111-1111-111111111111)'],
  ['image size', '![Curve](assets/figure.png "A curve {width=320}")'],
  ['mermaid source', '```mermaid\nflowchart LR\n  Evidence --> Understanding\n```'],
  ['unicode', '# 论文笔记\n\n保持中文、α、β 与 😀。\n\n多行\n文本。'],
]
for (const [name, markdown] of fixtures) {
  test(`semantic round-trip: ${name}`, () => {
    const element = document.createElement('div'); document.body.append(element)
    const editor = createEditor(element)
    const parsed = validateMarkdown(editor, markdown)
    editor.commands.setContent(parsed)
    const output = editor.getMarkdown()
    assert.deepEqual(canonicalDocument(editor.markdown.parse(output)), canonicalDocument(parsed))
    if (name === 'image size') assert.match(output, /width=320/)
    if (name === 'math') { assert.equal(element.querySelectorAll('.katex').length, 2); assert.match(output, /\\frac\{1\}\{3\}/) }
    if (name === 'resources') { assert.match(output, /assets\/figure\.png/); assert.match(output, /paperreader:\/\/source/) }
    if (name === 'formatting') { assert.equal(element.querySelector('strong')?.textContent, 'bold'); assert.equal(element.querySelector('em')?.textContent, 'italic') }
    editor.destroy(); element.remove()
  })
}
test('unsupported syntax is rejected without mutating content', () => {
  const editor = createEditor(document.createElement('div'))
  editor.commands.setContent('<p>Original content</p>')
  for (const markdown of ['---\ntitle: draft\n---\n', '<iframe src="x"></iframe>', 'Text[^1]\n\n[^1]: Footnote']) {
    assert.throws(() => validateMarkdown(editor, markdown))
    assert.equal(editor.getText(), 'Original content')
  }
  editor.destroy()
})
test('conversation Markdown renders Chinese emphasis, blocks, tables and safe links', async () => {
  const {messageHTML} = await import('../src/message-markdown.js')
  const parser = createEditor(document.createElement('div'))
  const html = messageHTML(parser, '# 结果\n\n这是**粗体**和*斜体*。\n\n- 证据\n- 结论\n\n| A | B |\n| --- | --- |\n| 1 | 2 |\n\n```swift\nlet x = 1\n```\n\n[p.2](paperreader://page/2)\n\n$x^2$')
  const element = document.createElement('div'); element.innerHTML = html
  assert.equal(element.querySelector('strong')?.textContent, '粗体')
  assert.equal(element.querySelector('em')?.textContent, '斜体')
  assert.ok(element.querySelector('h1') && element.querySelector('li') && element.querySelector('table') && element.querySelector('pre code'))
  assert.equal(element.querySelector('a')?.getAttribute('href'), 'paperreader://page/2')
  assert.equal(element.querySelector('[data-latex]')?.dataset.latex, 'x^2')
  const unsafe = messageHTML(parser, '<script>alert(1)</script>\n\n<img src="x" onerror="alert(1)">\n\n[bad](javascript:alert(1))')
  const checked = document.createElement('div'); checked.innerHTML = unsafe
  assert.equal(checked.querySelector('script,[onerror],a[href^="javascript:"]'), null)
  parser.destroy()
})
test('editing math, task and formatting is undoable and serializes supported syntax', () => {
  const editor = createEditor(document.createElement('div'))
  editor.chain().setMeta('addToHistory', false).setContent(validateMarkdown(editor, 'Result $x^2$')).run()
  let pos
  editor.state.doc.descendants((node, at) => { if (node.type.name === 'inlineMath') pos = at })
  editor.chain().setNodeSelection(pos).updateInlineMath({latex: 'x^3', pos}).run()
  assert.match(editor.getMarkdown(), /\$x\^3\$/)
  editor.commands.undo()
  assert.match(editor.getMarkdown(), /\$x\^2\$/)
  editor.destroy()
})
