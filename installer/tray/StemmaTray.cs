// Ícone do Stemma na bandeja do Windows (F5b, ADR 0014). O Stemma em si é o serviço;
// este app só mostra o estado e dá atalhos: abrir, QR para o celular, parar/iniciar, sair.
// Sair fecha só o ícone (o serviço continua), como no Tailscale.
//
// Compilado pelo installer\build.ps1 com o csc do .NET Framework 4 (C# 5: sem interpolação
// de string, sem "?."), com o Stemma.manifest (DPI por monitor). Uso:
//   Stemma.exe --root C:\stemma --service stemma [--open] [--qr]
//   --open: abre o navegador (atalho do Menu Iniciar); --qr: abre a janela "Abrir no celular".
using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Net;
using System.Runtime.InteropServices;
using System.ServiceProcess;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows.Forms;

namespace Stemma
{
    internal static class Program
    {
        [STAThread]
        private static int Main(string[] args)
        {
            string root = @"C:\stemma";
            string service = "stemma";
            bool open = false;
            bool qr = false;
            for (int i = 0; i < args.Length; i++)
            {
                if (args[i] == "--root" && i + 1 < args.Length) root = args[i + 1];
                if (args[i] == "--service" && i + 1 < args.Length) service = args[i + 1];
                if (args[i] == "--open") open = true;
                if (args[i] == "--qr") qr = true;
            }

            bool created;
            using (var mutex = new Mutex(true, @"Local\StemmaTray-" + service, out created))
            {
                // --open (atalho do Menu Iniciar): abre o navegador; no login só aparece o ícone.
                if (open || !created) TrayContext.OpenUrl(TrayContext.ReadUrl(root));
                if (!created) return 0;
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                var context = new TrayContext(root, service);
                if (qr) context.ShowQr();
                Application.Run(context);
            }
            return 0;
        }
    }

    /// <summary>Cores dos tokens do design (docs/design/README.md, tema escuro).</summary>
    internal static class Theme
    {
        public static readonly Color BgBase = ColorTranslator.FromHtml("#121416");
        public static readonly Color BgRaised = ColorTranslator.FromHtml("#2c323b");
        public static readonly Color BgRaised2 = ColorTranslator.FromHtml("#3a414b");
        public static readonly Color Line = ColorTranslator.FromHtml("#323840");
        public static readonly Color TextStrong = ColorTranslator.FromHtml("#eceff3");
        public static readonly Color TextBody = ColorTranslator.FromHtml("#c2c8d0");
        public static readonly Color TextMuted = ColorTranslator.FromHtml("#9199a3");
        public static readonly Color AccentText = ColorTranslator.FromHtml("#eec07a");
        public static readonly Color Good = ColorTranslator.FromHtml("#5ba17a");
        public static readonly Color Warn = ColorTranslator.FromHtml("#bc9050");
        public static readonly Color QrLight = ColorTranslator.FromHtml("#f4f2ee");

        public static Font Ui(float size, FontStyle style)
        {
            return new Font("Segoe UI", size, style, GraphicsUnit.Point);
        }

        [DllImport("dwmapi.dll")]
        private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);

