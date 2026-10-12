// Validate the shipped font, rather than the full SDK font used by widget tests.
import { readFile, readdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const project = fileURLToPath(new URL('../', import.meta.url));
const bundle = path.resolve(project, process.argv[2] ?? 'build/windows/x64/runner/Release');
const configUrl = new URL('../.dart_tool/package_config.json', import.meta.url);
const config = JSON.parse(await readFile(configUrl, 'utf8'));
const flutter = config.packages.find(p => p.name === 'flutter');
const sdkIcons = await readFile(new URL('lib/src/material/icons.dart',
  new URL(flutter.rootUri.endsWith('/') ? flutter.rootUri : flutter.rootUri + '/', configUrl)), 'utf8');
const codes = new Map([...sdkIcons.matchAll(/static const IconData (\w+) = IconData\(\s*0x([0-9a-f]+)/g)]
  .map(([, name, code]) => [name, parseInt(code, 16)]));

async function dartFiles(directory) {
  const result = [];
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const fullPath = path.join(directory, entry.name);
    if (entry.isDirectory()) result.push(...await dartFiles(fullPath));
    else if (entry.name.endsWith('.dart')) result.push(fullPath);
  }
  return result;
}

function hasGlyph(data, code) {
  const u16 = p => data.readUInt16BE(p);
  const u32 = p => data.readUInt32BE(p);
  let cmap;
  for (let p = 12; p < 12 + 16 * u16(4); p += 16) {
    if (data.toString('ascii', p, p + 4) === 'cmap') cmap = u32(p + 8);
  }
  if (cmap === undefined) throw new Error('Icon font has no character map');
  for (let p = cmap + 4; p < cmap + 4 + 8 * u16(cmap + 2); p += 8) {
    const start = cmap + u32(p + 4);
    if (u16(start) === 4) {
      const count = u16(start + 6) / 2;
      const ends = start + 14;
      const starts = ends + count * 2 + 2;
      const deltas = starts + count * 2;
      const offsets = deltas + count * 2;
      for (let i = 0; i < count; i++) {
        const low = u16(starts + i * 2), high = u16(ends + i * 2);
        if (code < low || code > high) continue;
        const delta = u16(deltas + i * 2), offset = u16(offsets + i * 2);
        const glyph = offset === 0 ? code : u16(offsets + i * 2 + offset + 2 * (code - low));
        if ((offset === 0 || glyph !== 0) && ((glyph + delta) & 0xffff) !== 0) return true;
      }
    } else if (u16(start) === 12) {
      for (let group = start + 16; group < start + 16 + 12 * u32(start + 12); group += 12) {
        const low = u32(group), high = u32(group + 4), glyph = u32(group + 8);
        if (low <= code && code <= high && glyph + code - low !== 0) return true;
      }
    }
  }
  return false;
}

const names = new Set();
for (const file of await dartFiles(path.join(project, 'lib'))) {
  for (const [, name] of (await readFile(file, 'utf8')).matchAll(/\bIcons\.(\w+)/g)) names.add(name);
}
const font = await readFile(path.join(bundle, 'data/flutter_assets/fonts/MaterialIcons-Regular.otf'));
const missing = [...names].filter(name => !codes.has(name) || !hasGlyph(font, codes.get(name)));
if (missing.length > 0) {
  console.error('MISSING from Windows icon font: ' + missing.join(', '));
  process.exitCode = 1;
} else {
  console.log(`PASS: all ${names.size} Material icons used by the app exist in the Windows bundle.`);
}
