import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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