"""TFMEDIA3 desktop tool: original workflow, fixed previews and card identity."""
from __future__ import annotations
import argparse
import ctypes
import json
import os
from pathlib import Path
import queue
import subprocess
import sys
import tempfile
import threading
import time
import tkinter as tk
from tkinter import ttk, filedialog, messagebox
from PIL import Image, ImageOps, ImageTk
import subtitles
import media_card

ROOT=Path(__file__).resolve().parents[1]
CREATE_NO_WINDOW=0x08000000 if os.name=='nt' else 0
VIDEO={'.mp4','.mkv','.avi','.mov','.wmv','.webm','.m4v','.mpg','.mpeg'}
IMAGES=media_card.IMAGE_SUFFIXES
TYPES=[('图片与视频','*.png *.jpg *.jpeg *.bmp *.tif *.tiff *.webp *.mp4 *.mkv *.avi *.mov *.wmv *.webm *.m4v *.mpg *.mpeg'),('所有文件','*.*')]


def admin():
    return os.name=='nt' and bool(ctypes.windll.shell32.IsUserAnAdmin())


def configure_runtime():
    runtime=Path(sys.executable).parent
    if (runtime/'_tcl_data').exists():
        os.environ['TCL_LIBRARY']=str(runtime/'_tcl_data')
        os.environ['TK_LIBRARY']=str(runtime/'_tk_data')
    config=ROOT/'.runtime/current.json'
    if config.exists():
        data=json.loads(config.read_text(encoding='utf-8-sig'))
        os.environ['TFMEDIA_FFMPEG']=str(ROOT/data['ffmpeg'])
    os.environ['PYTHONUTF8']='1'
    os.environ['PYTHONIOENCODING']='utf-8'


def capacity(size):
    return f'{int(size)/1_000_000_000:.2f} GB ({int(size)/2**30:.2f} GiB)'


def volume_names(disk):
    parts=[]
    for v in disk.get('Volumes',[]):
        letter=v.get('DriveLetter','').strip('\x00')
        if letter:parts.append(letter+':'+(' '+v.get('Label','') if v.get('Label') else ''))
    return ' / '.join(parts) or '无盘符（裸卡 / 未分区）'


def disk_label(disk):
    return f'{volume_names(disk)}  |  {int(disk["Size"])/1_000_000_000:.2f} GB  |  {disk["FriendlyName"]}  |  磁盘 {disk["Number"]}'


class DeviceNotifications:
    """Forward Windows device notifications to the UI queue without polling."""
    def __init__(self,window,events):
        from ctypes import wintypes as wt
        self.events=events;self.user=ctypes.WinDLL('user32',use_last_error=True)
        self.hwnd=int(window.tk.call('wm','frame',window._w),16)
        self.callback_type=ctypes.WINFUNCTYPE(ctypes.c_ssize_t,wt.HWND,wt.UINT,wt.WPARAM,wt.LPARAM)
        self.setter=getattr(self.user,'SetWindowLongPtrW',self.user.SetWindowLongW)
        self.setter.argtypes=[wt.HWND,ctypes.c_int,ctypes.c_void_p];self.setter.restype=ctypes.c_void_p
        self.user.CallWindowProcW.argtypes=[ctypes.c_void_p,wt.HWND,wt.UINT,wt.WPARAM,wt.LPARAM]
        self.user.CallWindowProcW.restype=ctypes.c_ssize_t
        self.callback=self.callback_type(self.receive)
        ctypes.set_last_error(0)
        self.previous=self.setter(self.hwnd,-4,ctypes.cast(self.callback,ctypes.c_void_p))
        if not self.previous:raise ctypes.WinError(ctypes.get_last_error())

    def receive(self,hwnd,message,wparam,lparam):
        if message==0x0219 and wparam in (7,0x8000,0x8004):
            self.events.put(('device_change',))
        return self.user.CallWindowProcW(self.previous,hwnd,message,wparam,lparam)

    def close(self):
        if self.previous:
            self.setter(self.hwnd,-4,self.previous);self.previous=None


class VideoPreview:
    """One retained frame; worker threads never call Tcl/Tk."""
    def __init__(self,source,seconds=0):
        self.lock=threading.Lock();self.latest=None;self.error='';self.ended=False
        ffmpeg=media_card.find_ffmpeg(None)
        self.process=subprocess.Popen([ffmpeg,'-nostdin','-v','error','-re','-ss',str(seconds),'-i',str(source),
            '-an','-vf','fps=12,scale=480:360:force_original_aspect_ratio=decrease,pad=480:360:(ow-iw)/2:(oh-ih)/2',
            '-threads','1','-pix_fmt','rgb24','-f','rawvideo','pipe:1'],stdout=subprocess.PIPE,stderr=subprocess.PIPE,
            creationflags=CREATE_NO_WINDOW)
        self.reader=threading.Thread(target=self.read,daemon=True);self.reader.start()
        threading.Thread(target=self.read_errors,daemon=True).start()

    def read_errors(self):
        try:
            text=self.process.stderr.read().decode('utf-8',errors='replace').strip()
            if text:self.error=text[-500:]
        except (OSError,ValueError):pass

    def read(self):
        try:
            size=480*360*3
            while True:
                chunks=bytearray()
                while len(chunks)<size:
                    chunk=self.process.stdout.read(size-len(chunks))
                    if not chunk:return
                    chunks.extend(chunk)
                frame=Image.frombytes('RGB',(480,360),bytes(chunks))
                with self.lock:self.latest=frame
        except (OSError,ValueError) as exc:self.error=str(exc)
        finally:self.ended=True

    def take(self):
        with self.lock:frame=self.latest;self.latest=None;return frame

    def stop(self):
        if self.process.poll() is None:
            self.process.terminate()
            try:self.process.wait(timeout=2)
            except subprocess.TimeoutExpired:self.process.kill();self.process.wait()
        self.reader.join(timeout=2)
        self.process.stdout.close()


