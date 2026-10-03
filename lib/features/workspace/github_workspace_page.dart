import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class GitHubWorkspacePage extends StatefulWidget {
  const GitHubWorkspacePage({
    super.key,
    this.initialUrl = 'https://github.com',
  });

  final String initialUrl;

  @override
  State<GitHubWorkspacePage> createState() => _GitHubWorkspacePageState();
}

class _GitHubWorkspacePageState extends State<GitHubWorkspacePage> {
  late final WebViewController _controller;
  late String _url;

  @override
  void initState() {
    super.initState();
    _url = widget.initialUrl;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onUrlChange: (change) {
            final url = change.url;
            if (url != null && mounted) {
              setState(() => _url = url);
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(_url));
  }

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(_url);
    final path = uri?.path ?? '';

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('GitHub', style: TextStyle(fontSize: 16)),
            Text(
              path.isEmpty ? 'github.com' : path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Back',
            onPressed: () async {
              if (await _controller.canGoBack()) {
                await _controller.goBack();
              }
            },
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          IconButton(
            tooltip: 'Reload',
            onPressed: _controller.reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}
