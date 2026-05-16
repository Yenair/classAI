enum CurriculumType { nerdc, cambridge, ccss }

extension CurriculumTypeX on CurriculumType {
  String get code {
    switch (this) {
      case CurriculumType.nerdc: return 'nerdc';
      case CurriculumType.cambridge: return 'cambridge';
      case CurriculumType.ccss: return 'ccss';
    }
  }
  String get displayName {
    switch (this) {
      case CurriculumType.nerdc: return 'NERDC (Nigeria)';
      case CurriculumType.cambridge: return 'Cambridge International';
      case CurriculumType.ccss: return 'CCSS (US Common Core)';
    }
  }
  String get latestVersion {
    switch (this) {
      case CurriculumType.nerdc: return 'nerdc_v2024';
      case CurriculumType.cambridge: return 'cambridge_v2025';
      case CurriculumType.ccss: return 'ccss_v2024';
    }
  }
}

enum SubscriptionTier { free, basic, standard, elite }

extension SubscriptionTierX on SubscriptionTier {
  int get offlineCredits {
    switch (this) {
      case SubscriptionTier.free: return 3;
      case SubscriptionTier.basic: return 5;
      case SubscriptionTier.standard: return 10;
      case SubscriptionTier.elite: return 20;
    }
  }
}
