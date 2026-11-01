// Real WASM module load/search/dispose soak. Run from repository root:
//   node tool/uci/frozenight_wasm_lifecycle.mjs [cycles]
// This exercises the delivered bridge/module, not a mock. Dart-side lease
// serialization is covered by the engine gate and source audit.
import '../../web/frozenight_bridge.js';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const web = join(dirname(fileURLToPath(import.meta.url)), '..', '..', 'web');
const wasmBytes = await readFile(join(web, 'frozenight_wasm_bg.wasm'));

const cycles = Number(process.argv[2] || 100);
if (!Number.isInteger(cycles) || cycles < 1 || cycles > 10000) {
  throw new Error('cycles must be 1..10000');
}
const start = Date.now();
let peak = 0;
for (let i = 0; i < cycles; i++) {
  await globalThis.frozenightLoad({ module_or_path: wasmBytes });
  globalThis.frozenightSetPosition('startpos', 'e2e4 e7e5');
  const result = globalThis.frozenightSearchBounded(3, 5000) || globalThis.frozenightSearch(3);
  const move = typeof result === 'string' ? result.trim().split(/\s+/, 1)[0] : result;
  if (typeof result !== 'string' || !/^[a-h][1-8][a-h][1-8][qrbn]?$/.test(move)) {
    throw new Error(`bad move at cycle ${i}: ${result}`);
  }
  globalThis.frozenightDispose();
  if (globalThis.frozenightIsLoaded()) throw new Error('module still loaded after dispose');
  const mem = process.memoryUsage();
  peak = Math.max(peak, mem.rss);
  if (i % 20 === 0) {
    console.log(JSON.stringify({ cycle: i, rss: mem.rss, heapUsed: mem.heapUsed, move }));
  }
}
console.log(JSON.stringify({ outcome: 'ready', cycles, peakRss: peak, millis: Date.now() - start }));
