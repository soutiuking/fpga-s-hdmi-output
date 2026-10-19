"""TFMEDIA3 host packer / validator / Windows raw-card writer (Python 3.10+)."""
from __future__ import annotations
import argparse
import contextlib
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import zlib
from jpeg_profile import check_hardware_profile

CREATE_NO_WINDOW = 0x08000000 if os.name == 'nt' else 0

SECTOR = 512
WIDTH, HEIGHT, FPS = 640, 480, 25
MAX_JPEG = 65536
import subtitles
IMAGE_SUFFIXES = {'.png', '.jpg', '.jpeg', '.bmp', '.tif', '.tiff', '.webp'}

def sectors(n): return (n + 511) // 512
def crc_sector(data):
    data = bytearray(data)
    struct.pack_into('<I', data, 508, zlib.crc32(data[:508]))
    return data

def jpeg_check(data):
    from PIL import Image, JpegImagePlugin
    check_hardware_profile(data)
    if not data.startswith(b'\xff\xd8') or not data.endswith(b'\xff\xd9'):
        raise ValueError('JPEG SOI/EOI missing')
    with Image.open(io.BytesIO(data)) as im:
        if im.format != 'JPEG' or im.size != (WIDTH, HEIGHT):
            raise ValueError('JPEG must be 640x480')
        if im.info.get('progressive') or im.info.get('progression'):
            raise ValueError('Progressive JPEG is unsupported')
        if im.mode != 'RGB' or JpegImagePlugin.get_sampling(im) != 2:
            raise ValueError('JPEG must be baseline YCbCr 4:2:0')
        im.load()

def encode_frame(im, quality, limit):
    for q in range(quality, 9, -5):
        buf = io.BytesIO()
        im.save(buf, 'JPEG', quality=q, subsampling=2, progressive=False, optimize=False)
        data = buf.getvalue()
        if len(data) <= limit:
            jpeg_check(data)
            return data
    raise ValueError(f'Frame exceeds {limit} bytes even at low quality; use simpler content or raise the budget')

def find_ffmpeg(explicit=None):
    candidates = [explicit, os.environ.get('TFMEDIA_FFMPEG'), shutil.which('ffmpeg')]
    root = Path(__file__).resolve().parents[1]
    config = root / '.runtime/current.json'
    if config.is_file():
        candidates.append(str(root / json.loads(config.read_text(encoding='utf-8'))['ffmpeg']))
    for p in candidates:
        if p and Path(p).is_file(): return str(Path(p).resolve())
    raise ValueError('FFmpeg missing; pass --ffmpeg PATH')

def read_exact(pipe, size):
    parts, remaining = [], size
    while remaining:
        block = pipe.read(remaining)
        if not block: break
        parts.append(block); remaining -= len(block)
    data = b''.join(parts)
    if data and len(data) != size: raise ValueError('Truncated FFmpeg raw frame')
    return data

def convert_source(path, folder, args):
    from PIL import Image, ImageOps
    kind = 1 if path.suffix.lower() in IMAGE_SUFFIXES else 2
    data_path = folder / 'jpeg.dat'
    records, offset = [], 0
    def append_frame(im, output):
        nonlocal offset
        limit = MAX_JPEG if kind == 1 else args.max_frame_bytes
        data = encode_frame(im, args.quality, limit)
        records.append((offset, len(data)))
        output.write(data); offset += len(data)
        if offset > 0xffffffff: raise ValueError('One media exceeds the 32-bit data-length limit')
    with data_path.open('wb') as output:
        if kind == 1:
            with Image.open(path) as im:
                im = ImageOps.exif_transpose(im).convert('RGB')
                append_frame(ImageOps.pad(im, (WIDTH, HEIGHT), color='black'), output)
        else:
            ffmpeg = find_ffmpeg(args.ffmpeg)
            command = [ffmpeg, '-nostdin', '-v', 'error', '-i', str(path), '-an',
                       '-vf', 'fps=25,scale=640:480:force_original_aspect_ratio=decrease,pad=640:480:(ow-iw)/2:(oh-ih)/2',
                       '-pix_fmt', 'rgb24', '-threads', '1']
            if args.max_frames: command += ['-frames:v', str(args.max_frames)]
            command += ['-f', 'rawvideo', 'pipe:1']
            with tempfile.TemporaryFile() as errors:
                proc = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=errors, creationflags=CREATE_NO_WINDOW)
                try:
                    while raw := read_exact(proc.stdout, WIDTH * HEIGHT * 3):
                        append_frame(Image.frombytes('RGB', (WIDTH, HEIGHT), raw), output)
                    if proc.wait():
                        errors.seek(0)
                        raise ValueError(errors.read().decode(errors='replace'))
                finally:
                    if proc.poll() is None: proc.kill(); proc.wait()
                    proc.stdout.close()
    if not records: raise ValueError(f'No frames in {path}')
    audio_path = folder / 'audio.dat'
    audio_bytes = 0
    if kind == 2 and args.audio:
        command = [find_ffmpeg(args.ffmpeg), '-nostdin', '-v', 'error', '-y', '-i', str(path),
                   '-map', '0:a:0?', '-vn', '-ac', '1', '-ar', '48000', '-t', str(len(records)/25),
                   '-f', 's16le', str(audio_path)]
        result = subprocess.run(command, capture_output=True, creationflags=CREATE_NO_WINDOW)
        if result.returncode:
            message = result.stderr.decode(errors='replace')
            if 'does not contain any stream' not in message and 'matches no streams' not in message:
                raise ValueError(message)
            audio_path.write_bytes(b'')
        audio_bytes = len(records) * 3840
        with audio_path.open('r+b') as stream: stream.truncate(audio_bytes)
    return dict(kind=kind, name=path.name, frames=records, size=offset,
                data_path=data_path, audio_path=audio_path, audio_bytes=audio_bytes)

