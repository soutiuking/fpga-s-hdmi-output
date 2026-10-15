"""Decode a real card-image frame in RTL and compare its RGB with Pillow.

--alignments extends APP0 metadata to exercise every tail size.
Requires the Icarus portable installation and Pillow used by run_tests.py.
"""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import argparse
import io
import math
import struct
import subprocess
import tempfile


def read_frame(image, media, frame):
    with image.open('rb') as stream:
        head = stream.read(512)
        if head[:8] != b'TFMEDIA3':
            raise ValueError('Not a TFMEDIA3 image')
        directory_lba = struct.unpack_from('<I', head, 16)[0]
        stream.seek(directory_lba * 512 + media * 16)
        _, _, _, meta_lba, data_lba, _ = struct.unpack('<BBHIII', stream.read(16))
        stream.seek(meta_lba * 512 + 8)
        index_lba, frame_count = struct.unpack('<II', stream.read(8))
        if not 0 <= frame < frame_count:
            raise ValueError('Frame index out of range')
        stream.seek(index_lba * 512 + frame * 8)
        offset, length = struct.unpack('<II', stream.read(8))
        stream.seek(data_lba * 512 + offset)
        original = stream.read(length)
    if not original.startswith(b'\xff\xd8') or not original.endswith(b'\xff\xd9'):
        raise ValueError('SOI/EOI missing')
    return original


def software_reference(original):
    from PIL import Image
    root = Path(__file__).resolve().parents[1]
    reference = Image.open(io.BytesIO(original)).convert('RGB')
    # core_jpeg replicates each 4:2:0 chroma sample over 2x2 pixels. Pillow's
    # default RGB decoder smooths chroma, so compare against a nearest-chroma
    # reference produced by an independent libavcodec IDCT implementation.
    import sys
    sys.path.insert(0, str(root/'tools'))
    from media_card import find_ffmpeg
    try:
        ffmpeg = Path(find_ffmpeg())
    except ValueError:
        ffmpeg = None
    if ffmpeg is not None:
        result = subprocess.run([str(ffmpeg), '-v', 'error', '-f', 'mjpeg', '-i', 'pipe:0',
                                 '-frames:v', '1', '-pix_fmt', 'yuvj420p', '-f', 'rawvideo', 'pipe:1'],
                                input=original, capture_output=True, check=True)
        raw = result.stdout
        if len(raw) != 640*480*3//2:
            raise AssertionError('Unexpected software YUV reference size')
        y = Image.frombytes('L', (640,480), raw[:307200])
        cb = Image.frombytes('L', (320,240), raw[307200:384000]).resize((640,480), Image.Resampling.NEAREST)
        cr = Image.frombytes('L', (320,240), raw[384000:]).resize((640,480), Image.Resampling.NEAREST)
        reference = Image.merge('YCbCr', (y,cb,cr)).convert('RGB')
    return reference


