import { t } from './localization.js'
import { Editor, Extension } from '@tiptap/core'
import { Markdown } from '@tiptap/markdown'
import { NoteStarterKit, NoteMathematics, NoteHighlight } from './live-markdown.js'
import { ResearchImage } from './research-image.js'
import { DiagramCodeBlock } from './diagram.js'
import { TableKit } from '@tiptap/extension-table'
import TaskList from '@tiptap/extension-task-list'
import TaskItem from '@tiptap/extension-task-item'
import { NoteOrderedList } from './ordered-list.js'
import { MarkdownPaste } from './markdown-paste.js'
export { validateMarkdown, canonicalDocument } from './markdown-validation.js'

export function extensions(onMath = () => {}) {
  return [
    NoteStarterKit.configure({codeBlock: false, orderedList: false, link: {openOnClick: false, protocols: ['paperreader']}}),
    NoteOrderedList,
    Markdown.configure({indentation: {style: 'space', size: 2}}),
    MarkdownPaste,
    NoteHighlight, ResearchImage, DiagramCodeBlock,
    TableKit.configure({table: {resizable: false}}), TaskList, TaskItem.configure({nested: true, a11y: {checkboxLabel: node => `${t('任务')}: ${node.textContent || t('空白任务')}`}}),
    NoteMathematics.configure({
      katexOptions: {throwOnError: false, trust: false, strict: 'warn'},
      inlineOptions: {onClick: (node, pos) => onMath(node, pos, false)},
      blockOptions: {onClick: (node, pos) => onMath(node, pos, true)},
    }),
    Extension.create({
      name: 'listIndentation',
      addKeyboardShortcuts() {
        return {
          Tab: () => this.editor.commands.sinkListItem('listItem') || this.editor.commands.sinkListItem('taskItem'),
          'Shift-Tab': () => this.editor.commands.liftListItem('listItem') || this.editor.commands.liftListItem('taskItem'),
        }
      },
    }),
  ]
}

export function createEditor(element, options = {}) {
  return new Editor({element, extensions: extensions(options.onMath), content: '',
    editorProps: {attributes: {'aria-label': t('论文 Markdown 笔记'), spellcheck: 'false'}}, ...options})
}
