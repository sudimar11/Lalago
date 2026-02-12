import 'dart:io';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:brgy/model/advertisement.dart';
import 'package:brgy/services/ads_service.dart';

class AdAddEditPage extends StatefulWidget {
  final Advertisement? ad;

  const AdAddEditPage({super.key, this.ad});

  @override
  State<AdAddEditPage> createState() => _AdAddEditPageState();
}

class _AdAddEditPageState extends State<AdAddEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priorityController = TextEditingController();
  final _restaurantIdController = TextEditingController();
  final _imagePicker = ImagePicker();

  bool _isEnabled = true;
  DateTime? _startDate;
  DateTime? _endDate;
  List<String> _imageUrls = [];
  List<XFile> _newImages = [];
  bool _isUploading = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.ad != null) {
      _titleController.text = widget.ad!.title;
      _descriptionController.text = widget.ad!.description;
      _priorityController.text = widget.ad!.priority.toString();
      _isEnabled = widget.ad!.isEnabled;
      _startDate = widget.ad!.startDate;
      _endDate = widget.ad!.endDate;
      _imageUrls = List.from(widget.ad!.imageUrls);
      _restaurantIdController.text = widget.ad!.restaurantId ?? '';
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _priorityController.dispose();
    _restaurantIdController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
      );
      if (image != null) {
        setState(() {
          _newImages.add(image);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking image: $e')),
        );
      }
    }
  }

  void _removeNewImage(int index) {
    setState(() {
      _newImages.removeAt(index);
    });
  }

  void _removeExistingImage(int index) {
    setState(() {
      _imageUrls.removeAt(index);
    });
  }

  Future<void> _selectStartDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked != null) {
      final TimeOfDay? time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now(),
      );
      if (time != null) {
        setState(() {
          _startDate = DateTime(
            picked.year,
            picked.month,
            picked.day,
            time.hour,
            time.minute,
          );
        });
      }
    }
  }

  Future<void> _selectEndDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? (_startDate ?? DateTime.now()),
      firstDate: _startDate ?? DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked != null) {
      final TimeOfDay? time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now(),
      );
      if (time != null) {
        setState(() {
          _endDate = DateTime(
            picked.year,
            picked.month,
            picked.day,
            time.hour,
            time.minute,
          );
        });
      }
    }
  }

  Future<void> _saveAd() async {
    log('=== START: Saving Advertisement ===');
    log('Is creating new ad: ${widget.ad == null}');

    if (!_formKey.currentState!.validate()) {
      log('ERROR: Form validation failed');
      return;
    }

    if (_imageUrls.isEmpty && _newImages.isEmpty) {
      log('ERROR: No images provided');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add at least one image'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    log('Form data:');
    log('- Title: ${_titleController.text.trim()}');
    log('- Description: ${_descriptionController.text.trim()}');
    log('- Priority: ${_priorityController.text.trim()}');
    log('- IsEnabled: $_isEnabled');
    log('- Restaurant ID: ${_restaurantIdController.text.trim()}');
    log('- Start Date: $_startDate');
    log('- End Date: $_endDate');
    log('- Existing Images: ${_imageUrls.length}');
    log('- New Images: ${_newImages.length}');

    setState(() {
      _isSaving = true;
      _isUploading = true;
    });

    try {
      // Upload new images
      log('--- START: Uploading new images ---');
      final List<String> uploadedUrls = [];
      for (int i = 0; i < _newImages.length; i++) {
        log('Uploading image ${i + 1}/${_newImages.length}...');
        try {
          final url = await AdsService.uploadAdImage(_newImages[i]);
          uploadedUrls.add(url);
          log('Successfully uploaded image ${i + 1}: $url');
        } catch (e, stackTrace) {
          log('ERROR uploading image ${i + 1}: $e');
          log('StackTrace: $stackTrace');
          rethrow;
        }
      }
      log('--- END: All images uploaded successfully ---');

      // Combine existing and new image URLs
      final allImageUrls = [..._imageUrls, ...uploadedUrls];
      log('Total images after combining: ${allImageUrls.length}');

      // Create or update ad
      log('--- Creating Advertisement object ---');
      final ad = Advertisement(
        id: widget.ad?.id ?? '',
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        imageUrls: allImageUrls,
        isEnabled: _isEnabled,
        startDate: _startDate,
        endDate: _endDate,
        priority: int.tryParse(_priorityController.text.trim()) ?? 0,
        impressions: widget.ad?.impressions ?? 0,
        clicks: widget.ad?.clicks ?? 0,
        restaurantId: _restaurantIdController.text.trim().isEmpty 
            ? null 
            : _restaurantIdController.text.trim(),
        createdAt: widget.ad?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
        isDeleted: false,
      );
      log('Advertisement object created successfully');
      log('Ad ID: ${ad.id}');
      log('Restaurant ID: ${ad.restaurantId ?? "none"}');

      if (widget.ad == null) {
        log('--- START: Creating new ad in database ---');
        try {
          await AdsService.createAd(ad);
          log('--- SUCCESS: Ad created in database ---');
        } catch (e, stackTrace) {
          log('ERROR creating ad in database: $e');
          log('StackTrace: $stackTrace');
          rethrow;
        }
      } else {
        log('--- START: Updating existing ad in database ---');
        try {
          await AdsService.updateAd(ad);
          log('--- SUCCESS: Ad updated in database ---');
        } catch (e, stackTrace) {
          log('ERROR updating ad in database: $e');
          log('StackTrace: $stackTrace');
          rethrow;
        }
      }

      log('=== SUCCESS: Advertisement saved successfully ===');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.ad == null
                  ? 'Advertisement created successfully'
                  : 'Advertisement updated successfully',
            ),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e, stackTrace) {
      log('=== FATAL ERROR: Failed to save advertisement ===');
      log('Error: $e');
      log('Error Type: ${e.runtimeType}');
      log('StackTrace: $stackTrace');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving ad: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _isUploading = false;
        });
      }
      log('=== END: Save advertisement process ===');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.ad == null ? 'Create Ad' : 'Edit Ad'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _saveAd,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Title *',
                  hintText: 'Enter ad title',
                  prefixIcon: Icon(Icons.title),
                ),
                textCapitalization: TextCapitalization.words,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a title';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              // Description
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description *',
                  hintText: 'Enter ad description',
                  prefixIcon: Icon(Icons.description),
                ),
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a description';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              // Images section
              const Text(
                'Images *',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              // Existing images
              if (_imageUrls.isNotEmpty)
                SizedBox(
                  height: 120,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _imageUrls.length,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: kIsWeb
                                  ? Image.network(
                                      _imageUrls[index],
                                      width: 120,
                                      height: 120,
                                      fit: BoxFit.cover,
                                      loadingBuilder: (context, child, loadingProgress) {
                                        if (loadingProgress == null) return child;
                                        return Container(
                                          width: 120,
                                          height: 120,
                                          color: Colors.grey[300],
                                          child: const Center(
                                            child: CircularProgressIndicator(),
                                          ),
                                        );
                                      },
                                      errorBuilder: (context, error, stackTrace) => Container(
                                        width: 120,
                                        height: 120,
                                        color: Colors.grey[300],
                                        child: const Icon(Icons.image_not_supported),
                                      ),
                                    )
                                  : CachedNetworkImage(
                                      imageUrl: _imageUrls[index],
                                      width: 120,
                                      height: 120,
                                      fit: BoxFit.cover,
                                      placeholder: (context, url) => Container(
                                        width: 120,
                                        height: 120,
                                        color: Colors.grey[300],
                                        child: const Center(
                                          child: CircularProgressIndicator(),
                                        ),
                                      ),
                                      errorWidget: (context, url, error) => Container(
                                        width: 120,
                                        height: 120,
                                        color: Colors.grey[300],
                                        child: const Icon(Icons.image_not_supported),
                                      ),
                                    ),
                            ),
                            Positioned(
                              top: 4,
                              right: 4,
                              child: CircleAvatar(
                                radius: 14,
                                backgroundColor: Colors.red,
                                child: IconButton(
                                  padding: EdgeInsets.zero,
                                  icon: const Icon(
                                    Icons.close,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                  onPressed: () => _removeExistingImage(index),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              // New images
              if (_newImages.isNotEmpty) ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: 120,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _newImages.length,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: kIsWeb
                                  ? Image.network(
                                      _newImages[index].path,
                                      width: 120,
                                      height: 120,
                                      fit: BoxFit.cover,
                                    )
                                  : Image.file(
                                      File(_newImages[index].path),
                                      width: 120,
                                      height: 120,
                                      fit: BoxFit.cover,
                                    ),
                            ),
                            Positioned(
                              top: 4,
                              right: 4,
                              child: CircleAvatar(
                                radius: 14,
                                backgroundColor: Colors.red,
                                child: IconButton(
                                  padding: EdgeInsets.zero,
                                  icon: const Icon(
                                    Icons.close,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                  onPressed: () => _removeNewImage(index),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 8),
              // Add image button
              ElevatedButton.icon(
                onPressed: _isUploading ? null : _pickImage,
                icon: const Icon(Icons.add_photo_alternate),
                label: const Text('Add Image'),
              ),
              const SizedBox(height: 16),
              // Priority
              TextFormField(
                controller: _priorityController,
                decoration: const InputDecoration(
                  labelText: 'Priority',
                  hintText: '0',
                  prefixIcon: Icon(Icons.sort),
                  helperText: 'Lower number = higher priority',
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value != null && value.trim().isNotEmpty) {
                    final priority = int.tryParse(value.trim());
                    if (priority == null) {
                      return 'Please enter a valid number';
                    }
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              // Restaurant ID
              TextFormField(
                controller: _restaurantIdController,
                decoration: const InputDecoration(
                  labelText: 'Restaurant ID (Optional)',
                  hintText: 'Enter restaurant ID for click navigation',
                  prefixIcon: Icon(Icons.restaurant),
                  helperText:
                      'Leave empty if ad should not link to a restaurant',
                ),
              ),
              const SizedBox(height: 16),
              // Enable/Disable switch
              SwitchListTile(
                title: const Text('Enabled'),
                subtitle: const Text('Enable or disable this advertisement'),
                value: _isEnabled,
                onChanged: (value) {
                  setState(() {
                    _isEnabled = value;
                  });
                },
              ),
              const SizedBox(height: 16),
              // Start date
              ListTile(
                title: const Text('Start Date (Optional)'),
                subtitle: Text(
                  _startDate != null
                      ? '${_startDate!.year}-${_startDate!.month.toString().padLeft(2, '0')}-${_startDate!.day.toString().padLeft(2, '0')} ${_startDate!.hour.toString().padLeft(2, '0')}:${_startDate!.minute.toString().padLeft(2, '0')}'
                      : 'Not set',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_startDate != null)
                      IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() {
                            _startDate = null;
                          });
                        },
                      ),
                    const Icon(Icons.calendar_today),
                  ],
                ),
                onTap: _selectStartDate,
              ),
              const SizedBox(height: 8),
              // End date
              ListTile(
                title: const Text('End Date (Optional)'),
                subtitle: Text(
                  _endDate != null
                      ? '${_endDate!.year}-${_endDate!.month.toString().padLeft(2, '0')}-${_endDate!.day.toString().padLeft(2, '0')} ${_endDate!.hour.toString().padLeft(2, '0')}:${_endDate!.minute.toString().padLeft(2, '0')}'
                      : 'Not set',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_endDate != null)
                      IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() {
                            _endDate = null;
                          });
                        },
                      ),
                    const Icon(Icons.calendar_today),
                  ],
                ),
                onTap: _selectEndDate,
              ),
              const SizedBox(height: 24),
              // Save button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveAd,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text('Save Advertisement'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
