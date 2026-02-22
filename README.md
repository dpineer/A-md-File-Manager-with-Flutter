# Flutter Markdown 阅读器

一个基于 Flutter 开发的现代化 Markdown 阅读器，支持本地文件与远程知识库内容的统一管理。

## 功能特性

### 多源内容管理
- **CSV 驱动的文章列表**：通过 `doc_list.csv` 配置文件管理所有文章元数据
- **本地 Markdown 文件支持**：直接读取 assets 目录下的 Markdown 文件
- **Dify 知识库集成**：支持远程 AI 生成内容的无缝集成
- **智能路径处理**：自动修复文件路径空格，支持多种路径格式

### 智能搜索与导航
- **实时搜索功能**：支持按标题、作者、标签多维度搜索
- **文章列表过滤**：动态显示匹配结果数量
- **清晰的状态标识**：当前选中文章高亮显示，Dify 来源特殊标识

### 交互体验优化
- **响应式布局**：左侧导航栏与右侧内容区灵活布局
- **加载状态管理**：完整的加载中、错误处理、空状态提示
- **设置面板**：集成帮助文档、更新检查等功能
- **手势操作支持**：文章卡片点击反馈，滑动操作流畅

### 内容渲染能力
- **Markdown 语法支持**：基于 flutter_markdown 包的全格式支持
- **LaTeX 数学公式**：集成 Latex 渲染支持
- **代码高亮显示**：支持代码块语法高亮
- **可选中文本**：支持内容文本选择复制

## 项目结构
lib/
└── assets/
├── doc_list.csv # 文章列表配置
└── markdown/ # Markdown 文件存储

## 快速开始

### 环境要求
- Flutter 3.0.0 或更高版本
- Dart 2.17.0 或更高版本

### 安装步骤


1. **克隆项目**
bash
git clone https://github.com/your-username/flutter-markdown-reader.git
cd flutter-markdown-reader

## 配置说明

### CSV 文件格式
CSV 文件需要包含以下列：
- `文章名称` - 文章显示标题
- `作者` - 文章作者信息  
- `版本` - 内容版本号
- `文件路径` - 本地文件路径（assets/ 开头）
- `扩展URL` - Dify 知识库地址（为空表示本地文章）
- `备注` - 文章标签备注
- `标签` - 搜索关键词标签


## 功能特性

### 多源内容管理
- **CSV 驱动的文章列表**：通过 `doc_list.csv` 配置文件管理所有文章元数据
- **本地 Markdown 文件支持**：直接读取 assets 目录下的 Markdown 文件
- **Dify 知识库集成**：支持远程 AI 生成内容的无缝集成
- **智能路径处理**：自动修复文件路径空格，支持多种路径格式

### 智能搜索与导航
- **实时搜索功能**：支持按标题、作者、标签多维度搜索
- **文章列表过滤**：动态显示匹配结果数量
- **清晰的状态标识**：当前选中文章高亮显示，Dify 来源特殊标识

### 交互体验优化
- **响应式布局**：左侧导航栏与右侧内容区灵活布局
- **加载状态管理**：完整的加载中、错误处理、空状态提示
- **设置面板**：集成帮助文档、更新检查等功能
- **手势操作支持**：文章卡片点击反馈，滑动操作流畅

### 内容渲染能力
- **Markdown 语法支持**：基于 flutter_markdown 包的全格式支持
- **LaTeX 数学公式**：集成 Latex 渲染支持
- **代码高亮显示**：支持代码块语法高亮
- **可选中文本**：支持内容文本选择复制

# Markdown 文件存储

## 快速开始

### 环境要求
- Flutter 3.0.0 或更高版本
- Dart 2.17.0 或更高版本

### 安装步骤

1. **克隆项目**
bash
git clone https://github.com/your-username/flutter-markdown-reader.git
cd flutter-markdown-reader
复制
2. **安装依赖**
bash
flutter pub get
复制
3. **配置文章列表**
在 `assets/doc_list.csv` 中配置文章信息：
csv
文章名称,作者,版本,文件路径,扩展URL,备注,标签
示例文章,张三,1.0,assets/sample.md,,技术文档,flutter
AI文章,李四,1.0,,https://api.dify.com,AI生成,ai
复制
4. **运行项目**
bash
flutter run
复制
## 配置说明

### CSV 文件格式
CSV 文件需要包含以下列：
- `文章名称` - 文章显示标题
- `作者` - 文章作者信息  
- `版本` - 内容版本号
- `文件路径` - 本地文件路径（assets/ 开头）
- `扩展URL` - Dify 知识库地址（为空表示本地文章）
- `备注` - 文章标签备注
- `标签` - 搜索关键词标签

### 文章类型支持

#### 本地文章
csv
Flutter入门指南,王五,1.0,assets/flutter_intro.md,,技术文档,flutter
复制
#### Dify 知识库文章
csv
AI助手使用说明,AI助手,1.0,,https://api.dify.com/v1,AI生成,ai
复制
## 核心方法说明

### 文章列表加载
dart
Future<void> _loadArticleList() async
复制
- 从 CSV 加载文章元数据
- 支持自动重试和手动解析备用方案
- 智能路径处理和类型识别

### 内容渲染
dart
Future<void> _loadMarkdownFile(String filePath) async
复制
- 异步加载 Markdown 内容
- 错误处理和状态管理
- 支持本地和远程内容源

### 搜索过滤
dart
void _filterArticles(String query)
复制
- 实时搜索过滤
- 多字段匹配（标题、作者、标签）
- 搜索结果计数显示

## 自定义扩展

### 添加新的渲染组件
在 `markdown_viewer.dart` 中扩展 builders：
dart
builders: {
'custom': CustomElementBuilder(),
'latex': LatexElementBuilder(),
}
### 支持新的内容源
1. 在 CSV 中添加新的标识列
2. 在 `_loadArticleContent` 中实现内容加载逻辑
3. 添加相应的渲染组件

## 故障排除

### 常见问题

**Q: CSV 文件加载失败**
A: 检查文件路径格式，确保使用正确的换行符（LF）

**Q: Markdown 内容无法渲染**  
A: 验证文件路径是否正确，检查文件编码格式（UTF-8）

**Q: 搜索功能不工作**
A: 确认 CSV 文件中的标签列格式正确

### 日志调试
应用内置详细的日志输出，可通过控制台查看：
- 文章解析过程
- 文件加载状态
- 错误信息跟踪

## 技术栈

- **Flutter** - 跨平台 UI 框架
- **flutter_markdown** - Markdown 渲染核心
- **CSV 解析** - 轻量级数据管理
- **Dart 异步编程** - 高效的资源加载

## 贡献指南

欢迎提交 Issue 和 Pull Request 来改进项目！

## 许可证

CC BY NC SA 
