"""Read-only safety tests; no Win32 device handle is opened."""
from pathlib import Path
import sys
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
import media_card as card


def main():
    disk=dict(Number=2,FriendlyName='Test USB reader',BusType='USB',Size=32_000_000_000,
              SerialNumber='CARD-A',UniqueId='A',Path='reader-a',IsBoot=False,IsSystem=False,
              IsReadOnly=False,IsOffline=False,Volumes=[])
    identity=card.disk_identity(disk)
    assert card.disk_eligible(disk)
    with patch.object(card,'disks',return_value=[disk]):assert card.checked_disk(2,identity)==disk
    variants=[[],[dict(disk,SerialNumber='CARD-B')],[dict(disk,Size=64_000_000_000)],
              [dict(disk,UniqueId='B')],[dict(disk,Path='reader-b')],[dict(disk,IsBoot=True)],
              [dict(disk,IsSystem=True)],[dict(disk,IsReadOnly=True)],[dict(disk,IsOffline=True)],
              [dict(disk,BusType='NVMe')],[dict(disk,Size=0)]]
    for inventory in variants:
        with patch.object(card,'disks',return_value=inventory):
            try:card.checked_disk(2,identity)
            except ValueError:pass
            else:raise AssertionError('Unsafe or changed disk accepted: '+repr(inventory))
    assert card.disk_eligible(dict(disk,BusType='SD'))
    assert card.disk_eligible(dict(disk,BusType='MMC'))
    assert card.disk_identity(dict(disk,Volumes=[{'DriveLetter':'G'}]))==identity
    print('PASS: card identity, reused number, changed capacity/serial/path, removal, raw cards and protected disks; no physical writes')


if __name__=='__main__':main()
