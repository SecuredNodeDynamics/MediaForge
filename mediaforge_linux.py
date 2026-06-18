#!/usr/bin/env python3
"""Portable MediaForge backend used by the cross-platform desktop app."""

from __future__ import annotations

import base64
import html
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any


MEDIA_EXTS = {".mkv", ".mp4", ".avi", ".m4v", ".mov", ".wmv"}
RELEASE_TAG_RE = re.compile(
    r"\b(1080p|720p|480p|2160p|4k|uhd|bluray|blu-ray|webrip|web-dl|hdtv|"
    r"dvdrip|x264|x265|hevc|avc|aac|ac3|eac3|dts|hdr|sdr|remux|proper|"
    r"repack|extended|theatrical|directors\.cut)\b.*",
    re.I,
)


def config_dir() -> Path:
    if platform.system() == "Windows":
        base = os.environ.get("APPDATA")
        return Path(base) / "MediaForge" if base else Path.home() / "AppData" / "Roaming" / "MediaForge"
    base = os.environ.get("XDG_CONFIG_HOME")
    return Path(base).expanduser() / "MediaForge" if base else Path.home() / ".config" / "MediaForge"


def config_path() -> Path:
    return config_dir() / "config.json"


def app_root() -> Path:
    return Path(getattr(sys, "_MEIPASS", Path(__file__).resolve().parent))


def is_usable_executable(path: Path) -> bool:
    if not path.exists() or not path.is_file():
        return False
    if platform.system() != "Windows" and path.suffix.lower() == ".exe":
        return False
    return os.access(path, os.X_OK) or platform.system() == "Windows"


def bundled_ffmpeg_candidates() -> list[Path]:
    names = ("ffmpeg.exe",) if platform.system() == "Windows" else ("ffmpeg",)
    roots = [
        app_root() / "ffmpeg" / "bin",
        app_root() / "ffmpeg",
        Path(__file__).resolve().parent / "ffmpeg" / "bin",
        Path(__file__).resolve().parent / "ffmpeg",
    ]
    return [root / name for root in roots for name in names]


def load_config() -> dict[str, str]:
    path = config_path()
    if not path.exists():
        legacy = Path.home() / ".config" / "JellyfinRenamer"
        key_file = legacy / "key.dat"
        ffmpeg_file = legacy / "ffmpeg.dat"
        cfg: dict[str, str] = {}
        if key_file.exists():
            try:
                cfg["tmdb_key"] = base64.b64decode(key_file.read_text().strip()).decode()
            except Exception:
                pass
        if ffmpeg_file.exists():
            try:
                cfg["ffmpeg"] = base64.b64decode(ffmpeg_file.read_text().strip()).decode()
            except Exception:
                pass
        return cfg
    try:
        return json.loads(path.read_text())
    except Exception:
        return {}


def save_config(cfg: dict[str, str]) -> None:
    config_dir().mkdir(parents=True, exist_ok=True)
    config_path().write_text(json.dumps(cfg, indent=2, sort_keys=True) + "\n")


def http_json(url: str, data: dict[str, Any] | None = None) -> Any | None:
    headers = {"User-Agent": "MediaForge-Linux/1.0"}
    body = None
    if data is not None:
        body = json.dumps(data).encode()
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=body, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=20) as res:
            return json.loads(res.read().decode())
    except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, json.JSONDecodeError):
        return None


