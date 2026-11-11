import { generateHTML } from '@tiptap/core'

// Reuse the note schema and Markdown parser. Serialization only emits supported
// nodes and attributes, so model output cannot introduce scripts or event handlers.
export function messageHTML(parser, markdown) {
  return generateHTML(parser.markdown.parse(markdown), parser.extensionManager.extensions)
}
