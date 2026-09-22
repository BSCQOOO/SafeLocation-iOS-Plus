#!/usr/bin/env python3
"""Validate the actual PNG stream, without relying on a filename or Pillow."""
import json
from pathlib import Path
import struct
import zlib

ROOT = Path(__file__).resolve().parents[1]
ICON = ROOT / 'SafeLocation/Resources/Assets.xcassets/AppIcon.appiconset'


def validate():
    catalog = json.loads((ICON / 'Contents.json').read_text())
    entries = catalog['images']
    assert any(e.get('filename') == 'AppIcon.png' and e.get('size') == '1024x1024'
               and e.get('idiom') == 'universal' and e.get('platform') == 'ios' for e in entries)
    data = (ICON / 'AppIcon.png').read_bytes()
    assert data[:8] == b'\x89PNG\r\n\x1a\n', 'Not a PNG'
    offset = 8
    chunks = {}
    while offset < len(data):
        length = struct.unpack('>I', data[offset:offset + 4])[0]
        tag = data[offset + 4:offset + 8]
        body = data[offset + 8:offset + 8 + length]
        crc = struct.unpack('>I', data[offset + 8 + length:offset + 12 + length])[0]
        assert zlib.crc32(tag + body) & 0xffffffff == crc, 'Bad PNG chunk CRC'
        chunks.setdefault(tag, []).append(body)
        offset += length + 12
    width, height, depth, color, compression, filtering, interlace = struct.unpack('>IIBBBBB', chunks[b'IHDR'][0])
    assert (width, height, depth, color) == (1024, 1024, 8, 2), 'Expected 1024x1024 8-bit RGB without alpha'
    assert b'tRNS' not in chunks and b'iCCP' not in chunks, 'Transparency or unexpected ICC profile'
    assert chunks.get(b'sRGB') == [b'\x00'], 'Expected standard sRGB rendering intent'
    assert compression == filtering == interlace == 0
    raw = zlib.decompress(b''.join(chunks[b'IDAT']))
    assert len(raw) == height * (1 + width * 3), 'Invalid decoded scanline size'
    assert all(raw[y * (1 + width * 3)] <= 4 for y in range(height))
    print('AppIcon source OK: 1024x1024 RGB PNG, sRGB, no alpha/ICC, valid CRC and scanlines')


if __name__ == '__main__':
    validate()
