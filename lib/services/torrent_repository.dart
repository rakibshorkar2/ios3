import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../models/torrent_task_model.dart';

class TorrentRepository {
  static final TorrentRepository _instance = TorrentRepository._internal();
  factory TorrentRepository() => _instance;
  TorrentRepository._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'torrent_tasks.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE torrent_tasks(
            id TEXT PRIMARY KEY,
            magnetLink TEXT,
            savePath TEXT,
            name TEXT,
            infoHash TEXT,
            state INTEGER,
            progress REAL,
            totalBytes INTEGER,
            downloadedBytes INTEGER,
            downloadSpeed REAL,
            uploadSpeed REAL,
            etaSeconds INTEGER,
            seeders INTEGER,
            peers INTEGER,
            trackers TEXT,
            selectedFileIndices TEXT,
            isSequential INTEGER DEFAULT 0,
            errorMessage TEXT,
            addedAt TEXT
          )
        ''');
      },
    );
  }

  Future<void> insert(TorrentTaskModel task) async {
    final db = await database;
    await db.insert('torrent_tasks', task.toJson(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> update(TorrentTaskModel task) async {
    final db = await database;
    await db.update('torrent_tasks', task.toJson(),
        where: 'id = ?', whereArgs: [task.id]);
  }

  Future<void> delete(String id) async {
    final db = await database;
    await db.delete('torrent_tasks', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<TorrentTaskModel>> getAll() async {
    final db = await database;
    final maps = await db.query('torrent_tasks', orderBy: 'addedAt DESC');
    return maps.map((m) => TorrentTaskModel.fromJson(m)).toList();
  }

  Future<void> deleteAll() async {
    final db = await database;
    await db.delete('torrent_tasks');
  }
}
