import { readFile, readdir, access } from 'node:fs/promises';
import path from 'node:path';

const bundle = path.resolve(process.argv[2] ?? 'build/windows/x64/runner/Release');
const entries = await readdir(bundle);
const files = new Set(entries.map(name => name.toLowerCase()));
const missing = new Set();
let checked = 0;
// Inno Setup adds its own 32-bit uninstaller after installation. Check Ledgy's
// x64 payload; the compiler-provided uninstaller runs separately.
for (const name of entries.filter(name => /\.(exe|dll)$/i.test(name) && !/^unins\d+\.exe$/i.test(name))) {
  const data = await readFile(path.join(bundle, name));
  const pe = data.readUInt32LE(0x3c);
  if (data.readUInt32LE(pe) !== 0x4550 || data.readUInt16LE(pe + 4) !== 0x8664) {
    throw new Error(`Not an x64 PE binary: ${name}`);
  }
  const sections = data.readUInt16LE(pe + 6);
  const optional = pe + 24;
  const table = optional + data.readUInt16LE(pe + 20);
  function offset(rva) {
    for (let i = 0; i < sections; i++) {
      const section = table + i * 40;
      const start = data.readUInt32LE(section + 12);
      const size = Math.max(data.readUInt32LE(section + 8), data.readUInt32LE(section + 16));
      if (start <= rva && rva < start + size) return data.readUInt32LE(section + 20) + rva - start;
    }
    throw new Error(`Invalid import address in ${name}`);
  }
  const imports = data.readUInt32LE(optional + 112 + 8);
  if (imports === 0) continue;
  for (let entry = offset(imports); data.readUInt32LE(entry + 12) !== 0; entry += 20) {
    const start = offset(data.readUInt32LE(entry + 12));
    const dependency = data.toString('ascii', start, data.indexOf(0, start)).toLowerCase();
    if (files.has(dependency) || /^(api-ms-|ext-ms-)/.test(dependency)) continue;
    // MSVC runtimes must be app-local, even when already installed on this PC.
    if (/^(msvcp|vcruntime|concrt|vccorlib|vcomp)\d/.test(dependency)) {
      missing.add(dependency);
      continue;
    }
    try {
      await access(path.join(process.env.SystemRoot, 'System32', dependency));
    } catch {
      missing.add(dependency);
    }
  }
  checked++;
}
if (missing.size > 0) throw new Error('Missing dependencies: ' + [...missing].join(', '));
console.log(`PASS: dependencies of ${checked} x64 binaries resolve to the bundle or Windows system APIs.`);
