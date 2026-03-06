# 文档搜索器 (Doc Searcher)

一个基于 Flutter 开发的强大 Markdown 文档搜索与管理应用，支持本地文件与远程知识库内容的统一管理。

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
- **图表渲染**：支持 Markdown 中的图表渲染

## 项目结构

```
lib/
├── main.dart          # 主应用文件，包含主要UI逻辑
├── Line_Draw.dart     # 图表绘制功能模块
assets/
├── doc_list.csv       # 文章列表配置文件
├── Help.md            # 帮助文档
├── database/article/  # Markdown 文件存储目录
└── readtemp/          # 临时文件目录
```

## 快速开始

### 环境要求
- Flutter 3.0.0 或更高版本
- Dart 2.17.0 或更高版本

### 安装步骤

1. **克隆项目**
```bash
git clone https://github.com/dpineer/A-md-File-Manager-with-Flutter.git
cd doc_searcher
```

2. **安装依赖**
```bash
flutter pub get
```

3. **配置文章列表**
在 `assets/doc_list.csv` 中配置文章信息：
```csv
文章名称,作者,版本,文件路径,扩展URL,备注,标签
示例文章,张三,1.0,assets/sample.md,,技术文档,flutter
AI文章,李四,1.0,,https://api.dify.com,AI生成,ai
```

4. **运行项目**
```bash
flutter run
```

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
```csv
Flutter入门指南,王五,1.0,assets/flutter_intro.md,,技术文档,flutter
```

#### Dify 知识库文章
```csv
AI助手使用说明,AI助手,1.0,,https://api.dify.com/v1,AI生成,ai
```

## 核心功能模块

### 1. 主应用 (main.dart)

#### 主要类
- `MyApp`: 应用根组件
- `_MainPageState`: 主页面状态管理类

#### 核心功能
- **文章列表管理**: 通过 CSV 文件加载和管理文章列表
- **搜索功能**: 支持按标题、作者、标签多维度搜索
- **Markdown 渲染**: 支持完整的 Markdown 语法渲染
- **LaTeX 数学公式**: 集成 LaTeX 公式渲染
- **AI 对话集成**: 支持 Dify 知识库的 AI 对话功能
- **图表渲染**: 支持 Markdown 中的图表渲染

#### 文章数据结构
```dart
{
  'title': 文章标题,
  'author': 作者,
  'version': 版本号,
  'filePath': 文件路径,
  'extensionUrl': 扩展URL (用于Dify集成),
  'remark': 备注,
  'tags': 标签
}
```

### 2. 图表绘制模块 (Line_Draw.dart)

#### 主要类
- `ChartConfig`: 图表配置类
- `ChartDataParser`: 图表数据解析器
- `LineChartWidget`: 折线图组件
- `ChartElementBuilder`: Markdown 图表元素构建器

#### 功能特性
- 解析 Markdown 中的图表数据
- 支持折线图渲染
- 自定义图表配置 (标题、轴标签等)

## 依赖包分析

### 主要依赖
```yaml
dependencies:
  flutter_markdown_plus_latex: ^1.0.3  # Markdown + LaTeX 渲染
  flutter_markdown_plus: ^1.0.3       # Markdown 渲染
  markdown: ^7.3.0                    # Markdown 解析
  csv: ^6.0.0                         # CSV 文件处理
  fl_chart: ^1.1.1                    # 图表渲染
  dio: ^5.9.0                         # HTTP 客户端 (用于Dify API)
  path: ^1.9.1                        # 路径处理
  path_provider: ^2.1.5               # 文件路径提供器
  file_picker: ^10.3.7                # 文件选择器
  url_launcher: ^6.3.2                # URL 启动器
  flutter_math_fork: ^0.7.4           # 数学公式渲染
  flutter_dropzone: ^4.2.1            # 拖拽上传
  open_file_plus: ^3.4.1+1            # 文件打开
  permission_handler: ^12.0.1         # 权限处理
```

## 核心功能实现

### 1. 文章列表加载流程
1. 从 `assets/doc_list.csv` 加载 CSV 数据
2. 解析 CSV 内容为文章列表
3. 智能处理文件路径和类型识别
4. 应用搜索过滤功能

### 2. Markdown 渲染机制
- 使用 `flutter_markdown_plus` 包进行渲染
- 集成 LaTeX 数学公式支持
- 自定义图表元素构建器
- 支持代码高亮

### 3. AI 对话功能
- 集成 Dify 知识库 API
- 支持流式响应
- 多种对话模式 (通用、技术、创意、分析)
- 对话历史管理

### 4. 搜索功能
- 实时搜索过滤
- 支持标题、作者、标签多维度搜索
- 搜索结果高亮显示

## UI 界面设计

### 布局结构
- 左侧导航栏 (280px): 搜索栏 + 文章列表
- 右侧内容区: Markdown 内容显示或 AI 对话界面

### 主要组件
- 搜索输入框
- 文章列表卡片
- Markdown 渲染区域
- AI 对话界面
- 设置面板

## 特殊功能

### 1. Dify 集成
- 通过 URL 片段解析 API 配置
- 支持流式 AI 响应
- 专门的对话界面

### 2. 图表渲染
- 在 Markdown 中使用 ```chart 代码块
- 支持 CSV 格式的数据输入
- 自动渲染为折线图

### 3. 文件路径处理
- 自动修复路径中的空格问题
- 支持多种路径格式
- 智能路径转换

## 错误处理与调试

### 错误处理机制
- 文件加载失败处理
- CSV 解析错误处理
- 网络请求错误处理
- 图表渲染错误处理

### 调试功能
- 详细的日志输出
- 错误状态显示
- 重试机制

## 项目特点

1. **多源内容管理**: 统一管理本地和远程内容
2. **现代化 UI**: 响应式布局，良好的用户体验
3. **丰富功能**: Markdown、LaTeX、图表、AI 对话
4. **灵活配置**: CSV 驱动的内容管理
5. **智能搜索**: 多维度搜索功能
6. **扩展性好**: 模块化设计，易于扩展

## 技术栈

- **框架**: Flutter (Dart)
- **UI**: Material Design
- **数据格式**: CSV, Markdown, LaTeX
- **图表**: fl_chart
- **网络**: dio
- **解析**: markdown 包

## 使用场景

1. **文档管理**: 统一管理大量 Markdown 文档
2. **知识库**: 集成本地和 AI 知识库
3. **学术研究**: 支持数学公式和图表
4. **内容创作**: 便捷的 Markdown 编辑和查看

## 自定义扩展

### 添加新的渲染组件
在 `markdown_viewer.dart` 中扩展 builders：
```dart
builders: {
'custom': CustomElementBuilder(),
'latex': LatexElementBuilder(),
}
```

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

## 贡献指南

欢迎提交 Issue 和 Pull Request 来改进项目！

## 许可证

CC BY NC SA