class MetadataClient:
    def __init__(self, tmdb_key: str = "") -> None:
        self.tmdb_key = tmdb_key
        self.season_cache: dict[tuple[int, int], dict[int, dict[str, Any]]] = {}

    def tmdb(self, path: str, query: dict[str, Any] | None = None) -> Any | None:
        if not self.tmdb_key:
            return None
        q = {"api_key": self.tmdb_key}
        if query:
            q.update(query)
        return http_json("https://api.themoviedb.org/3" + path + "?" + urllib.parse.urlencode(q))

    def search_tmdb(self, query: str, media_type: str) -> list[dict[str, Any]]:
        data = self.tmdb(f"/search/{media_type}", {"query": query})
        return data.get("results", []) if isinstance(data, dict) else []

    def anilist(self, search: str) -> list[dict[str, Any]]:
        gql = """
query ($search: String, $type: MediaType) {
  Page(perPage: 10) {
    media(search: $search, type: $type, sort: SEARCH_MATCH) {
      id
      format
      title { romaji english native userPreferred }
      startDate { year }
    }
  }
}
"""
        data = http_json(
            "https://graphql.anilist.co",
            {"query": gql, "variables": {"search": search, "type": "ANIME"}},
        )
        try:
            return data["data"]["Page"]["media"] or []
        except Exception:
            return []

    def season_episodes(self, show_id: int, season: int) -> dict[int, dict[str, Any]]:
        key = (show_id, season)
        if key in self.season_cache:
            return self.season_cache[key]
        out: dict[int, dict[str, Any]] = {}
        if show_id:
            data = self.tmdb(f"/tv/{show_id}/season/{season}")
            for ep in data.get("episodes", []) if isinstance(data, dict) else []:
                num = ep.get("episode_number")
                if isinstance(num, int) and num > 0:
                    out[num] = ep
        self.season_cache[key] = out
        return out


def anilist_title(item: dict[str, Any]) -> str:
    title = item.get("title") or {}
    return title.get("userPreferred") or title.get("english") or title.get("romaji") or title.get("native") or ""


def year_from(date_value: Any) -> str:
    if isinstance(date_value, int):
        return str(date_value)
    if isinstance(date_value, str) and len(date_value) >= 4:
        return date_value[:4]
    return "????"


def sanitize_name(name: str) -> str:
    return re.sub(r'[<>:"/\\|?*\x00-\x1f]', "", name).strip()


def is_season_folder(name: str) -> bool:
    return bool(re.match(r"(?i)^season[\s._-]*\d{1,2}$", name) or re.match(r"(?i)^s\d{1,2}$", name))


def parse_season_episode(path: Path) -> tuple[int | None, int | None]:
    stem = path.stem
    parent = path.parent.name
    if m := re.search(r"(?i)(?:^|[^a-zA-Z])S(\d{1,2})E(\d{1,3})", stem):
        return int(m.group(1)), int(m.group(2))
    if m := re.search(r"(?i)(?:^|[^0-9])(\d{1,2})x(\d{2,3})(?:[^0-9]|$)", stem):
        return int(m.group(1)), int(m.group(2))
    if m := re.match(r"(?i)^season[\s._-]*(\d{1,2})$", parent):
        return int(m.group(1)), None
    if m := re.match(r"(?i)^s(\d{1,2})$", parent):
        return int(m.group(1)), None
    if m := re.search(r"(?i)season[\s._-]*(\d{1,2})", parent):
        return int(m.group(1)), None
    return None, None


def clean_media_candidate(path: Path) -> str:
    name = path.stem
    name = re.sub(r"(?i)[\s._-]*S\d{1,2}E\d{1,3}.*", "", name)
    name = re.sub(r"(?i)[\s._-]*\d{1,2}x\d{2,3}.*", "", name)
    name = re.sub(r"[\s._(-]*\b(19|20)\d{2}\b[\s._)]*", " ", name)
    name = RELEASE_TAG_RE.sub("", name)
    name = name.replace(".", " ").replace("_", " ")
    return re.sub(r"\s+", " ", name).strip(" -")


def candidates_from_path(path: Path) -> list[str]:
    candidates = []
    file_candidate = clean_media_candidate(path)
    if len(file_candidate) > 1:
        candidates.append(file_candidate)
    parent = path.parent.name
    if parent and not is_season_folder(parent) and len(parent) > 3:
        folder_candidate = re.sub(r"[\s._(-]*\b(19|20)\d{2}\b[\s._)]*", " ", parent).strip(" -._")
        if len(folder_candidate) > 1 and folder_candidate != file_candidate:
            candidates.append(folder_candidate)
    return candidates


def top_match(candidate: str, title: str) -> bool:
    one = re.sub(r"[^a-z0-9]", "", candidate.lower())
    two = re.sub(r"[^a-z0-9]", "", title.lower())
    return bool(one and two and (one == two or one.startswith(two) or two.startswith(one)))


