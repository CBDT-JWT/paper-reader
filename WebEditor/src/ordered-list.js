import { OrderedList } from '@tiptap/extension-list'

export const NoteOrderedList = OrderedList.extend({
  parseMarkdown(token, helpers) {
    const parsed = this.parent(token, helpers)
    // Tiptap 3.33's ordered-list parser bypasses ListItem's leading-paragraph
    // handling. Empty items (e.g. a note ending in "2. ") then crash serialization.
    // Normalize at the extension boundary so loading, pasting and insertion agree.
    for (const item of parsed.content ?? []) {
      if (item.type === 'listItem' && item.content?.[0]?.type !== 'paragraph') {
        item.content = [{type: 'paragraph', content: []}, ...(item.content ?? [])]
      }
    }
    return parsed
  },
})
