"""Decode image thumbnails and fixed-font subtitle previews for the desktop UI."""
import argparse
import json
from pathlib import Path
from PIL import Image, ImageOps
import subtitles

def main():
    p=argparse.ArgumentParser();p.add_argument('mode',choices=['image','subtitle'])
    p.add_argument('source');p.add_argument('output');args=p.parse_args()
    if args.mode=='image':
        with Image.open(args.source) as source:
            im=ImageOps.exif_transpose(source).convert('RGB')
            ImageOps.pad(im,(640,480),color='black').save(args.output)
    else:
        data=json.loads(Path(args.source).read_text(encoding='utf-8-sig'))
        subtitles.preview(data,args.output)
if __name__=='__main__':main()
