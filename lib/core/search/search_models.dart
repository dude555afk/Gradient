class SearchResult {
  const SearchResult({this.answer, required this.items});

  final String? answer;
  final List<SearchResultItem> items;
}

class SearchResultItem {
  const SearchResultItem({
    required this.title,
    required this.url,
    required this.text,
  });

  final String title;
  final String url;
  final String text;
}

class SearchOptions {
  const SearchOptions({
    this.resultSize = 8,
    this.timeout = const Duration(seconds: 20),
    this.region = 'us-en',
  });

  final int resultSize;
  final Duration timeout;
  final String region;
}
