import 'package:untitled2/code//random_forest_model.dart';
import 'package:untitled2/code//sensor_data_processor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:math' as math;

class MeasurePage extends StatefulWidget {
  final String userName;
  final String? gender;
  final String? birthday;

  const MeasurePage({
    Key? key,
    required this.userName,
    this.gender,
    this.birthday,
  }) : super(key: key);

  @override
  _MeasurePageState createState() => _MeasurePageState();
}

class _MeasurePageState extends State<MeasurePage> {
  final RandomForestModel _rfModel = RandomForestModel();
  final TextEditingController _pathController1 = TextEditingController();
  final TextEditingController _pathController2 = TextEditingController();
  final TextEditingController _pathController3 = TextEditingController();
  bool _isModelLoaded = false;
  bool _isProcessing = false;
  String _status = '準備載入模型和資料';
  String _predictionResult = '未進行預測';

  // 儲存解析後的傳感器資料
  List<List<double>> _sensorData1 = [];
  List<List<double>> _sensorData2 = [];
  List<List<double>> _sensorData3 = [];

  String? _uploadedFileName1;
  String? _uploadedFileName2;
  String? _uploadedFileName3;

  // 顯示用戶信息的對話框
  void _showUserInfoDialog() {
    showCupertinoDialog(
      context: context,
      builder: (BuildContext context) {
        return CupertinoAlertDialog(
          title: Text("User Info"),
          content: Column(
            children: [
              SizedBox(height: 10),
              Text("Name: ${widget.userName}"),
              SizedBox(height: 5),
              Text("Gender: ${widget.gender ?? 'None'}"),
              SizedBox(height: 5),
              Text("Birthday: ${widget.birthday ?? 'None'}"),
            ],
          ),
          actions: [
            CupertinoDialogAction(
              child: Text("Close"),
              isDefaultAction: true,
              onPressed: () {
                Navigator.pop(context);
              },
            ),
          ],
        );
      },
    );
  }

