import { build } from 'esbuild'
import { mkdir, copyFile, readdir, readFile, writeFile, rm } from 'node:fs/promises'
import path from 'node:path'
const outdir = new URL('../Sources/PaperReader/Resources/Editor/', import.meta.url).pathname
await rm(outdir, {recursive: true, force: true})
await mkdir(outdir, {recursive: true})
await build({entryPoints: ['src/editor.js', 'src/conversation.js'], outdir, bundle: true, minify: true, target: 'safari17',
  loader: {'.woff': 'file', '.woff2': 'file', '.ttf': 'file'}, assetNames: 'fonts/[name]-[hash]', legalComments: 'eof'})
await copyFile('index.html', path.join(outdir, 'index.html'))
await copyFile('conversation.html', path.join(outdir, 'conversation.html'))
// Include all transitive dependency licenses in the shipped app.
let licenses = 'THIRD-PARTY SOFTWARE NOTICES\n\n'
async function walk(dir) {
  for (const item of await readdir(dir, {withFileTypes: true})) {
    if (!item.isDirectory() || item.name.startsWith('.')) continue
    const full = path.join(dir, item.name)
    if (item.name.startsWith('@')) { await walk(full); continue }
    let pkg
    try { pkg = JSON.parse(await readFile(path.join(full, 'package.json'), 'utf8')) } catch { continue }
    licenses += `\n=== ${pkg.name} ${pkg.version} (${pkg.license}) ===\n`
    for (const name of ['LICENSE', 'LICENSE.md', 'LICENSE.txt', 'LICENSE-MIT', 'License.txt', 'license']) {
      try { licenses += await readFile(path.join(full, name), 'utf8'); break } catch {}
    }
  }
}
await walk('node_modules')
await writeFile(path.join(outdir, 'THIRD-PARTY-NOTICES.txt'), licenses)
console.log('Offline editor built, including KaTeX fonts and license notices.')
