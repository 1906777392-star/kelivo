import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/api/chat_api_service.dart';
import 'package:Kelivo/core/services/api/providers/openai/chat_completions_api.dart';
import 'package:Kelivo/core/services/api/providers/openai/openai_vendor_compat.dart';
import 'package:Kelivo/core/utils/multimodal_input_utils.dart';

void main() {
  group('OpenAI current-turn visual media policy', () {
    test('historical user media is not encoded into a later request', () async {
      final dir = await Directory.systemTemp.createTemp('kelivo_old_media_');
      addTearDown(() async => dir.delete(recursive: true));
      final oldImage = File('${dir.path}/old.png');
      await oldImage.writeAsBytes(const [1, 2, 3, 4]);

      final messages = await buildOpenAIChatCompletionMessages(
        [
          {
            'role': 'user',
            'content': 'old turn',
            multimodalInternalMediaPathsKey: [oldImage.path],
          },
          {'role': 'assistant', 'content': 'noted'},
          {'role': 'user', 'content': 'new text-only turn'},
        ],
        canImageInput: true,
        allowRemoteImages: true,
        reasoningContentReplayPolicy: ReasoningContentReplayPolicy.none,
      );

      expect(jsonEncode(messages), isNot(contains('data:image/')));
      expect(messages.last['content'], 'new text-only turn');
    });

    test('latest user media survives a same-turn tool follow-up', () async {
      final dir = await Directory.systemTemp.createTemp('kelivo_now_media_');
      addTearDown(() async => dir.delete(recursive: true));
      final currentImage = File('${dir.path}/current.png');
      await currentImage.writeAsBytes(const [1, 2, 3, 4]);

      final messages = await buildOpenAIChatCompletionMessages(
        [
          {
            'role': 'user',
            'content': 'inspect this',
            multimodalInternalMediaPathsKey: [currentImage.path],
          },
          {
            'role': 'assistant',
            'content': 'checking',
            'tool_calls': [
              {
                'id': 'call_1',
                'type': 'function',
                'function': {'name': 'lookup', 'arguments': '{}'},
              },
            ],
          },
          {
            'role': 'tool',
            'tool_call_id': 'call_1',
            'name': 'lookup',
            'content': 'ok',
          },
        ],
        canImageInput: true,
        allowRemoteImages: true,
        reasoningContentReplayPolicy: ReasoningContentReplayPolicy.none,
      );

      final user = messages.firstWhere((message) => message['role'] == 'user');
      expect(user['content'], isA<List>());
      expect(jsonEncode(user), contains('data:image/png;base64,AQIDBA=='));
    });

    test('historical assistant structured images are removed', () async {
      final messages = await buildOpenAIChatCompletionMessages(
        const [
          {
            'role': 'assistant',
            'content': [
              {'type': 'text', 'text': 'generated'},
              {
                'type': 'image_url',
                'image_url': {'url': 'data:image/png;base64,OLD'},
              },
            ],
          },
          {'role': 'user', 'content': 'continue without an image'},
        ],
        canImageInput: true,
        allowRemoteImages: true,
        reasoningContentReplayPolicy: ReasoningContentReplayPolicy.none,
      );

      expect(jsonEncode(messages), isNot(contains('base64,OLD')));
      expect(messages.first['content'], isA<List>());
      expect(
        (messages.first['content'] as List).any(
          (part) => part is Map && part['type'] == 'image_url',
        ),
        isFalse,
      );
    });

    test('historical markdown image payload is replaced by a small marker', () async {
      final messages = await buildOpenAIChatCompletionMessages(
        const [
          {
            'role': 'assistant',
            'content': 'done ![image](data:image/png;base64,VERY_LARGE_PAYLOAD)',
          },
          {'role': 'user', 'content': 'next'},
        ],
        canImageInput: true,
        allowRemoteImages: true,
        reasoningContentReplayPolicy: ReasoningContentReplayPolicy.none,
      );

      expect(jsonEncode(messages), isNot(contains('VERY_LARGE_PAYLOAD')));
      expect(jsonEncode(messages), contains('historical image omitted'));
    });

    test('Responses API also omits historical media', () async {
      late Map<String, dynamic> requestBody;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async => server.close(force: true));
      server.listen((request) async {
        requestBody = (jsonDecode(await utf8.decoder.bind(request).join()) as Map)
            .cast<String, dynamic>();
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'id': 'resp_1',
            'output': [
              {
                'type': 'message',
                'role': 'assistant',
                'content': [
                  {'type': 'output_text', 'text': 'ok'},
                ],
              },
            ],
            'usage': {'input_tokens': 1, 'output_tokens': 1},
          }),
        );
        await request.response.close();
      });

      final dir = await Directory.systemTemp.createTemp('kelivo_resp_old_');
      addTearDown(() async => dir.delete(recursive: true));
      final oldImage = File('${dir.path}/old.png');
      await oldImage.writeAsBytes(const [1, 2, 3, 4]);

      final config = ProviderConfig(
        id: 'OpenAITest',
        enabled: true,
        name: 'OpenAITest',
        apiKey: 'test-key',
        baseUrl: 'http://${server.address.address}:${server.port}/v1',
        providerType: ProviderKind.openai,
        useResponseApi: true,
      );
      await ChatApiService.sendMessageStream(
        config: config,
        modelId: 'gpt-4.1',
        messages: [
          {
            'role': 'assistant',
            'content': 'old image',
            multimodalInternalMediaPathsKey: [oldImage.path],
          },
          {'role': 'user', 'content': 'new turn'},
        ],
        stream: false,
      ).toList();

      expect(jsonEncode(requestBody), isNot(contains('data:image/')));
      expect(jsonEncode(requestBody), contains('new turn'));
    });
  });
}
