class FemaleExpert {
  final String id;
  final String nickname;
  final int pricePerMin;
  final String languages;
  final double rating;
  final bool isOnline;

  const FemaleExpert({
    required this.id,
    required this.nickname,
    required this.pricePerMin,
    required this.languages,
    required this.rating,
    required this.isOnline,
  });

  int get displayAge {
    if (id.isEmpty) return 22; // Safe fallback
    // .abs() ensures no negative numbers. % 6 gives 0-5. Adding 20 gives 20-25.
    return (id.hashCode.abs() % 6) + 20; 
  }

  static List<FemaleExpert> get mockExperts {
    return const [
      FemaleExpert(
        id: "expert_1",
        nickname: "Seerat",
        pricePerMin: 5,
        languages: "Hindi - Punjabi",
        rating: 4.5,
        isOnline: true,
      ),
      FemaleExpert(
        id: "expert_2",
        nickname: "maya",
        pricePerMin: 5,
        languages: "Hindi-Kannada",
        rating: 4.8,
        isOnline: true,
      ),
      FemaleExpert(
        id: "expert_3",
        nickname: "Archana gupta",
        pricePerMin: 5,
        languages: "Hindi - Punjabi",
        rating: 4.6,
        isOnline: true,
      ),
      FemaleExpert(
        id: "expert_4",
        nickname: "Simmi",
        pricePerMin: 5,
        languages: "Hindi",
        rating: 4.7,
        isOnline: true,
      ),
      FemaleExpert(
        id: "expert_5",
        nickname: "divya",
        pricePerMin: 5,
        languages: "Hindi",
        rating: 4.4,
        isOnline: true,
      ),
      FemaleExpert(
        id: "expert_6",
        nickname: "Poonam",
        pricePerMin: 5,
        languages: "Hindi-Gujarati",
        rating: 4.9,
        isOnline: true,
      ),
      FemaleExpert(
        id: "expert_7",
        nickname: "Aanya",
        pricePerMin: 5,
        languages: "Hindi-English",
        rating: 4.6,
        isOnline: true,
      ),
      FemaleExpert(
        id: "expert_8",
        nickname: "Sanjuli",
        pricePerMin: 5,
        languages: "Hindi-Rajasthani",
        rating: 4.7,
        isOnline: false,
      ),
    ];
  }
}
