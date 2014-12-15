library tekartik_iodb.idb_database;

import 'package:idb_shim/idb_client_memory.dart';
import 'package:idb_shim/idb_client.dart';
import 'package:tekartik_iodb/database.dart' as iodb;
import 'dart:async';
import 'package:path/path.dart';
import 'idb_common_meta.dart';

const IDB_IODB_DATABASE_MEMORY = "iodb";

class _IodbVersionChangeEvent extends VersionChangeEvent {

  final int oldVersion;
  final int newVersion;
  Request request;
  Object get target => request;
  Database get database => transaction.database;
  /**
     * added for convenience
     */
  _EmbsioTransaction get transaction => request.transaction;

  _IodbVersionChangeEvent(_IodbDatabase database, int oldVersion, this.newVersion) //
      : oldVersion = oldVersion == null ? 0 : oldVersion {

    // handle = too to catch programatical errors
    if (this.oldVersion >= newVersion) {
      throw new StateError("cannot downgrade from ${oldVersion} to $newVersion");
    }
    request = new OpenDBRequest(database, database.versionChangeTransaction);
  }
  @override
  String toString() {
    return "${oldVersion} => ${newVersion}";
  }
}

class _EmbsioTransaction extends Transaction {

  Completer completer;
  @override
  _IodbDatabase get database => super.database;

  final IdbTransactionMeta meta;
  _EmbsioTransaction(_IodbDatabase database, this.meta) : super(database);

  @override
  Future<Database> get completed => completer == null ? new Future.value(database) : completer.future;

  @override
  ObjectStore objectStore(String name) {
    return new _IodbObjectStore(this, database.meta.getObjectStore(name));
  }
}

class _EmbsioIndex extends Index {

  final _IodbObjectStore store;
  final IdbIndexMeta meta;

  _EmbsioIndex(this.store, this.meta);

  @override
  Future<int> count([key_OR_range]) {
    throw 'not implemented yet';
  }

  @override
  Future get(key) {
    throw 'not implemented yet';
  }

  @override
  Future getKey(key) {
    throw 'not implemented yet';
  }

  @override
  get keyPath => meta.keyPath;

  @override
  bool get multiEntry => meta.multiEntry;

  @override
  String get name => meta.name;

  @override
  Stream<CursorWithValue> openCursor({key, KeyRange range, String direction, bool autoAdvance}) {
    throw 'not implemented yet';
  }

  @override
  Stream<Cursor> openKeyCursor({key, KeyRange range, String direction, bool autoAdvance}) {
    throw 'not implemented yet';
  }

  @override
  bool get unique => meta.unique;
}
class _IodbObjectStore extends ObjectStore {

  final IdbObjectStoreMeta meta;
  final _EmbsioTransaction transaction;
  _IodbDatabase get database => transaction.database;
  iodb.Database get iodbDatabase => database.db;
  iodb.Store iodbStore;

  _IodbObjectStore(this.transaction, this.meta) {
    iodbStore = iodbDatabase.getStore(name);
  }

  Future inWritableTransaction(Future computation()) {
    if (transaction.meta.mode != IDB_MODE_READ_WRITE) {
      return new Future.error(new DatabaseReadOnlyError());
    }
    return inTransaction(computation);
  }

  Future inTransaction(Future computation()) {
    return new Future.sync(computation);
  }


  /// extract the key from the key itself or from the value
  /// it is a map and keyPath is not null
  dynamic _getKey(value, [key]) {

    if ((keyPath != null) && (value is Map)) {
      var keyInValue = value[keyPath];
      if (keyInValue != null) {
        if (key != null) {
          throw new ArgumentError("both key ${key} and inline keyPath ${keyInValue} are specified");
        } else {
          return keyInValue;
        }
      }
    }
    
    if (key == null && (!autoIncrement)) {
      throw new DatabaseError('neither keyPath nor autoIncrement set and trying to add object without key');
    }
    
    return key;
  }

  @override
  Future add(value, [key]) {
    return inWritableTransaction(() {
      return iodbStore.inTransaction(() {

        key = _getKey(value, key);

        if (key != null) {
          return iodbStore.get(key).then((existingValue) {
            if (existingValue != null) {
              throw new DatabaseError('Key ${key} already exists in the object store');
            }
            return iodbStore.put(value, key);
          });
        } else {
          return iodbStore.put(value, key);
        }
      });
    });
  }


