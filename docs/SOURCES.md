# NM VIBE Music Sources

| Source | Stream | Offline copy | Status / conditions |
| --- | --- | --- | --- |
| Local files | Yes | Already on device | Built. The main catalog. |
| Internet Archive | Yes | Only when item metadata indicates a supported permission | Built. Check rights and attribution per item. Unknown, NC and ND items are stream-only. |
| Audius | — | — | Not built or approved. No provider integration is planned in this task. |
| Internet radio | — | — | Not built or approved. No provider integration is planned in this task. |
| YouTube, Piped, social platforms | — | — | Do not build. |

- **Download gate**: offer downloads only when both `canDownload` and `downloadAllowed` are true.
- **Internet Archive**: evaluate each item's rights metadata; unknown, NC, and ND items are stream-only.
- **Attribution**: show each online track's source, credit, and licence link when available.
- **Backend**: retained for health checks and update metadata. Discover search does not require it.
