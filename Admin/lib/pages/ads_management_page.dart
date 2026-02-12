import 'package:flutter/material.dart';
import 'package:brgy/services/ads_service.dart';
import 'package:brgy/model/advertisement.dart';
import 'package:brgy/widgets/ads/ad_card_widget.dart';
import 'package:brgy/widgets/ads/ad_preview_dialog.dart';
import 'package:brgy/pages/ad_add_edit_page.dart';

class AdsManagementPage extends StatefulWidget {
  const AdsManagementPage({super.key});

  @override
  State<AdsManagementPage> createState() => _AdsManagementPageState();
}

class _AdsManagementPageState extends State<AdsManagementPage> {
  Future<void> _onRefresh() async {
    setState(() {});
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  Future<void> _handleDelete(Advertisement ad) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Advertisement'),
        content: Text('Are you sure you want to delete "${ad.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await AdsService.deleteAd(ad.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Advertisement deleted successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _handleToggleEnabled(Advertisement ad) async {
    try {
      await AdsService.toggleEnabled(ad.id, !ad.isEnabled);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ad.isEnabled
                  ? 'Advertisement disabled'
                  : 'Advertisement enabled',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to toggle: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleReorder(Advertisement ad, bool moveUp) async {
    try {
      await AdsService.reorderAd(ad.id, moveUp);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to reorder: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ads Management'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add Ad',
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AdAddEditPage(),
                ),
              );
              if (result == true) {
                _onRefresh();
              }
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        child: StreamBuilder<List<Advertisement>>(
          stream: AdsService.getAdsStream(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error, size: 64, color: Colors.red),
                    const SizedBox(height: 16),
                    Text('Error loading ads: ${snapshot.error}'),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _onRefresh,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              );
            }

            final ads = snapshot.data ?? [];

            if (ads.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.campaign, size: 64, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    Text(
                      'No advertisements yet',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tap the + button to create your first ad',
                      style: TextStyle(color: Colors.grey[500]),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () async {
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const AdAddEditPage(),
                          ),
                        );
                        if (result == true) {
                          _onRefresh();
                        }
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Create Ad'),
                    ),
                  ],
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: ads.length,
              itemBuilder: (context, index) {
                final ad = ads[index];
                return AdCardWidget(
                  ad: ad,
                  onPreview: () {
                    showDialog(
                      context: context,
                      builder: (context) => AdPreviewDialog(ad: ad),
                    );
                  },
                  onEdit: () async {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => AdAddEditPage(ad: ad),
                      ),
                    );
                    if (result == true) {
                      _onRefresh();
                    }
                  },
                  onToggleEnabled: () => _handleToggleEnabled(ad),
                  onMoveUp: () => _handleReorder(ad, true),
                  onMoveDown: () => _handleReorder(ad, false),
                  onDelete: () => _handleDelete(ad),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

