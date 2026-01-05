# MarkDown 功能测试文档

## 1. 基本文本格式测试
这是一个测试文档，用于验证**Markdown**的各种语法特性。我们可以创建*无序列表*：
- 列项二
- 列表项三

1. 第一项
2. 第二项
3. 第三项表项一
- 列表

## 2. 表格测试
下面是一个简单的表格示例：

| 姓名 | 年龄 | 职业 |
|------|------|------|
| 张三 | 28   | 工程师 |
| 李四 | 32   | 设计师 |


$$
c = \pm\sqrt{a^2 + b^2}
$$

![Alt](resource:assets/database/article/AP1.png)

$$
\int_{-\infty}^{\infty} e^{-x^2} dx = \sqrt{\pi}
$$

## 表格示例
| 函数 | 公式 | 描述 |
|------|------|------|
| 正弦 | $\sin(x)$ | 三角函数 |
| 指数 | $e^{x}$ | 指数函数 |
| 积分 | $\int f(x) dx$ | 不定积分 |


## 图表示例

```chart
Budget,Income,Expenses,Debt
June,500.30,8000,4000,6000
July,3000,1000,4000,3000
Aug,5000,7000,6000,3000
Sep,7000,2000,3000,1000
Oct,6000,500.890,4000,2000
Nov,4000,3000,5000,

type: line
title: Monthly Revenue
x.title: Amount
y.title: Month
```
✌

```chart
Budget,Income,Expenses,Debt
1,5000,8000,4000,6000
2,3000,1000,4000,3000
3,5000,7000,6000,3000
4,7000,2000,3.32000,1000
5,6000,5000,4000,2000
6,4000,3000,5000,

type: line
title: 测试
x.title: Amount
y.title: Month
```

## 5. 数学公式测试
行内公式示例：爱因斯坦质能方程 $E = mc^2$

块级公式示例：
$$
\sum_{i=1}^{n} i = \frac{n(n+1)}{2}
$$

## 代码示例
```python
void main() {
  // 计算圆的面积
  double area = Math.pi * Math.pow(radius, 2);
  print('面积: $area');
}
```

---

**注意**：[3](@ref)。
```
