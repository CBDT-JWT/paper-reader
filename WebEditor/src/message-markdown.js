import { getHTMLFromFragment } from '@tiptap/core'

// Reuse the note schema and Markdown parser. Serialization only emits supported
// nodes and attributes, so model output cannot introduce scripts or event handlers.
export function messageHTML(parser, markdown) {
  const document = parser.schema.nodeFromJSON(parser.markdown.parse(markdown))
  return getHTMLFromFragment(document.content, parser.schema)
}
