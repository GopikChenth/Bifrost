import 'dart:convert';
import 'dart:io';

class DiscordWebhookService {
  const DiscordWebhookService();

  Future<void> sendWebhook({
    required String webhookUrl,
    required String title,
    required String description,
    required int color,
    List<Map<String, String>>? fields,
  }) async {
    final String trimmedUrl = webhookUrl.trim();
    if (trimmedUrl.isEmpty || !trimmedUrl.startsWith('http')) {
      throw Exception('Invalid Discord Webhook URL.');
    }

    final HttpClient client = HttpClient();
    try {
      final Uri uri = Uri.parse(trimmedUrl);
      final HttpClientRequest request = await client.postUrl(uri);
      
      // Set content-type header to application/json
      request.headers.contentType = ContentType.json;

      // Construct Discord Embed Payload
      final Map<String, dynamic> payload = <String, dynamic>{
        'embeds': <Map<String, dynamic>>[
          <String, dynamic>{
            'title': title,
            'description': description,
            'color': color,
            if (fields != null && fields.isNotEmpty)
              'fields': fields.map((Map<String, String> field) => <String, dynamic>{
                'name': field['name'],
                'value': field['value'],
                'inline': field['inline'] == 'true',
              }).toList(),
            'footer': <String, dynamic>{
              'text': 'Bifrost Minecraft Manager',
            },
            'timestamp': DateTime.now().toUtc().toIso8601String(),
          }
        ]
      };

      request.write(jsonEncode(payload));
      final HttpClientResponse response = await request.close();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final String body = await response.transform(utf8.decoder).join();
        throw Exception(
          'Discord returned status code ${response.statusCode}: $body',
        );
      }
    } finally {
      client.close();
    }
  }

  Future<void> sendServerStartedNotification({
    required String webhookUrl,
    required String serverName,
    required String creatorName,
    required String version,
    required String type,
    required String? address,
    int? themeColor,
  }) async {
    await sendWebhook(
      webhookUrl: webhookUrl,
      title: '🟢 Server is Live!',
      description: 'The Minecraft server **$serverName** has successfully started and is ready for players to join.',
      color: themeColor ?? 0x57F287, // Discord Green
      fields: <Map<String, String>>[
        <String, String>{'name': 'Server Name', 'value': serverName, 'inline': 'true'},
        <String, String>{'name': 'Created/Hosted By', 'value': creatorName, 'inline': 'true'},
        <String, String>{'name': 'Version / Type', 'value': '$version ($type)', 'inline': 'true'},
        <String, String>{
          'name': 'Connection Address',
          'value': address != null ? '`$address`' : 'Offline/Local only',
          'inline': 'false',
        },
      ],
    );
  }

  Future<void> sendServerStoppedNotification({
    required String webhookUrl,
    required String serverName,
    required String creatorName,
    int? themeColor,
  }) async {
    await sendWebhook(
      webhookUrl: webhookUrl,
      title: '🔴 Server Offline',
      description: 'The Minecraft server **$serverName** has been stopped.',
      color: themeColor ?? 0xED4245, // Discord Red
      fields: <Map<String, String>>[
        <String, String>{'name': 'Server Name', 'value': serverName, 'inline': 'true'},
        <String, String>{'name': 'Hosted By', 'value': creatorName, 'inline': 'true'},
      ],
    );
  }

  Future<void> sendWorldSyncedNotification({
    required String webhookUrl,
    required String serverName,
    required String creatorName,
    required String statusMessage,
    int? themeColor,
  }) async {
    final bool isSuccess = !statusMessage.toLowerCase().contains('failed');
    await sendWebhook(
      webhookUrl: webhookUrl,
      title: isSuccess ? '💾 Backup Saved' : '⚠️ Backup Failed',
      description: isSuccess
          ? 'World save for **$serverName** has been successfully backed up to Google Drive.'
          : 'Failed to sync world backup for **$serverName** to Google Drive.',
      color: themeColor ?? (isSuccess ? 0x3498DB : 0xF1C40F), // Blue for success, Yellow for warning
      fields: <Map<String, String>>[
        <String, String>{'name': 'Server Name', 'value': serverName, 'inline': 'true'},
        <String, String>{'name': 'Triggered By', 'value': creatorName, 'inline': 'true'},
        <String, String>{'name': 'Details', 'value': statusMessage, 'inline': 'false'},
      ],
    );
  }

  Future<void> sendTestNotification({
    required String webhookUrl,
    required String creatorName,
    int? themeColor,
  }) async {
    await sendWebhook(
      webhookUrl: webhookUrl,
      title: '🧪 Bifrost Discord Webhook Test',
      description: 'Congratulations! The Discord webhook configuration is working perfectly.',
      color: themeColor ?? 0x5865F2, // Discord Blurple (5865F2)
      fields: <Map<String, String>>[
        <String, String>{'name': 'Test By', 'value': creatorName, 'inline': 'true'},
        <String, String>{'name': 'Status', 'value': 'Success ✅', 'inline': 'true'},
      ],
    );
  }
}
