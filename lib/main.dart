import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 用于rootBundle
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_markdown_plus_latex/flutter_markdown_plus_latex.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:csv/csv.dart';
import 'Line_Draw.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Markdown阅读器',
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
  late String _currentArticleTitle;
  late String _currentArticleFilePath;

  // 搜索相关
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';

  // 版本信息
  final String _appVersion = "0.0.0.dev";
  String _dataVersion = "0";

  @override
  void initState() {
    super.initState();
    // 初始加载CSV文件并解析文章列表
    _loadArticleList();

    // 添加搜索监听
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
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

  // 加载并解析CSV文件
  Future<void> _loadArticleList() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      // 加载CSV文件
      final String csvContent = await rootBundle.loadString(
        'assets/doc_list.csv',
      );

      // 解析CSV内容
      final List<List<dynamic>> csvTable = const CsvToListConverter().convert(
        csvContent,
      );

      // 跳过标题行，将数据转换为Map列表
      final List<Map<String, String>> articles = [];
      for (int i = 1; i < csvTable.length; i++) {
        final row = csvTable[i];
        if (row.length >= 4) {
          articles.add({
            'title': row[0].toString(),
            'author': row[1].toString(),
            'version': row[2].toString(),
            'filePath': row[3].toString(),
            'remark': row.length > 5 ? row[5].toString() : '', // 备注作为标签
          });
        }
      }

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

      // 加载第一篇文章
      if (_articleList.isNotEmpty) {
        _loadMarkdownFile(_articleList.first['filePath']!);
      }
    } catch (e) {
      setState(() {
        _markdownContent = '# 加载失败\n\n无法加载文章列表: $e';
        _isLoading = false;
        _errorMessage = e.toString();
        _articleList = [];
        _filteredArticleList = [];
        _dataVersion = "0";
      });
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
  void _onArticleTap(String articleTitle, String filePath) {
    setState(() {
      _currentArticleTitle = articleTitle;
      _currentArticleFilePath = filePath;
    });
    _loadMarkdownFile(filePath);
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
                              article['remark'] ?? '', // 传递备注作为标签
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

  // 构建文章按钮 - 显示文章名称、作者和标签
  Widget _buildArticleButton(
    String title,
    String author,
    String filePath,
    String remark,
  ) {
    bool isSelected = _currentArticleTitle == title;

    return GestureDetector(
      onTap: () => _onArticleTap(title, filePath),
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
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 文章标题
            Text(
              title,
              style: TextStyle(
                color: isSelected ? Colors.blue[700] : Colors.grey[800],
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                fontSize: 14,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
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
          ],
        ),
      ),
    );
  }
}
