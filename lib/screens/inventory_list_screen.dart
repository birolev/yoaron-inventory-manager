import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yoaron_app/constants/categories.dart';

import 'sales_screen.dart';
import '../widgets/safe_bottom_sheet.dart';

class InventoryListScreen extends StatefulWidget {
  const InventoryListScreen({super.key});

  @override
  State<InventoryListScreen> createState() => _InventoryListScreenState();
}

class _InventoryListScreenState extends State<InventoryListScreen> {
  List<dynamic> _inventory = [];
  bool _isLoading = true;
  bool _filtersExpanded = true;

  String _selectedFilter = 'Minden';
  String _selectedGenderFilter = 'Minden';
  String _selectedLocationFilter = 'All locations';
  String _selectedSizeFilter = '';
  String _selectedBrandFilter = '';
  String _selectedColorFilter = '';
  final TextEditingController _sizeFilterController = TextEditingController();
  final TextEditingController _brandFilterController = TextEditingController();
  final TextEditingController _colorFilterController = TextEditingController();
  static const _locations = ['Csengery', 'Astoria'];
  static const _colorFamilies = <List<String>>[
    ['kék', 'kek', 'blue', 'navy', 'tengerészkék', 'azúr', 'türkiz', 'cyan'],
    [
      'pink', 'rózsaszín', 'rozsaszin', 'magenta', 'magneta', 'fukszia',
      'fuchsia', 'ciklámen', 'ciklamen',
    ],
    ['piros', 'vörös', 'voros', 'red', 'bordó', 'bordo', 'burgundy'],
    ['zöld', 'zold', 'green', 'olíva', 'oliva', 'khaki'],
    ['sárga', 'sarga', 'yellow', 'mustár', 'mustard'],
    ['narancs', 'orange', 'barack', 'peach'],
    ['lila', 'purple', 'ibolya', 'violet', 'levendula', 'lavender'],
    ['barna', 'brown', 'csoki', 'chocolate', 'bézs', 'beige'],
    ['szürke', 'szurke', 'grey', 'gray', 'ezüst', 'silver'],
    ['fehér', 'feher', 'white', 'krém', 'krem', 'ivory'],
    ['fekete', 'black'],
  ];
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
      const pageSize = 1000;
      final data = <dynamic>[];
      var offset = 0;

      while (true) {
        var query = Supabase.instance.client.from('inventory').select();

        if (_selectedFilter != 'Minden') {
          query = query.eq('category', _selectedFilter);
        }
        if (_selectedGenderFilter != 'Minden') {
          query = query.eq('gender', _selectedGenderFilter);
        }
        if (_selectedLocationFilter != 'All locations') {
          query = query.eq('location', _selectedLocationFilter);
        }
        if (_selectedSizeFilter.trim().isNotEmpty) {
          query = query.ilike('size', _selectedSizeFilter.trim());
        }
        if (_selectedBrandFilter.trim().isNotEmpty) {
          query = query.ilike('brand', '%${_selectedBrandFilter.trim()}%');
        }
        if (_selectedColorFilter.trim().isNotEmpty) {
          final terms = _colorSearchTerms(_selectedColorFilter);
          query = query.or(
            terms.map((term) => 'color.ilike.%$term%').join(','),
          );
        }

        final page = await query
            .order(_sortColumn, ascending: _sortAscending)
            .order('id')
            .range(offset, offset + pageSize - 1);
        data.addAll(page);
        if (page.length < pageSize) break;
        offset += pageSize;
      }

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

  @override
  void dispose() {
    _sizeFilterController.dispose();
    _brandFilterController.dispose();
    _colorFilterController.dispose();
    super.dispose();
  }

  List<String> _colorSearchTerms(String input) {
    final normalized = input.trim().toLowerCase();
    for (final family in _colorFamilies) {
      if (family.any((term) => normalized.contains(term))) return family;
    }
    return [input.trim()];
  }

