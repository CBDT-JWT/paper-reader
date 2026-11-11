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

window.conversation = {
  render({messages, generating}) {
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
        article.append(heading, content)
        transcript.append(article)
        node = {article, content, markdown: null}
        nodes.set(message.id, node)
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
    if (follow) requestAnimationFrame(() => window.scrollTo(0, document.documentElement.scrollHeight))
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
post({type: 'ready'})