  @override
  Future clear() {
    return inWritableTransaction(() {
      return iodbStore.clear();
    }).then((_) {
      return null;
    });
  }

  iodb.Filter _keyOrRangeFilter([key_OR_range]) {
    if (key_OR_range == null) {
      return null;
    } else if (key_OR_range is KeyRange) {
      KeyRange range = key_OR_range;
      iodb.Filter lowerFilter;
      iodb.Filter upperFilter;
      List<iodb.Filter> filters = [];
      if (range.lower != null) {
        if (range.lowerOpen == true) {
          lowerFilter = new iodb.Filter.greaterThan(iodb.Field.KEY, range.lower);
        } else {
          lowerFilter = new iodb.Filter.greaterThanOrEquals(iodb.Field.KEY, range.lower);
        }
        filters.add(lowerFilter);
      }
      if (range.upper != null) {
        if (range.upperOpen == true) {
          upperFilter = new iodb.Filter.lessThan(iodb.Field.KEY, range.upper);
        } else {
          upperFilter = new iodb.Filter.lessThanOrEquals(iodb.Field.KEY, range.upper);
        }
        filters.add(upperFilter);
      }
      return new iodb.Filter.and(filters);

    } else {
      return new iodb.Filter.byKey(key_OR_range);
    }
  }
  @override
  Future<int> count([key_OR_range]) {
    return inTransaction(() {
      return iodbStore.count(_keyOrRangeFilter(key_OR_range));
    });
  }

  @override
  Index createIndex(String name, keyPath, {bool unique, bool multiEntry}) {
    IdbIndexMeta indexMeta = new IdbIndexMeta(name, keyPath, unique, multiEntry);
    meta.createIndex(indexMeta);
    return new _EmbsioIndex(this, indexMeta);
  }

  @override
  Future delete(key) {
    return inWritableTransaction(() {
      return iodbStore.delete(key);
    });
  }

  dynamic _recordToValue(iodb.Record record) {
    if (record == null) {
      return null;
    }
    var value = record.value;
    // Add key if _keyPath is not null
    if ((keyPath != null) && (value is Map)) {
      value[keyPath] = record.key;
    }

    return value;
  }

  @override
  Future getObject(key) {
    return inTransaction(() {
      return iodbStore.getRecord(key).then((iodb.Record record) {
        return _recordToValue(record);
      });
    });
  }

  @override
  Index index(String name) {
    IdbIndexMeta indexMeta = meta.index(name);
    return new _EmbsioIndex(this, indexMeta);
  }

  @override
  List<String> get indexNames => new List.from(meta.indexNames, growable: false);

  @override
  String get name => meta.name;

  @override
  Stream<CursorWithValue> openCursor({key, KeyRange range, String direction, bool autoAdvance}) {
    throw 'not implemented yet';
  }

  @override
  Future put(value, [key]) {
    return inWritableTransaction(() {
      return iodbStore.put(value, _getKey(value, key));
    });
  }

  @override
  bool get autoIncrement => meta.autoIncrement;

  @override
  get keyPath => meta.keyPath;
}

///
/// meta format
/// {"key":"version","value":1}
/// {"key":"stores","value":["test_store"]}
/// {"key":"store_test_store","value":{"name":"test_store","keyPath":"my_key","autoIncrement":true}}

class _IodbDatabase extends Database {

  _EmbsioTransaction versionChangeTransaction;
  final IdbDatabaseMeta meta = new IdbDatabaseMeta();
  final String _name;
  iodb.Database db;

  @override
  IdbDatabaseFactory get factory => super.factory;

  iodb.DatabaseFactory get iodbFactory => factory._databaseFactory;

  _IodbDatabase(IdbFactory factory, this._name) : super(factory);

