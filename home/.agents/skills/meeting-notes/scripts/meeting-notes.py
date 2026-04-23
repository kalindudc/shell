#!/usr/bin/env python3
"""meeting-notes.py -- read-only Google Docs/Sheets fetcher.

Pulls a Google Doc (with multi-tab content) and any linked Google Sheets,
then emits a structured JSON bundle plus raw per-resource dumps for a
downstream LLM to summarize. This script is READ-ONLY by construction:

  * Only HTTP GET is ever issued (central http_get helper).
  * Host whitelist: docs.googleapis.com, sheets.googleapis.com, www.googleapis.com.
  * Path-prefix whitelist: /v1/documents/, /v4/spreadsheets/, /drive/v3/about,
    /drive/v3/files/.
  * URL-substring denylist rejects any known write endpoint.
  * A pre-flight self-check greps this very file for write-shaped literals
    and aborts with exit code 2 if any are found.

Stdlib only. Python 3.9+. macOS.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil  # noqa: F401  (kept available per skill spec)
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from urllib import parse as urlparse
from urllib import request as urlrequest
from urllib.error import HTTPError, URLError


# ---------------------------------------------------------------------------
# Hex-encoded sensitive literals.
#
# These strings MUST NOT appear verbatim in this file's source, otherwise the
# self-check below will trip on itself. We decode them at import time.
# ---------------------------------------------------------------------------


def _hex(h: str) -> str:
    return bytes.fromhex(h).decode("ascii")


# Forbidden literals the self-check looks for in source. The actual
# strings are hex-encoded below so they do not appear verbatim here.
_FORBIDDEN_SRC_LITERALS = [
    _hex("6261746368557064617465"),
    _hex("66696c65732e757064617465"),
    _hex("66696c65732e636f7079"),
    _hex("66696c65732e64656c657465"),
    _hex("7065726d697373696f6e732e637265617465"),
    _hex("7265766973696f6e732e64656c657465"),
]

# Quoted HTTP verbs other than GET. Built at runtime so the literals never
# appear in source. Regex equivalent to: "(POST|PUT|PATCH|DELETE)".
_WRITE_VERBS = [
    _hex("504f5354"),
    _hex("505554"),
    _hex("5041544348"),
    _hex("44454c455445"),
]
_FORBIDDEN_VERB_RE = re.compile('"(' + "|".join(_WRITE_VERBS) + ')"')

# URL-substring denylist. Enforced inside http_get(). Strings below are
# hex-encoded to keep them out of this file's source verbatim.
_FORBIDDEN_URL_SUBSTRINGS = [
    _hex("3a6261746368557064617465"),
    _hex("3a636f7079"),
    _hex("3a757064617465"),
    _hex("2f7065726d697373696f6e73"),
    _hex("2f7265766973696f6e73"),
    _hex("3a6578706f7274"),
]

ALLOWED_HOSTS = {
    "docs.googleapis.com",
    "sheets.googleapis.com",
    "www.googleapis.com",
}

ALLOWED_PATH_PREFIXES = (
    "/v1/documents/",
    "/v4/spreadsheets/",
    "/drive/v3/about",
    "/drive/v3/files/",
)

SHEET_URL_RE = re.compile(
    r"https?://docs\.google\.com/spreadsheets/d/([a-zA-Z0-9_-]+)"
)
DOC_ID_RE = re.compile(r"/document/d/([a-zA-Z0-9_-]+)")

MAX_SHEETS = 10
MAX_TABS_PER_SHEET = 50
MAX_ROWS_PER_TAB = 1000

VERBOSE = False


# ---------------------------------------------------------------------------
# Tiny helpers
# ---------------------------------------------------------------------------


def log(msg: str) -> None:
    """Print to stderr when --verbose is set."""
    if VERBOSE:
        print(msg, file=sys.stderr)


def die(msg: str, code: int = 1) -> None:
    """Print an ERROR line to stderr and exit."""
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(code)


# ---------------------------------------------------------------------------
# Pre-flight self-check
# ---------------------------------------------------------------------------


def self_check() -> None:
    """Grep this file's source for write-shaped literals. Exit 2 on match."""
    try:
        src = Path(__file__).read_text(encoding="utf-8")
    except Exception as exc:  # pragma: no cover -- defensive
        print(
            f"ERROR: self-check could not read own source ({exc})",
            file=sys.stderr,
        )
        sys.exit(2)

    m = _FORBIDDEN_VERB_RE.search(src)
    if m:
        print(
            f"ERROR: self-check tripped on forbidden quoted verb: {m.group(0)}",
            file=sys.stderr,
        )
        sys.exit(2)

    for lit in _FORBIDDEN_SRC_LITERALS:
        if lit in src:
            print(
                f"ERROR: self-check tripped on forbidden literal: {lit}",
                file=sys.stderr,
            )
            sys.exit(2)


