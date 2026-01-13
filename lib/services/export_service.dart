import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'package:archive/archive.dart';
import '../models/site.dart';
import '../models/field_journal.dart';
import '../models/context_sheet.dart';
import '../models/measurement.dart';

/// Supported export formats
enum ExportFormat {
  json('JSON', 'json', 'application/json'),
  csv('CSV', 'csv', 'text/csv'),
  geojson('GeoJSON', 'geojson', 'application/geo+json'),
  kml('KML', 'kml', 'application/vnd.google-earth.kml+xml');

  final String label;
  final String extension;
  final String mimeType;

  const ExportFormat(this.label, this.extension, this.mimeType);
}

/// Service for exporting data in various formats
class ExportService {
  static final ExportService _instance = ExportService._internal();
  factory ExportService() => _instance;
  ExportService._internal();

  final _dateFormat = DateFormat('yyyy-MM-dd');
  final _dateTimeFormat = DateFormat('yyyy-MM-dd_HH-mm-ss');

  /// Export findings to JSON
  Future<File?> exportFindingsToJson(List<Map<String, dynamic>> findings) async {
    try {
      final exportData = {
        'exportType': 'findings',
        'exportDate': DateTime.now().toIso8601String(),
        'count': findings.length,
        'data': findings,
        'metadata': {
          'app': 'AncientVision',
          'version': '1.0.0',
          'format': 'json',
        },
      };

      final jsonString = const JsonEncoder.withIndent('  ').convert(exportData);
      return await _saveFile(jsonString, 'findings_export', 'json');
    } catch (e) {
      debugPrint('Error exporting findings to JSON: $e');
      return null;
    }
  }

  /// Export findings to CSV
  Future<File?> exportFindingsToCsv(List<Map<String, dynamic>> findings) async {
    try {
      if (findings.isEmpty) return null;

      // Get all unique keys from findings
      final allKeys = <String>{};
      for (final f in findings) {
        allKeys.addAll(f.keys);
      }
      final headers = allKeys.toList()..sort();

      // Build CSV content
      final buffer = StringBuffer();

      // Header row
      buffer.writeln(headers.map(_escapeCsvField).join(','));

      // Data rows
      for (final finding in findings) {
        final row = headers.map((key) {
          final value = finding[key];
          return _escapeCsvField(_formatCsvValue(value));
        }).join(',');
        buffer.writeln(row);
      }

      return await _saveFile(buffer.toString(), 'findings_export', 'csv');
    } catch (e) {
      debugPrint('Error exporting findings to CSV: $e');
      return null;
    }
  }

  /// Export findings to GeoJSON for mapping applications
  Future<File?> exportFindingsToGeoJson(List<Map<String, dynamic>> findings) async {
    try {
      final features = <Map<String, dynamic>>[];

      for (final finding in findings) {
        final lat = finding['latitude'];
        final lng = finding['longitude'];
        if (lat != null && lng != null) {
          features.add({
            'type': 'Feature',
            'geometry': {
              'type': 'Point',
              'coordinates': [lng, lat],
            },
            'properties': {
              'id': finding['id'],
              'description': finding['description'],
              'type': finding['type'],
              'site': finding['site'] ?? finding['siteName'],
              'date': finding['createdAt'],
            },
          });
        }
      }

      final geoJson = {
        'type': 'FeatureCollection',
        'features': features,
        'metadata': {
          'exportDate': DateTime.now().toIso8601String(),
          'count': features.length,
          'app': 'AncientVision',
        },
      };

      final jsonString = const JsonEncoder.withIndent('  ').convert(geoJson);
      return await _saveFile(jsonString, 'findings_export', 'geojson');
    } catch (e) {
      debugPrint('Error exporting to GeoJSON: $e');
      return null;
    }
  }

  /// Export findings to KML for Google Earth
  Future<File?> exportFindingsToKml(List<Map<String, dynamic>> findings) async {
    try {
      final buffer = StringBuffer();

      buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
      buffer.writeln('<kml xmlns="http://www.opengis.net/kml/2.2">');
      buffer.writeln('  <Document>');
      buffer.writeln('    <name>AncientVision Findings Export</name>');
      buffer.writeln('    <description>Exported on ${DateTime.now().toIso8601String()}</description>');

      // Add placemarks for each finding
      for (final finding in findings) {
        final lat = finding['latitude'];
        final lng = finding['longitude'];
        if (lat != null && lng != null) {
          buffer.writeln('    <Placemark>');
          buffer.writeln('      <name>${_escapeXml(finding['id'] ?? 'Unknown')}</name>');
          buffer.writeln('      <description>${_escapeXml(finding['description'] ?? '')}</description>');
          buffer.writeln('      <Point>');
          buffer.writeln('        <coordinates>$lng,$lat,0</coordinates>');
          buffer.writeln('      </Point>');
          buffer.writeln('    </Placemark>');
        }
      }

      buffer.writeln('  </Document>');
      buffer.writeln('</kml>');

      return await _saveFile(buffer.toString(), 'findings_export', 'kml');
    } catch (e) {
      debugPrint('Error exporting to KML: $e');
      return null;
    }
  }

