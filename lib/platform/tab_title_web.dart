import 'package:web/web.dart' as web;

const _baseTitle = 'TourFlow';

void setUnreadBadgePlatform(int count) {
  web.document.title = count > 0 ? '($count) $_baseTitle' : _baseTitle;
}
