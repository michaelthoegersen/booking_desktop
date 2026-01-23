final GoRouter appRouter = GoRouter(
  initialLocation: "/",
  routes: [
    ShellRoute(
      builder: (context, state, child) => AppShell(child: child),
      routes: [
        GoRoute(
          path: "/",
          builder: (context, state) => const DashboardPage(),
        ),

        // ✅ /new (blank) OR /new?id=UUID
        GoRoute(
          path: "/new",
          builder: (context, state) {
            final id = state.uri.queryParameters['id'];
            return NewOfferPage(offerId: id);
          },
        ),

        // ✅ /new/<uuid>  <-- DETTE ER DET DU MANGLER I RUNTIME
        GoRoute(
          path: "/new/:id",
          builder: (context, state) {
            final id = state.pathParameters['id']!;
            return NewOfferPage(offerId: id);
          },
        ),

        GoRoute(
          path: "/edit",
          builder: (context, state) => const EditOfferPage(),
        ),
        GoRoute(
          path: "/customers",
          builder: (context, state) => const CustomersPage(),
        ),
        GoRoute(
          path: "/settings",
          builder: (context, state) => const SettingsPage(),
        ),
      ],
    ),
  ],
);