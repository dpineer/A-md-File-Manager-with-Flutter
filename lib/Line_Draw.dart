import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

//用于解析Markdown中的线性表数据
class ChartConfig {
  final String type;
  final String title;
  final String xTitle;
  final String yTitle;
  final String ySuffix;
  final List<String> headers;
  final List<Map<String, dynamic>> data;

  ChartConfig({
    required this.type,
    required this.title,
    required this.xTitle,
    required this.yTitle,
    required this.ySuffix,
    required this.headers,
    required this.data,
  });
}

class ChartDataParser {
  static ChartConfig parseChartData(String content) {
    List<String> lines = content.split('\n');

    // 解析数据部分
    List<String> headers = [];
    List<Map<String, dynamic>> data = [];
    Map<String, String> config = {};

    bool isDataSection = true;

    for (String line in lines) {
      line = line.trim();
      if (line.isEmpty) continue;

      if (line.startsWith('type:')) {
        isDataSection = false;
      }

      if (isDataSection) {
        // 解析CSV数据
        List<String> values = line.split(',').map((e) => e.trim()).toList();
        if (headers.isEmpty) {
          headers = values;
        } else {
          Map<String, dynamic> row = {};
          for (int i = 0; i < headers.length && i < values.length; i++) {
            if (values[i].isNotEmpty) {
              row[headers[i]] = double.tryParse(values[i]) ?? values[i];
            }
          }
          if (row.isNotEmpty) data.add(row);
        }
      } else {
        // 解析配置
        if (line.contains(':')) {
          List<String> parts = line.split(':');
          if (parts.length >= 2) {
            String key = parts[0].trim();
            String value = parts.sublist(1).join(':').trim();
            config[key] = value;
          }
        }
      }
    }

    return ChartConfig(
      type: config['type'] ?? 'line',
      title: config['title'] ?? '',
      xTitle: config['x.title'] ?? '',
      yTitle: config['y.title'] ?? '',
      ySuffix: config['y.suffix'] ?? '',
      headers: headers,
      data: data,
    );
  }
}

class LineChartWidget extends StatelessWidget {
  final ChartConfig config;

  const LineChartWidget({super.key, required this.config});

  Widget build(BuildContext context) {
    // 在构建图表之前，先检查数据是否为空
    if (config.data.isEmpty) {
      return Container(
        height: 350,
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.insert_chart, size: 48, color: Colors.grey[400]),
              SizedBox(height: 16),
              Text('暂无数据', style: TextStyle(color: Colors.grey[600])),
            ],
          ),
        ),
      );
    }
    // 准备折线图数据
    List<LineChartBarData> lineBarsData = [];
    List<String> xLabels = [];

    // 获取x轴标签（月份）
    xLabels = config.data
        .map((row) => row[config.headers[0]].toString())
        .toList();

    // 为每个数据系列创建一条线（除了第一列是标签列）
    for (int i = 1; i < config.headers.length; i++) {
      String header = config.headers[i];
      List<FlSpot> spots = [];

      for (int j = 0; j < config.data.length; j++) {
        double? value = config.data[j][header] is double
            ? config.data[j][header]
            : double.tryParse(config.data[j][header].toString());
        if (value != null) {
          spots.add(FlSpot(j.toDouble(), value));
        }
      }

      if (spots.isNotEmpty) {
        lineBarsData.add(
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: _getColorForIndex(i),
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(show: false),
          ),
        );
      }
    }

    return Container(
      height: 350,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          if (config.title.isNotEmpty)
            Text(
              config.title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          const SizedBox(height: 20),
          Expanded(
            child: LineChart(
              LineChartData(
                lineTouchData: LineTouchData(
                  enabled: true,
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (List<LineBarSpot> touchedSpots) {
                      return touchedSpots.map((spot) {
                        //String xLabel = xLabels[spot.x.toInt()];
                        String yValue =
                            spot.y.toStringAsFixed(0) + config.ySuffix;
                        String LineSet = config.headers[spot.barIndex];
                        return LineTooltipItem(
                          //'$LineSet X:$xLabel Y:$yValue',
                          '$LineSet : $yValue',
                          TextStyle(
                            color: _getColorForIndex(spot.barIndex),
                            fontSize: 12,
                            backgroundColor: Colors.white,
                          ),
                        );
                      }).toList();
                    },
                    getTooltipColor: (touchedSpot) {
                      return Colors.white;
                    },
                  ),
                ), //tooltipBgColor: Colors.blueAccent)),
                lineBarsData: lineBarsData,
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) => Text(
                        xLabels[value.toInt()],
                        style: const TextStyle(fontSize: 10),
                      ),
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        return Text('${value.toInt()}${config.ySuffix}');
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getColorForIndex(int index) {
    final colors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.red,
      Colors.teal,
      Colors.brown,
      Colors.cyan,
      Colors.indigo,
      Colors.lime,
    ];
    return colors[index % colors.length];
  }
}

class ChartElementBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    if (element.tag == 'code' &&
        element.attributes['class'] == 'language-chart') {
      try {
        String content = element.textContent;
        ChartConfig config = ChartDataParser.parseChartData(content);

        switch (config.type) {
          case 'line':
            return LineChartWidget(config: config);
          // 可以扩展其他图表类型
          default:
            return LineChartWidget(config: config);
        }
      } catch (e) {
        return Container(
          padding: const EdgeInsets.all(16),
          color: Colors.red[50],
          child: Text('图表解析错误: $e'),
        );
      }
    }
    return null;
  }
}