def pack(args):
    inputs = [Path(s).resolve(strict=True) for s in args.inputs]
    output = Path(args.output).resolve()
    if output in inputs: raise ValueError('Output cannot overwrite an input')
    if not 1 <= len(inputs) <= 20: raise ValueError('Select 1..20 inputs')
    pictures = sum(p.suffix.lower() in IMAGE_SUFFIXES for p in inputs)
    if pictures > 10 or len(inputs)-pictures > 10: raise ValueError('At most 10 pictures and 10 videos')
    if not 10 <= args.quality <= 95 or not 1024 <= args.max_frame_bytes <= MAX_JPEG:
        raise ValueError('quality must be 10..95, frame budget 1024..65536')
    if args.max_frames is not None and args.max_frames < 1: raise ValueError('max-frames must be positive')
    subtitle_entries=subtitles.load(getattr(args,"subtitles",None))
    subtitle_blob=subtitles.encode(subtitle_entries)
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='tfmedia3-', dir=output.parent) as tmp:
        folder = Path(tmp); items = []
        for i, p in enumerate(inputs):
            work = folder / str(i); work.mkdir()
            print(f'Convert {i+1}/{len(inputs)}: {p.name}', flush=True)
            items.append(convert_source(p, work, args))
        cursor = 2
        for item in items:
            item['meta_lba'] = cursor; cursor += 1
            item['index_lba'] = cursor; cursor += sectors(len(item['frames']) * 8)
            item['data_lba'] = cursor; cursor += sectors(item['size'])
            item['audio_lba'] = cursor if item['audio_bytes'] else 0
            cursor += sectors(item['audio_bytes'])
        subtitle_lba=cursor if subtitle_blob else 0
        cursor += len(subtitle_blob)//512
        if cursor > 0xffffffff: raise ValueError('Card image exceeds 32-bit sector limit')
        staged = folder / 'card.img'
        with staged.open('wb') as out:
            out.truncate(cursor * SECTOR)
            header = bytearray(SECTOR)
            header[:8] = b'TFMEDIA3'
            struct.pack_into('<HHHHIIHHIIHHIII', header, 8,
                             3,512,16,len(items),1,1,WIDTH,HEIGHT,25,1,1,16,48000,0,cursor)
            struct.pack_into("<I",header,52,subtitle_lba)
            out.seek(0); out.write(crc_sector(header))
            if subtitle_blob:
                out.seek(subtitle_lba*512);out.write(subtitle_blob)
            for i, item in enumerate(items):
                out.seek(SECTOR+i*16)
                out.write(struct.pack('<BBHIII', item['kind'],0,i,item['meta_lba'],item['data_lba'],item['size']))
                meta = bytearray(SECTOR); meta[:8] = b'TFMETA3\0'
                duration_num = 3 if item['kind']==1 else len(item['frames'])
                duration_den = 1 if item['kind']==1 else FPS
                struct.pack_into('<IIIIIIII',meta,8,item['index_lba'],len(item['frames']),
                                 item['audio_lba'],item['audio_bytes'],duration_num,duration_den,FPS,1)
                name = item['name'].encode('utf-8')[:63]
                while True:
                    try: name.decode('utf-8'); break
                    except UnicodeDecodeError: name=name[:-1]
                meta[64:64+len(name)] = name
                out.seek(item['meta_lba']*SECTOR); out.write(crc_sector(meta))
                out.seek(item['index_lba']*SECTOR)
                for record in item['frames']: out.write(struct.pack('<II',*record))
                out.seek(item['data_lba']*SECTOR)
                with item['data_path'].open('rb') as src: shutil.copyfileobj(src,out)
                if item['audio_bytes']:
                    out.seek(item['audio_lba']*SECTOR)
                    with item['audio_path'].open('rb') as src: shutil.copyfileobj(src,out)
        report = inspect(staged)
        os.replace(staged, output)
    print(json.dumps(dict(path=str(output), **report),ensure_ascii=False,indent=2))

