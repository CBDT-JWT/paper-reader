import { Extension } from '@tiptap/core'
import { Plugin } from '@tiptap/pm/state'
import { Slice } from '@tiptap/pm/model'
import { closeHistory } from '@tiptap/pm/history'
import { validateMarkdown } from './markdown-validation.js'

export const MarkdownPaste = Extension.create({
  name: 'markdownPaste',
  priority: 1100,
  addProseMirrorPlugins() {
    return [new Plugin({
      props: {
        handlePaste: (view, event) => {
          const clipboard = event.clipboardData
          const hasHTML = clipboard?.getData('text/html').trim()
          const hasCodeMetadata = clipboard?.getData('vscode-editor-data')
          if (!this.editor.isEditable || view.composing || hasHTML || hasCodeMetadata) return false
          const text = clipboard?.getData('text/plain')
          const marks = view.state.storedMarks ?? view.state.selection.$from.marks()
          if (!text || view.state.selection.$from.parent.type.spec.code || marks.some(mark => mark.type.spec.code)) return false
          let parsedDocument
          try {
            parsedDocument = view.state.schema.nodeFromJSON(validateMarkdown(this.editor, text))
            parsedDocument.check()
          } catch { return false }
          view.dispatch(closeHistory(view.state.tr))
          const transaction = view.state.tr.replaceSelection(Slice.maxOpen(parsedDocument.content))
            .setMeta('paste', true).setMeta('uiEvent', 'paste').scrollIntoView()
          view.dispatch(transaction)
          view.dispatch(closeHistory(view.state.tr))
          return true
        },
      },
    })]
  },
})
