import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: ".env");

  // Initialize Supabase
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  runApp(const YoaronApp());
}

// 1. The Root of the App
class YoaronApp extends StatelessWidget {
  const YoaronApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Inventory Manager',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const InventoryScreen(), // Points to your main screen
    );
  }
}

// 2. The Main Screen Widget
class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

// 3. The State & Logic for the Main Screen
class _InventoryScreenState extends State<InventoryScreen> {
  File? _selectedImage;
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = false;
  bool _isEditing = false; 

  // Custom Hungarian Categories
  final List<String> _myCategories = [
    'Poló',
    'Galléros',
    'Kötött pulcsi',
    'zipup',
    'farmer',
    'nadrág',
    'dzseki',
    'hoodie',
    'quarter zip',
    'short',
    'jort',
    'other'
  ];

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _brandController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  String? _selectedCategory;

  @override
  void dispose() {
    _nameController.dispose();
    _brandController.dispose();
    _priceController.dispose();
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
      _showSnackBar('Error picking image: $e', isError: true);
    }
  }

  Future<void> _analyzeWithGemini() async {
    if (_selectedImage == null) return;
    setState(() => _isLoading = true);

    try {
      final imageBytes = await _selectedImage!.readAsBytes();
      final base64Image = base64Encode(imageBytes);

      // ---> PASTE YOUR GEMINI KEY HERE <---
      final geminiKey = dotenv.env['GEMINI_API_KEY']!;

      final response = await http.post(
        Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite-preview:generateContent?key=$geminiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "contents": [
            {
              "parts": [
                {
                  "text": "Analyze this item in hungarian. Choose one category ONLY from this list: ${_myCategories.join(', ')}. Return JSON: {'name': string, 'brand': string, 'category': string, 'price': number}"
                },
                {
                  "inlineData": {
                    "mimeType": "image/jpeg",
                    "data": base64Image
                  }
                }
              ]
            }
          ],
          "generationConfig": {
            "responseMimeType": "application/json"
          }
        }),
      );

      if (response.statusCode != 200) throw Exception('Gemini failed: ${response.body}');

      final data = jsonDecode(response.body);
      final aiResult = jsonDecode(data['candidates'][0]['content']['parts'][0]['text']);

      setState(() {
        _nameController.text = aiResult['name'] ?? "";
        _brandController.text = aiResult['brand'] ?? "";
        _priceController.text = aiResult['price']?.toString() ?? "0";
        _selectedCategory = _myCategories.contains(aiResult['category']) 
            ? aiResult['category'] 
            : _myCategories.first; // Defaults to 'Poló' if AI gets confused
        
        _isEditing = true;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnackBar('AI Error: $e', isError: true);
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
      _showSnackBar('Save Error: $e', isError: true);
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
appBar: AppBar(
        title: const Text('Inventory Manager'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.list, size: 30),
            onPressed: () {
              // This navigates the user to the new screen!
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const InventoryListScreen()),
              );
            },
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // IMAGE PREVIEW
            Container(
              height: 300,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: _selectedImage != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(_selectedImage!, fit: BoxFit.cover),
                    )
                  : const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_a_photo, size: 80, color: Colors.grey),
                        Text('No Image Selected', style: TextStyle(color: Colors.grey)),
                      ],
                    ),
            ),
            const SizedBox(height: 20),

            // CAPTURE BUTTONS
            if (!_isEditing && !_isLoading) 
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    onPressed: () => _pickImage(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Camera'),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _pickImage(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Gallery'),
                  ),
                ],
              ),
            const SizedBox(height: 20),

            // LOADING STATE
            if (_isLoading) 
              const Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 10),
                  Text("Processing..."),
                ],
              ),

            // ANALYZE BUTTON
            if (_selectedImage != null && !_isEditing && !_isLoading)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _analyzeWithGemini,
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Analyze with AI'),
                  style: FilledButton.styleFrom(padding: const EdgeInsets.all(15)),
                ),
              ),

            // THE EDIT FORM
            if (_isEditing && !_isLoading) ...[
              const Divider(height: 40),
              const Text('Verify Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 15),
              
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Item Name', border: OutlineInputBorder(), prefixIcon: Icon(Icons.label)),
              ),
              const SizedBox(height: 12),
              
              TextField(
                controller: _brandController,
                decoration: const InputDecoration(labelText: 'Brand', border: OutlineInputBorder(), prefixIcon: Icon(Icons.branding_watermark)),
              ),
              const SizedBox(height: 12),
              
              TextField(
                controller: _priceController,
                decoration: const InputDecoration(labelText: 'Price', border: OutlineInputBorder(), prefixIcon: Icon(Icons.attach_money)),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              
              DropdownButtonFormField<String>(
                value: _selectedCategory,
                decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder(), prefixIcon: Icon(Icons.category)),
                items: _myCategories.map((category) => DropdownMenuItem(value: category, child: Text(category))).toList(),
                onChanged: (val) => setState(() => _selectedCategory = val),
              ),
              
              const SizedBox(height: 25),
              
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _finalUpload,
                  icon: const Icon(Icons.cloud_upload),
                  label: const Text('Confirm & Save to Inventory'),
                  style: FilledButton.styleFrom(padding: const EdgeInsets.all(16), backgroundColor: Colors.green[700]),
                ),
              ),
              
              TextButton(
                onPressed: () => setState(() {
                  _isEditing = false;
                  _selectedImage = null;
                }),
                child: const Text('Discard and Start Over', style: TextStyle(color: Colors.red)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
class InventoryListScreen extends StatefulWidget {
  const InventoryListScreen({super.key});

  @override
  State<InventoryListScreen> createState() => _InventoryListScreenState();
}

class _InventoryListScreenState extends State<InventoryListScreen> {
  List<dynamic> _inventory = [];
  bool _isLoading = true;
  String _selectedFilter = 'Minden'; // 'All' in Hungarian

  // The categories to filter by (Includes 'Minden' at the start)
  final List<String> _filterCategories = [
    'Minden',
    'Poló',
    'Galléros',
    'Kötött pulcsi',
    'zipup',
    'farmer',
    'nadrág',
    'dzseki',
    'hoodie',
    'quarter zip',
    'short',
    'jort',
    'other'
  ];

  @override
  void initState() {
    super.initState();
    _fetchInventory();
  }

  // Grabs the data from Supabase
// Grabs the data from Supabase
  Future<void> _fetchInventory() async {
    setState(() => _isLoading = true);

    try {
      // 1. Start the base query
      var query = Supabase.instance.client.from('inventory').select();

      // 2. Apply the category filter FIRST (if needed)
      if (_selectedFilter != 'Minden') {
        query = query.eq('category', _selectedFilter);
      }

      // 3. Apply the sorting LAST, and then await the final result
      final data = await query.order('created_at', ascending: false);

      setState(() {
        _inventory = data;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('Error loading inventory: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Készlet (Inventory)'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      backgroundColor: Colors.grey[100],
      body: Column(
        children: [
          // --- THE FILTER MENU ---
          Container(
            height: 60,
            color: Colors.white,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              itemCount: _filterCategories.length,
              itemBuilder: (context, index) {
                final category = _filterCategories[index];
                final isSelected = category == _selectedFilter;
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: FilterChip(
                    label: Text(category),
                    selected: isSelected,
                    onSelected: (bool selected) {
                      setState(() {
                        _selectedFilter = category;
                      });
                      _fetchInventory(); // Reload data with new filter
                    },
                    selectedColor: Theme.of(context).colorScheme.primaryContainer,
                    checkmarkColor: Theme.of(context).colorScheme.primary,
                  ),
                );
              },
            ),
          ),

          // --- THE GRID VIEW ---
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _inventory.isEmpty
                    ? const Center(child: Text('Nincs találat (No items found)', style: TextStyle(fontSize: 18, color: Colors.grey)))
                    : GridView.builder(
                        padding: const EdgeInsets.all(10),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2, // 2 items per row
                          childAspectRatio: 0.7, // Makes the cards taller
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                        itemCount: _inventory.length,
                        itemBuilder: (context, index) {
                          final item = _inventory[index];
                          return Card(
                            clipBehavior: Clip.antiAlias,
                            elevation: 2,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Item Image
                                Expanded(
                                  child: Container(
                                    width: double.infinity,
                                    color: Colors.grey[200],
                                    child: item['image_url'] != null
                                        ? Image.network(
                                            item['image_url'],
                                            fit: BoxFit.cover,
                                          )
                                        : const Icon(Icons.image_not_supported, color: Colors.grey),
                                  ),
                                ),
                                // Item Details
                                Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item['brand'] ?? 'Unknown Brand',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        item['name'] ?? 'Unknown Item',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '\$${item['price_est']}',
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green[700]),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}