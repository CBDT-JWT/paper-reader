import { InputRule, markInputRule } from '@tiptap/core'
import StarterKit from '@tiptap/starter-kit'
import Highlight from '@tiptap/extension-highlight'
import { Mathematics } from '@tiptap/extension-mathematics'

function escapedAt(text, position) {
  let slashes = 0
  while (position > 0 && text[--position] === '\\') slashes++
  return slashes % 2 === 1
}

function insideCodeSpan(text, end) {
  let delimiter = 0
  for (let index = 0; index < end; index++) {
    if (text[index] !== '`' || (!delimiter && escapedAt(text, index))) continue
    let length = 1
    while (text[index + length] === '`') length++
    if (!delimiter) delimiter = length
    else if (delimiter === length) delimiter = 0
    index += length - 1
  }
  return delimiter !== 0
}

function mathToken(source, delimiter) {
  if (!source.startsWith(delimiter) || source[delimiter.length] === '$') return null
  for (let end = delimiter.length; end < source.length; end++) {
    if (delimiter === '$' && source[end] === '\n') return null
    if (!source.startsWith(delimiter, end) || escapedAt(source, end)) continue
    if (delimiter === '$$' && source[end + delimiter.length] === '$') return null
    const latex = source.slice(delimiter.length, end).trim()
    if (!latex) return null
    return {type: delimiter === '$' ? 'inlineMath' : 'blockMath', raw: source.slice(0, end + delimiter.length), latex}
  }
  return null
}

function inlineInput(text) {
  if (!text.endsWith('$') || escapedAt(text, text.length - 1) || text.endsWith('$$')) return null
  for (let start = text.length - 2; start >= 0; start--) {
    if (text[start] !== '$' || escapedAt(text, start)) continue
    if (text[start - 1] === '$' || insideCodeSpan(text, start)) return null
    const token = mathToken(text.slice(start), '$')
    if (!token || token.raw.length !== text.length - start || /^\s|\s$/.test(token.raw.slice(1, -1))) return null
    return {index: start, text: token.raw, data: {latex: token.latex}}
  }
  return null
}

const inlineMathConfiguration = {
  markdownTokenizer: {
    name: 'inlineMath', level: 'inline',
    start: source => source.indexOf('$'),
    tokenize: source => mathToken(source, '$') ?? undefined,
  },
  addInputRules() {
    return [new InputRule({
      find: inlineInput,
      handler: ({state, range, match}) => {
        state.tr.replaceWith(range.from, range.to, this.type.create({latex: match.data.latex}))
      },
    })]
  },
}

const blockMathConfiguration = {
  markdownTokenizer: {
    name: 'blockMath', level: 'block',
    // Marked probes paragraph interruptions after slicing off one character.
    // Require an actual newline so adjacent $x$$y$ stays in one paragraph.
    start: source => {
      const match = /\n {0,3}\$\$/.exec(source)
      return match ? match.index + 1 : -1
    },
    tokenize: source => {
      const indent = source.match(/^ {0,3}/)[0]
      const token = mathToken(source.slice(indent.length), '$$')
      return token ? {...token, raw: indent + token.raw} : undefined
    },
  },
  addInputRules() {
    const standard = new InputRule({
      find: text => {
        const token = mathToken(text, '$$')
        return token?.raw.length === text.length ? {index: 0, text, data: {latex: token.latex}} : null
      },
      handler: ({state, range, match}) => {
        const position = state.doc.resolve(range.from)
        const wholeParagraph = range.from === position.start() && range.to === position.end()
        const replaceParagraph = wholeParagraph && position.node(-1).canReplaceWith(position.index(-1), position.indexAfter(-1), this.type)
        const from = replaceParagraph ? position.before() : range.from
        const to = replaceParagraph ? position.after() : range.to
        state.tr.replaceWith(from, to, this.type.create({latex: match.data.latex}))
      },
    })
    return [standard, ...this.parent()]
  },
}

export const NoteMathematics = Mathematics.extend({
  addExtensions() {
    return this.parent().map(extension => {
      const configuration = extension.name === 'inlineMath' ? inlineMathConfiguration : blockMathConfiguration
      return extension.extend(configuration).configure({
        katexOptions: {...extension.options.katexOptions, displayMode: extension.name === 'blockMath'},
      })
    })
  },
})

const markPatterns = {
  bold: [/\*\*([^*\n]+)\*\*$/, /__([^_\n]+)__$/],
  italic: [/\*([^*\n]+)\*$/, /_([^_\n]+)_$/],
  strike: [/~~([^~\n]+)~~$/],
  highlight: [/==([^=\n]+)==$/],
}

function markInput(text, pattern, name) {
  const match = pattern.exec(text)
  const closingWidth = name === 'italic' ? 1 : 2
  if (!match || /^\s|\s$/.test(match[1])) return null
  if (escapedAt(text, match.index) || escapedAt(text, text.length - closingWidth)) return null
  if (insideCodeSpan(text, match.index)) return null
  const previous = text[match.index - 1]
  if (previous === match[0][0]) return null
  if (match[0][0] === '_' && previous && /[\p{L}\p{N}]/u.test(previous)) return null
  return {index: match.index, text: match[0], replaceWith: match[1]}
}

function liveMark(extension) {
  const patterns = markPatterns[extension.name]
  if (!patterns) return extension
  return extension.extend({
    addInputRules() {
      return patterns.map(pattern => markInputRule({
        type: this.type,
        find: text => markInput(text, pattern, extension.name),
      }))
    },
  })
}

export const NoteStarterKit = StarterKit.extend({addExtensions() { return this.parent().map(liveMark) }})
export const NoteHighlight = liveMark(Highlight)
