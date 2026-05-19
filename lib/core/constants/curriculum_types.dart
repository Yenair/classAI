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

/// Nigerian NERDC (National Educational Research and Development Council)
/// subjects taught in Nigerian secondary schools (JSS and SSS).
const List<String> nerdcSubjects = [
  'English Studies',
  'Mathematics',
  'Basic Science',
  'Social Studies',
  'Christian Religious Studies',
  'Islamic Religious Studies',
  'French',
  'Home Economics',
  'Agricultural Science',
  'Civic Education',
  'Physical Education',
  'Business Studies',
  'Computer Studies',
  'Fine Arts',
  'Music',
  'Hausa',
  'Igbo',
  'Yoruba',
];

/// Default subjects pre-selected for a new school.
const List<String> defaultSubjects = [
  'English Studies',
  'Mathematics',
  'Basic Science',
  'Social Studies',
  'Christian Religious Studies',
  'Civic Education',
];
