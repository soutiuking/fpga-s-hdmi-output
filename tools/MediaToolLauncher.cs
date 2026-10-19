using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

class MediaToolLauncher {
    [STAThread]
    static int Main(string[] args) {
        try {
            string root=AppDomain.CurrentDomain.BaseDirectory;
            var start=new ProcessStartInfo(Path.Combine(root,".runtime","python","pythonw.exe"));
            start.Arguments=Quote(Path.Combine(root,"tools","media_gui_tk.py"));
            foreach(string arg in args)start.Arguments+=" "+Quote(arg);
            start.WorkingDirectory=root;start.UseShellExecute=false;start.CreateNoWindow=true;
            using(var process=Process.Start(start)) { process.WaitForExit();return process.ExitCode; }
        } catch(Exception error) {
            MessageBox.Show("无法启动。请复制完整工具文件夹，包含 .runtime 和 tools。\r\n\r\n"+error.Message,"FPGA TF 媒体制作工具");return 1;
        }
    }
    static string Quote(string value) {return "\""+value.Replace("\"","\\\"")+"\"";}
}
