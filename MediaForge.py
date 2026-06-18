#!/usr/bin/env python3
"""Cross-platform MediaForge desktop app."""

from __future__ import annotations

import queue
import threading
import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox, ttk

import mediaforge_linux as mf


class MediaForgeApp(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title("MediaForge")
        self.geometry("1120x760")
        self.minsize(980, 660)
        self.configure(bg="#12131a")
        self.files: list[Path] = []
        self.plans: list[mf.Plan] = []
        self.audio_rows: list[dict] = []
        self.work_queue: queue.Queue[tuple[str, object]] = queue.Queue()
        self.cfg = mf.load_config()
        self.tmdb_key = tk.StringVar(value=self.cfg.get("tmdb_key", ""))
        self.ffmpeg = tk.StringVar(value=self.cfg.get("ffmpeg", ""))
        self.mode = tk.StringVar(value="tv")
        self.exts = tk.StringVar(value=",".join(sorted(mf.MEDIA_EXTS)))
        self.season = tk.IntVar(value=1)
        self.start_ep = tk.IntVar(value=1)
        self.include_show = tk.BooleanVar(value=True)
        self.rename_in_place = tk.BooleanVar(value=False)
        self.manual_override = tk.BooleanVar(value=False)
        self.status = tk.StringVar(value="Ready")

        self._style()
        self._build()
        self.after(100, self._poll_worker)

    def _style(self) -> None:
        style = ttk.Style(self)
        try:
            style.theme_use("clam")
        except tk.TclError:
            pass
        style.configure(".", background="#12131a", foreground="#e8e8ee", fieldbackground="#20222c")
        style.configure("TFrame", background="#12131a")
        style.configure("Panel.TFrame", background="#191b24")
        style.configure("TLabel", background="#12131a", foreground="#d7d8e1")
        style.configure("Panel.TLabel", background="#191b24", foreground="#d7d8e1")
        style.configure("TButton", background="#2f3342", foreground="#f4f4f8", borderwidth=0, padding=(10, 6))
        style.map("TButton", background=[("active", "#3b4054")])
        style.configure("Accent.TButton", background="#6366f1", foreground="#ffffff")
        style.map("Accent.TButton", background=[("active", "#7477ff")])
        style.configure("TEntry", fieldbackground="#20222c", foreground="#f4f4f8", insertcolor="#ffffff")
        style.configure("Treeview", background="#181a22", foreground="#e5e7eb", fieldbackground="#181a22", borderwidth=0, rowheight=28)
        style.configure("Treeview.Heading", background="#252837", foreground="#b8bbca", borderwidth=0)
        style.map("Treeview", background=[("selected", "#3f4370")])
        style.configure("TRadiobutton", background="#12131a", foreground="#e8e8ee")
        style.configure("TCheckbutton", background="#12131a", foreground="#e8e8ee")

    def _build(self) -> None:
        top = ttk.Frame(self, padding=14)
        top.pack(fill="x")
        ttk.Label(top, text="MediaForge", font=("Segoe UI", 18, "bold")).pack(side="left")
        ttk.Button(top, text="Settings", command=self.open_settings).pack(side="right")

        modebar = ttk.Frame(self, padding=(14, 0, 14, 8))
        modebar.pack(fill="x")
        for text, value in (("TV Show", "tv"), ("Movie", "movie"), ("Audio Fix", "audio")):
            ttk.Radiobutton(modebar, text=text, value=value, variable=self.mode, command=self.refresh_options).pack(side="left", padx=(0, 18))

        self.options = ttk.Frame(self, style="Panel.TFrame", padding=12)
        self.options.pack(fill="x", padx=14)
        self.refresh_options()

        controls = ttk.Frame(self, padding=(14, 12, 14, 8))
        controls.pack(fill="x")
        ttk.Button(controls, text="Add Files", command=self.add_files).pack(side="left")
        ttk.Button(controls, text="Add Folder", command=self.add_folder).pack(side="left", padx=8)
        ttk.Button(controls, text="Clear", command=self.clear_files).pack(side="left")
        ttk.Button(controls, text="Duplicates", command=self.scan_duplicates).pack(side="left", padx=8)
        ttk.Button(controls, text="Preview", style="Accent.TButton", command=self.preview).pack(side="right")
        ttk.Button(controls, text="Apply", command=self.apply).pack(side="right", padx=8)

        pane = ttk.Frame(self, padding=(14, 0, 14, 8))
        pane.pack(fill="both", expand=True)
        columns = ("file", "audio", "action", "destination")
        self.tree = ttk.Treeview(pane, columns=columns, show="headings", selectmode="extended")
        for col, text, width in (
            ("file", "File", 250),
            ("audio", "Audio", 90),
            ("action", "Action", 340),
            ("destination", "Destination", 400),
        ):
            self.tree.heading(col, text=text)
            self.tree.column(col, width=width, anchor="w")
        yscroll = ttk.Scrollbar(pane, orient="vertical", command=self.tree.yview)
        self.tree.configure(yscrollcommand=yscroll.set)
        self.tree.pack(side="left", fill="both", expand=True)
        yscroll.pack(side="right", fill="y")

        bottom = ttk.Frame(self, padding=(14, 0, 14, 14))
        bottom.pack(fill="both")
        ttk.Label(bottom, textvariable=self.status).pack(anchor="w")
        self.log = tk.Text(bottom, height=7, bg="#0e0f15", fg="#d7d8e1", insertbackground="#fff", relief="flat", wrap="word")
        self.log.pack(fill="both", expand=False, pady=(6, 0))

    def refresh_options(self) -> None:
        for child in self.options.winfo_children():
            child.destroy()
        mode = self.mode.get()
        if mode == "tv":
            for label, var in (("Season", self.season), ("Start Ep", self.start_ep)):
                ttk.Label(self.options, text=label, style="Panel.TLabel").pack(side="left", padx=(0, 6))
                ttk.Spinbox(self.options, from_=0, to=999, textvariable=var, width=5).pack(side="left", padx=(0, 14))
            ttk.Checkbutton(self.options, text="Include show name", variable=self.include_show).pack(side="left", padx=8)
            ttk.Checkbutton(self.options, text="Rename in place", variable=self.rename_in_place).pack(side="left", padx=8)
            ttk.Checkbutton(self.options, text="Manual episode override", variable=self.manual_override).pack(side="left", padx=8)
        elif mode == "movie":
            ttk.Checkbutton(self.options, text="Rename in place", variable=self.rename_in_place).pack(side="left")
        else:
            ttk.Label(self.options, text="Audio Fix scans for HE-AAC and converts it to AAC LC stereo.", style="Panel.TLabel").pack(side="left")
        ttk.Label(self.options, text="Extensions", style="Panel.TLabel").pack(side="right", padx=(10, 6))
        ttk.Entry(self.options, textvariable=self.exts, width=24).pack(side="right")

    def open_settings(self) -> None:
        win = tk.Toplevel(self)
        win.title("Settings")
        win.transient(self)
        win.grab_set()
        win.configure(bg="#12131a")
        frame = ttk.Frame(win, padding=16)
        frame.pack(fill="both", expand=True)
        ttk.Label(frame, text="TMDB API Key").grid(row=0, column=0, sticky="w")
        ttk.Entry(frame, textvariable=self.tmdb_key, width=58, show="*").grid(row=1, column=0, columnspan=2, sticky="ew", pady=(4, 12))
        ttk.Label(frame, text="FFmpeg").grid(row=2, column=0, sticky="w")
        ttk.Entry(frame, textvariable=self.ffmpeg, width=48).grid(row=3, column=0, sticky="ew", pady=(4, 12))
        ttk.Button(frame, text="Browse", command=lambda: self.pick_ffmpeg()).grid(row=3, column=1, padx=(8, 0))
        ttk.Button(frame, text="Save", style="Accent.TButton", command=lambda: self.save_settings(win)).grid(row=4, column=1, sticky="e")

    def pick_ffmpeg(self) -> None:
        path = filedialog.askopenfilename(title="Select ffmpeg", filetypes=[("FFmpeg", "ffmpeg ffmpeg.exe"), ("All files", "*")])
        if path:
            self.ffmpeg.set(path)

    def save_settings(self, win: tk.Toplevel) -> None:
        self.cfg["tmdb_key"] = self.tmdb_key.get().strip()
        self.cfg["ffmpeg"] = self.ffmpeg.get().strip()
        mf.save_config(self.cfg)
        self.log_line(f"Settings saved to {mf.config_path()}")
        win.destroy()

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

    def clear_files(self) -> None:
        self.files.clear()
        self.plans.clear()
        self.audio_rows.clear()
        self.render_files()
        self.status.set("Ready")

    def render_files(self) -> None:
        self.tree.delete(*self.tree.get_children())
        for path in self.files:
            self.tree.insert("", "end", values=(path.name, "", "Queued", str(path.parent)))

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
                import re

                match = re.search(r"(?i)S\d{1,2}E\d{1,3}", path.stem)
                if not match:
                    continue
                key = match.group(0).upper()
            else:
                import re

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

    def run_worker(self, apply: bool) -> None:
        if not self.files:
            messagebox.showinfo("MediaForge", "Add files or a folder first.")
            return
        self.status.set("Working...")
        self.log_line(("Applying" if apply else "Previewing") + f" {self.mode.get()} operation...")
        thread = threading.Thread(target=self._worker, args=(apply,), daemon=True)
        thread.start()

    def _worker(self, apply: bool) -> None:
        try:
            client = mf.MetadataClient(self.tmdb_key.get().strip())
            mode = self.mode.get()
            if mode == "tv":
                plans = mf.tv_plans(client, self.files, self.season.get(), self.start_ep.get(), self.include_show.get(), self.rename_in_place.get(), self.manual_override.get())
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
                    self.log_line(str(payload))
                elif kind == "error":
                    self.status.set("Error")
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

    def show_audio(self, rows: list[dict]) -> None:
        self.tree.delete(*self.tree.get_children())
        for row in rows:
            path = row["file"]
            self.tree.insert("", "end", values=(path.name, row["label"], row["action"], str(path)))
        pending = sum(1 for r in rows if r.get("heaac"))
        self.status.set(f"{pending} file(s) need audio conversion")

    def log_line(self, text: str) -> None:
        self.log.insert("end", text + "\n")
        self.log.see("end")


if __name__ == "__main__":
    MediaForgeApp().mainloop()
