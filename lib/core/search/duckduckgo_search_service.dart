import 'package:html/parser.dart' as parser;
import 'package:http/http.dart' as http;

import 'search_models.dart';

/// Native, keyless DuckDuckGo HTML search.
///
/// Adapted from Kelivo's DuckDuckGo search provider.
class DuckDuckGoSearchService {
  DuckDuckGoSearchService({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;

  Future<SearchResult> search(
    String query, {
    SearchOptions options = const SearchOptions(),
  }) async {
    final region = options.region.trim().isEmpty
        ? 'us-en'
        : options.region.trim();

    final uri = Uri.https('duckduckgo.com', '/html/', {
      'q': query,
      'kl': region,
    });

    final response = await _client
        .get(
          uri,
          headers: const {
            'User-Agent':
                'Mozilla/5.0 (Linux; Android 16) AppleWebKit/537.36 Chrome/124.0 Mobile Safari/537.36',
          },
        )
        .timeout(options.timeout);

    if (response.statusCode != 200) {
      throw StateError(
        'DuckDuckGo returned HTTP ${response.statusCode}',
      );
    }

    final document = parser.parse(response.body);
    final items = <SearchResultItem>[];

    for (final result in document.querySelectorAll('.result')) {
      if (items.length >= options.resultSize) break;

      final titleElement = result.querySelector('.result__a');
      final urlElement = result.querySelector('.result__url');
      final snippetElement = result.querySelector('.result__snippet');

      final title = titleElement?.text.trim() ?? '';
      final rawUrl = titleElement?.attributes['href']?.trim() ??
          urlElement?.text.trim() ??
          '';
      final url = _resolveResultUrl(rawUrl);
      final snippet = snippetElement?.text.trim() ?? '';

      if (title.isEmpty && url.isEmpty && snippet.isEmpty) continue;

      items.add(
        SearchResultItem(
          title: title,
          url: url,
          text: snippet,
        ),
      );
    }

    return SearchResult(items: items);
  }

  static String _resolveResultUrl(String raw) {
    if (raw.isEmpty) return raw;
    final normalized = raw.startsWith('//') ? 'https:$raw' : raw;
    final uri = Uri.tryParse(normalized);
    return uri?.queryParameters['uddg'] ?? normalized;
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}
