import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/api/chat_api_service.dart';
import 'package:Kelivo/core/utils/multimodal_input_utils.dart';

ProviderConfig _openAiConfig(String baseUrl, {bool useResponseApi = false}) {
  return ProviderConfig(
    id: 'OpenAITest',
    enabled: true,
    name: 'OpenAITest',
    apiKey: 'test-key',
    baseUrl: baseUrl,
    providerType: ProviderKind.openai,
    useResponseApi: useResponseApi,
  );
}

Future<Map<String, dynamic>> _sendAndCaptureRequestBody(
  Future<List<dynamic>> Function(String baseUrl) sendRequest,
) async {
  Map<String, dynamic>? requestBody;
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final baseUrl = 'http://${server.address.address}:${server.port}/v1';

  try {
    server.listen((request) async {
      final rawBody = await utf8.decoder.bind(request).join();
      requestBody = (jsonDecode(rawBody) as Map).cast<String, dynamic>();
      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'id': 'chatcmpl-1',
          'object': 'chat.completion',
          'choices': [
            {
              'index': 0,
              'message': {'role': 'assistant', 'content': 'ok'},
              'finish_reason': 'stop',
            },
          ],
          'usage': {
            'prompt_tokens': 1,
            'completion_tokens': 1,
            'total_tokens': 2,
          },
        }),
      );
      await request.response.close();
    });

    await sendRequest(baseUrl);
  } finally {
    await server.close(force: true);
  }

  final captured = requestBody;
  if (captured == null) {
    fail('expected request body to be captured');
  }
  return captured;
}

ProviderConfig _claudeConfig(String baseUrl) {
  return ProviderConfig(
    id: 'ClaudeStructuredMediaTest',
    enabled: true,
    name: 'ClaudeStructuredMediaTest',
    apiKey: 'test-key',
    baseUrl: baseUrl,
    providerType: ProviderKind.claude,
  );
}

ProviderConfig _geminiConfig(String baseUrl) {
  return ProviderConfig(
    id: 'GeminiStructuredMediaTest',
    enabled: true,
    name: 'GeminiStructuredMediaTest',
    apiKey: 'test-key',
    baseUrl: baseUrl,
    providerType: ProviderKind.google,
  );
}

Future<File> _tempPng(String prefix) async {
  final dir = await Directory.systemTemp.createTemp(prefix);
  final file = File('${dir.path}/sample.png');
  await file.writeAsBytes(const [1, 2, 3, 4]);
  return file;
}

Future<Map<String, dynamic>> _captureProviderBody(
  Future<List<dynamic>> Function(String baseUrl) sendRequest, {
  required Map<String, dynamic> responseBody,
  String basePath = '',
}) async {
  Map<String, dynamic>? requestBody;
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final baseUrl = 'http://${server.address.address}:${server.port}$basePath';

  try {
    server.listen((request) async {
      requestBody = (jsonDecode(await utf8.decoder.bind(request).join()) as Map)
          .cast<String, dynamic>();
      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(responseBody));
      await request.response.close();
    });
    await sendRequest(baseUrl);
  } finally {
    await server.close(force: true);
  }

  final captured = requestBody;
  if (captured == null) {
    fail('expected request body to be captured');
  }
  return captured;
}

List<Map<String, dynamic>> _extractSingleMessageParts(
  Map<String, dynamic> body,
) {
  final messages = (body['messages'] as List).cast<Map>();
  final content = messages.single['content'];
  expect(content, isA<List>());
  return (content as List).cast<Map<String, dynamic>>();
}

Future<Map<String, dynamic>> _sendAndCaptureResponsesBody(
  Future<List<dynamic>> Function(String baseUrl) sendRequest,
) async {
  Map<String, dynamic>? requestBody;
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final baseUrl = 'http://${server.address.address}:${server.port}/v1';

  try {
    final future = sendRequest(baseUrl);
    final request = await server.first;
    requestBody =
        jsonDecode(await utf8.decoder.bind(request).join())
            as Map<String, dynamic>;
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
    await future;
  } finally {
    await server.close(force: true);
  }

  return requestBody;
}