def collect_files(paths: list[str], exts: set[str]) -> list[Path]:
    files: list[Path] = []
    for raw in paths:
        p = Path(raw).expanduser()
        if p.is_dir():
            files.extend(x for x in p.rglob("*") if x.is_file() and x.suffix.lower() in exts)
        elif p.is_file() and p.suffix.lower() in exts:
            files.append(p)
    return sorted(set(files), key=lambda x: str(x).lower())


@dataclass
class Plan:
    source: Path
    dest: Path
    label: str


def find_movie_match(client: MetadataClient, path: Path) -> dict[str, Any] | None:
    for candidate in candidates_from_path(path):
        if client.tmdb_key:
            results = client.search_tmdb(candidate, "movie")
            if results:
                top = results[0]
                title = top.get("title") or top.get("original_title") or ""
                if top_match(candidate, title):
                    return {"title": title, "year": year_from(top.get("release_date")), "source": "TMDB"}
        for item in client.anilist(candidate):
            if item.get("format") not in {"MOVIE", "OVA", "ONA", "SPECIAL"}:
                continue
            title = anilist_title(item)
            if top_match(candidate, title):
                return {"title": title, "year": year_from((item.get("startDate") or {}).get("year")), "source": "AniList"}
    return None


def find_show_match(client: MetadataClient, path: Path) -> dict[str, Any] | None:
    for candidate in candidates_from_path(path):
        if client.tmdb_key:
            results = client.search_tmdb(candidate, "tv")
            if results:
                top = results[0]
                title = top.get("name") or top.get("original_name") or ""
                if top_match(candidate, title):
                    return {
                        "id": int(top.get("id") or 0),
                        "title": title,
                        "year": year_from(top.get("first_air_date")),
                        "source": "TMDB",
                    }
        for item in client.anilist(candidate):
            if item.get("format") == "MOVIE":
                continue
            title = anilist_title(item)
            if top_match(candidate, title):
                return {
                    "id": 0,
                    "title": title,
                    "year": year_from((item.get("startDate") or {}).get("year")),
                    "source": "AniList",
                }
    return None


def normalize_tmdb_show(item: dict[str, Any]) -> dict[str, Any]:
    title = item.get("name") or item.get("original_name") or ""
    return {
        "id": int(item.get("id") or 0),
        "title": title,
        "year": year_from(item.get("first_air_date")),
        "source": "TMDB",
    }


def movie_plans(client: MetadataClient, files: list[Path], rename_in_place: bool) -> list[Plan]:
    plans = []
    for path in files:
        match = find_movie_match(client, path)
        if not match:
            print(f"unmatched: {path}")
            continue
        title = sanitize_name(match["title"])
        year = match["year"]
        if rename_in_place:
            dest = path.with_name(f"{title} ({year}){path.suffix}")
            label = dest.name
        else:
            folder = f"{title} ({year})"
            dest = path.parent / folder / f"{folder}{path.suffix}"
            label = f"{folder}/{dest.name}"
        plans.append(Plan(path, dest, f"{path.name} -> {label} [{match['source']}]"))
    return plans


