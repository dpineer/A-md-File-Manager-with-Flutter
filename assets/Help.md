# 帮助文件

## 基本使用

在当前的版本 V0.0.0.dev 当中，您可以在左上方的搜索栏中搜索，
添加/修改文件需要按照以下指示打开路径并编辑文件

![1](resource:assets/image.png)

![2](resource:assets/image-1.png)

![3](resource:assets/image-2.png)

![4](resource:assets/image-3.png)

![5](resource:assets/image-4.png)

随后重启，即可看到应用的更改

## 编写md文档

该程序兼容许多标准Markdown格式，但仍然需要阅读以下内容

### 存档地址

 在Windows当中，所有的文档都存放在该目录下
 程序路径\data\flutter_assets\assets
 包括该帮助文档也存放在这里
 目前暂不支持自行创建管理文件夹，该问题已添加到开发计划中

### 插入图片

在图片名称前面添加：resource:assets/database/article/
同时在文件名后面不应该
图片路径需要放在assets/database/article/目录下，范例md文件演示了如何编写可被该程序解析的格式

### 插入图表

目前暂时只支持折线图，将会在后继的开发计划中添加其他类型的图表

您可能需要添加以下内容

type: line
title: 标题
x.title: X轴标题
y.title: Y轴标题

### 说明

1. 添加图片时，请将图片放在assets/database/article/目录下，并添加resource:assets/database/article/图片名称