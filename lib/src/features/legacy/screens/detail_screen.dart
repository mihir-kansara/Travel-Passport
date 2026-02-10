import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_application_trial/src/models/item.dart';
import 'package:flutter_application_trial/src/widgets/app_scaffold.dart';

class DetailScreen extends StatefulWidget {
  final Item item;
  const DetailScreen({super.key, required this.item});

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  late int likes;

  @override
  void initState() {
    super.initState();
    likes = widget.item.likes;
  }

  void _toggleLike() {
    setState(() => likes = likes + 1);
  }

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    return AppScaffold(
      title: it.title,
      padding: EdgeInsets.zero,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CachedNetworkImage(
              imageUrl: it.imageUrl,
              width: double.infinity,
              height: 320,
              fit: BoxFit.cover,
              placeholder: (c, s) =>
                  Container(height: 320, color: Colors.grey[200]),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    it.title,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    it.subtitle,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      IconButton(
                        onPressed: _toggleLike,
                        icon: const Icon(Icons.favorite_border),
                      ),
                      Text('$likes likes'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
