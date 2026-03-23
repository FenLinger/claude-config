---
name: source-fetch
description: Search and download papers/books from Anna's Archive via JSON API. Use when deep-research-survey Phase 3 needs full-text acquisition, or standalone when the user asks to download a specific paper or book.
---

# Source Fetch

## Overview

Acquire full-text papers and books from Anna's Archive using its JSON API.
Replaces the broken `annas-mcp` MCP server with direct `curl` calls.

## Configuration

Read these values from `.env` in the repository root:

| Variable | Purpose | Default |
|----------|---------|---------|
| `ANNAS_SECRET_KEY` | API key for `fast_download.json` | *(required)* |
| `ANNAS_DOWNLOAD_PATH` | Local download directory | `./download/` |

To extract the key programmatically:

```bash
grep ANNAS_SECRET_KEY .env | cut -d= -f2
```

## Workflow

### Step 1 — Search

Search for articles (default) or books. Extract MD5 hashes from the results page.

**Articles:**

```bash
curl -s "https://annas-archive.gl/search?q=<query>&ext=pdf" | grep -oP 'href="/md5/\K[a-f0-9]{32}'
```

**Books:**

```bash
curl -s "https://annas-archive.gl/search?q=<query>&content=book_any&ext=pdf" | grep -oP 'href="/md5/\K[a-f0-9]{32}'
```

Take the first few unique MD5 hashes (typically 3–5) for verification in Step 2.

### Step 2 — Verify metadata

Confirm the result matches the intended source by checking the title on the MD5 page:

```bash
curl -s "https://annas-archive.gl/md5/<md5>" | grep -oP '<title>\K[^<]+'
```

Compare the returned title against the expected author/title/year. Discard non-matches.

### Step 3 — Get download URL

Call the JSON API with the verified MD5 and the API key:

```bash
curl -s "https://annas-archive.gl/dyn/api/fast_download.json?md5=<md5>&key=<api_key>"
```

Parse the `download_url` field from the JSON response. If the response contains an error or no URL, log the failure and skip.

### Step 4 — Download

Download the PDF to the configured download path:

```bash
curl -L -o download/<filename>.pdf "<download_url>"
```

**Filename convention:** `<author>-<shorttitle>-<year>.pdf`, kebab-case, no spaces.

Examples:
- `farrow-continuously-variable-1988.pdf`
- `harris-multirate-signal-processing-2004.pdf`
- `vaidyanathan-multirate-systems-1993.pdf`

### Step 5 — Verify download

Check file size — reject anything under 100 KB as likely corrupt or a stub page:

```bash
ls -la download/<filename>.pdf
```

If the file is < 100 KB:
1. Delete the corrupt file.
2. Try the next MD5 from Step 1 if available.
3. If all candidates fail, flag in the evidence ledger as unavailable.

### Step 6 — Extract and confirm content

Use pymupdf to extract the table of contents or first-page text to confirm the content matches:

```bash
python -c "
import fitz
doc = fitz.open('download/<filename>.pdf')
toc = doc.get_toc()
if toc:
    for level, title, page in toc[:15]:
        print('  ' * level + title + f' (p.{page})')
else:
    print(doc[0].get_text()[:500])
doc.close()
"
```

If the content does not match expectations, delete and retry with the next candidate.

## Rules

- **Format:** PDF only. Never request other formats.
- **Budget:** ~50 downloads per day. Track with a running counter: `Downloads: N/~50 used, holdback: H remaining`.
- **Holdback:** When called from `deep-research-survey`, reserve ~10–15 downloads for gaps discovered during synthesis (Phase 4).
- **Filenames:** `<author>-<shorttitle>-<year>.pdf`, kebab-case, no spaces, no special characters.
- **Size check:** Reject files < 100 KB as corrupt/stub.
- **Content check:** Always verify TOC or first-page text after download.
- **Ledger entry:** Record each successful download as `[Author, Title, Year] (local: download/<filename>)`.
- **Failures:** Log failed downloads in the evidence ledger Gaps column. Fall back to abstract-level citation.

## Standalone Usage

When invoked directly (not from `deep-research-survey`), accept the query as an argument:

```
/source-fetch Farrow continuously variable digital delay
/source-fetch book: Vaidyanathan Multirate Systems
```

Run through Steps 1–6, report the result, and place the file in the download directory.