        /// <summary>Barra de título escura e cantos arredondados (Windows 11; ignorado nos anteriores).</summary>
        public static void StyleWindow(IntPtr handle, bool dark, bool round)
        {
            try
            {
                int on = 1;
                if (dark) DwmSetWindowAttribute(handle, 20, ref on, 4); // DWMWA_USE_IMMERSIVE_DARK_MODE
                int corner = 2; // DWMWCP_ROUND
                if (round) DwmSetWindowAttribute(handle, 33, ref corner, 4); // DWMWA_WINDOW_CORNER_PREFERENCE
            }
            catch (DllNotFoundException) { }
            catch (EntryPointNotFoundException) { }
        }
    }

    /// <summary>Menu no tema escuro do Stemma (no lugar do cinza padrão do WinForms).</summary>
    internal sealed class DarkColors : ProfessionalColorTable
    {
        public override Color ToolStripDropDownBackground { get { return Theme.BgRaised; } }
        public override Color ImageMarginGradientBegin { get { return Theme.BgRaised; } }
        public override Color ImageMarginGradientMiddle { get { return Theme.BgRaised; } }
        public override Color ImageMarginGradientEnd { get { return Theme.BgRaised; } }
        public override Color MenuBorder { get { return Theme.Line; } }
        public override Color MenuItemBorder { get { return Theme.BgRaised2; } }
        public override Color MenuItemSelected { get { return Theme.BgRaised2; } }
        public override Color MenuItemSelectedGradientBegin { get { return Theme.BgRaised2; } }
        public override Color MenuItemSelectedGradientEnd { get { return Theme.BgRaised2; } }
        public override Color SeparatorDark { get { return Theme.Line; } }
        public override Color SeparatorLight { get { return Theme.Line; } }
    }

    internal sealed class DarkRenderer : ToolStripProfessionalRenderer
    {
        public DarkRenderer() : base(new DarkColors()) { RoundedEdges = false; }

        protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e)
        {
            e.TextColor = !e.Item.Enabled ? Theme.TextMuted : Theme.TextStrong;
            base.OnRenderItemText(e);
        }

        protected override void OnRenderSeparator(ToolStripSeparatorRenderEventArgs e)
        {
            int y = e.Item.Height / 2;
            using (var pen = new Pen(Theme.Line))
            {
                e.Graphics.DrawLine(pen, 8, y, e.Item.Width - 8, y);
            }
        }
    }

    internal sealed class TrayContext : ApplicationContext
    {
        private readonly string root;
        private readonly string serviceId;
        private readonly string setupDir;
        private readonly NotifyIcon icon;
        private readonly ContextMenuStrip menu;
        private readonly ToolStripMenuItem header;
        private readonly ToolStripMenuItem startStop;
        private readonly System.Windows.Forms.Timer timer;
        private Icon iconOn;
        private Icon iconOff;
        private Form qrForm;
        private bool running;
        private string lastState;

        public TrayContext(string root, string serviceId)
        {
            this.root = root;
            this.serviceId = serviceId;
            setupDir = Path.Combine(root, "setup");
            LoadIcons();

            header = new ToolStripMenuItem("Stemma") { Enabled = false };
            var open = new ToolStripMenuItem("Abrir o Stemma", null, delegate { OpenUrl(ReadUrl(root)); });
            var phone = new ToolStripMenuItem("Abrir no celular…", null, delegate { ShowQr(); });
            startStop = new ToolStripMenuItem("Parar o Stemma", null, delegate { ToggleService(); });
            var quit = new ToolStripMenuItem("Sair (o Stemma continua no ar)", null, delegate { Quit(); });

            menu = new ContextMenuStrip
            {
                Renderer = new DarkRenderer(),
                ShowImageMargin = true,
                Font = Theme.Ui(10f, FontStyle.Regular),
                Padding = new Padding(4, 6, 4, 6)
            };
            menu.Items.AddRange(new ToolStripItem[] {
                header, new ToolStripSeparator(), open, phone, new ToolStripSeparator(), startStop, quit
            });
            foreach (ToolStripItem item in menu.Items)
            {
                if (!(item is ToolStripSeparator)) item.Padding = new Padding(4, 5, 12, 5);
            }
            open.Font = Theme.Ui(10f, FontStyle.Bold);
            header.Font = Theme.Ui(9f, FontStyle.Regular);
            menu.HandleCreated += delegate { Theme.StyleWindow(menu.Handle, true, true); };

            icon = new NotifyIcon
            {
                Icon = iconOff,
                Text = "Stemma",
                ContextMenuStrip = menu,
                Visible = true
            };
            icon.MouseClick += delegate (object s, MouseEventArgs e)
            {
                if (e.Button == MouseButtons.Left) OpenUrl(ReadUrl(root));
            };

            timer = new System.Windows.Forms.Timer { Interval = 5000 };
            timer.Tick += delegate { Refresh(); };
            timer.Start();
            Refresh();
        }

        // --- estado ------------------------------------------------------------------

        private void Refresh()
        {
            // Síncrono: o /health é local (porta fechada recusa na hora; timeout curto).
            // Nada aqui pode derrubar o ícone: um erro inesperado conta como "sem resposta".
            string status = null;
            string version = null;
            try
            {
                status = ServiceStatus();
                version = status == "Running" ? HealthVersion() : null;
            }
            catch (Exception) { version = null; }
            Apply(status, version);
        }

        private void Apply(string status, string version)
        {
            string text;
            Color dot;
            if (status == null)
            {
                running = false;
                text = "não instalado";
                dot = Theme.TextMuted;
            }
            else if (status == "Running" && version != null)
            {
                running = true;
                text = "no ar · v" + version;
                dot = Theme.Good;
            }
            else if (status == "Running" || status == "StartPending")
            {
                running = true;
                text = "iniciando…";
                dot = Theme.Warn;
            }
            else
            {
                running = false;
                text = status == "StopPending" ? "parando…" : "parado";
                dot = Theme.TextMuted;
            }
            string state = text + dot.ToArgb();
            if (state == lastState) return;
            lastState = state;

            header.Text = "Stemma: " + text;
            Image previous = header.Image;
            header.Image = Dot(dot);
            if (previous != null) previous.Dispose();
            icon.Text = Truncate("Stemma: " + text, 63);
            icon.Icon = running && version != null ? iconOn : iconOff;
            startStop.Text = running ? "Parar o Stemma" : "Iniciar o Stemma";
            startStop.Enabled = status != null;
        }

        private string ServiceStatus()
        {
            try
            {
                using (var controller = new ServiceController(serviceId))
                {
                    return controller.Status.ToString();
                }
            }
            catch (InvalidOperationException) { return null; }
        }

        private string HealthVersion()
        {
            try
            {
                var request = (HttpWebRequest)WebRequest.Create("http://127.0.0.1:" + ReadPort() + "/health");
                request.Timeout = 1500;
                request.Proxy = null;
                using (var response = request.GetResponse())
                using (var reader = new StreamReader(response.GetResponseStream()))
                {
                    Match match = Regex.Match(reader.ReadToEnd(), "\"version\"\\s*:\\s*\"([^\"]+)\"");
                    return match.Success ? match.Groups[1].Value : null;
                }
            }
            catch (WebException) { return null; }
            catch (IOException) { return null; }
            catch (UriFormatException) { return null; } // PORT inválido no .env
        }

        private string ReadPort()
        {
            int port;
            foreach (string line in ReadLines(Path.Combine(root, ".env")))
            {
                string trimmed = line.Trim();
                if (trimmed.StartsWith("PORT=") && int.TryParse(trimmed.Substring(5).Trim().Trim('"', '\''), out port))
                {
                    return port.ToString();
                }
            }
            return "8000";
        }

        /// <summary>Linhas de um arquivo, ou nenhuma se ele não existe ou não pode ser lido.</summary>
        private static string[] ReadLines(string file)
        {
            try { return File.Exists(file) ? File.ReadAllLines(file) : new string[0]; }
            catch (IOException) { return new string[0]; }
            catch (UnauthorizedAccessException) { return new string[0]; }
        }

        // --- ações -------------------------------------------------------------------

        internal static string ReadUrl(string root)
        {
            // Gravado pelo instalador (Stemma.url): https://<pc>.<tailnet>.ts.net ou o local.
            foreach (string line in ReadLines(Path.Combine(Path.Combine(root, "setup"), "Stemma.url")))
            {
                if (line.StartsWith("URL=")) return line.Substring(4).Trim();
            }
            return "http://127.0.0.1:8000";
        }

        internal static void OpenUrl(string url)
        {
            try { Process.Start(new ProcessStartInfo(url) { UseShellExecute = true }); }
            catch (System.ComponentModel.Win32Exception) { }
        }

        private void ToggleService()
        {
            // O motor pede administrador (UAC) sozinho e mostra o aviso no fim.
            string script = Path.Combine(Path.Combine(setupDir, "engine"), "setup.ps1");
            string mode = running ? "Stop" : "Start";
            var info = new ProcessStartInfo("powershell.exe",
                "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + script + "\" -Mode " + mode +
                " -Root \"" + root + "\" -ServiceId \"" + serviceId + "\"")
            {
                UseShellExecute = false,
                CreateNoWindow = true
            };
            try { Process.Start(info); }
            catch (System.ComponentModel.Win32Exception) { }
        }

        internal void ShowQr()
        {
            if (qrForm != null && !qrForm.IsDisposed)
            {
                qrForm.Activate();
                return;
            }
            qrForm = new QrForm(ReadUrl(root), Path.Combine(setupDir, "qr.bmp"), iconOn);
            qrForm.Show();
            qrForm.Activate();
        }

        private void Quit()
        {
            timer.Stop();
            icon.Visible = false;
            icon.Dispose();
            ExitThread();
        }

        // --- ícone -------------------------------------------------------------------

        private void LoadIcons()
        {
            // O .ico tem 16–256 px; com o manifesto de DPI, SmallIconSize já vem na escala da tela.
            string file = Path.Combine(setupDir, "stemma.ico");
            try
            {
                iconOn = File.Exists(file)
                    ? new Icon(file, SystemInformation.SmallIconSize)
                    : Icon.ExtractAssociatedIcon(Application.ExecutablePath);
            }
            catch (ArgumentException) { iconOn = SystemIcons.Application; }
            iconOff = MakeGray(iconOn);
        }

        private static Icon MakeGray(Icon source)
        {
            // Parado/iniciando: o mesmo ícone em cinza, meio transparente.
            using (Bitmap color = source.ToBitmap())
            {
                var gray = new Bitmap(color.Width, color.Height);
                for (int y = 0; y < color.Height; y++)
                {
                    for (int x = 0; x < color.Width; x++)
                    {
                        Color c = color.GetPixel(x, y);
                        int l = (int)(c.R * 0.3 + c.G * 0.59 + c.B * 0.11);
                        gray.SetPixel(x, y, Color.FromArgb(c.A * 3 / 5, l, l, l));
                    }
                }
                return Icon.FromHandle(gray.GetHicon());
            }
        }

        private static Image Dot(Color color)
        {
            int size = SystemInformation.SmallIconSize.Width;
            var bitmap = new Bitmap(size, size);
            using (Graphics g = Graphics.FromImage(bitmap))
            using (var brush = new SolidBrush(color))
            {
                g.SmoothingMode = SmoothingMode.AntiAlias;
                int d = size / 2;
                g.FillEllipse(brush, (size - d) / 2f, (size - d) / 2f, d, d);
            }
            return bitmap;
        }

        private static string Truncate(string text, int max)
        {
            return text.Length <= max ? text : text.Substring(0, max);
        }
    }

    /// <summary>"Abrir no celular": QR do endereço do Tailscale no tema escuro do Stemma.</summary>
    internal sealed class QrForm : Form
    {
        public QrForm(string url, string qrPath, Icon appIcon)
        {
            bool https = url.StartsWith("https://");
            Text = "Abrir no celular";
            Icon = appIcon;
            FormBorderStyle = FormBorderStyle.FixedSingle;
            MaximizeBox = false;
            MinimizeBox = false;
            StartPosition = FormStartPosition.CenterScreen;
            BackColor = Theme.BgBase;
            ForeColor = Theme.TextBody;
            Font = Theme.Ui(10f, FontStyle.Regular);
            AutoScaleMode = AutoScaleMode.Dpi;
            AutoScaleDimensions = new SizeF(96f, 96f);
            AutoSize = true;
            AutoSizeMode = AutoSizeMode.GrowAndShrink;

            var layout = new FlowLayoutPanel
            {
                FlowDirection = FlowDirection.TopDown,
                AutoSize = true,
                AutoSizeMode = AutoSizeMode.GrowAndShrink,
                WrapContents = false,
                BackColor = Theme.BgBase,
                Padding = new Padding(24, 20, 24, 24)
            };
            var title = new Label
            {
                AutoSize = true,
                Text = "Abrir no celular",
                Font = Theme.Ui(14f, FontStyle.Bold),
                ForeColor = Theme.TextStrong,
                Margin = new Padding(0, 0, 0, 8)
            };
            var hint = new Label
            {
                AutoSize = true,
                MaximumSize = new Size(300, 0),
                Text = https
                    ? "Aponte a câmera do celular para o código ou abra o endereço abaixo. No Chrome, use ⋮ → Instalar app."
                    : "Sem o Tailscale, o Stemma abre só neste PC.",
                Margin = new Padding(0, 0, 0, 16)
            };
            layout.Controls.Add(title);
            layout.Controls.Add(hint);
            if (https && File.Exists(qrPath))
            {
                layout.Controls.Add(new QrView(Image.FromFile(qrPath)) { Margin = new Padding(0, 0, 0, 16) });
            }
            var link = new LinkLabel
            {
                AutoSize = true,
                Text = url,
                Font = new Font("Consolas", 10f, FontStyle.Regular, GraphicsUnit.Point),
                LinkColor = Theme.AccentText,
                ActiveLinkColor = Theme.TextStrong,
                VisitedLinkColor = Theme.AccentText,
                LinkBehavior = LinkBehavior.HoverUnderline
            };
            link.LinkClicked += delegate { TrayContext.OpenUrl(url); };
            layout.Controls.Add(link);
            Controls.Add(layout);
        }

        protected override void OnHandleCreated(EventArgs e)
        {
            base.OnHandleCreated(e);
            Theme.StyleWindow(Handle, true, false);
        }
    }

    /// <summary>QR ampliado sem borrar (vizinho mais próximo), num cartão claro com cantos arredondados.</summary>
    internal sealed class QrView : Control
    {
        private readonly Image image;

        public QrView(Image image)
        {
            this.image = image;
            Size = new Size(260, 260);
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer |
                ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true);
            BackColor = Theme.BgBase;
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            using (var path = Rounded(new Rectangle(0, 0, Width - 1, Height - 1), 12))
            using (var brush = new SolidBrush(Theme.QrLight))
            {
                g.FillPath(brush, path);
            }
            g.SmoothingMode = SmoothingMode.None;
            g.InterpolationMode = InterpolationMode.NearestNeighbor;
            g.PixelOffsetMode = PixelOffsetMode.Half;
            int pad = Width / 20;
            g.DrawImage(image, new Rectangle(pad, pad, Width - 2 * pad, Height - 2 * pad));
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing) image.Dispose();
            base.Dispose(disposing);
        }

        private static GraphicsPath Rounded(Rectangle r, int radius)
        {
            var path = new GraphicsPath();
            int d = radius * 2;
            path.AddArc(r.X, r.Y, d, d, 180, 90);
            path.AddArc(r.Right - d, r.Y, d, d, 270, 90);
            path.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
            path.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
            path.CloseFigure();
            return path;
        }
    }
}
