import { Editor, Extension } from '@tiptap/core'
import StarterKit from '@tiptap/starter-kit'
import { Markdown } from '@tiptap/markdown'
import { Mathematics } from '@tiptap/extension-mathematics'
import Highlight from '@tiptap/extension-highlight'
import Image from '@tiptap/extension-image'
import { TableKit } from '@tiptap/extension-table'
import TaskList from '@tiptap/extension-task-list'
import TaskItem from '@tiptap/extension-task-item'

export function extensions(onMath = () => {}) {
  return [
    StarterKit.configure({link: {openOnClick: false, protocols: ['paperreader']}}),
    Markdown.configure({indentation: {style: 'space', size: 2}}),
    Highlight, Image.configure({allowBase64: false}),
    TableKit.configure({table: {resizable: false}}), TaskList, TaskItem.configure({nested: true}),
    Mathematics.configure({
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

// Fail closed on syntax we cannot represent; caller retains original .md untouched.
export function validateMarkdown(editor, markdown) {
  const prose = markdown.replace(/^(`{3,}|~{3,})[^\n]*\n[\s\S]*?^\1[^\n]*$/gm, '').replace(/(`+)[\s\S]*?\1/g, '')
  if (/^---\s*\n/.test(markdown) || /<\/?[A-Za-z][^>]*>/.test(prose) || /^\[\^.+?\]:/m.test(prose)) {
    throw new Error('暂不支持 YAML、原始 HTML 或脚注。原文件保持完整，请先转换这些语法。')
  }
  const parsed = editor.markdown.parse(markdown)
  const serialized = editor.markdown.serialize(parsed)
  const reparsed = editor.markdown.parse(serialized)
  if (JSON.stringify(canonicalDocument(parsed)) !== JSON.stringify(canonicalDocument(reparsed))) {
    throw new Error('这份 Markdown 无法安全往返转换。原文件保持完整，请使用其他编辑器处理。')
  }
  return parsed
}

export function createEditor(element, options = {}) {
  return new Editor({element, extensions: extensions(options.onMath), content: '',
    editorProps: {attributes: {'aria-label': '论文 Markdown 笔记', spellcheck: 'false'}}, ...options})
}

// Markdown has no representation for an editor-only empty trailing paragraph.
export function canonicalDocument(json) {
  const copy = structuredClone(json)
  while (copy.content?.at(-1)?.type === 'paragraph' && !copy.content.at(-1).content?.length) copy.content.pop()
  return copy
}
