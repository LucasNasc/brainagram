// Encoder de GIF animado (GIF89a), sem dependências.
//
// Três ideias deixam o arquivo pequeno para um diagrama:
//   1. Paleta global única, montada de amostras de vários quadros — as cores
//      de um diagrama são poucas (tokens do design system), então 256 bastam.
//   2. Cada quadro grava só o retângulo que mudou em relação ao anterior
//      (descarte "deixar no lugar"): entre dois quadros, quase sempre só o
//      impulso e a seta ativa se movem.
//   3. Quadros idênticos não são gravados de novo: o anterior ganha mais tempo.

const MAX_COLORS = 256;

// ── paleta ──────────────────────────────────────────────────────────────────

// Cores agrupadas em 5 bits por canal (32768 baldes). A paleta são os baldes
// mais frequentes, cada um pela média real das suas cores.
export class Palette {
  constructor() {
    this.count = new Uint32Array(32768);
    this.sum = new Float64Array(32768 * 3);
    this.colors = null;
    this.lookup = null;
  }

  sample(rgba) {
    for (let i = 0; i < rgba.length; i += 4) {
      const key = ((rgba[i] >> 3) << 10) | ((rgba[i + 1] >> 3) << 5) | (rgba[i + 2] >> 3);
      this.count[key]++;
      this.sum[key * 3] += rgba[i];
      this.sum[key * 3 + 1] += rgba[i + 1];
      this.sum[key * 3 + 2] += rgba[i + 2];
    }
  }

  build() {
    const keys = [];
    for (let k = 0; k < 32768; k++) if (this.count[k] > 0) keys.push(k);
    keys.sort((a, b) => this.count[b] - this.count[a]);

    this.colors = keys.slice(0, MAX_COLORS).map((k) => {
      const n = this.count[k];
      return [Math.round(this.sum[k * 3] / n), Math.round(this.sum[k * 3 + 1] / n), Math.round(this.sum[k * 3 + 2] / n)];
    });
    if (this.colors.length === 0) this.colors.push([255, 255, 255]);

    // balde → índice na paleta; o que não coube vai para a cor mais próxima
    this.lookup = new Int16Array(32768).fill(-1);
    keys.slice(0, MAX_COLORS).forEach((k, i) => (this.lookup[k] = i));
  }

  nearest(key) {
    const r = ((key >> 10) & 31) * 8 + 4;
    const g = ((key >> 5) & 31) * 8 + 4;
    const b = (key & 31) * 8 + 4;
    let best = 0;
    let bestD = Infinity;
    for (let i = 0; i < this.colors.length; i++) {
      const c = this.colors[i];
      const d = (c[0] - r) ** 2 * 2 + (c[1] - g) ** 2 * 4 + (c[2] - b) ** 2 * 3;
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    this.lookup[key] = best;
    return best;
  }

  index(rgba) {
    const out = new Uint8Array(rgba.length / 4);
    for (let i = 0, p = 0; i < rgba.length; i += 4, p++) {
      const key = ((rgba[i] >> 3) << 10) | ((rgba[i + 1] >> 3) << 5) | (rgba[i + 2] >> 3);
      const hit = this.lookup[key];
      out[p] = hit >= 0 ? hit : this.nearest(key);
    }
    return out;
  }
}

// ── escrita ─────────────────────────────────────────────────────────────────

class ByteWriter {
  constructor() {
    this.chunks = [];
    this.buf = new Uint8Array(1 << 16);
    this.pos = 0;
  }

  byte(b) {
    if (this.pos === this.buf.length) this.flush();
    this.buf[this.pos++] = b;
  }

  bytes(arr) {
    for (let i = 0; i < arr.length; i++) this.byte(arr[i]);
  }

  u16(n) {
    this.byte(n & 0xff);
    this.byte((n >> 8) & 0xff);
  }

  text(s) {
    for (let i = 0; i < s.length; i++) this.byte(s.charCodeAt(i));
  }

  flush() {
    this.chunks.push(this.buf.slice(0, this.pos));
    this.pos = 0;
  }

  result() {
    this.flush();
    return new Blob(this.chunks, { type: "image/gif" });
  }
}

export class GifWriter {
  constructor(width, height, palette) {
    this.width = width;
    this.height = height;
    this.palette = palette;
    this.out = new ByteWriter();
    this.prev = null;
    this.pending = null;
    this.frames = 0;
    this.header();
  }

