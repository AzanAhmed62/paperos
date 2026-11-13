import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:paperos/app/router.dart';

String pathOf(GoRouter router) =>
    router.routeInformationProvider.value.uri.path;

void main() {
  test('a new router starts at Paper Home', () {
    final GoRouter router = createAppRouter();
    addTearDown(router.dispose);

    expect(pathOf(router), Routes.home);
  });

  test('two routers do not share navigation state', () {
    final GoRouter first = createAppRouter();
    final GoRouter second = createAppRouter();
    addTearDown(first.dispose);
    addTearDown(second.dispose);

    first.go(Routes.library);

    expect(pathOf(first), Routes.library);
    expect(pathOf(second), Routes.home);
  });

  test('recreating the provider discards the previous location', () {
    final ProviderContainer first = ProviderContainer();
    final GoRouter firstRouter = first.read(appRouterProvider);
    firstRouter.go(Routes.settings);
    expect(pathOf(firstRouter), Routes.settings);
    first.dispose();

    final ProviderContainer second = ProviderContainer();
    addTearDown(second.dispose);
    final GoRouter secondRouter = second.read(appRouterProvider);

    expect(pathOf(secondRouter), Routes.home);
  });
}
