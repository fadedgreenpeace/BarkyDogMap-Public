import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/map_pin.dart';
import '../models/walk.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._init();
  static Database? _database;

  DatabaseService._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('bark_hazards.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 5,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }

  Future _createDB(Database db, int version) async {
    const idType = 'TEXT PRIMARY KEY';
    const realType = 'REAL NOT NULL';
    const textType = 'TEXT NOT NULL';

    await db.execute('''
CREATE TABLE hazards (
  id $idType,
  type $textType DEFAULT 'hazard',
  title $textType DEFAULT '',
  description $textType DEFAULT '',
  image_path $textType DEFAULT '',
  latitude $realType,
  longitude $realType,
  timestamp $textType
  )
''');

    await db.execute('''
CREATE TABLE walks (
  id $idType,
  startTime $textType,
  endTime $textType,
  distanceMeters $realType,
  routeJson $textType
  )
''');
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      const idType = 'TEXT PRIMARY KEY';
      const realType = 'REAL NOT NULL';
      const textType = 'TEXT NOT NULL';

      await db.execute('''
CREATE TABLE walks (
  id $idType,
  startTime $textType,
  endTime $textType,
  distanceMeters $realType,
  routeJson $textType
  )
''');
    }

    if (oldVersion < 3) {
      await db.execute(
        "ALTER TABLE hazards ADD COLUMN type TEXT DEFAULT 'hazard'",
      );
    }

    if (oldVersion < 4) {
      await db.execute("ALTER TABLE hazards ADD COLUMN title TEXT DEFAULT ''");
      await db.execute(
        "ALTER TABLE hazards ADD COLUMN description TEXT DEFAULT ''",
      );
    }

    if (oldVersion < 5) {
      await db.execute(
        "ALTER TABLE hazards ADD COLUMN image_path TEXT DEFAULT ''",
      );
    }
  }

  Future<void> insertPin(MapPin pin) async {
    final db = await instance.database;
    await db.insert(
      'hazards',
      pin.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updatePin(MapPin pin) async {
    final db = await instance.database;
    await db.update(
      'hazards',
      pin.toMap(),
      where: 'id = ?',
      whereArgs: [pin.id],
    );
  }

  Future<List<MapPin>> getAllPins() async {
    final db = await instance.database;
    final maps = await db.query('hazards', orderBy: 'timestamp DESC');
    return maps.map((map) => MapPin.fromMap(map)).toList();
  }

  Future<void> deletePin(String id) async {
    final db = await instance.database;
    await db.delete('hazards', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> insertWalk(Walk walk) async {
    final db = await instance.database;
    await db.insert(
      'walks',
      walk.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Walk>> getAllWalks() async {
    final db = await instance.database;
    final maps = await db.query('walks', orderBy: 'startTime DESC');
    return maps.map((map) => Walk.fromMap(map)).toList();
  }

  Future<void> deleteWalk(String id) async {
    final db = await instance.database;
    await db.delete('walks', where: 'id = ?', whereArgs: [id]);
  }
}
