"""Verify portable project inputs and the accepted release artifact."""
from pathlib import Path
import hashlib
import json
import re

ROOT=Path(__file__).resolve().parents[1]
def main():
    count=0
    for project in sorted((ROOT/'td_project').glob('*.al')):
        text=project.read_text(encoding='utf-8-sig')
        for relative in re.findall(r'<File Path="([^"]+)"',text):
            assert not re.match(r'(?:[A-Za-z]:|/|\\)',relative), (project,relative)
            source=(project.parent/relative).resolve()
            assert source.is_relative_to(ROOT.resolve()) and source.is_file(), (project,relative)
            count+=1
    expected='d720296b1bc6d058de31c581583c3561c512d416f46b9e987cda86b5777e14d6'
    assert hashlib.sha256((ROOT/'firmware/08_player_avsync.bit').read_bytes()).hexdigest()==expected
    for dependency in json.loads((ROOT/'vendor/manifest.json').read_text(encoding='utf-8')):
        path=ROOT/'vendor'/dependency['file']
        assert hashlib.sha256(path.read_bytes()).hexdigest()==dependency['sha256'], path
    release=ROOT/'RELEASE_MANIFEST.json'
    if release.is_file():
        for item in json.loads(release.read_text(encoding='utf-8'))['files']:
            path=ROOT/item['path']
            assert hashlib.sha256(path.read_bytes()).hexdigest()==item['sha256'], path
        print('PASS: ZIP release manifest matches every delivered file')
    print(f'PASS: {count} relative TD references, accepted bitstream and offline dependency hashes')

if __name__=='__main__':main()
