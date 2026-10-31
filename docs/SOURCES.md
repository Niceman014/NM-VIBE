# NM VIBE Music Sources

| Source | Stream | Offline copy | Status / conditions |
| --- | --- | --- | --- |
| Local files | Yes | Already on device | Built. The main catalog. |
| Internet Archive | Yes | Only items marked public domain, CC0, CC BY or CC BY-SA | Built. Check licence per item. Unknown, NC and ND items are stream only. |
| Jamendo | Yes | No | Built, stream only, through the backend. A paid app needs a commercial agreement first. Credit + backlink required. |
| Audius | Yes | No | Not built. Read API terms and get a key first. |
| Internet radio | Yes | No | Not built. Public stream endpoints only. |
| YouTube, Piped, social platforms | — | — | Do not build. |

- **Download gate**: offer downloads only when both `canDownload` and `downloadAllowed` are true.
- **Internet Archive**: check each item licence; unknown, NC, and ND items are stream-only.
- **Jamendo**: stream through the backend only; commercial use requires an agreement.
- **Attribution**: show each online track's source, credit, and licence link.