  void _showHelpDialog() {
    showCupertinoDialog(
      context: context,
      builder: (BuildContext context) {
        return CupertinoAlertDialog(
          title: Text("Info"),
          content: Text("This system is made by \n ZWX, CYL, WBY! \n Version: 1.0.0"),
          actions: [
            CupertinoDialogAction(
              child: Text("Good Job!"),
              isDefaultAction: true,
              onPressed: () {
                Navigator.pop(context);
              },
            ),
          ],
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _loadModel();
  }

  @override
  void dispose() {
    _pathController1.dispose();
    _pathController2.dispose();
    _pathController3.dispose();
    super.dispose();
  }

  // 載入模型
  Future<void> _loadModel() async {
    try {
      setState(() {
        _status = '正在載入模型...';
      });

      await _rfModel.loadModel();

      setState(() {
        _isModelLoaded = true;
        _status = '模型已成功載入，請選擇三個資料檔案或輸入本機檔案路徑';
      });
    } catch (e) {
      setState(() {
        _status = '模型載入失敗: $e';
      });
      print('模型載入錯誤: $e');
    }
  }

  // 從檔案選擇器讀取CSV資料
  Future<void> _loadCSVData(int fileIndex) async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['csv']);

    if (result != null) {
      File file = File(result.files.single.path!);
      String fileName = file.path.split('/').last;
      String rawData = await file.readAsString();

      setState(() {
        if (fileIndex == 1) {
          _uploadedFileName1 = fileName;
          _processCSVString(rawData, fileIndex);
        } else if (fileIndex == 2) {
          _uploadedFileName2 = fileName;
          _processCSVString(rawData, fileIndex);
        } else if (fileIndex == 3) {
          _uploadedFileName3 = fileName;
          _processCSVString(rawData, fileIndex);
        }
      });
    }
  }

  // 從文本輸入解析CSV
  Future<void> _parseCSVText() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('直接輸入CSV資料'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('請將CSV資料複製並貼上於此:'),
            SizedBox(height: 8),
            Expanded(
              child: TextField(
                controller: _pathController,
                maxLines: 10,
                decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '時間戳,加速度X,加速度Y,加速度Z,...',
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              String csvText = _pathController.text.trim();
              if (csvText.isNotEmpty) {
                Navigator.pop(context);
                _processCSVString(csvText);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(0xFF9F35FF),
            ),
            child: Text('解析'),
          ),
        ],
      ),
    );
  }

  // 從應用內部目錄讀取檔案
  Future<void> _loadFileFromAssets() async {
    setState(() {
      _isProcessing = true;
      _status = '正在從應用內部讀取檔案...';
      _sensorData = [];
    });

    try {
      // 讀取應用資源中的CSV檔案
      final String rawData = await rootBundle.loadString('assets/data/sample.csv');
      _uploadedFileName = "sample.csv";
      await _processCSVString(rawData);
    } catch (e) {
      setState(() {
        _status = '檔案讀取失敗: $e';
        _isProcessing = false;
      });
      print('檔案讀取錯誤: $e');
    }
  }

  // 處理CSV字符串
  Future<void> _processCSVString(String csvString, int fileIndex) async {
    setState(() {
      _isProcessing = true;
      _status = '正在處理CSV資料...';
    });

    try {
      List<List<dynamic>> csvTable = const CsvToListConverter().convert(csvString);

      // 移除標題行
      if (csvTable.isNotEmpty) {
        csvTable.removeAt(0);
      }

      // 將資料轉換為數值型別
      List<List<double>> sensorData = [];
      for (var row in csvTable) {
        List<double> numericRow = row.map((e) => e is num ? e.toDouble() : double.tryParse(e.toString()) ?? 0.0).toList();
        sensorData.add(numericRow);
      }

      setState(() {
        if (fileIndex == 1) {
          _sensorData1 = sensorData;
        } else if (fileIndex == 2) {
          _sensorData2 = sensorData;
        } else if (fileIndex == 3) {
          _sensorData3 = sensorData;
        }
        _status = '資料載入完成';
        _isProcessing = false;
      });
    } catch (e) {
      setState(() {
        _status = '資料解析失敗: $e';
        _isProcessing = false;
      });
      print('資料解析錯誤: $e');
    }
  }

  // 自定義數據處理方法
  Future<void> _processData() async {
    if (_sensorData1.isEmpty || _sensorData2.isEmpty || _sensorData3.isEmpty) {
      setState(() {
        _status = '必須上傳三個檔案才能進行預測';
      });
      return;
    }

    setState(() {
      _isProcessing = true;
      _status = '正在處理資料並進行預測...';
    });

    try {
      // 假設CSV資料結構為: 時間戳,加速度X,加速度Y,加速度Z,陀螺儀X,陀螺儀Y,陀螺儀Z
      List<double> accelX1 = _sensorData1.map((row) => row[1]).toList();
      List<double> accelY1 = _sensorData1.map((row) => row[2]).toList();
      List<double> accelZ1 = _sensorData1.map((row) => row[3]).toList();
      List<double> gyroX1 = _sensorData1.map((row) => row[4]).toList();
      List<double> gyroY1 = _sensorData1.map((row) => row[5]).toList();
      List<double> gyroZ1 = _sensorData1.map((row) => row[6]).toList();

      List<double> accelX2 = _sensorData2.map((row) => row[1]).toList();
      List<double> accelY2 = _sensorData2.map((row) => row[2]).toList();
      List<double> accelZ2 = _sensorData2.map((row) => row[3]).toList();
      List<double> gyroX2 = _sensorData2.map((row) => row[4]).toList();
      List<double> gyroY2 = _sensorData2.map((row) => row[5]).toList();
      List<double> gyroZ2 = _sensorData2.map((row) => row[6]).toList();

      List<double> accelX3 = _sensorData3.map((row) => row[1]).toList();
      List<double> accelY3 = _sensorData3.map((row) => row[2]).toList();
      List<double> accelZ3 = _sensorData3.map((row) => row[3]).toList();
      List<double> gyroX3 = _sensorData3.map((row) => row[4]).toList();
      List<double> gyroY3 = _sensorData3.map((row) => row[5]).toList();
      List<double> gyroZ3 = _sensorData3.map((row) => row[6]).toList();

      // 自定義處理特徵
      List<double> features = _calculateCustomFeatures(
          accelX1, accelY1, accelZ1, gyroX1, gyroY1, gyroZ1,
          accelX2, accelY2, accelZ2, gyroX2, gyroY2, gyroZ2,
          accelX3, accelY3, accelZ3, gyroX3, gyroY3, gyroZ3
      );

      // 使用模型進行預測
      int prediction = _rfModel.predict(features);
      String predictionDescription = _getPredictionDescription(prediction);

      setState(() {
        _isProcessing = false;
        _status = '預測完成';
        _predictionResult = '預測結果: $predictionDescription (類別 $prediction)';
      });
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _status = '預測處理失敗: $e';
      });
      print('預測處理錯誤: $e');
    }
  }

  // 輔助方法: 調整列表長度
  void _adjustListLength(List<double> list, int targetLength) {
    if (list.length > targetLength) {
      // 截斷列表
      list.removeRange(targetLength, list.length);
    } else if (list.length < targetLength) {
      // 填充列表
      double paddingValue = list.isNotEmpty ? list.last : 0.0;
      list.addAll(List<double>.filled(targetLength - list.length, paddingValue));
    }
  }

  // 輔助方法: 替換異常值
  void _replaceAbnormalValues(List<double> list, String listName, double threshold) {
    int replacedCount = 0;
    for (int i = 0; i < list.length; i++) {
      if (list[i].isNaN || list[i].isInfinite || list[i].abs() > threshold) {
        list[i] = 0.0;
        replacedCount++;
      }
    }
    if (replacedCount > 0) {
      print('替換了 $listName 中的 $replacedCount 個異常值');
    }
  }

  // 自定義特徵計算方法
  List<double> _calculateCustomFeatures(
      List<double> accelX1, List<double> accelY1, List<double> accelZ1,
      List<double> gyroX1, List<double> gyroY1, List<double> gyroZ1,
      List<double> accelX2, List<double> accelY2, List<double> accelZ2,
      List<double> gyroX2, List<double> gyroY2, List<double> gyroZ2,
      List<double> accelX3, List<double> accelY3, List<double> accelZ3,
      List<double> gyroX3, List<double> gyroY3, List<double> gyroZ3) {

    // 計算每個軸的平均值
    double avgAccelX = _calculateAverage(accelX);
    double avgAccelY = _calculateAverage(accelY);
    double avgAccelZ = _calculateAverage(accelZ);
    double avgGyroX = _calculateAverage(gyroX);
    double avgGyroY = _calculateAverage(gyroY);
    double avgGyroZ = _calculateAverage(gyroZ);

    // 計算每個軸的標準差
    double stdAccelX = _calculateStandardDeviation(accelX, avgAccelX);
    double stdAccelY = _calculateStandardDeviation(accelY, avgAccelY);
    double stdAccelZ = _calculateStandardDeviation(accelZ, avgAccelZ);
    double stdGyroX = _calculateStandardDeviation(gyroX, avgGyroX);
    double stdGyroY = _calculateStandardDeviation(gyroY, avgGyroY);
    double stdGyroZ = _calculateStandardDeviation(gyroZ, avgGyroZ);

    // 計算每個軸的最大值和最小值
    double maxAccelX = _findMax(accelX);
    double maxAccelY = _findMax(accelY);
    double maxAccelZ = _findMax(accelZ);
    double minAccelX = _findMin(accelX);
    double minAccelY = _findMin(accelY);
    double minAccelZ = _findMin(accelZ);

    // 計算總加速度的平均值和標準差
    List<double> totalAccel = _calculateTotalAcceleration(accelX, accelY, accelZ);
    double avgTotalAccel = _calculateAverage(totalAccel);
    double stdTotalAccel = _calculateStandardDeviation(totalAccel, avgTotalAccel);

    // 返回特徵向量
    return [];
  }

  // 計算平均值
  double _calculateAverage(List<double> values) {
    if (values.isEmpty) return 0.0;
    double sum = 0.0;
    for (var value in values) {
      sum += value;
    }
    return sum / values.length;
  }

  // 計算標準差
  double _calculateStandardDeviation(List<double> values, double mean) {
    if (values.isEmpty) return 0.0;
    double sumOfSquaredDifferences = 0.0;
    for (var value in values) {
      double difference = value - mean;
      sumOfSquaredDifferences += difference * difference;
    }
    return math.sqrt(sumOfSquaredDifferences / values.length);
  }

  // 計算總加速度
  List<double> _calculateTotalAcceleration(
      List<double> accelX, List<double> accelY, List<double> accelZ) {
    List<double> result = [];
    int length = accelX.length;
    if (length != accelY.length || length != accelZ.length) {
      print('警告: 加速度軸的數據長度不一致');
      length = [accelX.length, accelY.length, accelZ.length].reduce((min, len) => len < min ? len : min);
    }

    for (int i = 0; i < length; i++) {
      double x = accelX[i];
      double y = accelY[i];
      double z = accelZ[i];
      double total = math.sqrt(x*x + y*y + z*z);
      result.add(total);
    }

    return result;
  }

  // 查找最大值
  double _findMax(List<double> values) {
    if (values.isEmpty) return 0.0;
    double max = values[0];
    for (var value in values) {
      if (value > max) max = value;
    }
    return max;
  }

  // 查找最小值
  double _findMin(List<double> values) {
    if (values.isEmpty) return 0.0;
    double min = values[0];
    for (var value in values) {
      if (value < min) min = value;
    }
    return min;
  }

  // 輔助方法: 從特殊字串中提取數字
  double _extractNumberFromString(String input) {
    // 去除"x180"這樣的標記，只保留數字部分
    String numericPart = input.replaceAll(RegExp(r'[^\d.-]'), '');
    if (numericPart.isEmpty) return 0.0;

    try {
      return double.parse(numericPart);
    } catch (e) {
      print('無法從 "$input" 提取數字: $e');
      return 0.0;
    }
  }

  // 輔助方法: 清理數據列表中的可能問題值
  void _sanitizeDataList(List<double> list, String listName) {
    for (int i = 0; i < list.length; i++) {
      // 檢查是否為無效值
      if (list[i].isNaN || list[i].isInfinite) {
        print('發現無效值在 $listName[$i]: ${list[i]}，已替換為0.0');
        list[i] = 0.0;
        continue;
      }

      // 檢查值是否過大（可能是問題數據）
      // 正常的加速度和陀螺儀數據通常在一個合理範圍內
      if (list[i].abs() > 1000000) {
        print('發現可能的問題值在 $listName[$i]: ${list[i]}，已替換為0.0');
        list[i] = 0.0;
      }

      // 檢查是否為可能的"x180"等情況（通過檢查字串表示）
      String strVal = list[i].toString();
      if (strVal.contains("x") || strVal.contains("X")) {
        print('發現可疑字符在值 $listName[$i]: $strVal');
        // 嘗試提取數值部分
        try {
          double cleanValue = double.parse(
              strVal.replaceAll(RegExp(r'[^\d.-]'), '')
          );
          list[i] = cleanValue;
          print('已清理為: ${list[i]}');
        } catch (e) {
          list[i] = 0.0;
          print('無法清理，已設為0');
        }
      }
    }
  }

  // 將預測結果轉換為可讀描述
  String _getPredictionDescription(int predictionClass) {
    switch(predictionClass) {
      case 1: return '刷前牙';
      case 2: return '刷後牙';
      case 3: return '刷左側牙齒';
      case 4: return '刷右側牙齒';
      case 5: return '刷上牙';
      case 6: return '刷下牙';
      case 7: return '刷咬合面';
      case 8: return '刷舌側';
      case 9: return '刷唇側';
      case 10: return '刷頰側';
      default: return '未知刷牙方式';
    }
  }

  // 顯示CSV資料來源選擇對話框
  void _showDataSourceDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('選擇CSV資料來源'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('請選擇CSV資料的來源方式:'),
            SizedBox(height: 20),
            ListTile(
              leading: Icon(Icons.text_fields, color: Color(0xFF9F35FF)),
              title: Text('直接輸入資料'),
              subtitle: Text('將CSV資料複製貼上到應用中'),
              onTap: () {
                Navigator.pop(context);
                _pathController.clear(); // 清空之前的內容
                _parseCSVText();
              },
            ),
            SizedBox(height: 10),
            Divider(),
            SizedBox(height: 10),
            Text(
              '提示: 由於權限限制，此版本僅支援直接輸入資料。在完整版本中，也可以支援從檔案系統讀取檔案。',
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Tooth Brushing \nManagement System", style: TextStyle(fontSize: 18)),
        backgroundColor: Color(0xFFBD9BEB),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: Icon(Icons.person),
            iconSize: 30,
            padding: EdgeInsets.only(right: 10),
            onPressed: _showUserInfoDialog,
          ),
          IconButton(
            icon: Icon(FontAwesomeIcons.circleQuestion),
            iconSize: 30,
            padding: EdgeInsets.only(right: 20),
            onPressed: _showHelpDialog,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: 10),
            Text(
              '使用者: ${widget.userName}',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 20),
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '狀態',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF9F35FF),
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      _status,
                      style: TextStyle(fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 20),
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '資料來源選擇',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF9F35FF),
                      ),
                    ),
                    SizedBox(height: 15),
                    Text(
                      '上傳三個CSV檔案:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: Icon(Icons.upload_file),
                            label: Text('選擇CSV檔案1'),
                            onPressed: _isProcessing ? null : () => _loadCSVData(1),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Color(0xFF9F35FF),
                              padding: EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_uploadedFileName1 != null) ...[
                      SizedBox(height: 10),
                      Text(
                        '已載入資料: $_uploadedFileName1',
                        style: TextStyle(
                          fontSize: 14,
                          fontStyle: FontStyle.italic,
                          color: Colors.green[700],
                        ),
                      ),
                    ],
                    SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: Icon(Icons.upload_file),
                            label: Text('選擇CSV檔案2'),
                            onPressed: _isProcessing ? null : () => _loadCSVData(2),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Color(0xFF9F35FF),
                              padding: EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_uploadedFileName2 != null) ...[
                      SizedBox(height: 10),
                      Text(
                        '已載入資料: $_uploadedFileName2',
                        style: TextStyle(
                          fontSize: 14,
                          fontStyle: FontStyle.italic,
                          color: Colors.green[700],
                        ),
                      ),
                    ],
                    SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: Icon(Icons.upload_file),
                            label: Text('選擇CSV檔案3'),
                            onPressed: _isProcessing ? null : () => _loadCSVData(3),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Color(0xFF9F35FF),
                              padding: EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_uploadedFileName3 != null) ...[
                      SizedBox(height: 10),
                      Text(
                        '已載入資料: $_uploadedFileName3',
                        style: TextStyle(
                          fontSize: 14,
                          fontStyle: FontStyle.italic,
                          color: Colors.green[700],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            SizedBox(height: 20),
            if (_sensorData1.isNotEmpty && _sensorData2.isNotEmpty && _sensorData3.isNotEmpty)
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '資料統計',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF9F35FF),
                        ),
                      ),
                      SizedBox(height: 8),
                      Text('資料記錄總數: ${_sensorData1.length}'),
                      Text('每行欄位數: ${_sensorData1.first.length}'),
                      Text('前五筆資料:'),
                      SizedBox(height: 5),
                      Container(
                        height: 100,
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: EdgeInsets.all(8),
                        child: SingleChildScrollView(
                          child: Text(
                            _sensorData1.take(5).map((row) => row.join(', ')).join('\n'),
                            style: TextStyle(fontFamily: 'monospace'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            SizedBox(height: 20),
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '預測結果',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF9F35FF),
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      _predictionResult,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[700],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: (_isProcessing || _sensorData1.isEmpty || _sensorData2.isEmpty || _sensorData3.isEmpty) ? null : _processData,
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFF9F35FF),
                padding: EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                minimumSize: Size(double.infinity, 50),
              ),
              child: Text(
                _isProcessing ? '處理中...' : '開始分析',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}