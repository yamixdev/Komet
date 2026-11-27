import '../../../../core/utils/parse.dart';

class MessageSearchResult {
  final String id;
  final int time;
  final int senderId;
  final String text;
  final List<String> highlights;
  final String? attachmentType;
  final String? attachmentName;

  const MessageSearchResult({
    required this.id,
    required this.time,
    required this.senderId,
    required this.text,
    required this.highlights,
    this.attachmentType,
    this.attachmentName,
  });

  static MessageSearchResult? fromRaw(Map<dynamic, dynamic> raw) {
    final message = raw['message'];
    if (message is! Map) return null;
    final id = message['id']?.toString();
    if (id == null) return null;
    final rawHighlights = raw['highlights'];
    final highlights = rawHighlights is List
        ? rawHighlights.whereType<String>().toList()
        : const <String>[];
    final time = message['time'];
    final sender = message['sender'];
    final attachments = message['attaches'];
    final attachment = attachments is List
        ? attachments.whereType<Map>().firstOrNull
        : null;
    final type = attachment?['_type']?.toString().toUpperCase();
    final filename = attachment?['name'];
    final link = message['link'];
    return MessageSearchResult(
      id: id,
      time: time is int ? time : int.tryParse('${time ?? 0}') ?? 0,
      senderId: sender is int ? sender : int.tryParse('${sender ?? 0}') ?? 0,
      text: message['text']?.toString() ?? '',
      highlights: highlights,
      attachmentType: type ?? (link is Map ? link['type']?.toString() : null),
      attachmentName: type == 'FILE' && filename is String
          ? repairLatin1Mojibake(filename)
          : null,
    );
  }
}