# ---------------------------------------------------------------------------
# Central HTTP GET with whitelists
# ---------------------------------------------------------------------------


def http_get(url: str, token: str, timeout: int = 30):
    """Perform a safe, whitelisted GET. Returns (status:int, body:dict)."""
    parsed = urlparse.urlsplit(url)

    if parsed.scheme != "https":
        raise RuntimeError(f"refusing non-https URL: {url}")
    if parsed.netloc not in ALLOWED_HOSTS:
        raise RuntimeError(f"host not in whitelist: {parsed.netloc}")
    if not any(parsed.path.startswith(p) for p in ALLOWED_PATH_PREFIXES):
        raise RuntimeError(f"path prefix not in whitelist: {parsed.path}")
    for bad in _FORBIDDEN_URL_SUBSTRINGS:
        if bad in url:
            raise RuntimeError(f"URL contains denylisted substring: {bad}")

    req = urlrequest.Request(
        url,
        method="GET",
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/json",
        },
    )
    # Defence-in-depth: Request.method is user-settable; re-verify.
    if req.get_method() != "GET":
        raise RuntimeError("non-GET request rejected by http_get")

    try:
        with urlrequest.urlopen(req, timeout=timeout) as resp:
            status = resp.status
            body = resp.read()
    except HTTPError as exc:
        raw = exc.read().decode("utf-8", errors="replace")
        try:
            return exc.code, json.loads(raw)
        except Exception:
            return exc.code, {"_raw": raw}
    except URLError as exc:
        raise RuntimeError(f"network error calling {url}: {exc}") from exc

    text = body.decode("utf-8", errors="replace")
    try:
        return status, json.loads(text)
    except Exception:
        return status, {"_raw": text}


# ---------------------------------------------------------------------------
# Auth
# ---------------------------------------------------------------------------


def get_access_token() -> str:
    """Shell out to gcloud for a bearer token."""
    try:
        r = subprocess.run(
            ["gcloud", "auth", "print-access-token"],
            capture_output=True,
            text=True,
            timeout=10,
        )
    except FileNotFoundError:
        die("gcloud CLI not found. Install the Google Cloud SDK and run `gcloud auth login`.")
    except subprocess.TimeoutExpired:
        die("`gcloud auth print-access-token` timed out after 10s")

    if r.returncode != 0 or not r.stdout.strip():
        stderr = (r.stderr or "").strip()
        die(
            "gcloud could not print an access token. Run `gcloud auth login`.\n"
            f"gcloud stderr:\n{stderr}"
        )
    return r.stdout.strip()


def drive_about(token: str) -> str:
    """Call Drive about to surface the account email and verify scopes."""
    status, body = http_get(
        "https://www.googleapis.com/drive/v3/about?fields=user",
        token,
    )
    body_str = json.dumps(body) if isinstance(body, dict) else str(body)
    if status == 403 and "ACCESS_TOKEN_SCOPE_INSUFFICIENT" in body_str:
        die(
            "Your gcloud access token lacks Drive/Docs scopes. "
            "Re-run `gcloud auth login` and ensure Drive and Docs scopes "
            "are granted for your account."
        )
    if status != 200:
        die(f"drive.about failed: status={status} body={body_str[:400]}")
    return (body.get("user") or {}).get("emailAddress", "unknown")


# ---------------------------------------------------------------------------
# Doc id extraction
# ---------------------------------------------------------------------------


def extract_doc_id(url: str) -> str:
    """Pull the document id out of a Google Docs URL."""
    m = DOC_ID_RE.search(url)
    if not m:
        die("could not extract document id from URL")
    return m.group(1)


# ---------------------------------------------------------------------------
# Doc content walker
# ---------------------------------------------------------------------------


def _walk_structural_elements(
    elements,
    out_text: list,
    out_links: list,
) -> None:
    """Recursive walker over a list of Docs StructuralElement dicts."""
    for el in elements or []:
        para = el.get("paragraph")
        if para is not None:
            for pe in para.get("elements", []) or []:
                tr = pe.get("textRun")
                if tr is not None:
                    content = tr.get("content", "") or ""
                    out_text.append(content)
                    link = ((tr.get("textStyle") or {}).get("link") or {})
                    url = link.get("url")
                    if url:
                        out_links.append(
                            {"url": url, "anchor": content.strip()}
                        )
                # Rich-link chips (e.g. @-mentions of Sheets) land here.
                rl = pe.get("richLink")
                if rl is not None:
                    props = rl.get("richLinkProperties") or {}
                    url = props.get("uri")
                    title = props.get("title") or ""
                    if url:
                        out_links.append(
                            {"url": url, "anchor": title.strip()}
                        )
            continue

        table = el.get("table")
        if table is not None:
            for row in table.get("tableRows", []) or []:
                for cell in row.get("tableCells", []) or []:
                    _walk_structural_elements(
                        cell.get("content", []) or [],
                        out_text,
                        out_links,
                    )
            continue

        # sectionBreak, tableOfContents, etc. are intentionally ignored.


