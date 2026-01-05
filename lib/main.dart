import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 用于rootBundle
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_markdown_plus_latex/flutter_markdown_plus_latex.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:csv/csv.dart';
import 'Line_Draw.dart';
import 'package:dio/dio.dart';
import 'dart:convert'; // 用于jsonDecode
import 'dart:async'; // 用于StreamController

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'markdown和知识库',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: MainPage(),
    );
  }
}

class MainPage extends StatefulWidget {
  @override
  _MainPageState createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  String _markdownContent = '# 加载中...';
  bool _isLoading = true;
  String? _errorMessage;

  // 用于存储从CSV解析的文章列表
  List<Map<String, String>> _articleList = [];
  List<Map<String, String>> _filteredArticleList = [];
  String _currentArticleTitle = ''; // 去掉late，直接初始化
  String _currentArticleFilePath = '';

  // 搜索相关
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';

  // 版本信息
  final String _appVersion = "0.0.0.dev";
  String _dataVersion = "0";

  final TextEditingController _aiMessageController = TextEditingController();
  final List<Map<String, dynamic>> _conversationHistory = [];
  bool _isWaitingForAI = false;
  String _selectedConversationMode = 'general';

  // 对话模式选项
  final List<Map<String, String>> _conversationModes = [
    {'value': 'general', 'label': '通用对话'},
    {'value': 'technical', 'label': '技术问答'},
    {'value': 'creative', 'label': '创意写作'},
    {'value': 'analysis', 'label': '分析推理'},
  ];

  // 流式响应相关变量
  StreamController<String> _streamResponseController =
      StreamController<String>();
  bool _isStreaming = false;
  String _currentStreamingResponse = "";

  @override
  void initState() {
    super.initState();
    _loadArticleList();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _streamResponseController.close();
    super.dispose();
  }

