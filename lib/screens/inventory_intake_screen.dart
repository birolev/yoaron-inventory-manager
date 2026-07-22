import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yoaron_app/constants/categories.dart';
import 'package:yoaron_app/models/batch_image_queue.dart';

import 'inventory_list_screen.dart';
import 'search_screen.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  BatchImageQueue? _queue;
  final ImagePicker _picker = ImagePicker();

  bool _isUploading = false; // Used for final Supabase upload
  bool _isEditing = false;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _brandController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _colorController = TextEditingController();
  final TextEditingController _patternController = TextEditingController();
  final TextEditingController _sizeController = TextEditingController();
  final TextEditingController _conditionController = TextEditingController();

  String? _selectedCategory;

  @override
  void dispose() {
    _nameController.dispose();
    _brandController.dispose();
    _priceController.dispose();
    _colorController.dispose();
    _patternController.dispose();
    _sizeController.dispose();
    _conditionController.dispose();
    super.dispose();
  }

  // --- Image Picking ---

  Future<void> _pickSingleImageCamera() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 70,
        maxWidth: 1000,
      );

      if (pickedFile != null) {
        _initializeQueue([pickedFile]);
      }
    } catch (e) {
      _showSnackBar('Error picking image: $e', isError: true);
    }
  }

  Future<void> _pickGalleryImages() async {
    try {
      final List<XFile> pickedFiles = await _picker.pickMultiImage(
        imageQuality: 70,
        maxWidth: 1000,
      );

      if (pickedFiles.isNotEmpty) {
        _initializeQueue(pickedFiles);
      }
    } catch (e) {
      _showSnackBar('Error picking images: $e', isError: true);
    }
  }

  void _initializeQueue(List<XFile> files) {
    setState(() {
      _queue = BatchImageQueue(files.map((f) => QueueItem(f)).toList());
      _isEditing = false;
    });
    _startBackgroundAnalysis();
  }

  // --- AI Background Processing ---

  Future<void> _startBackgroundAnalysis() async {
    if (_queue == null) return;

    // Process all items in the background
    for (var item in _queue!.items) {
      if (!item.isReady && !item.isAnalyzing) {
        await _analyzeItem(item);
      }
    }
  }

  Future<void> _analyzeItem(QueueItem item) async {
    item.isAnalyzing = true;
    if (_queue?.current == item && mounted) {
      setState(() {}); // Rebuild to show spinner if it's the current item
    }

    try {
      final imageBytes = await item.image.readAsBytes();
      final base64Image = base64Encode(imageBytes);
      final geminiKey = dotenv.env['GEMINI_API_KEY']!;

      final response = await http.post(
        Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite-preview:generateContent?key=$geminiKey',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "contents": [
            {
              "parts": [
                {
                  "text":
                      "Analyze this clothing item in Hungarian. Choose ONE category from: ${clothingCategories.join(', ')}. Return pure JSON: {'name': string, 'brand': string, 'category': string, 'price': number, 'color': string, 'pattern': string, 'condition': string (e.g., 'Új', 'Kiváló', 'Használt'), 'size': string}"
                },
                {
                  "inlineData": {
                    "mimeType": "image/jpeg",
                    "data": base64Image,
                  }
                }
              ]
            }
          ],
          "generationConfig": {
            "responseMimeType": "application/json",
          }
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Gemini failed: ${response.body}');
      }

      final data = jsonDecode(response.body);
      final aiResult = jsonDecode(
        data['candidates'][0]['content']['parts'][0]['text'],
      );

      item.aiResult = aiResult;
    } catch (e) {
      _showSnackBar('AI Error on an image: $e', isError: true);
      // Even if it fails, mark as ready so user can manually fill it out
      item.aiResult = {}; 
    } finally {
      item.isAnalyzing = false;
      item.isReady = true;

      // If the user is currently looking at this item, populate the form
      if (mounted && _queue?.current == item) {
        _populateControllers(item);
      } else if (mounted) {
        setState(() {}); // Silent rebuild to update background progress indicators if needed
      }
    }
  }

  void _populateControllers(QueueItem item) {
    if (item.aiResult == null) return;
    final aiResult = item.aiResult!;

    setState(() {
      _nameController.text = aiResult['name'] ?? "";
      _brandController.text = aiResult['brand'] ?? "";
      _priceController.text = aiResult['price']?.toString() ?? "0";
      _colorController.text = aiResult['color'] ?? "";
      _patternController.text = aiResult['pattern'] ?? "";
      _sizeController.text = aiResult['size'] ?? "";
      _conditionController.text = aiResult['condition'] ?? "";

      _selectedCategory = clothingCategories.contains(aiResult['category'])
          ? aiResult['category']
          : clothingCategories.first;

      _isEditing = true;
    });
  }

  // --- Uploading and Queue Management ---

  Future<void> _finalUpload() async {
    if (_queue == null) return;
    setState(() => _isUploading = true);

    try {
      final currentItem = _queue!.current;
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      final file = File(currentItem.image.path);

      await Supabase.instance.client.storage
          .from('clothes-images')
          .upload(fileName, file);

      final imageUrl = Supabase.instance.client.storage
          .from('clothes-images')
          .getPublicUrl(fileName);

      await Supabase.instance.client.from('inventory').insert({
        'name': _nameController.text,
        'brand': _brandController.text,
        'price_est': double.tryParse(_priceController.text) ?? 0.0,
        'category': _selectedCategory,
        'image_url': imageUrl,
        'color': _colorController.text,
        'pattern': _patternController.text,
        'size': _sizeController.text,
        'condition': _conditionController.text,
        'is_sold': false,
      });

      _showSnackBar('Item successfully saved to inventory!');
      _moveToNextItemInQueue();
    } catch (e) {
      setState(() => _isUploading = false);
      _showSnackBar('Save Error: $e', isError: true);
    }
  }

  void _moveToNextItemInQueue() {
    _nameController.clear();
    _brandController.clear();
    _priceController.clear();
    _colorController.clear();
    _patternController.clear();
    _sizeController.clear();
    _conditionController.clear();
    _selectedCategory = null;
    _isEditing = false;
    _isUploading = false;

    setState(() {
      _queue!.moveNext();
      if (!_queue!.hasNext) {
        _queue = null; // Finished batch
      } else {
        // If the next item has already finished processing in the background, load it instantly!
        if (_queue!.current.isReady) {
          _populateControllers(_queue!.current);
        }
      }
    });
  }

  void _discardCurrentItem() {
    _moveToNextItemInQueue();
  }

  void _cancelEntireBatch() {
    setState(() {
      _queue = null;
      _isEditing = false;
      _isUploading = false;
      _nameController.clear();
      _brandController.clear();
      _priceController.clear();
    });
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  // --- UI ---

  @override
  Widget build(BuildContext context) {
    final bool hasQueue = _queue != null && _queue!.hasNext;
    final QueueItem? currentItem = hasQueue ? _queue!.current : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory Manager'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.image_search, size: 30),
            tooltip: 'Keresés (Search)',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SearchScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.list, size: 30),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const InventoryListScreen()),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Batch Progress Indicator
            if (hasQueue) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Item ${_queue!.currentNumber} of ${_queue!.total}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  TextButton.icon(
                    onPressed: _cancelEntireBatch,
                    icon: const Icon(Icons.cancel, color: Colors.red, size: 18),
                    label: const Text('Cancel Batch', style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],

            // Image Preview Container
            Container(
              height: 300,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: currentItem != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        File(currentItem.image.path),
                        fit: BoxFit.cover,
                      ),
                    )
                  : const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_a_photo, size: 80, color: Colors.grey),
                        Text(
                          'No Image Selected',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
            ),

            const SizedBox(height: 20),

            // Selection Buttons (Only visible if no queue is active)
            if (!hasQueue && !_isUploading)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    onPressed: _pickSingleImageCamera,
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Camera'),
                  ),
                  ElevatedButton.icon(
                    onPressed: _pickGalleryImages,
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Gallery (Multi)'),
                  ),
                ],
              ),

            // Background Processing / Uploading Indicators
            if (_isUploading || (currentItem != null && currentItem.isAnalyzing))
              Column(
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 10),
                  Text(_isUploading ? "Uploading to inventory..." : "AI is analyzing this item..."),
                ],
              ),

            // Edit Form (Appears when item is ready)
            if (hasQueue && _isEditing && !_isUploading) ...[
              const Divider(height: 40),

              const Text(
                'Verify Details',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),

              const SizedBox(height: 15),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Item Name',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.label),
                ),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _brandController,
                decoration: const InputDecoration(
                  labelText: 'Brand',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.branding_watermark),
                ),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _priceController,
                decoration: const InputDecoration(
                  labelText: 'Price (Ft)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.attach_money),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _sizeController,
                decoration: const InputDecoration(
                  labelText: 'Méret (Size)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.straighten),
                ),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _colorController,
                decoration: const InputDecoration(
                  labelText: 'Szín (Color)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.color_lens),
                ),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _patternController,
                decoration: const InputDecoration(
                  labelText: 'Minta (Pattern)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.texture),
                ),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _conditionController,
                decoration: const InputDecoration(
                  labelText: 'Állapot (Condition)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.star),
                ),
              ),
              const SizedBox(height: 12),

              DropdownButtonFormField<String>(
                initialValue: _selectedCategory,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.category),
                ),
                items: clothingCategories
                    .map((category) => DropdownMenuItem(
                          value: category,
                          child: Text(category),
                        ))
                    .toList(),
                onChanged: (val) => setState(() => _selectedCategory = val),
              ),

              const SizedBox(height: 25),

              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _finalUpload,
                  icon: const Icon(Icons.cloud_upload),
                  label: const Text('Confirm & Save to Inventory'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                    backgroundColor: Colors.green[700],
                  ),
                ),
              ),

              TextButton(
                onPressed: _discardCurrentItem,
                child: const Text(
                  'Discard This Item',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}