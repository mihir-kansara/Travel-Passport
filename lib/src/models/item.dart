class Item {
  final String id;
  final String title;
  final String subtitle;
  final String imageUrl;
  final DateTime createdAt;
  int likes;

  Item({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.createdAt,
    this.likes = 0,
  });
}
