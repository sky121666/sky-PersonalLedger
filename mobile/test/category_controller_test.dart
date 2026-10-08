import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/features/categories/application/category_controller.dart';
import 'package:personal_ledger/features/categories/data/category.dart';
import 'package:personal_ledger/features/categories/data/category_repository.dart';

void main() {
  test(
    'a slow expense response cannot be shown as income categories',
    () async {
      final repository = _ControlledRepository();
      final container = ProviderContainer(
        overrides: [categoryRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      final controller = container.read(
        categoryListControllerProvider.notifier,
      );
      final income = controller.setType(CategoryType.income);
      expect(repository.types, [CategoryType.expense, CategoryType.income]);
      repository.responses[1].complete(
        CategoryListResult(
          categories: [
            Category.fromJson({'id': 'salary', 'name': '工资', 'type': 'income'}),
          ],
        ),
      );
      await income;
      repository.responses[0].complete(
        CategoryListResult(
          categories: [
            Category.fromJson({'id': 'food', 'name': '餐饮', 'type': 'expense'}),
          ],
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final state = container.read(categoryListControllerProvider).requireValue;
      expect(state.type, CategoryType.income);
      expect(state.categories.single.id, 'salary');
      expect(state.categories.single.type, CategoryType.income);
    },
  );
}

class _ControlledRepository implements CategoryRepository {
  final types = <CategoryType>[];
  final responses = <Completer<CategoryListResult>>[];

  @override
  Future<CategoryListResult> list(CategoryType type) {
    types.add(type);
    final response = Completer<CategoryListResult>();
    responses.add(response);
    return response.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
