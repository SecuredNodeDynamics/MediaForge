#!/usr/bin/env python3
"""Cross-platform MediaForge desktop app."""

from __future__ import annotations

import queue
import re
import sys
import threading
import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox, ttk

import mediaforge_linux as mf


class RoundedButton(tk.Canvas):
    def __init__(
        self,
        master: tk.Misc,
        text: str,
        command=None,
        width: int = 118,
        height: int = 30,
        radius: int = 6,
        bg: str = "#2f3342",
        hover_bg: str = "#3b4054",
        fg: str = "#ffffff",
        **kwargs,
    ) -> None:
        super().__init__(
            master,
            width=width,
            height=height,
            highlightthickness=0,
            bd=0,
            bg=master.cget("background") if "background" in master.keys() else "#12131a",
            **kwargs,
        )
        self.command = command
        self.text = text
        self.radius = radius
        self.normal_bg = bg
        self.hover_bg = hover_bg
        self.fg = fg
        self._draw(self.normal_bg)
        self.bind("<Enter>", lambda _event: self._draw(self.hover_bg))
        self.bind("<Leave>", lambda _event: self._draw(self.normal_bg))
        self.bind("<Button-1>", self._click)
        self.configure(cursor="hand2")

    def set_text(self, text: str) -> None:
        self.text = text
        self._draw(self.normal_bg)

    def _click(self, _event) -> None:
        if self.command:
            self.command()

    def _draw(self, fill: str) -> None:
        self.delete("all")
        width = int(self["width"])
        height = int(self["height"])
        r = min(self.radius, height // 2, width // 2)
        self.create_arc(0, 0, r * 2, r * 2, start=90, extent=90, fill=fill, outline=fill)
        self.create_arc(width - r * 2, 0, width, r * 2, start=0, extent=90, fill=fill, outline=fill)
        self.create_arc(width - r * 2, height - r * 2, width, height, start=270, extent=90, fill=fill, outline=fill)
        self.create_arc(0, height - r * 2, r * 2, height, start=180, extent=90, fill=fill, outline=fill)
        self.create_rectangle(r, 0, width - r, height, fill=fill, outline=fill)
        self.create_rectangle(0, r, width, height - r, fill=fill, outline=fill)
        self.create_text(width // 2, height // 2, text=self.text, fill=self.fg, font=("Segoe UI", 9))


class GreenProgressBar(tk.Canvas):
    def __init__(self, master: tk.Misc, height: int = 16, **kwargs) -> None:
        super().__init__(
            master,
            height=height,
            highlightthickness=0,
            bd=0,
            bg=master.cget("background") if "background" in master.keys() else "#12131a",
            **kwargs,
        )
        self.value = 0
        self.bind("<Configure>", lambda _event: self._draw())
        self._draw()

    def set(self, value: int) -> None:
        self.value = max(0, min(100, int(value)))
        self._draw()

    def configure(self, cnf=None, **kwargs):  # type: ignore[override]
        if "value" in kwargs:
            value = kwargs.pop("value")
            super().configure(cnf or {}, **kwargs)
            self.set(value)
            return None
        return super().configure(cnf or {}, **kwargs)

    config = configure

    def _draw(self) -> None:
        self.delete("all")
        width = max(1, self.winfo_width())
        height = int(self["height"])
        self.create_rectangle(0, 0, width, height, fill="#e8e8e8", outline="#e8e8e8")
        fill_width = int(width * (self.value / 100))
        if fill_width > 0:
            self.create_rectangle(0, 0, fill_width, height, fill="#64dc96", outline="#64dc96")


class MediaForgeApp(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title("MediaForge")
        self.geometry("1220x860")
        self.minsize(1120, 800)
        self.configure(bg="#12131a")
        self.logo_image: tk.PhotoImage | None = None
        self.files: list[Path] = []
        self.plans: list[mf.Plan] = []
        self.audio_rows: list[dict] = []
        self.selected_show: dict | None = None
        self.work_queue: queue.Queue[tuple[str, object]] = queue.Queue()
        self.cfg = mf.load_config()
        self.tmdb_key = tk.StringVar(value=self.cfg.get("tmdb_key", ""))
        self.ffmpeg = tk.StringVar(value=self.cfg.get("ffmpeg", "") or mf.ffmpeg_path(""))
        self.mode = tk.StringVar(value="tv")
        self.exts = tk.StringVar(value=",".join(sorted(mf.MEDIA_EXTS)))
        self.show_query = tk.StringVar(value="")
        self.season = tk.IntVar(value=1)
        self.start_ep = tk.IntVar(value=1)
        self.include_show = tk.BooleanVar(value=True)
        self.rename_in_place = tk.BooleanVar(value=False)
        self.manual_override = tk.BooleanVar(value=False)
        self.status = tk.StringVar(value="Ready")
        self.connect_status = tk.StringVar(value="")
        self.picked_status = tk.StringVar(value="(none picked)")
        self.file_count = tk.StringVar(value="0 files queued")

        self._style()
        self._load_logo()
        self.update_connect_status()
        self._build()
        self.after(100, self._poll_worker)

    def rounded_button(self, parent: tk.Misc, text: str, command=None, width: int = 118, accent: bool = False) -> RoundedButton:
        return RoundedButton(
            parent,
            text=text,
            command=command,
            width=width,
            bg="#6366f1" if accent else "#3a3a4d",
            hover_bg="#7477ff" if accent else "#4a4a60",
        )

    def resource_path(self, *parts: str) -> Path:
        root = Path(getattr(sys, "_MEIPASS", Path(__file__).resolve().parent))
        return root.joinpath(*parts)

    def _load_logo(self) -> None:
        logo_path = self.resource_path("static", "logo.png")
        if not logo_path.exists():
            return
        try:
            self.logo_image = tk.PhotoImage(file=str(logo_path))
            self.iconphoto(True, self.logo_image)
        except tk.TclError:
            self.logo_image = None

    def _style(self) -> None:
        style = ttk.Style(self)
        try:
            style.theme_use("clam")
        except tk.TclError:
            pass
        style.configure(".", background="#12131a", foreground="#e8e8ee", fieldbackground="#20222c")
        style.configure("TFrame", background="#12131a")
        style.configure("Header.TFrame", background="#191b24")
        style.configure("Panel.TFrame", background="#191b24")
        style.configure("TLabel", background="#12131a", foreground="#d7d8e1")
        style.configure("Header.TLabel", background="#191b24", foreground="#ffffff")
        style.configure("Panel.TLabel", background="#191b24", foreground="#d7d8e1")
        style.configure("Section.TLabel", background="#12131a", foreground="#6366ff", font=("Segoe UI", 9, "bold"))
        style.configure("Hint.TLabel", background="#191b24", foreground="#8588aa", font=("Segoe UI", 8, "italic"))
        style.configure("Ok.TLabel", background="#12131a", foreground="#64dc96")
        style.configure("Rail.TLabel", background="#12131a", foreground="#9093c0")
        style.configure("TButton", background="#2f3342", foreground="#f4f4f8", borderwidth=0, padding=(10, 6))
        style.map("TButton", background=[("active", "#3b4054")])
        style.configure("Connect.TButton", background="#191b24", foreground="#64dc96", borderwidth=0, padding=(2, 2))
        style.map("Connect.TButton", background=[("active", "#242634")])
        style.configure("Accent.TButton", background="#6366f1", foreground="#ffffff")
        style.map("Accent.TButton", background=[("active", "#7477ff")])
        style.configure("TEntry", fieldbackground="#20222c", foreground="#f4f4f8", insertcolor="#ffffff")
        style.configure("Treeview", background="#181a22", foreground="#e5e7eb", fieldbackground="#181a22", borderwidth=0, rowheight=28)
        style.configure("Treeview.Heading", background="#252837", foreground="#b8bbca", borderwidth=0)
        style.map("Treeview", background=[("selected", "#3f4370")])
        style.configure("TRadiobutton", background="#12131a", foreground="#e8e8ee")
        style.configure("TCheckbutton", background="#12131a", foreground="#e8e8ee")

    def _build(self) -> None:
        connect = ttk.Frame(self, style="Header.TFrame", padding=(14, 8, 14, 8))
        connect.pack(fill="x")
        self.connect_button = self.rounded_button(
            connect,
            text=self.connect_status.get(),
            command=self.open_connect_popup,
            width=150,
        )
        self.connect_button.pack(side="left")

        top = ttk.Frame(self, style="Header.TFrame", padding=(14, 12, 14, 12))
        top.pack(fill="x")
        if self.logo_image:
            logo = self.logo_image.subsample(max(1, self.logo_image.width() // 32), max(1, self.logo_image.height() // 32))
            self.header_logo = logo
            ttk.Label(top, image=logo).pack(side="left", padx=(0, 10))
        ttk.Label(top, text="MediaForge", style="Header.TLabel", font=("Segoe UI", 15, "bold")).pack(side="left")
        ttk.Label(top, text="TMDB-powered rename for Jellyfin", style="Panel.TLabel").pack(side="right", padx=(0, 150))

        modebar = ttk.Frame(self, padding=(14, 16, 14, 12))
        modebar.pack(fill="x")
        ttk.Label(modebar, text="Mode:").pack(side="left", padx=(0, 8))
        for text, value in (("TV Show", "tv"), ("Movie", "movie"), ("Audio Fix", "audio")):
            ttk.Radiobutton(modebar, text=text, value=value, variable=self.mode, command=self.refresh_options).pack(side="left", padx=(0, 18))
        self.rounded_button(modebar, "Settings", self.open_settings, width=112).pack(side="right")

        self.options = ttk.Frame(self, style="Panel.TFrame", padding=12)
        self.options.pack(fill="x", padx=14)
        self.refresh_options()

        pane = ttk.Frame(self, padding=(14, 10, 14, 8), height=360)
        pane.pack(fill="both", expand=True)
        pane.pack_propagate(False)
        pane.columnconfigure(0, weight=1)
        pane.columnconfigure(1, weight=0, minsize=132)
        pane.rowconfigure(1, weight=1)
        ttk.Label(pane, text="FILES / FOLDER  --  drag files or folders anywhere onto this window", style="Section.TLabel").grid(row=0, column=0, columnspan=2, sticky="w", pady=(0, 6))

        table_frame = ttk.Frame(pane)
        table_frame.grid(row=1, column=0, sticky="nsew")
        table_frame.columnconfigure(0, weight=1)
        table_frame.rowconfigure(0, weight=1)
        columns = ("file", "audio", "action", "destination")
        self.tree = ttk.Treeview(table_frame, columns=columns, show="headings", selectmode="extended")
        for col, text, width in (
            ("file", "File", 210),
            ("audio", "Audio", 74),
            ("action", "Action", 260),
            ("destination", "Destination", 260),
        ):
            self.tree.heading(col, text=text)
            self.tree.column(col, width=width, minwidth=60, anchor="w")
        yscroll = ttk.Scrollbar(table_frame, orient="vertical", command=self.tree.yview)
        self.tree.configure(yscrollcommand=yscroll.set)
        self.tree.grid(row=0, column=0, sticky="nsew")
        yscroll.grid(row=0, column=1, sticky="ns")
        self._build_file_rail(pane)

        bottom = ttk.Frame(self, padding=(14, 0, 14, 14), height=210)
        bottom.pack(fill="x")
        bottom.pack_propagate(False)
        bottom.columnconfigure(0, weight=1)
        bottom.rowconfigure(0, weight=1)
        self.log = tk.Text(bottom, height=7, bg="#06070c", fg="#64ff9a", insertbackground="#fff", relief="flat", wrap="word")
        self.log.grid(row=0, column=0, sticky="nsew", pady=(6, 0))
        ttk.Separator(bottom, orient="horizontal").grid(row=1, column=0, sticky="ew", pady=(6, 4))
        actions = ttk.Frame(bottom)
        actions.grid(row=2, column=0, sticky="ew", pady=(4, 8))
        self.rename_button = self.rounded_button(actions, "Rename Now", self.apply, width=128, accent=True)
        self.rename_button.pack(side="left")
        self.undo_button = self.rounded_button(actions, "Undo", width=88)
        self.undo_button.pack(side="left", padx=(10, 0))
        self.save_log_button = self.rounded_button(actions, "Save Log", self.save_log, width=100)
        self.save_log_button.pack(side="right", padx=(0, 10))
        self.clear_log_button = self.rounded_button(actions, "Clear Log", lambda: self.log.delete("1.0", "end"), width=100)
        self.clear_log_button.pack(side="right")
        self.save_log_button.pack_forget()
        self.progress = GreenProgressBar(bottom, height=16)
        self.progress.grid(row=3, column=0, sticky="ew")
        self.log_line("MediaForge ready.")
        if self.tmdb_key.get().strip():
            self.log_line("API key loaded from saved config.")
        resolved_ffmpeg = mf.ffmpeg_path(self.ffmpeg.get().strip())
        resolved_ffprobe = mf.ffprobe_path(resolved_ffmpeg)
        if resolved_ffmpeg and resolved_ffprobe:
            self.ffmpeg.set(resolved_ffmpeg)
            self.log_line(f"FFmpeg loaded: {resolved_ffmpeg}")
        else:
            self.log_line("FFmpeg not found. Bundle FFmpeg during build or install ffmpeg/ffprobe on this system.")

    def _build_file_rail(self, parent: ttk.Frame) -> None:
        rail = ttk.Frame(parent, padding=(10, 0, 0, 0))
        rail.grid(row=1, column=1, sticky="nsew")
        self.rounded_button(rail, "Browse Folder", self.add_folder, width=124).pack(fill="x", pady=(0, 8))
        self.rounded_button(rail, "Add Files", self.add_files, width=124).pack(fill="x", pady=(0, 8))
        self.rounded_button(rail, "Clear Selected", self.clear_selected, width=124).pack(fill="x", pady=(0, 8))
        self.rounded_button(rail, "Clear All", self.clear_files, width=124).pack(fill="x", pady=(0, 36))
        ttk.Label(rail, textvariable=self.file_count, style="Rail.TLabel").pack(anchor="center")

    def refresh_options(self) -> None:
        for child in self.options.winfo_children():
            child.destroy()
        mode = self.mode.get()
        if mode == "tv":
            ttk.Label(self.options, text="TV SHOW OPTIONS", style="Section.TLabel").grid(row=0, column=0, sticky="w", pady=(0, 8))
            ttk.Label(self.options, text="Show ID / Name:", style="Panel.TLabel").grid(row=1, column=0, sticky="w", padx=(0, 10))
            self.show_entry = ttk.Entry(self.options, textvariable=self.show_query)
            self.show_entry.grid(row=1, column=1, columnspan=4, sticky="ew", padx=(0, 8))
            self.show_entry.bind("<Return>", lambda _event: self.search_tv_tmdb())
            self.rounded_button(self.options, "Search TMDB", self.search_tv_tmdb, width=104, accent=True).grid(row=1, column=5, sticky="ew", padx=(0, 8))
            ttk.Label(self.options, textvariable=self.picked_status, style="Ok.TLabel").grid(row=1, column=6, sticky="w")
            ttk.Label(self.options, text="Fallback Season:", style="Panel.TLabel").grid(row=2, column=0, sticky="w", pady=(14, 0), padx=(0, 10))
            ttk.Entry(self.options, textvariable=self.season, width=7).grid(row=2, column=1, sticky="w", pady=(14, 0), padx=(0, 16))
            ttk.Label(self.options, text="Fallback Ep:", style="Panel.TLabel").grid(row=2, column=2, sticky="w", pady=(14, 0), padx=(0, 10))
            ttk.Entry(self.options, textvariable=self.start_ep, width=7).grid(row=2, column=3, sticky="w", pady=(14, 0), padx=(0, 10))
            ttk.Label(self.options, text="(used only when S##E## not in filename)", style="Hint.TLabel").grid(row=2, column=4, sticky="w", pady=(14, 0))
            ttk.Label(self.options, text="Extensions:", style="Panel.TLabel").grid(row=2, column=5, sticky="e", pady=(14, 0), padx=(0, 8))
            ttk.Entry(self.options, textvariable=self.exts, width=20).grid(row=2, column=6, sticky="ew", pady=(14, 0))
            ttk.Checkbutton(self.options, text="Include show name in filename", variable=self.include_show).grid(row=3, column=0, columnspan=2, sticky="w", pady=(12, 0))
            ttk.Checkbutton(self.options, text="Rename in Place", variable=self.rename_in_place).grid(row=3, column=2, columnspan=2, sticky="w", pady=(12, 0))
            self.options.columnconfigure(1, weight=1)
            self.options.columnconfigure(4, weight=1)
        elif mode == "movie":
            ttk.Label(self.options, text="MOVIE OPTIONS", style="Section.TLabel").pack(side="left", padx=(0, 20))
            ttk.Checkbutton(self.options, text="Rename in Place", variable=self.rename_in_place).pack(side="left")
            ttk.Label(self.options, text="Extensions:", style="Panel.TLabel").pack(side="right", padx=(10, 6))
            ttk.Entry(self.options, textvariable=self.exts, width=24).pack(side="right")
        else:
            ttk.Label(self.options, text="AUDIO FIX OPTIONS", style="Section.TLabel").pack(side="left", padx=(0, 20))
            ttk.Label(self.options, text="HE-AAC tracks will be converted to AAC LC stereo.", style="Panel.TLabel").pack(side="left")
            ttk.Label(self.options, text="Extensions:", style="Panel.TLabel").pack(side="right", padx=(10, 6))
            ttk.Entry(self.options, textvariable=self.exts, width=24).pack(side="right")
        if hasattr(self, "rename_button"):
            self.rename_button.set_text("Fix Now" if mode == "audio" else "Rename Now")
        if hasattr(self, "save_log_button"):
            if mode == "audio":
                self.save_log_button.pack(side="right", padx=(0, 10), before=self.clear_log_button)
            else:
                self.save_log_button.pack_forget()
        self.update_stats()

    def update_connect_status(self) -> None:
        self.connect_status.set("✓ TMDB Connected" if self.tmdb_key.get().strip() else "Connect")
        if hasattr(self, "connect_button"):
            self.connect_button.set_text(self.connect_status.get())

    def open_connect_popup(self) -> None:
        self.open_settings(focus_key=not bool(self.tmdb_key.get().strip()))

    def open_settings(self, focus_key: bool = False) -> None:
        win = tk.Toplevel(self)
        win.title("Connect to TMDB")
        win.transient(self)
        win.grab_set()
        win.configure(bg="#12131a")
        frame = ttk.Frame(win, padding=16)
        frame.pack(fill="both", expand=True)
        ttk.Label(frame, text="TMDB API Key").grid(row=0, column=0, sticky="w")
        key_entry = ttk.Entry(frame, textvariable=self.tmdb_key, width=58, show="*")
        key_entry.grid(row=1, column=0, columnspan=2, sticky="ew", pady=(4, 12))
        ttk.Label(frame, text="FFmpeg (auto-detected if blank)").grid(row=2, column=0, sticky="w")
        ttk.Entry(frame, textvariable=self.ffmpeg, width=48).grid(row=3, column=0, sticky="ew", pady=(4, 12))
        self.rounded_button(frame, "Browse", lambda: self.pick_ffmpeg(), width=92).grid(row=3, column=1, padx=(8, 0))
        self.rounded_button(frame, "Save", lambda: self.save_settings(win), width=92, accent=True).grid(row=4, column=1, sticky="e")
        if focus_key:
            key_entry.focus_set()

    def pick_ffmpeg(self) -> None:
        path = filedialog.askopenfilename(title="Select ffmpeg", filetypes=[("FFmpeg", "ffmpeg ffmpeg.exe"), ("All files", "*")])
        if path:
            self.ffmpeg.set(path)

    def save_settings(self, win: tk.Toplevel) -> None:
        self.cfg["tmdb_key"] = self.tmdb_key.get().strip()
        self.cfg["ffmpeg"] = self.ffmpeg.get().strip()
        mf.save_config(self.cfg)
        self.update_connect_status()
        resolved = mf.ffmpeg_path(self.ffmpeg.get().strip())
        if resolved and resolved != self.ffmpeg.get().strip():
            self.ffmpeg.set(resolved)
        self.log_line(f"Settings saved to {mf.config_path()}")
        win.destroy()

    def save_log(self) -> None:
        path = filedialog.asksaveasfilename(
            title="Save MediaForge Log",
            defaultextension=".txt",
            filetypes=[("Text Log", "*.txt"), ("All files", "*.*")],
        )
        if not path:
            return
        Path(path).write_text(self.log.get("1.0", "end-1c"))
        self.log_line(f"Log saved: {path}")

    def search_tv_tmdb(self) -> None:
        query = self.show_query.get().strip()
        if not query:
            messagebox.showinfo("Search TMDB", "Type a show name or TMDB ID first.")
            return
        if not self.tmdb_key.get().strip():
            if messagebox.askyesno("Connect to TMDB", "A TMDB API key is required for TV search. Add one now?"):
                self.open_settings(focus_key=True)
            return

        client = mf.MetadataClient(self.tmdb_key.get().strip())
        if query.isdigit():
            item = client.tmdb(f"/tv/{query}")
            results = [item] if isinstance(item, dict) and item.get("id") else []
        else:
            results = client.search_tmdb(query, "tv")
        if not results:
            messagebox.showinfo("Search TMDB", f"No results found for: {query}")
            return
        self.show_tv_result_picker(results, query)

    def show_tv_result_picker(self, results: list[dict], query: str) -> None:
        win = tk.Toplevel(self)
        win.title("Select TV Show")
        win.transient(self)
        win.grab_set()
        win.configure(bg="#12131a")
        win.geometry("680x420")
        frame = ttk.Frame(win, padding=14)
        frame.pack(fill="both", expand=True)
        ttk.Label(frame, text=f"Results for: {query}").pack(anchor="w", pady=(0, 8))

        columns = ("title", "year", "id", "overview")
        tree = ttk.Treeview(frame, columns=columns, show="headings", selectmode="browse")
        for col, text, width in (
            ("title", "Title", 220),
            ("year", "Year", 70),
            ("id", "TMDB ID", 90),
            ("overview", "Overview", 260),
        ):
            tree.heading(col, text=text)
            tree.column(col, width=width, anchor="w")
        tree.pack(fill="both", expand=True)

        result_by_iid: dict[str, dict] = {}
        for item in results:
            title = item.get("name") or item.get("original_name") or ""
            year = mf.year_from(item.get("first_air_date"))
            overview = (item.get("overview") or "").replace("\n", " ")
            iid = tree.insert("", "end", values=(title, year, item.get("id", ""), overview))
            result_by_iid[iid] = item
        first = tree.get_children()
        if first:
            tree.selection_set(first[0])
            tree.focus(first[0])

        buttons = ttk.Frame(frame)
        buttons.pack(fill="x", pady=(10, 0))

        def select_current() -> None:
            selection = tree.selection()
            if not selection:
                return
            item = result_by_iid[selection[0]]
            normalized = mf.normalize_tmdb_show(item)
            self.selected_show = normalized
            self.picked_status.set(f"{normalized['title']} ({normalized['year']})")
            self.log_line(f"Selected TV show: {normalized['title']} ({normalized['year']}) [TMDB {normalized['id']}]")
            win.destroy()
            if self.files:
                self.preview()

        self.rounded_button(buttons, "Select", select_current, width=90, accent=True).pack(side="right")
        self.rounded_button(buttons, "Cancel", win.destroy, width=90).pack(side="right", padx=(0, 8))
        tree.bind("<Double-1>", lambda _event: select_current())

    def add_files(self) -> None:
        paths = filedialog.askopenfilenames(title="Add media files")
        self.add_paths(paths)

    def add_folder(self) -> None:
        path = filedialog.askdirectory(title="Add media folder")
        if path:
            self.add_paths([path])

    def add_paths(self, paths: tuple[str, ...] | list[str]) -> None:
        found = mf.collect_files(list(paths), mf.parse_exts(self.exts.get()))
        existing = set(self.files)
        self.files.extend([p for p in found if p not in existing])
        self.files.sort(key=lambda x: str(x).lower())
        self.plans = []
        self.audio_rows = []
        self.render_files()
        self.status.set(f"{len(self.files)} file(s) queued")
        self.update_stats()

    def clear_files(self) -> None:
        self.files.clear()
        self.plans.clear()
        self.audio_rows.clear()
        self.selected_show = None
        self.picked_status.set("(none picked)")
        self.render_files()
        self.status.set("Ready")
        self.update_stats()

    def clear_selected(self) -> None:
        selected_names = {self.tree.item(item, "values")[0] for item in self.tree.selection()}
        if not selected_names:
            return
        self.files = [path for path in self.files if path.name not in selected_names]
        self.plans = []
        self.audio_rows = []
        self.render_files()
        self.status.set(f"{len(self.files)} file(s) queued")
        self.update_stats()

    def render_files(self) -> None:
        self.tree.delete(*self.tree.get_children())
        for path in self.files:
            self.tree.insert("", "end", values=(path.name, "", "Queued", str(path.parent)))
        self.update_stats()

    def preview(self) -> None:
        self.run_worker(apply=False)

    def apply(self) -> None:
        if not self.files:
            messagebox.showinfo("MediaForge", "Add files or a folder first.")
            return
        if not messagebox.askyesno("Apply changes", "Apply the previewed changes to disk?"):
            return
        self.run_worker(apply=True)

    def scan_duplicates(self) -> None:
        if not self.files:
            messagebox.showinfo("MediaForge", "Add files or a folder first.")
            return
        mode = "movie" if self.mode.get() == "movie" else "tv"
        groups: dict[str, list[Path]] = {}
        for path in self.files:
            if mode == "tv":
                match = re.search(r"(?i)S\d{1,2}E\d{1,3}", path.stem)
                if not match:
                    continue
                key = match.group(0).upper()
            else:
                key = re.sub(r"\s+", " ", path.stem).lower().strip()
            groups.setdefault(key, []).append(path)

        self.tree.delete(*self.tree.get_children())
        found = 0
        for key, paths in sorted(groups.items()):
            if len(paths) < 2:
                continue
            found += 1
            for path in sorted(paths):
                size = path.stat().st_size / 1024 / 1024
                self.tree.insert("", "end", values=(path.name, "", f"Duplicate group {key}", f"{size:.1f} MB | {path}"))
        if found:
            self.status.set(f"{found} duplicate group(s) found")
            self.log_line(f"Duplicate scan found {found} group(s).")
        else:
            self.status.set("No duplicates found")
            self.log_line("Duplicate scan found no duplicates.")
        self.update_stats()

    def run_worker(self, apply: bool) -> None:
        if not self.files:
            messagebox.showinfo("MediaForge", "Add files or a folder first.")
            return
        self.status.set("Working...")
        self.progress.configure(value=10)
        self.log_line(("Applying" if apply else "Previewing") + f" {self.mode.get()} operation...")
        thread = threading.Thread(target=self._worker, args=(apply,), daemon=True)
        thread.start()

    def _worker(self, apply: bool) -> None:
        try:
            client = mf.MetadataClient(self.tmdb_key.get().strip())
            mode = self.mode.get()
            if mode == "tv":
                plans = mf.tv_plans(
                    client,
                    self.files,
                    self.season.get(),
                    self.start_ep.get(),
                    self.include_show.get(),
                    self.rename_in_place.get(),
                    self.manual_override.get(),
                    self.selected_show,
                )
                if apply:
                    mf.apply_plans(plans, dry_run=False)
                self.work_queue.put(("plans", plans))
            elif mode == "movie":
                plans = mf.movie_plans(client, self.files, self.rename_in_place.get())
                if apply:
                    mf.apply_plans(plans, dry_run=False)
                self.work_queue.put(("plans", plans))
            else:
                ffmpeg = mf.ffmpeg_path(self.ffmpeg.get().strip())
                probe = mf.ffprobe_path(ffmpeg)
                if not probe:
                    raise RuntimeError("ffprobe was not found. Set FFmpeg in Settings.")
                rows = mf.audio_scan(self.files, probe)
                if apply:
                    if not ffmpeg:
                        raise RuntimeError("ffmpeg was not found. Set FFmpeg in Settings.")
                    mf.audio_fix(self.files, ffmpeg, probe, dry_run=False, report=None)
                    rows = mf.audio_scan(self.files, probe)
                self.work_queue.put(("audio", rows))
            self.work_queue.put(("done", "Complete"))
        except Exception as exc:
            self.work_queue.put(("error", str(exc)))

    def _poll_worker(self) -> None:
        try:
            while True:
                kind, payload = self.work_queue.get_nowait()
                if kind == "plans":
                    self.plans = payload  # type: ignore[assignment]
                    self.show_plans(self.plans)
                elif kind == "audio":
                    self.audio_rows = payload  # type: ignore[assignment]
                    self.show_audio(self.audio_rows)
                elif kind == "done":
                    self.status.set(str(payload))
                    self.progress.configure(value=100)
                    self.log_line(str(payload))
                elif kind == "error":
                    self.status.set("Error")
                    self.progress.configure(value=0)
                    self.log_line("Error: " + str(payload))
                    messagebox.showerror("MediaForge", str(payload))
        except queue.Empty:
            pass
        self.after(100, self._poll_worker)

    def show_plans(self, plans: list[mf.Plan]) -> None:
        self.tree.delete(*self.tree.get_children())
        plan_by_source = {p.source: p for p in plans}
        for path in self.files:
            plan = plan_by_source.get(path)
            action = "Unmatched"
            dest = ""
            if plan:
                action = "Already correct" if plan.source == plan.dest else plan.label
                dest = str(plan.dest)
            self.tree.insert("", "end", values=(path.name, "", action, dest))
        self.status.set(f"{len(plans)} matched file(s)")
        self.update_stats()

    def show_audio(self, rows: list[dict]) -> None:
        self.tree.delete(*self.tree.get_children())
        for row in rows:
            path = row["file"]
            self.tree.insert("", "end", values=(path.name, row["label"], row["action"], str(path)))
        pending = sum(1 for r in rows if r.get("heaac"))
        self.status.set(f"{pending} file(s) need audio conversion")
        self.update_stats()

    def update_stats(self) -> None:
        queued = len(self.files)
        matched = len(self.plans)
        pending = 0
        fixed = 0
        failed = 0

        if self.audio_rows:
            pending = sum(1 for r in self.audio_rows if r.get("heaac"))
            fixed = sum(1 for r in self.audio_rows if str(r.get("action", "")).lower().startswith("fixed"))
            failed = sum(1 for r in self.audio_rows if str(r.get("action", "")).lower().startswith("failed"))
        elif self.plans:
            pending = sum(1 for p in self.plans if p.source != p.dest)

        mode = "movie" if self.mode.get() == "movie" else "tv"
        groups: dict[str, int] = {}
        for path in self.files:
            if mode == "tv":
                match = re.search(r"(?i)S\d{1,2}E\d{1,3}", path.stem)
                if not match:
                    continue
                key = match.group(0).upper()
            else:
                key = re.sub(r"\s+", " ", path.stem).lower().strip()
            groups[key] = groups.get(key, 0) + 1
        duplicate_groups = {key for key, count in groups.items() if count > 1}

        self.file_count.set(f"{queued} files queued")

    def log_line(self, text: str) -> None:
        self.log.insert("end", text + "\n")
        self.log.see("end")


if __name__ == "__main__":
    MediaForgeApp().mainloop()
