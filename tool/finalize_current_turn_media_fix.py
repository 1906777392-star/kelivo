from pathlib import Path


def replace_required(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f"missing expected block: {label}")
    return text.replace(old, new)


chat_path = Path("lib/core/services/api/providers/openai/chat_completions_api.dart")
chat = chat_path.read_text()
chat = replace_required(
    chat,
    "  final pendingAssistantMediaUrls = <String>[];\n  final pendingAssistantVideoUrls = <String>{};\n",
    "",
    "pending assistant media declarations",
)
chat = replace_required(
    chat,
    "    const shouldAttachAssistantMedia = false;\n",
    "",
    "assistant media flag",
)
chat = replace_required(
    chat,
    """      final listHasEmbeddedMedia =
          canImageInput &&
          content is List &&
          content.any((part) {
            if (part is! Map) return false;
            final type = (part['type'] ?? '').toString();
            return type == 'image_url' || type == 'video_url';
          });
      if (canImageInput &&
          (hasInternalMedia ||
              hasAttachedImages ||
              shouldAttachAssistantMedia ||
              (isAssistant && listHasEmbeddedMedia))) {
""",
    """      if (canImageInput && (hasInternalMedia || hasAttachedImages)) {
""",
    "list content media gate",
)
chat = replace_required(
    chat,
    """        void stashOrAddImageUrl(String url) {
          if (url.isEmpty) return;
          if (!allowRemoteImages && isRemoteHttpUrl(url)) return;
          if (isAssistant) return;
          addImageUrl(url);
        }

        void stashOrAddVideoUrl(String url) {
          if (url.isEmpty) return;
          if (isAssistant) return;
          addVideoUrl(url);
        }

""",
    "",
    "list stash helpers",
)
chat = chat.replace("              if (isAssistant) stashOrAddImageUrl(url);\n", "")
chat = chat.replace("              if (isAssistant) stashOrAddVideoUrl(url);\n", "")
chat = chat.replace("stashOrAddVideoUrl(dataUrl);", "addVideoUrl(dataUrl);")
chat = chat.replace("stashOrAddImageUrl(dataUrl);", "addImageUrl(dataUrl);")
chat = replace_required(
    chat,
    """        if (shouldAttachAssistantMedia) {
          for (final url in pendingAssistantMediaUrls) {
            if (pendingAssistantVideoUrls.contains(url)) {
              addVideoUrl(url);
            } else {
              addImageUrl(url);
            }
          }
        }
""",
    "",
    "list assistant attach block",
)
chat = replace_required(
    chat,
    """    void stashOrAddImageUrl(String url) {
      if (url.isEmpty) return;
      if (!allowRemoteImages && isRemoteHttpUrl(url)) return;
      if (isAssistant) {
        if (!pendingAssistantMediaUrls.contains(url)) {
          pendingAssistantMediaUrls.add(url);
        }
        return;
      }
      addImageUrl(url);
    }

    void stashOrAddVideoUrl(String url) {
      if (url.isEmpty) return;
      if (isAssistant) {
        if (!pendingAssistantMediaUrls.contains(url)) {
          pendingAssistantMediaUrls.add(url);
        }
        pendingAssistantVideoUrls.add(url);
        return;
      }
      addVideoUrl(url);
    }

""",
    "",
    "string content stash helpers",
)
chat = chat.replace("stashOrAddImageUrl(url);", "addImageUrl(url);")
chat = replace_required(
    chat,
    """    // Attach stashed assistant media to the last user message.
    if (shouldAttachAssistantMedia) {
      for (final url in pendingAssistantMediaUrls) {
        if (pendingAssistantVideoUrls.contains(url)) {
          addVideoUrl(url);
        } else {
          addImageUrl(url);
        }
      }
    }
""",
    "",
    "string content assistant attach block",
)
chat = chat.replace("        !shouldAttachAssistantMedia) {", "        true) {")
chat_path.write_text(chat)

provider_path = Path("lib/core/services/api/providers/openai/openai_provider.dart")
provider = provider_path.read_text()
provider = replace_required(
    provider,
    """    // Collect assistant images to attach to the last user message.
    // Use last *user* index so tool follow-ups still receive stashed media.
    final List<String> lastAssistantImageUrls = <String>[];
""",
    "",
    "responses assistant image declarations",
)
provider = replace_required(
    provider,
    """      // For the last user message, also attach the last assistant image if available
      const shouldAttachAssistantImage = false;

""",
    "",
    "responses assistant image flag",
)
provider = replace_required(
    provider,
    """      if (hasMarkdownImages ||
          hasAttachedImages ||
          hasInternalMedia ||
          shouldAttachAssistantImage) {
""",
    """      if (hasMarkdownImages || hasAttachedImages || hasInternalMedia) {
""",
    "responses media gate",
)
provider = replace_required(
    provider,
    """          // For assistant messages, collect images; for user messages, add directly
          if (isAssistant) {
            if (!lastAssistantImageUrls.contains(url)) {
              lastAssistantImageUrls.add(url);
            }
          } else {
            addImage(url);
          }
""",
    """          addImage(url);
""",
    "responses parsed image replay",
)
provider = replace_required(
    provider,
    """          // Assistant Responses messages may only contain output_text/refusal.
          // Mirror the markdown path: stash for the following user turn.
          if (isAssistant) {
            if (!lastAssistantImageUrls.contains(dataUrl)) {
              lastAssistantImageUrls.add(dataUrl);
            }
          } else {
            addImage(dataUrl);
          }
""",
    """          addImage(dataUrl);
""",
    "responses supplemental image replay",
)
provider = replace_required(
    provider,
    """        // Attach all stashed assistant images to the last user message
        if (shouldAttachAssistantImage) {
          for (final url in lastAssistantImageUrls) {
            addImage(url);
          }
        }
""",
    "",
    "responses assistant image attach block",
)
provider_path.write_text(provider)
