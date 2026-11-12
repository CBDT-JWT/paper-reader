import { t, language } from './localization.js'
import { closeHistory } from '@tiptap/pm/history'
import { createEditor, validateMarkdown } from './schema.js'
import 'katex/dist/katex.min.css'
import './style.css'

document.documentElement.lang = language
for (const selector of ['#math-form label', '#math-cancel', '#math-form button[type=submit]']) { const node = document.querySelector(selector); node.textContent = t(node.textContent) }
let editor, paperID = null, loading = false, baselineMarkdown = ""
const host = document.querySelector('#editor')
const post = payload => window.webkit?.messageHandlers?.editor?.postMessage(payload)
window.addEventListener('error', event => post({type: 'error', message: event.message}))
let mathTarget = null
const mathPanel = document.querySelector('#math-panel')
const mathInput = document.querySelector('#math-input')
function showMath(node, pos, block) {
  mathTarget = {pos, block, selection: editor.state.selection.from}
  mathInput.value = node?.attrs.latex || ''
  mathPanel.hidden = false
  mathInput.focus()
}
function closeMath() { mathPanel.hidden = true; editor?.commands.focus() }
document.querySelector('#math-cancel').addEventListener('click', closeMath)
document.querySelector('#math-form').addEventListener('submit', event => {
  event.preventDefault()
  const latex = mathInput.value.trim()
  if (!latex || !mathTarget) return
  const {pos, block, selection} = mathTarget
  const chain = editor.chain().focus()
  if (pos != null) {
    chain.setNodeSelection(pos)
    block ? chain.updateBlockMath({latex, pos}).run() : chain.updateInlineMath({latex, pos}).run()
  } else {
    chain.setTextSelection(selection)
    block ? chain.insertBlockMath({latex, pos: selection}).run() : chain.insertInlineMath({latex, pos: selection}).run()
  }
  closeMath()
})
mathInput.addEventListener('keydown', event => {
  if (event.key === 'Escape') { event.preventDefault(); closeMath() }
})
function changed() {
  if (paperID && !loading) post({type: 'change', paperID, markdown: editor.getMarkdown()})
}
function makeEditor(content = '') {
  editor?.destroy()
  host.replaceChildren()
  editor = createEditor(host, {content, onMath: showMath, onUpdate: changed})
}
makeEditor()

// Navigation is mediated by native code, including source links. No arbitrary JS URLs.
document.addEventListener('click', event => {
  const image = event.target.closest('.tiptap img')
  if (image) {
    const source = image.closest('p')?.nextElementSibling?.querySelector('a[href^="paperreader://document?"]')
    post({type: 'link', url: source?.getAttribute('href') || `paperreader://asset?path=${encodeURIComponent(image.getAttribute('src'))}`})
  }
  const link = event.target.closest('a')
  if (link) {
    event.preventDefault()
    post({type: 'link', url: link.getAttribute('href')})
  }
})
document.addEventListener('drop', event => { event.preventDefault() })

window.paperEditor = {
  clearDocument() { loading = true; paperID = null; makeEditor(); editor.setEditable(false); loading = false; return true },
  rebindDocument(id) {
    if (!paperID) return null
    paperID = id
    document.querySelector('base').href = `paperreader-resource://paper/${paperID}/`
    return editor.getMarkdown()
  },
  setDocument(payload) {
    try {
      const parsed = validateMarkdown(editor, payload.markdown)
      loading = true
      paperID = payload.id
      document.querySelector('base').href = `paperreader-resource://paper/${paperID}/`
      // A shared workspace note keeps its selection and undo history across PDF switches.
      if (!payload.shared || editor.getMarkdown() !== payload.markdown) makeEditor(parsed)
      document.querySelector('#unsupported').hidden = true
      host.hidden = false
      mathPanel.hidden = true
      baselineMarkdown = editor.getMarkdown()
      loading = false
      return {ok: true}
    } catch (error) {
      paperID = null
      host.hidden = true
      const fallback = document.querySelector('#unsupported')
      fallback.hidden = false
      fallback.textContent = `${error.message}\n\n${payload.markdown}`
      loading = false
      return {ok: false, error: error.message}
    }
  },
  validate(markdown) {
    try { validateMarkdown(editor, markdown); return {ok: true} }
    catch (error) { return {ok: false, error: error.message} }
  },
  setReadOnly(value) { editor.setEditable(!value); return true },
  replaceMarkdown(payload) {
    if (paperID !== payload.id || editor.getMarkdown() !== payload.expected) return {ok: false}
    const content = validateMarkdown(editor, payload.markdown)
    editor.view.dispatch(closeHistory(editor.state.tr))
    editor.commands.setContent(content)
    editor.view.dispatch(closeHistory(editor.state.tr))
    return {ok: true}
  },
  inspectMarkdown(markdown) {
    const parsed = validateMarkdown(editor, markdown)
    const images = []
    function walk(node) {
      if (node.type === 'image') images.push(node.attrs.src)
      node.content?.forEach(walk)
    }
    walk(parsed)
    return {images: [...new Set(images)]}
  },
  rewriteImages(payload) {
    const parsed = validateMarkdown(editor, payload.markdown)
    function walk(node) {
      if (node.type === 'image' && payload.paths[node.attrs.src]) node.attrs.src = payload.paths[node.attrs.src]
      node.content?.forEach(walk)
    }
    walk(parsed)
    return editor.markdown.serialize(parsed)
  },
  insertMarkdown(markdown) {
    if (!paperID) return false
    return editor.chain().focus().insertContent(markdown, {contentType: 'markdown'}).run()
  },
  format(action) {
    const chain = editor.chain().focus()
    const commands = {
      bold: () => chain.toggleBold().run(), italic: () => chain.toggleItalic().run(),
      strike: () => chain.toggleStrike().run(), highlight: () => chain.toggleHighlight().run(),
      bullet: () => chain.toggleBulletList().run(), ordered: () => chain.toggleOrderedList().run(),
      task: () => chain.toggleTaskList().run(), quote: () => chain.toggleBlockquote().run(),
      code: () => chain.toggleCodeBlock().run(), inlineCode: () => chain.toggleCode().run(),
      h1: () => chain.toggleHeading({level: 1}).run(), h2: () => chain.toggleHeading({level: 2}).run(),
      h3: () => chain.toggleHeading({level: 3}).run(), table: () => chain.insertTable({rows: 3, cols: 3, withHeaderRow: true}).run(),
      math: () => showMath(null, null, false), blockMath: () => showMath(null, null, true),
      undo: () => chain.undo().run(), redo: () => chain.redo().run(),
    }
    return commands[action]?.() ?? false
  },
  getMarkdown: () => editor.getMarkdown(),
  markSaved(payload) {
    if (paperID === payload.id && editor.getMarkdown() === payload.markdown) baselineMarkdown = payload.markdown
    return true
  },
  snapshot: () => paperID ? {id: paperID, markdown: editor.getMarkdown(), baseline: baselineMarkdown} : null,
  // Only used by integration self-test; same public editor/transaction APIs as normal editing.
  diagnostics: () => ({paperID, json: editor.getJSON(), mathCount: document.querySelectorAll('.katex').length,
    diagramState: Array.from(document.querySelectorAll('.mermaid-diagram')).map(d => ({ready: d.dataset.ready || 'not-started', error: d.dataset.error || ''})),
    imageCount: document.querySelectorAll('.tiptap img').length, editable: editor.isEditable,
    text: editor.getText(), ready: document.readyState}),
}
post({type: 'ready'})
