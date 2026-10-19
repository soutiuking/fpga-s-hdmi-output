"""Fixed SimHei 16x16 glyphs: ten 32-character slots, CRC-protected sectors."""
from pathlib import Path
import json
import re
import struct
import zlib
from PIL import Image, ImageDraw, ImageFont

FONT = Path(__file__).resolve().parents[1] / 'vendor/fonts/simhei.ttf'
MAX_LINES, MAX_CHARS = 10, 32

def font_path():
    # Same font as the original default phrase. No user-selected font.
    for p in [FONT, Path('C:/Windows/Fonts/simhei.ttf')]:
        if p.is_file(): return p
    raise ValueError('Fixed SimHei font unavailable: install Windows SimHei')

def normalize(data):
    if isinstance(data, dict): data = data.get('subtitles', [])
    if not isinstance(data, list) or len(data)>10:
        raise ValueError('At most 10 subtitle entries are supported')
    result=[]
    for entry in data:
        if not isinstance(entry,dict): raise ValueError('Subtitle entry must be an object')
        text=entry.get('text','')
        if not isinstance(text,str):raise ValueError('Subtitle text must be a string')
        text=text.strip()
        if not text: continue
        if len(text)>32 or any(ord(c)<32 for c in text):
            raise ValueError('Each subtitle needs 1..32 printable characters (no newlines)')
        color=entry.get('color','#FDE68A')
        if not isinstance(color,str) or not re.fullmatch(r'#[0-9a-fA-F]{6}',color):
            raise ValueError('Subtitle color must be #RRGGBB')
        rainbow=entry.get('rainbow',False)
        if not isinstance(rainbow,bool): raise ValueError('rainbow must be true or false')
        result.append(dict(text=text,color=color.upper(),rainbow=rainbow))
    return result

def load(path):
    return normalize(json.loads(Path(path).read_text(encoding='utf-8-sig'))) if path else []

def glyph(char, font):
    image=Image.new('L',(16,16));draw=ImageDraw.Draw(image)
    b=draw.textbbox((0,0),char,font=font)
    draw.text(((16-(b[2]-b[0]))//2-b[0],-2),char,font=font,fill=255)
    return image.point(lambda v:255 if v>=96 else 0)

def bitmap(text):
    font=ImageFont.truetype(str(font_path()),16)
    result=bytearray()
    for char in text:
        im=glyph(char,font)
        for y in range(16):
            row=sum(1<<(15-x) for x in range(16) if im.getpixel((x,y)))
            result+=struct.pack('<H',row)
    return bytes(result)

def crc_sector(data):
    data=bytearray(data)
    struct.pack_into('<I',data,508,zlib.crc32(data[:508]))
    return bytes(data)

def encode(entries):
    entries=normalize(entries)
    if not entries:return b''
    header=bytearray(512);header[:8]=b'TFSUB1\0\0'
    header[8:12]=bytes([1,len(entries),32,16])
    payload=bytearray(10240)
    for i,e in enumerate(entries):
        off=16+i*8;header[off:off+5]=bytes([len(e['text']),int(e['rainbow'])])+bytes.fromhex(e['color'][1:])
        bits=bitmap(e['text']);payload[i*1024:i*1024+len(bits)]=bits
    result=bytearray(crc_sector(header))
    for i in range(21):
        sector=bytearray(512);chunk=payload[i*504:(i+1)*504]
        sector[:len(chunk)]=chunk
        result+=crc_sector(sector)
    return bytes(result)

def decode(data):
    if len(data)!=22*512:raise ValueError('Invalid subtitle extent')
    for i in range(22):
        sector=data[i*512:(i+1)*512]
        if zlib.crc32(sector[:508])!=struct.unpack_from('<I',sector,508)[0]:
            raise ValueError(f'Subtitle sector {i}: CRC32 mismatch')
    h=data[:512]
    if h[:8]!=b'TFSUB1\0\0' or h[8]!=1 or not 1<=h[9]<=10 or h[10:12]!=bytes([32,16]):
        raise ValueError('Unsupported subtitle format')
    result=[]
    for i in range(h[9]):
        off=16+i*8;n,flags=h[off:off+2]
        if not 1<=n<=32 or flags>1:raise ValueError('Invalid subtitle length/flags')
        result.append(dict(characters=n,color='#'+h[off+2:off+5].hex().upper(),rainbow=bool(flags)))
    return result

def preview(entry, output):
    entries=normalize([entry])
    if not entries:raise ValueError('Enter subtitle text before previewing')
    entry=entries[0]
    im=Image.new('RGB',(640,80),'#111827');font=ImageFont.truetype(str(font_path()),16)
    palette=['#FDE68A','#FDBA74','#FDA4AF','#F0ABFC','#C4B5FD','#93C5FD','#67E8F9','#6EE7B7']
    for i,c in enumerate(entry['text'][:19]):
        mask=glyph(c,font).resize((32,32),Image.Resampling.NEAREST)
        im.paste(palette[i%8] if entry['rainbow'] else entry['color'],(16+i*32,24),mask)
    im.save(output)
