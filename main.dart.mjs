// Compiles a dart2wasm-generated main module from `source` which can then
// be instantiated via the `instantiate` method.
//
// `source` needs to be a `Response` object (or promise thereof) e.g. created
// via the `fetch()` JS API.
export async function compileStreaming(source) {
  const builtins = {builtins: ['js-string'], importedStringConstants: ''};
  return new CompiledApp(
      await _compileStreaming(source, builtins), builtins);
}

// Compiles a dart2wasm-generated wasm module from `bytes` which is then
// instantiable via the `instantiate` method.
export async function compile(bytes) {
  const builtins = {builtins: ['js-string'], importedStringConstants: ''};
  return new CompiledApp(await WebAssembly.compile(bytes, builtins), builtins);
}

let _isCompileStreamingSupported;
async function _compileStreaming(source, builtins) {
  _isCompileStreamingSupported ??= WebAssembly.compileStreaming(
    new Response(
      new Uint8Array([0,97,115,109,1,0,0,0,1,4,1,96,0,0,2,23,1,14,119,97,115,109,58,106,115,45,115,116,114,105,110,103,4,99,97,115,116,0,0]),
      {headers: {'Content-Type': 'application/wasm'}},
    ),
    builtins,
  ).then(() => false, (e) => e instanceof WebAssembly.CompileError);
  if (await _isCompileStreamingSupported) {
    return WebAssembly.compileStreaming(source, builtins);
  }
  return WebAssembly.compile(await (await source).arrayBuffer(), builtins);
}

class CompiledApp {
  constructor(module, builtins) {
    this.module = module;
    this.builtins = builtins;
  }

