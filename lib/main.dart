import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 用于rootBundle
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_markdown_plus_latex/flutter_markdown_plus_latex.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:csv/csv.dart';
import 'package:fl_chart/fl_chart.dart'; // 引入图表库
import 'package:dio/dio.dart';
import 'dart:convert'; // 用于jsonDecode
import 'dart:async'; // 用于StreamController
import 'package:flutter_dropzone/flutter_dropzone.dart';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:args/args.dart';
import 'dart:ui' as ui;

// 全局主题状态管理器
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);

void main(List<String> arguments) async {
  // 记录所有命令行参数
  print('接收到的命令行参数: $arguments');

  // 创建debug文件夹并写入启动日志
  try {
    final debugDir = Directory('debug');
    if (!await debugDir.exists()) {
      await debugDir.create(recursive: true);
    }
    final now = DateTime.now();
    final logFileName = 'log_${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}.txt';
    final logFile = File('${debugDir.path}/$logFileName');
    final timestamp = DateTime.now().toString().split('.')[0];
    final logEntry = '[$timestamp] 应用启动 - 接收到的命令行参数: $arguments';
    await logFile.writeAsString(logEntry + '\n', mode: FileMode.append, encoding: utf8);
  } catch (e) {
    print('写入启动日志失败: $e');
  }

  // 解析命令行参数（针对Linux桌面环境容错处理）
  final parser = ArgParser()
    ..addOption('file', abbr: 'f', help: '要打开的Markdown文件路径');

  try {
    final results = parser.parse(arguments);
    String? filePath;

    // 策略1: 匹配带有标识的选项参数 (如 -f /path/to/file.md)
    if (results.wasParsed('file')) {
      filePath = results['file'] as String?;
    }
    // 策略2: 匹配匿名位置参数 (Linux文件管理器下执行"以...打开"的默认行为)
    else if (results.rest.isNotEmpty) {
      filePath = results.rest.first;
    }

    if (filePath != null && filePath.isNotEmpty) {
      runApp(MyApp(filePath: filePath));
    } else {
      runApp(MyApp());
    }
  } catch (e) {
    print('解析命令行参数时出错: $e');
    // 终极容错：遍历寻找第一个像路径的参数
    String? fallbackPath;
    for (final arg in arguments) {
      if (!arg.startsWith('-')) {
        fallbackPath = arg;
        break;
      }
    }
    if (fallbackPath != null && fallbackPath.isNotEmpty) {
      runApp(MyApp(filePath: fallbackPath));
    } else {
      runApp(MyApp());
    }
  }
}

class MyApp extends StatelessWidget {
  final String? filePath;

  MyApp({this.filePath});

  @override
  Widget build(BuildContext context) {
    // 监听全局主题状态变化
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, ThemeMode currentMode, __) {
        return MaterialApp(
          title: 'markdown和知识库',
          themeMode: currentMode,
          theme: ThemeData.light().copyWith(
            primaryColor: Colors.blue,
            scaffoldBackgroundColor: Colors.white,
            visualDensity: VisualDensity.adaptivePlatformDensity,
          ),
          darkTheme: ThemeData.dark().copyWith(
            primaryColor: Colors.blue,
            scaffoldBackgroundColor: const Color(0xFF121212),
            visualDensity: VisualDensity.adaptivePlatformDensity,
          ),
          home: MainPage(filePath: filePath),
        );
      },
    );
  }
}

class MainPage extends StatefulWidget {
  final String? filePath;
  MainPage({this.filePath});

  @override
  _MainPageState createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  String _markdownContent = '# 加载中...';
  bool _isLoading = true;
  String? _errorMessage;

  List<Map<String, String>> _articleList = [];
  List<Map<String, String>> _filteredArticleList =[];
  String _currentArticleTitle = '';
  String _currentArticleFilePath = '';
  String? _appDocDirPath;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';

  final String _appVersion = "0.0.0.dev";
  String _dataVersion = "0";

  bool _debugMode = true;
  final List<String> _debugLogs =[];
  StreamController<String>? _debugLogStreamController;

  final TextEditingController _aiMessageController = TextEditingController();
  final List<Map<String, dynamic>> _conversationHistory =[];
  bool _isWaitingForAI = false;
  String _selectedConversationMode = 'general';

  StreamController<String> _streamResponseController = StreamController<String>();
  bool _isStreaming = false;
  bool _isDragOver = false;

