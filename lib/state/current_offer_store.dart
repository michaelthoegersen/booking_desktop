import 'package:flutter/material.dart';
import '../models/offer_draft.dart';
import '../services/offer_storage_service.dart';

class CurrentOfferStore {
  static final ValueNotifier<OfferDraft?> current =
      ValueNotifier<OfferDraft?>(null);

  /// Last offer fra DB og push til UI
  static Future<void> load(String id) async {
    final offer = await OfferStorageService.loadDraft(id);
    current.value = offer;
  }

  /// Sett direkte (etter save)
  static void set(OfferDraft offer) {
    current.value = offer;
  }

  static void clear() {
    current.value = null;
  }
}