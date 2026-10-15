"""Export committed portable deliverables; never delete or overwrite files."""
from pathlib import Path
from datetime import datetime
import hashlib
import json
import subprocess
import zipfile

ROOT=Path(__file__).resolve().parents[1]
def git(*args):
    return subprocess.check_output(['git','-C',str(ROOT),*args])

def main():
    status=git('status','--porcelain','--untracked-files=normal')
    if status.strip():
        raise SystemExit('Commit all deliverable changes before packaging. Check git status.')
    commit=git('rev-parse','HEAD').decode().strip()
    paths=[p.decode('utf-8') for p in git('ls-tree','-r','--name-only','-z','HEAD').split(b'\0') if p]
    output=ROOT/'dist';output.mkdir(exist_ok=True)
    name=f'useing-08-{datetime.now():%Y%m%d-%H%M%S-%f}-{commit[:8]}.zip'
    target=output/name
    records=[]
    with zipfile.ZipFile(target,'x',zipfile.ZIP_DEFLATED,compresslevel=6) as archive:
        for relative in paths:
            data=git('show',f'HEAD:{relative}')
            if relative.endswith(('.cmd','.ps1')):
                data=data.replace(b'\r\n',b'\n').replace(b'\n',b'\r\n')
            archive.writestr('useing/'+relative,data)
            records.append(dict(path=relative,bytes=len(data),sha256=hashlib.sha256(data).hexdigest()))
        manifest=dict(commit=commit,created=datetime.now().astimezone().isoformat(),files=records)
        archive.writestr('useing/RELEASE_MANIFEST.json',json.dumps(manifest,ensure_ascii=False,indent=2))
    digest=hashlib.sha256(target.read_bytes()).hexdigest()
    target.with_suffix('.zip.sha256').write_text(f'{digest}  {target.name}\n',encoding='utf-8')
    with zipfile.ZipFile(target) as archive:
        damaged=archive.testzip()
        if damaged:raise SystemExit('ZIP CRC failed: '+damaged)
    print(target)
    print('SHA256:',digest)
    print('Files:',len(records),'Bytes:',target.stat().st_size)

if __name__=='__main__':main()
