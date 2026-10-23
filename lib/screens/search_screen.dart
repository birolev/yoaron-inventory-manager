import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yoaron_app/constants/categories.dart';

import 'package:yoaron_app/widgets/safe_bottom_sheet.dart';

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
  String _selectedLocation = 'All locations';
  static const _locations = ['All locations', 'Csengery', 'Astoria'];

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: 50,
        maxWidth: 600,
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
      final response = await Supabase.instance.client.functions.invoke(
        'gemini-vision',
        body: {
          'task': 'search',
          'imageBase64': base64Image,
          'mimeType': 'image/jpeg',
        },
      );

      if (response.status != 200) throw Exception('Image analysis failed: ${response.data}');
      final aiResult = response.data as Map<String, dynamic>;
      String searchCategory = aiResult['category'] ?? '';
      String searchColor = aiResult['color'] ?? '';
      
      // Save criteria to show the user what the AI is looking for
      setState(() => _aiCriteria = aiResult);

      // 3. Query Supabase
      // look for unsold items that match the category
      var query = Supabase.instance.client
          .from('inventory')
          .select()
          .eq('is_sold', false); // Only search items currently in the store

      if (_selectedLocation != 'All locations') {
        query = query.eq('location', _selectedLocation);
      }

      // Apply filters if AI found them
      if (clothingCategories.contains(searchCategory)) {
        query = query.eq('category', searchCategory);
      }
      if (searchColor.isNotEmpty) {
        query = query.ilike('color', '%$searchColor%'); 
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
  
  void _showItemDetails(Map<String, dynamic> item) {
    
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
              _buildDetailRow('Location:', item['location'] ?? 'Csengery'),
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
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _selectedLocation,
                  decoration: const InputDecoration(
                    labelText: 'Search location',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.store),
                    isDense: true,
                  ),
                  items: _locations
                      .map((location) => DropdownMenuItem(
                            value: location,
                            child: Text(location),
                          ))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _selectedLocation = value;
                        _searchResults = [];
                        _aiCriteria = null;
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),
                Row(
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
                                  Text(item['location'] ?? 'Csengery', style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
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
/*Future<T?> showSafeBottomSheet<T>({
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
}*/