class MediaApp(tk.Tk):
    def __init__(self,smoke=False):
        super().__init__()
        self.smoke=smoke;self.sources=[];self.events=queue.Queue();self.video=None
        self.photo=None;self.preview_image=None;self.preview_token=0;self.busy=False
        self.process=None;self.disks=[];self.selected_disk=None;self.disk_loading=False
        self.discovered=set();self.rows=[];self.temp=Path(tempfile.mkdtemp(prefix='tfmedia-studio-'))
        self.output_var=tk.StringVar(value=str(ROOT/'tf_media.img'))
        self.drive_var=tk.StringVar();self.confirm_var=tk.BooleanVar();self.audio_var=tk.BooleanVar(value=True)
        self.seek_var=tk.StringVar(value='0');self.status_var=tk.StringVar(value='就绪 · 最多 10 个视频和 10 张图片')
        self.title('FPGA TF 媒体制作工具 · 字幕增强版')
        self.geometry('1080x720');self.minsize(1000,680)
        self.configure(bg='#eef2f6');self.protocol('WM_DELETE_WINDOW',self.close)
        self.device_notifications=None;self.device_refresh_timer=None
        self.build_ui();self.update_idletasks()
        if os.name=='nt':
            try:self.device_notifications=DeviceNotifications(self,self.events)
            except OSError as exc:self.log_line('设备插拔通知不可用，请使用“刷新”按钮：'+str(exc))
        self.after(50,self.poll);self.after(400,self.refresh_devices)
        if smoke:self.after(600,self.start_smoke)

    def build_ui(self):
        style=ttk.Style(self);style.theme_use('clam')
        style.configure('.',font=('Microsoft YaHei UI',9),background='#eef2f6',foreground='#223047')
        style.configure('TButton',padding=(10,6),width=0,background='#ffffff',bordercolor='#cbd5e1')
        style.map('TButton',background=[('active','#e2e8f0'),('disabled','#edf0f4')])
        style.configure('Primary.TButton',background='#1766b5',foreground='white',bordercolor='#1766b5')
        style.map('Primary.TButton',background=[('active','#0f5296'),('disabled','#94a3b8')])
        style.configure('TLabelframe',background='#f8fafc',bordercolor='#cbd5e1',relief='solid')
        style.configure('TLabelframe.Label',font=('Microsoft YaHei UI',10,'bold'),background='#eef2f6')
        style.configure('TNotebook.Tab',padding=(18,8))
        style.configure('TEntry',fieldbackground='white',padding=4)
        header=ttk.Frame(self,padding=(18,10));header.pack(fill='x')
        ttk.Label(header,text='FPGA TF 媒体制作工具',font=('Microsoft YaHei UI',17,'bold')).pack(side='left')
        ttk.Label(header,text='TFMEDIA3  ·  640 × 480 / 25 fps',foreground='#64748b').pack(side='right')
        self.tabs=ttk.Notebook(self);self.tabs.pack(fill='both',expand=True,padx=14,pady=(0,6))
        self.main=ttk.Frame(self.tabs,padding=10);self.subtab=ttk.Frame(self.tabs,padding=14)
        self.logtab=ttk.Frame(self.tabs,padding=10)
        self.tabs.add(self.main,text='媒体与写卡');self.tabs.add(self.subtab,text='字幕设置 · 最多 10 条');self.tabs.add(self.logtab,text='任务记录')
        self.main.columnconfigure(0,weight=1);self.main.rowconfigure(0,weight=1)
        top=ttk.Frame(self.main);top.grid(row=0,column=0,sticky='nsew');top.rowconfigure(0,weight=1)
        top.columnconfigure(0,weight=1);top.columnconfigure(1,weight=1)
        source=ttk.LabelFrame(top,text='1. 播放内容（按列表顺序循环）',padding=10)
        source.grid(row=0,column=0,sticky='nsew',padx=(0,8));source.rowconfigure(1,weight=1);source.columnconfigure(0,weight=1)
        bar=ttk.Frame(source);bar.grid(row=0,column=0,columnspan=2,sticky='ew',pady=(0,8))
        self.source_buttons=[]
        for text,command in [('添加文件',self.add_files),('添加目录',self.add_folder),('删除',self.remove),('上移',lambda:self.move(-1)),('下移',lambda:self.move(1)),('清空',self.clear)]:
            b=ttk.Button(bar,text=text,command=command,padding=(5,5));b.pack(side='left',padx=(0,3));self.source_buttons.append(b)
        self.source_list=tk.Listbox(source,selectmode='extended',exportselection=False,font=('Microsoft YaHei UI',10),
            bg='white',fg='#25354d',selectbackground='#dbeafe',selectforeground='#174b87',relief='flat',highlightthickness=1,highlightbackground='#d6dee8')
        self.source_list.grid(row=1,column=0,sticky='nsew');scroll=ttk.Scrollbar(source,command=self.source_list.yview)
        scroll.grid(row=1,column=1,sticky='ns');self.source_list.configure(yscrollcommand=scroll.set)
        self.source_list.bind('<<ListboxSelect>>',lambda e:self.show_preview())
        self.count_label=ttk.Label(source,text='图片 0 / 10    视频 0 / 10',foreground='#64748b');self.count_label.grid(row=2,column=0,sticky='w',pady=(7,0))
        right=ttk.LabelFrame(top,text='2. 预览与固定输出规格',padding=10);right.grid(row=0,column=1,sticky='nsew');right.columnconfigure(0,weight=1);right.rowconfigure(1,weight=1)
        ttk.Label(right,text='640×480 @ 25 fps · JPEG 4:2:0\n48 kHz / 16-bit / 单声道 · 图片停留 3 秒',foreground='#586980').grid(row=0,column=0,sticky='w',pady=(0,6))
        self.canvas=tk.Canvas(right,bg='#101820',highlightthickness=0,height=150)
        self.canvas.grid(row=1,column=0,sticky='nsew');self.canvas.bind('<Configure>',lambda e:self.render_preview())
        self.preview_caption=ttk.Label(right,text='选择图片自动预览；视频可播放与定位',foreground='#64748b',anchor='w',width=42,wraplength=430)
        self.preview_caption.grid(row=2,column=0,sticky='ew',pady=4)
        controls=ttk.Frame(right);controls.grid(row=3,column=0,sticky='ew')
        ttk.Button(controls,text='播放 / 重播',command=self.play_preview,padding=(6,4)).pack(side='left')
        ttk.Button(controls,text='停止',command=self.stop_preview,padding=(6,4)).pack(side='left',padx=4)
        ttk.Label(controls,text='秒：').pack(side='left');ttk.Entry(controls,textvariable=self.seek_var,width=6).pack(side='left')
        ttk.Button(controls,text='定位',command=self.play_preview,padding=(6,4)).pack(side='left',padx=4)
        ttk.Label(controls,text='预览静音',foreground='#64748b').pack(side='right')
        self.build_destination(self.main)
        self.build_subtitles()
        self.log=tk.Text(self.logtab,state='disabled',wrap='word',font=('Consolas',10),bg='#ffffff',relief='flat')
        self.log.pack(fill='both',expand=True)
        footer=ttk.Frame(self,padding=(16,3,16,10));footer.pack(side='bottom',fill='x',before=self.tabs)
        self.progress=ttk.Progressbar(footer,mode='determinate',maximum=100);self.progress.pack(fill='x',pady=(0,5))
        ttk.Label(footer,textvariable=self.status_var,wraplength=1020).pack(side='left')
        self.render_preview()

    def build_destination(self,parent):
        box=ttk.LabelFrame(parent,text='3. 生成镜像或写入 TF 卡',padding=10)
        box.grid(row=1,column=0,sticky='ew',pady=(10,0));box.columnconfigure(1,weight=1)
        ttk.Label(box,text='镜像文件：').grid(row=0,column=0,sticky='w')
        self.output_entry=ttk.Entry(box,textvariable=self.output_var);self.output_entry.grid(row=0,column=1,sticky='ew',padx=6)
        ttk.Button(box,text='浏览…',command=self.choose_output).grid(row=0,column=2)
        ttk.Label(box,text='TF 卡设备：').grid(row=1,column=0,sticky='w',pady=7)
        self.drive_combo=ttk.Combobox(box,textvariable=self.drive_var,state='readonly')
        self.drive_combo.grid(row=1,column=1,sticky='ew',padx=6,pady=7);self.drive_combo.bind('<<ComboboxSelected>>',self.choose_disk)
        actions=ttk.Frame(box);actions.grid(row=1,column=2)
        self.refresh_button=ttk.Button(actions,text='刷新',command=self.refresh_devices);self.refresh_button.pack(side='left')
        ttk.Button(actions,text='查看设备',command=self.show_disks).pack(side='left',padx=(4,0))
        self.card_detail=ttk.Label(box,text='正在读取设备列表…',foreground='#64748b',justify='left',wraplength=950)
        self.card_detail.grid(row=2,column=0,columnspan=3,sticky='w',pady=(0,5))
        checks=ttk.Frame(box);checks.grid(row=3,column=0,columnspan=3,sticky='ew')
        self.confirm_check=ttk.Checkbutton(checks,text='我确认上方设备是可清空的 TF 卡（写入将覆盖整张卡）',variable=self.confirm_var,command=self.update_actions)
        self.confirm_check.pack(side='left')
        ttk.Label(checks,text='已以管理员身份运行' if admin() else '写卡时需管理员身份',foreground='#167c2b' if admin() else '#ad6416').pack(side='right')
        row=ttk.Frame(box);row.grid(row=4,column=0,columnspan=3,sticky='ew',pady=(8,0))
        self.generate_button=ttk.Button(row,text='仅生成镜像',command=lambda:self.generate(False),style='Primary.TButton');self.generate_button.pack(side='left')
        self.write_button=ttk.Button(row,text='生成并写入 TF 卡',command=lambda:self.generate(True));self.write_button.pack(side='left',padx=6)
        self.existing_button=ttk.Button(row,text='写入已有镜像',command=self.write_existing);self.existing_button.pack(side='left')
        self.inspect_button=ttk.Button(row,text='检查镜像',command=self.inspect_image);self.inspect_button.pack(side='left',padx=6)
        self.cancel_button=ttk.Button(row,text='取消生成',command=self.cancel,state='disabled');self.cancel_button.pack(side='right')
        ttk.Checkbutton(row,text='保留视频声音',variable=self.audio_var).pack(side='right',padx=8)
        self.update_actions()

    def build_subtitles(self):
        self.subtab.columnconfigure(1,weight=1)
        ttk.Label(self.subtab,text='固定黑体 · 每条最多 32 字 · 空行忽略；全部为空时使用板上默认字幕',foreground='#586980').grid(row=0,column=0,columnspan=5,sticky='w',pady=(0,12))
        for i in range(10):
            text=tk.StringVar();rainbow=tk.BooleanVar();color='#FDE68A'
            ttk.Label(self.subtab,text=f'{i+1:02d}',foreground='#64748b').grid(row=i+1,column=0,padx=(0,12))
            valid=(self.register(lambda value:len(value)<=32),'%P')
            entry=ttk.Entry(self.subtab,textvariable=text,validate='key',validatecommand=valid)
            entry.grid(row=i+1,column=1,sticky='ew',pady=2)
            button=tk.Button(self.subtab,text=color,bg=color,fg='#223047',relief='flat',width=10,command=lambda n=i:self.choose_color(n))
            button.grid(row=i+1,column=2,padx=12)
            ttk.Checkbutton(self.subtab,text='炫彩文字',variable=rainbow).grid(row=i+1,column=3,padx=(0,12))
            ttk.Button(self.subtab,text='预览',command=lambda n=i:self.preview_subtitle(n),padding=(10,4)).grid(row=i+1,column=4)
            self.rows.append(dict(text=text,rainbow=rainbow,color=color,button=button))
        self.sub_canvas=tk.Canvas(self.subtab,bg='#111827',height=76,highlightthickness=0)
        self.sub_canvas.grid(row=11,column=0,columnspan=5,sticky='ew',pady=(14,8))
        ttk.Label(self.subtab,text='预览显示前 19 字；板上完整滚动。SW3 开启后 S0 下一条、S1 上一条，SW0～SW2 设置优先。',foreground='#64748b').grid(row=12,column=0,columnspan=5,sticky='w')
        controls=ttk.Frame(self.subtab);controls.grid(row=13,column=0,columnspan=5,sticky='w',pady=12)
        for text,command in [('保存字幕配置',self.save_subtitles),('载入字幕配置',self.load_subtitles),('清空字幕',self.clear_subtitles)]:ttk.Button(controls,text=text,command=command).pack(side='left',padx=(0,8))

    def add_files(self):
        files=filedialog.askopenfilenames(parent=self,title='选择图片或视频',filetypes=TYPES)
        self.add_paths(files)

    def add_folder(self):
        folder=filedialog.askdirectory(parent=self,title='选择媒体目录')
        if folder:self.add_paths(sorted(Path(folder).iterdir()))

    def add_paths(self,files):
        for p in files:
            p=Path(p)
            if p.is_file() and p.suffix.lower() in IMAGES|VIDEO and p not in self.sources:self.sources.append(p)
        self.refresh_list(len(self.sources)-1)

    def refresh_list(self,index=None):
        self.source_list.delete(0,'end')
        for i,p in enumerate(self.sources):self.source_list.insert('end',f'{i+1:02d}. [{"图片" if p.suffix.lower() in IMAGES else "视频"}] {p.name}')
        n=sum(p.suffix.lower() in IMAGES for p in self.sources)
        self.count_label.configure(text=f'图片 {n} / 10    视频 {len(self.sources)-n} / 10',foreground='#b42318' if n>10 or len(self.sources)-n>10 else '#64748b')
        if self.sources and index is not None:
            index=max(0,min(index,len(self.sources)-1));self.source_list.selection_set(index);self.source_list.see(index);self.show_preview()
        elif not self.sources:self.stop_preview();self.preview_image=None;self.render_preview()

    def remove(self):
        selected=self.source_list.curselection()
        for i in reversed(selected):del self.sources[i]
        self.refresh_list(selected[0] if selected else None)

    def move(self,direction):
        selected=self.source_list.curselection()
        if len(selected)!=1:return
        i=selected[0];j=i+direction
        if 0<=j<len(self.sources):self.sources[i],self.sources[j]=self.sources[j],self.sources[i];self.refresh_list(j)

    def clear(self):self.sources.clear();self.refresh_list()

    def selected_source(self):
        selected=self.source_list.curselection()
        return self.sources[selected[0]] if selected else None

    def stop_preview(self):
        self.preview_token+=1
        if self.video:self.video.stop();self.video=None

    def show_preview(self):
        source=self.selected_source()
        if not source:return
        self.stop_preview();self.preview_image=None;self.render_preview();self.seek_var.set('0')
        self.preview_caption.configure(text=source.name)
        if source.suffix.lower() in VIDEO:self.play_preview();return
        token=self.preview_token
        def decode():
            try:
                with Image.open(source) as im:
                    im=ImageOps.exif_transpose(im).convert('RGB');im.thumbnail((960,720));image=im.copy()
                self.events.put(('image',token,image))
            except Exception as exc:self.events.put(('preview_error',token,str(exc)))
        threading.Thread(target=decode,daemon=True).start()

    def play_preview(self):
        source=self.selected_source()
        if not source or source.suffix.lower() not in VIDEO:return
        try:
            seconds=float(self.seek_var.get())
            if not 0<=seconds<=86400:raise ValueError('定位秒数应在 0～86400 之间')
            self.stop_preview();self.video=VideoPreview(source,seconds)
            self.preview_caption.configure(text=f'{source.name} · 静音预览 · 从 {seconds:g} 秒播放')
        except Exception as exc:self.preview_caption.configure(text='预览失败：'+str(exc))

    def render_preview(self):
        self.canvas.delete('all');w=max(self.canvas.winfo_width(),100);h=max(self.canvas.winfo_height(),100)
        if self.preview_image:
            image=ImageOps.contain(self.preview_image,(w,h),Image.Resampling.BILINEAR)
            self.photo=ImageTk.PhotoImage(image,master=self)
            self.canvas.create_image(w//2,h//2,image=self.photo)
        else:self.canvas.create_text(w//2,h//2,text='选择图片或视频，查看预览',fill='#9caec3',font=('Microsoft YaHei UI',12))

    def subtitle_config(self):
        return {'subtitles':[dict(text=r['text'].get(),color=r['color'],rainbow=r['rainbow'].get()) for r in self.rows]}

    def choose_color(self,index):
        row=self.rows[index];chosen=self.tk.call('tk_chooseColor','-initialcolor',row['color'],'-parent',self._w,'-title','选择字幕颜色')
        if chosen:
            row['color']=chosen.upper();rgb=tuple(int(chosen[i:i+2],16) for i in (1,3,5))
            row['button'].configure(text=chosen.upper(),bg=chosen,fg='white' if sum(rgb)<360 else '#223047')

    def preview_subtitle(self,index):
        row=self.rows[index]
        try:
            path=self.temp/'subtitle.png';subtitles.preview(dict(text=row['text'].get(),color=row['color'],rainbow=row['rainbow'].get()),path)
            with Image.open(path) as im:self.sub_photo=ImageTk.PhotoImage(im.copy(),master=self)
            self.sub_canvas.delete('all');self.sub_canvas.create_image(8,0,image=self.sub_photo,anchor='nw')
        except Exception as exc:messagebox.showerror('字幕预览',str(exc),parent=self)

    def save_subtitles(self):
        path=filedialog.asksaveasfilename(parent=self,defaultextension='.json',filetypes=[('字幕配置','*.json')])
        if path:
            try:subtitles.normalize(self.subtitle_config());Path(path).write_text(json.dumps(self.subtitle_config(),ensure_ascii=False,indent=2),encoding='utf-8')
            except Exception as exc:messagebox.showerror('保存失败',str(exc),parent=self)

    def load_subtitles(self):
        path=filedialog.askopenfilename(parent=self,filetypes=[('字幕配置','*.json')])
        if not path:return
        try:
            entries=subtitles.load(path);self.clear_subtitles()
            for row,e in zip(self.rows,entries):
                row['text'].set(e['text']);row['color']=e['color'];row['rainbow'].set(e['rainbow']);row['button'].configure(text=e['color'],bg=e['color'])
        except Exception as exc:messagebox.showerror('载入失败',str(exc),parent=self)

    def clear_subtitles(self):
        for row in self.rows:row['text'].set('');row['rainbow'].set(False)
        self.sub_canvas.delete('all')

    def choose_output(self):
        path=filedialog.asksaveasfilename(parent=self,title='保存裸卡镜像',defaultextension='.img',initialfile='tf_media.img',filetypes=[('TFMEDIA3 镜像','*.img')])
        if path:self.output_var.set(path)

    def refresh_devices(self,automatic=False):
        if self.disk_loading or self.busy:return
        self.disk_loading=True;self.refresh_button.configure(state='disabled')
        if not automatic:self.confirm_var.set(False)
        def scan():
            try:
                result=subprocess.run([sys.executable,str(ROOT/'tools/media_card.py'),'disks'],capture_output=True,creationflags=CREATE_NO_WINDOW,timeout=30)
                if result.returncode:raise ValueError(result.stderr.decode('utf-8',errors='replace'))
                self.events.put(('disks',json.loads(result.stdout.decode('utf-8-sig')),automatic))
            except Exception as exc:self.events.put(('disk_error',str(exc)))
        threading.Thread(target=scan,daemon=True).start()

    def apply_disks(self,disks,automatic=False):
        self.disk_loading=False;self.refresh_button.configure(state='normal')
        previous=self.selected_disk;self.disks=disks;self.eligible=[d for d in disks if d.get('Eligible')]
        self.drive_combo.configure(values=[disk_label(d) for d in self.eligible])
        current=next((d for d in self.eligible if previous and d['Identity']==previous['Identity']),None)
        if automatic and current:
            self.drive_var.set(disk_label(current));self.selected_disk=current
        else:
            self.selected_disk=None;self.drive_var.set('');self.confirm_var.set(False)
        if self.selected_disk:self.describe_disk()
        else:
            text=('发现 '+str(len(self.eligible))+' 个可写外接设备，请按盘符、容量和型号选择。' if self.eligible else '未发现可写 USB / SD / MMC 设备。请插入读卡器后点“刷新”；内置磁盘不会列为写入目标。')
            if previous and not current:text='原选中设备已移除或身份变化，请重新选择。 '+text
            self.card_detail.configure(text=text,foreground='#a85b13' if self.eligible else '#b42318')
        self.update_actions()

    def device_changed(self):
        # Clear consent immediately; a device may disappear while a scan is active.
        self.selected_disk=None;self.drive_var.set('');self.confirm_var.set(False);self.update_actions()
        if self.device_refresh_timer:self.after_cancel(self.device_refresh_timer)
        self.device_refresh_timer=self.after(750,self.refresh_changed_devices)

    def refresh_changed_devices(self):
        self.device_refresh_timer=None
        if self.busy or self.disk_loading:
            self.device_refresh_timer=self.after(750,self.refresh_changed_devices);return
        self.refresh_devices(automatic=True)

    def choose_disk(self,event=None):
        i=self.drive_combo.current();self.selected_disk=self.eligible[i] if 0<=i<len(self.eligible) else None
        self.confirm_var.set(False);self.describe_disk();self.update_actions()

    def describe_disk(self):
        d=self.selected_disk
        if not d:return
        serial=(d.get('SerialNumber') or d.get('UniqueId') or '未提供').strip()
        self.card_detail.configure(text=f'目标：磁盘 {d["Number"]}  ·  {volume_names(d)}  ·  {capacity(d["Size"])}\n型号：{d["FriendlyName"]}  |  接口：{d["BusType"]}  |  序列号：{serial}',foreground='#145487')

    def show_disks(self):
        dialog=tk.Toplevel(self);dialog.title('设备识别详情（只读）');dialog.geometry('880x400');dialog.transient(self)
        ttk.Label(dialog,text='写卡目标仅允许可写的 USB / SD / MMC；USB 设备也可能是移动硬盘，请核对容量和型号。',padding=12).pack(anchor='w')
        columns=('number','volumes','size','name','bus','state')
        tree=ttk.Treeview(dialog,columns=columns,show='headings',height=10);tree.pack(fill='both',expand=True,padx=12)
        for name,title,width in zip(columns,['磁盘编号','盘符 / 卷标','容量 GB','设备型号','接口','写入状态'],[70,150,85,230,70,130]):tree.heading(name,text=title);tree.column(name,width=width)
        for d in self.disks:
            reason='可选外接设备' if d.get('Eligible') else '受保护 / 非卡设备'
            tree.insert('','end',values=(d['Number'],volume_names(d),f'{d["Size"]/1e9:.2f}',d['FriendlyName'],d['BusType'],reason))
        ttk.Label(dialog,text='裸卡写入后没有 Windows 盘符也属正常，仍可根据物理编号、容量和型号识别。',padding=12).pack(anchor='w')

    def update_actions(self):
        state='normal' if not self.busy else 'disabled'
        for b in [self.generate_button,self.inspect_button,*self.source_buttons]:b.configure(state=state)
        allowed=not self.busy and self.selected_disk is not None and self.confirm_var.get()
        for b in [self.write_button,self.existing_button]:b.configure(state='normal' if allowed else 'disabled')
        self.drive_combo.configure(state='disabled' if self.busy else 'readonly')
        self.confirm_check.configure(state=state)

    def confirm_target(self):
        if self.smoke:raise ValueError('自动验证模式禁止物理磁盘写入')
        d=self.selected_disk
        if not d or not self.confirm_var.get():raise ValueError('请先选择 TF 卡，并勾选覆盖确认框')
        if not admin():raise ValueError('请关闭程序，以管理员身份运行“以管理员身份运行.bat”后再写卡。工程目录可右键启动文件选择管理员运行。普通生成镜像无需管理员权限。')
        dialog=tk.Toplevel(self);dialog.title('最后确认 · 覆盖整张卡');dialog.transient(self);dialog.grab_set();dialog.resizable(False,False)
        token=f'磁盘 {d["Number"]}'
        text=f'将覆盖以下设备的全部分区和数据：\n\n{disk_label(d)}\n容量：{capacity(d["Size"])}\n序列号：{(d.get("SerialNumber") or d.get("UniqueId") or "未提供").strip()}\n\n请再次核对设备。输入“{token}”后才能继续。'
        ttk.Label(dialog,text=text,padding=18,wraplength=650,justify='left').pack()
        value=tk.StringVar();entry=ttk.Entry(dialog,textvariable=value,width=35);entry.pack(padx=18,pady=6);entry.focus_set()
        result=[];buttons=ttk.Frame(dialog,padding=14);buttons.pack(fill='x')
        accept=ttk.Button(buttons,text='确认覆盖并开始',state='disabled',command=lambda:(result.append(True),dialog.destroy()))
        accept.pack(side='right');ttk.Button(buttons,text='取消',command=dialog.destroy).pack(side='right',padx=8)
        value.trace_add('write',lambda *args:accept.configure(state='normal' if value.get().strip()==token else 'disabled'))
        dialog.bind('<Escape>',lambda e:dialog.destroy());self.wait_window(dialog)
        return dict(d) if result else None

    def validate_sources(self):
        if not self.sources:raise ValueError('请先添加图片或视频')
        images=sum(p.suffix.lower() in IMAGES for p in self.sources)
        if images>10 or len(self.sources)-images>10:raise ValueError('最多支持 10 张图片和 10 个视频')
        output=Path(self.output_var.get().strip())
        if not self.output_var.get().strip() or output.suffix.lower()!='.img':raise ValueError('请选择 .img 镜像输出文件')
        subtitles.normalize(self.subtitle_config())
        return output

    def generate(self,write=False):
        try:
            output=self.validate_sources();disk=self.confirm_target() if write else None
            if write and not disk:return
            if output.exists() and not messagebox.askyesno('覆盖镜像文件',f'镜像文件已存在，是否替换？\n{output}',parent=self):return
            config=self.temp/'subtitles.json';config.write_text(json.dumps(self.subtitle_config(),ensure_ascii=False),encoding='utf-8')
            args=['pack',*map(str,self.sources),'-o',str(output),'--subtitles',str(config)]
            if self.audio_var.get():args.append('--audio')
            self.start_job(args,'pack',output,disk)
        except Exception as exc:messagebox.showerror('无法开始',str(exc),parent=self)

    def write_existing(self):
        try:
            path=filedialog.askopenfilename(parent=self,title='选择已有镜像',filetypes=[('TFMEDIA3 镜像','*.img')])
            if not path:return
            disk=self.confirm_target()
            if disk:self.start_write(Path(path),disk)
        except Exception as exc:messagebox.showerror('无法写卡',str(exc),parent=self)

    def inspect_image(self):
        path=filedialog.askopenfilename(parent=self,title='检查镜像',filetypes=[('TFMEDIA3 镜像','*.img')])
        if path:self.start_job(['inspect',path],'inspect',Path(path))

    def start_write(self,path,disk):
        if self.smoke:raise ValueError('自动验证模式禁止物理磁盘写入')
        self.start_job(['write',str(path),'--disk',str(disk['Number']),'--confirm-disk',str(disk['Number']),'--disk-identity',disk['Identity']],'write',path,disk)

    def start_job(self,args,kind,path=None,disk=None):
        if self.busy:raise ValueError('已有任务正在执行')
        self.busy=True;self.job_kind=kind;self.job_path=path;self.job_disk=disk;self.cancelled=False
        self.progress.configure(mode='indeterminate',value=0);self.progress.start(12)
        self.status_var.set({'pack':'正在转换媒体并生成镜像…','inspect':'正在检查镜像…','write':'正在核对设备身份、写入并回读校验…'}[kind])
        self.cancel_button.configure(state='normal' if kind=='pack' else 'disabled');self.update_actions()
        self.log_line('\n'+time.strftime('%H:%M:%S')+'  '+self.status_var.get())
        def run():
            lines=[];code=1
            try:
                self.process=subprocess.Popen([sys.executable,str(ROOT/'tools/media_card.py'),*args],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,
                    text=True,encoding='utf-8',errors='replace',creationflags=CREATE_NO_WINDOW)
                if self.cancelled:self.process.terminate()
                for line in self.process.stdout:
                    if line.startswith('PROGRESS '):self.events.put(('progress',line.strip()))
                    else:lines.append(line);self.events.put(('log',line.rstrip()))
                code=self.process.wait();self.process.stdout.close()
            except Exception as exc:lines.append(str(exc));self.events.put(('log',str(exc)))
            finally:self.events.put(('job_done',code,''.join(lines)))
        threading.Thread(target=run,daemon=True).start()

    def cancel(self):
        if self.busy and self.job_kind=='pack':
            self.cancelled=True
            if self.process and self.process.poll() is None:self.process.terminate()
            self.status_var.set('正在取消生成…')

    def finish_job(self,code,text):
        kind=self.job_kind;path=self.job_path;disk=self.job_disk
        self.process=None;self.busy=False;self.progress.stop();self.progress.configure(mode='determinate',value=100 if code==0 else 0)
        self.cancel_button.configure(state='disabled');self.update_actions()
        if code==0:
            self.status_var.set({'pack':'镜像生成成功 · '+str(path),'inspect':'镜像结构与校验检查通过','write':'写卡成功 · 全量回读 SHA-256 校验通过'}[kind])
            if kind=='pack' and disk:self.start_write(path,disk);return
        else:
            self.status_var.set('生成已取消' if self.cancelled else '任务失败 · 原因见“任务记录”')
            if not self.smoke and not self.cancelled:messagebox.showerror('任务失败',text[-1400:],parent=self)
        if self.smoke:self.events.put(('smoke_job',kind,code,text))

    def log_line(self,text):
        self.log.configure(state='normal');self.log.insert('end',text+'\n');self.log.see('end');self.log.configure(state='disabled')

    def poll(self):
        try:
            while True:
                event=self.events.get_nowait();kind=event[0]
                if kind=='image' and event[1]==self.preview_token:self.preview_image=event[2];self.render_preview()
                elif kind=='preview_error' and event[1]==self.preview_token:self.preview_caption.configure(text='图片预览失败：'+event[2])
                elif kind=='disks':self.apply_disks(event[1],event[2])
                elif kind=='device_change':self.device_changed()
                elif kind=='disk_error':
                    self.disk_loading=False;self.refresh_button.configure(state='normal');self.apply_disks([])
                    self.card_detail.configure(text='设备读取失败，请刷新重试；详细原因见任务记录。',foreground='#b42318');self.log_line(event[1])
                elif kind=='log':self.log_line(event[1])
                elif kind=='progress':
                    _,phase,done,total=event[1].split();percentage=int(done)*100/max(int(total),1)
                    self.progress.stop();self.progress.configure(mode='determinate',value=percentage)
                    self.status_var.set(('正在写入 TF 卡' if phase=='write' else '正在全量回读校验')+f' · {percentage:.0f}%')
                elif kind=='job_done':self.finish_job(event[1],event[2])
                elif kind=='smoke_job':self.smoke_job_result=event[1:]
        except queue.Empty:pass
        if self.video:
            frame=self.video.take()
            if frame:self.preview_image=frame;self.render_preview()
            if self.video.ended:
                error=self.video.error;self.stop_preview()
                self.preview_caption.configure(text='视频预览失败：'+error if error else '视频预览结束，可重播或输入秒数定位')
        self.after(50,self.poll)

    def close(self):
        if self.busy:
            messagebox.showinfo('任务正在进行','请等待写卡与回读校验结束；生成镜像时可以先点“取消生成”。',parent=self);return
        self.stop_preview();self.destroy()

    def destroy(self):
        if self.device_notifications:self.device_notifications.close()
        super().destroy()

    def screenshot(self,name):
        self.update();folder=ROOT/'build';folder.mkdir(exist_ok=True)
        # Capture this window only; other desktop windows never enter the image.
        from ctypes import wintypes as wt
        user=ctypes.windll.user32;gdi=ctypes.windll.gdi32
        hwnd=int(self.tk.call('wm','frame',self._w),16)
        rect=wt.RECT();user.GetWindowRect(wt.HWND(hwnd),ctypes.byref(rect));w=rect.right-rect.left;h=rect.bottom-rect.top
        class Header(ctypes.Structure):
            _fields_=[('size',wt.DWORD),('width',wt.LONG),('height',wt.LONG),('planes',wt.WORD),('bits',wt.WORD),
                      ('compression',wt.DWORD),('image_size',wt.DWORD),('x',wt.LONG),('y',wt.LONG),('used',wt.DWORD),('important',wt.DWORD)]
        user.GetDC.argtypes=[wt.HWND];user.GetDC.restype=wt.HDC
        gdi.CreateCompatibleDC.argtypes=[wt.HDC];gdi.CreateCompatibleDC.restype=wt.HDC
        gdi.CreateDIBSection.argtypes=[wt.HDC,ctypes.c_void_p,wt.UINT,ctypes.POINTER(ctypes.c_void_p),wt.HANDLE,wt.DWORD];gdi.CreateDIBSection.restype=wt.HBITMAP
        gdi.SelectObject.argtypes=[wt.HDC,wt.HANDLE];gdi.SelectObject.restype=wt.HANDLE
        gdi.DeleteObject.argtypes=[wt.HANDLE];gdi.DeleteDC.argtypes=[wt.HDC];user.ReleaseDC.argtypes=[wt.HWND,wt.HDC]
        screen=user.GetDC(wt.HWND(hwnd));dc=gdi.CreateCompatibleDC(screen);pixels=ctypes.c_void_p()
        header=Header(ctypes.sizeof(Header),w,-h,1,32,0,w*h*4,0,0,0,0)
        bitmap=gdi.CreateDIBSection(dc,ctypes.byref(header),0,ctypes.byref(pixels),None,0);previous=gdi.SelectObject(dc,bitmap)
        try:
            if not user.PrintWindow(wt.HWND(hwnd),wt.HDC(dc),2):raise OSError('Window capture failed')
            Image.frombytes('RGB',(w,h),ctypes.string_at(pixels,w*h*4),'raw','BGRX').save(folder/name)
        finally:gdi.SelectObject(dc,previous);gdi.DeleteObject(bitmap);gdi.DeleteDC(dc);user.ReleaseDC(wt.HWND(hwnd),screen)

    def start_smoke(self):
        self.smoke_step=0;self.smoke_deadline=time.monotonic()+75;self.smoke_job_result=None
        self.smoke_image=self.temp/'中文 预览图片.png';Image.new('RGB',(640,360),'#2468ab').save(self.smoke_image)
        self.smoke_video=self.temp/'中文 预览视频.mp4'
        command=[media_card.find_ffmpeg(None),'-y','-v','error','-f','lavfi','-i','color=c=red:s=320x180:r=12:d=3','-c:v','mpeg4',str(self.smoke_video)]
        def create():
            try:subprocess.run(command,check=True,creationflags=CREATE_NO_WINDOW);self.smoke_fixture_ready=True;self.events.put(('log','PASS: preview video fixture generated'))
            except Exception as exc:self.events.put(('log',str(exc)))
        threading.Thread(target=create,daemon=True).start()
        self.add_paths([self.smoke_image]);self.after(100,self.smoke_tick)

    def smoke_tick(self):
        try:
            if time.monotonic()>self.smoke_deadline:raise AssertionError('GUI smoke test timed out')
            if self.smoke_step==0 and self.preview_image and getattr(self,'smoke_fixture_ready',False):
                assert self.photo and self.preview_image.getpixel((10,10))==(36,104,171)
                self.rows[0]['text'].set('测试字幕 FPGA');self.rows[0]['color']='#22D3EE';self.preview_subtitle(0)
                self.tabs.select(self.subtab);self.screenshot('tk-subtitles.png')
                self.tabs.select(self.main);self.screenshot('tk-media.png')
                self.add_paths([self.smoke_video]);self.smoke_step=1
            elif self.smoke_step==1 and self.video and self.preview_image and self.preview_image.getpixel((240,180))[0]>200:
                self.seek_var.set('1');self.play_preview();self.preview_image=None;self.smoke_step=2
            elif self.smoke_step==2 and self.preview_image:
                assert self.preview_image.getpixel((240,180))[0]>200
                self.screenshot('tk-video.png');self.stop_preview()
                # Synthetic data is visibly marked; the smoke guard forbids physical writes.
                self.disk_loading=False
                fixture=dict(Number=9,FriendlyName='演示读卡器（仅界面测试）',BusType='USB',Size=31914983424,
                    SerialNumber='DEMO-NOT-A-REAL-CARD',UniqueId='demo-card',Path='demo',IsBoot=False,IsSystem=False,IsReadOnly=False,
                    IsOffline=False,PartitionStyle='MBR',Volumes=[dict(DriveLetter='G',Label='演示 TF 卡')])
                fixture['Identity']=media_card.disk_identity(fixture);fixture['Eligible']=True
                self.apply_disks([fixture]);assert self.selected_disk is None and not self.confirm_var.get()
                self.drive_combo.current(0);self.choose_disk();assert self.selected_disk['Number']==9
                self.confirm_var.set(True);self.update_actions();self.screenshot('tk-card-demo.png')
                self.apply_disks([],automatic=True);assert self.selected_disk is None and not self.confirm_var.get()
                for action in (self.confirm_target,lambda:self.start_write(self.temp/'forbidden.img',fixture)):
                    try:action()
                    except ValueError as exc:assert '禁止物理磁盘写入' in str(exc)
                    else:raise AssertionError('Smoke mode allowed physical writes')
                self.smoke_checks=['image preview','video playback and seek','subtitle preview','no automatic card selection','removed card clears confirmation','smoke mode forbids physical writes']
                config=self.temp/'subtitles.json';config.write_text(json.dumps(self.subtitle_config(),ensure_ascii=False),encoding='utf-8')
                self.start_job(['pack',str(self.smoke_image),str(self.smoke_video),'--audio','--subtitles',str(config),'-o',str(self.temp/'smoke.img')],'pack',self.temp/'smoke.img')
                self.smoke_step=3
            elif self.smoke_step==3 and self.smoke_job_result:
                kind,code,text=self.smoke_job_result;assert code==0,text
                report=media_card.inspect(self.temp/'smoke.img');assert len(report['media'])==2 and len(report['subtitles'])==1
                self.smoke_checks+=['image+video+audio+subtitle pack','complete image validation']
                (ROOT/'build/tk-gui-validation.json').write_text(json.dumps(dict(passed=True,checks=self.smoke_checks),indent=2),encoding='utf-8')
                print('PASS: '+', '.join(self.smoke_checks),flush=True);self.destroy();return
            self.after(80,self.smoke_tick)
        except Exception as exc:
            print('FAIL: '+repr(exc),flush=True)
            (ROOT/'build/tk-gui-validation.json').write_text(json.dumps(dict(passed=False,error=repr(exc))),encoding='utf-8')
            self.stop_preview();self.destroy();self.smoke_failed=True


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--smoke-test',action='store_true');args=parser.parse_args()
    configure_runtime()
    if os.name=='nt':
        try:ctypes.windll.shcore.SetProcessDpiAwareness(1)
        except (OSError,AttributeError):pass
    app=MediaApp(args.smoke_test);app.mainloop()
    return 1 if getattr(app,'smoke_failed',False) else 0


if __name__=='__main__':raise SystemExit(main())
