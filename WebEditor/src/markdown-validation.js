import { t } from './localization.js'

// Fail closed on syntax we cannot represent; caller retains original .md untouched.
export function validateMarkdown(editor, markdown) {
  const prose = markdown.replace(/^(`{3,}|~{3,})[^\n]*\n[\s\S]*?^\1[^\n]*$/gm, '').replace(/(`+)[\s\S]*?\1/g, '')
  if (/^---\s*\n/.test(markdown) || /<\/?[A-Za-z][^>]*>/.test(prose) || /^\[\^.+?\]:/m.test(prose)) {
    throw new Error(t('暂不支持 YAML、原始 HTML 或脚注。原文件保持完整，请先转换这些语法。'))
  }
  const parsed = editor.markdown.parse(markdown)
  const serialized = editor.markdown.serialize(parsed)
  const reparsed = editor.markdown.parse(serialized)
  if (JSON.stringify(canonicalDocument(parsed)) !== JSON.stringify(canonicalDocument(reparsed))) {
    throw new Error(t('这份 Markdown 无法安全往返转换。原文件保持完整，请使用其他编辑器处理。'))
  }
  return parsed
}

// Markdown has no representation for an editor-only empty trailing paragraph.
export function canonicalDocument(json) {
  const copy = structuredClone(json)
  while (copy.content?.at(-1)?.type === 'paragraph' && !copy.content.at(-1).content?.length) copy.content.pop()
  return copy
}
