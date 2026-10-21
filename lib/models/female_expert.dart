class FemaleExpert {
  final String id;
  final String nickname;
  final int pricePerMin;
  final String languages;
  final double rating;
  final bool isOnline;
  final int age;
  final String? avatarUrl;
  final int avatarIndex;

  const FemaleExpert({
    required this.id,
    required this.nickname,
    required this.pricePerMin,
    required this.languages,
    required this.rating,
    required this.isOnline,
    this.age = 22,
    this.avatarUrl,
    this.avatarIndex = 1,
  });

  int get displayAge => age;

  static List<FemaleExpert> get mockExperts {
    return const [
      FemaleExpert(
        id: "expert_1",
        nickname: "Seerat",
        pricePerMin: 4,
        languages: "Hindi - Punjabi",
        rating: 4.5,
        isOnline: true,
      ),
      FemaleExpert(
        id: "expert_2",
        nickname: "maya",
        pricePerMin: 4,
        languages: "Hindi-Kannada",
        rating: 4.8,
        isOnline: true,
      ),
      FemaleExpert(
        id: "expert_3",
        nickname: "Archana gupta",
        pricePerMin: 4,
        languages: "Hindi - Punjabi",
        rating: 4.6,
        isOnline: true,
      ),
      FemaleExpert(
        id: "expert_4",
        nickname: "Simmi",
        pricePerMin: 4,
        languages: "Hindi",
        rating: 4.7,
        isOnline: true,
      ),
      FemaleExpert(
        id: "expert_5",
        nickname: "divya",
        pricePerMin: 4,
        languages: "Hindi",
        rating: 4.4,
        isOnline: true,
      ),
      FemaleExpert(
        id: "expert_6",
        nickname: "Poonam",
        pricePerMin: 4,
        languages: "Hindi-Gujarati",
        rating: 4.9,
        isOnline: true,
      ),
      FemaleExpert(
        id: "expert_7",
        nickname: "Aanya",
        pricePerMin: 4,
        languages: "Hindi-English",
        rating: 4.6,
        isOnline: true,
      ),
      FemaleExpert(
        id: "expert_8",
        nickname: "Sanjuli",
        pricePerMin: 4,
        languages: "Hindi-Rajasthani",
        rating: 4.7,
        isOnline: false,
      ),
    ];
  }
}