def tv_plans(
    client: MetadataClient,
    files: list[Path],
    season: int,
    start_ep: int,
    include_show_name: bool,
    rename_in_place: bool,
    manual_override: bool,
    selected_show: dict[str, Any] | None = None,
) -> list[Plan]:
    plans = []
    counters: dict[tuple[str, int], int] = {}
    for path in files:
        match = selected_show or find_show_match(client, path)
        if not match:
            print(f"unmatched: {path}")
            continue
        parsed_season, parsed_ep = parse_season_episode(path)
        out_season = season if manual_override or not parsed_season else parsed_season
        key = (match["title"], out_season)
        counters.setdefault(key, start_ep)
        if manual_override or parsed_ep is None:
            ep_num = counters[key]
            counters[key] += 1
        else:
            ep_num = parsed_ep

        ep_name = f"Episode {ep_num}"
        if match["source"] == "TMDB" and match["id"]:
            ep = client.season_episodes(match["id"], out_season).get(ep_num)
            if ep and ep.get("name"):
                ep_name = ep["name"]
        show_name = sanitize_name(match["title"])
        ep_name = sanitize_name(ep_name)
        ep_tag = f"S{out_season:02d}E{ep_num:02d}"
        new_name = f"{show_name} - {ep_tag} - {ep_name}{path.suffix}" if include_show_name else f"{ep_tag} - {ep_name}{path.suffix}"
        already_season = is_season_folder(path.parent.name)
        if rename_in_place or already_season:
            dest = path.with_name(new_name)
            label = dest.name
        else:
            dest = path.parent / f"{show_name} ({match['year']})" / f"Season {out_season:02d}" / new_name
            label = str(dest.relative_to(path.parent))
        plans.append(Plan(path, dest, f"{path.name} -> {label} [{match['source']}]"))
    return plans


def apply_plans(plans: list[Plan], dry_run: bool) -> None:
    for plan in plans:
        state = "skip" if plan.source == plan.dest else "plan" if dry_run else "move"
        print(f"{state}: {plan.label}")
        if dry_run or plan.source == plan.dest:
            continue
        plan.dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(plan.source), str(plan.dest))
    print(f"{'Previewed' if dry_run else 'Processed'} {len(plans)} file(s).")


def ffprobe_path(ffmpeg: str = "") -> str:
    configured = Path(ffmpeg).expanduser() if ffmpeg else None
    if configured and is_usable_executable(configured):
        names = ("ffprobe.exe",) if platform.system() == "Windows" else ("ffprobe",)
        for name in names:
            sibling = configured.with_name(name)
            if is_usable_executable(sibling):
                return str(sibling)
    bundled_ffmpeg = ffmpeg_path("")
    if bundled_ffmpeg:
        names = ("ffprobe.exe",) if platform.system() == "Windows" else ("ffprobe",)
        for name in names:
            sibling = Path(bundled_ffmpeg).with_name(name)
            if is_usable_executable(sibling):
                return str(sibling)
    found = shutil.which("ffprobe.exe") if platform.system() == "Windows" else shutil.which("ffprobe")
    return found or ""


def ffmpeg_path(configured: str = "") -> str:
    if configured:
        configured_path = Path(configured).expanduser()
        if is_usable_executable(configured_path):
            return str(configured_path)
    for candidate in bundled_ffmpeg_candidates():
        if is_usable_executable(candidate):
            return str(candidate)
    found = shutil.which("ffmpeg.exe") if platform.system() == "Windows" else shutil.which("ffmpeg")
    return found or ""


def audio_info(path: Path, probe: str) -> dict[str, Any]:
    if not probe:
        return {"label": "-", "heaac": False}
    cmd = [
        probe,
        "-v",
        "quiet",
        "-select_streams",
        "a:0",
        "-show_entries",
        "stream=codec_name,profile,bit_rate,channels",
        "-of",
        "json",
        str(path),
    ]
    try:
        data = json.loads(subprocess.check_output(cmd, text=True, stderr=subprocess.STDOUT))
        stream = (data.get("streams") or [{}])[0]
    except Exception:
        return {"label": "Err", "heaac": False}
    codec = str(stream.get("codec_name") or "unknown").lower()
    profile = str(stream.get("profile") or "")
    bitrate = int(stream.get("bit_rate") or 0)
    heaac = codec == "aac" and ("HE-AAC" in profile or "aac_he" in profile or (not profile and 0 < bitrate < 80000))
    labels = {"aac": "HE-AAC" if heaac else "AAC LC", "ac3": "AC3", "eac3": "EAC3", "dts": "DTS", "truehd": "TrueHD", "mp3": "MP3", "flac": "FLAC", "opus": "Opus", "vorbis": "Vorbis"}
    return {"label": labels.get(codec, codec.upper()), "heaac": heaac}