  header() {
    const o = this.out;
    o.text("GIF89a");
    o.u16(this.width);
    o.u16(this.height);
    o.byte(0xf7); // tabela global de 256 cores, 8 bits
    o.byte(0); // fundo
    o.byte(0); // proporção de pixel
    for (let i = 0; i < MAX_COLORS; i++) {
      const c = this.palette.colors[i] || [0, 0, 0];
      o.bytes(c);
    }
    // NETSCAPE2.0: repetir para sempre
    o.bytes([0x21, 0xff, 0x0b]);
    o.text("NETSCAPE2.0");
    o.bytes([0x03, 0x01, 0x00, 0x00, 0x00]);
  }

  // `indices`: um índice da paleta por pixel do quadro inteiro; `delay` em ms.
  addFrame(indices, delay) {
    if (!this.prev) {
      this.prev = indices;
      this.pending = { rect: [0, 0, this.width, this.height], data: indices, delay };
      return;
    }

    const rect = changedRect(this.prev, indices, this.width, this.height);
    if (!rect) {
      this.pending.delay += delay;
      return;
    }

    this.writePending();
    this.prev = indices;
    this.pending = { rect, data: crop(indices, this.width, rect), delay };
  }

  writePending() {
    const f = this.pending;
    if (!f) return;
    const o = this.out;
    const [x, y, w, h] = f.rect;
    const cs = Math.max(2, Math.min(65535, Math.round(f.delay / 10)));

    o.bytes([0x21, 0xf9, 0x04, 0x04]); // controle gráfico: descarte "deixar no lugar"
    o.u16(cs);
    o.bytes([0x00, 0x00]);

    o.byte(0x2c);
    o.u16(x);
    o.u16(y);
    o.u16(w);
    o.u16(h);
    o.byte(0x00); // sem tabela local, sem entrelaçamento

    lzw(f.data, 8, o);
    this.frames++;
    this.pending = null;
  }

  finish(lastHold = 0) {
    if (this.pending) this.pending.delay += lastHold;
    this.writePending();
    this.out.byte(0x3b);
    return this.out.result();
  }
}

function changedRect(a, b, width, height) {
  let minX = width;
  let minY = height;
  let maxX = -1;
  let maxY = -1;
  for (let y = 0; y < height; y++) {
    const row = y * width;
    for (let x = 0; x < width; x++) {
      if (a[row + x] !== b[row + x]) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }
  return maxX < 0 ? null : [minX, minY, maxX - minX + 1, maxY - minY + 1];
}

function crop(indices, width, [x, y, w, h]) {
  const out = new Uint8Array(w * h);
  for (let row = 0; row < h; row++) {
    out.set(indices.subarray((y + row) * width + x, (y + row) * width + x + w), row * w);
  }
  return out;
}

// LZW de largura variável, como o GIF pede: começa em minCode+1 bits, cresce
// até 12 e reinicia o dicionário quando enche.
function lzw(indices, minCode, o) {
  o.byte(minCode);

  const clear = 1 << minCode;
  const eoi = clear + 1;
  let next = eoi + 1;
  let size = minCode + 1;
  let dict = new Map();

  let block = new Uint8Array(255);
  let blockLen = 0;
  let acc = 0;
  let bits = 0;

  const emitByte = (b) => {
    block[blockLen++] = b;
    if (blockLen === 255) {
      o.byte(255);
      o.bytes(block);
      blockLen = 0;
    }
  };

  const emit = (code) => {
    acc |= code << bits;
    bits += size;
    while (bits >= 8) {
      emitByte(acc & 0xff);
      acc >>>= 8;
      bits -= 8;
    }
  };

  emit(clear);
  let prefix = indices[0];

  for (let i = 1; i < indices.length; i++) {
    const k = indices[i];
    const key = (prefix << 8) | k;
    const hit = dict.get(key);
    if (hit !== undefined) {
      prefix = hit;
      continue;
    }

    emit(prefix);
    if (next < 4096) {
      dict.set(key, next++);
      if (next > 1 << size && size < 12) size++;
    } else {
      emit(clear);
      dict = new Map();
      next = eoi + 1;
      size = minCode + 1;
    }
    prefix = k;
  }

  emit(prefix);
  emit(eoi);
  if (bits > 0) emitByte(acc & 0xff);
  if (blockLen > 0) {
    o.byte(blockLen);
    o.bytes(block.subarray(0, blockLen));
  }
  o.byte(0);
}
