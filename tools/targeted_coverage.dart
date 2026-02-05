import 'dart:io';

const _defaultTargets = [
  'lib/src/core/services/notification_service.dart',
  'lib/src/features/settings/presentation/pages/settings_page.dart',
  'lib/src/features/settings/presentation/controllers/settings_controller.dart',
];

void main(List<String> args) {
  final targets = args.isNotEmpty ? args : _defaultTargets;
  final file = File('coverage/lcov.info');
  if (!file.existsSync()) {
    stderr.writeln('coverage/lcov.info not found. Run `flutter test --coverage`.');
    exit(1);
  }

  final lines = file.readAsLinesSync();
  var currentFile = '';
  var include = false;
  int totalLf = 0;
  int totalLh = 0;
  int fileLf = 0;
  int fileLh = 0;
  final stats = <String, Map<String, int>>{};

  for (final line in lines) {
    if (line.startsWith('SF:')) {
      if (include && currentFile.isNotEmpty) {
        stats[currentFile] = {
          'lines': fileLf,
          'covered': fileLh,
        };
      }
      currentFile = line.substring(3);
      include = targets.any((target) => currentFile.endsWith(target));
      fileLf = 0;
      fileLh = 0;
      continue;
    }
    if (!include) {
      continue;
    }
    if (line.startsWith('LF:')) {
      final value = int.parse(line.substring(3));
      fileLf = value;
      totalLf += value;
    }
    if (line.startsWith('LH:')) {
      final value = int.parse(line.substring(3));
      fileLh = value;
      totalLh += value;
    }
  }

  if (include && currentFile.isNotEmpty) {
    stats[currentFile] = {
      'lines': fileLf,
      'covered': fileLh,
    };
  }

  if (totalLf == 0) {
    print('No target files found in coverage report.');
    exit(0);
  }

  final coverage = totalLh / totalLf * 100;
  print('Targeted coverage: ${coverage.toStringAsFixed(2)}% ($totalLh/$totalLf lines)');

  for (final entry in stats.entries) {
    final path = entry.key;
    final metrics = entry.value;
    final linesCount = metrics['lines'] ?? 0;
    final coveredCount = metrics['covered'] ?? 0;
    if (linesCount > 0) {
      final percent = coveredCount / linesCount * 100;
      print(' - ${path.split('/').last}: ${percent.toStringAsFixed(2)}% ($coveredCount/$linesCount)');
    }
  }
}
