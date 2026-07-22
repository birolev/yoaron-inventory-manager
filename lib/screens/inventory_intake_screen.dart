import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yoaron_app/constants/categories.dart';



import 'inventory_list_screen.dart';
import 'search_screen.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  File? _selectedImage;
  
  final ImagePicker _picker = ImagePicker();

  bool _isLoading = false;
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

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: 70,
        maxWidth: 1000,
      );

      if (pickedFile != null) {
        setState(() {
          _selectedImage = File(pickedFile.path);
          _isEditing = false;
        });
      }
    } catch (e) {
      _showSnackBar(
        'Error picking image: $e',
        isError: true,
      );
    }
  }

  Future<void> _analyzeWithGemini() async {
    if (_selectedImage == null) return;

    setState(() => _isLoading = true);

    try {
      final imageBytes = await _selectedImage!.readAsBytes();
      final base64Image = base64Encode(imageBytes);

      final geminiKey = dotenv.env['GEMINI_API_KEY']!;

      final response = await http.post(
        Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite-preview:generateContent?key=$geminiKey',
        ),
        headers: {
          'Content-Type': 'application/json',
        },
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

      setState(() {
        _nameController.text = aiResult['name'] ?? "";
        _brandController.text = aiResult['brand'] ?? "";
        _priceController.text = aiResult['price']?.toString() ?? "0";
        _colorController.text = aiResult['color'] ?? "";
        _patternController.text = aiResult['pattern'] ?? "";
        _sizeController.text = aiResult['size'] ?? "";
        _conditionController.text = aiResult['condition'] ?? "";

        _selectedCategory =
            clothingCategories.contains(aiResult['category'])
                ? aiResult['category']
                : clothingCategories.first;

        _isEditing = true;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);

      _showSnackBar(
        'AI Error: $e',
        isError: true,
      );
    }
  }
    Future<void> _finalUpload() async {
    setState(() => _isLoading = true);

    try {
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';

      await Supabase.instance.client.storage
          .from('clothes-images')
          .upload(fileName, _selectedImage!);

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

      setState(() {
        _isEditing = false;
        _selectedImage = null;
        _isLoading = false;

        _nameController.clear();
        _brandController.clear();
        _priceController.clear();
      });
    } catch (e) {
      setState(() => _isLoading = false);

      _showSnackBar(
        'Save Error: $e',
        isError: true,
      );
    }
  }

  void _showSnackBar(
    String message, {
    bool isError = false,
  }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            isError ? Colors.red : Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory Manager'),
        backgroundColor:
            Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(
              Icons.image_search,
              size: 30,
            ),
            tooltip: 'Keresés (Search)',
            onPressed: () {
              Navigator.push(
               context,
                MaterialPageRoute(
                  builder: (context) =>
                     SearchScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(
              Icons.list,
              size: 30,
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      InventoryListScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              height: 300,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius:
                    BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.grey[300]!,
                ),
              ),
              child: _selectedImage != null
                  ? ClipRRect(
                      borderRadius:
                          BorderRadius.circular(12),
                      child: Image.file(
                        _selectedImage!,
                        fit: BoxFit.cover,
                      ),
                    )
                  : const Column(
                      mainAxisAlignment:
                          MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.add_a_photo,
                          size: 80,
                          color: Colors.grey,
                        ),
                        Text(
                          'No Image Selected',
                          style: TextStyle(
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
            ),

            const SizedBox(height: 20),

            if (!_isEditing && !_isLoading)
              Row(
                mainAxisAlignment:
                    MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    onPressed: () =>
                        _pickImage(ImageSource.camera),
                    icon:
                        const Icon(Icons.camera_alt),
                    label: const Text('Camera'),
                  ),
                  ElevatedButton.icon(
                    onPressed: () =>
                        _pickImage(ImageSource.gallery),
                    icon: const Icon(
                        Icons.photo_library),
                    label: const Text('Gallery'),
                  ),
                ],
              ),

            const SizedBox(height: 20),

            if (_isLoading)
              const Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 10),
                  Text("Processing..."),
                ],
              ),

            if (_selectedImage != null &&
                !_isEditing &&
                !_isLoading)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _analyzeWithGemini,
                  icon:
                      const Icon(Icons.auto_awesome),
                  label:
                      const Text('Analyze with AI'),
                  style: FilledButton.styleFrom(
                    padding:
                        const EdgeInsets.all(15),
                  ),
                ),
              ),

            if (_isEditing && !_isLoading) ...[
              const Divider(height: 40),

              const Text(
                'Verify Details',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
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
                    .map(
                      (category) => DropdownMenuItem(
                        value: category,
                        child: Text(category),
                      ),
                    )
                    .toList(),
                onChanged: (val) =>
                    setState(() => _selectedCategory = val),
              ),

              const SizedBox(height: 25),

              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _finalUpload,
                  icon: const Icon(Icons.cloud_upload),
                  label: const Text(
                    'Confirm & Save to Inventory',
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                    backgroundColor: Colors.green[700],
                  ),
                ),
              ),

              TextButton(
                onPressed: () => setState(() {
                  _isEditing = false;
                  _selectedImage = null;
                }),
                child: const Text(
                  'Discard and Start Over',
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