  /// Export site data
  Future<File?> exportSite(Site site, {ExportFormat format = ExportFormat.json}) async {
    try {
      final data = site.toJson();

      switch (format) {
        case ExportFormat.json:
          final jsonString = const JsonEncoder.withIndent('  ').convert({
            'exportType': 'site',
            'exportDate': DateTime.now().toIso8601String(),
            'data': data,
          });
          return await _saveFile(jsonString, 'site_${site.id}', 'json');

        case ExportFormat.csv:
          final buffer = StringBuffer();
          buffer.writeln(data.keys.map(_escapeCsvField).join(','));
          buffer.writeln(data.values.map((v) => _escapeCsvField(_formatCsvValue(v))).join(','));
          return await _saveFile(buffer.toString(), 'site_${site.id}', 'csv');

        default:
          return await exportSite(site, format: ExportFormat.json);
      }
    } catch (e) {
      debugPrint('Error exporting site: $e');
      return null;
    }
  }

  /// Export context sheets
  Future<File?> exportContextSheets(List<ContextSheet> contexts, {ExportFormat format = ExportFormat.json}) async {
    try {
      final data = contexts.map((c) => c.toJson()).toList();

      switch (format) {
        case ExportFormat.json:
          final jsonString = const JsonEncoder.withIndent('  ').convert({
            'exportType': 'context_sheets',
            'exportDate': DateTime.now().toIso8601String(),
            'count': contexts.length,
            'data': data,
          });
          return await _saveFile(jsonString, 'context_sheets_export', 'json');

        case ExportFormat.csv:
          return _exportListToCsv(data, 'context_sheets_export');

        default:
          return await exportContextSheets(contexts, format: ExportFormat.json);
      }
    } catch (e) {
      debugPrint('Error exporting context sheets: $e');
      return null;
    }
  }

  /// Export journal entries
  Future<File?> exportJournalEntries(List<JournalEntry> entries, {ExportFormat format = ExportFormat.json}) async {
    try {
      final data = entries.map((e) => e.toJson()).toList();

      switch (format) {
        case ExportFormat.json:
          final jsonString = const JsonEncoder.withIndent('  ').convert({
            'exportType': 'field_journal',
            'exportDate': DateTime.now().toIso8601String(),
            'count': entries.length,
            'data': data,
          });
          return await _saveFile(jsonString, 'journal_export', 'json');

        case ExportFormat.csv:
          return _exportListToCsv(data, 'journal_export');

        default:
          return await exportJournalEntries(entries, format: ExportFormat.json);
      }
    } catch (e) {
      debugPrint('Error exporting journal: $e');
      return null;
    }
  }

  /// Export measurements
  Future<File?> exportMeasurements(List<Measurement> measurements, {ExportFormat format = ExportFormat.json}) async {
    try {
      final data = measurements.map((m) => m.toJson()).toList();

      switch (format) {
        case ExportFormat.json:
          final jsonString = const JsonEncoder.withIndent('  ').convert({
            'exportType': 'measurements',
            'exportDate': DateTime.now().toIso8601String(),
            'count': measurements.length,
            'data': data,
          });
          return await _saveFile(jsonString, 'measurements_export', 'json');

        case ExportFormat.csv:
          return _exportListToCsv(data, 'measurements_export');

        default:
          return await exportMeasurements(measurements, format: ExportFormat.json);
      }
    } catch (e) {
      debugPrint('Error exporting measurements: $e');
      return null;
    }
  }