def write_vector(path, jpeg):
    padded = jpeg + bytes(-len(jpeg) % 4)
    words = struct.unpack('<' + 'H'*(len(padded)//2), padded)
    path.write_text(''.join(f'{v:04x}\n' for v in words))


def compare_pixels(decoded, reference):
    from PIL import ImageChops, ImageStat
    stats = ImageStat.Stat(ImageChops.difference(decoded,reference))
    mae = sum(stats.mean)/3
    mse = sum(v*v for v in stats.rms)/3
    psnr = float('inf') if mse == 0 else 10*math.log10(255*255/mse)
    # This integer IDCT core is approximate; natural images need a tolerance
    # larger than the sparse logo. Require both mean error < 2/255 and > 40 dB.
    if mae >= 2 or psnr < 40:
        raise AssertionError(f'Pixel mismatch: MAE={mae}, PSNR={psnr}')
    return f'MAE={mae:.6f}/255 PSNR={psnr:.3f}dB'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('image', type=Path)
    parser.add_argument('--iverilog', required=True, type=Path)
    parser.add_argument('--media', type=int, default=0)
    parser.add_argument('--frame', type=int, default=0)
    parser.add_argument('--alignments', action='store_true')
    parser.add_argument('--second-media', type=int, help='Run A -> B -> A without reset')
    args = parser.parse_args()
    if args.alignments and args.second_media is not None:
        parser.error('Choose alignments or a media sequence')
    from PIL import Image, ImageChops, ImageStat
    root = Path(__file__).resolve().parents[1]
    original = read_frame(args.image, args.media, args.frame)
    length = len(original)
    reference = software_reference(original)
    print(f'Image media={args.media} frame={args.frame} bytes={length} '
          f'last_word_index=0x{(length+3)//4-1:04X}', flush=True)
    variants = [original]
    if args.alignments:
        # Extend the existing APP0 metadata, preserving marker alignment of
        # the stream prefix and leaving every compressed scan byte unchanged.
        if original[2:4] != b'\xff\xe0':
            raise ValueError('Alignment variants require an initial APP0 segment')
        app_length = struct.unpack('>H',original[4:6])[0]
        end = 4+app_length
        variants += [original[:4]+struct.pack('>H',app_length+n)+original[6:end]+bytes(n)+original[end:]
                     for n in (1,2,3)]
    with tempfile.TemporaryDirectory(prefix='tfmedia3-frame-') as temp:
        work = Path(temp)
        target = work/'frame.vvp'
        exe = args.iverilog.resolve()
        vvp = exe.with_name('vvp.exe' if exe.suffix == '.exe' else 'vvp')
        subprocess.run([str(exe), '-g2012', '-s', 'tb_jpeg_display_completion', '-o', str(target),
                        str(root/'sim/tb_jpeg_display_completion.v'),
                        str(root/'user_source/hdl_source/tfmedia3/jpeg_decode_pipeline.v'),
                        *map(str, sorted((root/'third_party/core_jpeg/src_v').glob('*.v')))], check=True)

        def decode(item):
            index, jpeg = item
            case = work/str(index)
            case.mkdir()
            write_vector(case/'golden_first_jpeg.hex', jpeg)
            extra = []
            if args.second_media is not None:
                second = read_frame(args.image,args.second_media,0)
                write_vector(case/'second_jpeg.hex',second)
                extra = ['+sequence=1', f'+second_bytes={len(second)}']
            result = subprocess.run([str(vvp), str(target), f'+jpeg_bytes={len(jpeg)}', *extra],
                                    cwd=case, text=True, capture_output=True, check=True)
            if 'PASS' not in result.stdout or any(s in result.stdout for s in ('FATAL:', 'FAIL', 'ERROR:')):
                raise AssertionError(f'JPEG length {len(jpeg)}:\n{result.stdout}\n{result.stderr}')
            rgb = bytes.fromhex((case/'decoded.hex').read_text())
            decoded = Image.frombytes('RGB', (640, 480), rgb)
            metric = compare_pixels(decoded,reference)
            decoded.save(root/'sim'/f'frame_media{args.media}_variant{index}.png')
            reference.save(root/'sim'/f'reference_media{args.media}.png')
            if args.second_media is not None:
                if 'PASS: real JPEG A -> B -> A' not in result.stdout:
                    raise AssertionError('Incomplete frame sequence')
                for name, expected in [('decoded_b.hex',software_reference(second)),
                                       ('decoded_a2.hex',reference)]:
                    decoded_next = Image.frombytes('RGB',(640,480),bytes.fromhex((case/name).read_text()))
                    metric_next=compare_pixels(decoded_next,expected)
                    decoded_next.save(root/'sim'/f'sequence_{name}.png')
                    print(f'PASS: {name} {metric_next}',flush=True)
                print('PASS: real JPEG A -> B -> A, all three pixel arrays verified',flush=True)
            return f'PASS full frame: bytes={len(jpeg)} size%4={len(jpeg)%4} {metric}'

        with ThreadPoolExecutor(max_workers=2) as pool:
            for message in pool.map(decode, enumerate(variants)):
                print(message, flush=True)
    print('PASS: requested real JPEG frames decoded and matched software pixels', flush=True)


if __name__ == '__main__':
    main()
