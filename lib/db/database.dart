import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/models.dart';

class AppDatabase {
  static Database? _db;

  static Future<Database> get db async {
    _db ??= await _open();
    return _db!;
  }

  static Future<Database> _open() async {
    final path = join(await getDatabasesPath(), 'receipt_splitter.db');
    return openDatabase(path, version: 2, onCreate: _onCreate, onUpgrade: _onUpgrade);
  }

  static Future<void> _onUpgrade(Database db, int from, int to) async {
    if (from < 2) await db.execute('ALTER TABLE sessions ADD COLUMN mePersonId INTEGER');
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        createdAt TEXT NOT NULL,
        mePersonId INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE persons (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sessionId INTEGER NOT NULL,
        name TEXT NOT NULL,
        FOREIGN KEY (sessionId) REFERENCES sessions(id)
      )
    ''');
    await db.execute('''
      CREATE TABLE items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sessionId INTEGER NOT NULL,
        personId INTEGER,
        name TEXT NOT NULL,
        price REAL NOT NULL,
        FOREIGN KEY (sessionId) REFERENCES sessions(id),
        FOREIGN KEY (personId) REFERENCES persons(id)
      )
    ''');
  }

  // Sessions
  static Future<Session> createSession() async {
    final d = await db;
    final session = Session(createdAt: DateTime.now());
    final id = await d.insert('sessions', session.toMap()..remove('id'));
    return Session(id: id, createdAt: session.createdAt);
  }

  static Future<void> deleteAllSessions() async {
    final d = await db;
    await d.delete('items');
    await d.delete('persons');
    await d.delete('sessions');
  }

  static Future<Session?> getLatestSession() async {
    final d = await db;
    final rows = await d.query('sessions', orderBy: 'id DESC', limit: 1);
    if (rows.isEmpty) return null;
    return Session.fromMap(rows.first);
  }

  static Future<void> setMe(int sessionId, int? personId) async {
    final d = await db;
    await d.update('sessions', {'mePersonId': personId}, where: 'id = ?', whereArgs: [sessionId]);
  }

  // Persons
  static Future<Person> addPerson(int sessionId, String name) async {
    final d = await db;
    final person = Person(sessionId: sessionId, name: name);
    final id = await d.insert('persons', person.toMap()..remove('id'));
    return Person(id: id, sessionId: sessionId, name: name);
  }

  static Future<void> renamePerson(int personId, String name) async {
    final d = await db;
    await d.update('persons', {'name': name}, where: 'id = ?', whereArgs: [personId]);
  }

  /// Deletes a person; their items stay in the session as unassigned.
  static Future<void> deletePerson(int sessionId, int personId) async {
    final d = await db;
    await d.transaction((t) async {
      await t.update('items', {'personId': null}, where: 'personId = ?', whereArgs: [personId]);
      await t.delete('persons', where: 'id = ?', whereArgs: [personId]);
      await t.update('sessions', {'mePersonId': null},
          where: 'id = ? AND mePersonId = ?', whereArgs: [sessionId, personId]);
    });
  }

  static Future<List<Person>> getPersons(int sessionId) async {
    final d = await db;
    final rows = await d.query('persons',
        where: 'sessionId = ?', whereArgs: [sessionId]);
    return rows.map(Person.fromMap).toList();
  }

  // Items
  static Future<ReceiptItem> addItem(ReceiptItem item) async {
    final d = await db;
    final id = await d.insert('items', item.toMap()..remove('id'));
    return ReceiptItem(
      id: id,
      sessionId: item.sessionId,
      personId: item.personId,
      name: item.name,
      price: item.price,
    );
  }

  static Future<void> updateItem(ReceiptItem item) async {
    final d = await db;
    await d.update('items', item.toMap(),
        where: 'id = ?', whereArgs: [item.id]);
  }

  static Future<void> deleteItem(int itemId) async {
    final d = await db;
    await d.delete('items', where: 'id = ?', whereArgs: [itemId]);
  }

  static Future<List<ReceiptItem>> getItems(int sessionId) async {
    final d = await db;
    final rows = await d.query('items',
        where: 'sessionId = ?', whereArgs: [sessionId]);
    return rows.map(ReceiptItem.fromMap).toList();
  }
}
