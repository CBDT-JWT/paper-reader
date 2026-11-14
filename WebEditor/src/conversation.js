import { createEditor } from './schema.js'
import { messageHTML } from './message-markdown.js'
import katex from 'katex'
import 'katex/dist/katex.min.css'
import './style.css'
import './conversation.css'

const parser = createEditor(document.createElement('div'), {editable: false})
const transcript = document.querySelector('#transcript')
const nodes = new Map()
const post = value => window.webkit?.messageHandlers.conversation.postMessage(value)
document.documentElement.lang = location.search.includes('lang=zh') ? 'zh-Hans' : 'en'
let lastRevealRequest = -1

window.conversation = {
  render({messages, generating, revealMessageID = '', revealRequest = 0}) {
    const follow = window.scrollY + innerHeight >= document.documentElement.scrollHeight - 90
    const ids = new Set(messages.map(message => message.id))
    for (const [id, node] of nodes) {
      if (!ids.has(id)) { node.article.remove(); nodes.delete(id) }
    }
    for (const message of messages) {
      let node = nodes.get(message.id)
      if (!node) {
        const article = document.createElement('article')
        const heading = document.createElement('header')
        const role = document.createElement('span')
        role.textContent = message.role === 'user' ? (document.documentElement.lang === 'en' ? 'You' : '你') : 'AI'
        const copy = document.createElement('button')
        copy.type = 'button'
        copy.textContent = document.documentElement.lang === 'en' ? 'Copy' : '复制'
        copy.addEventListener('click', () => post({type: 'copy', id: message.id}))
        heading.append(role, copy)
        const content = document.createElement('div')
        content.className = 'message-content'
        article.className = message.role === 'user' ? 'user-message' : 'assistant-message'
        article.dataset.id = message.id
        const quote = document.createElement('blockquote')
        quote.className = 'message-quote'
        quote.hidden = true
        article.append(heading, quote, content)
        transcript.append(article)
        node = {article, content, quote, quoteValue: null, markdown: null}
        nodes.set(message.id, node)
      }
      const quoteValue = JSON.stringify(message.quote ?? null)
      if (node.quoteValue !== quoteValue) {
        node.quoteValue = quoteValue
        node.quote.replaceChildren()
        node.quote.hidden = !message.quote
        if (message.quote) {
          const label = document.createElement(message.quote.link ? 'a' : 'span')
          label.textContent = message.quote.label
          if (message.quote.link) label.setAttribute('href', message.quote.link)
          const text = document.createElement('p')
          text.textContent = message.quote.text
          node.quote.append(label, text)
        }
      }
      if (node.markdown !== message.content) {
        // Preserve selected text elsewhere in the conversation during streaming.
        node.markdown = message.content
        try {
          node.content.innerHTML = messageHTML(parser, message.content)
          for (const element of node.content.querySelectorAll('[data-latex]')) {
            katex.render(element.dataset.latex, element, {displayMode: element.dataset.type === 'block-math', throwOnError: false, trust: false})
          }
        } catch {
          node.content.textContent = message.content
        }
      }
    }
    document.body.dataset.generating = String(generating)
    if (revealMessageID && revealRequest !== lastRevealRequest) {
      lastRevealRequest = revealRequest
      requestAnimationFrame(() => nodes.get(revealMessageID)?.article.scrollIntoView({block: 'center'}))
    } else if (follow) requestAnimationFrame(() => window.scrollTo(0, document.documentElement.scrollHeight))
    return true
  },
  diagnostics: () => ({messages: nodes.size, bold: !!transcript.querySelector('strong'), italic: !!transcript.querySelector('em'),
    table: !!transcript.querySelector('table'), math: !!transcript.querySelector('.katex'),
    boldWeight: transcript.querySelector('strong') && getComputedStyle(transcript.querySelector('strong')).fontWeight,
    italicStyle: transcript.querySelector('em') && getComputedStyle(transcript.querySelector('em')).fontStyle})
}
transcript.addEventListener('click', event => {
  const link = event.target.closest('a')
  if (link) { event.preventDefault(); post({type: 'link', url: link.getAttribute('href')}) }
})
const selectionTools = document.createElement('div')
selectionTools.className = 'selection-tools'
selectionTools.setAttribute('role', 'toolbar')
selectionTools.hidden = true
let selectedReply = null
for (const [action, english, chinese] of [['ask', 'Ask AI', '问 AI'], ['excerpt', 'Excerpt', '摘录']]) {
  const button = document.createElement('button')
  button.type = 'button'
  button.textContent = document.documentElement.lang === 'en' ? english : chinese
  button.addEventListener('mousedown', event => event.preventDefault())
  button.addEventListener('click', () => {
    if (selectedReply) post({type: 'selection', action, ...selectedReply})
    selectionTools.hidden = true
  })
  selectionTools.append(button)
}
document.body.append(selectionTools)
function selectionAction() {
  const selection = window.getSelection()
  const element = node => node?.nodeType === Node.ELEMENT_NODE ? node : node?.parentElement
  const start = element(selection?.anchorNode)?.closest('.assistant-message .message-content')
  const end = element(selection?.focusNode)?.closest('.assistant-message .message-content')
  const text = selection?.toString().trim()
  if (!start || start !== end || !text || !selection.rangeCount) {
    selectedReply = null
    selectionTools.hidden = true
    return
  }
  selectedReply = {id: start.closest('article').dataset.id, text}
  const rect = selection.getRangeAt(0).getBoundingClientRect()
  selectionTools.hidden = false
  const left = Math.max(8, Math.min(rect.left + rect.width / 2 - selectionTools.offsetWidth / 2, innerWidth - selectionTools.offsetWidth - 8))
  const top = rect.top > 44 ? rect.top - selectionTools.offsetHeight - 6 : rect.bottom + 6
  selectionTools.style.left = `${left}px`
  selectionTools.style.top = `${Math.max(8, Math.min(top, innerHeight - selectionTools.offsetHeight - 8))}px`
}
document.addEventListener('mouseup', event => { if (!selectionTools.contains(event.target)) requestAnimationFrame(selectionAction) })
document.addEventListener('keyup', event => { if (event.key === 'Escape') selectionTools.hidden = true; else selectionAction() })
document.addEventListener('mousedown', event => { if (!selectionTools.contains(event.target)) selectionTools.hidden = true })
window.addEventListener('scroll', () => { selectionTools.hidden = true }, {passive: true})
post({type: 'ready'})
