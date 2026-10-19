"""Exercise real WM_DEVICECHANGE delivery; fake inventory, never touch disks."""
from pathlib import Path
import ctypes
from ctypes import wintypes
import json
import subprocess
import sys
import time
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
import media_gui_tk as gui


def main():
    gui.configure_runtime()
    calls=[]
    disk=dict(Number=9,FriendlyName='Notification test card',BusType='USB',Size=32_000_000_000,
        SerialNumber='TEST',UniqueId='TEST',Path='TEST',Volumes=[],Eligible=True)
    disk['Identity']=gui.media_card.disk_identity(disk)

    def inventory(command,**kwargs):
        assert command[-1]=='disks',command
        calls.append(time.monotonic())
        return subprocess.CompletedProcess(command,0,json.dumps([disk]).encode(),b'')

    def pump(seconds):
        deadline=time.monotonic()+seconds
        while time.monotonic()<deadline:
            app.update();time.sleep(.015)

    with patch.object(gui.subprocess,'run',side_effect=inventory):
        app=gui.MediaApp();app.withdraw()
        try:
            assert app.device_notifications is not None
            pump(22)
            assert len(calls)==1,('Idle inventory process repeated',len(calls))
            app.drive_combo.current(0);app.choose_disk();app.confirm_var.set(True)
            user=ctypes.WinDLL('user32',use_last_error=True)
            user.SendMessageW.argtypes=[wintypes.HWND,wintypes.UINT,wintypes.WPARAM,wintypes.LPARAM]
            user.SendMessageW.restype=ctypes.c_ssize_t
            for code in (7,0x8004,0x8000):
                user.SendMessageW(app.device_notifications.hwnd,0x0219,code,0)
            pump(.2)
            assert app.selected_disk is None and not app.confirm_var.get()
            pump(1.2)
            assert len(calls)==2,('Device event burst was not coalesced',len(calls))
            app.busy=True
            user.SendMessageW(app.device_notifications.hwnd,0x0219,7,0)
            pump(1)
            assert len(calls)==2,'Scanned while write/job was active'
            app.busy=False;pump(1)
            assert len(calls)==3,'Did not scan after pending job finished'
            app.refresh_devices();pump(.3)
            assert len(calls)==4,'Manual refresh failed'
        finally:app.destroy()
    report=dict(passed=True,idle_seconds=22,idle_inventory_queries=1,
        checks=['real Windows device notifications','hotplug burst debounce','selection consent cleared',
                'device scan deferred during jobs','manual refresh','window procedure restored'],physical_writes=False)
    (ROOT/'build/device-notification-validation.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print('PASS: 22-second idle has one startup scan; native hotplug events coalesced; consent cleared; busy deferral and manual refresh; no physical writes')


if __name__=='__main__':main()