void main() {
  group('ChatApiService structured media paths (no custom markers)', () {
    test('encodes local media paths as data URLs', () async {
      final body = await _sendAndCaptureRequestBody((baseUrl) async {
        final dir = await Directory.systemTemp.createTemp('kelivo_local_img_');
        addTearDown(() async {
          if (await dir.exists()) {
            await dir.delete(recursive: true);
          }
        });

        final file = File('${dir.path}/sample.png');
        await file.writeAsBytes(const [1, 2, 3, 4]);

        return ChatApiService.sendMessageStream(
          config: _openAiConfig(baseUrl),
          modelId: 'gpt-4.1',
          messages: [
            {
              'role': 'user',
              'content': 'before after',
              multimodalInternalMediaPathsKey: [file.path],
            },
          ],
          stream: false,
        ).toList();
      });

      final parts = _extractSingleMessageParts(body);
      expect(parts, hasLength(2));
      expect(parts.first['type'], 'text');
      expect(parts.first['text'], 'before after');
      expect(parts.last['type'], 'image_url');
      expect(
        (parts.last['image_url'] as Map<String, dynamic>)['url'] as String,
        'data:image/png;base64,AQIDBA==',
      );
    });

    test('literal [image:...] text is not treated as an attachment', () async {
      final body = await _sendAndCaptureRequestBody((baseUrl) async {
        return ChatApiService.sendMessageStream(
          config: _openAiConfig(baseUrl),
          modelId: 'gpt-4.1',
          messages: const [
            {
              'role': 'user',
              'content': 'inline [image:data:image/png;base64,QUJD]',
            },
          ],
          stream: false,
        ).toList();
      });

      final messages = (body['messages'] as List).cast<Map>();
      final content = messages.single['content'];
      final text = content is List ? (content.single as Map)['text'] : content;
      expect(text, 'inline [image:data:image/png;base64,QUJD]');
      if (content is List) {
        expect(
          content.any((part) => (part as Map)['type'] == 'image_url'),
          isFalse,
        );
      }
    });

    test('markdown images are still parsed for image-capable models', () async {
      final body = await _sendAndCaptureRequestBody((baseUrl) async {
        return ChatApiService.sendMessageStream(
          config: _openAiConfig(baseUrl),
          modelId: 'gpt-4.1',
          messages: const [
            {
              'role': 'user',
              'content': 'look ![x](data:image/png;base64,QUJD)',
            },
          ],
          stream: false,
        ).toList();
      });

      final parts = _extractSingleMessageParts(body);
      expect(parts.any((part) => part['type'] == 'image_url'), isTrue);
    });

    test(
      'userImagePaths attach images without marker strings in content',
      () async {
        final dir = await Directory.systemTemp.createTemp('kelivo_user_paths_');
        addTearDown(() async {
          if (await dir.exists()) await dir.delete(recursive: true);
        });
        final file = File('${dir.path}/tool.png');
        await file.writeAsBytes(const [1, 2, 3, 4]);

        final body = await _sendAndCaptureRequestBody((baseUrl) async {
          return ChatApiService.sendMessageStream(
            config: _openAiConfig(baseUrl),
            modelId: 'gpt-4.1',
            messages: [
              {'role': 'user', 'content': 'inspect'},
            ],
            userImagePaths: [file.path],
            stream: false,
          ).toList();
        });

        final parts = _extractSingleMessageParts(body);
        expect(parts.first['text'], 'inspect');
        expect(parts.last['type'], 'image_url');
        expect(jsonEncode(body), isNot(contains('[image:')));
      },
    );

    test(
      'tool follow-up preserves structured media paths on rebuilt user message',
      () async {
        final dir = await Directory.systemTemp.createTemp('kelivo_tool_media_');
        addTearDown(() async {
          if (await dir.exists()) await dir.delete(recursive: true);
        });
        final file = File('${dir.path}/sample.png');
        await file.writeAsBytes(const [1, 2, 3, 4]);

        final requestBodies = <Map<String, dynamic>>[];
        var requestCount = 0;
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() async {
          await server.close(force: true);
        });

        server.listen((request) async {
          requestCount += 1;
          final raw = await utf8.decoder.bind(request).join();
          requestBodies.add((jsonDecode(raw) as Map).cast<String, dynamic>());

          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentType = ContentType(
            'text',
            'event-stream',
            charset: 'utf-8',
          );

          if (requestCount == 1) {
            request.response.write(
              'data: ${jsonEncode({
                'id': 'cmpl-1',
                'object': 'chat.completion.chunk',
                'choices': [
                  {
                    'index': 0,
                    'delta': {
                      'role': 'assistant',
                      'content': 'checking',
                      'tool_calls': [
                        {
                          'index': 0,
                          'id': 'call_media_1',
                          'type': 'function',
                          'function': {'name': 'lookup', 'arguments': '{}'},
                        },
                      ],
                    },
                    'finish_reason': 'tool_calls',
                  },
                ],
              })}\n\n',
            );
          } else {
            request.response.write(
              'data: ${jsonEncode({
                'id': 'cmpl-2',
                'object': 'chat.completion.chunk',
                'choices': [
                  {
                    'index': 0,
                    'delta': {'role': 'assistant', 'content': 'done'},
                    'finish_reason': 'stop',
                  },
                ],
              })}\n\n',
            );
          }
          request.response.write('data: [DONE]\n\n');
          await request.response.close();
        });

        final baseUrl = 'http://${server.address.address}:${server.port}/v1';
        await ChatApiService.sendMessageStream(
          config: _openAiConfig(baseUrl),
          modelId: 'gpt-4.1',
          messages: [
            {
              'role': 'user',
              'content': 'describe this',
              multimodalInternalMediaPathsKey: [
                {'uri': file.path, 'mime': 'image/png'},
              ],
            },
          ],
          tools: const [
            {
              'type': 'function',
              'function': {
                'name': 'lookup',
                'description': 'Lookup helper',
                'parameters': {
                  'type': 'object',
                  'properties': <String, dynamic>{},
                },
              },
            },
          ],
          onToolCall: (_, __, {toolCallId}) async => 'ok',
        ).toList();

        expect(requestBodies, hasLength(2));

        final secondMessages = (requestBodies[1]['messages'] as List)
            .cast<Map>();
        final userMsg = secondMessages.firstWhere((m) => m['role'] == 'user');
        // User is not last after tool follow-up, so userImagePaths alone
        // would not re-attach. Structured refs must survive copy+rebuild.
        expect(userMsg['content'], isA<List>());
        final parts = (userMsg['content'] as List).cast<Map<String, dynamic>>();
        expect(
          parts.any((part) => part['type'] == 'image_url'),
          isTrue,
          reason:
              'second request rebuilt user message must keep image_url from '
              '_kelivo_media_paths',
        );
        expect(
          parts.any(
            (part) =>
                part['type'] == 'image_url' &&
                ((part['image_url'] as Map)['url'] as String).startsWith(
                  'data:image/png;base64,',
                ),
          ),
          isTrue,
        );
      },
    );

    test('tool follow-up keeps bare userImagePaths on last user', () async {
      final dir = await Directory.systemTemp.createTemp(
        'kelivo_tool_user_paths_',
      );
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });
      final file = File('${dir.path}/user.png');
      await file.writeAsBytes(const [1, 2, 3, 4]);

      final requestBodies = <Map<String, dynamic>>[];
      var requestCount = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });

      server.listen((request) async {
        requestCount += 1;
        final raw = await utf8.decoder.bind(request).join();
        requestBodies.add((jsonDecode(raw) as Map).cast<String, dynamic>());

        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
          charset: 'utf-8',
        );

        if (requestCount == 1) {
          request.response.write(
            'data: ${jsonEncode({
              'id': 'cmpl-1',
              'object': 'chat.completion.chunk',
              'choices': [
                {
                  'index': 0,
                  'delta': {
                    'role': 'assistant',
                    'content': 'checking',
                    'tool_calls': [
                      {
                        'index': 0,
                        'id': 'call_user_paths_1',
                        'type': 'function',
                        'function': {'name': 'lookup', 'arguments': '{}'},
                      },
                    ],
                  },
                  'finish_reason': 'tool_calls',
                },
              ],
            })}\n\n',
          );
        } else {
          request.response.write(
            'data: ${jsonEncode({
              'id': 'cmpl-2',
              'object': 'chat.completion.chunk',
              'choices': [
                {
                  'index': 0,
                  'delta': {'role': 'assistant', 'content': 'done'},
                  'finish_reason': 'stop',
                },
              ],
            })}\n\n',
          );
        }
        request.response.write('data: [DONE]\n\n');
        await request.response.close();
      });

      final baseUrl = 'http://${server.address.address}:${server.port}/v1';
      await ChatApiService.sendMessageStream(
        config: _openAiConfig(baseUrl),
        modelId: 'gpt-4.1',
        messages: [
          {'role': 'user', 'content': 'inspect this'},
        ],
        userImagePaths: [file.path],
        tools: const [
          {
            'type': 'function',
            'function': {
              'name': 'lookup',
              'description': 'Lookup helper',
              'parameters': {
                'type': 'object',
                'properties': <String, dynamic>{},
              },
            },
          },
        ],
        onToolCall: (_, __, {toolCallId}) async => 'ok',
      ).toList();

      expect(requestBodies, hasLength(2));
      final secondMessages = (requestBodies[1]['messages'] as List).cast<Map>();
      final userMsg = secondMessages.firstWhere((m) => m['role'] == 'user');
      expect(userMsg['content'], isA<List>());
      final parts = (userMsg['content'] as List).cast<Map<String, dynamic>>();
      expect(
        parts.any((part) => part['type'] == 'image_url'),
        isTrue,
        reason:
            'bare userImagePaths must survive tool follow-up even when the '
            'user message is no longer array-tail and has no structured refs',
      );
    });
  });

  group('ChatApiService Responses API structured media paths', () {
    test('local video/mp4 is not encoded as input_image', () async {
      final body = await _sendAndCaptureResponsesBody((baseUrl) async {
        final dir = await Directory.systemTemp.createTemp('kelivo_resp_vid_');
        addTearDown(() async {
          if (await dir.exists()) {
            await dir.delete(recursive: true);
          }
        });
        final file = File('${dir.path}/clip.mp4');
        await file.writeAsBytes(const [1, 2, 3, 4]);

        return ChatApiService.sendMessageStream(
          config: _openAiConfig(baseUrl, useResponseApi: true),
          modelId: 'gpt-4.1',
          messages: [
            {
              'role': 'user',
              'content': 'watch this',
              multimodalInternalMediaPathsKey: [
                {'uri': file.path, 'mime': 'video/mp4'},
              ],
            },
          ],
          stream: false,
        ).toList();
      });

      final encoded = jsonEncode(body);
      expect(encoded, isNot(contains('"type":"input_image"')));
      final input = (body['input'] as List).cast<Map>();
      final content = input.single['content'];
      if (content is List) {
        expect(
          content.any((part) => (part as Map)['type'] == 'input_image'),
          isFalse,
        );
      }
    });

    test('pure local video attachment keeps non-empty text content', () async {
      late final String videoPath;
      final body = await _sendAndCaptureResponsesBody((baseUrl) async {
        final dir = await Directory.systemTemp.createTemp(
          'kelivo_resp_pure_vid_',
        );
        addTearDown(() async {
          if (await dir.exists()) {
            await dir.delete(recursive: true);
          }
        });
        final file = File('${dir.path}/clip.mp4');
        await file.writeAsBytes(const [1, 2, 3, 4]);
        videoPath = file.path;

        return ChatApiService.sendMessageStream(
          config: _openAiConfig(baseUrl, useResponseApi: true),
          modelId: 'gpt-4.1',
          messages: [
            {
              'role': 'user',
              'content': '',
              multimodalInternalMediaPathsKey: [
                {'uri': file.path, 'mime': 'video/mp4'},
              ],
            },
          ],
          stream: false,
        ).toList();
      });

      final encoded = jsonEncode(body);
      expect(encoded, isNot(contains('"type":"input_image"')));
      final input = (body['input'] as List).cast<Map>();
      final content = input.single['content'];
      expect(content, isA<List>());
      final parts = (content as List).cast<Map<String, dynamic>>();
      expect(parts, isNotEmpty, reason: 'pure video must not emit content: []');
      expect(parts.any((part) => part['type'] == 'input_image'), isFalse);
      expect(
        parts.any(
          (part) => part['type'] == 'input_text' && part['text'] == videoPath,
        ),
        isTrue,
      );
    });

    test('remote video URL stays as text, not input_image', () async {
      final body = await _sendAndCaptureResponsesBody((baseUrl) async {
        return ChatApiService.sendMessageStream(
          config: _openAiConfig(baseUrl, useResponseApi: true),
          modelId: 'gpt-4.1',
          messages: [
            {
              'role': 'user',
              'content': 'watch this',
              multimodalInternalMediaPathsKey: const [
                {'uri': 'https://example.com/clip.mp4', 'mime': 'video/mp4'},
              ],
            },
          ],
          stream: false,
        ).toList();
      });

      final input = (body['input'] as List).cast<Map>();
      final content = input.single['content'];
      expect(content, isA<List>());
      final parts = (content as List).cast<Map<String, dynamic>>();
      expect(parts.any((part) => part['type'] == 'input_image'), isFalse);
      expect(
        parts.any(
          (part) =>
              part['type'] == 'input_text' &&
              part['text'] == 'https://example.com/clip.mp4',
        ),
        isTrue,
      );
    });

    test('encodes multimodalInternalMediaPathsKey as input_image', () async {
      final body = await _sendAndCaptureResponsesBody((baseUrl) async {
        final dir = await Directory.systemTemp.createTemp('kelivo_resp_img_');
        addTearDown(() async {
          if (await dir.exists()) {
            await dir.delete(recursive: true);
          }
        });
        final file = File('${dir.path}/sample.png');
        await file.writeAsBytes(const [1, 2, 3, 4]);

        return ChatApiService.sendMessageStream(
          config: _openAiConfig(baseUrl, useResponseApi: true),
          modelId: 'gpt-4.1',
          messages: [
            {
              'role': 'user',
              'content': 'before after',
              multimodalInternalMediaPathsKey: [file.path],
            },
          ],
          stream: false,
        ).toList();
      });

      final input = (body['input'] as List).cast<Map>();
      final content = input.single['content'];
      expect(content, isA<List>());
      final parts = (content as List).cast<Map<String, dynamic>>();
      expect(parts.any((part) => part['type'] == 'input_image'), isTrue);
      expect(jsonEncode(body), isNot(contains('[image:')));
    });

    test('literal [image:...] text is not treated as an attachment', () async {
      final body = await _sendAndCaptureResponsesBody((baseUrl) async {
        return ChatApiService.sendMessageStream(
          config: _openAiConfig(baseUrl, useResponseApi: true),
          modelId: 'gpt-4.1',
          messages: const [
            {
              'role': 'user',
              'content': 'inline [image:data:image/png;base64,QUJD]',
            },
          ],
          stream: false,
        ).toList();
      });

      final input = (body['input'] as List).cast<Map>();
      final content = input.single['content'];
      final encoded = jsonEncode(body);
      expect(encoded, contains('inline [image:data:image/png;base64,QUJD]'));
      expect(encoded, isNot(contains('"type":"input_image"')));
      if (content is List) {
        expect(
          content.any((part) => (part as Map)['type'] == 'input_image'),
          isFalse,
        );
      }
    });

    test(
      'remote structured media stays as text when allowRemoteImages is false',
      () async {
        final body = await _sendAndCaptureRequestBody((baseUrl) async {
          return ChatApiService.sendMessageStream(
            config: _openAiConfig(baseUrl),
            modelId: 'moonshotai/kimi-k3',
            messages: [
              {
                'role': 'user',
                'content': 'describe this',
                multimodalInternalMediaPathsKey: [
                  encodeInternalMediaRef(
                    uri: 'https://example.com/remote-structured.png',
                    mime: 'image/png',
                  ),
                ],
              },
            ],
            stream: false,
          ).toList();
        });

        final parts = _extractSingleMessageParts(body);
        expect(
          parts.any(
            (part) =>
                part['type'] == 'text' &&
                part['text'] == 'https://example.com/remote-structured.png',
          ),
          isTrue,
        );
        expect(parts.any((part) => part['type'] == 'image_url'), isFalse);
        expect(
          jsonEncode(body),
          contains('https://example.com/remote-structured.png'),
        );
      },
    );
  });

  group('Claude structured media paths (ticket 10)', () {
    test(
      'encodes multimodalInternalMediaPathsKey as Anthropic image blocks',
      () async {
        final file = await _tempPng('kelivo_claude_media_');
        addTearDown(() async {
          final dir = file.parent;
          if (await dir.exists()) await dir.delete(recursive: true);
        });

        final body = await _captureProviderBody(
          (baseUrl) {
            return ChatApiService.sendMessageStream(
              config: _claudeConfig(baseUrl),
              modelId: 'claude-sonnet-4-6',
              messages: [
                {
                  'role': 'user',
                  'content': 'before after',
                  multimodalInternalMediaPathsKey: [file.path],
                },
              ],
              stream: false,
            ).toList();
          },
          responseBody: const <String, dynamic>{
            'id': 'msg_1',
            'content': [
              {'type': 'text', 'text': 'ok'},
            ],
            'usage': {'input_tokens': 1, 'output_tokens': 1},
          },
        );

        final messages = (body['messages'] as List).cast<Map>();
        final parts = (messages.single['content'] as List).cast<Map>();
        expect(parts.first['type'], 'text');
        expect(parts.first['text'], 'before after');
        expect(parts.last['type'], 'image');
        expect(parts.last['source']['type'], 'base64');
        expect(parts.last['source']['media_type'], 'image/png');
        expect(parts.last['source']['data'], 'AQIDBA==');
        expect(jsonEncode(body), isNot(contains('[image:')));
        expect(
          jsonEncode(body),
          isNot(contains(multimodalInternalMediaPathsKey)),
        );
      },
    );

    test('literal [image:...] text is not treated as an attachment', () async {
      final body = await _captureProviderBody(
        (baseUrl) {
          return ChatApiService.sendMessageStream(
            config: _claudeConfig(baseUrl),
            modelId: 'claude-sonnet-4-6',
            messages: const [
              {
                'role': 'user',
                'content': 'inline [image:data:image/png;base64,QUJD]',
              },
            ],
            stream: false,
          ).toList();
        },
        responseBody: const <String, dynamic>{
          'id': 'msg_1',
          'content': [
            {'type': 'text', 'text': 'ok'},
          ],
          'usage': {'input_tokens': 1, 'output_tokens': 1},
        },
      );

      final messages = (body['messages'] as List).cast<Map>();
      final content = messages.single['content'];
      expect(content, 'inline [image:data:image/png;base64,QUJD]');
      expect(jsonEncode(body), isNot(contains('"type":"image"')));
    });

    test('skips missing local media paths without crashing', () async {
      final missing =
          '${Directory.systemTemp.path}/kelivo_missing_claude_${DateTime.now().microsecondsSinceEpoch}.png';
      final body = await _captureProviderBody(
        (baseUrl) {
          return ChatApiService.sendMessageStream(
            config: _claudeConfig(baseUrl),
            modelId: 'claude-sonnet-4-6',
            messages: [
              {
                'role': 'user',
                'content': 'still send me',
                multimodalInternalMediaPathsKey: [missing],
              },
            ],
            stream: false,
          ).toList();
        },
        responseBody: const <String, dynamic>{
          'id': 'msg_1',
          'content': [
            {'type': 'text', 'text': 'ok'},
          ],
          'usage': {'input_tokens': 1, 'output_tokens': 1},
        },
      );

      final messages = (body['messages'] as List).cast<Map>();
      final content = messages.single['content'];
      if (content is List) {
        final parts = content.cast<Map>();
        expect(parts.any((part) => part['type'] == 'image'), isFalse);
        expect(parts.first['text'], 'still send me');
      } else {
        expect(content, 'still send me');
      }
    });

    test('preserves media-paths list order in image blocks', () async {
      final dir = await Directory.systemTemp.createTemp('kelivo_claude_order_');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });
      final first = File('${dir.path}/a.png');
      final second = File('${dir.path}/b.png');
      await first.writeAsBytes(const [1, 2, 3, 4]);
      await second.writeAsBytes(const [5, 6, 7, 8]);

      final body = await _captureProviderBody(
        (baseUrl) {
          return ChatApiService.sendMessageStream(
            config: _claudeConfig(baseUrl),
            modelId: 'claude-sonnet-4-6',
            messages: [
              {
                'role': 'user',
                'content': 'ordered',
                multimodalInternalMediaPathsKey: [first.path, second.path],
              },
            ],
            stream: false,
          ).toList();
        },
        responseBody: const <String, dynamic>{
          'id': 'msg_1',
          'content': [
            {'type': 'text', 'text': 'ok'},
          ],
          'usage': {'input_tokens': 1, 'output_tokens': 1},
        },
      );

      final messages = (body['messages'] as List).cast<Map>();
      final parts = (messages.single['content'] as List).cast<Map>();
      final images = parts.where((part) => part['type'] == 'image').toList();
      expect(images, hasLength(2));
      expect(images[0]['source']['data'], 'AQIDBA==');
      expect(images[1]['source']['data'], 'BQYHCA==');
    });

    test(
      'image/jpg supplemental mime is emitted as media_type image/jpeg',
      () async {
        final dir = await Directory.systemTemp.createTemp('kelivo_claude_jpg_');
        addTearDown(() async {
          if (await dir.exists()) await dir.delete(recursive: true);
        });
        final file = File('${dir.path}/photo.jpg');
        await file.writeAsBytes(const [1, 2, 3, 4]);

        final body = await _captureProviderBody(
          (baseUrl) {
            return ChatApiService.sendMessageStream(
              config: _claudeConfig(baseUrl),
              modelId: 'claude-sonnet-4-6',
              messages: [
                {
                  'role': 'user',
                  'content': 'see this',
                  multimodalInternalMediaPathsKey: [
                    encodeInternalMediaRef(uri: file.path, mime: 'image/jpg'),
                  ],
                },
              ],
              stream: false,
            ).toList();
          },
          responseBody: const <String, dynamic>{
            'id': 'msg_1',
            'content': [
              {'type': 'text', 'text': 'ok'},
            ],
            'usage': {'input_tokens': 1, 'output_tokens': 1},
          },
        );

        final messages = (body['messages'] as List).cast<Map>();
        final parts = (messages.single['content'] as List).cast<Map>();
        final image = parts.firstWhere((part) => part['type'] == 'image');
        expect(image['source']['media_type'], 'image/jpeg');
        expect(jsonEncode(body), isNot(contains('"media_type":"image/jpg"')));
      },
    );

    test(
      'video/mp4 supplemental ref does not become Claude image block',
      () async {
        final dir = await Directory.systemTemp.createTemp(
          'kelivo_claude_video_',
        );
        addTearDown(() async {
          if (await dir.exists()) await dir.delete(recursive: true);
        });
        final file = File('${dir.path}/clip.mp4');
        await file.writeAsBytes(const [1, 2, 3, 4]);

        final body = await _captureProviderBody(
          (baseUrl) {
            return ChatApiService.sendMessageStream(
              config: _claudeConfig(baseUrl),
              modelId: 'claude-sonnet-4-6',
              messages: [
                {
                  'role': 'user',
                  'content': 'watch this',
                  multimodalInternalMediaPathsKey: [
                    encodeInternalMediaRef(uri: file.path, mime: 'video/mp4'),
                  ],
                },
              ],
              stream: false,
            ).toList();
          },
          responseBody: const <String, dynamic>{
            'id': 'msg_1',
            'content': [
              {'type': 'text', 'text': 'ok'},
            ],
            'usage': {'input_tokens': 1, 'output_tokens': 1},
          },
        );

        final messages = (body['messages'] as List).cast<Map>();
        final content = messages.single['content'];
        if (content is List) {
          final parts = content.cast<Map>();
          expect(parts.any((part) => part['type'] == 'image'), isFalse);
          expect(
            parts.any(
              (part) =>
                  part['type'] == 'image' &&
                  (part['source'] as Map?)?['media_type'] == 'video/mp4',
            ),
            isFalse,
          );
          expect(parts.first['text'], 'watch this');
        } else {
          expect(content, 'watch this');
        }
        expect(jsonEncode(body), isNot(contains('"media_type":"video/mp4"')));
      },
    );

    test(
      'remote video/mp4 supplemental ref is kept as text, not image',
      () async {
        const remote = 'https://cdn.example.com/clip.mp4';
        final body = await _captureProviderBody(
          (baseUrl) {
            return ChatApiService.sendMessageStream(
              config: _claudeConfig(baseUrl),
              modelId: 'claude-sonnet-4-6',
              messages: [
                {
                  'role': 'user',
                  'content': 'remote clip',
                  multimodalInternalMediaPathsKey: [
                    encodeInternalMediaRef(uri: remote, mime: 'video/mp4'),
                  ],
                },
              ],
              stream: false,
            ).toList();
          },
          responseBody: const <String, dynamic>{
            'id': 'msg_1',
            'content': [
              {'type': 'text', 'text': 'ok'},
            ],
            'usage': {'input_tokens': 1, 'output_tokens': 1},
          },
        );

        final messages = (body['messages'] as List).cast<Map>();
        final parts = (messages.single['content'] as List).cast<Map>();
        expect(parts.any((part) => part['type'] == 'image'), isFalse);
        expect(
          parts.any((part) => part['type'] == 'text' && part['text'] == remote),
          isTrue,
        );
        expect(jsonEncode(body), isNot(contains('"media_type":"video/mp4"')));
      },
    );
  });

  group('Gemini structured media paths (ticket 10)', () {
    test('encodes multimodalInternalMediaPathsKey as inline_data', () async {
      final file = await _tempPng('kelivo_gemini_media_');
      addTearDown(() async {
        final dir = file.parent;
        if (await dir.exists()) await dir.delete(recursive: true);
      });

      final body = await _captureProviderBody(
        (baseUrl) {
          return ChatApiService.sendMessageStream(
            config: _geminiConfig('$baseUrl/v1beta'),
            modelId: 'gemini-2.5-pro',
            messages: [
              {
                'role': 'user',
                'content': 'before after',
                multimodalInternalMediaPathsKey: [file.path],
              },
            ],
            stream: false,
          ).toList();
        },
        responseBody: const <String, dynamic>{
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': 'ok'},
                ],
              },
            },
          ],
        },
        basePath: '',
      );

      final contents = (body['contents'] as List).cast<Map>();
      final parts = (contents.single['parts'] as List).cast<Map>();
      expect(parts.first['text'], 'before after');
      expect(parts.any((part) => part['inline_data'] is Map), isTrue);
      final image = parts.firstWhere((part) => part['inline_data'] is Map);
      expect(image['inline_data']['mime_type'], 'image/png');
      expect(image['inline_data']['data'], 'AQIDBA==');
      expect(jsonEncode(body), isNot(contains('[image:')));
    });

    test('literal [image:...] text is not treated as an attachment', () async {
      final body = await _captureProviderBody(
        (baseUrl) {
          return ChatApiService.sendMessageStream(
            config: _geminiConfig('$baseUrl/v1beta'),
            modelId: 'gemini-2.5-pro',
            messages: const [
              {
                'role': 'user',
                'content': 'inline [image:data:image/png;base64,QUJD]',
              },
            ],
            stream: false,
          ).toList();
        },
        responseBody: const <String, dynamic>{
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': 'ok'},
                ],
              },
            },
          ],
        },
      );

      final contents = (body['contents'] as List).cast<Map>();
      final parts = (contents.single['parts'] as List).cast<Map>();
      expect(parts.single['text'], 'inline [image:data:image/png;base64,QUJD]');
      expect(parts.any((part) => part['inline_data'] is Map), isFalse);
    });

    test('skips missing local media paths without crashing', () async {
      final missing =
          '${Directory.systemTemp.path}/kelivo_missing_gemini_${DateTime.now().microsecondsSinceEpoch}.png';
      final body = await _captureProviderBody(
        (baseUrl) {
          return ChatApiService.sendMessageStream(
            config: _geminiConfig('$baseUrl/v1beta'),
            modelId: 'gemini-2.5-pro',
            messages: [
              {
                'role': 'user',
                'content': 'still send me',
                multimodalInternalMediaPathsKey: [missing],
              },
            ],
            stream: false,
          ).toList();
        },
        responseBody: const <String, dynamic>{
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': 'ok'},
                ],
              },
            },
          ],
        },
      );

      final contents = (body['contents'] as List).cast<Map>();
      final parts = (contents.single['parts'] as List).cast<Map>();
      expect(parts.single['text'], 'still send me');
      expect(parts.any((part) => part['inline_data'] is Map), isFalse);
    });
  });

  group('LongCat host / streaming usage detection', () {
    test('recognizes bare hostname and full URL', () {
      expect(ChatApiService.isLongCatHostForTest('api.longcat.chat'), isTrue);
      expect(
        ChatApiService.isLongCatHostForTest('https://api.longcat.chat/v1'),
        isTrue,
      );
      expect(ChatApiService.isLongCatHostForTest('api.openai.com'), isFalse);
    });

    test('streaming usage options disabled for LongCat hostnames', () {
      expect(
        ChatApiService.shouldIncludeStreamingUsageOptionsForTest(
          'api.longcat.chat',
        ),
        isFalse,
      );
      expect(
        ChatApiService.shouldIncludeStreamingUsageOptionsForTest(
          'https://api.longcat.chat',
        ),
        isFalse,
      );
      expect(
        ChatApiService.shouldIncludeStreamingUsageOptionsForTest(
          'api.openai.com',
        ),
        isTrue,
      );
    });
  });
}
