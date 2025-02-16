library sembast.doc_test;

import 'dart:convert';

import 'package:pedantic/pedantic.dart';

// ignore: implementation_imports
import 'package:sembast/src/api/v2/sembast.dart';
// ignore: implementation_imports
import 'package:sembast/src/memory/database_factory_memory.dart';
import 'package:sembast/utils/database_utils.dart';
import 'package:sembast/utils/sembast_import_export.dart';
import 'package:sembast/utils/value_utils.dart';

import 'test_common.dart';

void main() {
  defineTests(memoryDatabaseContext);
}

void defineTests(DatabaseTestContext ctx) {
  var factory = ctx.factory;

  group('doc', () {
    Database? db;

    setUp(() async {});

    tearDown(() async {
      if (db != null) {
        await db!.close();
        db = null;
      }
    });

    test('store', () async {
      db = await setupForTest(ctx, 'doc/store.db');

      // Simple writes
      {
        var store = StoreRef.main();

        await store.record('title').put(db!, 'Simple application');
        await store.record('version').put(db!, 10);
        await store.record('settings').put(db!, {'offline': true});
        var title = await store.record('title').get(db!) as String?;
        var version = await store.record('version').get(db!) as int?;
        var settings = await store.record('settings').get(db!) as Map?;

        await store.record('version').delete(db!);

        unused([title, version, settings]);
      }

      // records
      {
        var store = intMapStoreFactory.store();
        var key = await store.add(db!, {
          'path': {'sub': 'my_value'},
          'with.dots': 'my_other_value'
        });

        var record = (await store.record(key).getSnapshot(db!))!;
        var value = record['path.sub'];
        // value = 'my_value'
        var value2 = record[FieldKey.escape('with.dots')];
        // value2 = 'my_other_value'

        expect(value, 'my_value');
        expect(value2, 'my_other_value');
      }

      {
        await db!.close();
        db = await setupForTest(ctx, 'doc/store.db');

        var store = StoreRef<int, String>.main();
        // Auto incrementation is built-in
        var key1 = await store.add(db!, 'value1');
        var key2 = await store.add(db!, 'value2');
        // key1 = 1, key2 = 2...
        expect([key1, key2], [1, 2]);

        await db!.transaction((txn) async {
          await store.add(txn, 'value1');
          await store.add(txn, 'value2');
        });
      }
      {
        var path = db!.path;
        await db!.close();

        // Migration

        // Open the database with version 1
        db = await factory.openDatabase(path, version: 1);

        // ...

        await db!.close();

        db = await factory.openDatabase(path, version: 2,
            onVersionChanged: (db, oldVersion, newVersion) {
          if (oldVersion == 1) {
            // Perform changes before the database is opened
          }
        });
      }
      {
        // Autogenerated id

        // Use the main store for storing map data with an auto-generated
        // int key
        var store = intMapStoreFactory.store();

        // Add the data and get the key
        var key = await store.add(db!, {'value': 'test'});

        // Retrieve the record
        var record = store.record(key);
        var readMap = (await record.get(db!))!;

        expect(readMap, {'value': 'test'});

        // Update the record
        await record.put(db!, {'other_value': 'test2'}, merge: true);

        readMap = (await record.get(db!))!;

        expect(readMap, {'value': 'test', 'other_value': 'test2'});

        // Track record changes
        var subscription = record.onSnapshot(db!).listen((snapshot) {
          // if snapshot is null, the record is not present or has been
          // deleted

          // ...
        });
        // cancel subscription. Important! not doing this might lead to
        // memory leaks
        unawaited(subscription.cancel());
      }

      {
        // Use the main store for storing key values as String
        var store = StoreRef<String, String>.main();

        // Writing the data
        await store.record('username').put(db!, 'my_username');
        await store.record('url').put(db!, 'my_url');

        // Reading the data
        var url = await store.record('url').get(db!);
        var username = await store.record('username').get(db!);

        await db!.transaction((txn) async {
          url = await store.record('url').get(txn);
          username = await store.record('username').get(txn);
        });

        unused([url, username]);
      }

      {
        // Use the main store, key being an int, value a Map<String, Object?>
        // Lint warnings will warn you if you try to use different types
        var store = intMapStoreFactory.store();
        var key = await store.add(db!, {'offline': true});
        var value = (await store.record(key).get(db!))!;

        // specify a key
        key = 1234;
        await store.record(key).put(db!, {'offline': true});

        unused(value);
      }

      {
        // Use the animals store using Map records with int keys
        var store = intMapStoreFactory.store('animals');

        // Store some objects
        await db!.transaction((txn) async {
          await store.add(txn, {'name': 'fish'});
          await store.add(txn, {'name': 'cat'});
          await store.add(txn, {'name': 'dog'});
        });

        // Look for any animal 'greater than' (alphabetically) 'cat'
        // ordered by name
        var finder = Finder(
            filter: Filter.greaterThan('name', 'cat'),
            sortOrders: [SortOrder('name')]);
        var records = await store.find(db!, finder: finder);

        expect(records.length, 2);
        expect(records[0]['name'], 'dog');
        expect(records[1]['name'], 'fish');

        // Find the first record matching the finder
        var record = (await store.findFirst(db!, finder: finder))!;
        // Get the record id
        var recordId = record.key;
        // Get the record value
        var recordValue = record.value;

        expect(recordId, 3);
        expect(recordValue, {'name': 'dog'});

        // Track query changes
        var query = store.query(finder: finder);
        var subscription = query.onSnapshots(db!).listen((snapshots) {
          // snapshots always contains the list of records matching the query

          // ...
        });
        // cancel subscription. Important! not doing this might lead to
        // memory leaks
        unawaited(subscription.cancel());
      }

      {
        final store = intMapStoreFactory.store('animals');
        await store.drop(db!);

        // Store some objects
        late int key1, key2, key3;
        await db!.transaction((txn) async {
          key1 = await store.add(txn, {'name': 'fish'});
          key2 = await store.add(txn, {'name': 'cat'});
          key3 = await store.add(txn, {'name': 'dog'});
        });

        // Read by key
        var value = (await store.record(key1).get(db!))!;

        // read values are immutable/read-only. If you want to modify it you
        // should clone it first

        // the following will throw an exception
        try {
          value['name'] = 'nice fish';
          throw 'should fail';
        } on StateError catch (_) {}

        // clone the resulting map for modification
        var map = cloneMap(value);
        map['name'] = 'nice fish';

        // existing remain un changed
        expect(await store.record(key1).get(db!), {'name': 'fish'});

// Read 2 records by key
        var records = await store.records([key2, key3]).get(db!);
        expect(records[0], {'name': 'cat'});
        expect(records[1], {'name': 'dog'});

        {
          // Look for any animal 'greater than' (alphabetically) 'cat'
          // ordered by name
          var finder = Finder(
              filter: Filter.greaterThan('name', 'cat'),
              sortOrders: [SortOrder('name')]);
          var records = await store.find(db!, finder: finder);

          expect(records.length, 2);
          expect(records[0]['name'], 'dog');
          expect(records[1]['name'], 'fish');
        }
        {
          // Look for the last created record
          var finder = Finder(sortOrders: [SortOrder(Field.key, false)]);
          var record = (await store.findFirst(db!, finder: finder))!;

          expect(record['name'], 'dog');
        }
        {
          // Look for the one after `cat`
          var finder = Finder(
              sortOrders: [SortOrder('name', true)],
              start: Boundary(values: ['cat']));
          var record = (await store.findFirst(db!, finder: finder))!;
          expect(record['name'], 'dog');

          record = (await store.findFirst(db!, finder: finder))!;

          // record snapshot are read-only.
          // If you want to modify it you should clone it
          var map = cloneMap(record.value);
          map['name'] = 'nice dog';

          // existing remains unchanged
          record = (await store.findFirst(db!, finder: finder))!;
          expect(record['name'], 'dog');
        }
        {
          // Upsert multiple records
          var records = store.records([key1, key2]);
          var result = await (records.put(
              db!,
              [
                {'value': 'new value for key1'},
                {'value_other': 'new value for key2'}
              ],
              merge: true));
          expect(result, [
            {'name': 'fish', 'value': 'new value for key1'},
            {'name': 'cat', 'value_other': 'new value for key2'}
          ]);
        }
        {
          // Our shop store
          var store = intMapStoreFactory.store('shop');

          await db!.transaction((txn) async {
            await store.add(txn, {'name': 'Lamp', 'price': 10});
            await store.add(txn, {'name': 'Chair', 'price': 10});
            await store.add(txn, {'name': 'Deco', 'price': 5});
            await store.add(txn, {'name': 'Table', 'price': 35});
          });

          // Look for object after Chair 10 (ordered by price then name) so
          // should the the Lamp 10
          var finder = Finder(
              sortOrders: [SortOrder('price'), SortOrder('name')],
              start: Boundary(values: [10, 'Chair']));
          var record = (await store.findFirst(db!, finder: finder))!;
          expect(record['name'], 'Lamp');

          // You can also specify to look after a given record
          finder = Finder(
              sortOrders: [SortOrder('price'), SortOrder('name')],
              start: Boundary(record: record));
          record = (await store.findFirst(db!, finder: finder))!;
          // After the lamp the more expensive one is the Table
          expect(record['name'], 'Table');

          {
            // The test before the doc..

            // Delete all record with a price greater then 10
            var filter = Filter.greaterThan('price', 10);
            var finder = Finder(filter: filter);
            final deleted = await store.delete(db!, finder: finder);
            expect(deleted, 1);

            // Clear all records from the store
            await store.delete(db!);
          }

          {
            // Delete all record with a price greater then 10
            var filter = Filter.greaterThan('price', 10);
            var finder = Finder(filter: filter);
            await store.delete(db!, finder: finder);

            // Clear all records from the store
            await store.delete(db!);
          }
        }
      }
    });

    test('New 1.15 shop_file_format', () async {
      db = await setupForTest(ctx, 'doc/new_1.15_shop_file_format.db');
      {
        // Our shop store sample data
        StoreRef<int?, Map<String, Object?>> store =
            intMapStoreFactory.store('shop');

        int? lampKey;
        int? chairKey;
        await db!.transaction((txn) async {
          // Add 2 records
          lampKey = await store.add(txn, {'name': 'Lamp', 'price': 10});
          chairKey = await store.add(txn, {'name': 'Chair', 'price': 15});
        });

        // update the price of the lamp record
        await store.record(lampKey).update(db!, {'price': 12});

        // Avoid unused warning that make the code easier-to read
        expect(chairKey, 2);

        var content = await exportDatabase(db!);
        expect(
            content,
            {
              'sembast_export': 1,
              'version': 1,
              'stores': [
                {
                  'name': 'shop',
                  'keys': [1, 2],
                  'values': [
                    {'name': 'Lamp', 'price': 12},
                    {'name': 'Chair', 'price': 15}
                  ]
                }
              ]
            },
            reason: jsonEncode(content));

        // Save as text
        var saved = jsonEncode(content);

        // await db.close();
        var databaseFactory = databaseFactoryMemory;

        // Import the data
        var map = jsonDecode(saved) as Map;
        var importedDb =
            await importDatabase(map, databaseFactory, 'imported.db');

        // Check the lamp price
        expect((await store.record(lampKey).get(importedDb))!['price'], 12);
      }
    });

    test('Write data', () async {
      db = await setupForTest(ctx, 'doc/write_data.db');
      {
        // Our product store.
        StoreRef<int?, Map<String, Object?>> store =
            intMapStoreFactory.store('product');

        int? lampKey;
        int? chairKey;
        await db!.transaction((txn) async {
          // Add 2 records
          lampKey = await store.add(txn, {'name': 'Lamp', 'price': 10});
          chairKey = await store.add(txn, {'name': 'Chair', 'price': 15});
        });

        expect(await store.record(lampKey).get(db!),
            {'name': 'Lamp', 'price': 10});

        // update the price of the lamp record
        await store.record(lampKey).update(db!, {'price': 12});

        var tableKey = 1000578;
        // Update or create the table product with key 1000578
        await store.record(tableKey).put(db!, {'name': 'Table', 'price': 120});

        // Avoid unused warning that make the code easier-to read
        expect(chairKey, 2);
      }
    });

    test('Preload data', () async {
      var path = dbPathFromName('doc/preload_data.db');
      await factory.deleteDatabase(path);
      {
        // Our shop store sample data
        var store = intMapStoreFactory.store('shop');

        var db = await factory.openDatabase(path, version: 1,
            onVersionChanged: (db, oldVersion, newVersion) async {
          // If the db does not exist, create some data
          if (oldVersion == 0) {
            await store.add(db, {'name': 'Lamp', 'price': 10});
            await store.add(db, {'name': 'Chair', 'price': 15});
          }
        });

        expect(await store.query().getSnapshots(db), hasLength(2));
      }
    });

    test('migration data', () async {
      var path = dbPathFromName('doc/migration.db');
      await factory.deleteDatabase(path);
      {
        // By default, unless specified a new database has version 1
        // after being opened. While this value seems odd, it actually enforce
        // migration during `onVersionChanged`
        await factory.deleteDatabase(path);
        var db = await factory.openDatabase(path);
        expect(db.version, 1);
        await db.close();

        // It has version 0 if created in onVersionChanged
        await factory.deleteDatabase(path);
        db = await factory.openDatabase(path, version: 1,
            onVersionChanged: (db, oldVersion, newVersion) async {
          expect(oldVersion, 0);
          expect(newVersion, 1);
        });
        expect(db.version, 1);
        await db.close();

        // You can perform basic data migration, by specifying a version
        var store = stringMapStoreFactory.store('product');
        var demoProductRecord1 = store.record('demo_product_1');
        var demoProductRecord2 = store.record('demo_product_2');
        var demoProductRecord3 = store.record('demo_product_3');
        await factory.deleteDatabase(path);
        db = await factory.openDatabase(path, version: 1,
            onVersionChanged: (db, oldVersion, newVersion) async {
          // If the db does not exist, create some data
          if (oldVersion == 0) {
            await demoProductRecord1
                .put(db, {'name': 'Demo product 1', 'price': 10});
            await demoProductRecord2
                .put(db, {'name': 'Demo product 2', 'price': 100});
          }
        });

        Future<List<Map<String, Object?>>> getProductMaps() async {
          var results = await store
              .stream(db)
              .map(((snapshot) => Map<String, Object?>.from(snapshot.value)
                ..['id'] = snapshot.key))
              .toList();
          return results;
        }

        expect(await getProductMaps(), [
          {'name': 'Demo product 1', 'price': 10, 'id': 'demo_product_1'},
          {'name': 'Demo product 2', 'price': 100, 'id': 'demo_product_2'}
        ]);
        await db.close();

        // You can perform update migration, by specifying a new version
        // Here in version 2, we want to update the price of a demo product
        db = await factory.openDatabase(path, version: 2,
            onVersionChanged: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            // Creation
            await demoProductRecord1
                .put(db, {'name': 'Demo product 1', 'price': 15});
          }

          // Creation 0 -> 1
          if (oldVersion < 1) {
            await demoProductRecord2
                .put(db, {'name': 'Demo product 2', 'price': 100});
          } else if (oldVersion < 2) {
            // Migration 1 -> 2
            // no action needed.
          }
        });
        expect(await getProductMaps(), [
          {'name': 'Demo product 1', 'price': 15, 'id': 'demo_product_1'},
          {'name': 'Demo product 2', 'price': 100, 'id': 'demo_product_2'}
        ]);

        // Let's add a new demo product
        await demoProductRecord3
            .put(db, {'name': 'Demo product 3', 'price': 1000});
        await db.close();

        // Let say you want to tag your existing demo product as demo by adding
        // a tag propery
        db = await factory.openDatabase(path, version: 3,
            onVersionChanged: (db, oldVersion, newVersion) async {
          if (oldVersion < 3) {
            // Creation
            await demoProductRecord1.put(
                db, {'name': 'Demo product 1', 'price': 15, 'tag': 'demo'});
          }

          // Creation 0 -> 1
          if (oldVersion < 1) {
            await demoProductRecord2.put(
                db, {'name': 'Demo product 2', 'price': 100, 'tag': 'demo'});
          } else if (oldVersion < 3) {
            // Migration 1 -> 3
            // Add demo tag to all records containing 'demo' in their name
            // no action needed.
            await store.update(db, {'tag': 'demo'},
                finder: Finder(
                    filter: Filter.custom((record) => (record['name'] as String)
                        .toLowerCase()
                        .contains('demo'))));
          }
        });
        expect(await getProductMaps(), [
          {
            'name': 'Demo product 1',
            'price': 15,
            'tag': 'demo',
            'id': 'demo_product_1'
          },
          {
            'name': 'Demo product 2',
            'price': 100,
            'tag': 'demo',
            'id': 'demo_product_2'
          },
          {
            'name': 'Demo product 3',
            'price': 1000,
            'tag': 'demo',
            'id': 'demo_product_3'
          }
        ]);
        await db.close();
      }
    });
    test('database_utils', () async {
      db = await setupForTest(ctx, 'doc/database_utils.db');

      // Get the list of non-empty store names
      var names = getNonEmptyStoreNames(db!);

      expect(names, []);
    });
  });
}
