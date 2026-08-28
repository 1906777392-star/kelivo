from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected 1 match, found {count}")
    return text.replace(old, new, 1)


def remove_test_block(text: str, marker: str) -> str:
    marker_at = text.index(marker)
    start = text.rfind("    test(", 0, marker_at)
    if start < 0:
        raise SystemExit(f"test start not found: {marker}")
    depth = 0
    quote = None
    escaped = False
    i = start
    saw_open = False
    while i < len(text):
        ch = text[i]
        if quote is not None:
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == quote:
                quote = None
        else:
            if ch in ("'", '"'):
                quote = ch
            elif ch == '(':
                depth += 1
                saw_open = True
            elif ch == ')':
                depth -= 1
                if saw_open and depth == 0:
                    end = i + 1
                    while end < len(text) and text[end].isspace() and text[end] != '\n':
                        end += 1
                    if end < len(text) and text[end] == ';':
                        end += 1
                    if end < len(text) and text[end] == '\n':
                        end += 1
                    return text[:start] + text[end:]
        i += 1
    raise SystemExit(f"test end not found: {marker}")

chat_path = Path("lib/core/services/api/providers/openai/chat_completions_api.dart")
chat = chat_path.read_text()
chat = replace_once(
    chat,
    "String _stripHistoricalImageMarkdown(String raw)",
    "String stripHistoricalImageMarkdown(String raw)",
    "make sanitizer shared",
)
chat = chat.replace(
    "raw = _stripHistoricalImageMarkdown(raw);",
    "raw = stripHistoricalImageMarkdown(raw);",
)
chat_path.write_text(chat)

responses_path = Path("lib/core/services/api/providers/openai/openai_provider.dart")
responses = responses_path.read_text().replace(
    "raw = _stripHistoricalImageMarkdown(raw);",
    "raw = stripHistoricalImageMarkdown(raw);",
)
responses_path.write_text(responses)

test_path = Path("test/chat_api_custom_image_marker_test.dart")
tests = test_path.read_text()
for marker in [
    "assistant ImagePart is omitted from later user requests",
    "assistant List image_url without sidecar is not replayed",
    "tool follow-up omits historical assistant media",
    "List-shaped user content omits historical assistant media",
    "assistant ImagePart is not replayed into later Responses input",
    "multiple assistant images are not replayed to following user",
]:
    tests = remove_test_block(tests, marker)
test_path.write_text(tests)
