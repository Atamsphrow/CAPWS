import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Where a captured problem came from.
enum AppErrorKind {
  /// Thrown inside the widget tree — build, layout, paint, gesture callbacks.
  flutter('Flutter'),

  /// Escaped an async callback and reached the platform dispatcher.
  platform('Async'),

  /// The native bridge returned an error, or the channel itself failed.
  native('Natif'),

  /// A permission write was refused, by Shizuku or by Android.
  permissionWrite('Écriture'),

  /// Reading the device inventory failed.
  inventory('Inventaire'),

  /// Recorded on purpose, including the self-test.
  manual('Manuel');

  const AppErrorKind(this.label);

  final String label;
}

/// One captured problem.
@immutable
class AppError {
  const AppError({
    required this.time,
    required this.kind,
    required this.message,
    this.stack,
    this.context,
  });

  final DateTime time;
  final AppErrorKind kind;
  final String message;
  final String? stack;

  /// What the app was doing — the package being toggled, the permission, the
  /// channel method. This is usually what makes a report actionable.
  final String? context;

  String get shortTime =>
      '${_two(time.hour)}:${_two(time.minute)}:${_two(time.second)}';

  static String _two(int value) => value.toString().padLeft(2, '0');

  /// One entry as it appears in the copied report.
  String format(int index) {
    final buffer = StringBuffer()
      ..writeln('[$index] ${time.toIso8601String()} — ${kind.label}')
      ..writeln('  $message');
    if (context != null) buffer.writeln('  contexte : $context');
    final trace = stack;
    if (trace != null && trace.trim().isNotEmpty) {
      buffer.writeln('  trace :');
      for (final line in trace.trimRight().split('\n')) {
        buffer.writeln('    ${line.trimRight()}');
      }
    }
    return buffer.toString();
  }
}

/// In-app capture of everything that goes wrong, so a problem on a device the
/// developer cannot attach a debugger to still produces a report.
///
/// Deliberately memory-only and capped: the spec rules out writing files, so the
/// log lives for the life of the process and leaves via the clipboard. A crash
/// takes the log with it, which is the honest trade for not touching storage.
class ErrorReporter extends ChangeNotifier {
  ErrorReporter._();

  static final ErrorReporter instance = ErrorReporter._();

  /// Old entries are dropped rather than growing without bound: a widget that
  /// throws on every build can produce thousands of identical errors in seconds.
  static const int maxEntries = 200;

  final List<AppError> _entries = [];
  int _unseen = 0;
  int _dropped = 0;
  bool _notifyScheduled = false;
  bool _installed = false;

  /// Newest first, which is the order the screen shows them in.
  List<AppError> get entries => List.unmodifiable(_entries.reversed);

  int get count => _entries.length;

  /// How many entries were discarded to stay under [maxEntries]. Surfaced in the
  /// report so a truncated log never looks like a complete one.
  int get dropped => _dropped;

  bool get isEmpty => _entries.isEmpty;

  /// Drives the badge on the dashboard.
  int get unseen => _unseen;

  void markSeen() {
    if (_unseen == 0) return;
    _unseen = 0;
    _scheduleNotify();
  }

  /// Redirects Flutter's own error handling here. Safe to call more than once.
  void install() {
    if (_installed) return;
    _installed = true;

    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      record(
        kind: AppErrorKind.flutter,
        message: details.exceptionAsString(),
        stack: details.stack?.toString(),
        context: [
          if (details.library != null) details.library,
          if (details.context != null) details.context.toString(),
        ].whereType<String>().join(' · '),
      );
      // Still print to the console in debug; this replaces the UI, not the log.
      previous?.call(details);
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      record(
        kind: AppErrorKind.platform,
        message: '$error',
        stack: '$stack',
      );
      // Returning true keeps the app alive so the user can actually read the
      // report. A capture tool that dies with the error it captured is useless.
      return true;
    };
  }

  void record({
    required AppErrorKind kind,
    required String message,
    String? stack,
    String? context,
  }) {
    _entries.add(
      AppError(
        time: DateTime.now(),
        kind: kind,
        message: message.trim().isEmpty ? '(message vide)' : message.trim(),
        stack: stack,
        context: (context == null || context.trim().isEmpty) ? null : context.trim(),
      ),
    );
    while (_entries.length > maxEntries) {
      _entries.removeAt(0);
      _dropped++;
    }
    _unseen++;
    _scheduleNotify();
  }

  void clear() {
    if (_entries.isEmpty && _dropped == 0) return;
    _entries.clear();
    _unseen = 0;
    _dropped = 0;
    _scheduleNotify();
  }

  /// Builds the text report. [header] carries the app/device/Shizuku context that
  /// only the UI layer knows about.
  String buildReport(Map<String, String> header) {
    final buffer = StringBuffer()
      ..writeln('=== CAPWS — rapport de diagnostic ===')
      ..writeln('Généré : ${DateTime.now().toIso8601String()}');
    header.forEach((key, value) => buffer.writeln('$key : $value'));
    buffer.writeln('Erreurs capturées : $count');
    if (_dropped > 0) {
      buffer.writeln('Entrées plus anciennes supprimées : $_dropped (limite $maxEntries)');
    }
    buffer.writeln();

    if (_entries.isEmpty) {
      buffer.writeln('Aucune erreur capturée.');
      return buffer.toString();
    }

    // Oldest first in the report: a cause usually precedes its consequences.
    for (var i = 0; i < _entries.length; i++) {
      buffer.writeln(_entries[i].format(i + 1));
    }
    return buffer.toString();
  }

  /// Notifying straight away can land in the middle of a build — which is exactly
  /// when Flutter errors arrive — so it is deferred to after the current frame.
  void _scheduleNotify() {
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    final binding = WidgetsBinding.instance;
    binding.addPostFrameCallback((_) {
      _notifyScheduled = false;
      notifyListeners();
    });
    binding.scheduleFrame();
  }
}