def _flatten_tabs(tabs, flat: list, depth: int = 0, parent=None) -> None:
    """Flatten the nested tabs[] tree into a simple list."""
    for t in tabs or []:
        props = t.get("tabProperties") or {}
        doc_tab = t.get("documentTab") or {}
        body = doc_tab.get("body") or {}

        text_parts: list = []
        links: list = []
        _walk_structural_elements(
            body.get("content", []) or [], text_parts, links
        )
        text = "".join(text_parts)
        title = props.get("title", "") or ""

        ts_matches = len(re.findall(r"\b\d\d:\d\d(?::\d\d)?\b", text))
        is_transcript = (
            bool(re.search(r"transcript|recording|captions", title, re.I))
            or ts_matches >= 10
        )

        flat.append(
            {
                "tabId": props.get("tabId", ""),
                "title": title,
                "depth": depth,
                "parentTabId": parent,
                "isTranscript": is_transcript,
                "charCount": len(text),
                "text": text,
                "links": links,
            }
        )

        _flatten_tabs(
            t.get("childTabs", []) or [],
            flat,
            depth + 1,
            props.get("tabId"),
        )


# ---------------------------------------------------------------------------
# Linked Sheets
# ---------------------------------------------------------------------------


def _collect_sheet_ids(tabs_flat) -> list:
    """De-duplicated, insertion-ordered list of linked Sheet ids."""
    seen: dict = {}
    for tab in tabs_flat:
        for link in tab.get("links", []) or []:
            url = link.get("url") or ""
            m = SHEET_URL_RE.search(url)
            if m:
                sid = m.group(1)
                if sid not in seen:
                    seen[sid] = True
    return list(seen.keys())


def fetch_sheet(sheet_id: str, token: str, output_dir: Path, warnings: list) -> dict:
    """Fetch metadata + row values for a single Sheet. Never raises."""
    meta_url = (
        f"https://sheets.googleapis.com/v4/spreadsheets/{sheet_id}"
        "?includeGridData=false"
    )
    log(f"fetching sheet metadata: {sheet_id}")
    status, meta = http_get(meta_url, token)

    if status == 403:
        return {"id": sheet_id, "title": None, "tabs": [], "error": "permission_denied"}
    if status == 404:
        return {"id": sheet_id, "title": None, "tabs": [], "error": "not_found"}
    if status != 200:
        warnings.append(f"sheet {sheet_id}: metadata status={status}")
        return {"id": sheet_id, "title": None, "tabs": [], "error": f"http_{status}"}

    title = ((meta.get("properties") or {}).get("title")) if isinstance(meta, dict) else None
    sheet_props = [
        s.get("properties") or {}
        for s in (meta.get("sheets") or [])
        if isinstance(s, dict)
    ]
    sheet_names = [p.get("title") for p in sheet_props if p.get("title")]

    if len(sheet_names) > MAX_TABS_PER_SHEET:
        warnings.append(
            f"sheet {sheet_id}: {len(sheet_names)} tabs; truncated to {MAX_TABS_PER_SHEET}"
        )
        sheet_names = sheet_names[:MAX_TABS_PER_SHEET]

    combined = {"metadata": meta, "values": {}}
    tabs_out = []
    for name in sheet_names:
        enc = urlparse.quote(name, safe="")
        values_url = (
            f"https://sheets.googleapis.com/v4/spreadsheets/{sheet_id}"
            f"/values/{enc}?majorDimension=ROWS"
        )
        log(f"fetching sheet values: {sheet_id} / {name}")
        vstatus, vbody = http_get(values_url, token)
        if vstatus != 200:
            warnings.append(
                f"sheet {sheet_id} tab {name!r}: values status={vstatus}"
            )
            tabs_out.append(
                {"name": name, "rowCount": 0, "rows": [], "error": f"http_{vstatus}"}
            )
            continue
        combined["values"][name] = vbody
        rows = vbody.get("values") or []
        if len(rows) > MAX_ROWS_PER_TAB:
            warnings.append(
                f"sheet {sheet_id} tab {name!r}: {len(rows)} rows truncated to {MAX_ROWS_PER_TAB}"
            )
            rows = rows[:MAX_ROWS_PER_TAB]
        tabs_out.append({"name": name, "rowCount": len(rows), "rows": rows})

    raw_path = output_dir / f"raw-sheet-{sheet_id}.json"
    raw_path.write_text(json.dumps(combined, indent=2), encoding="utf-8")
    log(f"wrote {raw_path}")

    return {"id": sheet_id, "title": title, "tabs": tabs_out, "error": None}


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def _parse_args(argv=None) -> argparse.Namespace:
    p = argparse.ArgumentParser(
        prog="meeting-notes.py",
        description=(
            "Read-only fetcher for a Google Doc (multi-tab) plus any "
            "linked Google Sheets. Emits a JSON bundle for downstream "
            "LLM summarization."
        ),
    )
    p.add_argument("--url", required=True, help="Google Docs URL")
    p.add_argument(
        "--output-dir",
        required=True,
        help="Directory for bundle.json and raw-*.json files (created if missing)",
    )
    p.add_argument(
        "--verbose",
        action="store_true",
        help="Log progress to stderr",
    )
    return p.parse_args(argv)


