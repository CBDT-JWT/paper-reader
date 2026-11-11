import { build } from 'esbuild'
import { mkdir, readdir, readFile, writeFile, unlink } from 'node:fs/promises'
import path from 'node:path'
const outdir = new URL('../Sources/PaperReader/Resources/Editor/', import.meta.url).pathname
await mkdir(outdir, {recursive: true})
const result = await build({entryPoints: ['src/editor.js', 'src/conversation.js'], outdir, write: false, bundle: true, minify: true, target: 'safari17',
  loader: {'.woff': 'file', '.woff2': 'file', '.ttf': 'file'}, assetNames: 'fonts/[name]-[hash]', legalComments: 'eof'})
const expected = new Set(result.outputFiles.map(file => file.path))
async function publish(file, value) {
  expected.add(file)
  const contents = typeof value === 'string' ? Buffer.from(value) : value
  try {
    if ((await readFile(file)).equals(contents)) return
  } catch (error) {
    if (error.code !== 'ENOENT') throw error
  }
  await mkdir(path.dirname(file), {recursive: true})
  await writeFile(file, contents)
}
for (const file of result.outputFiles) await publish(file.path, file.contents)
await publish(path.join(outdir, 'index.html'), await readFile('index.html'))
await publish(path.join(outdir, 'conversation.html'), await readFile('conversation.html'))
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
await publish(path.join(outdir, 'THIRD-PARTY-NOTICES.txt'), licenses)
// Keep the resource directory and unchanged file identities stable in synced workspaces.
// Remove obsolete generated output individually after publishing the complete build.
async function removeStale(dir) {
  for (const item of await readdir(dir, {withFileTypes: true})) {
    const file = path.join(dir, item.name)
    if (item.isDirectory()) await removeStale(file)
    else if (!expected.has(file)) await unlink(file)
  }
}
await removeStale(outdir)
console.log('Offline editor built, including KaTeX fonts and license notices.')
