import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:brgy/model/advertisement.dart';

class AdCardWidget extends StatelessWidget {
  final Advertisement ad;
  final VoidCallback onPreview;
  final VoidCallback onEdit;
  final VoidCallback onToggleEnabled;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onDelete;

  const AdCardWidget({
    super.key,
    required this.ad,
    required this.onPreview,
    required this.onEdit,
    required this.onToggleEnabled,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      elevation: 2,
      child: InkWell(
        onTap: onPreview,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Thumbnail and title row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Thumbnail
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: ad.imageUrls.isNotEmpty
                        ? kIsWeb
                            ? Image.network(
                                ad.imageUrls.first,
                                width: 80,
                                height: 80,
                                fit: BoxFit.cover,
                                loadingBuilder: (context, child, loadingProgress) {
                                  if (loadingProgress == null) return child;
                                  return Container(
                                    width: 80,
                                    height: 80,
                                    color: Colors.grey[300],
                                    child: const Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  );
                                },
                                errorBuilder: (context, error, stackTrace) => Container(
                                  width: 80,
                                  height: 80,
                                  color: Colors.grey[300],
                                  child: const Icon(Icons.image_not_supported),
                                ),
                              )
                            : CachedNetworkImage(
                                imageUrl: ad.imageUrls.first,
                                width: 80,
                                height: 80,
                                fit: BoxFit.cover,
                                placeholder: (context, url) => Container(
                                  width: 80,
                                  height: 80,
                                  color: Colors.grey[300],
                                  child: const Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                ),
                                errorWidget: (context, url, error) => Container(
                                  width: 80,
                                  height: 80,
                                  color: Colors.grey[300],
                                  child: const Icon(Icons.image_not_supported),
                                ),
                              )
                        : Container(
                            width: 80,
                            height: 80,
                            color: Colors.grey[300],
                            child: const Icon(Icons.image),
                          ),
                  ),
                  const SizedBox(width: 12),
                  // Title and description
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ad.title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          ad.description,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Status badges and priority
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  _buildStatusBadge(),
                  if (ad.isScheduled) _buildScheduledBadge(),
                  if (ad.isExpired) _buildExpiredBadge(),
                  Chip(
                    label: Text('Priority: ${ad.priority}'),
                    labelStyle: const TextStyle(fontSize: 10),
                    padding: EdgeInsets.zero,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Analytics
              Row(
                children: [
                  Icon(Icons.visibility, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    '${ad.impressions}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const SizedBox(width: 16),
                  Icon(Icons.mouse, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    '${ad.clicks}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Action buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    icon: const Icon(Icons.visibility, size: 20),
                    tooltip: 'Preview',
                    onPressed: onPreview,
                    color: Colors.blue,
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit, size: 20),
                    tooltip: 'Edit',
                    onPressed: onEdit,
                    color: Colors.orange,
                  ),
                  IconButton(
                    icon: Icon(
                      ad.isEnabled ? Icons.toggle_on : Icons.toggle_off,
                      size: 24,
                    ),
                    tooltip: ad.isEnabled ? 'Disable' : 'Enable',
                    onPressed: onToggleEnabled,
                    color: ad.isEnabled ? Colors.green : Colors.grey,
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_upward, size: 20),
                    tooltip: 'Move Up',
                    onPressed: onMoveUp,
                    color: Colors.purple,
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_downward, size: 20),
                    tooltip: 'Move Down',
                    onPressed: onMoveDown,
                    color: Colors.purple,
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, size: 20),
                    tooltip: 'Delete',
                    onPressed: onDelete,
                    color: Colors.red,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge() {
    return Chip(
      label: Text(ad.isEnabled ? 'Enabled' : 'Disabled'),
      labelStyle: const TextStyle(fontSize: 10),
      backgroundColor: ad.isEnabled ? Colors.green[100] : Colors.red[100],
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Widget _buildScheduledBadge() {
    return Chip(
      label: const Text('Scheduled'),
      labelStyle: const TextStyle(fontSize: 10),
      backgroundColor: Colors.blue[100],
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Widget _buildExpiredBadge() {
    return Chip(
      label: const Text('Expired'),
      labelStyle: const TextStyle(fontSize: 10),
      backgroundColor: Colors.orange[100],
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

