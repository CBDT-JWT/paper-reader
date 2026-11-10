import CodeBlock from '@tiptap/extension-code-block'
import { t } from './localization.js'
let renderer
let sequence = 0
async function renderDiagram(text, target, token) {
  renderer ??= import('mermaid').then(module => {
    const mermaid = module.default
    mermaid.initialize({startOnLoad: false, securityLevel: 'strict', suppressErrorRendering: true,
      arrowMarkerAbsolute: true, maxTextSize: 30000, maxEdges: 400, theme: matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'neutral',
      fontFamily: '-apple-system, sans-serif', flowchart: {htmlLabels: false}})
    return mermaid
  })
  try {
    const mermaid = await renderer
    const {svg} = await mermaid.render(`paperdiagram${++sequence}`, text)
    if (target.dataset.token === String(token)) { target.innerHTML = svg; target.dataset.ready = 'true' }
  } catch (error) {
    target.dataset.error = String(error.message || error)
    if (target.dataset.token === String(token)) { target.textContent = t('图表语法错误，源码已保留。'); target.dataset.ready = 'error' }
  }
}
export const DiagramCodeBlock = CodeBlock.extend({
  addNodeView() {
    return ({node, editor, getPos}) => {
      let current = node, editing = false, version = 0
      const dom = document.createElement('div'), pre = document.createElement('pre'), code = document.createElement('code')
      const diagram = document.createElement('div'), button = document.createElement('button')
      pre.append(code); dom.append(diagram, button, pre); button.type = 'button'; button.contentEditable = 'false'; diagram.contentEditable = 'false'
      diagram.className = 'mermaid-diagram'; button.className = 'diagram-edit'
      function update() {
        const isDiagram = current.attrs.language === 'mermaid'
        dom.className = isDiagram ? 'diagram-block' : 'code-block'
        diagram.className = isDiagram ? 'mermaid-diagram' : 'code-preview-placeholder'
        diagram.hidden = !isDiagram || editing; button.hidden = !isDiagram; pre.hidden = isDiagram && !editing
        button.textContent = t(editing ? '显示图表' : '编辑源码')
        if (isDiagram && !editing && typeof SVGGraphicsElement !== 'undefined' && typeof SVGGraphicsElement.prototype.getBBox === 'function') { diagram.dataset.ready = 'loading'; diagram.dataset.token = String(++version); renderDiagram(current.textContent, diagram, version) }
      }
      button.addEventListener('click', () => {
        editing = !editing; update()
        if (editing && typeof getPos() === 'number') editor.chain().focus().setTextSelection(getPos() + 1).run()
      })
      update()
      return {dom, contentDOM: code, update(next) { if (next.type !== current.type) return false; const changed = next.textContent !== current.textContent || next.attrs.language !== current.attrs.language; current = next; if (changed) update(); return true },
        ignoreMutation: mutation => !pre.contains(mutation.target), stopEvent: event => button.contains(event.target) || diagram.contains(event.target), destroy: () => { diagram.dataset.token = 'destroyed' }}
    }
  },
})
