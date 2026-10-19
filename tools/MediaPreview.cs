using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Threading;

// Decode on a background thread. The Forms timer only swaps completed frames.
// Keeping a single latest frame bounds memory regardless of video duration.
public sealed class TfVideoPreview : IDisposable {
    Process process;
    Thread reader;
    Bitmap latest;
    readonly object gate = new object();
    volatile bool stopping;
    public string Error { get; private set; }
    public bool Ended { get; private set; }
    public static string Quote(string s) { return "\"" + s.Replace("\"", "\\\"") + "\""; }
    public void Start(string ffmpeg, string source, double seconds) {
        var psi = new ProcessStartInfo(ffmpeg,
            "-nostdin -v error -re -ss " + seconds.ToString(System.Globalization.CultureInfo.InvariantCulture) +
            " -i " + Quote(source) + " -an -vf " +
            Quote("fps=12,scale=480:360:force_original_aspect_ratio=decrease,pad=480:360:(ow-iw)/2:(oh-ih)/2") +
            " -threads 1 -pix_fmt bgr24 -f rawvideo pipe:1");
        psi.UseShellExecute=false;psi.CreateNoWindow=true;
        psi.RedirectStandardOutput=true;psi.RedirectStandardError=true;
        process = new Process();process.StartInfo=psi;
        process.ErrorDataReceived += (s,e) => { if(e.Data!=null) Error=e.Data; };
        process.Start();process.BeginErrorReadLine();
        reader=new Thread(Read);reader.IsBackground=true;reader.Start();
    }
    void Read() {
        try {
            byte[] bytes=new byte[480*360*3];
            while(!stopping) {
                int offset=0;
                while(offset<bytes.Length) {
                    int n=process.StandardOutput.BaseStream.Read(bytes,offset,bytes.Length-offset);
                    if(n==0) { Ended=true;return; } offset+=n;
                }
                var bitmap=new Bitmap(480,360,PixelFormat.Format24bppRgb);
                var data=bitmap.LockBits(new Rectangle(0,0,480,360),ImageLockMode.WriteOnly,PixelFormat.Format24bppRgb);
                Marshal.Copy(bytes,0,data.Scan0,bytes.Length);bitmap.UnlockBits(data);
                lock(gate) { if(latest!=null)latest.Dispose();latest=bitmap; }
            }
        } catch(Exception e) { if(!stopping)Error=e.Message; }
        finally { Ended=true; }
    }
    public Bitmap TakeFrame() { lock(gate) { var b=latest;latest=null;return b; } }
    public void Dispose() {
        stopping=true;
        if(process!=null) {
            try { if(!process.HasExited)process.Kill(); } catch(InvalidOperationException) {}
            if(reader!=null)reader.Join(1500);
            process.Dispose();process=null;
        }
        lock(gate) { if(latest!=null)latest.Dispose();latest=null; }
    }
}

// Process callbacks only update synchronized data; Forms polls on its UI timer.
public sealed class TfToolJob : IDisposable {
    readonly object gate = new object();
    readonly System.Text.StringBuilder output = new System.Text.StringBuilder();
    Process process;
    bool outDone, errDone;
    string phase = "";
    int progress;
    public void Start(ProcessStartInfo info) {
        process=new Process();process.StartInfo=info;
        process.OutputDataReceived+=(s,e)=>Receive(e.Data,false);
        process.ErrorDataReceived+=(s,e)=>Receive(e.Data,true);
        process.Start();process.BeginOutputReadLine();process.BeginErrorReadLine();
    }
    void Receive(string line,bool error) {
        lock(gate) {
            if(line==null) {if(error)errDone=true;else outDone=true;return;}
            if(line.StartsWith("PROGRESS ")) {
                var parts=line.Split(' ');long done,total;
                if(parts.Length==4 && long.TryParse(parts[2],out done) && long.TryParse(parts[3],out total) && total>0) {
                    phase=parts[1];progress=(int)Math.Min(100,done*100/total);
                }
            } else {
                if(output.Length>1048576)output.Remove(0,524288);
                output.AppendLine(line);
            }
        }
    }
    public bool HasExited {get {lock(gate){return process!=null && process.HasExited && outDone && errDone;}}}
    public int ExitCode {get{return process.ExitCode;}}
    public string Log {get{lock(gate){return output.ToString();}}}
    public string Phase {get{lock(gate){return phase;}}}
    public int Progress {get{lock(gate){return progress;}}}
    public void Dispose() {if(process!=null){process.Dispose();process=null;}}
}