  // 搜索文本变化处理
  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.toLowerCase().trim();
      _filterArticles();
    });
  }

  // 过滤文章列表
  void _filterArticles() {
    if (_searchQuery.isEmpty) {
      _filteredArticleList = List.from(_articleList);
    } else {
      _filteredArticleList = _articleList.where((article) {
        final title = article['title']?.toLowerCase() ?? '';
        final author = article['author']?.toLowerCase() ?? '';
        final remark = article['remark']?.toLowerCase() ?? '';

        return title.contains(_searchQuery) ||
            author.contains(_searchQuery) ||
            remark.contains(_searchQuery);
      }).toList();
    }
  }

  Stream<String> _fetchDifyContentStream(String query) async* {
    try {
      final dio = Dio();

      // 从当前文章获取Dify配置信息
      final currentArticle = _articleList.firstWhere(
        (article) => article['title'] == _currentArticleTitle,
        orElse: () => {},
      );

      // 从CSV的拓展内容地址字段解析Dify配置
      final extensionUrl = currentArticle['extensionUrl'] ?? '';
      final config = _parseDifyConfigFromUrl(extensionUrl);

      // 完全移除硬编码，如果配置解析失败则抛出明确错误
      if (config.isEmpty) {
        throw Exception('无法从文章配置中获取Dify API设置，请检查CSV文件中的拓展内容地址格式');
      }

      final String apiKey = config['apiKey']!;
      final String baseUrl = config['baseUrl']!;
      final String endpoint = config['endpoint']!;

      // 设置请求头
      final headers = {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      };

      // 构建对话历史
      final List<Map<String, String>> messages = [];

      // 添加最近的对话历史（限制长度避免token过多）
      final recentHistory = _conversationHistory.reversed
          .take(6)
          .toList()
          .reversed
          .toList();
      for (final msg in recentHistory) {
        messages.add({
          'role': msg['role'] == 'user' ? 'user' : 'assistant',
          'content': msg['content'].toString(),
        });
      }

      // 添加当前查询
      messages.add({'role': 'user', 'content': query});

      final requestBody = {
        'inputs': {},
        'query': query,
        'response_mode': 'streaming',
        'user': 'flutter_app_user',
        'messages': messages,
        'conversation_mode': _selectedConversationMode,
      };

      final response = await dio.post(
        '$baseUrl$endpoint',
        data: requestBody,
        options: Options(
          headers: headers,
          responseType: ResponseType.stream,
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

      if (response.statusCode == 200) {
        final ResponseBody responseBody = response.data;
        final Stream<List<int>> stream = responseBody.stream;
        final StringBuffer buffer = StringBuffer();

        await for (final chunk in stream) {
          final String text = utf8.decode(chunk, allowMalformed: true);
          buffer.write(text);

          final String bufferContent = buffer.toString();
          final List<String> lines = bufferContent.split('\n');

          // 清空缓冲区并保留最后一行（可能不完整）
          buffer.clear();
          if (lines.isNotEmpty && !bufferContent.endsWith('\n')) {
            buffer.write(lines.last);
            lines.removeLast();
          }

          for (final line in lines) {
            final String trimmedLine = line.trim();
            if (trimmedLine.isEmpty) continue;

            if (trimmedLine.startsWith('data: ')) {
              final String jsonStr = trimmedLine.substring(6);

              if (jsonStr == '[DONE]') {
                return;
              }

              if (jsonStr.isNotEmpty) {
                try {
                  final Map<String, dynamic> map =
                      jsonDecode(jsonStr) as Map<String, dynamic>;
                  final String? answer = map['answer'] as String?;

                  if (answer != null && answer.isNotEmpty) {
                    yield answer;
                  }
                } catch (e) {
                  print('JSON解析错误，跳过该行数据: $e');
                  continue;
                }
              }
            }
          }
        }

        // 处理缓冲区中剩余的数据
        final String remaining = buffer.toString();
        if (remaining.isNotEmpty) {
          final String trimmed = remaining.trim();
          if (trimmed.startsWith('data: ')) {
            final String jsonStr = trimmed.substring(6);
            if (jsonStr != '[DONE]' && jsonStr.isNotEmpty) {
              try {
                final Map<String, dynamic> map =
                    jsonDecode(jsonStr) as Map<String, dynamic>;
                final String? answer = map['answer'] as String?;
                if (answer != null && answer.isNotEmpty) {
                  yield answer;
                }
              } catch (e) {
                print('尾部数据解析错误: $e');
              }
            }
          }
        }
      } else {
        throw Exception('Dify请求失败: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('访问Dify后端失败: $e');
    }
  }

  // 新增方法：从URL解析Dify配置信息
  Map<String, String> _parseDifyConfigFromUrl(String extensionUrl) {
    if (extensionUrl.isEmpty) {
      return {};
    }

    try {
      // 假设URL格式为：http://192.168.124.3/v1#app-4FGPy6OjsydBXkIMLtvVCR7U
      final uri = Uri.parse(extensionUrl);
      final baseUrl =
          '${uri.scheme}://${uri.host}${uri.port != 80 ? ':${uri.port}' : ''}';
      final endpoint = uri.path;
      final apiKey = uri.fragment; // 从fragment中获取API Key

      return {'baseUrl': baseUrl, 'endpoint': endpoint, 'apiKey': apiKey};
    } catch (e) {
      print('解析Dify配置失败: $e');
      return {};
    }
  }

  Widget _buildAIChatInterface() {
    return Column(
      children: [
        // 对话模式选择器
        Container(
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
          ),
          child: Row(
            children: [
              Text(
                '对话模式:',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              SizedBox(width: 8),
              DropdownButton<String>(
                value: _selectedConversationMode,
                icon: Icon(Icons.arrow_drop_down, size: 20),
                elevation: 16,
                style: TextStyle(fontSize: 14, color: Colors.black),
                underline: Container(height: 0),
                onChanged: (String? newValue) {
                  setState(() {
                    _selectedConversationMode = newValue!;
                  });
                },
                items: _conversationModes.map<DropdownMenuItem<String>>((
                  Map<String, String> mode,
                ) {
                  return DropdownMenuItem<String>(
                    value: mode['value'],
                    child: Text(mode['label']!),
                  );
                }).toList(),
              ),
              Spacer(),
              IconButton(
                icon: Icon(Icons.refresh, size: 18),
                onPressed: () {
                  setState(() {
                    _conversationHistory.clear();
                    _conversationHistory.add({
                      'role': 'assistant',
                      'content': '对话已重置，请问有什么可以帮助您的？',
                      'timestamp': DateTime.now(),
                    });
                  });
                },
                tooltip: '重置对话',
              ),
            ],
          ),
        ),

        // 对话历史区域
        Expanded(
          child: _conversationHistory.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.chat_bubble_outline,
                        size: 48,
                        color: Colors.grey[400],
                      ),
                      SizedBox(height: 8),
                      Text(
                        '开始与AI对话',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.all(12),
                  itemCount: _conversationHistory.length,
                  itemBuilder: (context, index) {
                    final message = _conversationHistory[index];
                    return _buildMessageBubble(message);
                  },
                ),
        ),

        // 输入区域
        Container(
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Colors.grey[300]!)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _aiMessageController,
                  maxLines: 3,
                  minLines: 1,
                  decoration: InputDecoration(
                    hintText: '输入您的问题...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: Colors.grey[400]!),
                    ),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  onSubmitted: (_) => _sendMessageToAI(),
                ),
              ),
              SizedBox(width: 8),
              _isWaitingForAI
                  ? Padding(
                      padding: EdgeInsets.all(8),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      icon: Icon(Icons.send, color: Colors.blue),
                      onPressed: _sendMessageToAI,
                      tooltip: '发送消息',
                    ),
            ],
          ),
        ),
      ],
    );
  }

  // 新增：构建消息气泡
  Widget _buildMessageBubble(Map<String, dynamic> message) {
    final bool isUser = message['role'] == 'user';
    final bool isStreaming = message['isStreaming'] == true;
    final String content = message['content'].toString();

    return Container(
      margin: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (!isUser)
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.blue[100],
              child: Icon(Icons.smart_toy, size: 16, color: Colors.blue[600]),
            ),
          Flexible(
            child: Container(
              margin: EdgeInsets.symmetric(horizontal: 8),
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isUser ? Colors.blue[50] : Colors.grey[100],
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isUser ? Colors.blue[200]! : Colors.grey[300]!,
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isUser)
                    Text(
                      content,
                      style: TextStyle(fontSize: 14, color: Colors.grey[800]),
                    )
                  else
                    _buildAIResponse(content, isStreaming),
                  if (isStreaming) ...[
                    SizedBox(height: 4),
                    Row(
                      children: [
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 6),
                        Text(
                          'AI正在思考...',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ],
                  SizedBox(height: 4),
                  Text(
                    _formatTimestamp(message['timestamp'] as DateTime),
                    style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
          ),
          if (isUser)
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.green[100],
              child: Icon(Icons.person, size: 16, color: Colors.green[600]),
            ),
        ],
      ),
    );
  }

  // 新增：构建AI响应内容，处理图表标记
  Widget _buildAIResponse(String content, bool isStreaming) {
    // 检查是否包含图表标记
    final hasChartTag = content.contains('<chart>');

    if (!hasChartTag) {
      // 没有图表标记，直接渲染Markdown
      return _buildMarkdownContent(content, isStreaming);
    }

    // 分割图表标记之前和之后的内容
    final parts = content.split('<chart>');
    final beforeChart = parts[0];
    final afterChart = parts.length > 1 ? parts[1] : '';

    // 检查图表数据是否完整（包含结束标记）
    final isChartComplete = afterChart.contains('</chart>');
    final chartParts = afterChart.split('</chart>');
    final chartContent = chartParts.length > 1 ? chartParts[0] : '';
    final afterChartContent = chartParts.length > 1 ? chartParts[1] : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 图表标记之前的内容 - 浅色处理
        if (beforeChart.isNotEmpty)
          Opacity(
            opacity: 0.7,
            child: _buildMarkdownContent(beforeChart, isStreaming),
          ),

        // 图表内容（只有完整时才渲染）
        if (isChartComplete && chartContent.isNotEmpty) ...[
          SizedBox(height: 16), // 自动换行
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
            ),
            child: _buildChartContent(chartContent),
          ),
        ] else if (chartContent.isNotEmpty) ...[
          // 图表数据不完整时显示加载状态
          SizedBox(height: 16),
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.orange[300]!),
              borderRadius: BorderRadius.circular(8),
              color: Colors.orange[50],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Text(
                  '图表数据加载中...',
                  style: TextStyle(fontSize: 12, color: Colors.orange[800]),
                ),
              ],
            ),
          ),
        ],

        // 图表之后的内容
        if (afterChartContent.isNotEmpty)
          _buildMarkdownContent(afterChartContent, isStreaming),
      ],
    );
  }

  // 新增：构建图表内容
  Widget _buildChartContent(String chartContent) {
    try {
      // 将图表内容包装成代码块格式，以便ChartElementBuilder解析
      final wrappedContent = '```chart\n$chartContent\n```';

      return Markdown(
        data: wrappedContent,
        shrinkWrap: true,
        physics: NeverScrollableScrollPhysics(),
        builders: {
          'latex': LatexElementBuilder(
            textStyle: const TextStyle(fontWeight: FontWeight.w100),
            textScaleFactor: 1.2,
          ),
          'code': ChartElementBuilder(),
        },
        extensionSet: md.ExtensionSet(
          [...md.ExtensionSet.gitHubFlavored.blockSyntaxes, LatexBlockSyntax()],
          [
            ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
            LatexInlineSyntax(),
          ],
        ),
      );
    } catch (e) {
      return Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.red[300]!),
          borderRadius: BorderRadius.circular(8),
          color: Colors.red[50],
        ),
        child: Text(
          '图表渲染错误: $e',
          style: TextStyle(fontSize: 12, color: Colors.red[800]),
        ),
      );
    }
  }

  // 新增：构建Markdown内容（重构原有逻辑）
  Widget _buildMarkdownContent(String content, bool isStreaming) {
    return Markdown(
      data: content.isEmpty ? "正在检索知识库..." : content,
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      builders: {
        'latex': LatexElementBuilder(
          textStyle: const TextStyle(fontWeight: FontWeight.w100),
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

  // 修改_sendMessageToAI方法，确保图表标记正确处理
  Future<void> _sendMessageToAI() async {
    final String message = _aiMessageController.text.trim();
    if (message.isEmpty || _isWaitingForAI) return;

    try {
      setState(() {
        _isWaitingForAI = true;
        _isStreaming = true;
        _conversationHistory.add({
          'role': 'user',
          'content': message,
          'timestamp': DateTime.now(),
        });
        _conversationHistory.add({
          'role': 'assistant',
          'content': '',
          'timestamp': DateTime.now(),
          'isStreaming': true,
        });
        _aiMessageController.clear();
      });

      final stream = _fetchDifyContentStream(message);
      String fullResponse = '';

      await for (final chunk in stream) {
        setState(() {
          fullResponse += chunk;
          _conversationHistory.last['content'] = fullResponse;
        });
      }

      setState(() {
        _conversationHistory.last['isStreaming'] = false;
        _isWaitingForAI = false;
        _isStreaming = false;
      });
    } catch (e) {
      setState(() {
        _conversationHistory.last['content'] = '抱歉，发生错误：$e';
        _conversationHistory.last['isStreaming'] = false;
        _isWaitingForAI = false;
        _isStreaming = false;
      });
    }
  }

  // 新增：格式化时间戳
  String _formatTimestamp(DateTime timestamp) {
    return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
  }

  // 加载文章内容
  Future<void> _loadArticleContent(Map<String, String> article) async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final String? filePath = article['filePath'];
      final String? extensionUrl = article['extensionUrl'];
      final String? title = article['title'];

      String content;

      if (extensionUrl != null && extensionUrl.isNotEmpty) {
        // 如果是AI文章
        content = '# AI对话模式\n\n欢迎与AI助手对话，请在下方输入您的问题。';
        _conversationHistory.clear();
        _conversationHistory.add({
          'role': 'assistant',
          'content': '您好！我是AI助手，很高兴为您服务。请问有什么可以帮助您的？',
          'timestamp': DateTime.now(),
        });
      } else if (filePath != null && filePath.isNotEmpty) {
        try {
          // 从本地Markdown文件加载内容
          content = await rootBundle.loadString(filePath);
        } catch (e) {
          // 如果文件加载失败，显示错误信息
          content = '# 文件加载失败\n\n无法加载文件: $filePath\n错误: $e';
          _errorMessage = '文件加载失败: $filePath';
        }
      } else {
        // 如果没有文件路径，显示空内容
        content = '# 无内容\n\n这篇文章没有可用的内容。';
      }

      setState(() {
        _markdownContent = content;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _markdownContent = '# 加载失败\n\n无法加载文章内容: $e';
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  // 加载并解析CSV文件
  // 加载并解析CSV文件
  Future<void> _loadArticleList() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      print('开始加载文章列表...');

      // 加载CSV文件
      final String csvContent = await rootBundle.loadString(
        'assets/doc_list.csv',
      );

      print('CSV文件加载成功，内容长度: ${csvContent.length}');

      // --- 新增：详细的CSV内容分析 ---
      print('原始CSV内容（包含转义字符）：');
      for (int i = 0; i < csvContent.length; i++) {
        final char = csvContent[i];
        if (char == '\r') {
          print('位置$i: 回车符 \\r');
        } else if (char == '\n') {
          print('位置$i: 换行符 \\n');
        } else if (char == '\t') {
          print('位置$i: 制表符 \\t');
        } else if (char.codeUnitAt(0) < 32) {
          print('位置$i: 控制字符(ASCII ${char.codeUnitAt(0)})');
        }
      }

      // 检查并修复换行符问题
      String processedContent = csvContent;

      // 情况1：检查是否只有一行（用逗号分割后有7个字段以上，说明是标题行+数据行合并）
      final List<String> allFields = csvContent.split(',');
      print('用逗号分割后字段数: ${allFields.length}');

      // 如果字段数明显超过CSV应有的列数，说明确实有换行符问题
      if (allFields.length > 7) {
        print('检测到可能的换行符问题，字段数过多: ${allFields.length}');

        // 尝试识别换行符
        if (csvContent.contains('\r\n')) {
          print('检测到Windows换行符(\\r\\n)');
          processedContent = csvContent;
        } else if (csvContent.contains('\n')) {
          print('检测到Unix/Linux换行符(\\n)');
          processedContent = csvContent;
        } else if (csvContent.contains('\r')) {
          print('检测到Mac换行符(\\r)');
          // 将Mac换行符替换为Unix换行符
          processedContent = csvContent.replaceAll('\r', '\n');
        } else {
          print('未检测到标准换行符，可能所有内容都在一行');
          // 手动插入换行符：假设每行有7个字段
          final List<String> fields = csvContent.split(',');
          if (fields.length >= 7) {
            // 重建CSV内容，在标题行后插入换行符
            final StringBuffer fixedCsv = StringBuffer();
            // 标题行（前7个字段）
            for (int i = 0; i < 7; i++) {
              fixedCsv.write(fields[i]);
              if (i < 6) fixedCsv.write(',');
            }
            fixedCsv.write('\n');

            // 数据行（后续字段，每7个字段为一行）
            for (int i = 7; i < fields.length; i += 7) {
              for (int j = 0; j < 7 && i + j < fields.length; j++) {
                fixedCsv.write(fields[i + j]);
                if (j < 6 && i + j + 1 < fields.length) fixedCsv.write(',');
              }
              if (i + 7 < fields.length) fixedCsv.write('\n');
            }

            processedContent = fixedCsv.toString();
            print('手动重建CSV内容，新长度: ${processedContent.length}');
          }
        }
      }

      // 按行分割以便调试
      final List<String> lines = processedContent.split('\n');
      print('按\\n分割，共${lines.length}行');

      for (int i = 0; i < lines.length; i++) {
        print('行$i: "${lines[i]}" (长度: ${lines[i].length})');
      }
      // --- 分析结束 ---

      // 解析CSV内容
      print('开始解析处理后的CSV内容，长度: ${processedContent.length}');
      final List<List<dynamic>> csvTable = const CsvToListConverter().convert(
        processedContent,
      );

      print('CSV解析完成，共${csvTable.length}行数据');

      // 检查标题行
      if (csvTable.isNotEmpty) {
        print('标题行: ${csvTable[0]} (列数: ${csvTable[0].length})');
      }

      // 手动解析作为备用方案
      if (csvTable.length <= 1) {
        print('CSV解析失败，尝试手动解析...');
        return _parseCSVManually(csvContent);
      }

      // 跳过标题行，将数据转换为Map列表
      final List<Map<String, String>> articles = [];
      for (int i = 1; i < csvTable.length; i++) {
        final row = csvTable[i];
        print('解析第$i行: $row (列数: ${row.length})');

        if (row.length >= 4) {
          // 清理文件路径，确保没有多余的空格或换行
          String filePath = row[3].toString().trim();
          print('原始文件路径: "$filePath"');

          // 如果是"DIFY知识库"（AI文章），不需要文件路径
          if (filePath == 'DIFY知识库' || filePath.isEmpty) {
            filePath = '';
          } else {
            // 确保路径以assets/开头，并且是有效的相对路径
            if (!filePath.startsWith('assets/')) {
              // 如果路径是绝对路径，转换为相对路径
              if (filePath.contains('home') || filePath.startsWith('/')) {
                // 这是绝对路径，需要转换为相对路径
                // 在Linux中，通常从项目根目录开始
                if (filePath.contains('assets/')) {
                  // 提取assets之后的部分
                  final startIndex = filePath.indexOf('assets/');
                  filePath = filePath.substring(startIndex);
                } else {
                  // 如果无法转换，设置为空
                  filePath = '';
                }
              } else {
                // 确保路径以assets/开头
                filePath = 'assets/$filePath';
              }
            }
          }

          final article = {
            'title': row[0].toString().trim(),
            'author': row[1].toString().trim(),
            'version': row[2].toString().trim(),
            'filePath': filePath, // 使用清理后的路径
            'extensionUrl': row.length > 4 ? row[4].toString().trim() : '',
            'remark': row.length > 5 ? row[5].toString().trim() : '',
            'tags': row.length > 6 ? row[6].toString().trim() : '',
          };

          articles.add(article);
          print('成功解析文章: ${article['title']}，路径: ${article['filePath']}');
        } else if (row.isNotEmpty) {
          print('警告: 第$i行数据不完整，跳过该行。行数据: $row');
        }
      }

      print('文章列表解析完成，共${articles.length}篇文章');

      _updateArticleList(articles, csvContent);
    } catch (e, stackTrace) {
      print('加载文章列表失败: $e');
      print('堆栈跟踪: $stackTrace');

      // 尝试手动解析
      try {
        // 加载CSV文件
        final String csvContent = await rootBundle.loadString(
          'assets/doc_list.csv',
        );
        await _parseCSVManually(csvContent);
      } catch (e2) {
        print('手动解析也失败: $e2');
        setState(() {
          _markdownContent = '# 加载失败\n\n无法加载文章列表: $e\n\n请检查CSV文件格式。';
          _isLoading = false;
          _errorMessage = e.toString();
          _articleList = [];
          _filteredArticleList = [];
          _dataVersion = "0";
          _currentArticleTitle = '加载失败';
          _currentArticleFilePath = '';
        });
      }
    }
  }

  // 新增：手动解析CSV的方法
  Future<void> _parseCSVManually(String csvContent) async {
    print('开始手动解析CSV...');

    // 先尝试用换行符分割
    List<String> lines = csvContent.split('\n');
    if (lines.length <= 1) {
      lines = csvContent.split('\r');
    }
    if (lines.length <= 1) {
      lines = csvContent.split('\r\n');
    }

    print('手动解析找到${lines.length}行');

    final List<Map<String, String>> articles = [];

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      // 跳过标题行
      if (i == 0 && line.startsWith('文章名称')) {
        print('跳过标题行: $line');
        continue;
      }

      // 简单逗号分割（注意：不支持带引号的逗号）
      final List<String> fields = line.split(',');
      print('手动解析第$i行，字段数: ${fields.length}');

      if (fields.length >= 4) {
        String filePath = fields[3].trim();

        // 修复路径中的多余空格
        if (filePath.contains(' ')) {
          filePath = filePath.replaceAll(' ', '');
          print('修复路径空格: "$fields[3]" -> "$filePath"');
        }

        // 如果是"DIFY知识库"（AI文章），不需要文件路径
        if (filePath == 'DIFY知识库' || filePath.isEmpty) {
          filePath = '';
        } else if (!filePath.startsWith('assets/')) {
          filePath = 'assets/$filePath';
        }

        final article = {
          'title': fields[0].trim(),
          'author': fields[1].trim(),
          'version': fields[2].trim(),
          'filePath': filePath,
          'extensionUrl': fields.length > 4 ? fields[4].trim() : '',
          'remark': fields.length > 5 ? fields[5].trim() : '',
          'tags': fields.length > 6 ? fields[6].trim() : '',
        };

        articles.add(article);
        print('手动解析成功: ${article['title']}');
      } else {
        print('手动解析失败: 第$i行字段不足: $line');
      }
    }

    _updateArticleList(articles, csvContent);
  }

  // 新增：更新文章列表的公共方法
  void _updateArticleList(
    List<Map<String, String>> articles,
    String csvContent,
  ) {
    print('更新文章列表，共${articles.length}篇文章');

    setState(() {
      _articleList = articles;
      _filteredArticleList = List.from(articles);
      _dataVersion = articles.length.toString();

      if (_articleList.isNotEmpty) {
        _currentArticleTitle = _articleList.first['title']!;
        _currentArticleFilePath = _articleList.first['filePath']!;
        print('文章列表更新完成，当前选中文章: $_currentArticleTitle');
      } else {
        _currentArticleTitle = '无可用文章';
        _currentArticleFilePath = '';
        _markdownContent = '# 无可用文章\n\n未找到任何可用的文章。\n\nCSV内容:\n$csvContent';
        _errorMessage = 'CSV格式可能不正确';
        print('警告: 文章列表为空');
      }
      _isLoading = false;
    });

    // 加载第一篇文章
    if (_articleList.isNotEmpty) {
      _loadArticleContent(_articleList.first);
    }
  }

  Future<void> _loadMarkdownFile(String filePath) async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final String content = await rootBundle.loadString(filePath);

      setState(() {
        _markdownContent = content;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _markdownContent = '# 加载失败\n\n无法加载Markdown文件: $e';
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  // 处理文章点击事件
  void _onArticleTap(
    String articleTitle,
    String filePath,
    String extensionUrl,
  ) {
    final article = _articleList.firstWhere(
      (article) => article['title'] == articleTitle,
      orElse: () => {},
    );

    if (article.isNotEmpty) {
      setState(() {
        _currentArticleTitle = articleTitle;
        _currentArticleFilePath = filePath;
      });
      _loadArticleContent(article);
    }
  }

  // 显示设置弹窗
  void _showSettingsDialog() {
    showDialog(
      context: context,
      barrierColor: Colors.black,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: Colors.white, width: 1),
          ),
          child: Container(
            width: 320,
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 弹窗标题
                Text(
                  '设置',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 20),

                // 功能按钮区域 - 只保留刷新目录和获取更新
                Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildSettingButton(
                            icon: Icons.help_outline, // 改为帮助图标
                            text: '打开帮助',
                            onPressed: _openHelp, // 打开帮助方法
                            // onPressed: _refreshDirectory,
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: _buildSettingButton(
                            icon: Icons.cloud_download,
                            text: '获取更新',
                            onPressed: _fetchUpdates,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                SizedBox(height: 20),

                // 版本信息区域
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white.withOpacity(0.3)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '软件版本',
                            style: TextStyle(color: Colors.white, fontSize: 12),
                          ),
                          Text(
                            '0.0.0.dev',
                            style: TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '数据版本',
                            style: TextStyle(color: Colors.white, fontSize: 12),
                          ),
                          Text(
                            '0',
                            style: TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 20),

                // 关闭按钮
                Center(
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        side: BorderSide(color: Colors.white, width: 1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                        padding: EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text('关闭'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // 构建设置弹窗按钮
  Widget _buildSettingButton({
    required IconData icon,
    required String text,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          side: BorderSide(color: Colors.white, width: 1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20),
            SizedBox(height: 4),
            Text(text, style: TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }

  // 打开帮助文件
  void _openHelp() {
    Navigator.of(context).pop(); // 关闭设置弹窗

    setState(() {
      _currentArticleTitle = '帮助文档';
      _currentArticleFilePath = 'assets/Help.md';
    });

    _loadMarkdownFile('assets/Help.md');

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('正在打开帮助文档...'), duration: Duration(seconds: 1)),
    );
  }

  // 新增：判断是否为AI文章的方法
  bool _isAIArticle() {
    final currentArticle = _articleList.firstWhere(
      (article) => article['title'] == _currentArticleTitle,
      orElse: () => {},
    );
    final extensionUrl = currentArticle['extensionUrl'] ?? '';
    return extensionUrl.isNotEmpty;
  }

  void _fetchUpdates() async {
    Navigator.of(context).pop(); // 关闭弹窗
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('正在检查更新...'), duration: Duration(seconds: 2)),
    );

    //目前暂未启用
    await Future.delayed(Duration(seconds: 2));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('目前暂未开启更新服务'), duration: Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Row(
        children: [
          // 左侧边栏
          Container(
            width: 280,
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(color: Colors.grey[300]!, width: 1),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 搜索栏 - 改为功能完整的搜索框
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[400]!),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Center(
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      decoration: InputDecoration(
                        hintText: '搜索文章、作者或标签...',
                        hintStyle: TextStyle(color: Colors.grey[600]),
                        prefixIcon: Icon(
                          Icons.search,
                          size: 20,
                          color: Colors.grey[600],
                        ),
                        border: InputBorder.none,
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: Icon(Icons.clear, size: 16),
                                onPressed: () {
                                  _searchController.clear();
                                },
                              )
                            : null,
                      ),
                    ),
                  ),
                ),
                // 文章列表区域
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '文章列表 (${_filteredArticleList.length})',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[800],
                      ),
                    ),
                    if (_searchQuery.isNotEmpty)
                      Text(
                        '搜索: "$_searchQuery"',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                  ],
                ),
                SizedBox(height: 15),

                Expanded(
                  child: _isLoading && _filteredArticleList.isEmpty
                      ? Center(child: CircularProgressIndicator())
                      : _filteredArticleList.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.search_off,
                                size: 40,
                                color: Colors.grey[400],
                              ),
                              SizedBox(height: 10),
                              Text(
                                _searchQuery.isNotEmpty ? '未找到匹配结果' : '暂无文章',
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                              if (_searchQuery.isNotEmpty)
                                TextButton(
                                  onPressed: () {
                                    _searchController.clear();
                                  },
                                  child: Text('清空搜索条件'),
                                ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _filteredArticleList.length,
                          itemBuilder: (context, index) {
                            final article = _filteredArticleList[index];
                            return _buildArticleButton(
                              article['title']!,
                              article['author']!,
                              article['filePath']!,
                              article['remark'] ?? '',
                              article['extensionUrl'] ?? '', // 新增参数
                            );
                          },
                        ),
                ),

                Spacer(),

                // 设置按钮
                GestureDetector(
                  onTap: _showSettingsDialog,
                  child: Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.blue, width: 1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.settings, color: Colors.blue, size: 18),
                          SizedBox(width: 8),
                          Text(
                            '设置',
                            style: TextStyle(
                              color: Colors.blue,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 右侧主内容区
          Expanded(
            child: _isLoading && _markdownContent == '# 加载中...'
                ? Center(child: CircularProgressIndicator())
                : _isAIArticle() // 判断是否为AI选项卡
                ? _buildAIChatInterface() // 显示AI对话界面
                : Markdown(
                    selectable: true,
                    data: _markdownContent,
                    builders: {
                      'latex': LatexElementBuilder(
                        textStyle: const TextStyle(fontWeight: FontWeight.w100),
                        textScaleFactor: 1.2,
                      ),
                      'code': ChartElementBuilder(),
                    },
                    extensionSet: md.ExtensionSet(
                      [
                        ...md.ExtensionSet.gitHubFlavored.blockSyntaxes,
                        LatexBlockSyntax(),
                      ],
                      [
                        ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
                        LatexInlineSyntax(),
                      ],
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: _errorMessage != null
          ? FloatingActionButton(
              onPressed: _loadArticleList,
              child: Icon(Icons.refresh),
              tooltip: '重新加载',
            )
          : null,
    );
  }

  Widget _buildArticleButton(
    String title,
    String author,
    String filePath,
    String remark,
    String extensionUrl, // 新增参数
  ) {
    bool isSelected = _currentArticleTitle == title;
    bool isDifyArticle = extensionUrl.isNotEmpty;

    return GestureDetector(
      onTap: () => _onArticleTap(title, filePath, extensionUrl),
      child: Container(
        width: double.infinity,
        margin: EdgeInsets.only(bottom: 12),
        padding: EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue[50] : Colors.grey[100],
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? Colors.blue : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: Colors.blue.withOpacity(0.2),
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 文章标题和Dify标识
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: isSelected ? Colors.blue[700] : Colors.grey[800],
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.w600,
                      fontSize: 14,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isDifyArticle) ...[
                  SizedBox(width: 4),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.green, width: 1),
                    ),
                    child: Text(
                      'Dify',
                      style: TextStyle(
                        color: Colors.green[700],
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            SizedBox(height: 4),
            // 作者信息
            Text(
              '作者: $author',
              style: TextStyle(
                color: isSelected ? Colors.blue[500] : Colors.grey[600],
                fontSize: 11,
                fontWeight: FontWeight.normal,
              ),
            ),
            // 标签信息（如果有）
            if (remark.isNotEmpty) ...[
              SizedBox(height: 4),
              Text(
                '标签: $remark',
                style: TextStyle(
                  color: isSelected ? Colors.blue[400] : Colors.grey[500],
                  fontSize: 10,
                  fontStyle: FontStyle.italic,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            // Dify内容提示
            if (isDifyArticle) ...[
              SizedBox(height: 4),
              Text(
                '来源: Dify知识库',
                style: TextStyle(
                  color: Colors.green[600],
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
