"""진행률 줄을 읽는지 보려고 서버가 띄우는 가짜 작업입니다."""
from app.library import report_progress

report_progress(0.25)
print("잡담 한 줄")
report_progress(0.5)
