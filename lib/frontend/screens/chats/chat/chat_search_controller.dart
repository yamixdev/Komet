import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../../backend/modules/messages.dart';
import '../../../../core/utils/logger.dart';
import '../../../../main.dart';
import 'message_search_result.dart';

class ChatSearchController extends ChangeNotifier {
  ChatSearchController({
    required this.chatId,
    required this.isMounted,
    this.onFirstResult,
    MessagesModule? source,
  }) : _messages = source ?? messagesModule {
    searchController.addListener(_onTextChanged);
  }

  final int chatId;
  final bool Function() isMounted;
  final void Function(MessageSearchResult)? onFirstResult;
  final MessagesModule _messages;

  final TextEditingController searchController = TextEditingController();
  final ValueNotifier<bool> searchMode = ValueNotifier(false);
  final ValueNotifier<bool> showResults = ValueNotifier(false);
  List<MessageSearchResult> _results = const [];
  bool _loading = false;
  bool _performed = false;
  bool _failed = false;
  int _selectedIndex = 0;
  String _query = '';
  String? _inFlightQuery;
  Timer? _debounce;
  int _seq = 0;

  List<MessageSearchResult> get results => _results;
  bool get loading => _loading;
  bool get performed => _performed;
  bool get failed => _failed;
  int get selectedIndex => _selectedIndex;
  MessageSearchResult? get selected =>
      _results.isEmpty ? null : _results[_selectedIndex];

  void _onTextChanged() {
    final query = searchController.text.trim();
    if (_query == query) return;
    _query = query;
    _debounce?.cancel();
    _seq++;
    _inFlightQuery = null;
    _results = const [];
    _selectedIndex = 0;
    _loading = query.isNotEmpty;
    _performed = false;
    _failed = false;
    notifyListeners();
    if (query.isNotEmpty) {
      _debounce = Timer(const Duration(milliseconds: 300), () {
        unawaited(runSearch(query));
      });
    }
  }

  void submit(String query) {
    _debounce?.cancel();
    if (_performed && !_failed && query.trim() == _query) {
      final result = selected;
      if (!showResults.value && result != null) onFirstResult?.call(result);
      return;
    }
    unawaited(runSearch(query));
  }

  Future<void> runSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty || trimmed == _inFlightQuery) return;
    final seq = ++_seq;
    _inFlightQuery = trimmed;
    if (!_loading) {
      _loading = true;
      _failed = false;
      notifyListeners();
    }
    List<Map<String, dynamic>> raw;
    bool failed = false;
    try {
      raw = await _messages.searchMessages(chatId, trimmed);
    } catch (e) {
      logger.e('Search error: $e');
      raw = const [];
      failed = true;
    }
    if (!isMounted() || seq != _seq) return;
    _inFlightQuery = null;
    final matchedIds = <String>{};
    final mapped = List<MessageSearchResult>.unmodifiable(
      raw
          .map(MessageSearchResult.fromRaw)
          .whereType<MessageSearchResult>()
          .where((result) => matchedIds.add(result.id)),
    );
    _results = mapped;
    _selectedIndex = 0;
    _loading = false;
    _performed = true;
    _failed = failed;
    notifyListeners();
    if (mapped.isEmpty) return;
    if (searchMode.value && !showResults.value) {
      onFirstResult?.call(mapped.first);
    }
    unawaited(_resolveSenders(seq, mapped));
  }

  Future<void> _resolveSenders(int seq, List<MessageSearchResult> found) async {
    try {
      final resolved = await _messages.ensureContactNames(
        found.map((r) => r.senderId),
      );
      if (resolved && isMounted() && seq == _seq) notifyListeners();
    } catch (e) {
      logger.e('Search contacts error: $e');
    }
  }

  MessageSearchResult? step(int delta) {
    final index = _selectedIndex + delta;
    if (index < 0 || index >= _results.length) return null;
    _selectedIndex = index;
    notifyListeners();
    return _results[index];
  }

  void select(MessageSearchResult result) {
    final index = _results.indexWhere((entry) => entry.id == result.id);
    if (index == -1) return;
    _selectedIndex = index;
    showResults.value = false;
    notifyListeners();
  }

  void reset() {
    _debounce?.cancel();
    _seq++;
    _inFlightQuery = null;
    _query = '';
    searchMode.value = false;
    showResults.value = false;
    searchController.clear();
    _results = const [];
    _selectedIndex = 0;
    _loading = false;
    _performed = false;
    _failed = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _seq++;
    searchController.removeListener(_onTextChanged);
    searchController.dispose();
    searchMode.dispose();
    showResults.dispose();
    super.dispose();
  }
}