def audio_scan(files: list[Path], probe: str) -> list[dict[str, Any]]:
    rows = []
    for path in files:
        info = audio_info(path, probe)
        action = "will convert" if info["heaac"] else "ok"
        print(f"{action:12} {info['label']:8} {path}")
        rows.append({"file": path, **info, "action": action})
    return rows


def audio_fix(files: list[Path], ffmpeg: str, probe: str, dry_run: bool, report: Path | None) -> None:
    rows = audio_scan(files, probe)
    results = []
    for row in rows:
        path = row["file"]
        if not row["heaac"]:
            results.append({"file": str(path), "status": "Skipped", "detail": row["label"]})
            continue
        tmp = path.with_name(f"__heaac_fix_{path.name}")
        cmd = [ffmpeg, "-i", str(path), "-c:v", "copy", "-c:a", "aac", "-ac", "2", "-b:a", "192k", "-y", str(tmp)]
        if dry_run:
            print("dry-run:", " ".join(urllib.parse.quote(x) if " " in x else x for x in cmd))
            results.append({"file": str(path), "status": "Skipped", "detail": "dry-run"})
            continue
        proc = subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if proc.returncode == 0 and tmp.exists():
            tmp.replace(path)
            print(f"fixed: {path}")
            results.append({"file": str(path), "status": "Fixed", "detail": "Converted to AAC LC stereo"})
        else:
            if tmp.exists():
                tmp.unlink()
            detail = (proc.stderr.strip().splitlines()[-1] if proc.stderr.strip() else f"ffmpeg exit {proc.returncode}")
            print(f"failed: {path}: {detail}")
            results.append({"file": str(path), "status": "Failed", "detail": detail})
    if report:
        save_audio_report(report, results)


def save_audio_report(path: Path, rows: list[dict[str, str]]) -> None:
    counts = {name: sum(1 for r in rows if r["status"] == name) for name in ("Fixed", "Failed", "Skipped")}
    body = "\n".join(
        f"<tr class='{html.escape(r['status'].lower())}'><td>{html.escape(r['file'])}</td>"
        f"<td>{html.escape(r['status'])}</td><td>{html.escape(r['detail'])}</td></tr>"
        for r in rows
    )
    doc = f"""<!doctype html><html lang="en"><head><meta charset="utf-8"><title>MediaForge Report</title>
<style>body{{font-family:sans-serif;background:#111;color:#ddd;padding:32px}}table{{width:100%;border-collapse:collapse}}td,th{{padding:8px;border-bottom:1px solid #333;text-align:left}}.fixed td{{color:#8ee09f}}.failed td{{color:#ff8888}}.skipped td{{color:#aaa}}</style></head>
<body><h1>MediaForge Report</h1><p>{datetime.now().strftime('%Y-%m-%d %H:%M')} | Fixed: {counts['Fixed']} | Failed: {counts['Failed']} | Skipped: {counts['Skipped']}</p>
<table><thead><tr><th>File</th><th>Status</th><th>Detail</th></tr></thead><tbody>{body}</tbody></table></body></html>"""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(doc)
    print(f"report: {path}")


def duplicate_scan(files: list[Path], mode: str) -> None:
    groups: dict[str, list[Path]] = {}
    for path in files:
        if mode == "tv":
            m = re.search(r"(?i)S\d{1,2}E\d{1,3}", path.stem)
            if not m:
                continue
            key = m.group(0).upper()
        else:
            key = re.sub(r"\s+", " ", path.stem).lower().strip()
        groups.setdefault(key, []).append(path)
    found = False
    for key, paths in sorted(groups.items()):
        if len(paths) < 2:
            continue
        found = True
        print(f"[{key}] {len(paths)} copies")
        for path in sorted(paths):
            print(f"  {path.name} ({path.stat().st_size / 1024 / 1024:.1f} MB)")
            print(f"  {path}")
    if not found:
        print("No duplicates found.")


def parse_exts(value: str) -> set[str]:
    return {x.strip().lower() if x.strip().startswith(".") else "." + x.strip().lower() for x in value.split(",") if x.strip()}


if __name__ == "__main__":
    from MediaForge import MediaForgeApp

    MediaForgeApp().mainloop()
