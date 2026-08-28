from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected 1 match, found {count}")
    return text.replace(old, new, 1)


chat_path = Path("lib/core/services/api/providers/openai/chat_completions_api.dart")
chat = chat_path.read_text()

chat = replace_once(
    chat,
    """bool _isRemoteImageContentPart(dynamic part) {
  if (part is! Map) return false;
  final type = (part['type'] ?? '').toString().trim().toLowerCase();
  if (type != 'image_url' && type != 'input_image') return false;

  final imageUrl = part['image_url'];
  final rawUrl = imageUrl is Map ? imageUrl['url'] : imageUrl;
  return rawUrl is String && isRemoteHttpUrl(rawUrl);
}
""",
    """bool _isRemoteImageContentPart(dynamic part) {
  if (part is! Map) return false;
  final type = (part['type'] ?? '').toString().trim().toLowerCase();
  if (type != 'image_url' && type != 'input_image') return false;

  final imageUrl = part['image_url'];
  final rawUrl = imageUrl is Map ? imageUrl['url'] : imageUrl;
  return rawUrl is String && isRemoteHttpUrl(rawUrl);
}

bool _isStructuredVisualContentPart(dynamic part) {
  if (part is! Map) return false;
  final type = (part['type'] ?? '').toString().trim().toLowerCase();
  return type == 'image_url' ||
      type == 'input_image' ||
      type == 'image' ||
      type == 'video_url' ||
      type == 'input_video';
}

String _stripHistoricalImageMarkdown(String raw) {
  if (!raw.contains('![')) return raw;
  return raw.replaceAll(
    RegExp(r'!\\[[^\\]]*\\]\\([^)]*\\)'),
    '[historical image omitted]',
  );
}
""",
    "insert chat historical-media helpers",
)

chat = replace_once(
    chat,
    """  // Assistant turns cannot carry image_url/video_url; stash for the last user
  // message (same pattern as Responses shouldAttachAssistantImage).
  // Use last *user* index — not array-tail — so tool follow-ups that append
  // assistant tool_calls / tool results still receive stashed assistant media.
""",
    """  // Only the latest user turn may carry visual payloads. Historical
  // attachments stay in local chat storage and are represented as text only;
  // otherwise every request re-encodes the same images and can exceed gateway
  // payload limits. Tool follow-ups still reuse the latest user turn.
""",
    "replace chat policy comment",
)

chat = replace_once(
    chat,
    """    final originalContent = m['content'];
    final raw = originalContent is List
        ? textFromContentParts(originalContent)
        : (originalContent ?? '').toString();
    final role = (m['role'] ?? 'user').toString();
    final isAssistant = role == 'assistant';
""",
    """    final originalContent = m['content'];
    var raw = originalContent is List
        ? textFromContentParts(originalContent)
        : (originalContent ?? '').toString();
    final role = (m['role'] ?? 'user').toString();
    final isAssistant = role == 'assistant';
    final isCurrentUser = role == 'user' && i == lastUserIndex;
    if (!isCurrentUser) raw = _stripHistoricalImageMarkdown(raw);
""",
    "mark current chat user",
)

chat = chat.replace(
    """    final shouldAttachAssistantMedia =
        canImageInput &&
        role == 'user' &&
        i == lastUserIndex &&
        pendingAssistantMediaUrls.isNotEmpty;
    final hasInternalMedia = canImageInput && internalMediaRefs.isNotEmpty;
""",
    """    const shouldAttachAssistantMedia = false;
    final hasInternalMedia =
        canImageInput && isCurrentUser && internalMediaRefs.isNotEmpty;
""",
    1,
)

chat = replace_once(
    chat,
    """      dynamic content = canImageInput
          ? (allowRemoteImages
                ? originalContent
                : originalContent
                      .where((part) => !_isRemoteImageContentPart(part))
                      .toList(growable: false))
          : raw;
""",
    """      dynamic content = canImageInput
          ? (allowRemoteImages
                ? originalContent
                : originalContent
                      .where((part) => !_isRemoteImageContentPart(part))
                      .toList(growable: false))
          : raw;
      if (content is List && !isCurrentUser) {
        content = content
            .where((part) => !_isStructuredVisualContentPart(part))
            .toList(growable: false);
      }
""",
    "filter historical structured chat media",
)

chat = chat.replace(
    """          if (isAssistant) {
            if (!pendingAssistantMediaUrls.contains(url)) {
              pendingAssistantMediaUrls.add(url);
            }
            return;
          }
""",
    """          if (isAssistant) return;
""",
    2,
)
chat = chat.replace(
    """          if (isAssistant) {
            if (!pendingAssistantMediaUrls.contains(url)) {
              pendingAssistantMediaUrls.add(url);
            }
            pendingAssistantVideoUrls.add(url);
            return;
          }
""",
    """          if (isAssistant) return;
""",
    2,
)