  // The second argument is an options object containing:
  // `loadDeferredModules` is a JS function that takes an array of module names
  //   matching wasm files produced by the dart2wasm compiler. It also takes a
  //   callback that should be invoked for each loaded module with 2 arguments:
  //   (1) the module name, (2) the loaded module in a format supported by
  //   `WebAssembly.compile` or `WebAssembly.compileStreaming`. The callback
  //   returns a Promise that resolves when the module is instantiated.
  //   loadDeferredModules should return a Promise that resolves when all the
  //   modules have been loaded and the callback promises have resolved.
  // `loadDeferredId` is a JS function that takes load ID produced by the
  //   compiler when the `use-load-ids` option is passed. Each load ID maps to
  //   one or more wasm files as specified in the emitted JSON file. It also
  //   takes a callback that should be invoked for each loaded module with 2
  //   arguments: (1) the module name, (2) the loaded module in a format
  //   supported by `WebAssembly.compile` or `WebAssembly.compileStreaming`.
  //   The callback returns a Promise that resolves when the module is
  //   instantiated.
  //   loadDeferredId should return a Promise that resolves when all the
  //   modules have been loaded and the callback promises have resolved.
  async instantiate(additionalImports, {loadDeferredModules, loadDeferredId} = {}) {
    let dartInstance;

    // Prints to the console
    function printToConsole(value) {
      if (typeof dartPrint == "function") {
        dartPrint(value);
        return;
      }
      if (typeof console == "object" && typeof console.log != "undefined") {
        console.log(value);
        return;
      }
      if (typeof print == "function") {
        print(value);
        return;
      }

      throw "Unable to print message: " + value;
    }

    // A special symbol attached to functions that wrap Dart functions.
    const jsWrappedDartFunctionSymbol = Symbol("JSWrappedDartFunction");

    function finalizeWrapper(dartFunction, wrapped) {
      wrapped.dartFunction = dartFunction;
      wrapped[jsWrappedDartFunctionSymbol] = true;
      return wrapped;
    }

    // Imports
    const dart2wasm = {
            AB: b => !!b,
      AC: Function.prototype.call.bind(DataView.prototype.setInt16),
      AD: x0 => x0.height,
      AE: x0 => x0.computedStyleMap(),
      AF: x0 => x0.clientX,
      AG: x0 => x0.current(),
      AH: x0 => x0.value,
      AI: a => a.pop(),
      AJ: x0 => x0.duration,
      AK: (x0,x1,x2,x3) => x0.removeEventListener(x1,x2,x3),
      AL: x0 => x0.statusText,
      AM: x0 => x0.assetBase,
      B: s => printToConsole(s),
      BB: () => globalThis.document,
      BC: Function.prototype.call.bind(DataView.prototype.setUint16),
      BD: x0 => x0.width,
      BE: (x0,x1) => x0.get(x1),
      BF: x0 => x0.changedTouches,
      BG: (x0,x1) => new Intl.v8BreakIterator(x0,x1),
      BH: x0 => x0.selectionDirection,
      BI: x0 => new WeakRef(x0),
      BJ: (x0,x1) => ({frameIndex: x0,completeFramesOnly: x1}),
      BK: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      BL: x0 => x0.url,
      BM: x0 => x0.loader,
      C: Function.prototype.call.bind(Number.prototype.toString),
      CB: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      CC: Function.prototype.call.bind(DataView.prototype.setUint8),
      CD: x0 => x0.screen,
      CE: (o, p) => p in o,
      CF: x0 => x0.key,
      CG: x0 => x0.v8BreakIterator,
      CH: x0 => x0.selectionStart,
      CI: x0 => x0.deref(),
      CJ: (x0,x1) => x0.decode(x1),
      CK: () => new XMLHttpRequest(),
      CL: x0 => x0.getReader(),
      CM: () => globalThis._flutter,
      D: Function.prototype.call.bind(BigInt.prototype.toString),
      DB: (x0,x1) => x0.focus(x1),
      DC: Function.prototype.call.bind(DataView.prototype.setInt8),
      DD: o => {
        if (o === null || o === undefined) return 0;
        if (typeof(o) === 'string') return 1;
        return 2;
      },
      DE: (x0,x1) => { x0.textContent = x1 },
      DF: x0 => x0.identifier,
      DG: () => globalThis.Intl,
      DH: x0 => x0.selectionEnd,
      DI: () => globalThis.WeakRef,
      DJ: x0 => x0.image,
      DK: (x0,x1,x2,x3) => x0.open(x1,x2,x3),
      DL: x0 => x0.read(),
      E: (exn) => {
        let stackString = exn.toString();
        let frames = stackString.split('\n');
        let drop = 4;
        if (frames[0].startsWith('Error')) {
            drop += 1;
        }
        return frames.slice(drop).join('\n');
      },
      EB: () => ({}),
      EC: Function.prototype.call.bind(DataView.prototype.getInt8),
      ED: x0 => x0.tabIndex,
      EE: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      EF: x0 => x0.touches,
      EG: (x0,x1) => x0.segment(x1),
      EH: x0 => x0.value,
      EI: (o, offsetInBytes, lengthInBytes) => {
        var dst = new ArrayBuffer(lengthInBytes);
        new Uint8Array(dst).set(new Uint8Array(o, offsetInBytes, lengthInBytes));
        return new DataView(dst);
      },
      EJ: x0 => x0.close(),
      EK: x0 => x0.send(),
      EL: x0 => x0.value,
      F: () => new Error().stack,
      FB: (o, p, v) => o[p] = v,
      FC: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Int8Array) return 1;
        return 2;
      },
      FD: (x0,x1) => x0.contains(x1),
      FE: x0 => x0.matches,
      FF: x0 => x0.pressure,
      FG: x0 => x0.index,
      FH: x0 => x0.selectionDirection,
      FI: (a, s, e) => a.slice(s, e),
      FJ: (x0,x1,x2,x3,x4) => ({type: x0,data: x1,premultiplyAlpha: x2,colorSpaceConversion: x3,preferAnimation: x4}),
      FK: x0 => x0.response,
      FL: x0 => x0.done,
      G: s => JSON.stringify(s),
      GB: () => [],
      GC: (o, start, length) => new Float64Array(o.buffer, o.byteOffset + start, length),
      GD: x0 => x0.activeElement,
      GE: (x0,x1) => x0.matchMedia(x1),
      GF: x0 => x0.tiltY,
      GG: x0 => x0.next(),
      GH: x0 => x0.selectionStart,
      GI: (x0,x1) => globalThis.chessSoundPlay(x0,x1),
      GJ: x0 => new window.ImageDecoder(x0),
      GK: (x0,x1) => { x0.responseType = x1 },
      GL: x0 => x0.cancel(),
      H: Function.prototype.call.bind(Number.prototype.toString),
      HB: (a, i) => a.push(i),
      HC: (o, start, length) => new Float32Array(o.buffer, o.byteOffset + start, length),
      HD: x0 => x0.parentNode,
      HE: x0 => x0.matches,
      HF: x0 => x0.tiltX,
      HG: x0 => x0.value,
      HH: x0 => x0.selectionEnd,
      HI: (x0,x1) => x0.fetch(x1),
      HJ: x0 => x0.name,
      HK: x0 => x0.vendor,
      HL: x0 => x0.body,
      I: Function.prototype.call.bind(String.prototype.indexOf),
      IB: x0 => new Int8Array(x0),
      IC: (o, start, length) => new Uint32Array(o.buffer, o.byteOffset + start, length),
      ID: x0 => x0.tagName,
      IE: o => typeof o === 'function' && o[jsWrappedDartFunctionSymbol] === true,
      IF: x0 => x0.pointerType,
      IG: x0 => x0.done,
      IH: (x0,x1) => { x0.name = x1 },
      II: x0 => x0.arrayBuffer(),
      IJ: x0 => x0.repetitionCount,
      IK: x0 => x0.navigator,
      IL: x0 => x0.headers,
      J: (s, p, i) => s.lastIndexOf(p, i),
      JB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmI8ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      JC: (o, start, length) => new Int32Array(o.buffer, o.byteOffset + start, length),
      JD: x0 => x0.target,
      JE: f => f.dartFunction,
      JF: x0 => x0.pointerId,
      JG: (o, m, a) => o[m].apply(o, a),
      JH: (x0,x1) => { x0.placeholder = x1 },
      JI: () => globalThis.window,
      JJ: x0 => x0.frameCount,
      JK: x0 => new Blob(x0),
      JL: x0 => x0.signal,
      K: o => o,
      KB: x0 => new Uint8Array(x0),
      KC: (o, start, length) => new Uint16Array(o.buffer, o.byteOffset + start, length),
      KD: x0 => x0.clientY,
      KE: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      KF: x0 => x0.getCoalescedEvents(),
      KG: x0 => x0.iterator,
      KH: (x0,x1) => { x0.autocomplete = x1 },
      KI: (x0,x1) => globalThis.searchlessOnnxLoad(x0,x1),
      KJ: x0 => x0.selectedTrack,
      KK: x0 => x0.size,
      KL: (x0,x1) => x0.querySelector(x1),
      L: o => {
        if (o === undefined || o === null) return 0;
        if (typeof o === 'number') return 1;
        return 2;
      },
      LB: x0 => new Uint8ClampedArray(x0),
      LC: (o, start, length) => new Int16Array(o.buffer, o.byteOffset + start, length),
      LD: x0 => x0.clientX,
      LE: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1) { return wasmFunction(f,arguments.length,x0,x1) }),
      LF: s => s.trimLeft(),
      LG: () => globalThis.Symbol,
      LH: (x0,x1) => { x0.type = x1 },
      LI: x0 => globalThis.searchlessOnnxClose(x0),
      LJ: x0 => x0.completed,
      LK: (x0,x1,x2) => x0.insertBefore(x1,x2),
      LL: (x0,x1) => x0.createElement(x1),
      M: x0 => x0.index,
      MB: x0 => new Int16Array(x0),
      MC: (o, start, length) => new Uint8ClampedArray(o.buffer, o.byteOffset + start, length),
      MD: (x0,x1,x2) => x0.addEventListener(x1,x2),
      ME: (p, s, f) => p.then(s, (e) => f(e, e === undefined)),
      MF: s => s.toUpperCase(),
      MG: (x0,x1) => new Intl.Segmenter(x0,x1),
      MH: (x0,x1) => { x0.name = x1 },
      MI: (x0,x1,x2) => globalThis.searchlessOnnxInfer(x0,x1,x2),
      MJ: x0 => x0.ready,
      MK: x0 => x0.id,
      ML: (o, a) => o + a,
      N: o => String(o),
      NB: x0 => new Uint16Array(x0),
      NC: (o, start, length) => new Uint8Array(o.buffer, o.byteOffset + start, length),
      ND: (x0,x1,x2) => x0.setAttribute(x1,x2),
      NE: (o, i) => o[i],
      NF: x0 => x0.pop(),
      NG: x0 => x0.Segmenter,
      NH: (x0,x1) => { x0.placeholder = x1 },
      NI: x0 => globalThis.lynxLoad(x0),
      NJ: x0 => x0.tracks,
      NK: x0 => x0.offsetHeight,
      NL: x0 => x0.children,
      O: o => o === undefined,
      OB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmI16ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      OC: (o, start, length) => new Int8Array(o.buffer, o.byteOffset + start, length),
      OD: (x0,x1) => x0.closest(x1),
      OE: o => o.length,
      OF: x0 => x0.flags,
      OG: x0 => x0.buffer,
      OH: (x0,x1) => { x0.scrollTop = x1 },
      OI: () => globalThis.lynxLoadedBundle(),
      OJ: () => globalThis.window.ImageDecoder,
      OK: x0 => x0.offsetWidth,
      OL: (x0,x1) => { x0.id = x1 },
      P: (x0,x1) => x0.exec(x1),
      PB: x0 => new Int32Array(x0),
      PC: (x0,x1) => x0.querySelector(x1),
      PD: (ms, c) =>
      setTimeout(() => dartInstance.exports.$invokeCallback(c),ms),
      PE: o => {
        if (o === undefined) return 1;
        var type = typeof o;
        if (type === 'boolean') return 2;
        if (type === 'number') return 3;
        if (type === 'string') return 4;
        if (o instanceof Array) return 5;
        if (ArrayBuffer.isView(o)) {
          if (o instanceof Int8Array) return 6;
          if (o instanceof Uint8Array) return 7;
          if (o instanceof Uint8ClampedArray) return 8;
          if (o instanceof Int16Array) return 9;
          if (o instanceof Uint16Array) return 10;
          if (o instanceof Int32Array) return 11;
          if (o instanceof Uint32Array) return 12;
          if (o instanceof Float32Array) return 13;
          if (o instanceof Float64Array) return 14;
          if (o instanceof DataView) return 15;
        }
        if (o instanceof ArrayBuffer) return 16;
        // Feature check for `SharedArrayBuffer` before doing a type-check.
        if (globalThis.SharedArrayBuffer !== undefined &&
            o instanceof SharedArrayBuffer) {
            return 17;
        }
        if (o instanceof Promise) return 18;
        return 19;
      },
      PF: (a, s) => a.join(s),
      PG: x0 => x0.wasmMemory,
      PH: (x0,x1,x2) => x0.setSelectionRange(x1,x2),
      PI: x0 => globalThis.lynxSendUci(x0),
      PJ: (o, p) => p in o,
      PK: x0 => x0.stopPropagation(),
      PL: () => globalThis.document,
      Q: (x0,x1) => { x0.lastIndex = x1 },
      QB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmI32ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      QC: (x0,x1) => x0.item(x1),
      QD: (handle) => clearTimeout(handle),
      QE: x0 => x0.language,
      QF: (x0,x1) => x0.error(x1),
      QG: () => globalThis.window._flutter_skwasmInstance,
      QH: (x0,x1,x2) => x0.setSelectionRange(x1,x2),
      QI: x0 => globalThis.lynxSearch(x0),
      QJ: x0 => x0.groups,
      QK: x0 => x0.disabled,
      QL: (x0,x1,x2) => x0.addEventListener(x1,x2),
      R: o => o,
      RB: x0 => new Uint32Array(x0),
      RC: x0 => x0.length,
      RD: x0 => x0.maxTouchPoints,
      RE: (x0,x1,x2,x3) => x0.register(x1,x2,x3),
      RF: () => globalThis.console,
      RG: () => new TextDecoder(),
      RH: s => {
        if (/[[\]{}()*+?.\\^$|]/.test(s)) {
            s = s.replace(/[[\]{}()*+?.\\^$|]/g, '\\$&');
        }
        return s;
      },
      RI: () => globalThis.lc0OnnxClose(),
      RJ: (x0,x1) => x0.getRandomValues(x1),
      RK: (x0,x1) => { x0.min = x1 },
      RL: x0 => x0.click(),
      S: (s, m) => {
        try {
          return new RegExp(s, m);
        } catch (e) {
          return String(e);
        }
      },
      SB: x0 => new Float32Array(x0),
      SC: (x0,x1) => x0.querySelectorAll(x1),
      SD: x0 => x0.platform,
      SE: () => globalThis.window.FinalizationRegistry,
      SF: s => s.trimRight(),
      SG: (map, o, v) => map.set(o, v),
      SH: x0 => x0.keyCode,
      SI: x0 => globalThis.lc0OnnxLoad(x0),
      SJ: () => globalThis.crypto,
      SK: (x0,x1) => { x0.max = x1 },
      SL: (x0,x1) => x0.removeChild(x1),
      T: o => o instanceof RegExp,
      TB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmF32ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      TC: (x0,x1) => x0.getAttribute(x1),
      TD: s => new Date(s * 1000).getTimezoneOffset() * 60,
      TE: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      TF: x0 => x0.blur(),
      TG: (map, o) => map.get(o),
      TH: (x0,x1) => x0.scrollIntoView(x1),
      TI: x0 => globalThis.lc0OnnxInfer(x0),
      TJ: l => new DataView(new ArrayBuffer(l)),
      TK: (x0,x1) => { x0.disabled = x1 },
      TL: x0 => x0.firstChild,
      U: (string, times) => string.repeat(times),
      UB: x0 => new Float64Array(x0),
      UC: x0 => x0.remove(),
      UD: Date.now,
      UE: x0 => new window.FinalizationRegistry(x0),
      UF: x0 => x0.button,
      UG: () => new WeakMap(),
      UH: x0 => x0.multiViewEnabled,
      UI: () => globalThis.frozenightLoad(),
      UJ: (d, f) => d.toExponential(f),
      UK: (x0,x1) => { x0.scrollLeft = x1 },
      UL: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      V: o => o,
      VB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmF64ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      VC: (x0,x1) => x0.appendChild(x1),
      VD: (x0,x1) => x0.contains(x1),
      VE: (x0,x1) => x0.unregister(x1),
      VF: (x0,x1) => x0.prepend(x1),
      VG: x0 => x0.debugSkipFontRetryDelay,
      VH: (x0,x1) => x0.replaceWith(x1),
      VI: (x0,x1) => globalThis.frozenightSearchBounded(x0,x1),
      VJ: (a, i) => a.splice(i, 1)[0],
      VK: (x0,x1) => { x0.spellcheck = x1 },
      VL: (x0,x1,x2) => x0.removeEventListener(x1,x2),
      W: o => {
        if (o === undefined || o === null) return 0;
        if (typeof o === 'boolean') return 1;
        return 2;
      },
      WB: x0 => new ArrayBuffer(x0),
      WC: (x0,x1) => x0.append(x1),
      WD: (decoder, codeUnits) => decoder.decode(codeUnits),
      WE: x0 => x0.preventDefault(),
      WF: x0 => x0.parentElement,
      WG: x0 => x0.status,
      WH: (x0,x1) => { x0.className = x1 },
      WI: x0 => globalThis.frozenightSearch(x0),
      WJ: x0 => x0.text(),
      WK: (x0,x1) => { x0.disabled = x1 },
      WL: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      X: x0 => x0.dotAll,
      XB: (x0,x1,x2) => new Uint8Array(x0,x1,x2),
      XC: (x0,x1,x2,x3) => x0.setProperty(x1,x2,x3),
      XD: () => new TextDecoder("utf-8", {fatal: true}),
      XE: x0 => x0.parent,
      XF: x0 => x0.innerHeight,
      XG: (x0,x1,x2) => x0.set(x1,x2),
      XH: (x0,x1) => { x0.tabIndex = x1 },
      XI: (x0,x1) => globalThis.frozenightSetPosition(x0,x1),
      XJ: x0 => x0.status,
      XK: x0 => x0.canvasKitMaximumSurfaces,
      XL: x0 => x0.length,
      Y: x0 => x0.unicode,
      YB: (x0,x1,x2) => new DataView(x0,x1,x2),
      YC: x0 => x0.style,
      YD: () => new TextDecoder("utf-8", {fatal: false}),
      YE: x0 => x0.timeStamp,
      YF: x0 => x0.innerWidth,
      YG: x0 => x0.arrayBuffer(),
      YH: (x0,x1) => { x0.action = x1 },
      YI: () => globalThis.frozenightGetEval(),
      YJ: (x0,x1,x2,x3) => x0.putImageData(x1,x2,x3),
      YK: x0 => x0.hostElement,
      YL: (x0,x1) => x0.item(x1),
      Z: x0 => x0.ignoreCase,
      ZB: (o, p) => o[p],
      ZC: x0 => x0.debugShowSemanticsNodes,
      ZD: (a, i, v) => a[i] = v,
      ZE: (x0,x1) => x0.hasAttribute(x1),
      ZF: x0 => x0.height,
      ZG: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof ArrayBuffer) return 1;
        if (globalThis.SharedArrayBuffer !== undefined &&
            o instanceof SharedArrayBuffer) {
          return 2;
        }
        return 3;
      },
      ZH: (x0,x1) => { x0.method = x1 },
      ZI: x0 => x0.terminate(),
      ZJ: x0 => x0.arrayBuffer(),
      ZK: x0 => x0.location,
      ZL: x0 => ({type: x0}),
      a: x0 => x0.multiline,
      aB: (o) => new DataView(o.buffer, o.byteOffset, o.byteLength),
      aC: (x0,x1) => x0.warn(x1),
      aD: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmI8ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      aE: x0 => x0.type,
      aF: x0 => x0.width,
      aG: (x0,x1) => x0.fetch(x1),
      aH: (x0,x1) => { x0.noValidate = x1 },
      aI: x0 => globalThis.URL.revokeObjectURL(x0),
      aJ: (x0,x1) => x0.transferFromImageBitmap(x1),
      aK: (x0,x1) => x0.getModifierState(x1),
      aL: (x0,x1) => new Blob(x0,x1),
      b: (exn) => {
        if (exn instanceof Error) {
          return exn.stack;
        } else {
          return null;
        }
      },
      bB: Function.prototype.call.bind(Object.getOwnPropertyDescriptor(DataView.prototype, 'byteLength').get),
      bC: x0 => x0.console,
      bD: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmI16ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      bE: (x0,x1) => x0.getModifierState(x1),
      bF: x0 => x0.clientHeight,
      bG: x0 => x0.fontFallbackBaseUrl,
      bH: x0 => x0.click(),
      bI: (x0,x1) => globalThis.cachedFetch(x0,x1),
      bJ: x0 => x0.rasterEndMilliseconds,
      bK: x0 => x0.metaKey,
      bL: x0 => x0.name,
      c: (c) =>
      queueMicrotask(() => dartInstance.exports.$invokeCallback(c)),
      cB: o => o.byteOffset,
      cC: () => globalThis.window,
      cD: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmI32ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      cE: x0 => x0.buttons,
      cF: x0 => x0.clientWidth,
      cG: (x0,x1,x2,x3) => x0.pushState(x1,x2,x3),
      cH: (x0,x1) => x0.getElementsByClassName(x1),
      cI: x0 => x0.blob(),
      cJ: x0 => x0.rasterStartMilliseconds,
      cK: x0 => x0.altKey,
      cL: x0 => x0.type,
      d: (x0,x1) => x0.didCreateEngineInitializer(x1),
      dB: o => o.buffer,
      dC: (o, c) => o instanceof c,
      dD: (s) => +s,
      dE: x0 => x0.ctrlKey,
      dF: x0 => x0.isConnected,
      dG: x0 => x0.history,
      dH: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmF32ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      dI: x0 => globalThis.URL.createObjectURL(x0),
      dJ: x0 => x0.imageBitmaps,
      dK: x0 => x0.ctrlKey,
      dL: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      e: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      eB: Function.prototype.call.bind(DataView.prototype.getUint8),
      eC: (x0,x1) => x0[x1],
      eD: s => {
        if (!/^\s*[+-]?(?:Infinity|NaN|(?:\.\d+|\d+(?:\.\d*)?)(?:[eE][+-]?\d+)?)\s*$/.test(s)) {
          return NaN;
        }
        return parseFloat(s);
      },
      eE: x0 => x0.getBoundingClientRect(),
      eF: x0 => x0.head,
      eG: x0 => x0.search,
      eH: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmF64ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      eI: x0 => new Worker(x0),
      eJ: (x0,x1) => { x0.height = x1 },
      eK: x0 => x0.isComposing,
      eL: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      f: (wasmFunction,f) => finalizeWrapper(f, function() { return wasmFunction(f,arguments.length) }),
      fB: (b, o) => new DataView(b, o),
      fC: x0 => x0.length,
      fD: s => s.trim(),
      fE: x0 => x0.y,
      fF: (x0,x1) => { x0.content = x1 },
      fG: x0 => x0.location,
      fH: (x0,x1) => x0.dispatchEvent(x1),
      fI: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      fJ: (x0,x1) => { x0.width = x1 },
      fK: x0 => x0.code,
      fL: x0 => x0.files,
      g: (x0,x1) => ({initializeEngine: x0,autoStart: x1}),
      gB: (b, o, l) => new DataView(b, o, l),
      gC: (string, token) => string.split(token),
      gD: x0 => x0.classList,
      gE: x0 => x0.x,
      gF: (x0,x1) => { x0.name = x1 },
      gG: x0 => x0.pathname,
      gH: (x0,x1) => x0.createEvent(x1),
      gI: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      gJ: x0 => x0.convertToBlob(),
      gK: x0 => x0.repeat,
      gL: x0 => x0.target,
      h: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1) { return wasmFunction(f,arguments.length,x0,x1) }),
      hB: Function.prototype.call.bind(DataView.prototype.getFloat64),
      hC: o => o instanceof Array,
      hD: x0 => x0.relatedTarget,
      hE: x0 => x0.top,
      hF: (x0,x1) => x0.removeChild(x1),
      hG: (x0,x1,x2,x3) => x0.replaceState(x1,x2,x3),
      hH: (x0,x1,x2,x3) => x0.initEvent(x1,x2,x3),
      hI: (x0,x1) => x0.postMessage(x1),
      hJ: (x0,x1,x2) => new ImageData(x0,x1,x2),
      hK: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      hL: (x0,x1) => { x0.display = x1 },
      i: x0 => new Promise(x0),
      iB: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Float64Array) return 1;
        return 2;
      },
      iC: (a, i) => a[i],
      iD: x0 => x0.hasFocus(),
      iE: x0 => x0.left,
      iF: x0 => x0.firstChild,
      iG: o => {
        const proto = Object.getPrototypeOf(o);
        return proto === Object.prototype || proto === null;
      },
      iH: x0 => x0.readText(),
      iI: (x0,x1) => { x0.onerror = x1 },
      iJ: (x0,x1) => x0.getContext(x1),
      iK: (x0,x1) => x0.getItem(x1),
      iL: x0 => x0.style,
      j: (x0,x1,x2) => x0.call(x1,x2),
      jB: Function.prototype.call.bind(DataView.prototype.setFloat64),
      jC: a => a.length,
      jD: x0 => x0.shiftKey,
      jE: x0 => x0.scrollTop,
      jF: x0 => x0.viewConstraints,
      jG: o => Object.keys(o),
      jH: x0 => x0.clipboard,
      jI: x0 => x0.type,
      jJ: (x0,x1) => new OffscreenCanvas(x0,x1),
      jK: x0 => x0.localStorage,
      jL: (x0,x1) => { x0.accept = x1 },
      k: (constructor, args) => {
        const factoryFunction = constructor.bind.apply(
            constructor, [null, ...args]);
        return new factoryFunction();
      },
      kB: (t, s) => t.set(s),
      kC: (x0,x1) => x0.test(x1),
      kD: x0 => x0.body,
      kE: x0 => x0.offsetTop,
      kF: x0 => x0.hostElement,
      kG: x0 => x0.state,
      kH: (x0,x1) => x0.writeText(x1),
      kI: (x0,x1) => { x0.onmessage = x1 },
      kJ: x0 => x0.allocationSize(),
      kK: (x0,x1) => x0.key(x1),
      kL: (x0,x1) => { x0.multiple = x1 },
      l: x0 => new Array(x0),
      lB: Function.prototype.call.bind(DataView.prototype.setFloat32),
      lC: x0 => x0.userAgent,
      lD: x0 => x0.visibilityState,
      lE: x0 => x0.scrollLeft,
      lF: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      lG: x0 => x0.hash,
      lH: x0 => x0.unlock(),
      lI: x0 => x0.data,
      lJ: (x0,x1) => x0.copyTo(x1),
      lK: x0 => x0.length,
      lL: (x0,x1) => { x0.draggable = x1 },
      m: o => [o],
      mB: Function.prototype.call.bind(DataView.prototype.getFloat32),
      mC: x0 => x0.navigator,
      mD: (x0,x1,x2) => x0.removeEventListener(x1,x2),
      mE: x0 => x0.offsetLeft,
      mF: x0 => ({runApp: x0}),
      mG: x0 => x0.state,
      mH: (x0,x1) => x0.lock(x1),
      mI: () => globalThis.lynxDispose(),
      mJ: (x0,x1) => { x0.height = x1 },
      mK: (x0,x1,x2) => x0.setItem(x1,x2),
      mL: (x0,x1) => { x0.type = x1 },
      n: (o0, o1) => [o0, o1],
      nB: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Float32Array) return 1;
        return 2;
      },
      nC: Function.prototype.call.bind(String.prototype.toLowerCase),
      nD: x0 => x0.disconnect(),
      nE: x0 => x0.offsetParent,
      nF: () => typeof dartUseDateNowForTicks !== "undefined",
      nG: (x0,x1) => x0.go(x1),
      nH: x0 => x0.orientation,
      nI: () => globalThis.frozenightDispose(),
      nJ: (x0,x1) => { x0.width = x1 },
      nK: (x0,x1) => x0.removeItem(x1),
      nL: (x0,x1) => { x0.download = x1 },
      o: (o0, o1, o2) => [o0, o1, o2],
      oB: Function.prototype.call.bind(DataView.prototype.getUint32),
      oC: Object.is,
      oD: x0 => new Intl.Locale(x0),
      oE: x0 => x0.offsetY,
      oF: () => Date.now(),
      oG: (x0,x1) => x0.querySelectorAll(x1),
      oH: (x0,x1) => x0.querySelector(x1),
      oI: x0 => x0.close(),
      oJ: (x0,x1) => x0.toDataURL(x1),
      oK: x0 => x0.baseURI,
      oL: (x0,x1) => { x0.target = x1 },
      p: (o0, o1, o2, o3) => [o0, o1, o2, o3],
      pB: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Uint32Array) return 1;
        return 2;
      },
      pC: x0 => x0.vendor,
      pD: x0 => x0.region,
      pE: x0 => x0.offsetX,
      pF: () => 1000 * performance.now(),
      pG: (d, digits) => d.toFixed(digits),
      pH: (x0,x1) => { x0.title = x1 },
      pI: x0 => x0.height,
      pJ: (x0,x1,x2,x3) => x0.drawImage(x1,x2,x3),
      pK: x0 => x0.document,
      pL: (x0,x1) => { x0.href = x1 },
      q: (x0,x1,x2) => { x0[x1] = x2 },
      qB: Function.prototype.call.bind(DataView.prototype.getInt32),
      qC: (x0,x1) => x0.createTextNode(x1),
      qD: x0 => x0.script,
      qE: (o, p, r) => o.replace(p, () => r),
      qF: (x0,x1) => x0.requestAnimationFrame(x1),
      qG: x0 => x0.maxHeight,
      qH: (x0,x1) => x0.vibrate(x1),
      qI: x0 => x0.width,
      qJ: (x0,x1,x2,x3,x4,x5,x6,x7,x8,x9) => x0.drawImage(x1,x2,x3,x4,x5,x6,x7,x8,x9),
      qK: () => {
        return typeof process != "undefined" &&
               Object.prototype.toString.call(process) == "[object process]" &&
               process.platform == "win32"
      },
      qL: x0 => x0.extraAssets,
      r: (o, p) => o[p],
      rB: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Int32Array) return 1;
        return 2;
      },
      rC: (x0,x1) => { x0.id = x1 },
      rD: x0 => x0.language,
      rE: (o, p, r) => o.replaceAll(p, () => r),
      rF: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      rG: x0 => x0.maxWidth,
      rH: x0 => x0.content,
      rI: (x0,x1,x2,x3,x4,x5) => x0.createImageBitmap(x1,x2,x3,x4,x5),
      rJ: (x0,x1) => x0.getContext(x1),
      rK: () => {
        // On browsers return `globalThis.location.href`
        if (globalThis.location != null) {
          return globalThis.location.href;
        }
        return null;
      },
      rL: x0 => x0.fontManifest,
      s: () => globalThis,
      sB: o => o instanceof Uint16Array,
      sC: (x0,x1) => { x0.nonce = x1 },
      sD: x0 => x0.languages,
      sE: x0 => x0.deltaMode,
      sF: x0 => x0.now(),
      sG: x0 => x0.minHeight,
      sH: x0 => x0.document,
      sI: (x0,x1) => x0.createImageBitmap(x1),
      sJ: x0 => x0.format,
      sK: x0 => x0.abort(),
      sL: x0 => x0.assetManifest,
      t: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      tB: Function.prototype.call.bind(DataView.prototype.getUint16),
      tC: x0 => x0.nonce,
      tD: (x0,x1) => x0.observe(x1),
      tE: x0 => x0.deltaY,
      tF: x0 => x0.performance,
      tG: x0 => x0.minWidth,
      tH: (handle) => clearInterval(handle),
      tI: x0 => new Blob(x0),
      tJ: (x0,x1,x2,x3,x4) => x0.getImageData(x1,x2,x3,x4),
      tK: () => new AbortController(),
      tL: x0 => x0.buildConfig,
      u: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      uB: o => o instanceof Int16Array,
      uC: () => globalThis.window.flutterConfiguration,
      uD: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1) { return wasmFunction(f,arguments.length,x0,x1) }),
      uE: x0 => x0.deltaX,
      uF: x0 => new Uint8Array(x0),
      uG: (x0,x1) => x0.removeProperty(x1),
      uH: (ms, c) =>
      setInterval(() => dartInstance.exports.$invokeCallback(c), ms),
      uI: x0 => x0.close(),
      uJ: x0 => x0.data,
      uK: (x0,x1,x2,x3,x4,x5) => ({method: x0,headers: x1,body: x2,credentials: x3,redirect: x4,signal: x5}),
      uL: x0 => x0.length,
      v: (x0,x1) => ({addView: x0,removeView: x1}),
      vB: Function.prototype.call.bind(DataView.prototype.getInt16),
      vC: (x0,x1) => x0.attachShadow(x1),
      vD: x0 => new ResizeObserver(x0),
      vE: x0 => x0.wheelDeltaY,
      vF: (x0,x1,x2) => x0.slice(x1,x2),
      vG: (x0,x1) => x0.add(x1),
      vH: () => Date.now(),
      vI: x0 => x0.naturalHeight,
      vJ: () => new FileReader(),
      vK: (x0,x1) => globalThis.fetch(x0,x1),
      vL: x0 => x0.getReader(),
      w: (l, r) => l === r,
      wB: o => o instanceof Uint8ClampedArray,
      wC: (x0,x1) => x0.createElement(x1),
      wD: (x0,x1) => x0.getPropertyValue(x1),
      wE: x0 => x0.wheelDeltaX,
      wF: (x0,x1) => x0.decode(x1),
      wG: x0 => x0.data,
      wH: Function.prototype.call.bind(DataView.prototype.getBigInt64),
      wI: x0 => x0.naturalWidth,
      wJ: (x0,x1) => x0.readAsArrayBuffer(x1),
      wK: (x0,x1) => x0.get(x1),
      wL: x0 => x0.value,
      x: x0 => x0.random(),
      xB: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Uint8Array) return 1;
        return 2;
      },
      xC: x0 => x0.scale,
      xD: x0 => globalThis.parseFloat(x0),
      xE: x0 => x0.bottom,
      xF: (x0,x1) => x0.adoptText(x1),
      xG: (x0,x1) => x0.removeAttribute(x1),
      xH: Function.prototype.call.bind(DataView.prototype.setBigInt64),
      xI: (x0,x1) => { x0.src = x1 },
      xJ: x0 => x0.result,
      xK: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1,x2) { return wasmFunction(f,arguments.length,x0,x1,x2) }),
      xL: x0 => x0.done,
      y: () => globalThis.Math,
      yB: Function.prototype.call.bind(DataView.prototype.setInt32),
      yC: x0 => x0.visualViewport,
      yD: (x0,x1) => x0.getComputedStyle(x1),
      yE: x0 => x0.right,
      yF: x0 => x0.first(),
      yG: (x0,x1) => { x0.value = x1 },
      yH: (o, start, length) => new BigInt64Array(o.buffer, o.byteOffset + start, length),
      yI: x0 => x0.displayHeight,
      yJ: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      yK: (x0,x1) => x0.forEach(x1),
      yL: x0 => x0.read(),
      z: (x0,x1,x2,x3) => x0.addEventListener(x1,x2,x3),
      zB: Function.prototype.call.bind(DataView.prototype.setUint32),
      zC: x0 => x0.devicePixelRatio,
      zD: x0 => x0.documentElement,
      zE: x0 => x0.clientY,
      zF: x0 => x0.next(),
      zG: (x0,x1) => { x0.value = x1 },
      zH: (a, i) => a.splice(i, 1),
      zI: x0 => x0.displayWidth,
      zJ: (x0,x1,x2,x3) => x0.addEventListener(x1,x2,x3),
      zK: x0 => x0.name,
      zL: x0 => x0.body,

    };

    const baseImports = {
      _: dart2wasm,
      Math: Math,
      Date: Date,
      Object: Object,
      Array: Array,
      Reflect: Reflect,
      WebAssembly: {
        JSTag: WebAssembly.JSTag,
      },
      "": new Proxy({}, { get(_, prop) { return prop; } }),

    };

    

    dartInstance = await WebAssembly.instantiate(this.module, {
      ...baseImports,
      ...additionalImports,
      
    });

    return new InstantiatedApp(this, dartInstance);
  }
}

class InstantiatedApp {
  constructor(compiledApp, instantiatedModule) {
    this.compiledApp = compiledApp;
    this.instantiatedModule = instantiatedModule;
  }

  // Call the main function with the given arguments.
  invokeMain(...args) {
    this.instantiatedModule.exports.$invokeMain(args);
  }
}
