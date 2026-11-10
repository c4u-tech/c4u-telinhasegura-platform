import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../auth/auth_api.dart' show PlatformRole;
import '../design/field_layout.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import 'routes.dart';

/// A place of several items on a large window: its list in a pane at the
/// start, beside the rail, then a reed hairline, then the item the list
/// opened. No card and no shadow: the hairline does the dividing.
class ListDetail extends StatelessWidget {
  const ListDetail({
    super.key,
    required this.list,
    required this.detail,
    this.listWidth = ShellSizes.listPaneWidth,
  });

  /// The list pane's width at [textScale]: from a large text size on it
  /// grows with the text, so a row's title never breaks inside a word.
  static double listWidthAt(double textScale) =>
      ShellSizes.listPaneWidth * math.max(1, textScale / 1.5);

  /// Whether a content area [width] wide holds the list at [textScale]
  /// and, beside it, the detail's whole column with its margins.
  static bool fits(double width, double textScale) =>
      width - listWidthAt(textScale) - 1 - (Space.xxxl + Space.xl) >=
      FieldSizes.columnMaxWidth;

  final double listWidth;

  static const listKey = Key('list-pane');
  static const detailKey = Key('detail-pane');
  static const hairlineKey = Key('list-detail-hairline');

  final Widget list;
  final Widget detail;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SizedBox(
        key: listKey,
        width: listWidth,
        // Read before the detail: the list is where the reader chooses.
        child: FocusTraversalGroup(child: list),
      ),
      VerticalDivider(
        key: hairlineKey,
        width: 1,
        thickness: 1,
        color: context.palette.outline.withValues(alpha: .5),
      ),
      Expanded(
        child: KeyedSubtree(
          key: detailKey,
          child: FocusTraversalGroup(child: detail),
        ),
      ),
    ],
  );
}

/// Which item of a place a path opens, and which paths leave the list
/// for the whole content area. The path is the one source of truth, so a
/// link, a resize or a rotation lands on the same item.
abstract final class Panes {
  /// The places shown as a list beside their item.
  static const roots = {Routes.family, Routes.account, Routes.staffHome};

  /// What asks for the reader's whole attention takes the whole content
  /// area: the PIN, deleting the family or the account, and turning on
  /// the second factor.
  static bool isFocus(String path) =>
      path == Routes.setPin ||
      path == Routes.deleteFamily ||
      path == Routes.accountDelete ||
      _under(Routes.accountMfaEnroll, path);

  /// The items of each place, in the order their list shows them.
  static const _family = [
    Routes.children,
    Routes.adults,
    Routes.invitations,
    Routes.kidMode,
  ];
  static const _account = [
    Routes.accountEmail,
    Routes.accountPassword,
    Routes.accountMfa,
    Routes.accountSessions,
    Routes.accountData,
  ];
  static const _staff = [
    Routes.curation,
    Routes.packs,
    Routes.heldVideos,
    Routes.accounts,
    Routes.team,
    Routes.audit,
    Routes.auditSample,
    Routes.numbers,
  ];

  /// Every item's own path: the first level of what the detail shows.
  static final _items = {..._family, ..._account, ..._staff};

  /// Whether a page, named by its route's path pattern, is a place's root
  /// or an item's first level, which needs no back beside the list.
  static bool isPaneRoot(String pattern) =>
      roots.contains(pattern) || _items.contains(pattern);

  /// The item a place's root opens on arrival: the children, the email,
  /// and the team's first row for the [roles] held.
  static String? firstOf(String root, Set<PlatformRole>? roles) =>
      switch (root) {
        Routes.family => Routes.children,
        Routes.account => Routes.accountEmail,
        Routes.staffHome => switch (roles) {
          null => null,
          final r when r.contains(PlatformRole.curator) => Routes.curation,
          final r
              when r.contains(PlatformRole.moderator) ||
                  r.contains(PlatformRole.admin) =>
            Routes.heldVideos,
          _ => null,
        },
        _ => null,
      };

  /// The item [path] lies under, its root opening the first: a child's
  /// time, videos and page are the children's, the kid-mode screens the
  /// kid mode's, a review the queue's.
  static String? itemOf(String path, Set<PlatformRole>? roles) {
    if (roots.contains(path)) return firstOf(path, roles);
    if (_under(Routes.screenTime, path) || _under(Routes.familyVideos, path)) {
      return Routes.children;
    }
    for (final item in _items) {
      if (_under(item, path)) return item;
    }
    return null;
  }

  static bool _under(String root, String path) =>
      path == root || path.startsWith('$root/');
}

/// A place's root as a page of its own navigator. Beside the list on a
/// large window it is the detail's ground: at the root's own path it
/// shows the [first] item, and under an item's page nothing, since the
/// list pane already shows the root; elsewhere it is the root itself.
class ListRoot extends StatelessWidget {
  const ListRoot({
    super.key,
    required this.path,
    required this.root,
    required this.first,
    required this.child,
  });

  /// The location's path, from the route (never read from the router
  /// inside a page that a redirect may be replacing).
  final String path;
  final String root;
  final WidgetBuilder first;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (ShellFrame.maybeOf(context)?.pane != Pane.detail) return child;
    return path == root ? first(context) : const SizedBox.shrink();
  }
}
