export const language = typeof window !== 'undefined' && window.location?.search.includes('lang=zh') ? 'zh-Hans' : 'en'
const messages = {
  '编辑 LaTeX 公式': 'Edit LaTeX equation', '取消': 'Cancel', '应用公式': 'Apply equation',
  '论文 Markdown 笔记': 'Paper Markdown note',
  '暂不支持 YAML、原始 HTML 或脚注。原文件保持完整，请先转换这些语法。': 'YAML, raw HTML, and footnotes are not supported yet. Your original file is preserved. Convert this syntax before importing.',
  '这份 Markdown 无法安全往返转换。原文件保持完整，请使用其他编辑器处理。': 'This Markdown cannot be safely round-tripped. Your original file is preserved. Use another editor to process it.',
  '编辑源码': 'Edit source', '显示图表': 'Show diagram', '图表语法错误，源码已保留。': 'Diagram syntax error. The source is preserved.',
  '只读笔记': 'Read-only note', '任务': 'Task', '空白任务': 'Empty task',
}
export const t = text => language === 'zh-Hans' ? text : messages[text] ?? text