def inspect(path):
    path = Path(path)
    size = path.stat().st_size
    ranges = [(0,2*SECTOR,'header/catalog')]
    def extent(start,length,name):
        if start < 2*SECTOR or length <= 0 or start+length > size:
            raise ValueError(f'{name}: extent outside image')
        ranges.append((start,start+length,name))
    with path.open('rb') as card:
        def read_at(offset,n):
            if offset < 0 or n < 0 or offset+n > size: raise ValueError('Read outside image')
            card.seek(offset); result=card.read(n)
            if len(result)!=n: raise ValueError('Short image read')
            return result
        def checked_sector(lba,magic):
            data=read_at(lba*SECTOR,SECTOR)
            if data[:8]!=magic: raise ValueError(f'LBA {lba}: bad magic')
            if zlib.crc32(data[:508])!=struct.unpack_from('<I',data,508)[0]:
                raise ValueError(f'LBA {lba}: CRC32 mismatch')
            return data
        header=checked_sector(0,b'TFMEDIA3')
        values=struct.unpack_from('<HHHHIIHHIIHHIII',header,8)
        version,hsize,esize,count,ilba,isectors,w,h,fn,fd,ach,abits,rate,flags,total=values
        if (version,hsize,esize,ilba,isectors,w,h,fn,fd,ach,abits,rate)!=(3,512,16,1,1,640,480,25,1,1,16,48000):
            raise ValueError('Unsupported TFMEDIA3 profile')
        if not 1<=count<=20 or size!=total*512: raise ValueError('Invalid count or total image size')
        subtitle_lba=struct.unpack_from("<I",header,52)[0]
        subtitle_report=[]
        if subtitle_lba:
            extent(subtitle_lba*512,22*512,"subtitles")
            subtitle_report=subtitles.decode(read_at(subtitle_lba*512,22*512))
        items=[]
        for i in range(count):
            kind,eflags,mid,mlba,dlba,dbytes=struct.unpack('<BBHIII',read_at(512+i*16,16))
            if kind not in (1,2): raise ValueError('Unsupported media type')
            extent(mlba*512,512,f'{i} metadata')
            meta=checked_sector(mlba,b'TFMETA3\0')
            flba,frames,alba,abytes,dn,dd,mfn,mfd=struct.unpack_from('<IIIIIIII',meta,8)
            if not 1<=frames<=0xffffff or (kind==1 and frames!=1): raise ValueError('Invalid frame count')
            if (mfn,mfd)!=(25,1) or dd==0: raise ValueError('Invalid media timing')
            if abytes and (kind!=2 or abytes!=frames*3840): raise ValueError('Invalid PCM length')
            if bool(alba)!=bool(abytes): raise ValueError('Invalid audio address')
            extent(flba*512,sectors(frames*8)*512,f'{i} frame table')
            extent(dlba*512,sectors(dbytes)*512,f'{i} JPEG data')
            if abytes: extent(alba*512,sectors(abytes)*512,f'{i} PCM')
            table=read_at(flba*512,frames*8)
            max_frame=0; previous_end=0
            for f in range(frames):
                offset,length=struct.unpack_from('<II',table,f*8)
                if not 1<=length<=MAX_JPEG or offset<previous_end or offset+length>dbytes:
                    raise ValueError(f'Media {i} frame {f}: invalid offset/size')
                jpeg_check(read_at(dlba*512+offset,length))
                max_frame=max(max_frame,length); previous_end=offset+length
            items.append(dict(index=i,type='image' if kind==1 else 'video',frames=frames,
                              jpeg_bytes=dbytes,max_frame_bytes=max_frame,audio_bytes=abytes,
                              estimated_stream_bytes_per_second=round((dbytes+abytes)*25/frames) if kind==2 else 0))
        ranges.sort()
        for left,right in zip(ranges,ranges[1:]):
            if left[1]>right[0]: raise ValueError(f'Overlapping regions: {left[2]} / {right[2]}')
    return dict(sectors=total,bytes=size,media=items,subtitles=subtitle_report)

