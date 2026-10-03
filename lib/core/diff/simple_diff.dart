String buildSimpleDiff({
  required String path,
  required String oldText,
  required String newText,
}) {
  final oldLines = oldText.split('\n');
  final newLines = newText.split('\n');

  var prefix = 0;
  while (prefix < oldLines.length &&
      prefix < newLines.length &&
      oldLines[prefix] == newLines[prefix]) {
    prefix++;
  }

  var oldSuffix = oldLines.length - 1;
  var newSuffix = newLines.length - 1;
  while (oldSuffix >= prefix &&
      newSuffix >= prefix &&
      oldLines[oldSuffix] == newLines[newSuffix]) {
    oldSuffix--;
    newSuffix--;
  }

  final buffer = StringBuffer()
    ..writeln('--- a/$path')
    ..writeln('+++ b/$path');

  final contextStart = prefix > 3 ? prefix - 3 : 0;
  for (var i = contextStart; i < prefix; i++) {
    buffer.writeln(' ${oldLines[i]}');
  }

  for (var i = prefix; i <= oldSuffix; i++) {
    buffer.writeln('-${oldLines[i]}');
  }
  for (var i = prefix; i <= newSuffix; i++) {
    buffer.writeln('+${newLines[i]}');
  }

  final suffixEnd =
      (oldSuffix + 4).clamp(0, oldLines.length - 1);
  for (var i = oldSuffix + 1; i <= suffixEnd; i++) {
    if (i >= 0 && i < oldLines.length) {
      buffer.writeln(' ${oldLines[i]}');
    }
  }

  return buffer.toString().trimRight();
}
