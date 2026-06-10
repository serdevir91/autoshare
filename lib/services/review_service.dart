import 'package:in_app_review/in_app_review.dart';
import 'package:url_launcher/url_launcher.dart';

class ReviewService {
  const ReviewService();

  Future<bool> requestInAppReviewWithFallback() async {
    final inAppReview = InAppReview.instance;

    try {
      if (await inAppReview.isAvailable()) {
        await inAppReview.requestReview();
        return true;
      }
    } catch (_) {
      // Fall through to store listing fallback.
    }

    return openStoreReviewPage();
  }

  Future<bool> openStoreReviewPage() async {
    final inAppReview = InAppReview.instance;
    try {
      await inAppReview.openStoreListing();
      return true;
    } catch (_) {
      // Fallback for environments where in_app_review listing call fails.
    }

    // Direct url fallback
    final packageId = 'com.autoshare.app';
    final marketUri = Uri.parse('market://details?id=$packageId');
    final webUri = Uri.parse('https://play.google.com/store/apps/details?id=$packageId');

    try {
      if (await launchUrl(marketUri, mode: LaunchMode.externalApplication)) {
        return true;
      }
    } catch (_) {}

    try {
      if (await launchUrl(webUri, mode: LaunchMode.externalApplication)) {
        return true;
      }
    } catch (_) {}

    return false;
  }
}
