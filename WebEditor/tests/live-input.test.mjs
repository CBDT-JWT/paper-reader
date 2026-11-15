import { JSDOM } from 'jsdom'
import test from 'node:test'
import assert from 'node:assert/strict'

const dom = new JSDOM('<!doctype html><body></body>', {url: 'https://test.invalid/'})
for (const key of ['window', 'document', 'navigator', 'Node', 'HTMLElement', 'Element', 'MutationObserver', 'DOMParser', 'getComputedStyle']) {
  Object.defineProperty(globalThis, key, {value: key === 'getComputedStyle' ? dom.window.getComputedStyle.bind(dom.window) : dom.window[key], configurable: true})
}
globalThis.requestAnimationFrame = callback => setTimeout(callback, 0)
globalThis.cancelAnimationFrame = clearTimeout
const {createEditor, validateMarkdown, canonicalDocument} = await import('../src/schema.js')

function typeText(editor, text) {
  for (const character of text) {
    const {from, to} = editor.state.selection
    const handled = editor.view.someProp('handleTextInput', handler => handler(editor.view, from, to, character))
    if (!handled) editor.view.dispatch(editor.state.tr.insertText(character, from, to))
  }
}

test('typing standard inline dollars renders math beside Chinese text and saves editable LaTeX', () => {
  const editor = createEditor(document.createElement('div'))
  try {
    typeText(editor, '公式$x^2$和$E=mc^2$')
    assert.equal(editor.view.dom.querySelectorAll('[data-type="inline-math"] .katex').length, 2)
    assert.match(editor.getMarkdown(), /\$x\^2\$/)
    assert.match(editor.getMarkdown(), /\$E=mc\^2\$/)
    assert.equal(editor.getText(), '公式和')
    const saved = editor.getMarkdown()
    editor.commands.setContent(validateMarkdown(editor, saved))
    assert.equal(editor.view.dom.querySelectorAll('.katex').length, 2)
  } finally { editor.destroy() }
})

test('typing double dollars creates a display equation with a safe Markdown round-trip', () => {
  const editor = createEditor(document.createElement('div'))
  try {
    typeText(editor, '$$x^2 + y^2 = z^2$$')
    assert.equal(editor.state.doc.firstChild.type.name, 'blockMath')
    assert.ok(editor.view.dom.querySelector('[data-type="block-math"] .katex-display'))
    editor.state.doc.check()
    assert.deepEqual(canonicalDocument(validateMarkdown(editor, editor.getMarkdown())), canonicalDocument(editor.getJSON()))
  } finally { editor.destroy() }
})

test('adjacent equations and following digits retain their math nodes after reopening', () => {
  for (const source of ['前$x$$y$后', '$x$2']) {
    const editor = createEditor(document.createElement('div'))
    try {
      typeText(editor, source)
      assert.deepEqual(canonicalDocument(validateMarkdown(editor, editor.getMarkdown())), canonicalDocument(editor.getJSON()))
    } finally { editor.destroy() }
  }
})

test('Chinese-adjacent inline formatting renders while typing', () => {
  for (const [source, selector, text] of [
    ['中文**粗体**', 'strong', '粗体'], ['中文*斜体*', 'em', '斜体'],
    ['中文==高亮==', 'mark', '高亮'], ['中文~~删除~~', 's', '删除'],
    ['中文`代码`', 'code', '代码'],
  ]) {
    const editor = createEditor(document.createElement('div'))
    try {
      typeText(editor, source)
      assert.equal(editor.view.dom.querySelector(selector)?.textContent, text, source)
      assert.equal(editor.getText(), '中文' + text)
      validateMarkdown(editor, editor.getMarkdown())
    } finally { editor.destroy() }
  }
})

test('unfinished, escaped and code-contained dollars remain literal during input', () => {
  for (const source of ['$x^2', '\\$x^2$', '`$x^2$`', '``$x^2$``', '$5 and $10']) {
    const editor = createEditor(document.createElement('div'))
    try {
      typeText(editor, source)
      assert.equal(editor.view.dom.querySelectorAll('.katex').length, 0, source)
    } finally { editor.destroy() }
  }
  const editor = createEditor(document.createElement('div'))
  try {
    editor.commands.setContent({type: 'doc', content: [{type: 'codeBlock', content: [{type: 'text', text: 'code '}]}]})
    editor.commands.setTextSelection(editor.state.doc.firstChild.nodeSize - 1)
    typeText(editor, '$x^2$')
    assert.equal(editor.view.dom.querySelectorAll('.katex').length, 0)
    assert.equal(editor.state.doc.firstChild.textContent, 'code $x^2$')
  } finally { editor.destroy() }
})