def disks():
    if os.name!='nt': raise ValueError('Disk enumeration/writing requires Windows')
    script=r'''$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
$result=@(Get-Disk | ForEach-Object {
 $d=$_
 $volumes=@(Get-Partition -DiskNumber $d.Number -ErrorAction SilentlyContinue | ForEach-Object {
  $p=$_;$v=$p | Get-Volume -ErrorAction SilentlyContinue
  [pscustomobject]@{DriveLetter=([string]$p.DriveLetter).Trim([char]0);Label=[string]$v.FileSystemLabel;
   FileSystem=[string]$v.FileSystem;Size=[long]$p.Size;AccessPaths=@($p.AccessPaths)}
 })
 [pscustomobject]@{Number=[int]$d.Number;FriendlyName=[string]$d.FriendlyName;
  BusType=[string]$d.BusType;Size=[long]$d.Size;IsBoot=[bool]$d.IsBoot;
  IsSystem=[bool]$d.IsSystem;IsReadOnly=[bool]$d.IsReadOnly;IsOffline=[bool]$d.IsOffline;
  SerialNumber=[string]$d.SerialNumber;UniqueId=[string]$d.UniqueId;
  Path=[string]$d.Path;PartitionStyle=[string]$d.PartitionStyle;Volumes=$volumes}
})
ConvertTo-Json -InputObject $result -Depth 6 -Compress'''
    result=subprocess.run(['powershell.exe','-NoProfile','-Command',script],capture_output=True,check=True,creationflags=CREATE_NO_WINDOW)
    data=json.loads(result.stdout.decode('utf-8-sig',errors='replace'))
    result=data if isinstance(data,list) else [data]
    for disk in result:
        disk['Identity']=disk_identity(disk)
        disk['Eligible']=disk_eligible(disk)
    return result


def disk_eligible(disk):
    return (not any(disk.get(k,False) for k in ('IsBoot','IsSystem','IsReadOnly','IsOffline'))
            and int(disk.get('Size',0))>0
            and str(disk.get('BusType','')).lower() in ('usb','sd','mmc','7','12','13'))


def disk_identity(disk):
    fields={key:disk.get(key) for key in ('Number','FriendlyName','BusType','Size','SerialNumber','UniqueId','Path')}
    return hashlib.sha256(json.dumps(fields,sort_keys=True,ensure_ascii=False).encode('utf-8')).hexdigest()


def checked_disk(number, identity=None):
    disk=next((d for d in disks() if d['Number']==number),None)
    if not disk or not disk_eligible(disk):
        raise ValueError('Refusing a system, boot, read-only, offline or unsupported disk')
    if identity and disk_identity(disk)!=identity:
        raise ValueError('Target device changed. Refresh and select the card again.')
    return disk

