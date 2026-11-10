import Image from '@tiptap/extension-image'
// Dimensions remain portable Markdown: stored in the optional image title, never as a hidden JSON-only attribute.
export const ResearchImage = Image.extend({
  parseMarkdown(token, helpers) {
    const match = (token.title || '').match(/^(.*?)(?:\s*\{width=(\d+)\})$/)
    return helpers.createNode('image', {src: token.href, alt: token.text, title: match ? match[1] || null : token.title || null,
      width: match ? Number(match[2]) : null, height: null})
  },
  renderMarkdown(node) {
    const {src = '', alt = '', width, title} = node.attrs || {}
    const description = [title || '', width ? `{width=${Math.round(Number(width))}}` : ''].filter(Boolean).join(' ')
    return `![${alt}](${src}${description ? ` "${description.replace(/"/g, '\\"')}"` : ''})`
  },
}).configure({resize: {enabled: true, directions: ['bottom-left', 'bottom-right'], minWidth: 80, minHeight: 30, alwaysPreserveAspectRatio: true}})
