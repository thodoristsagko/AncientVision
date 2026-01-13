import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../models/artifact_classification.dart';
import '../models/site.dart';
import '../models/context_sheet.dart';
import '../models/measurement.dart';

/// Service for generating professional PDF reports
class ReportService {
  static final ReportService _instance = ReportService._internal();
  factory ReportService() => _instance;
  ReportService._internal();

  final _dateFormat = DateFormat('MMMM d, yyyy');
  final _timeFormat = DateFormat('HH:mm');
  final _dateTimeFormat = DateFormat('yyyy-MM-dd HH:mm');

  /// Generate a comprehensive finding report
  Future<File?> generateFindingReport({
    required Map<String, dynamic> finding,
    ArtifactMetadata? metadata,
    List<Measurement>? measurements,
    Uint8List? imageBytes,
  }) async {
    try {
      final pdf = pw.Document();
      final now = DateTime.now();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          header: (context) => _buildHeader('Finding Report'),
          footer: (context) => _buildFooter(context),
          build: (context) => [
            _buildTitle(finding['id'] ?? 'Unknown ID'),
            pw.SizedBox(height: 20),

            // Basic Information
            _buildSectionTitle('Basic Information'),
            _buildInfoRow('Finding ID', finding['id'] ?? 'N/A'),
            _buildInfoRow('Site', finding['site'] ?? finding['siteName'] ?? 'N/A'),
            _buildInfoRow('Location', _formatLocation(finding)),
            _buildInfoRow('Date Recorded', _formatDate(finding['createdAt'])),
            _buildInfoRow('Recorded By', finding['recordedBy'] ?? 'N/A'),
            pw.SizedBox(height: 15),

            // Classification
            if (metadata != null) ...[
              _buildSectionTitle('Classification'),
              if (metadata.type != null)
                _buildInfoRow('Type', metadata.type!.name),
              if (metadata.subType != null)
                _buildInfoRow('Sub-type', metadata.subType!),
              if (metadata.material != null)
                _buildInfoRow('Material', metadata.material!.name),
              if (metadata.period != null) ...[
                _buildInfoRow('Period', metadata.period!.name),
                _buildInfoRow('Date Range', metadata.period!.dateRange),
              ],
              if (metadata.condition != null)
                _buildInfoRow('Condition', metadata.condition!.name),
              pw.SizedBox(height: 15),
            ],

            // Measurements
            if (measurements != null && measurements.isNotEmpty) ...[
              _buildSectionTitle('Measurements'),
              ...measurements.map((m) => _buildInfoRow(
                    m.type.label,
                    m.valueString,
                  )),
              pw.SizedBox(height: 15),
            ],

            // Description
            if (finding['description'] != null &&
                finding['description'].toString().isNotEmpty) ...[
              _buildSectionTitle('Description'),
              pw.Paragraph(
                text: finding['description'],
                style: const pw.TextStyle(fontSize: 11),
              ),
              pw.SizedBox(height: 15),
            ],

            // Notes
            if (finding['notes'] != null &&
                finding['notes'].toString().isNotEmpty) ...[
              _buildSectionTitle('Notes'),
              pw.Paragraph(
                text: finding['notes'],
                style: const pw.TextStyle(fontSize: 11),
              ),
              pw.SizedBox(height: 15),
            ],

            // Conservation
            if (metadata?.conservationNotes != null) ...[
              _buildSectionTitle('Conservation Notes'),
              pw.Paragraph(
                text: metadata!.conservationNotes!,
                style: const pw.TextStyle(fontSize: 11),
              ),
              pw.SizedBox(height: 15),
            ],

            // Image placeholder
            if (imageBytes != null) ...[
              _buildSectionTitle('Photograph'),
              pw.Container(
                width: 300,
                height: 200,
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400),
                ),
                child: pw.Center(
                  child: pw.Image(pw.MemoryImage(imageBytes), fit: pw.BoxFit.contain),
                ),
              ),
              pw.SizedBox(height: 15),
            ],

            // Report metadata
            pw.Divider(color: PdfColors.grey300),
            pw.SizedBox(height: 10),
            pw.Text(
              'Report generated: ${_dateTimeFormat.format(now)}',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
            ),
            pw.Text(
              'Generated by AncientVision Archaeological Field App',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
            ),
          ],
        ),
      );

      return await _saveAndReturnFile(pdf, 'finding_${finding['id']}_report.pdf');
    } catch (e) {
      debugPrint('Error generating finding report: $e');
      return null;
    }
  }

  /// Generate a site summary report
  Future<File?> generateSiteReport({
    required Site site,
    required List<Map<String, dynamic>> findings,
    SiteStatistics? statistics,
    List<ContextSheet>? contexts,
  }) async {
    try {
      final pdf = pw.Document();
      final now = DateTime.now();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          header: (context) => _buildHeader('Site Report'),
          footer: (context) => _buildFooter(context),
          build: (context) => [
            _buildTitle(site.name),
            pw.SizedBox(height: 5),
            pw.Text(
              site.type.label,
              style: pw.TextStyle(
                fontSize: 14,
                color: PdfColors.grey700,
                fontStyle: pw.FontStyle.italic,
              ),
            ),
            pw.SizedBox(height: 20),

            // Site Information
            _buildSectionTitle('Site Information'),
            _buildInfoRow('Site Name', site.name),
            _buildInfoRow('Type', site.type.label),
            _buildInfoRow('Location', site.locationString),
            if (site.country != null)
              _buildInfoRow('Country/Region', '${site.country}${site.region != null ? ', ${site.region}' : ''}'),
            if (site.areaString != null)
              _buildInfoRow('Area', site.areaString!),
            if (site.director != null)
              _buildInfoRow('Director', site.director!),
            if (site.institution != null)
              _buildInfoRow('Institution', site.institution!),
            if (site.permitNumber != null)
              _buildInfoRow('Permit Number', site.permitNumber!),
            _buildInfoRow('Status', site.isActive ? 'Active' : 'Inactive'),
            if (site.startDate != null)
              _buildInfoRow('Start Date', _dateFormat.format(site.startDate!)),
            if (site.endDate != null)
              _buildInfoRow('End Date', _dateFormat.format(site.endDate!)),
            if (site.durationDays != null)
              _buildInfoRow('Duration', '${site.durationDays} days'),
            pw.SizedBox(height: 15),

            // Description
            if (site.description != null && site.description!.isNotEmpty) ...[
              _buildSectionTitle('Description'),
              pw.Paragraph(
                text: site.description!,
                style: const pw.TextStyle(fontSize: 11),
              ),
              pw.SizedBox(height: 15),
            ],

            // Team Members
            if (site.teamMembers.isNotEmpty) ...[
              _buildSectionTitle('Team Members'),
              pw.Wrap(
                children: site.teamMembers
                    .map((m) => pw.Container(
                          margin: const pw.EdgeInsets.only(right: 10, bottom: 5),
                          padding: const pw.EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: pw.BoxDecoration(
                            color: PdfColors.grey200,
                            borderRadius: pw.BorderRadius.circular(4),
                          ),
                          child: pw.Text(m, style: const pw.TextStyle(fontSize: 10)),
                        ))
                    .toList(),
              ),
              pw.SizedBox(height: 15),
            ],

            // Statistics
            if (statistics != null) ...[
              _buildSectionTitle('Statistics'),
              _buildInfoRow('Total Findings', statistics.totalFindings.toString()),
              _buildInfoRow('Photos Taken', statistics.photosCount.toString()),
              _buildInfoRow('3D Reconstructions', statistics.reconstructionsCount.toString()),
              if (statistics.lastActivity != null)
                _buildInfoRow('Last Activity', _dateFormat.format(statistics.lastActivity!)),
              pw.SizedBox(height: 15),
            ],

            // Findings Summary
            if (findings.isNotEmpty) ...[
              _buildSectionTitle('Findings Summary (${findings.length} total)'),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
                columnWidths: {
                  0: const pw.FlexColumnWidth(1),
                  1: const pw.FlexColumnWidth(2),
                  2: const pw.FlexColumnWidth(1.5),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    children: [
                      _buildTableHeader('ID'),
                      _buildTableHeader('Description'),
                      _buildTableHeader('Date'),
                    ],
                  ),
                  ...findings.take(20).map((f) => pw.TableRow(
                        children: [
                          _buildTableCell(f['id'] ?? 'N/A'),
                          _buildTableCell(_truncate(f['description'] ?? 'No description', 50)),
                          _buildTableCell(_formatDate(f['createdAt'])),
                        ],
                      )),
                ],
              ),
              if (findings.length > 20)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 5),
                  child: pw.Text(
                    '... and ${findings.length - 20} more findings',
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontStyle: pw.FontStyle.italic,
                      color: PdfColors.grey600,
                    ),
                  ),
                ),
              pw.SizedBox(height: 15),
            ],

            // Contexts Summary
            if (contexts != null && contexts.isNotEmpty) ...[
              _buildSectionTitle('Stratigraphic Contexts (${contexts.length} total)'),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
                columnWidths: {
                  0: const pw.FlexColumnWidth(1),
                  1: const pw.FlexColumnWidth(1),
                  2: const pw.FlexColumnWidth(2),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    children: [
                      _buildTableHeader('Context #'),
                      _buildTableHeader('Type'),
                      _buildTableHeader('Interpretation'),
                    ],
                  ),
                  ...contexts.take(15).map((c) => pw.TableRow(
                        children: [
                          _buildTableCell(c.contextNumber),
                          _buildTableCell(c.type.label),
                          _buildTableCell(_truncate(c.interpretation ?? 'N/A', 40)),
                        ],
                      )),
                ],
              ),
              pw.SizedBox(height: 15),
            ],

            // Report metadata
            pw.Divider(color: PdfColors.grey300),
            pw.SizedBox(height: 10),
            pw.Text(
              'Report generated: ${_dateTimeFormat.format(now)}',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
            ),
            pw.Text(
              'Generated by AncientVision Archaeological Field App',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
            ),
          ],
        ),
      );

      return await _saveAndReturnFile(pdf, 'site_${site.id}_report.pdf');
    } catch (e) {
      debugPrint('Error generating site report: $e');
      return null;
    }
  }

  /// Generate a context sheet PDF
  Future<File?> generateContextSheetPDF(ContextSheet context) async {
    try {
      final pdf = pw.Document();
      final now = DateTime.now();

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(30),
          build: (ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(15),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(width: 2),
                ),
                child: pw.Column(
                  children: [
                    pw.Text(
                      'CONTEXT RECORDING SHEET',
                      style: pw.TextStyle(
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 10),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        _buildContextField('Context No.', context.contextNumber, width: 100),
                        _buildContextField('Site', context.siteId ?? 'N/A', width: 150),
                        _buildContextField('Trench', context.trenchId ?? 'N/A', width: 100),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 15),

              // Type and Interpretation
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: _buildContextSection('Type', [
                      _buildCheckboxRow('Deposit', context.type == ContextType.deposit),
                      _buildCheckboxRow('Cut', context.type == ContextType.cut),
                      _buildCheckboxRow('Fill', context.type == ContextType.fill),
                      _buildCheckboxRow('Structure', context.type == ContextType.structure),
                      _buildCheckboxRow('Surface', context.type == ContextType.surface),
                    ]),
                  ),
                  pw.SizedBox(width: 15),
                  pw.Expanded(
                    flex: 2,
                    child: _buildContextSection('Interpretation', [
                      pw.Container(
                        height: 60,
                        width: double.infinity,
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(width: 0.5),
                        ),
                        padding: const pw.EdgeInsets.all(5),
                        child: pw.Text(
                          context.interpretation ?? '',
                          style: const pw.TextStyle(fontSize: 10),
                        ),
                      ),
                    ]),
                  ),
                ],
              ),
              pw.SizedBox(height: 15),

              // Soil Description
              _buildContextSection('Soil Description', [
                pw.Row(
                  children: [
                    _buildContextField('Soil Type', context.soilType?.label ?? '', width: 120),
                    pw.SizedBox(width: 15),
                    _buildContextField('Color', context.soilColor?.munsellCode ?? '', width: 100),
                    pw.SizedBox(width: 15),
                    _buildContextField('Compaction', context.compaction?.label ?? '', width: 100),
                  ],
                ),
              ]),
              pw.SizedBox(height: 15),

              // Stratigraphic Relationships
              _buildContextSection('Stratigraphic Relationships', [
                pw.Row(
                  children: [
                    _buildContextField('Above', context.above?.join(', ') ?? '', width: 150),
                    pw.SizedBox(width: 15),
                    _buildContextField('Below', context.below?.join(', ') ?? '', width: 150),
                  ],
                ),
                pw.SizedBox(height: 5),
                pw.Row(
                  children: [
                    _buildContextField('Cuts', context.cuts?.join(', ') ?? '', width: 150),
                    pw.SizedBox(width: 15),
                    _buildContextField('Cut by', context.cutBy?.join(', ') ?? '', width: 150),
                  ],
                ),
              ]),
              pw.SizedBox(height: 15),

              // Dimensions
              _buildContextSection('Dimensions', [
                pw.Row(
                  children: [
                    _buildContextField('Length', context.lengthCm != null ? '${context.lengthCm} cm' : '', width: 100),
                    pw.SizedBox(width: 15),
                    _buildContextField('Width', context.widthCm != null ? '${context.widthCm} cm' : '', width: 100),
                    pw.SizedBox(width: 15),
                    _buildContextField('Depth', context.depthCm != null ? '${context.depthCm} cm' : '', width: 100),
                  ],
                ),
                pw.SizedBox(height: 5),
                pw.Row(
                  children: [
                    _buildContextField('Top Elev.', context.topElevation != null ? '${context.topElevation} m' : '', width: 100),
                    pw.SizedBox(width: 15),
                    _buildContextField('Bottom Elev.', context.bottomElevation != null ? '${context.bottomElevation} m' : '', width: 100),
                  ],
                ),
              ]),
              pw.SizedBox(height: 15),

              // Samples
              _buildContextSection('Samples', [
                pw.Row(
                  children: [
                    _buildCheckboxRow('Soil Sample', context.soilSampleTaken),
                    pw.SizedBox(width: 20),
                    _buildCheckboxRow('Flotation', context.flotationSampleTaken),
                    pw.SizedBox(width: 20),
                    _buildCheckboxRow('Carbon/C14', context.carbonSampleTaken),
                  ],
                ),
              ]),
              pw.SizedBox(height: 15),

              // Recording Info
              pw.Row(
                children: [
                  _buildContextField('Recorded By', context.recordedBy ?? '', width: 150),
                  pw.SizedBox(width: 15),
                  _buildContextField('Date', _dateFormat.format(context.recordedAt), width: 120),
                ],
              ),

              // Footer
              pw.Spacer(),
              pw.Divider(),
              pw.Text(
                'Generated by AncientVision - ${_dateTimeFormat.format(now)}',
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
              ),
            ],
          ),
        ),
      );

      return await _saveAndReturnFile(pdf, 'context_${context.contextNumber}.pdf');
    } catch (e) {
      debugPrint('Error generating context sheet: $e');
      return null;
    }
  }

  /// Generate daily field report
  Future<File?> generateDailyReport({
    required DateTime date,
    required List<Map<String, dynamic>> findings,
    String? siteName,
    String? weatherSummary,
    String? notes,
  }) async {
    try {
      final pdf = pw.Document();
      final now = DateTime.now();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          header: (context) => _buildHeader('Daily Field Report'),
          footer: (context) => _buildFooter(context),
          build: (context) => [
            _buildTitle(_dateFormat.format(date)),
            pw.SizedBox(height: 5),
            if (siteName != null)
              pw.Text(
                siteName,
                style: pw.TextStyle(
                  fontSize: 14,
                  color: PdfColors.grey700,
                  fontStyle: pw.FontStyle.italic,
                ),
              ),
            pw.SizedBox(height: 20),

            // Summary
            _buildSectionTitle('Daily Summary'),
            _buildInfoRow('Date', _dateFormat.format(date)),
            _buildInfoRow('Findings Recorded', findings.length.toString()),
            if (weatherSummary != null)
              _buildInfoRow('Weather', weatherSummary),
            pw.SizedBox(height: 15),

            // Findings
            if (findings.isNotEmpty) ...[
              _buildSectionTitle('Findings Recorded Today'),
              ...findings.map((f) => pw.Container(
                    margin: const pw.EdgeInsets.only(bottom: 10),
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey300),
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          f['id'] ?? 'Unknown',
                          style: pw.TextStyle(
                            fontSize: 12,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 5),
                        pw.Text(
                          _truncate(f['description'] ?? 'No description', 100),
                          style: const pw.TextStyle(fontSize: 10),
                        ),
                        if (f['type'] != null)
                          pw.Text(
                            'Type: ${f['type']}',
                            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
                          ),
                      ],
                    ),
                  )),
              pw.SizedBox(height: 15),
            ] else
              pw.Text(
                'No findings recorded on this date.',
                style: pw.TextStyle(
                  fontSize: 11,
                  fontStyle: pw.FontStyle.italic,
                  color: PdfColors.grey600,
                ),
              ),

            // Notes
            if (notes != null && notes.isNotEmpty) ...[
              _buildSectionTitle('Notes'),
              pw.Paragraph(
                text: notes,
                style: const pw.TextStyle(fontSize: 11),
              ),
            ],

            // Footer
            pw.Divider(color: PdfColors.grey300),
            pw.SizedBox(height: 10),
            pw.Text(
              'Report generated: ${_dateTimeFormat.format(now)}',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
            ),
          ],
        ),
      );

      final fileName = 'daily_report_${DateFormat('yyyy-MM-dd').format(date)}.pdf';
      return await _saveAndReturnFile(pdf, fileName);
    } catch (e) {
      debugPrint('Error generating daily report: $e');
      return null;
    }
  }

  // ========== HELPER METHODS ==========

  pw.Widget _buildHeader(String title) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 20),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'AncientVision',
            style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.brown,
            ),
          ),
          pw.Text(
            title,
            style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey600),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildFooter(pw.Context context) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 20),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Generated by AncientVision App',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey500),
          ),
          pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey500),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildTitle(String text) {
    return pw.Text(
      text,
      style: pw.TextStyle(
        fontSize: 24,
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.brown800,
      ),
    );
  }

  pw.Widget _buildSectionTitle(String text) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 10),
      padding: const pw.EdgeInsets.only(bottom: 5),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: PdfColors.brown200, width: 2)),
      ),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 14,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.brown700,
        ),
      ),
    );
  }

  pw.Widget _buildInfoRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 120,
            child: pw.Text(
              '$label:',
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey700,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: const pw.TextStyle(fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildTableHeader(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 10,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
  }

  pw.Widget _buildTableCell(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Text(
        text,
        style: const pw.TextStyle(fontSize: 9),
      ),
    );
  }

  pw.Widget _buildContextSection(String title, List<pw.Widget> children) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(width: 0.5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: const pw.BoxDecoration(
              color: PdfColors.grey200,
            ),
            child: pw.Text(
              title,
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(8),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildContextField(String label, String value, {required double width}) {
    return pw.Container(
      width: width,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label,
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(width: 0.5)),
            ),
            child: pw.Text(
              value,
              style: const pw.TextStyle(fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildCheckboxRow(String label, bool checked) {
    return pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Container(
          width: 12,
          height: 12,
          decoration: pw.BoxDecoration(
            border: pw.Border.all(width: 0.5),
          ),
          child: checked
              ? pw.Center(
                  child: pw.Text('X', style: const pw.TextStyle(fontSize: 8)),
                )
              : pw.SizedBox(),
        ),
        pw.SizedBox(width: 4),
        pw.Text(label, style: const pw.TextStyle(fontSize: 9)),
      ],
    );
  }

  String _formatLocation(Map<String, dynamic> finding) {
    final lat = finding['latitude'];
    final lng = finding['longitude'];
    if (lat != null && lng != null) {
      return '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}';
    }
    return finding['location'] ?? 'N/A';
  }

  String _formatDate(dynamic date) {
    if (date == null) return 'N/A';
    if (date is DateTime) return _dateFormat.format(date);
    if (date is String) {
      try {
        return _dateFormat.format(DateTime.parse(date));
      } catch (_) {
        return date;
      }
    }
    return 'N/A';
  }

  String _truncate(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }

  Future<File> _saveAndReturnFile(pw.Document pdf, String filename) async {
    final dir = await getApplicationDocumentsDirectory();
    final reportsDir = Directory('${dir.path}/reports');
    if (!await reportsDir.exists()) {
      await reportsDir.create(recursive: true);
    }
    final file = File('${reportsDir.path}/$filename');
    await file.writeAsBytes(await pdf.save());
    debugPrint('Report saved: ${file.path}');
    return file;
  }

  /// Share a generated report
  Future<void> shareReport(File file) async {
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'Archaeological Report',
    );
  }
}
