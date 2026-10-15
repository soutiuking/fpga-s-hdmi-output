"""Extract a simulation vector from an existing TFMEDIA3 card image."""
from pathlib import Path
import struct
import sys

image_path = Path(sys.argv[1])
output_path = Path(sys.argv[2])
with image_path.open('rb') as image:
    header = image.read(512)
    assert header[:8] == b'TFMEDIA3'
    index_lba = struct.unpack_from('<I', header, 16)[0]
    image.seek(index_lba * 512)
    _, _, _, meta_lba, data_lba, _ = struct.unpack('<BBHIII', image.read(16))
    image.seek(meta_lba * 512)
    meta = image.read(512)
    frame_lba = struct.unpack_from('<I', meta, 8)[0]
    image.seek(frame_lba * 512)
    offset, size = struct.unpack('<II', image.read(8))
    image.seek(data_lba * 512 + offset)
    jpeg = image.read(size)
assert jpeg[:2] == b'\xff\xd8'
padded = jpeg + b'\x00' * (-len(jpeg) % 4)
words = struct.unpack('<' + 'H' * (len(padded) // 2), padded)
output_path.write_text('\n'.join(f'{word:04x}' for word in words) + '\n')
print(f'Extracted {size} bytes / {len(words)} SRAM words')