test('typed equations preserve escaped dollars inside LaTeX across reopening', () => {
  const editor = createEditor(document.createElement('div'))
  try {
    typeText(editor, '$\\text{price: \\$5}$')
    assert.equal(editor.state.doc.firstChild.firstChild.attrs.latex, '\\text{price: \\$5}')
    const parsed = validateMarkdown(editor, editor.getMarkdown())
    assert.deepEqual(canonicalDocument(parsed), canonicalDocument(editor.getJSON()))
  } finally { editor.destroy() }
})

test('math conversion can be undone and redone', () => {
  const editor = createEditor(document.createElement('div'))
  try {
    typeText(editor, '$x^2$')
    assert.equal(editor.view.dom.querySelectorAll('.katex').length, 1)
    editor.commands.undo()
    assert.equal(editor.getText(), '$x^2$')
    editor.commands.redo()
    assert.equal(editor.view.dom.querySelectorAll('.katex').length, 1)
  } finally { editor.destroy() }
})

test('IME composition defers math rendering until committed', async () => {
  const editor = createEditor(document.createElement('div'))
  try {
    editor.view.dom.dispatchEvent(new dom.window.CompositionEvent('compositionstart', {bubbles: true}))
    typeText(editor, '公式$x^2$')
    assert.equal(editor.view.dom.querySelectorAll('.katex').length, 0)
    editor.view.dom.dispatchEvent(new dom.window.CompositionEvent('compositionend', {bubbles: true}))
    await new Promise(resolve => setTimeout(resolve, 30))
    assert.equal(editor.view.dom.querySelectorAll('.katex').length, 1)
  } finally { editor.destroy() }
})

test('plain Markdown paste renders inline syntax at the caret with undo and redo', () => {
  const editor = createEditor(document.createElement('div'))
  try {
    typeText(editor, '前文 ')
    const event = {clipboardData: {getData: type => type === 'text/plain' ? '$x^2$ **粗体** 和 *斜体*' : ''}}
    const handled = editor.view.someProp('handlePaste', handler => handler(editor.view, event))
    assert.equal(handled, true)
    assert.equal(editor.state.doc.childCount, 1)
    assert.ok(editor.getText().startsWith('前文 '))
    assert.ok(editor.view.dom.querySelector('.katex'))
    assert.equal(editor.view.dom.querySelector('strong')?.textContent, '粗体')
    assert.equal(editor.view.dom.querySelector('em')?.textContent, '斜体')
    validateMarkdown(editor, editor.getMarkdown())
    editor.commands.undo()
    assert.equal(editor.getText(), '前文 ')
    editor.commands.redo()
    assert.ok(editor.view.dom.querySelector('.katex'))
  } finally { editor.destroy() }
})

test('Markdown paste defers rich HTML and code-context paste to the native editor', () => {
  const editor = createEditor(document.createElement('div'))
  try {
    const html = {clipboardData: {getData: type => type === 'text/html' ? '<b>rich content</b>' : type === 'text/plain' ? '$x$' : ''}}
    assert.ok(!editor.view.someProp('handlePaste', handler => handler(editor.view, html)))
    editor.commands.setContent({type: 'doc', content: [{type: 'codeBlock', content: [{type: 'text', text: 'code '}]}]})
    editor.commands.setTextSelection(editor.state.doc.firstChild.nodeSize - 1)
    const plain = {clipboardData: {getData: type => type === 'text/plain' ? '$x^2$' : ''}}
    assert.ok(!editor.view.someProp('handlePaste', handler => handler(editor.view, plain)))
    assert.equal(editor.view.dom.querySelectorAll('.katex').length, 0)
    editor.commands.setContent('Read-only note')
    editor.setEditable(false)
    assert.ok(!editor.view.someProp('handlePaste', handler => handler(editor.view, plain)))
    assert.equal(editor.getText(), 'Read-only note')
  } finally { editor.destroy() }
})
