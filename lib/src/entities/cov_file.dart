import 'dart:io';

import 'package:collection/collection.dart';
import 'package:coverde/src/assets/file_report_line_template.html.asset.dart';
import 'package:coverde/src/assets/file_report_template.html.asset.dart';
import 'package:coverde/src/assets/report_style.css.asset.dart';
import 'package:coverde/src/entities/cov_base.dart';
import 'package:coverde/src/entities/cov_line.dart';
import 'package:coverde/src/entities/covfile_format.exception.dart';
import 'package:coverde/src/utils/path.dart';
import 'package:html/dom.dart';
import 'package:meta/meta.dart';

/// {@template cov_file}
/// # Covered File Data
///
/// A [CovElement] that holds coverage data about a [source] file.
///
/// The data includes the [raw] coverage data about the [source] and the
/// [covLines] with their coverage data.
/// {@endtemplate}
@immutable
class CovFile extends CovElement {
  /// Create a [CovFile] instance.
  ///
  /// {@macro cov_file}
  @visibleForTesting
  CovFile({
    required this.source,
    required this.raw,
    required Iterable<CovLine> covLines,
  }) : _covLines = covLines;

  /// Create a [CovFile] from a [data] trace block string.
  ///
  /// Throws a [CovfileFormatException] if the [data] is not a valid trace
  /// block.
  factory CovFile.parse(String data) {
    final dataLines = data.split('\n');

    String sourcePath() => dataLines
        .firstWhere(
          (l) => l.startsWith(sourceFileTag),
          orElse: () => throw CovfileFormatException(
            message: 'Source file tag not found in the tracefile block.',
          ),
        )
        .replaceAll(sourceFileTag, '')
        .trim();

    final sourceFile = path.canonicalize(
      [
        '.',
        ...sourcePath().split(RegExp(r'(\\|\/)')),
      ].reduce(path.join),
    );

    final covLines = dataLines
        .where((l) => l.startsWith(lineDataTag))
        .map((covLineData) => CovLine.parse(covLineData));

    return CovFile(
      source: File(sourceFile),
      raw: data,
      covLines: covLines,
    );
  }

  /// The raw trace data for the [source].
  final String raw;

  final Iterable<CovLine> _covLines;

  /// The coverage data about the lines of code within the [source].
  late final UnmodifiableListView<CovLine> covLines =
      UnmodifiableListView<CovLine>(_covLines);

  @override
  final File source;

  @override
  late final linesFound = _covLines.length;

  @override
  late final linesHit = _covLines.where((l) => l.hasBeenHit).length;

  /// {@macro cov_line.tag}
  @visibleForTesting
  static const lineDataTag = CovLine.tag;

  /// The beginning of the line of a trace bloc that contains the [raw] coverage
  /// data about a [source] file.
  static const sourceFileTag = 'SF:';

  /// The ending line of a trace bloc that contains the [raw] coverage data
  /// about a [source] file.
  static const endOfRecordTag = 'end_of_record';

  static const _equality = IterableEquality<CovLine>();

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is CovFile &&
        path.equals(other.source.path, source.path) &&
        _equality.equals(other._covLines, _covLines);
  }

  @override
  int get hashCode =>
      path.canonicalize(source.path).hashCode ^ _equality.hash(_covLines);

  /// File report HTML element template.
  @visibleForTesting
  static final fileReportTemplate = Document.html(
    String.fromCharCodes(fileReportTemplateHtmlBytes),
  );

  /// File report line HTML element template.
  @visibleForTesting
  static final fileReportLineTemplate = Element.html(
    String.fromCharCodes(fileReportLineTemplateHtmlBytes),
  );

  @override
  void generateSubReport({
    required String tracefileName,
    required String parentReportDirAbsPath,
    required String reportDirRelPath,
    required int reportRelDepth,
    required DateTime tracefileModificationDate,
    required double medium,
    required double high,
  }) {
    final fileReport = fileReportTemplate.clone(true);

    final topLevelDirRelPath = (reportRelDepth > 1)
        ? List.filled(reportRelDepth - 1, '..').reduce(path.join)
        : '.';
    final topLevelReportRelPath = path.join(topLevelDirRelPath, 'index.html');
    final topLevelCssRelPath = path.join(
      topLevelDirRelPath,
      reportStyleCssFilename,
    );

    final reportFileAbsPath = path.join(
      parentReportDirAbsPath,
      '$reportDirRelPath.html',
    );

    {
      final title = 'Coverage Report - $tracefileName';
      final currentDirPath = source.parent.path;
      final fileName = path.basename(source.path);
      final suffix = getClassSuffix(medium: medium, high: high);

      fileReport.head
        ?..querySelector('link')?.attributes['href'] = topLevelCssRelPath
        ..querySelector('.headTitle')?.text = title;

      fileReport.querySelector('.topLevelAnchor')?.attributes['href'] =
          topLevelReportRelPath;
      fileReport.querySelector('.currentDirPath')?.text = currentDirPath;
      fileReport.querySelector('.currentFileName')?.nodes.last.text =
          ' - $fileName';
      fileReport.querySelector('.tracefileName')?.text = tracefileName;
      fileReport.querySelector('.linesHit')?.text = '$linesHit';
      fileReport.querySelector('.linesFound')?.text = '$linesFound';
      fileReport.querySelector('.covValue')
        ?..text = '$coverageString %'
        ..classes.add('headerCovTableEntry$suffix');
    }

    fileReport.querySelector('.lastTracefileModificationDate')?.text =
        tracefileModificationDate.toString();

    {
      final src = fileReport.querySelector('.source');
      final sourceLines = source.readAsLinesSync();
      final indexedSourceLines = sourceLines.asMap();
      for (final sourceLine in indexedSourceLines.entries) {
        final lineNumber = sourceLine.key + 1;
        final lineContent = sourceLine.value;
        final fileReportLine = fileReportLineTemplate.clone(true);
        final lineNumberText = '$lineNumber '.padLeft(9);
        fileReportLine.querySelector('.lineNum')?.text = lineNumberText;
        {
          final covLine = _covLines.singleWhereOrNull(
            (e) => e.lineNumber == lineNumber,
          );
          final lineHitsText = '${covLine?.hitsNumber ?? ''}'.padLeft(11);
          final srcLine = fileReportLine.querySelector('.sourceLine');
          srcLine?.text = '$lineHitsText : $lineContent';
          if (covLine != null) {
            srcLine?.classes.add(covLine.hasBeenHit ? 'lineCov' : 'lineNoCov');
          }
          src?.append(fileReportLine);
        }
      }
    }

    File(reportFileAbsPath)
      ..createSync(recursive: true)
      ..writeAsStringSync(fileReport.outerHtml);
  }
}
