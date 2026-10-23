import 'package:capws/services/error_reporter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // record() schedules its notification through the binding, so the binding has to
  // exist even for these plain unit tests.
  TestWidgetsFlutterBinding.ensureInitialized();

  final reporter = ErrorReporter.instance;

  setUp(reporter.clear);

  group('ErrorReporter', () {
    test('starts empty', () {
      expect(reporter.isEmpty, isTrue);
      expect(reporter.count, 0);
      expect(reporter.unseen, 0);
      expect(reporter.dropped, 0);
    });

    test('records an entry with its kind and context', () {
      reporter.record(
        kind: AppErrorKind.permissionWrite,
        message: 'pm grant a échoué',
        context: 'grant CAMERA -> com.example',
      );

      expect(reporter.count, 1);
      final entry = reporter.entries.single;
      expect(entry.kind, AppErrorKind.permissionWrite);
      expect(entry.message, 'pm grant a échoué');
      expect(entry.context, 'grant CAMERA -> com.example');
    });

    test('exposes entries newest first', () {
      reporter.record(kind: AppErrorKind.manual, message: 'premier');
      reporter.record(kind: AppErrorKind.manual, message: 'deuxieme');
      reporter.record(kind: AppErrorKind.manual, message: 'troisieme');

      expect(
        reporter.entries.map((entry) => entry.message),
        ['troisieme', 'deuxieme', 'premier'],
      );
    });

    test('normalises a blank message rather than showing nothing', () {
      reporter.record(kind: AppErrorKind.native, message: '   ');
      expect(reporter.entries.single.message, '(message vide)');
    });

    test('treats a blank context as absent', () {
      reporter.record(kind: AppErrorKind.native, message: 'x', context: '  ');
      expect(reporter.entries.single.context, isNull);
    });

    test('caps the log and counts what it dropped', () {
      // A widget throwing on every build is the case this protects against.
      for (var i = 0; i < ErrorReporter.maxEntries + 25; i++) {
        reporter.record(kind: AppErrorKind.flutter, message: 'boucle $i');
      }

      expect(reporter.count, ErrorReporter.maxEntries);
      expect(reporter.dropped, 25);
      // The oldest survivor is entry 25, so the first 25 really were discarded.
      expect(reporter.entries.last.message, 'boucle 25');
    });

    test('counts unseen entries for the badge until they are seen', () {
      reporter.record(kind: AppErrorKind.manual, message: 'a');
      reporter.record(kind: AppErrorKind.manual, message: 'b');
      expect(reporter.unseen, 2);

      reporter.markSeen();
      expect(reporter.unseen, 0);
      // Seen entries stay in the log; only the badge resets.
      expect(reporter.count, 2);
    });

    test('clear empties the log, the badge and the dropped counter', () {
      for (var i = 0; i < ErrorReporter.maxEntries + 5; i++) {
        reporter.record(kind: AppErrorKind.manual, message: '$i');
      }
      reporter.clear();

      expect(reporter.isEmpty, isTrue);
      expect(reporter.unseen, 0);
      expect(reporter.dropped, 0);
    });
  });

  group('ErrorReporter.buildReport', () {
    test('carries the header and says so when nothing was captured', () {
      final report = reporter.buildReport({'Android SDK': '34'});

      expect(report, contains('CAPWS'));
      expect(report, contains('Android SDK : 34'));
      expect(report, contains('Erreurs capturées : 0'));
      expect(report, contains('Aucune erreur capturée.'));
    });

    test('lists entries oldest first, with context and stack', () {
      reporter.record(kind: AppErrorKind.manual, message: 'cause');
      reporter.record(
        kind: AppErrorKind.platform,
        message: 'consequence',
        context: 'apres la cause',
        stack: 'frame #0\nframe #1',
      );

      final report = reporter.buildReport(const {});
      expect(report.indexOf('cause'), lessThan(report.indexOf('consequence')));
      expect(report, contains('contexte : apres la cause'));
      expect(report, contains('frame #0'));
      expect(report, contains('frame #1'));
    });

    test('says when the log was truncated, so it never looks complete', () {
      for (var i = 0; i < ErrorReporter.maxEntries + 3; i++) {
        reporter.record(kind: AppErrorKind.manual, message: '$i');
      }
      expect(reporter.buildReport(const {}), contains('supprimées : 3'));
    });
  });
}
