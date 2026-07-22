import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yoaron_app/constants/categories.dart';


import '../widgets/safe_bottom_sheet.dart';

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

  @override
  void initState() {
    super.initState();
    _fetchInventory();
  }

  Future<void> _fetchInventory() async {
    setState(() => _isLoading = true);
    try {
      var query = Supabase.instance.client.from('inventory').select();

      if (_selectedFilter != 'Minden') {
        query = query.eq('category', _selectedFilter);
      }

      final data = await query.order(
        _sortColumn,
        ascending: _sortAscending,
      );

      setState(() {
        _inventory = data;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hiba a betöltésnél: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _updateItem(
    dynamic id,
    String name,
    String brand,
    double price,
    String category,
    bool isSold,
  ) async {
    await Supabase.instance.client.from('inventory').update({
      'name': name,
      'brand': brand,
      'price_est': price,
      'category': category,
      'is_sold': isSold,
    }).eq('id', id);

    if (mounted) Navigator.pop(context);
    _fetchInventory();
  }

 Future<void> _deleteItem(dynamic id) async {
    bool confirm = await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Törlés (Delete)'),
            content: const Text(
              'Biztosan törlöd ezt a terméket?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(
                  context,
                  false,
                ),
                child: const Text('Mégse'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(
                  context,
                  true,
                ),
                child: const Text(
                  'Törlés',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirm) return;

    try {
      await Supabase.instance.client
          .from('inventory')
          .delete()
          .eq('id', id);

      if (mounted) {
        Navigator.pop(context);
      }

      _fetchInventory();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Termék törölve! (Deleted)',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hiba: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showEditSheet(
    Map<String, dynamic> item,
  ) {
    final nameCtrl = TextEditingController(
      text: item['name'],
    );

    final brandCtrl = TextEditingController(
      text: item['brand'],
    );

    final priceCtrl = TextEditingController(
      text: item['price_est'].toString(),
    );

    final sizeCtrl = TextEditingController(
      text: item['size'],
    );

    bool itemIsSold = item['is_sold'] ?? false;

    final editCategories =
        filterCategories
            .where((c) => c != 'Minden')
            .toList();

    String selectedCat =
        editCategories.contains(item['category'])
            ? item['category']
            : editCategories.first;

    showSafeBottomSheet(
      context: context,
      child: StatefulBuilder(
        builder: (
          context,
          setSheetState,
        ) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Termék Szerkesztése',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 15),

              SwitchListTile(
                title: const Text(
                  'Eladva (Mark as Sold)',
                  style: TextStyle(
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
                activeThumbColor:
                    Colors.green,
                value: itemIsSold,
                onChanged: (bool val) {
                  setSheetState(
                    () => itemIsSold = val,
                  );
                },
              ),

              const Divider(),

              TextField(
                controller: nameCtrl,
                decoration:
                    const InputDecoration(
                  labelText: 'Név',
                  border:
                      OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 10),

              TextField(
                controller: brandCtrl,
                decoration:
                    const InputDecoration(
                  labelText: 'Márka',
                  border:
                      OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 10),

              TextField(
                controller: priceCtrl,
                decoration:
                    const InputDecoration(
                  labelText: 'Ár (Ft)',
                  border:
                      OutlineInputBorder(),
                ),
                keyboardType:
                    TextInputType.number,
              ),

              const SizedBox(height: 10),

              TextField(
                controller: sizeCtrl,
                decoration:
                    const InputDecoration(
                  labelText: 'Méret',
                  border:
                      OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 10),

              DropdownButtonFormField<String>(
                initialValue:
                    selectedCat,
                decoration:
                    const InputDecoration(
                  labelText:
                      'Kategória',
                  border:
                      OutlineInputBorder(),
                ),
                items: editCategories
                    .map(
                      (c) =>
                          DropdownMenuItem(
                        value: c,
                        child: Text(c),
                      ),
                    )
                    .toList(),
                onChanged: (val) {
                  setSheetState(
                    () => selectedCat =
                        val!,
                  );
                },
              ),

              const SizedBox(height: 25),

              Row(
                children: [
                  Expanded(
                    child:
                        OutlinedButton.icon(
                      onPressed: () =>
                          _deleteItem(
                        item['id'],
                      ),
                      icon: const Icon(
                        Icons.delete,
                        color: Colors.red,
                      ),
                      label: const Text(
                        'Törlés',
                        style: TextStyle(
                          color:
                              Colors.red,
                        ),
                      ),
                      style:
                          OutlinedButton.styleFrom(
                        side:
                            const BorderSide(
                          color:
                              Colors.red,
                        ),
                        padding:
                            const EdgeInsets.symmetric(
                          vertical: 15,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 15),

                  Expanded(
                    flex: 2,
                    child:
                        FilledButton.icon(
                      onPressed: () {
                        _updateItem(
                          item['id'],
                          nameCtrl.text,
                          brandCtrl.text,
                          double.tryParse(
                                priceCtrl.text,
                              ) ??
                              0.0,
                          selectedCat,
                          itemIsSold,
                        );
                      },
                      icon: const Icon(
                        Icons.save,
                      ),
                      label:
                          const Text(
                        'Mentés',
                      ),
                      style:
                          FilledButton.styleFrom(
                        padding:
                            const EdgeInsets.symmetric(
                          vertical: 15,
                        ),
                        backgroundColor:
                            Colors.green[
                                700],
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Paste the unchanged build() implementation from your original file here.
    // We couldn't fit it into chat due to response size limits.
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
              itemCount: filterCategories.length,
              itemBuilder: (context, index) {
                final category = filterCategories[index];
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

