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
      home: const InventoryScreen(),
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
    super.dispose();  }

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

    
      final geminiKey = dotenv.env['GEMINI_API_KEY']!;

      final response = await http.post(
        Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite-preview:generateContent?key=$geminiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "contents": [
            {
              "parts": [
                {
                  "text": "Analyze this clothing item in Hungarian. Choose ONE category from: ${_myCategories.join(', ')}. Return pure JSON: {'name': string, 'brand': string, 'category': string, 'price': number, 'color': string, 'pattern': string, 'condition': string (e.g., 'Új', 'Kiváló', 'Használt'), 'size': string}"
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
        _colorController.text = aiResult['color'] ?? "";
        _patternController.text = aiResult['pattern'] ?? "";
        _sizeController.text = aiResult['size'] ?? "";
        _conditionController.text = aiResult['condition'] ?? "";


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
        'color': _colorController.text,
        'pattern': _patternController.text,
        'size': _sizeController.text,
        'condition': _conditionController.text,
        'is_sold': false, // Always false when first adding a new item
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
                decoration: const InputDecoration(labelText: 'Price (Ft)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.attach_money)),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _sizeController,
                decoration: const InputDecoration(labelText: 'Méret (Size)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.straighten)),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _colorController,
                decoration: const InputDecoration(labelText: 'Szín (Color)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.color_lens)),
              ),
              const SizedBox(height: 12),
              
              TextField(
                controller: _patternController,
                decoration: const InputDecoration(labelText: 'Minta (Pattern)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.texture)),
              ),
              const SizedBox(height: 12),
              
              TextField(
                controller: _conditionController,
                decoration: const InputDecoration(labelText: 'Állapot (Condition)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.star)),
              ),

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
  String _selectedFilter = 'Minden'; 
  
  String _sortColumn = 'created_at';
  bool _sortAscending = false;

  final List<String> _filterCategories = [
    'Minden', 'Poló', 'Galléros', 'Kötött pulcsi', 'zipup', 
    'farmer', 'nadrág', 'dzseki', 'hoodie', 'quarter zip', 
    'short', 'jort', 'other'
  ];

  @override
  void initState() {
    super.initState();
    _fetchInventory();
  }

  // --- 1. READ: Fetch Data ---
  Future<void> _fetchInventory() async {
    setState(() => _isLoading = true);
    try {
      var query = Supabase.instance.client.from('inventory').select();

      if (_selectedFilter != 'Minden') {
        query = query.eq('category', _selectedFilter);
      }

      final data = await query.order(_sortColumn, ascending: _sortAscending);

      setState(() {
        _inventory = data;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('Hiba a betöltésnél: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // --- 2. UPDATE: Save Edited Data ---
  Future<void> _updateItem(dynamic id, String name, String brand, double price, String category, bool isSold) async {
    try {
      await Supabase.instance.client.from('inventory').update({
        'name': name,
        'brand': brand,
        'price_est': price,
        'category': category,
        'is_sold' : isSold,
      }).eq('id', id);

      if (mounted) Navigator.pop(context); // Close the bottom sheet
      _fetchInventory(); // Refresh the list
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sikeresen frissítve! (Updated)'), backgroundColor: Colors.green)
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hiba: $e'), backgroundColor: Colors.red));
      }
    }
  }

  // --- 3. DELETE: Remove Item ---
  Future<void> _deleteItem(dynamic id) async {
    // Show a confirmation popup first
    bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Törlés (Delete)'),
        content: const Text('Biztosan törlöd ezt a terméket?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Mégse')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Törlés', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    ) ?? false;

    if (!confirm) return;

    try {
      await Supabase.instance.client.from('inventory').delete().eq('id', id);
      if (mounted) Navigator.pop(context); // Close the bottom sheet
      _fetchInventory(); // Refresh the list
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Termék törölve! (Deleted)'), backgroundColor: Colors.red)
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hiba: $e'), backgroundColor: Colors.red));
      }
    }
  }

  // --- 4. THE EDIT MENU (Bottom Sheet) ---
  // --- REFACTORED: THE EDIT MENU ---
  void _showEditSheet(Map<String, dynamic> item) {
    // Setup local controllers
    final nameCtrl = TextEditingController(text: item['name']);
    final brandCtrl = TextEditingController(text: item['brand']);
    final priceCtrl = TextEditingController(text: item['price_est'].toString());
    bool itemIsSold = item['isSold'] ?? false;
    
    final List<String> editCategories = _filterCategories.where((c) => c != 'Minden').toList();
    String selectedCat = editCategories.contains(item['category']) ? item['category'] : editCategories.first;

    // Use YOUR global helper instead of showModalBottomSheet!
    showSafeBottomSheet(
      context: context,
      child: StatefulBuilder( // We keep StatefulBuilder so the toggle switch animates!
        builder: (context, setSheetState) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Termék Szerkesztése', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 15),
              
              SwitchListTile(
                title: const Text('Eladva (Mark as Sold)', style: TextStyle(fontWeight: FontWeight.bold)),
                activeColor: Colors.green,
                value: itemIsSold,
                onChanged: (bool val) => setSheetState(() => itemIsSold = val),
              ),
              const Divider(),
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Név', border: OutlineInputBorder())),
              const SizedBox(height: 10),
              TextField(controller: brandCtrl, decoration: const InputDecoration(labelText: 'Márka', border: OutlineInputBorder())),
              const SizedBox(height: 10),
              TextField(controller: priceCtrl, decoration: const InputDecoration(labelText: 'Ár (Ft)', border: OutlineInputBorder()), keyboardType: TextInputType.number),
              const SizedBox(height: 10),
              
              DropdownButtonFormField<String>(
                value: selectedCat,
                decoration: const InputDecoration(labelText: 'Kategória', border: OutlineInputBorder()),
                items: editCategories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (val) => setSheetState(() => selectedCat = val!),
              ),
              
              const SizedBox(height: 25),
              
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _deleteItem(item['id']),
                      icon: const Icon(Icons.delete, color: Colors.red),
                      label: const Text('Törlés', style: TextStyle(color: Colors.red)),
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red), padding: const EdgeInsets.symmetric(vertical: 15)),
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: () {
                        _updateItem(item['id'], nameCtrl.text, brandCtrl.text, double.tryParse(priceCtrl.text) ?? 0.0, selectedCat, itemIsSold);
                      },
                      icon: const Icon(Icons.save),
                      label: const Text('Mentés'),
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 15), backgroundColor: Colors.green[700]),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10), // Small extra buffer for the keyboard
            ],
          );
        }
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Készlet (Inventory)'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort),
            tooltip: 'Rendezés (Sort)',
            onSelected: (String result) {
              setState(() {
                if (result == 'newest') { _sortColumn = 'created_at'; _sortAscending = false; } 
                else if (result == 'oldest') { _sortColumn = 'created_at'; _sortAscending = true; } 
                else if (result == 'price_low') { _sortColumn = 'price_est'; _sortAscending = true; } 
                else if (result == 'price_high') { _sortColumn = 'price_est'; _sortAscending = false; }
              });
              _fetchInventory(); 
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(value: 'newest', child: Text('Legújabb elöl (Newest)')),
              const PopupMenuItem<String>(value: 'oldest', child: Text('Legrégebbi elöl (Oldest)')),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(value: 'price_low', child: Text('Legolcsóbb elöl (Price: Low-High)')),
              const PopupMenuItem<String>(value: 'price_high', child: Text('Legdrágább elöl (Price: High-Low)')),
            ],
          ),
        ],
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
                      setState(() => _selectedFilter = category);
                      _fetchInventory();
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
                          crossAxisCount: 2, 
                          childAspectRatio: 0.7, 
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                        itemCount: _inventory.length,
                        itemBuilder: (context, index) {
                          final item = _inventory[index];
                          
                          // --- NEW: INKWELL MAKES THE CARD TAPPABLE ---
                          return InkWell(
                            onTap: () => _showEditSheet(item), // Opens the menu!
                            borderRadius: BorderRadius.circular(12),
                            child: Card(
                              clipBehavior: Clip.antiAlias,
                              elevation: 2,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Container(
                                      width: double.infinity,
                                      color: Colors.grey[200],
                                      child: item['image_url'] != null
                                          ? Image.network(item['image_url'], fit: BoxFit.cover)
                                          : const Icon(Icons.image_not_supported, color: Colors.grey),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item['brand'] ?? 'Unknown Brand',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey),
                                          maxLines: 1, overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          item['name'] ?? 'Unknown Item',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                          maxLines: 1, overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${item['price_est']} Ft',
                                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green[700]),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
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
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  File? _searchImage;
  final ImagePicker _picker = ImagePicker();
  bool _isSearching = false;
  List<dynamic> _searchResults = [];
  Map<String, dynamic>? _aiCriteria; // Stores what the AI was looking for

  final List<String> _myCategories = [
    'Poló', 'Galléros', 'Kötött pulcsi', 'zipup', 'farmer', 
    'nadrág', 'dzseki', 'hoodie', 'quarter zip', 'short', 'jort', 'other'
  ];

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: 50,
        maxWidth: 600, // Kept small for speed!
      );

      if (pickedFile != null) {
        setState(() {
          _searchImage = File(pickedFile.path);
          _searchResults = []; // Clear old results
          _aiCriteria = null;
        });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hiba: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _executeSearch() async {
    if (_searchImage == null) return;
    setState(() => _isSearching = true);

    try {
      // 1. Convert Image for Gemini
      final imageBytes = await _searchImage!.readAsBytes();
      final base64Image = base64Encode(imageBytes);
      final geminiKey = dotenv.env['GEMINI_API_KEY']!;

      // 2. Ask Gemini to extract JUST the core searchable attributes
      final response = await http.post(
        Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite-preview:generateContent?key=$geminiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "contents": [{
            "parts": [
              {
                "text": "Analyze this clothing item. Identify its category (Choose EXACTLY ONE from: ${_myCategories.join(', ')}), its main color (in Hungarian, e.g. 'kék', 'piros', 'fekete'), and its pattern (e.g. 'kockás', 'csíkos', 'egyszínű'). Return pure JSON: {'category': string, 'color': string, 'pattern': string}"
              },
              {
                "inlineData": {"mimeType": "image/jpeg", "data": base64Image}
              }
            ]
          }],
          "generationConfig": {"responseMimeType": "application/json"}
        }),
      );

      if (response.statusCode != 200) throw Exception('Gemini failed');

      final data = jsonDecode(response.body);
      final aiResult = jsonDecode(data['candidates'][0]['content']['parts'][0]['text']);
      
      String searchCategory = aiResult['category'] ?? '';
      String searchColor = aiResult['color'] ?? '';
      
      // Save criteria to show the user what the AI is looking for
      setState(() => _aiCriteria = aiResult);

      // 3. Query Supabase! 
      // We look for unsold items that match the category, and use 'ilike' (fuzzy search) for the color
      var query = Supabase.instance.client
          .from('inventory')
          .select()
          .eq('is_sold', false); // Only search items currently in the store

      // Apply filters if AI found them
      if (_myCategories.contains(searchCategory)) {
        query = query.eq('category', searchCategory);
      }
      if (searchColor.isNotEmpty) {
        query = query.ilike('color', '%$searchColor%'); // % allows partial matches (e.g., 'világoskék' matches 'kék')
      }

      final results = await query;

      setState(() {
        _searchResults = results;
        _isSearching = false;
      });

    } catch (e) {
      setState(() => _isSearching = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Keresési hiba: $e'), backgroundColor: Colors.red));
    }
  }
  // --- NEW: THE DETAILS BOTTOM SHEET ---
  void _showItemDetails(Map<String, dynamic> item) {
    // Call global function instead of Flutter's default
    showSafeBottomSheet(
      context: context,
      child: Column( 
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item['name'] ?? 'Ismeretlen Termék', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          Text(item['brand'] ?? 'Ismeretlen Márka', style: const TextStyle(fontSize: 16, color: Colors.grey)),
          const Divider(height: 30),
          
              _buildDetailRow('Ár (Price):', '${item['price_est']} Ft', isHighlight: true),
              _buildDetailRow('Kategória:', item['category'] ?? '-'),
              _buildDetailRow('Méret (Size):', item['size'] ?? '-'),
              _buildDetailRow('Szín (Color):', item['color'] ?? '-'),
              _buildDetailRow('Minta (Pattern):', item['pattern'] ?? '-'),
              _buildDetailRow('Állapot (Condition):', item['condition'] ?? '-'),
          
          const SizedBox(height: 25),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.check),
              label: const Text('Rendben (Got it)'),
              style: FilledButton.styleFrom(padding: const EdgeInsets.all(15)),
            ),
          )
        ],
      ),
    );
  }
  // A tiny helper widget to make the list look clean
  Widget _buildDetailRow(String label, String value, {bool isHighlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 14)),
          Text(value, style: TextStyle(
            fontWeight: isHighlight ? FontWeight.bold : FontWeight.w600,
            fontSize: isHighlight ? 20 : 16,
            color: isHighlight ? Colors.green[700] : Colors.black87,
          )),
        ],
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Kereső (Reverse Search)'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      backgroundColor: Colors.grey[100],
      body: Column(
        children: [
          // --- TOP SECTION: CAMERA & AI STATUS ---
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Thumbnail Preview
                GestureDetector(
                  onTap: () => _pickImage(ImageSource.camera),
                  child: Container(
                    height: 100, width: 100,
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[400]!),
                    ),
                    child: _searchImage != null
                        ? ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(_searchImage!, fit: BoxFit.cover))
                        : const Icon(Icons.camera_alt, color: Colors.grey, size: 40),
                  ),
                ),
                const SizedBox(width: 16),
                
                // Search Button & Status
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_searchImage != null && !_isSearching && _searchResults.isEmpty)
                        FilledButton.icon(
                          onPressed: _executeSearch,
                          icon: const Icon(Icons.search),
                          label: const Text('Keresés (Search)'),
                        ),
                      if (_isSearching)
                        const Row(children: [CircularProgressIndicator(), SizedBox(width: 10), Text("AI elemzés...")]),
                      if (_aiCriteria != null) ...[
                        const Text("AI Keresési szűrők:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
                        Text("${_aiCriteria!['category']} | ${_aiCriteria!['color']} | ${_aiCriteria!['pattern']}", style: const TextStyle(fontWeight: FontWeight.bold)),
                      ]
                    ],
                  ),
                )
              ],
            ),
          ),
          
          // --- BOTTOM SECTION: RESULTS GRID ---
          Expanded(
            child: _searchResults.isEmpty
              ? Center(
                  child: Text(
                    _searchImage == null ? 'Készíts egy fotót a kereséshez!' : 'Nincs találat. (No exact matches found)', 
                    style: const TextStyle(color: Colors.grey)
                  )
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(10),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2, childAspectRatio: 0.7, crossAxisSpacing: 10, mainAxisSpacing: 10,
                  ),
                  itemCount: _searchResults.length,
                  itemBuilder: (context, index) {
                    final item = _searchResults[index];
                    
                    // --- CHANGED: WRAPPED IN INKWELL ---
                    return InkWell(
                      onTap: () => _showItemDetails(item), // Opens the details sheet!
                      borderRadius: BorderRadius.circular(12),
                      child: Card(
                        clipBehavior: Clip.antiAlias,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Container(
                                width: double.infinity, color: Colors.grey[200],
                                child: item['image_url'] != null ? Image.network(item['image_url'], fit: BoxFit.cover) : const Icon(Icons.image_not_supported),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item['brand'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
                                  Text(item['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  Text('${item['price_est']} Ft', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green[700])),
                                ],
                              ),
                            ),
                          ],
                        ),
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
// --- GLOBAL HELPER FUNCTION ---
Future<T?> showSafeBottomSheet<T>({
  required BuildContext context,
  required Widget child, 
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true, // Fixes the 50% height limit
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (BuildContext context) {
      return SafeArea( // Protects against the system navigation bar
        child: Padding(
          // Protects against the keyboard covering input fields
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom, 
            left: 20, 
            right: 20, 
            top: 20
          ),
          child: SingleChildScrollView( // Protects against overflow crashes
            child: child,
          ),
        ),
      );
    },
  );
}