def _classify_tab(tab: dict) -> str:
    return "transcript" if tab.get("isTranscript") else "notes"


def main(argv=None) -> int:
    global VERBOSE

    self_check()

    args = _parse_args(argv)
    VERBOSE = bool(args.verbose)

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    doc_id = extract_doc_id(args.url)
    log(f"doc id: {doc_id}")

    token = get_access_token()
    log("got access token from gcloud")

    account = drive_about(token)
    log(f"drive.about account: {account}")

    # --- Fetch the doc ---
    doc_url = (
        f"https://docs.googleapis.com/v1/documents/{doc_id}"
        "?includeTabsContent=true"
    )
    log(f"fetching doc: {doc_url}")
    status, doc = http_get(doc_url, token)

    if status in (401, 403):
        die(
            f"Permission denied for doc {doc_id}. Your account {account} "
            "cannot read this document."
        )
    if status == 404:
        die(f"Document {doc_id} not found (or inaccessible to {account}).")
    if status != 200:
        snippet = json.dumps(doc)[:400] if isinstance(doc, dict) else str(doc)[:400]
        die(f"Docs API returned status={status}: {snippet}")

    raw_doc_path = output_dir / "raw-doc.json"
    raw_doc_path.write_text(json.dumps(doc, indent=2), encoding="utf-8")
    log(f"wrote {raw_doc_path}")

    doc_title = doc.get("title", "") or ""

    # --- Flatten tabs ---
    tabs_flat: list = []
    _flatten_tabs(doc.get("tabs") or [], tabs_flat)
    log(f"extracted {len(tabs_flat)} tabs")

    # --- Linked sheets ---
    warnings: list = []
    sheet_ids = _collect_sheet_ids(tabs_flat)
    if len(sheet_ids) > MAX_SHEETS:
        warnings.append(
            f"{len(sheet_ids)} linked sheets found; truncated to {MAX_SHEETS}"
        )
        sheet_ids = sheet_ids[:MAX_SHEETS]

    sheets_out: list = []
    for sid in sheet_ids:
        sheets_out.append(fetch_sheet(sid, token, output_dir, warnings))

    # --- Emit bundle ---
    bundle = {
        "source": {
            "url": args.url,
            "documentId": doc_id,
            "title": doc_title,
            "fetchedAt": datetime.now(timezone.utc)
            .isoformat(timespec="seconds")
            .replace("+00:00", "Z"),
            "account": account,
        },
        "tabs": tabs_flat,
        "sheets": sheets_out,
        "warnings": warnings,
    }

    bundle_path = output_dir / "bundle.json"
    bundle_path.write_text(json.dumps(bundle, indent=2), encoding="utf-8")

    # --- Stdout recap ---
    print(f"Fetched: {doc_title}")
    for tab in tabs_flat:
        print(
            f"  tab: {tab['title']} "
            f"({tab['charCount']:,} chars, {_classify_tab(tab)})"
        )
    print(f"Sheets linked: {len(sheets_out)}")
    for sh in sheets_out:
        label = sh.get("title") or sh.get("id")
        if sh.get("error"):
            print(f"  sheet: {label} [{sh['error']}]")
        else:
            tab_count = len(sh.get("tabs") or [])
            print(f"  sheet: {label} ({tab_count} tab(s))")
    if warnings:
        print(f"Warnings ({len(warnings)}):")
        for w in warnings:
            print(f"  - {w}")
    print(f"Bundle written to: {bundle_path}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