  Future open(int newVersion, void onUpgradeNeeded(VersionChangeEvent event)) {
    int previousVersion;
    _open() {
      return iodbFactory.openDatabase(join(factory._path, _name), version: 1).then((iodb.Database db) {
        this.db = db;
        return db.inTransaction(() {

          return db.mainStore.get("version").then((int version) {
            previousVersion = version;
          }).then((_) {
            // read meta
            return db.mainStore.getRecord("stores").then((iodb.Record record) {
              if (record != null) {
                List<String> storeNames = record.value;
                List<String> keys = [];
                storeNames.forEach((String storeName) {
                  keys.add("store_${storeName}");
                });
                return db.mainStore.getRecords(keys).then((List<iodb.Record> records) {
                  records.forEach((iodb.Record record) {
                    Map map = record.value;
                    IdbObjectStoreMeta store = new IdbObjectStoreMeta.fromMap(meta, map);
                    meta.addObjectStore(store);


                  });
                });
              }

            });
          });
        }).then((_) => db);



      });
    }

    return _open().then((db) {
      if (newVersion != previousVersion) {
        Set<IdbObjectStoreMeta> changedStores;

        meta.onUpgradeNeeded(() {
          versionChangeTransaction = new _EmbsioTransaction(this, meta.versionChangeTransaction);
          // could be null when opening an empty database
          if (onUpgradeNeeded != null) {
            onUpgradeNeeded(new _IodbVersionChangeEvent(this, previousVersion, newVersion));
          }
          changedStores = meta.versionChangeStores;
        });


        return db.inTransaction(() {

          return db.put(newVersion, "version").then((_) {
            if (changedStores.isNotEmpty) {
              return db.put(new List.from(objectStoreNames), "stores");
            }
          }).then((_) {
// write changes
            List<Future> futures = [];

            changedStores.forEach((IdbObjectStoreMeta storeMeta) {
              futures.add(db.put(storeMeta.toMap(), "store_${storeMeta.name}"));
            });

            return Future.wait(futures);

          });

        }).then((_) {
          // considered as opened
          meta.version = newVersion;
        });

      }
    });


  }

  @override
  void close() {
    db.close();
  }

  @override
  ObjectStore createObjectStore(String name, {String keyPath, bool autoIncrement}) {
    IdbObjectStoreMeta storeMeta = new IdbObjectStoreMeta(meta, name, keyPath, autoIncrement);
    meta.createObjectStore(storeMeta);
    return new _IodbObjectStore(versionChangeTransaction, storeMeta);
  }

  @override
  void deleteObjectStore(String name) {
    throw 'not implemented yet';
  }

  @override
  String get name => _name;

  @override
  Iterable<String> get objectStoreNames {
    return meta.objectStoreNames;
  }

  @override
  Stream<VersionChangeEvent> get onVersionChange {
    throw 'not implemented yet';
  }

  @override
  Transaction transaction(storeName_OR_storeNames, String mode) {
    IdbTransactionMeta txnMeta = meta.transaction(storeName_OR_storeNames, mode);
    return new _EmbsioTransaction(this, txnMeta);
  }

  @override
  Transaction transactionList(List<String> storeNames, String mode) {
    IdbTransactionMeta txnMeta = meta.transaction(storeNames, mode);
    return new _EmbsioTransaction(this, txnMeta);
  }

  @override
  int get version => meta.version;

  Map toDebugMap() {
    Map map;
    if (meta != null) {
      map = meta.toDebugMap();
    } else {
      map = {};
    }

    if (db != null) {
      map["db"] = db.toDebugMap();
    }
    return map;
  }

  String toString() {
    return toDebugMap().toString();
  }
}
class IdbDatabaseFactory extends IdbFactory {

  final iodb.DatabaseFactory _databaseFactory;
  final String _path;

  @override
  bool get persistent => _databaseFactory.persistent;

  IdbDatabaseFactory(this._databaseFactory, this._path);

  String get name => IDB_IODB_DATABASE_MEMORY;


  @override
  Future<Database> open(String dbName, {int version, OnUpgradeNeededFunction onUpgradeNeeded, OnBlockedFunction onBlocked}) {

    // check params
    if ((version == null) != (onUpgradeNeeded == null)) {
      return new Future.error(new ArgumentError('version and onUpgradeNeeded must be specified together'));
    }
    if (version == 0) {
      return new Future.error(new ArgumentError('version cannot be 0'));
    } else if (version == null) {
      version = 1;
    }

    // name null no
    if (dbName == null) {
      return new Future.error(new ArgumentError('name cannot be null'));
    }

    _IodbDatabase db = new _IodbDatabase(this, dbName);

    return db.open(version, onUpgradeNeeded).then((_) {
      return db;
    });

  }

  Future<IdbFactory> deleteDatabase(String dbName, {void onBlocked(Event)}) {
    if (dbName == null) {
      return new Future.error(new ArgumentError('dbName cannot be null'));
    }
    return _databaseFactory.deleteDatabase(join(_path, dbName));
  }

  @override
  bool get supportsDatabaseNames {
    return false;
  }

  Future<List<String>> getDatabaseNames() {
    return null;
  }
}