  /// Create a complete project backup (ZIP archive)
  Future<File?> createFullBackup({
    required List<Map<String, dynamic>> findings,
    List<Site>? sites,
    List<ContextSheet>? contexts,
    List<JournalEntry>? journal,
    List<Measurement>? measurements,
  }) async {
    try {
      final archive = Archive();
      final timestamp = _dateTimeFormat.format(DateTime.now());

      // Add manifest
      final manifest = {
        'backupDate': DateTime.now().toIso8601String(),
        'app': 'AncientVision',
        'version': '1.0.0',
        'contents': {
          'findings': findings.length,
          'sites': sites?.length ?? 0,
          'contexts': contexts?.length ?? 0,
          'journal': journal?.length ?? 0,
          'measurements': measurements?.length ?? 0,
        },
      };
      archive.addFile(ArchiveFile(
        'manifest.json',
        utf8.encode(const JsonEncoder.withIndent('  ').convert(manifest)).length,
        utf8.encode(const JsonEncoder.withIndent('  ').convert(manifest)),
      ));

      // Add findings
      if (findings.isNotEmpty) {
        final findingsJson = const JsonEncoder.withIndent('  ').convert(findings);
        archive.addFile(ArchiveFile(
          'findings.json',
          utf8.encode(findingsJson).length,
          utf8.encode(findingsJson),
        ));
      }

      // Add sites
      if (sites != null && sites.isNotEmpty) {
        final sitesJson = const JsonEncoder.withIndent('  ').convert(
          sites.map((s) => s.toJson()).toList(),
        );
        archive.addFile(ArchiveFile(
          'sites.json',
          utf8.encode(sitesJson).length,
          utf8.encode(sitesJson),
        ));
      }

      // Add contexts
      if (contexts != null && contexts.isNotEmpty) {
        final contextsJson = const JsonEncoder.withIndent('  ').convert(
          contexts.map((c) => c.toJson()).toList(),
        );
        archive.addFile(ArchiveFile(
          'contexts.json',
          utf8.encode(contextsJson).length,
          utf8.encode(contextsJson),
        ));
      }

      // Add journal entries
      if (journal != null && journal.isNotEmpty) {
        final journalJson = const JsonEncoder.withIndent('  ').convert(
          journal.map((j) => j.toJson()).toList(),
        );
        archive.addFile(ArchiveFile(
          'journal.json',
          utf8.encode(journalJson).length,
          utf8.encode(journalJson),
        ));
      }

      // Add measurements
      if (measurements != null && measurements.isNotEmpty) {
        final measurementsJson = const JsonEncoder.withIndent('  ').convert(
          measurements.map((m) => m.toJson()).toList(),
        );
        archive.addFile(ArchiveFile(
          'measurements.json',
          utf8.encode(measurementsJson).length,
          utf8.encode(measurementsJson),
        ));
      }

      // Save ZIP file
      final zipData = ZipEncoder().encode(archive);
      if (zipData == null) return null;

      final dir = await getApplicationDocumentsDirectory();
      final exportDir = Directory('${dir.path}/exports');
      if (!await exportDir.exists()) {
        await exportDir.create(recursive: true);
      }

      final file = File('${exportDir.path}/ancientvision_backup_$timestamp.zip');
      await file.writeAsBytes(zipData);

      debugPrint('Backup created: ${file.path}');
      return file;
    } catch (e) {
      debugPrint('Error creating backup: $e');
      return null;
    }
  }

  /// Share an exported file
  Future<void> shareFile(File file) async {
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'AncientVision Export',
    );
  }

  /// Get list of available exports
  Future<List<FileSystemEntity>> getExportedFiles() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final exportDir = Directory('${dir.path}/exports');
      if (!await exportDir.exists()) return [];
      return exportDir.listSync()..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    } catch (e) {
      return [];
    }
  }

  /// Delete an exported file
  Future<bool> deleteExport(File file) async {
    try {
      await file.delete();
      return true;
    } catch (e) {
      return false;
    }
  }

  // ========== HELPER METHODS ==========

  Future<File?> _exportListToCsv(List<Map<String, dynamic>> data, String filename) async {
    if (data.isEmpty) return null;

    // Get all unique keys
    final allKeys = <String>{};
    for (final item in data) {
      allKeys.addAll(_flattenKeys(item));
    }
    final headers = allKeys.toList()..sort();

    // Build CSV
    final buffer = StringBuffer();
    buffer.writeln(headers.map(_escapeCsvField).join(','));

    for (final item in data) {
      final flatItem = _flattenMap(item);
      final row = headers.map((key) {
        return _escapeCsvField(_formatCsvValue(flatItem[key]));
      }).join(',');
      buffer.writeln(row);
    }

    return await _saveFile(buffer.toString(), filename, 'csv');
  }

  Set<String> _flattenKeys(Map<String, dynamic> map, [String prefix = '']) {
    final keys = <String>{};
    for (final entry in map.entries) {
      final key = prefix.isEmpty ? entry.key : '$prefix.${entry.key}';
      if (entry.value is Map<String, dynamic>) {
        keys.addAll(_flattenKeys(entry.value as Map<String, dynamic>, key));
      } else {
        keys.add(key);
      }
    }
    return keys;
  }

  Map<String, dynamic> _flattenMap(Map<String, dynamic> map, [String prefix = '']) {
    final result = <String, dynamic>{};
    for (final entry in map.entries) {
      final key = prefix.isEmpty ? entry.key : '$prefix.${entry.key}';
      if (entry.value is Map<String, dynamic>) {
        result.addAll(_flattenMap(entry.value as Map<String, dynamic>, key));
      } else {
        result[key] = entry.value;
      }
    }
    return result;
  }

  Future<File> _saveFile(String content, String baseName, String extension) async {
    final dir = await getApplicationDocumentsDirectory();
    final exportDir = Directory('${dir.path}/exports');
    if (!await exportDir.exists()) {
      await exportDir.create(recursive: true);
    }

    final timestamp = _dateTimeFormat.format(DateTime.now());
    final filename = '${baseName}_$timestamp.$extension';
    final file = File('${exportDir.path}/$filename');
    await file.writeAsString(content);

    debugPrint('File exported: ${file.path}');
    return file;
  }

  String _escapeCsvField(String field) {
    if (field.contains(',') || field.contains('"') || field.contains('\n')) {
      return '"${field.replaceAll('"', '""')}"';
    }
    return field;
  }

  String _formatCsvValue(dynamic value) {
    if (value == null) return '';
    if (value is DateTime) return _dateFormat.format(value);
    if (value is List) return value.join('; ');
    if (value is Map) return const JsonEncoder().convert(value);
    return value.toString();
  }

  String _escapeXml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}