  Future<String?> _chooseCategory() async {
    final controller = TextEditingController();
    var matchingCategories = filterCategories;
    final selection = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Search category'),
          content: SizedBox(
            width: double.maxFinite,
            height: MediaQuery.sizeOf(context).height * 0.6,
            child: Column(
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Type a category, e.g. hoo',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    setDialogState(() {
                      matchingCategories = filterCategories
                          .where(
                            (category) => category.toLowerCase().contains(
                              value.trim().toLowerCase(),
                            ),
                          )
                          .toList();
                    });
                  },
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: matchingCategories.isEmpty
                      ? const Center(child: Text('No matching categories'))
                      : ListView.builder(
                          itemCount: matchingCategories.length,
                          itemBuilder: (context, index) {
                            final category = matchingCategories[index];
                            return ListTile(
                              title: Text(category),
                              selected: category == _selectedFilter,
                              onTap: () =>
                                  Navigator.pop(dialogContext, category),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    controller.dispose();
    return selection;
  }

  Future<void> _updateItem(
    dynamic id,
    String name,
    String brand,
    double price,
    String category,
    String gender,
    String location,
    bool isSold,
  ) async {
    await Supabase.instance.client
        .from('inventory')
        .update({
          'name': name,
          'brand': brand,
          'price_est': price,
          'category': category,
          'gender': gender,
          'location': location,
          'is_sold': isSold,
        })
        .eq('id', id);

    if (mounted) Navigator.pop(context);
    _fetchInventory();
  }

  Future<void> _deleteItem(dynamic id) async {
    bool confirm =
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Törlés (Delete)'),
            content: const Text('Biztosan törlöd ezt a terméket?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Mégse'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
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
      await Supabase.instance.client.from('inventory').delete().eq('id', id);

      if (mounted) {
        Navigator.pop(context);
      }

      _fetchInventory();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Termék törölve! (Deleted)'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hiba: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showEditSheet(Map<String, dynamic> item) {
    final nameCtrl = TextEditingController(text: item['name']);

    final brandCtrl = TextEditingController(text: item['brand']);

    final priceCtrl = TextEditingController(text: item['price_est'].toString());

    final sizeCtrl = TextEditingController(text: item['size']);

    bool itemIsSold = item['is_sold'] ?? false;
    final imageUrl = item['image_url'] as String?;

    final editCategories = clothingCategories;

    String selectedCat = editCategories.contains(item['category'])
        ? item['category']
        : defaultClothingCategory;
    String selectedGender = genderOptions.contains(item['gender'])
        ? item['gender']
        : defaultClothingGender;
    String selectedLocation = _locations.contains(item['location'])
        ? item['location']
        : _locations.first;

    showSafeBottomSheet(
      context: context,
      child: StatefulBuilder(
        builder: (context, setSheetState) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (imageUrl != null && imageUrl.isNotEmpty) ...[
                GestureDetector(
                  onTap: () => _showFullImage(imageUrl),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      height: 300,
                      width: double.infinity,
                      color: Colors.black12,
                      child: Image.network(
                        imageUrl,
                        fit: BoxFit.contain,
                        loadingBuilder: (context, child, progress) =>
                            progress == null
                            ? child
                            : const Center(child: CircularProgressIndicator()),
                        errorBuilder: (context, error, stackTrace) =>
                            const Center(
                              child: Icon(
                                Icons.broken_image,
                                size: 48,
                                color: Colors.grey,
                              ),
                            ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              const Text(
                'Termék Szerkesztése',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 15),

              SwitchListTile(
                title: const Text(
                  'Eladva (Mark as Sold)',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                activeThumbColor: Colors.green,
                value: itemIsSold,
                onChanged: (bool val) {
                  setSheetState(() => itemIsSold = val);
                },
              ),

              const Divider(),

              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Név',
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 10),

              TextField(
                controller: brandCtrl,
                decoration: const InputDecoration(
                  labelText: 'Márka',
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 10),

              TextField(
                controller: priceCtrl,
                decoration: const InputDecoration(
                  labelText: 'Ár (Ft)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),

              const SizedBox(height: 10),

              TextField(
                controller: sizeCtrl,
                decoration: const InputDecoration(
                  labelText: 'Méret',
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 10),

              DropdownButtonFormField<String>(
                initialValue: selectedCat,
                decoration: const InputDecoration(
                  labelText: 'Kategória',
                  border: OutlineInputBorder(),
                ),
                items: editCategories
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (val) {
                  setSheetState(() => selectedCat = val!);
                },
              ),

              const SizedBox(height: 10),

              DropdownButtonFormField<String>(
                initialValue: selectedGender,
                decoration: const InputDecoration(
                  labelText: 'Nem / Gender',
                  border: OutlineInputBorder(),
                ),
                items: genderOptions
                    .map(
                      (gender) =>
                          DropdownMenuItem(value: gender, child: Text(gender)),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setSheetState(() => selectedGender = value);
                  }
                },
              ),

              const SizedBox(height: 10),

              DropdownButtonFormField<String>(
                initialValue: selectedLocation,
                decoration: const InputDecoration(
                  labelText: 'Store location',
                  border: OutlineInputBorder(),
                ),
                items: _locations
                    .map(
                      (location) => DropdownMenuItem(
                        value: location,
                        child: Text(location),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setSheetState(() => selectedLocation = value);
                  }
                },
              ),

              const SizedBox(height: 25),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _deleteItem(item['id']),
                      icon: const Icon(Icons.delete, color: Colors.red),
                      label: const Text(
                        'Törlés',
                        style: TextStyle(color: Colors.red),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                      ),
                    ),
                  ),

                  const SizedBox(width: 15),

                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: () {
                        _updateItem(
                          item['id'],
                          nameCtrl.text,
                          brandCtrl.text,
                          double.tryParse(priceCtrl.text) ?? 0.0,
                          selectedCat,
                          selectedGender,
                          selectedLocation,
                          itemIsSold,
                        );
                      },
                      icon: const Icon(Icons.save),
                      label: const Text('Mentés'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        backgroundColor: Colors.green[700],
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

  void _showFullImage(String imageUrl) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: SizedBox(
          width: MediaQuery.sizeOf(dialogContext).width * 0.9,
          height: MediaQuery.sizeOf(dialogContext).height * 0.8,
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 4,
            child: Image.network(
              imageUrl,
              fit: BoxFit.contain,
              loadingBuilder: (context, child, progress) => progress == null
                  ? child
                  : const Center(child: CircularProgressIndicator()),
              errorBuilder: (context, error, stackTrace) => const Center(
                child: Icon(Icons.broken_image, size: 48, color: Colors.grey),
              ),
            ),
          ),
        ),
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
          IconButton(
            tooltip: 'Record sale',
            icon: const Icon(Icons.point_of_sale),
            onPressed: () async {
              final recorded = await Navigator.push<bool>(
                context,
                MaterialPageRoute(builder: (_) => const SalesScreen()),
              );
              if (recorded == true) _fetchInventory();
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort),
            tooltip: 'Rendezés (Sort)',
            onSelected: (String result) {
              setState(() {
                if (result == 'newest') {
                  _sortColumn = 'created_at';
                  _sortAscending = false;
                } else if (result == 'oldest') {
                  _sortColumn = 'created_at';
                  _sortAscending = true;
                } else if (result == 'price_low') {
                  _sortColumn = 'price_est';
                  _sortAscending = true;
                } else if (result == 'price_high') {
                  _sortColumn = 'price_est';
                  _sortAscending = false;
                }
              });
              _fetchInventory();
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'newest',
                child: Text('Legújabb elöl (Newest)'),
              ),
              const PopupMenuItem<String>(
                value: 'oldest',
                child: Text('Legrégebbi elöl (Oldest)'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: 'price_low',
                child: Text('Legolcsóbb elöl (Price: Low-High)'),
              ),
              const PopupMenuItem<String>(
                value: 'price_high',
                child: Text('Legdrágább elöl (Price: High-Low)'),
              ),
            ],
          ),
        ],
      ),
      backgroundColor: Colors.grey[100],
      body: Column(
        children: [
          // --- THE FILTER MENU ---
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Inventory filters',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () =>
                          setState(() => _filtersExpanded = !_filtersExpanded),
                      icon: Icon(
                        _filtersExpanded ? Icons.expand_less : Icons.tune,
                      ),
                      label: Text(_filtersExpanded ? 'Hide' : 'Edit'),
                    ),
                  ],
                ),
                if (_filtersExpanded) ...[
                  InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: () async {
                      final category = await _chooseCategory();
                      if (category == null || !mounted) return;
                      setState(() => _selectedFilter = category);
                      _fetchInventory();
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Category',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.category),
                        suffixIcon: Icon(Icons.arrow_drop_down),
                        isDense: true,
                      ),
                      child: Text(_selectedFilter),
                    ),
                  ),
                  SizedBox(
                    height: 56,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: ['Minden', ...genderOptions].map((gender) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(gender),
                            selected: gender == _selectedGenderFilter,
                            onSelected: (_) {
                              setState(() => _selectedGenderFilter = gender);
                              _fetchInventory();
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  SizedBox(
                    height: 48,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: ['All locations', ..._locations].map((
                        location,
                      ) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(location),
                            selected: location == _selectedLocationFilter,
                            onSelected: (_) {
                              setState(
                                () => _selectedLocationFilter = location,
                              );
                              _fetchInventory();
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  SizedBox(
                    height: 56,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TextField(
                        controller: _sizeFilterController,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (value) {
                          setState(() => _selectedSizeFilter = value.trim());
                          _fetchInventory();
                        },
                        decoration: InputDecoration(
                          labelText: 'Filter by size',
                          hintText: 'e.g. M, 32, 42',
                          prefixIcon: const Icon(Icons.straighten),
                          suffixIcon: IconButton(
                            tooltip: 'Apply size filter',
                            icon: const Icon(Icons.search),
                            onPressed: () {
                              setState(
                                () => _selectedSizeFilter =
                                    _sizeFilterController.text.trim(),
                              );
                              _fetchInventory();
                            },
                          ),
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 56,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TextField(
                        controller: _brandFilterController,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (value) {
                          setState(() => _selectedBrandFilter = value.trim());
                          _fetchInventory();
                        },
                        decoration: InputDecoration(
                          labelText: 'Filter by brand',
                          hintText: 'e.g. Nike',
                          prefixIcon: const Icon(Icons.branding_watermark),
                          suffixIcon: IconButton(
                            tooltip: 'Apply brand filter',
                            icon: const Icon(Icons.search),
                            onPressed: () {
                              setState(
                                () => _selectedBrandFilter =
                                    _brandFilterController.text.trim(),
                              );
                              _fetchInventory();
                            },
                          ),
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 56,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TextField(
                        controller: _colorFilterController,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (value) {
                          setState(() => _selectedColorFilter = value.trim());
                          _fetchInventory();
                        },
                        decoration: InputDecoration(
                          labelText: 'Filter by color',
                          hintText: 'e.g. kék (all shades), pink, magenta',
                          prefixIcon: const Icon(Icons.color_lens),
                          suffixIcon: IconButton(
                            tooltip: 'Apply color filter',
                            icon: const Icon(Icons.search),
                            onPressed: () {
                              setState(
                                () => _selectedColorFilter =
                                    _colorFilterController.text.trim(),
                              );
                              _fetchInventory();
                            },
                          ),
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ),
                ] else
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Category: $_selectedFilter · Gender: $_selectedGenderFilter · '
                        'Location: $_selectedLocationFilter'
                        '${_selectedSizeFilter.isEmpty ? '' : ' · Size: $_selectedSizeFilter'}'
                        '${_selectedBrandFilter.isEmpty ? '' : ' · Brand: $_selectedBrandFilter'}'
                        '${_selectedColorFilter.isEmpty ? '' : ' · Color: $_selectedColorFilter'}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.blueGrey,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Showing ${_inventory.length} items',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ),

          // --- THE GRID VIEW ---
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _inventory.isEmpty
                ? const Center(
                    child: Text(
                      'Nincs találat (No items found)',
                      style: TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(10),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
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
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Container(
                                  width: double.infinity,
                                  color: Colors.grey[200],
                                  child: item['image_url'] != null
                                      ? Image.network(
                                          item['image_url'],
                                          fit: BoxFit.cover,
                                        )
                                      : const Icon(
                                          Icons.image_not_supported,
                                          color: Colors.grey,
                                        ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item['brand'] ?? 'Unknown Brand',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      item['name'] ?? 'Unknown Item',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${item['price_est']} Ft',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        color: Colors.green[700],
                                      ),
                                    ),
                                    Text(
                                      item['location'] ?? 'Csengery',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.blueGrey,
                                      ),
                                    ),
                                    Text(
                                      '${item['category'] ?? '-'} · ${item['gender'] ?? '-'}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.blueGrey,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
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