def write_card(args):
    import ctypes
    from ctypes import wintypes
    image=Path(args.image).resolve(strict=True)
    inspect(image)  # Validate the entire image before any disk write.
    if args.disk != args.confirm_disk: raise ValueError('--confirm-disk must equal --disk')
    if not ctypes.windll.shell32.IsUserAnAdmin(): raise ValueError('Run in an Administrator terminal')
    disk=checked_disk(args.disk,getattr(args,'disk_identity',None))
    identity=disk_identity(disk)
    if image.stat().st_size>disk['Size']: raise ValueError('Image exceeds card capacity')
    drive=image.drive.rstrip(':')
    # Reject an image stored on the disk about to be overwritten.
    location_script=f"(Get-Partition -DriveLetter '{drive}' | Get-Disk).Number"
    location=subprocess.run(['powershell.exe','-NoProfile','-Command',location_script],capture_output=True,check=True,creationflags=CREATE_NO_WINDOW)
    if location.stdout.strip()==str(args.disk).encode(): raise ValueError('Image is stored on target disk')
    kernel=ctypes.WinDLL('kernel32',use_last_error=True)
    kernel.CreateFileW.argtypes=[wintypes.LPCWSTR,wintypes.DWORD,wintypes.DWORD,wintypes.LPVOID,wintypes.DWORD,wintypes.DWORD,wintypes.HANDLE]
    kernel.CreateFileW.restype=wintypes.HANDLE
    kernel.DeviceIoControl.argtypes=[wintypes.HANDLE,wintypes.DWORD,wintypes.LPVOID,wintypes.DWORD,wintypes.LPVOID,wintypes.DWORD,ctypes.POINTER(wintypes.DWORD),wintypes.LPVOID]
    kernel.CloseHandle.argtypes=[wintypes.HANDLE]
    invalid=ctypes.c_void_p(-1).value
    def ioctl(handle,code):
        returned=wintypes.DWORD()
        if not kernel.DeviceIoControl(handle,code,None,0,None,0,ctypes.byref(returned),None):
            raise ctypes.WinError(ctypes.get_last_error())
    script=f"Get-Partition -DiskNumber {args.disk} | Where-Object DriveLetter | Select-Object -ExpandProperty DriveLetter"
    volumes=subprocess.run(['powershell.exe','-NoProfile','-Command',script],capture_output=True,check=True,creationflags=CREATE_NO_WINDOW).stdout.decode().split()
    with contextlib.ExitStack() as stack:
        checked_disk(args.disk,identity)
        for letter in volumes:
            handle=kernel.CreateFileW('\\\\.\\'+letter+':',0xc0000000,3,None,3,0,None)
            if handle==invalid: raise ctypes.WinError(ctypes.get_last_error())
            stack.callback(kernel.CloseHandle,handle)
            ioctl(handle,0x90018)  # FSCTL_LOCK_VOLUME. Fail closed on any busy volume.
            stack.callback(ioctl,handle,0x9001c)
            ioctl(handle,0x90020)  # FSCTL_DISMOUNT_VOLUME
        target='\\\\.\\PhysicalDrive'+str(args.disk)
        checked_disk(args.disk,identity)
        print(f'Writing {image.stat().st_size} bytes to disk {args.disk}: {disk["FriendlyName"]}',flush=True)
        expected=hashlib.sha256()
        with image.open('rb') as src, open(target,'r+b',buffering=0) as dst:
            total=image.stat().st_size;written=0
            print(f'PROGRESS write 0 {total}',flush=True)
            while block:=src.read(1024*1024):
                expected.update(block)
                if dst.write(block)!=len(block): raise OSError('Short disk write')
                written+=len(block)
                print(f'PROGRESS write {written} {total}',flush=True)
            os.fsync(dst.fileno()); dst.seek(0)
            actual=hashlib.sha256(); remaining=image.stat().st_size
            print(f'PROGRESS verify 0 {total}',flush=True)
            while remaining:
                block=dst.read(min(1024*1024,remaining))
                if not block: raise OSError('Short disk verify read')
                actual.update(block); remaining-=len(block)
                print(f'PROGRESS verify {total-remaining} {total}',flush=True)
            if actual.digest()!=expected.digest(): raise ValueError('Card SHA-256 verification failed')
        print('Write and full readback verified. SHA256='+expected.hexdigest())

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    sub=parser.add_subparsers(dest='command',required=True)
    p=sub.add_parser('pack'); p.add_argument('inputs',nargs='+'); p.add_argument('-o','--output',required=True)
    p.add_argument('--ffmpeg'); p.add_argument('--quality',type=int,default=75)
    p.add_argument('--max-frame-bytes',type=int,default=28000)
    p.add_argument('--subtitles',help='JSON: up to ten fixed-font subtitles')
    p.add_argument('--max-frames',type=int); p.add_argument('--audio',action='store_true')
    p=sub.add_parser('inspect'); p.add_argument('image')
    sub.add_parser('disks')
    p=sub.add_parser('write'); p.add_argument('image'); p.add_argument('--disk',type=int,required=True)
    p.add_argument('--confirm-disk',type=int,required=True)
    p.add_argument('--disk-identity',help='Expected device identity from disks; refuse a changed target')
    args=parser.parse_args()
    try:
        if args.command=='pack': pack(args)
        elif args.command=='inspect': print(json.dumps(inspect(args.image),ensure_ascii=False,indent=2))
        elif args.command=='disks': print(json.dumps(disks(),ensure_ascii=False,indent=2))
        else: write_card(args)
    except (ValueError,OSError,subprocess.CalledProcessError) as exc:
        parser.exit(1,'ERROR: '+str(exc)+'\n')

if __name__=='__main__': main()