  @override
  void initState() {
    super.initState();
    _debugMode = true;
    _logDebug('应用启动 - 调试模式已开启');

    _initAppDocDir();

    if (widget.filePath != null && widget.filePath!.isNotEmpty) {
      _logDebug('通过命令行参数加载文件: ${widget.filePath}');
      _loadMarkdownFile(widget.filePath!);
      setState(() {
        _currentArticleTitle = widget.filePath!.split('/').last;
        _currentArticleFilePath = widget.filePath!;
      });
    } else {
      _logDebug('加载默认文章列表');
      _loadArticleList();
    }
    _searchController.addListener(_onSearchChanged);
  }

  Future<void> _initAppDocDir() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      setState(() {
        _appDocDirPath = directory.path;
      });
    } catch (e) {
      _logDebug('获取应用文档目录失败: $e');
    }
  }

  @override
  void dispose() {
    _streamResponseController.close();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  // ===================== Markdown 核心渲染系统 =====================

  /// LaTeX 公式语法预处理拦截器，将不支持的语法替换为标准语法
  String _preprocessLatex(String text) {
    if (text.isEmpty) return text;
    // 替换行内公式 \( \) 为 $ $
    text = text.replaceAll(r'\(', r'$').replaceAll(r'\)', r'$');
    // 替换块级公式 \[ \] 为 $$ $$
    text = text.replaceAll(r'\[', r'$$').replaceAll(r'\]', r'$$');
    return text;
  }

  /// 自定义图片渲染引擎，兼容标准Markdown规则及Linux文件系统
  Widget _customImageBuilder(Uri uri, String? title, String? alt) {
    final String uriString = uri.toString();
    if (uriString.startsWith('http://') || uriString.startsWith('https://')) {
      return Image.network(uriString, errorBuilder: (c, e, s) => _buildErrorImage(alt ?? uriString));
    }
    if (uriString.startsWith('assets/')) {
      return Image.asset(uriString, errorBuilder: (c, e, s) => _buildErrorImage(alt ?? uriString));
    }
    File imageFile;
    if (uriString.startsWith('/')) {
      imageFile = File(uriString);
    } else {
      if (_currentArticleFilePath.startsWith('/')) {
        final String parentDir = File(_currentArticleFilePath).parent.path;
        imageFile = File('$parentDir/$uriString');
      } else if (_currentArticleFilePath.startsWith('dragged_articles/') && _appDocDirPath != null) {
        final String parentDir = '$_appDocDirPath/dragged_articles';
        imageFile = File('$parentDir/$uriString');
      } else {
        imageFile = File(uriString);
      }
    }
    return Image.file(
      imageFile,
      errorBuilder: (context, error, stackTrace) => _buildErrorImage(alt ?? '本地图片缺失: $uriString'),
    );
  }

  Widget _buildErrorImage(String altText) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[800] : Colors.grey[100],
        border: Border.all(color: isDark ? Colors.grey[700]! : Colors.grey[300]!),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children:[
          Icon(Icons.broken_image, color: Colors.grey[500], size: 16),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              altText,
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// 通用 Markdown 统一构建方法
  Widget _renderMarkdown(String content, {bool isSelectable = false, bool shrinkWrap = false}) {
    final processedContent = _preprocessLatex(content.isEmpty ? "正在检索知识库..." : content);
    return Markdown(
      data: processedContent,
      selectable: isSelectable,
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : const AlwaysScrollableScrollPhysics(),
      imageBuilder: _customImageBuilder,
      builders: {
        'latex': LatexElementBuilder(
          textStyle: const TextStyle(fontWeight: FontWeight.w400, fontSize: 16.0),
          textScaleFactor: 1.2,
        ),
        'code': ChartElementBuilder(),
      },
      extensionSet: md.ExtensionSet(
        [...md.ExtensionSet.gitHubFlavored.blockSyntaxes, LatexBlockSyntax()],
        [...md.ExtensionSet.gitHubFlavored.inlineSyntaxes, LatexInlineSyntax()],
      ),
    );
  }

  Widget _buildMarkdownContent(String content, bool isStreaming) {
    return _renderMarkdown(content, isSelectable: false, shrinkWrap: true);
  }

  Widget _buildChartContent(String chartContent) {
    try {
      final wrappedContent = '```chart\n$chartContent\n```';
      return _renderMarkdown(wrappedContent, isSelectable: false, shrinkWrap: true);
    } catch (e) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.red[300]!),
          borderRadius: BorderRadius.circular(8),
          color: isDark ? Colors.red[900]!.withOpacity(0.3) : Colors.red[50],
        ),
        child: Text('图表渲染错误: $e', style: TextStyle(fontSize: 12, color: Colors.red[800])),
      );
    }
  }

  // ===================== 日志与配置加载 =====================

  void _logDebug(String message) {
    if (_debugMode) {
      final timestamp = DateTime.now().toString().split('.')[0];
      final logEntry = '[$timestamp] $message';
      _debugLogs.add(logEntry);
      print(logEntry);
      if (_debugLogStreamController != null && !_debugLogStreamController!.isClosed) {
        _debugLogStreamController!.add(logEntry);
      }
      _writeLogToFile(logEntry);
    }
  }

  Future<void> _writeLogToFile(String logEntry) async {
    try {
      final debugDir = Directory('debug');
      if (!await debugDir.exists()) await debugDir.create(recursive: true);
      final now = DateTime.now();
      final logFile = File('${debugDir.path}/log_${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}.txt');
      await logFile.writeAsBytes(utf8.encode('$logEntry\n'), mode: FileMode.append);
    } catch (e) {
      print('写入日志文件失败: $e');
    }
  }

  void _showDebugLogWindow() {
    _debugLogStreamController = StreamController<String>();
    Navigator.push(context, MaterialPageRoute(
      builder: (BuildContext context) {
        return StatefulBuilder(builder: (context, setState) {
          return Scaffold(
            appBar: AppBar(
              title: Text('调试日志窗口'), backgroundColor: Colors.black, foregroundColor: Colors.white,
              actions:[
                IconButton(icon: Icon(Icons.close), onPressed: () {
                  Navigator.of(context).pop();
                  if (_debugLogStreamController != null && !_debugLogStreamController!.isClosed) {
                    _debugLogStreamController!.close();
                    _debugLogStreamController = null;
                  }
                  this.setState(() { _debugMode = false; });
                }),
              ],
            ),
            backgroundColor: Colors.black,
            body: Container(
              padding: EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children:[
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[900],
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.grey[700]!, width: 1),
                      ),
                      child: StreamBuilder<String>(
                        stream: _debugLogStreamController!.stream,
                        builder: (context, snapshot) {
                          if (snapshot.hasData) _debugLogs.add(snapshot.data!);
                          return ListView.builder(
                            itemCount: _debugLogs.length,
                            itemBuilder: (context, index) {
                              return Container(
                                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                child: Text(_debugLogs[index], style: TextStyle(color: Colors.green[400], fontSize: 12, fontFamily: 'monospace')),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        });
      },
      fullscreenDialog: true,
    ));
  }

  // ===================== 数据获取与解析 =====================

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.toLowerCase().trim();
      if (_searchQuery.isEmpty) {
        _filteredArticleList = List.from(_articleList);
      } else {
        _filteredArticleList = _articleList.where((article) {
          final title = article['title']?.toLowerCase() ?? '';
          final author = article['author']?.toLowerCase() ?? '';
          final remark = article['remark']?.toLowerCase() ?? '';
          return title.contains(_searchQuery) || author.contains(_searchQuery) || remark.contains(_searchQuery);
        }).toList();
      }
    });
  }

  Map<String, String> _parseDifyConfigFromUrl(String extensionUrl) {
    if (extensionUrl.isEmpty) return {};
    try {
      final uri = Uri.parse(extensionUrl);
      final baseUrl = '${uri.scheme}://${uri.host}${uri.port != 80 ? ':${uri.port}' : ''}';
      return {'baseUrl': baseUrl, 'endpoint': uri.path, 'apiKey': uri.fragment};
    } catch (e) {
      return {};
    }
  }

  Stream<String> _fetchDifyContentStream(String query) async* {
    try {
      final currentArticle = _articleList.firstWhere((a) => a['title'] == _currentArticleTitle, orElse: () => {});
      final config = _parseDifyConfigFromUrl(currentArticle['extensionUrl'] ?? '');
      if (config.isEmpty) throw Exception('无法从文章配置中获取Dify API设置，请检查CSV格式');

      final headers = {'Authorization': 'Bearer ${config['apiKey']}', 'Content-Type': 'application/json'};
      final messages = _conversationHistory.reversed.take(6).toList().reversed.map((msg) {
        return {'role': msg['role'] == 'user' ? 'user' : 'assistant', 'content': msg['content'].toString()};
      }).toList();
      messages.add({'role': 'user', 'content': query});

      final dio = Dio();
      final response = await dio.post(
        '${config['baseUrl']}${config['endpoint']}',
        data: {'inputs': {}, 'query': query, 'response_mode': 'streaming', 'user': 'flutter_app_user', 'messages': messages, 'conversation_mode': _selectedConversationMode},
        options: Options(headers: headers, responseType: ResponseType.stream),
      );

      if (response.statusCode == 200) {
        final Stream<List<int>> stream = response.data.stream;
        final buffer = StringBuffer();

        await for (final chunk in stream) {
          buffer.write(utf8.decode(chunk, allowMalformed: true));
          final lines = buffer.toString().split('\n');
          buffer.clear();
          if (lines.isNotEmpty && !buffer.toString().endsWith('\n')) {
            buffer.write(lines.last);
            lines.removeLast();
          }

          for (final line in lines) {
            final trimmed = line.trim();
            if (trimmed.startsWith('data: ')) {
              final jsonStr = trimmed.substring(6);
              if (jsonStr == '[DONE]') return;
              if (jsonStr.isNotEmpty) {
                try {
                  final map = jsonDecode(jsonStr);
                  if (map['answer'] != null && map['answer'].toString().isNotEmpty) {
                    yield map['answer'];
                  }
                } catch (_) {}
              }
            }
          }
        }
      }
    } catch (e) {
      throw Exception('访问Dify后端失败: $e');
    }
  }

  Future<void> _sendMessageToAI() async {
    final message = _aiMessageController.text.trim();
    if (message.isEmpty || _isWaitingForAI) return;
    try {
      setState(() {
        _isWaitingForAI = true; _isStreaming = true;
        _conversationHistory.add({'role': 'user', 'content': message, 'timestamp': DateTime.now()});
        _conversationHistory.add({'role': 'assistant', 'content': '', 'timestamp': DateTime.now(), 'isStreaming': true});
        _aiMessageController.clear();
      });

      String fullResponse = '';
      await for (final chunk in _fetchDifyContentStream(message)) {
        setState(() {
          fullResponse += chunk;
          _conversationHistory.last['content'] = fullResponse;
        });
      }

      setState(() {
        _conversationHistory.last['isStreaming'] = false;
        _isWaitingForAI = false; _isStreaming = false;
      });
    } catch (e) {
      setState(() {
        _conversationHistory.last['content'] = '抱歉，发生错误：$e';
        _conversationHistory.last['isStreaming'] = false;
        _isWaitingForAI = false; _isStreaming = false;
      });
    }
  }

  String _formatTimestamp(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _loadArticleContent(Map<String, String> article) async {
    try {
      setState(() { _isLoading = true; _errorMessage = null; });
      final filePath = article['filePath'];
      final extensionUrl = article['extensionUrl'];
      String content;

      if (extensionUrl != null && extensionUrl.isNotEmpty) {
        content = '# AI对话模式\n\n欢迎与AI助手对话，请在下方输入您的问题。';
        _conversationHistory.clear();
        _conversationHistory.add({'role': 'assistant', 'content': '您好！我是AI助手，很高兴为您服务。请问有什么可以帮助您的？', 'timestamp': DateTime.now()});
      } else if (filePath != null && filePath.isNotEmpty) {
        if (filePath.contains('dragged_articles/')) {
          final directory = await getApplicationDocumentsDirectory();
          content = await File('${directory.path}/$filePath').readAsString();
        } else {
          content = await rootBundle.loadString(filePath);
        }
      } else {
        content = '# 无内容\n\n这篇文章没有可用的内容。';
      }

      setState(() { _markdownContent = content; _isLoading = false; });
    } catch (e) {
      setState(() {
        _markdownContent = '# 加载失败\n\n无法加载文章内容: $e';
        _isLoading = false; _errorMessage = e.toString();
      });
    }
  }

  Future<void> _loadArticleList() async {
    try {
      setState(() { _isLoading = true; _errorMessage = null; });
      final csvContent = await rootBundle.loadString('assets/doc_list.csv');
      
      String processedContent = csvContent;
      if (csvContent.split(',').length > 7) {
        if (csvContent.contains('\r\n') || csvContent.contains('\n')) {
          processedContent = csvContent;
        } else if (csvContent.contains('\r')) {
          processedContent = csvContent.replaceAll('\r', '\n');
        }
      }

      final csvTable = const CsvToListConverter().convert(processedContent);
      final List<Map<String, String>> articles =[];
      
      for (int i = 1; i < csvTable.length; i++) {
        final row = csvTable[i];
        if (row.length >= 4) {
          String filePath = row[3].toString().trim();
          if (filePath == 'DIFY知识库' || filePath.isEmpty) filePath = '';
          else if (!filePath.startsWith('assets/') && !filePath.startsWith('/')) filePath = 'assets/$filePath';
          
          articles.add({
            'title': row[0].toString().trim(),
            'author': row[1].toString().trim(),
            'version': row[2].toString().trim(),
            'filePath': filePath,
            'extensionUrl': row.length > 4 ? row[4].toString().trim() : '',
            'remark': row.length > 5 ? row[5].toString().trim() : '',
            'tags': row.length > 6 ? row[6].toString().trim() : '',
          });
        }
      }
      _updateArticleList(articles, csvContent);
    } catch (e) {
      setState(() {
        _markdownContent = '# 加载失败\n\n无法加载文章列表: $e\n\n请检查CSV文件格式。';
        _isLoading = false; _errorMessage = e.toString();
      });
    }
  }

  void _updateArticleList(List<Map<String, String>> articles, String csvContent) {
    setState(() {
      _articleList = articles;
      _filteredArticleList = List.from(articles);
      _dataVersion = articles.length.toString();
      if (_articleList.isNotEmpty) {
        _currentArticleTitle = _articleList.first['title']!;
        _currentArticleFilePath = _articleList.first['filePath']!;
      }
      _isLoading = false;
    });
    if (_articleList.isNotEmpty) _loadArticleContent(_articleList.first);
  }

  Future<void> _loadMarkdownFile(String filePath) async {
    try {
      setState(() { _isLoading = true; _errorMessage = null; });
      String content;
      if (filePath.startsWith('/')) {
        final file = File(filePath);
        content = await file.exists() ? await file.readAsString() : '# 文件不存在\n\n无法找到文件: $filePath';
      } else if (filePath.contains('dragged_articles/')) {
        final directory = await getApplicationDocumentsDirectory();
        content = await File('${directory.path}/$filePath').readAsString();
      } else {
        content = await rootBundle.loadString(filePath);
      }
      setState(() { _markdownContent = content; _isLoading = false; });
    } catch (e) {
      setState(() { _markdownContent = '# 加载失败\n\n无法加载Markdown文件: $e'; _isLoading = false; });
    }
  }

  void _showDesktopFilePicker() async {
    try {
      const XTypeGroup typeGroup = XTypeGroup(label: 'Markdown Files', extensions: ['md', 'txt', 'markdown']);
      final XFile? file = await openFile(acceptedTypeGroups: [typeGroup]);
      if (file != null) {
        String fileName = file.name;
        String content = await file.readAsString();
        
        final directory = await getApplicationDocumentsDirectory();
        final targetDir = Directory('${directory.path}/dragged_articles');
        if (!await targetDir.exists()) await targetDir.create(recursive: true);
        await File('${targetDir.path}/$fileName').writeAsString(content);

        final newArticle = {
          'title': fileName, 'author': '本地导入', 'version': '1',
          'filePath': 'dragged_articles/$fileName', 'extensionUrl': '',
          'remark': '手动导入', 'tags': '导入文件',
        };

        setState(() {
          _articleList.add(newArticle); _filteredArticleList.add(newArticle);
          _currentArticleTitle = fileName; _currentArticleFilePath = 'dragged_articles/$fileName';
          _markdownContent = content;
        });

        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('成功导入文件: $fileName'), backgroundColor: Colors.green));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('选择文件时出错: $e'), backgroundColor: Colors.red));
    }
  }

  // ===================== 界面构建 =====================

  void _showSettingsDialog() {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Colors.grey, width: 1)),
          child: Container(
            width: 350,
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children:[
                Text('系统设置', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                SizedBox(height: 20),
                Row(
                  children:[
                    Expanded(child: _buildSettingButton(icon: Icons.help_outline, text: '打开帮助', onPressed: () {
                      Navigator.of(context).pop();
                      setState(() { _currentArticleTitle = '帮助文档'; _currentArticleFilePath = 'assets/Help.md'; });
                      _loadMarkdownFile('assets/Help.md');
                    })),
                    SizedBox(width: 12),
                    Expanded(child: _buildSettingButton(icon: Icons.cloud_download, text: '获取更新', onPressed: () {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('目前暂未开启更新服务')));
                    })),
                  ],
                ),
                SizedBox(height: 12),
                Row(
                  children:[
                    Expanded(child: _buildSettingButton(
                      icon: Icons.dark_mode, 
                      text: themeNotifier.value == ThemeMode.dark ? '日间模式' : '暗夜模式', 
                      onPressed: () {
                        themeNotifier.value = themeNotifier.value == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
                        Navigator.pop(context);
                      })),
                    SizedBox(width: 12),
                    Expanded(child: _buildSettingButton(
                      icon: Icons.file_upload, 
                      text: '导入文件', 
                      onPressed: () {
                        Navigator.pop(context);
                        _showDesktopFilePicker();
                      })),
                  ],
                ),
                SizedBox(height: 12),
                Row(
                  children:[
                    Expanded(child: _buildSettingButton(
                      icon: _debugMode ? Icons.bug_report : Icons.build,
                      text: _debugMode ? '调试模式: 开' : '调试模式: 关',
                      onPressed: () {
                        setState(() { _debugMode = !_debugMode; });
                        if (_debugMode) _showDebugLogWindow();
                        else if (_debugLogStreamController != null) _debugLogStreamController!.close();
                        Navigator.pop(context);
                      })),
                  ],
                ),
                SizedBox(height: 20),
                Center(child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text('关闭'),
                  ),
                )),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSettingButton({required IconData icon, required String text, required VoidCallback onPressed}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: isDark ? Colors.grey[800] : Colors.white,
          foregroundColor: isDark ? Colors.white : Colors.black87,
          side: BorderSide(color: isDark ? Colors.grey[700]! : Colors.grey[300]!, width: 1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children:[
            Icon(icon, size: 20),
            SizedBox(height: 4),
            Text(text, style: TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildAIChatInterface() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children:[
        Container(
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.grey[50],
            border: Border(bottom: BorderSide(color: isDark ? Colors.grey[800]! : Colors.grey[300]!)),
          ),
          child: Row(
            children:[
              Text('对话模式:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              SizedBox(width: 8),
              DropdownButton<String>(
                value: _selectedConversationMode,
                icon: Icon(Icons.arrow_drop_down, size: 20),
                underline: Container(height: 0),
                onChanged: (newValue) => setState(() => _selectedConversationMode = newValue!),
                items:[
                  {'value': 'general', 'label': '通用对话'},
                  {'value': 'technical', 'label': '技术问答'},
                ].map((mode) => DropdownMenuItem(value: mode['value'], child: Text(mode['label']!))).toList(),
              ),
              Spacer(),
              IconButton(icon: Icon(Icons.refresh, size: 18), onPressed: () => setState(() {
                _conversationHistory.clear();
                _conversationHistory.add({'role': 'assistant', 'content': '对话已重置。', 'timestamp': DateTime.now()});
              })),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.all(12),
            itemCount: _conversationHistory.length,
            itemBuilder: (context, index) => _buildMessageBubble(_conversationHistory[index]),
          ),
        ),
        Container(
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            border: Border(top: BorderSide(color: isDark ? Colors.grey[800]! : Colors.grey[300]!)),
          ),
          child: Row(
            children:[
              Expanded(
                child: TextField(
                  controller: _aiMessageController,
                  maxLines: 3, minLines: 1,
                  decoration: InputDecoration(
                    hintText: '输入您的问题...',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  onSubmitted: (_) => _sendMessageToAI(),
                ),
              ),
              SizedBox(width: 8),
              _isWaitingForAI 
                  ? CircularProgressIndicator()
                  : IconButton(icon: Icon(Icons.send, color: Colors.blue), onPressed: _sendMessageToAI),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> message) {
    final isUser = message['role'] == 'user';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final content = message['content'].toString();

    return Container(
      margin: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children:[
          if (!isUser) CircleAvatar(child: Icon(Icons.smart_toy, size: 16)),
          Flexible(
            child: Container(
              margin: EdgeInsets.symmetric(horizontal: 8),
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isUser 
                    ? (isDark ? Colors.blue[900]!.withOpacity(0.3) : Colors.blue[50]) 
                    : (isDark ? const Color(0xFF2A2A2A) : Colors.grey[100]),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isDark ? Colors.transparent : Colors.grey[300]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children:[
                  if (isUser) Text(content, style: TextStyle(fontSize: 14))
                  else _buildAIResponse(content, message['isStreaming'] == true),
                ],
              ),
            ),
          ),
          if (isUser) CircleAvatar(child: Icon(Icons.person, size: 16)),
        ],
      ),
    );
  }

  Widget _buildAIResponse(String content, bool isStreaming) {
    if (!content.contains('<chart>')) return _buildMarkdownContent(content, isStreaming);
    final parts = content.split('<chart>');
    final beforeChart = parts[0];
    final afterChart = parts.length > 1 ? parts[1] : '';
    final isChartComplete = afterChart.contains('</chart>');
    final chartParts = afterChart.split('</chart>');
    final chartContent = chartParts.isNotEmpty ? chartParts[0] : '';
    final afterChartContent = chartParts.length > 1 ? chartParts[1] : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children:[
        if (beforeChart.isNotEmpty) _buildMarkdownContent(beforeChart, isStreaming),
        if (isChartComplete && chartContent.isNotEmpty) Container(
          margin: EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(8)),
          child: _buildChartContent(chartContent),
        ),
        if (afterChartContent.isNotEmpty) _buildMarkdownContent(afterChartContent, isStreaming),
      ],
    );
  }

  Widget _buildContentArea() {
    return _isLoading && _markdownContent == '# 加载中...'
        ? Center(child: CircularProgressIndicator())
        : (_articleList.firstWhere((a) => a['title'] == _currentArticleTitle, orElse: () => {})['extensionUrl'] ?? '').isNotEmpty
        ? _buildAIChatInterface()
        : _renderMarkdown(_markdownContent, isSelectable: true, shrinkWrap: false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Row(
        children:[
          // 左侧边栏
          Container(
            width: 280,
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              border: Border(right: BorderSide(color: isDark ? Colors.grey[800]! : Colors.grey[300]!, width: 1)),
            ),
            child: Column(
              children:[
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: '搜索文章...',
                    prefixIcon: Icon(Icons.search),
                    filled: true,
                    fillColor: isDark ? const Color(0xFF2A2A2A) : Colors.grey[100],
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  ),
                ),
                SizedBox(height: 15),
                Expanded(
                  child: ListView.builder(
                    itemCount: _filteredArticleList.length,
                    itemBuilder: (context, index) {
                      final article = _filteredArticleList[index];
                      return _buildArticleButton(article['title']!, article['author']!, article['filePath']!, article['extensionUrl'] ?? '');
                    },
                  ),
                ),
                SizedBox(height: 10),
                GestureDetector(
                  onTap: _showSettingsDialog,
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.blue),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Center(child: Row(mainAxisAlignment: MainAxisAlignment.center, children:[Icon(Icons.settings, color: Colors.blue, size: 18), SizedBox(width: 8), Text('设置', style: TextStyle(color: Colors.blue))])),
                  ),
                ),
              ],
            ),
          ),
          // 右侧主内容区（支持拖拽覆盖层）
          Expanded(
            child: DragTarget<String>(
              onWillAccept: (data) => true,
              onAccept: (data) => _showDesktopFilePicker(),
              builder: (context, candidateData, rejectedData) => Stack(
                children:[
                  Container(
                    width: double.infinity, height: double.infinity,
                    color: isDark ? const Color(0xFF121212) : Colors.white,
                    child: _buildContentArea(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildArticleButton(String title, String author, String filePath, String extensionUrl) {
    bool isSelected = _currentArticleTitle == title;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: () {
        setState(() { _currentArticleTitle = title; _currentArticleFilePath = filePath; });
        _loadArticleContent(_articleList.firstWhere((a) => a['title'] == title));
      },
      child: Container(
        margin: EdgeInsets.only(bottom: 12),
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? (isDark ? Colors.blue[900]!.withOpacity(0.5) : Colors.blue[50]) : (isDark ? Colors.transparent : Colors.grey[100]),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: isSelected ? Colors.blue : (isDark ? Colors.grey[800]! : Colors.grey[300]!), width: isSelected ? 2 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children:[
            Text(title, style: TextStyle(color: isSelected ? Colors.blue : (isDark ? Colors.white : Colors.black87), fontWeight: isSelected ? FontWeight.bold : FontWeight.w600)),
            SizedBox(height: 4),
            Text('作者: $author', style: TextStyle(fontSize: 11, color: isDark ? Colors.grey[400] : Colors.grey[600])),
          ],
        ),
      ),
    );
  }
}

// ===================== 图表渲染扩展 (fl_chart) =====================

class ChartConfig {
  final String type;
  final String title;
  final String xTitle;
  final String yTitle;
  final String ySuffix;
  final List<String> headers;
  final List<Map<String, dynamic>> data;

  ChartConfig({required this.type, required this.title, required this.xTitle, required this.yTitle, required this.ySuffix, required this.headers, required this.data});
}

class ChartDataParser {
  static ChartConfig parseChartData(String content) {
    List<String> lines = content.split('\n');
    List<String> headers =[];
    List<Map<String, dynamic>> data =[];
    Map<String, String> config = {};
    bool isDataSection = true;

    for (String line in lines) {
      line = line.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('type:')) isDataSection = false;

      if (isDataSection) {
        List<String> values = line.split(',').map((e) => e.trim()).toList();
        if (headers.isEmpty) headers = values;
        else {
          Map<String, dynamic> row = {};
          for (int i = 0; i < headers.length && i < values.length; i++) {
            if (values[i].isNotEmpty) row[headers[i]] = double.tryParse(values[i]) ?? values[i];
          }
          if (row.isNotEmpty) data.add(row);
        }
      } else {
        if (line.contains(':')) {
          List<String> parts = line.split(':');
          if (parts.length >= 2) config[parts[0].trim()] = parts.sublist(1).join(':').trim();
        }
      }
    }
    return ChartConfig(
      type: config['type'] ?? 'line', title: config['title'] ?? '', xTitle: config['x.title'] ?? '',
      yTitle: config['y.title'] ?? '', ySuffix: config['y.suffix'] ?? '', headers: headers, data: data,
    );
  }
}

class LineChartWidget extends StatelessWidget {
  final ChartConfig config;
  const LineChartWidget({super.key, required this.config});

  Color _getColorForIndex(int index) {
    final colors =[Colors.blue, Colors.green, Colors.orange, Colors.purple, Colors.red, Colors.teal];
    return colors[index % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (config.data.isEmpty) {
      return Container(
        height: 350, padding: const EdgeInsets.all(16),
        child: Center(child: Text('暂无图表数据', style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600]))),
      );
    }

    List<LineChartBarData> lineBarsData =[];
    List<String> xLabels = config.data.map((row) => row[config.headers[0]].toString()).toList();

    for (int i = 1; i < config.headers.length; i++) {
      String header = config.headers[i];
      List<FlSpot> spots =[];
      for (int j = 0; j < config.data.length; j++) {
        double? value = config.data[j][header] is double ? config.data[j][header] : double.tryParse(config.data[j][header].toString());
        if (value != null) spots.add(FlSpot(j.toDouble(), value));
      }
      if (spots.isNotEmpty) {
        lineBarsData.add(LineChartBarData(
          spots: spots, isCurved: true, color: _getColorForIndex(i), barWidth: 3,
          isStrokeCapRound: true, dotData: const FlDotData(show: true), belowBarData: BarAreaData(show: false),
        ));
      }
    }

    return Container(
      height: 350, padding: const EdgeInsets.all(16),
      child: Column(
        children:[
          if (config.title.isNotEmpty) Text(config.title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
          const SizedBox(height: 20),
          Expanded(
            child: LineChart(
              LineChartData(
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (spot) => isDark ? Colors.grey[800]! : Colors.white,
                    getTooltipItems: (touchedSpots) => touchedSpots.map((spot) => LineTooltipItem(
                      '${config.headers[spot.barIndex]} : ${spot.y.toStringAsFixed(0)}${config.ySuffix}',
                      TextStyle(color: _getColorForIndex(spot.barIndex), fontSize: 12),
                    )).toList(),
                  ),
                ),
                lineBarsData: lineBarsData,
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, m) => Text(xLabels[v.toInt()], style: TextStyle(fontSize: 10, color: isDark ? Colors.grey[400] : Colors.black)))),
                  leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, m) => Text('${v.toInt()}${config.ySuffix}', style: TextStyle(fontSize: 10, color: isDark ? Colors.grey[400] : Colors.black)))),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: true, border: Border.all(color: isDark ? Colors.grey[700]! : Colors.grey[300]!)),
                gridData: FlGridData(show: true, getDrawingHorizontalLine: (value) => FlLine(color: isDark ? Colors.grey[800]! : Colors.grey[200]!, strokeWidth: 1)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ChartElementBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    if (element.tag == 'code' && element.attributes['class'] == 'language-chart') {
      try {
        String content = element.textContent;
        ChartConfig config = ChartDataParser.parseChartData(content);
        return LineChartWidget(config: config);
      } catch (e) {
        return Container(padding: const EdgeInsets.all(16), color: Colors.red[50], child: Text('图表解析错误: $e'));
      }
    }
    return null;
  }
}