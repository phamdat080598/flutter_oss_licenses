import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:dart_pubspec_licenses/dart_pubspec_licenses.dart' as oss;
import 'package:path/path.dart' as path;

main(List<String> args) async {
  final parser = getArgParser();
  final pubCacheDirPath = oss.guessPubCacheDir();
  final results = parser.parse(args);

  try {
    if (results['help']) {
      printUsage(parser);
      return 0;
    } else if (oss.flutterDir == null) {
      stdout.writeln('FLUTTER_ROOT is not set.');
      return 1;
    } else if (pubCacheDirPath == null) {
      stdout.writeln('Could not determine PUB_CACHE directory.');
      return 2;
    } else if (results.rest.isNotEmpty) {
      stdout.writeln('WARNING: extra parameter given');
      printUsage(parser);
      return 3;
    }

    final projectRoot = results['project-root'] ?? await findProjectRoot();
    final outputFilePath = results['output'] ?? path.join(projectRoot, 'lib', 'oss_licenses.dart');
    final generateJson = results['json'] || path.extension(outputFilePath).toLowerCase() == '.json';
    final deps = await oss.listDependencies(
      pubspecLockPath: path.join(projectRoot, 'pubspec.lock'),
      ignore: results['ignore'],
    );

    final String output;
    if (generateJson) {
      output = const JsonEncoder.withIndent('  ').convert(deps.allDependencies.map((e) => e.toJson()).toList());
    } else {
      final sb = StringBuffer();
      String toQuotedString(String s) {
        s = s.replaceAll('\$', '\\\$');
        final quoteCount = "'".allMatches(s).length;
        final doubleQuoteCount = '"'.allMatches(s).length;
        final quote = quoteCount > doubleQuoteCount ? '"' : "'";
        if (!s.contains('\n')) {
          return quote + s.replaceAll(quote, "\\$quote") + quote;
        }
        final q3 = quote * 3;
        return q3 + s.replaceAll(q3, '\\$quote' * 3) + q3;
      }

      void writeIfNotNull(String name, dynamic obj) {
        if (obj == null) return;
        if (obj is List) {
          sb.write('    $name: [');
          for (int i = 0; i < obj.length; i++) {
            if (i > 0) sb.write(', ');
            sb.write(toQuotedString(obj[i]));
          }
          sb.writeln('],');
          return;
        }
        if (obj is! String) {
          sb.writeln('    $name: $obj,');
          return;
        }
        if (obj.contains('\n')) {
          sb.writeln("    $name: ${toQuotedString(obj)},");
          return;
        }
        sb.writeln('    $name: ${toQuotedString(obj)},');
      }

      for (final l in deps.allDependencies) {
        sb.writeln('/// ${l.name} ${l.version}');
        sb.writeln('const _${l.name} = Package(');
        writeIfNotNull('name', l.name);
        writeIfNotNull('description', l.description);
        writeIfNotNull('homepage', l.homepage);
        writeIfNotNull('repository', l.repository);
        writeIfNotNull('authors', l.authors);
        writeIfNotNull('version', l.version);
        writeIfNotNull('license', l.license);
        writeIfNotNull('isMarkdown', l.isMarkdown);
        writeIfNotNull('isSdk', l.isSdk);
        sb.writeln('    dependencies: [${l.dependencies.map((d) => 'PackageRef(\'${d.name}\')').join(', ')}]');

        sb.writeln('  );');
        sb.writeln('');
      }
      output = '''
// cSpell:disable
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: sort_constructors_first

// This code was generated by flutter_oss_licenses
// https://pub.dev/packages/flutter_oss_licenses

/// All dependencies including transitive dependencies.
const allDependencies = <Package>[
${deps.allDependencies.map((d) => '  _${d.name}').join(',\n')}
];

/// Direct `dependencies`.
const dependencies = <Package>[
${deps.dependencies.map((d) => '  _${d.name}').join(',\n')}
];

/// Direct `dev_dependencies`.
const devDependencies = <Package>[
${deps.devDependencies.map((d) => '  _${d.name}').join(',\n')}
];

/// Package license definition.
class Package {
  /// Package name
  final String name;
  /// Description
  final String description;
  /// Website URL
  final String? homepage;
  /// Repository URL
  final String? repository;
  /// Authors
  final List<String> authors;
  /// Version
  final String version;
  /// License
  final String? license;
  /// Whether the license is in markdown format or not (plain text).
  final bool isMarkdown;
  /// Whether the package is included in the SDK or not.
  final bool isSdk;
  /// Direct dependencies
  final List<PackageRef> dependencies;

  const Package({
    required this.name,
    required this.description,
    this.homepage,
    this.repository,
    required this.authors,
    required this.version,
    this.license,
    required this.isMarkdown,
    required this.isSdk,
    required this.dependencies,
  });
}

class PackageRef {
  final String name;

  const PackageRef(this.name);

  Package resolve() => allDependencies.firstWhere((d) => d.name == name);
}

${sb.toString()}''';
    }

    await File(outputFilePath).writeAsString(output);
    return 0;
  } catch (e, s) {
    stderr.writeln('$e: $s');
    return 4;
  }
}

Future<String> findProjectRoot({Directory? from}) async {
  from = from ?? Directory.current;
  if (await File(path.join(from.path, 'pubspec.yaml')).exists()) {
    return from.path;
  }
  return findProjectRoot(from: from.parent);
}

ArgParser getArgParser() {
  final parser = ArgParser();

  parser.addOption('output', abbr: 'o', defaultsTo: null, help: '''
Specify output file path. If the file extension is .json, --json option is implied anyway.
The default output file path depends on the --json flag:
  with    --json: PROJECT_ROOT/assets/oss_licenses.json
  without --json: PROJECT_ROOT/lib/oss_licenses.dart
''');
  parser.addMultiOption('ignore',
      abbr: 'i',
      defaultsTo: [],
      splitCommas: true,
      help: '''
Ignore packages by names.
This option can be specified multiple times, or as a comma-separated list.
''');
  parser.addOption('project-root',
      abbr: 'p', defaultsTo: null, help: 'Explicitly specify project root directory that contains pubspec.lock.');
  parser.addFlag('json',
      abbr: 'j', defaultsTo: false, negatable: false, help: 'Generate JSON file rather than dart file.');
  parser.addFlag('help', abbr: 'h', defaultsTo: false, negatable: false, help: 'Show the help.');

  return parser;
}

void printUsage(ArgParser parser) {
  stdout.writeln('Usage: ${path.basename(Platform.script.toString())} [OPTION]');
  stdout.writeln(parser.usage);
}
