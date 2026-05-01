import 'package:file_picker/file_picker.dart';

class DirectoryPickerService {
  const DirectoryPickerService();

  Future<String?> pickDirectory() async {
    return FilePicker.platform.getDirectoryPath();
  }
}
