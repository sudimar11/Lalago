import 'dart:io';

void debugLogAppend(String path, String line) {
  try {
    File(path).writeAsStringSync(line, mode: FileMode.append);
  } catch (_) {}
}
