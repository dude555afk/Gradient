import 'package:html/parser.dart' as parser;
import 'package:http/http.dart' as http;

import 'duckduckgo_search_service.dart';
import 'search_models.dart';

class WebResearchService {
  WebResearchService({
    DuckDuckGoSearchService? search,
    http.Client? client,
  })  : _search = search ?? DuckDuckGoSearchService(),
        _client = client ?? http.Client(),
        _ownsClient = client == null,
        _ownsSearch = search == null;

  final DuckDuckGoSearchService _search;
  final http.Client _client;
  final bool _ownsClient;
  final bool _ownsSearch;

  Future<SearchResult> search(String query) => _search.search(query);

  Future<String> openPage(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !{'http', 'https'}.contains(uri.scheme)) {
      throw const FormatException('Only http(s) URLs can be opened.');
    }

    final response = await _client
        .get(
          uri,
          headers: const {
            'User-Agent':
                'Mozilla/5.0 (Linux; Android 16) AppleWebKit/537.36 Chrome/124.0 Mobile Safari/537.36',
          },
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Page returned HTTP ${response.statusCode}.');
    }

    final doc = parser.parse(response.body);
    for (final node in doc.querySelectorAll(
      'script,style,noscript,svg,nav,footer',
    )) {
      node.remove();
    }

    final title = doc.querySelector('title')?.text.trim() ?? '';
    final text = (doc.body?.text ?? '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final clipped = text.length > 14000 ? text.substring(0, 14000) : text;
    return [if (title.isNotEmpty) 'Title: $title', clipped].join('\n\n');
  }

  void dispose() {
    if (_ownsSearch) _search.dispose();
    if (_ownsClient) _client.close();
  }
}
