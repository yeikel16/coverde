import 'dart:io';

import 'package:args/command_runner.dart';

/// {@template rm_cmd}
/// A generic subcommand to remove a set of files and/or folders.
/// {@endtemplate}
class RmCommand extends Command<void> {
  /// {@macro rm_cmd}
  RmCommand() {
    argParser.addFlag(
      _acceptAbsenceFlag,
      help: '''
Accept absence of a file or folder.
When an element is not present:
- If enabled, the command will continue.
- If disabled, the command will fail.''',
      defaultsTo: true,
    );
  }

  static const _acceptAbsenceFlag = 'accept-absence';

  @override // coverage:ignore-line
  String get description => '''
Remove a set of files and folders.''';

  @override
  String get name => 'remove';

  @override
  List<String> get aliases => ['rm'];

  @override
  Future<void> run() async {
    final _argResults = ArgumentError.checkNotNull(argResults);

    final shouldAcceptAbsence = ArgumentError.checkNotNull(
      _argResults[_acceptAbsenceFlag],
    ) as bool;

    final paths = _argResults.rest;
    if (paths.isEmpty) {
      throw ArgumentError(
        'A set of file and/or directory paths should be provided.',
      );
    }
    for (final elementPath in paths) {
      final elementType = FileSystemEntity.typeSync(elementPath);

      // The element can only be a folder or a file.
      // ignore: exhaustive_cases
      switch (elementType) {
        case FileSystemEntityType.directory:
          final dir = Directory(elementPath);
          dir.deleteSync(recursive: true);
          break;
        case FileSystemEntityType.file:
          final file = File(elementPath);
          file.deleteSync(recursive: true);
          break;
        case FileSystemEntityType.notFound:
          final message = 'The <$elementPath> element does not exist.';
          if (shouldAcceptAbsence) {
            stdout.writeln(message);
          } else {
            throw StateError(message);
          }
      }
    }
  }
}