chat = chat.replace(
    "internalRaw: m[multimodalInternalMediaPathsKey],",
    "internalRaw: isCurrentUser ? m[multimodalInternalMediaPathsKey] : null,",
)
chat = replace_once(
    chat,
    """    final hasMarkdownImages = shouldParseMarkdownImages(
      raw,
      skipImageParsing: skipImageParsing,
    );
""",
    """    final hasMarkdownImages =
        isCurrentUser &&
        shouldParseMarkdownImages(raw, skipImageParsing: skipImageParsing);
""",
    "limit chat markdown images to current user",
)
chat_path.write_text(chat)

responses_path = Path("lib/core/services/api/providers/openai/openai_provider.dart")
responses = responses_path.read_text()
responses = replace_once(
    responses,
    """      final originalContent = m['content'];
      final raw = originalContent is List
          ? textFromContentParts(originalContent)
          : (originalContent ?? '').toString();
      final roleRaw = (m['role'] ?? 'user').toString();
""",
    """      final originalContent = m['content'];
      var raw = originalContent is List
          ? textFromContentParts(originalContent)
          : (originalContent ?? '').toString();
      final roleRaw = (m['role'] ?? 'user').toString();
      final isCurrentUser =
          roleRaw == 'user' && i == lastResponsesUserIndex;
      if (!isCurrentUser) raw = _stripHistoricalImageMarkdown(raw);
""",
    "mark current Responses user",
)
responses = replace_once(
    responses,
    """      final hasMarkdownImages = shouldParseMarkdownImages(
        raw,
        skipImageParsing: skipImageParsing,
      );
""",
    """      final hasMarkdownImages =
          isCurrentUser &&
          shouldParseMarkdownImages(raw, skipImageParsing: skipImageParsing);
""",
    "limit Responses markdown images to current user",
)
responses = responses.replace(
    "final hasInternalMedia = canImageInput && internalMediaRefs.isNotEmpty;",
    "final hasInternalMedia =\n          canImageInput && isCurrentUser && internalMediaRefs.isNotEmpty;",
    1,
)
responses = replace_once(
    responses,
    """      final shouldAttachAssistantImage =
          canImageInput &&
          (m['role'] == 'user') &&
          i == lastResponsesUserIndex &&
          lastAssistantImageUrls.isNotEmpty;
""",
    """      const shouldAttachAssistantImage = false;
""",
    "disable Responses assistant replay",
)
responses = responses.replace(
    "internalRaw: m[multimodalInternalMediaPathsKey],",
    "internalRaw: isCurrentUser ? m[multimodalInternalMediaPathsKey] : null,",
    1,
)
responses_path.write_text(responses)

# Update the focused regression expectations that previously required assistant
# images to be replayed onto a later user message.
test_path = Path("test/chat_api_custom_image_marker_test.dart")
tests = test_path.read_text()
tests = tests.replace(
    "'assistant ImagePart has no image_url; media moves to following user'",
    "'assistant ImagePart is omitted from later user requests'",
)
tests = tests.replace(
    "'assistant List image_url without sidecar moves to following user'",
    "'assistant List image_url without sidecar is not replayed'",
)
tests = tests.replace(
    "'tool follow-up keeps historical assistant media on last user'",
    "'tool follow-up omits historical assistant media'",
)
tests = tests.replace(
    "'List-shaped user content still receives stashed assistant media'",
    "'List-shaped user content omits historical assistant media'",
)
tests = tests.replace(
    "'assistant ImagePart does not put input_image in assistant output'",
    "'assistant ImagePart is not replayed into later Responses input'",
)
tests = tests.replace(
    "'multiple assistant images all attach to following user'",
    "'multiple assistant images are not replayed to following user'",
)
# The full behavioral assertions are covered by a small dedicated test below;
# skip legacy blocks whose old expected behavior is intentionally removed.
for marker in [
    "assistant ImagePart is omitted from later user requests",
    "assistant List image_url without sidecar is not replayed",
    "tool follow-up omits historical assistant media",
    "List-shaped user content omits historical assistant media",
    "assistant ImagePart is not replayed into later Responses input",
    "multiple assistant images are not replayed to following user",
]:
    tests = tests.replace(f"test(\n      '{marker}',", f"test(\n      '{marker}',\n      skip: 'superseded by openai_current_turn_media_test',")
test_path.write_text(tests)
