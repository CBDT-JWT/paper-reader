import { JSDOM } from 'jsdom'
import { build } from 'esbuild'
import { readFile } from 'node:fs/promises'
import test from 'node:test'
import assert from 'node:assert/strict'

const html = await readFile(new URL('../index.html', import.meta.url), 'utf8')
const bundle = await build({
  entryPoints: [new URL('../src/editor.js', import.meta.url).pathname],
  bundle: true, write: false, format: 'iife', loader: {'.css': 'empty'},
})

test('native editor bridge reloads an unfinished list and recovers from rejected Markdown', () => {
  const dom = new JSDOM(html, {url: 'https://test.invalid/?lang=zh', runScripts: 'outside-only', pretendToBeVisual: true})
  try {
    dom.window.structuredClone = structuredClone
    dom.window.eval(bundle.outputFiles[0].text)
    const api = dom.window.paperEditor
    const markdown = '### Problem Formulation\n\n输入与任务。\n\n1. 尺寸不同的时候性能差\n2. \n\n'
    const payload = {id: 'workspace', markdown, shared: true}
    const loaded = api.setDocument(payload)
    assert.equal(loaded.ok, true, loaded.error)
    assert.equal(dom.window.document.querySelector('.tiptap h3').textContent, 'Problem Formulation')
    assert.equal(dom.window.document.querySelectorAll('.tiptap ol li').length, 2)
    assert.equal(dom.window.document.querySelector('#unsupported').hidden, true)
    const saved = api.snapshot().markdown
    assert.equal(api.setDocument({...payload, markdown: saved}).ok, true)
    assert.equal(api.snapshot().markdown, saved)

    const unsupported = '<iframe src="https://example.org"></iframe>'
    assert.equal(api.setDocument({...payload, markdown: unsupported}).ok, false)
    assert.equal(api.snapshot(), null)
    assert.equal(api.format('bold'), false)
    assert.equal(dom.window.document.querySelector('#unsupported-source').textContent, unsupported)
    assert.equal(dom.window.document.querySelector('#editor').hidden, true)
    assert.equal(api.setDocument(payload).ok, true)
    assert.equal(api.validate(api.getMarkdown()).ok, true)

    api.clearDocument()
    assert.equal(api.setDocument({...payload, markdown: ''}).ok, true)
    assert.equal(api.diagnostics().editable, true)
    assert.equal(api.insertMarkdown('1. First\n2. '), true)
    assert.equal(api.validate(api.snapshot().markdown).ok, true)
  } finally {
    dom.window.document.querySelector('.tiptap')?.editor?.destroy()
    dom.window.close()
  }
})
