import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:coverde/src/assets/report_style.css.asset.dart';
import 'package:coverde/src/assets/sort_alpha.png.asset.dart';
import 'package:coverde/src/assets/sort_numeric.png.asset.dart';
import 'package:coverde/src/entities/tracefile.dart';
import 'package:coverde/src/utils/command.dart';
import 'package:coverde/src/utils/path.dart';
import 'package:io/ansi.dart';
import 'package:meta/meta.dart';

/// {@template report_cmd}
/// A command to generate the coverage report from a given tracefile.
/// {@endtemplate}
class ReportCommand extends Command<void> {
  /// {@macro report_cmd}
  ReportCommand({Stdout? out}) : _out = out ?? stdout {
    argParser
      ..addOption(
        inputOption,
        abbr: inputOption[0],
        help: '''
Coverage tracefile to be used for the coverage report generation.''',
        valueHelp: _inputHelpValue,
        defaultsTo: 'coverage/lcov.info',
      )
      ..addOption(
        outputOption,
        abbr: outputOption[0],
        help: '''
Destination directory where the generated coverage report will be stored.''',
        valueHelp: _outputHelpValue,
        defaultsTo: 'coverage/html/',
      )
      ..addSeparator(
        '''
Threshold values (%):
These options provide reference coverage values for the HTML report styling.

High: $_highHelpValue <= coverage <= 100
Medium: $_mediumHelpValue <= coverge < $_highHelpValue
Low: 0 <= coverage < $_mediumHelpValue''',
      )
      ..addOption(
        mediumOption,
        help: '''
Medium threshold.''',
        valueHelp: _mediumHelpValue,
        defaultsTo: '75',
      )
      ..addOption(
        highOption,
        help: '''
High threshold.''',
        valueHelp: _highHelpValue,
        defaultsTo: '90',
      );
  }

  final Stdout _out;

  static const _inputHelpValue = 'TRACEFILE';
  static const _outputHelpValue = 'REPORT_DIR';
  static const _mediumHelpValue = 'MEDIUM_VAL';
  static const _highHelpValue = 'HIGH_VAL';

  /// Option name for the origin tracefile.
  @visibleForTesting
  static const inputOption = 'input';

  /// Option name for the destionation container folder to dump the report to.
  @visibleForTesting
  static const outputOption = 'output';

  /// Option name to set the medium threshold for coverage validation.
  @visibleForTesting
  static const mediumOption = 'medium';

  /// Option name to set the high threshold for coverage validation.
  @visibleForTesting
  static const highOption = 'high';

  @override
  String get description => '''
Generate the coverage report from a tracefile.

Genrate the coverage report inside $_outputHelpValue from the $_inputHelpValue tracefile.''';

  @override
  String get name => 'report';

  @override
  List<String> get aliases => [name[0]];

  @override
  Future<void> run() async {
    // Retrieve arguments and validate their value and the state they represent.
    final _tracefilePath = checkOption(
      optionKey: inputOption,
      optionName: 'input trace file',
    );
    final _reportDirPath = checkOption(
      optionKey: outputOption,
      optionName: 'output report folder',
    );
    final mediumString = checkOption(
      optionKey: mediumOption,
      optionName: 'medium threshold',
    );
    final medium = double.tryParse(mediumString);
    if (medium == null) usageException('Invalid medium threshold.');
    final highString = checkOption(
      optionKey: highOption,
      optionName: 'high threshold',
    );
    final high = double.tryParse(highString);
    if (high == null) usageException('Invalid high threshold.');

    // Report dir path should be absolute.
    final reportDirAbsPath = path.isAbsolute(_reportDirPath)
        ? _reportDirPath
        : path.join(Directory.current.path, _reportDirPath);
    final tracefileAbsPath = path.isAbsolute(_tracefilePath)
        ? _tracefilePath
        : path.join(Directory.current.path, _tracefilePath);

    final tracefile = File(tracefileAbsPath);

    if (!tracefile.existsSync()) {
      usageException(
        'The trace file located at `$tracefileAbsPath` does not exist.',
      );
    }

    // Get tracefile content.
    final tracefileContent = tracefile.readAsStringSync().trim();

    // Parse tracefile data.
    final tracefileData = Tracefile.parse(tracefileContent);

    // Build cov report base tree.
    final covTree = tracefileData.asTree
      // Generate report doc.
      ..generateReport(
        tracefileName: path.basename(tracefileAbsPath),
        tracefileModificationDate: tracefile.lastModifiedSync(),
        parentReportDirAbsPath: reportDirAbsPath,
        medium: medium,
        high: high,
      );

    // Copy static files.
    final cssRootPath = path.join(
      reportDirAbsPath,
      'report_style.css',
    );
    File(cssRootPath)
      ..createSync(recursive: true)
      ..writeAsBytesSync(reportStyleCssBytes);

    final sortAlphaIconRootPath = path.join(
      reportDirAbsPath,
      'sort_alpha.png',
    );
    File(sortAlphaIconRootPath)
      ..createSync(recursive: true)
      ..writeAsBytesSync(sortAlphaPngBytes);

    final sortNumericIconRootPath = path.join(
      reportDirAbsPath,
      'sort_numeric.png',
    );
    File(sortNumericIconRootPath)
      ..createSync(recursive: true)
      ..writeAsBytesSync(sortNumericPngBytes);

    final reportIndexAbsPath = path
        .join(reportDirAbsPath, 'index.html')
        .replaceAll(RegExp(r'(\/|\\)'), path.separator);

    _out
      ..writeln(covTree)
      ..write(
        wrapWith(
          'Report location: ',
          [blue, styleBold],
        ),
      )
      ..writeln(
        wrapWith(
          reportIndexAbsPath,
          [blue, styleBold, styleUnderlined],
        ),
      )
      ..writeln();
  }
}
