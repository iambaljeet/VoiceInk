import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common/sqlite_api.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class DatabaseService {
  DatabaseService._();
  static final instance = DatabaseService._();

  static const _databaseName = 'voiceink.db';
  static const _databaseVersion = 2;

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    await initialize();
    return _database!;
  }

  Future<void> initialize() async {
    if (_database != null) return;

    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final appSupportDir = await getApplicationSupportDirectory();
    final dbPath = p.join(appSupportDir.path, _databaseName);

    _database = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: _databaseVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE dictionary_terms (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        source_value TEXT NOT NULL,
        destination_value TEXT NOT NULL,
        is_enabled INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');

    await db.execute('''
      CREATE TABLE user_stats (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Remove transcription_history table (history feature removed)
      await db.execute('DROP TABLE IF EXISTS transcription_history');
    }
  }

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}
