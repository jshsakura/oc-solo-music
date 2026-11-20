"""서버 문구가 요청 언어로 나가는지 봅니다."""

from app import messages
from app.messages import msg


def test_every_message_has_all_three_languages():
    for code, table in messages.CATALOG.items():
        assert set(table) == set(messages.LANGS), code
        assert all(text.strip() for text in table.values()), code


def test_placeholders_match_across_languages():
    import string
    for code, table in messages.CATALOG.items():
        fields = [{f for _, f, _, _ in string.Formatter().parse(t) if f} for t in table.values()]
        assert all(f == fields[0] for f in fields), code


def test_picks_query_then_accept_language_then_english():
    assert messages.pick_language("ja", "ko-KR,ko;q=0.9") == "ja"
    assert messages.pick_language(None, "fr-FR,ja;q=0.8,ko;q=0.9") == "ko"
    assert messages.pick_language(None, "de-DE") == "en"
    assert messages.pick_language(None, None) == "en"


def test_renders_codes_and_passes_plain_text_through():
    take = msg("suno.take", actual="1.00", expected="1.00", dropouts=0, stalls=0, clicks=2)
    assert messages.render(take, "en").startswith("1.00s (original 1.00s)")
    assert messages.render("recorder said no", "ja") == "recorder said no"
    assert messages.render(None, "ko") == ""


def test_wire_round_trip_keeps_codes_and_rejects_unknown():
    m = msg("upload.not_audio")
    assert messages.from_wire(messages.to_wire(m)) == m
    assert messages.from_wire('@{"code": "nope"}') == '@{"code": "nope"}'
    assert messages.from_wire("plain reason") == "plain reason"


def test_api_errors_follow_the_request_language(client):
    bad = {"urls": ["https://example.com/x"]}
    ko = client.post("/api/add", json=bad, headers={"accept-language": "ko-KR"})
    ja = client.post("/api/add", json=bad, headers={"accept-language": "ja"})
    en = client.post("/api/add?lang=en", json=bad, headers={"accept-language": "ko"})
    assert ko.status_code == ja.status_code == en.status_code == 400
    assert ko.json()["detail"].startswith("수노 곡 주소가")
    assert ja.json()["detail"].startswith("Suno の曲")
    assert en.json() == {"detail": "Not a Suno song link: https://example.com/x", "code": "add.bad_url"}
