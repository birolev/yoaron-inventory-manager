import 'package:image_picker/image_picker.dart';


class QueueItem{
  final XFile image;
  Map<String, dynamic>? aiResult;
  
  bool isAnalyzing = false;
  bool isReady = false;
  QueueItem(this.image);
}

class BatchImageQueue {
  final List<QueueItem> items;

  int currentIndex = 0;

  BatchImageQueue(this.items);

  bool get hasNext =>
      currentIndex < items.length;

  QueueItem get current =>
      items[currentIndex];

  int get total =>
      items.length;

  int get currentNumber =>
      currentIndex + 1;

  void moveNext() {
    currentIndex++;
  } 

  void reset() {
    currentIndex = 0;
  }
}