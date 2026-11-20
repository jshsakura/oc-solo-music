"""파일을 Range 로 내려주는 부분.

아이폰 백그라운드 재생의 마지막 관문이다. iOS 사파리는 오디오를 열 때 먼저
`Range: bytes=0-1` 을 던져보고 206 이 제대로 오는지로 시킹 가능 여부를 판단한다.
여기가 틀리면 재생은 되면서 탐색만 죽는 식으로 애매하게 깨진다.
"""

from __future__ import annotations

from pathlib import Path

from fastapi import Request
from fastapi.responses import FileResponse, Response, StreamingResponse


def parse_range(header: str | None, size: int) -> tuple[int, int] | None:
    """`Range: bytes=a-b` 를 (start, end) 로. 없거나 잘못됐으면 None."""
    if not header or not header.startswith("bytes="):
        return None
    spec = header[6:].split(",")[0].strip()
    if "-" not in spec:
        return None
    a, _, b = spec.partition("-")
    try:
        if not a:  # bytes=-500 → 마지막 500 바이트
            n = int(b)
            if n <= 0:
                return None
            return max(0, size - n), size - 1
        start = int(a)
        end = int(b) if b else size - 1
    except ValueError:
        return None
    if start >= size or start > end:
        return None
    return start, min(end, size - 1)


def ranged_file(path: Path, request: Request, media_type: str = "audio/mpeg",
                max_age: int = 86400) -> Response:
    size = path.stat().st_size
    headers = {
        "Accept-Ranges": "bytes",
        "Cache-Control": f"private, max-age={max_age}",
        "Content-Type": media_type,
    }
    head = request.method == "HEAD"
    rng = parse_range(request.headers.get("range"), size)

    if rng is None:
        headers["Content-Length"] = str(size)
        if head:
            return Response(status_code=200, headers=headers)
        return FileResponse(path, headers=headers, media_type=media_type)

    start, end = rng
    length = end - start + 1
    headers["Content-Range"] = f"bytes {start}-{end}/{size}"
    headers["Content-Length"] = str(length)
    if head:
        return Response(status_code=206, headers=headers)

    def chunks():
        with path.open("rb") as fh:
            fh.seek(start)
            left = length
            while left > 0:
                data = fh.read(min(64 * 1024, left))
                if not data:
                    break
                left -= len(data)
                yield data

    return StreamingResponse(chunks(), status_code=206, headers=headers)
