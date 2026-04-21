const fs = require("fs");
const { Document, Packer, Paragraph, TextRun, Table, TableRow, TableCell,
        Header, Footer, AlignmentType, HeadingLevel, BorderStyle, WidthType,
        ShadingType, PageBreak, PageNumber, LevelFormat } = require("docx");

const GREEN = "26A889";
const DARK = "141413";
const GRAY = "666666";
const LIGHT_GREEN = "EBF7E8";
const LIGHT_GRAY = "F5F5F5";
const WHITE = "FFFFFF";

const border = { style: BorderStyle.SINGLE, size: 1, color: "CCCCCC" };
const borders = { top: border, bottom: border, left: border, right: border };
const cellMargins = { top: 80, bottom: 80, left: 120, right: 120 };

function heading(text, level) {
  return new Paragraph({ heading: level, spacing: { before: level === HeadingLevel.HEADING_1 ? 400 : 240, after: 200 },
    children: [new TextRun({ text, bold: true, color: level === HeadingLevel.HEADING_1 ? GREEN : DARK })] });
}

function para(text, opts = {}) {
  return new Paragraph({ spacing: { after: 120 }, alignment: opts.align || AlignmentType.LEFT,
    children: [new TextRun({ text, size: opts.size || 24, color: opts.color || DARK, bold: opts.bold || false, font: "Noto Sans TC" })] });
}

function tableRow(cells, isHeader) {
  return new TableRow({
    children: cells.map((text, i) => new TableCell({
      borders, margins: cellMargins,
      width: { size: cells.length === 2 ? (i === 0 ? 3000 : 6360) : Math.floor(9360 / cells.length), type: WidthType.DXA },
      shading: isHeader ? { fill: GREEN, type: ShadingType.CLEAR } : (i % 2 === 0 ? {} : {}),
      children: [new Paragraph({ children: [new TextRun({ text, bold: isHeader, color: isHeader ? WHITE : DARK, size: 22, font: "Noto Sans TC" })] })]
    }))
  });
}

function makeTable(headers, rows, colWidths) {
  const totalWidth = 9360;
  const widths = colWidths || headers.map(() => Math.floor(totalWidth / headers.length));
  return new Table({
    width: { size: totalWidth, type: WidthType.DXA },
    columnWidths: widths,
    rows: [
      tableRow(headers, true),
      ...rows.map(r => tableRow(r, false))
    ]
  });
}

function bulletItem(text) {
  return new Paragraph({
    spacing: { after: 60 },
    indent: { left: 720, hanging: 360 },
    children: [new TextRun({ text: "\u2022  " + text, size: 22, font: "Noto Sans TC", color: DARK })]
  });
}

function scenarioBox(title, scenario, benefit) {
  return [
    new Paragraph({ spacing: { before: 160, after: 60 }, children: [
      new TextRun({ text: "\u25B6 " + title, bold: true, size: 24, color: GREEN, font: "Noto Sans TC" })
    ]}),
    new Paragraph({ spacing: { after: 40 }, indent: { left: 360 }, children: [
      new TextRun({ text: "\u60C5\u5883\uFF1A", bold: true, size: 22, color: GRAY, font: "Noto Sans TC" }),
      new TextRun({ text: scenario, size: 22, color: DARK, font: "Noto Sans TC" })
    ]}),
    new Paragraph({ spacing: { after: 120 }, indent: { left: 360 }, children: [
      new TextRun({ text: "\u6548\u76CA\uFF1A", bold: true, size: 22, color: GREEN, font: "Noto Sans TC" }),
      new TextRun({ text: benefit, size: 22, color: DARK, font: "Noto Sans TC" })
    ]})
  ];
}

const doc = new Document({
  styles: {
    default: { document: { run: { font: "Noto Sans TC", size: 24 } } },
    paragraphStyles: [
      { id: "Heading1", name: "Heading 1", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { size: 36, bold: true, font: "Noto Sans TC", color: GREEN },
        paragraph: { spacing: { before: 400, after: 200 }, outlineLevel: 0 } },
      { id: "Heading2", name: "Heading 2", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { size: 30, bold: true, font: "Noto Sans TC", color: DARK },
        paragraph: { spacing: { before: 240, after: 180 }, outlineLevel: 1 } },
      { id: "Heading3", name: "Heading 3", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { size: 26, bold: true, font: "Noto Sans TC", color: DARK },
        paragraph: { spacing: { before: 200, after: 120 }, outlineLevel: 2 } },
    ]
  },
  sections: [
    // === Cover Page ===
    {
      properties: {
        page: { size: { width: 12240, height: 15840 }, margin: { top: 1440, right: 1440, bottom: 1440, left: 1440 } }
      },
      children: [
        new Paragraph({ spacing: { before: 3000 }, alignment: AlignmentType.CENTER, children: [] }),
        new Paragraph({ alignment: AlignmentType.CENTER, spacing: { after: 200 }, children: [
          new TextRun({ text: "\u25CF", size: 48, color: GREEN, font: "Noto Sans TC" })
        ]}),
        new Paragraph({ alignment: AlignmentType.CENTER, spacing: { after: 400 }, children: [
          new TextRun({ text: "\u91D1\u878D\u696D IT \u6BCF\u65E5\u81EA\u52D5\u5DE1\u6AA2\u7CFB\u7D71", size: 52, bold: true, color: DARK, font: "Noto Sans TC" })
        ]}),
        new Paragraph({ alignment: AlignmentType.CENTER, spacing: { after: 100 }, children: [
          new TextRun({ text: "IT Daily Inspection System", size: 28, color: GRAY, font: "Noto Sans TC" })
        ]}),
        new Paragraph({ alignment: AlignmentType.CENTER, spacing: { after: 600 }, children: [
          new TextRun({ text: "\u5546\u696D\u4F01\u5283\u66F8", size: 32, color: GREEN, font: "Noto Sans TC" })
        ]}),
        new Paragraph({ alignment: AlignmentType.CENTER, spacing: { after: 100 }, children: [
          new TextRun({ text: "v2.3.0.0", size: 24, color: GRAY, font: "JetBrains Mono" })
        ]}),
        new Paragraph({ alignment: AlignmentType.CENTER, spacing: { after: 100 }, children: [
          new TextRun({ text: "2026\u5E744\u6708", size: 24, color: GRAY, font: "Noto Sans TC" })
        ]}),
        new Paragraph({ alignment: AlignmentType.CENTER, children: [
          new TextRun({ text: "\u6A5F\u5BC6\u6587\u4EF6 \u2022 \u50C5\u4F9B\u5167\u90E8\u8A55\u4F30", size: 20, color: "CC0000", font: "Noto Sans TC" })
        ]}),
        new Paragraph({ children: [new PageBreak()] }),
      ]
    },
    // === Content ===
    {
      properties: {
        page: { size: { width: 12240, height: 15840 }, margin: { top: 1440, right: 1440, bottom: 1440, left: 1440 } }
      },
      headers: {
        default: new Header({ children: [new Paragraph({ alignment: AlignmentType.RIGHT,
          children: [new TextRun({ text: "\u91D1\u878D\u696D IT \u6BCF\u65E5\u81EA\u52D5\u5DE1\u6AA2\u7CFB\u7D71 \u2022 \u5546\u696D\u4F01\u5283\u66F8", size: 18, color: GRAY, font: "Noto Sans TC" })] })] })
      },
      footers: {
        default: new Footer({ children: [new Paragraph({ alignment: AlignmentType.CENTER,
          children: [new TextRun({ text: "\u7B2C ", size: 18, color: GRAY }), new TextRun({ children: [PageNumber.CURRENT], size: 18, color: GRAY }),
            new TextRun({ text: " \u9801", size: 18, color: GRAY })] })] })
      },
      children: [
        // 1. 產品概述
        heading("\u58F9\u3001\u7522\u54C1\u6982\u8FF0", HeadingLevel.HEADING_1),
        para("\u300C\u91D1\u878D\u696D IT \u6BCF\u65E5\u81EA\u52D5\u5DE1\u6AA2\u7CFB\u7D71\u300D\u662F\u4E00\u5957\u5C08\u70BA\u91D1\u878D\u6A5F\u69CB\u8A2D\u8A08\u7684\u81EA\u52D5\u5316\u4E3B\u6A5F\u5065\u5EB7\u6AA2\u67E5\u5E73\u53F0\u3002\u7CFB\u7D71\u900F\u904E Ansible \u81EA\u52D5\u63A1\u96C6\u6578\u767E\u53F0\u4E3B\u6A5F\u7684\u5065\u5EB7\u72C0\u614B\uFF08CPU\u3001\u78C1\u789F\u3001\u670D\u52D9\u3001\u8CC7\u5B89\u65E5\u8A8C\u7B49\uFF09\uFF0C\u7D71\u4E00\u5448\u73FE\u65BC Web \u4ECB\u9762\uFF0C\u8B93\u7DAD\u904B\u5718\u968A\u5728 3 \u79D2\u5167\u638C\u63E1\u5168\u90E8\u4E3B\u6A5F\u72C0\u614B\u3002"),
        para("\u672C\u7CFB\u7D71\u53D6\u4EE3\u904E\u53BB\u4EBA\u5DE5\u9010\u53F0\u767B\u5165\u6AA2\u67E5\u7684\u7E41\u7463\u6D41\u7A0B\uFF0C\u5927\u5E45\u964D\u4F4E\u4EBA\u529B\u6210\u672C\u8207\u4EBA\u70BA\u758F\u5931\u98A8\u96AA\uFF0C\u540C\u6642\u6EFF\u8DB3\u91D1\u7BA1\u6703\u5C0D\u65BC IT \u7A3D\u6838\u8207\u8CC7\u5B89\u5408\u898F\u7684\u8981\u6C42\u3002"),

        heading("\u4E3B\u8981\u7279\u8272", HeadingLevel.HEADING_2),
        bulletItem("\u6975\u81F4\u81EA\u52D5\u5316\uFF1A\u652F\u63F4 Linux / AIX / Windows / \u7DB2\u8DEF\u8A2D\u5099 / AS400 \u8DE8\u5E73\u53F0\u63A1\u96C6"),
        bulletItem("\u8996\u89BA\u76F4\u89BA\u5316\uFF1ADashboard KPI + \u5373\u6642\u72C0\u614B + \u9EDE\u64CA\u7BE9\u9078"),
        bulletItem("\u8CC7\u5B89\u5408\u898F\uFF1A\u5E33\u865F\u76E4\u9EDE + UID=0 \u8B66\u793A + \u767B\u5165\u5931\u6557\u76E3\u63A7"),
        bulletItem("\u96E2\u7DDA\u90E8\u7F72\uFF1A\u9069\u5408\u91D1\u878D\u5167\u7DB2\uFF0C\u4E0D\u9700\u5916\u90E8\u7DB2\u8DEF"),
        bulletItem("\u5B8C\u6574\u7DAD\u8B77\uFF1A\u7CFB\u7D71\u7BA1\u7406 + \u5099\u4EFD\u9084\u539F + Patch \u66F4\u65B0"),

        new Paragraph({ children: [new PageBreak()] }),

        // 2. 市場分析
        heading("\u8CB3\u3001\u5E02\u5834\u5206\u6790", HeadingLevel.HEADING_1),
        heading("\u5E02\u5834\u75DB\u9EDE", HeadingLevel.HEADING_2),
        makeTable(
          ["\u75DB\u9EDE", "\u8AAA\u660E", "\u672C\u7CFB\u7D71\u89E3\u6C7A\u65B9\u5F0F"],
          [
            ["\u4EBA\u5DE5\u5DE1\u6AA2\u8017\u6642", "\u6BCF\u65E5\u6BCF\u53F0\u4E3B\u6A5F\u767B\u5165\u6AA2\u67E5\u9700 5-10 \u5206\u9418\uFF0C500 \u53F0\u9700 40+ \u4EBA\u6642", "\u81EA\u52D5\u63A1\u96C6\uFF0C3 \u79D2\u770B\u5B8C\u5168\u90E8"],
            ["\u4EBA\u70BA\u758F\u5931", "\u624B\u52D5\u6AA2\u67E5\u5BB9\u6613\u907A\u6F0F\u3001\u8AA4\u5224", "\u6A19\u6E96\u5316\u6AA2\u67E5\u9805\u76EE\uFF0C\u96F6\u907A\u6F0F"],
            ["\u7A3D\u6838\u5408\u898F", "\u91D1\u7BA1\u6703\u8981\u6C42 IT \u7A3D\u6838\u7D00\u9304\u8207\u5831\u8868", "\u81EA\u52D5\u7522\u751F\u5408\u898F\u5831\u544A + \u5E33\u865F\u76E4\u9EDE"],
            ["\u8CC7\u5B89\u5A01\u8105", "\u5F71\u5B50\u5E33\u865F\u3001\u63D0\u6B0A\u653B\u64CA\u96E3\u4EE5\u5373\u6642\u767C\u73FE", "UID=0 \u5373\u6642\u8B66\u793A + \u767B\u5165\u5931\u6557\u76E3\u63A7"],
            ["\u7DAD\u904B\u4EBA\u529B\u4E0D\u8DB3", "\u5C11\u6578\u4EBA\u7BA1\u7406\u6578\u767E\u53F0\u4E3B\u6A5F", "\u4E00\u500B\u4EBA\u5C31\u80FD\u76E3\u63A7\u5168\u90E8"],
          ],
          [2200, 3580, 3580]
        ),

        heading("\u76EE\u6A19\u5BA2\u7FA4", HeadingLevel.HEADING_2),
        bulletItem("\u8B49\u5238\u516C\u53F8\uFF08\u570B\u6CF0\u3001\u5143\u5927\u3001\u51F1\u57FA\u3001\u5BCC\u90A6\u7B49\uFF09"),
        bulletItem("\u9280\u884C\u696D\uFF08\u8CC7\u8A0A\u8655 / IT \u90E8\u9580\uFF09"),
        bulletItem("\u4FDD\u96AA\u516C\u53F8\uFF08\u570B\u6CF0\u4EBA\u58FD\u3001\u5BCC\u90A6\u7522\u96AA\u7B49\uFF09"),
        bulletItem("\u6295\u4FE1\u516C\u53F8 / \u8CC7\u7522\u7BA1\u7406\u516C\u53F8"),
        bulletItem("\u91D1\u63A7\u516C\u53F8 IT \u5171\u7528\u670D\u52D9"),

        new Paragraph({ children: [new PageBreak()] }),

        // 3. 功能清單
        heading("\u53C3\u3001\u529F\u80FD\u6E05\u55AE\u8207\u60C5\u5883\u8AAA\u660E", HeadingLevel.HEADING_1),

        // 3.1 Dashboard
        heading("3.1 \u667A\u6167\u7E3D\u89BD Dashboard", HeadingLevel.HEADING_2),
        para("\u63D0\u4F9B KPI \u5361\u7247\uFF08\u6B63\u5E38/\u8B66\u544A/\u7570\u5E38/\u7E3D\u6578 + \u767E\u5206\u6BD4\uFF09\u3001OS \u6578\u91CF\u7D71\u8A08\u3001\u7570\u5E38\u7BE9\u9078\u958B\u95DC\u3001\u9EDE\u64CA KPI \u53EF\u7BE9\u9078\u5C0D\u61C9\u72C0\u614B\u4E3B\u6A5F\u3002"),
        ...scenarioBox("\u60C5\u5883\uFF1A\u6BCF\u65E5\u958B\u9580\u5DE1\u6AA2",
          "\u7DAD\u904B\u5DE5\u7A0B\u5E2B\u65E9\u4E0A 6:30 \u4E0A\u73ED\uFF0C\u6253\u958B Dashboard\uFF0C3 \u79D2\u5167\u770B\u5230\u300C\u6B63\u5E38 498 \u53F0 (99.6%)\u3001\u7570\u5E38 2 \u53F0 (0.4%)\u300D\u3002\u9EDE\u64CA\u7570\u5E38\u5361\u7247\uFF0C\u76F4\u63A5\u770B\u5230\u54EA\u53F0\u6A5F\u5668\u6709\u554F\u984C\u3002",
          "\u5F9E\u539F\u672C 2 \u5C0F\u6642\u7684\u4EBA\u5DE5\u5DE1\u6AA2\u7E2E\u77ED\u70BA 3 \u79D2\uFF0C\u7BC0\u7701 99.96% \u7684\u6642\u9593\u3002"),

        // 3.2 今日報告
        heading("3.2 \u4ECA\u65E5\u5DE1\u6AA2\u5831\u544A", HeadingLevel.HEADING_2),
        para("\u6BCF\u53F0\u4E3B\u6A5F\u5361\u7247\u986F\u793A\uFF1ACPU/MEM/Swap/IO/Load/Users/Disk/\u670D\u52D9/\u5E33\u865F/\u932F\u8AA4\u65E5\u8A8C/FailLogin/Uptime\u3002\u78C1\u789F\u6B63\u5E38\u986F\u793A OK\uFF0C\u7570\u5E38\u624D\u5C55\u958B\u7D30\u7BC0\u3002\u6BCF\u5F35\u5361\u7247\u53EF\u9EDE\u64CA\u9032\u5165\u8A73\u7D30\u5831\u544A\u3002"),
        ...scenarioBox("\u60C5\u5883\uFF1A\u4E3B\u7BA1\u8981\u6C42\u67E5\u770B\u7279\u5B9A\u4E3B\u6A5F",
          "\u4E3B\u7BA1\u554F\uFF1A\u300CPROD-SVR05 \u6628\u5929\u7684 CPU \u662F\u4E0D\u662F\u5F88\u9AD8\uFF1F\u300D\u7DAD\u904B\u76F4\u63A5\u9EDE\u9032 PROD-SVR05 \u8A73\u7D30\u5831\u544A\uFF0C\u770B\u5230 CPU 85%\u3001MEM 72%\u3001\u78C1\u789F C: 91% \u8B66\u544A\u3002",
          "\u4E0D\u7528\u767B\u5165\u4E3B\u6A5F\u5C31\u80FD\u5373\u6642\u56DE\u7B54\u4E3B\u7BA1\uFF0C\u5C55\u73FE\u5C08\u696D\u5EA6\u3002"),

        // 3.3 異常總結
        heading("3.3 \u7570\u5E38\u7E3D\u7D50\u5831\u544A", HeadingLevel.HEADING_2),
        para("\u4F9D\u56B4\u91CD\u5EA6\u6392\u5E8F\u7570\u5E38\u4E3B\u6A5F\uFF0C\u986F\u793A\uFF1A\u7570\u5E38\u539F\u56E0\u5206\u6790\u3001\u5EFA\u8B70\u8655\u7406\u52D5\u4F5C\uFF08\u542B\u5BE6\u969B\u6307\u4EE4\uFF09\u3001\u8CA0\u8CAC\u4EBA\u8CC7\u8A0A\u3001\u8207\u6628\u65E5\u8DA8\u52E2\u6BD4\u8F03\u3002\u53EF\u532F\u51FA\u6587\u5B57\u5831\u544A\u3002"),
        ...scenarioBox("\u60C5\u5883\uFF1A\u7570\u5E38\u8655\u7406\u6D3E\u5DE5",
          "\u7570\u5E38\u7E3D\u7D50\u986F\u793A 3 \u53F0\u7570\u5E38\uFF1APROD-DB01 \u78C1\u789F 96%\u3001PROD-AP03 \u670D\u52D9\u505C\u6B62\u3001PROD-SVR12 \u5E33\u865F\u7570\u52D5\u3002\u6BCF\u53F0\u90FD\u6709\u5EFA\u8B70\u6307\u4EE4\u548C\u8CA0\u8CAC\u4EBA\uFF0C\u76F4\u63A5\u6D3E\u5DE5\u8655\u7406\u3002",
          "\u7570\u5E38\u8655\u7406\u6642\u9593\u5F9E\u5E73\u5747 2 \u5C0F\u6642\u7E2E\u77ED\u70BA 15 \u5206\u9418\u3002"),

        // 3.4 帳號盤點
        heading("3.4 \u5E33\u865F\u76E4\u9EDE\u7CFB\u7D71", HeadingLevel.HEADING_2),
        para("\u81EA\u52D5\u63A1\u96C6\u6240\u6709\u4E3B\u6A5F\u7684\u975E\u5167\u5EFA\u5E33\u865F\uFF0C\u6AA2\u67E5\uFF1A180 \u5929\u672A\u6539\u5BC6\u78BC\u3001\u5BC6\u78BC\u5DF2\u5230\u671F\u3001180 \u5929\u672A\u767B\u5165\u3002\u652F\u63F4 HR \u4EBA\u54E1\u6A94\u6848\u532F\u5165\u81EA\u52D5\u5C0D\u61C9\u90E8\u9580\uFF0C\u53EF\u7DE8\u8F2F\u5E33\u865F\u5099\u8A3B\uFF0C\u53EF\u532F\u51FA CSV\u3002"),
        ...scenarioBox("\u60C5\u5883\uFF1A\u8CC7\u5B89\u7A3D\u6838\u8981\u6C42\u5E33\u865F\u76E4\u9EDE",
          "\u8CC7\u5B89\u7A3D\u6838\u54E1\u8981\u6C42\u63D0\u4F9B\u300C\u6240\u6709\u4E3B\u6A5F\u5E33\u865F\u6E05\u55AE + \u5BC6\u78BC\u66F4\u65B0\u72C0\u614B + \u672A\u767B\u5165\u5E33\u865F\u300D\u3002\u904E\u53BB\u9700\u8981\u9010\u53F0\u767B\u5165\u67E5\u8A62\uFF0C\u73FE\u5728\u76F4\u63A5\u958B\u5E33\u865F\u76E4\u9EDE\u9801\u9762\uFF0C\u7BE9\u9078\u300C\u6709\u98A8\u96AA\u300D\uFF0C\u532F\u51FA CSV \u5373\u53EF\u3002",
          "\u7A3D\u6838\u6E96\u5099\u6642\u9593\u5F9E 3 \u5929\u7E2E\u77ED\u70BA 5 \u5206\u9418\u3002"),

        // 3.5 UID=0 警示
        heading("3.5 UID=0 \u9AD8\u5371\u8B66\u793A", HeadingLevel.HEADING_2),
        para("\u7576\u5075\u6E2C\u5230\u4EFB\u4F55\u4E3B\u6A5F\u65B0\u589E UID=0 \u5E33\u865F\uFF08\u6F5B\u5728\u63D0\u6B0A\u653B\u64CA\uFF09\uFF0CDashboard \u548C\u8A73\u7D30\u5831\u544A\u90FD\u6703\u89F8\u767C\u7D05\u8272\u52D5\u614B\u9583\u720D\u8B66\u793A\uFF0C\u78BA\u4FDD\u4E0D\u6F0F\u770B\u3002"),
        ...scenarioBox("\u60C5\u5883\uFF1A\u63D0\u6B0A\u653B\u64CA\u5075\u6E2C",
          "\u99AD\u5BA2\u5728 PROD-DB01 \u5EFA\u7ACB\u4E86\u4E00\u500B UID=0 \u7684\u5F8C\u9580\u5E33\u865F\u3002\u7CFB\u7D71\u5728\u4E0B\u6B21\u5DE1\u6AA2\u6642\u5373\u523B\u5075\u6E2C\uFF0CDashboard \u51FA\u73FE\u7D05\u8272\u9583\u720D\u8B66\u793A\uFF0C\u7DAD\u904B\u5718\u968A\u7ACB\u5373\u8655\u7406\u3002",
          "\u653B\u64CA\u5075\u6E2C\u6642\u9593\u5F9E\u300C\u4E0D\u77E5\u9053\u300D\u7E2E\u77ED\u70BA\u300C\u6700\u591A 8 \u5C0F\u6642\u300D\uFF08\u5DE1\u6AA2\u9593\u9694\uFF09\u3002"),

        new Paragraph({ children: [new PageBreak()] }),

        // 3.6 登入失敗監控
        heading("3.6 \u767B\u5165\u5931\u6557\u76E3\u63A7 (FailLogin)", HeadingLevel.HEADING_2),
        para("\u7D71\u8A08\u6BCF\u53F0\u4E3B\u6A5F\u7684\u767B\u5165\u5931\u6557\u6B21\u6578\uFF0C\u986F\u793A\u8D85\u904E 5 \u6B21\u7684\u524D 3 \u540D\uFF0C\u53EF\u5C55\u958B Raw Data \u660E\u7D30\uFF08\u5E33\u865F/\u4F86\u6E90IP/\u6642\u9593\uFF09\u3002\u88AB\u9396\u5B9A\u5E33\u865F\u986F\u793A\u89E3\u9396\u6307\u4EE4\u3002"),
        ...scenarioBox("\u60C5\u5883\uFF1A\u66B4\u529B\u7834\u89E3\u5075\u6E2C",
          "\u5075\u6E2C\u5230\u67D0\u53F0\u4E3B\u6A5F 24 \u5C0F\u6642\u5167\u6709 500+ \u6B21\u5931\u6557\u767B\u5165\uFF0C\u4F86\u6E90 IP \u96C6\u4E2D\u5728 10.0.5.x \u7DB2\u6BB5\u3002\u7DAD\u904B\u7ACB\u5373\u5C01\u9396 IP \u4E26\u901A\u5831\u8CC7\u5B89\u3002",
          "\u4E3B\u52D5\u5075\u6E2C\u800C\u975E\u88AB\u52D5\u7B49\u5F85\u3002"),

        // 3.7 跨平台支援
        heading("3.7 \u8DE8\u5E73\u53F0\u652F\u63F4", HeadingLevel.HEADING_2),
        makeTable(
          ["\u5E73\u53F0", "\u9023\u7DDA\u65B9\u5F0F", "\u76E3\u63A7\u9805\u76EE"],
          [
            ["Linux (Rocky/RHEL/Debian)", "SSH", "CPU/MEM/Disk/Service/Account/Log/Swap/IO/Load/Users/FailLogin"],
            ["AIX 7.x", "SSH (raw)", "\u540C\u4E0A\uFF08\u4E0D\u5B89\u88DD Python\uFF09"],
            ["Windows 2016/2019/2022", "SSH/WinRM", "\u540C\u4E0A + Update/IIS/Defender/\u9632\u706B\u7246"],
            ["\u7DB2\u8DEF\u8A2D\u5099 (Cisco/Juniper)", "SNMP", "\u4ECB\u9762\u72C0\u614B/\u932F\u8AA4\u8A08\u6578/CPU/Uptime"],
            ["IBM AS/400", "SNMP", "ASP\u4F7F\u7528\u7387/CPU/Jobs/Users"],
          ],
          [2500, 1860, 5000]
        ),

        // 3.8 系統管理
        heading("3.8 \u7CFB\u7D71\u7BA1\u7406 (12 \u500B Tab)", HeadingLevel.HEADING_2),
        makeTable(
          ["Tab", "\u529F\u80FD\u8AAA\u660E"],
          [
            ["\u7CFB\u7D71\u72C0\u614B", "Flask/MongoDB/\u78C1\u789F/\u5BB9\u5668\u72C0\u614B + \u5FEB\u901F\u64CD\u4F5C"],
            ["\u8A2D\u5B9A\u7BA1\u7406", "\u95BE\u503C\u4FEE\u6539 + \u670D\u52D9\u6E05\u55AE + Email \u901A\u77E5"],
            ["\u5099\u4EFD\u7BA1\u7406", "\u7A0B\u5F0F\u5099\u4EFD + MongoDB Dump/Restore + Patch \u66F4\u65B0"],
            ["\u5DE5\u4F5C\u6392\u7A0B", "\u6700\u8FD1\u57F7\u884C\u72C0\u614B + \u65E5\u8A8C"],
            ["\u65E5\u8A8C\u6AA2\u8996", "\u641C\u5C0B/\u7BE9\u9078\u5DE1\u6AA2\u65E5\u8A8C"],
            ["\u4E3B\u6A5F\u7BA1\u7406", "\u65B0\u589E/\u7DE8\u8F2F/\u522A\u9664/Ping/CSV\u532F\u5165\u532F\u51FA"],
            ["\u544A\u8B66\u7BA1\u7406", "\u5448\u8B66\u7D00\u9304 + \u78BA\u8A8D"],
            ["\u6392\u7A0B\u8A2D\u5B9A", "\u65B0\u589E/\u505C\u7528/\u522A\u9664\u5DE1\u6AA2\u6392\u7A0B"],
            ["\u5408\u898F\u5831\u544A", "\u6708\u5831 + SLA% + \u532F\u51FA CSV"],
            ["\u5E33\u865F\u76E4\u9EDE", "\u98A8\u96AA\u6A19\u793A + \u7BE9\u9078 + \u5099\u8A3B\u7DE8\u8F2F"],
            ["\u5E33\u865F\u7BA1\u7406", "\u95BE\u503C\u8A2D\u5B9A + HR \u532F\u5165 + \u4EBA\u54E1\u5C0D\u61C9"],
            ["\u64CD\u4F5C\u7D00\u9304", "\u5B8C\u6574\u5BE9\u8A08\u8ECC\u8DE1"],
          ]
        ),

        new Paragraph({ children: [new PageBreak()] }),

        // 4. 技術架構
        heading("\u8086\u3001\u6280\u8853\u67B6\u69CB", HeadingLevel.HEADING_1),
        makeTable(
          ["\u5C64\u7D1A", "\u6280\u8853", "\u8AAA\u660E"],
          [
            ["\u8CC7\u6599\u63A1\u96C6", "Ansible Core 2.14", "\u8DE8\u5E73\u53F0\u5DE1\u6AA2\u5F15\u64CE"],
            ["\u5F8C\u7AEF API", "Python 3.9 + Flask", "REST API + MongoDB \u9023\u63A5"],
            ["\u524D\u7AEF", "HTML5 + \u539F\u751F JS", "\u570B\u6CF0 CI \u98A8\u683C + SVG \u5716\u793A"],
            ["\u8CC7\u6599\u5EAB", "MongoDB 6 (Podman)", "\u652F\u63F4 500+ \u53F0\u4E3B\u6A5F"],
            ["\u4EBA\u54E1\u67E5\u8A62", "LDAP", "\u5373\u6642\u67E5 AD\uFF0C\u4E0D\u5132\u5B58\u500B\u8CC7"],
            ["\u90E8\u7F72", "Podman \u96E2\u7DDA\u90E8\u7F72", "\u9069\u5408\u91D1\u878D\u5167\u7DB2"],
          ],
          [2000, 3000, 4360]
        ),

        heading("\u5B89\u5168\u6027", HeadingLevel.HEADING_2),
        bulletItem("ansible_svc \u5E33\u865F\uFF1A\u96F6 SUDO\uFF0C\u6700\u5C0F\u6B0A\u9650\u539F\u5247"),
        bulletItem("SSH Key\uFF1Aed25519\uFF0C365 \u5929\u66F4\u65B0\u9031\u671F"),
        bulletItem("MongoDB\uFF1A\u50C5\u5141\u8A31\u672C\u5730\u9023\u7DDA (127.0.0.1)"),
        bulletItem("\u767B\u5165\u7CFB\u7D71\uFF1ASession + \u5BC6\u78BC\u96DC\u6E4A + \u89D2\u8272\u63A7\u5236"),
        bulletItem("\u6240\u6709\u7BA1\u7406\u64CD\u4F5C\u5BE9\u8A08\u8EFD\u8DE1\u8A18\u9304"),

        new Paragraph({ children: [new PageBreak()] }),

        // 5. 定價策略
        heading("\u4F0D\u3001\u5B9A\u50F9\u7B56\u7565", HeadingLevel.HEADING_1),
        makeTable(
          ["\u65B9\u6848", "\u7BC4\u570D", "\u5EFA\u8B70\u552E\u50F9"],
          [
            ["\u57FA\u672C\u7248", "50 \u53F0\u4EE5\u4E0B\u3001Linux only", "NT$ 30 \u842C"],
            ["\u5C08\u696D\u7248", "200 \u53F0\u3001Linux + Windows", "NT$ 80 \u842C"],
            ["\u4F01\u696D\u7248", "500 \u53F0\u3001\u5168\u5E73\u53F0 + \u5E33\u865F\u76E4\u9EDE", "NT$ 150 \u842C"],
            ["\u5E74\u5EA6\u7DAD\u8B77", "\u66F4\u65B0 + \u6280\u8853\u652F\u63F4", "NT$ 30 \u842C/\u5E74"],
            ["\u5BA2\u88FD\u958B\u767C", "\u4F9D\u9700\u6C42\u5831\u50F9", "\u53E6\u8B70"],
          ],
          [2000, 4360, 3000]
        ),

        // 6. 競爭優勢
        heading("\u9678\u3001\u7AF6\u722D\u512A\u52E2", HeadingLevel.HEADING_1),
        makeTable(
          ["\u9805\u76EE", "\u672C\u7CFB\u7D71", "\u50B3\u7D71\u65B9\u5F0F", "\u5546\u696D\u76E3\u63A7\u5DE5\u5177"],
          [
            ["\u90E8\u7F72", "\u96E2\u7DDA\u4E00\u9375\u5B89\u88DD", "\u9700\u5C08\u4EBA\u5EFA\u7F6E", "\u9700\u96F2\u7AEF/\u8907\u96DC\u67B6\u69CB"],
            ["\u8DE8\u5E73\u53F0", "Linux/Windows/AIX/SNMP/AS400", "\u55AE\u4E00\u5E73\u53F0", "\u9700\u984D\u5916\u6388\u6B0A"],
            ["\u5E33\u865F\u76E4\u9EDE", "\u5167\u5EFA + HR \u5C0D\u61C9", "\u7121", "\u9700\u984D\u5916\u6A21\u7D44"],
            ["\u91D1\u878D\u5408\u898F", "\u5167\u5EFA SLA/\u6708\u5831", "\u624B\u5DE5\u6574\u7406", "\u9700\u5BA2\u88FD"],
            ["\u7DAD\u8B77\u6210\u672C", "\u4F4E\uFF08Web \u7BA1\u7406\uFF09", "\u9AD8\uFF08\u9700\u5C08\u4EBA\uFF09", "\u9AD8\uFF08\u6388\u6B0A\u8CBB\uFF09"],
            ["\u50F9\u683C", "NT$ 30-150 \u842C", "\u4EBA\u529B\u6210\u672C", "NT$ 100-500 \u842C/\u5E74"],
          ],
          [1800, 2520, 2520, 2520]
        ),

        new Paragraph({ children: [new PageBreak()] }),

        // 7. 導入效益
        heading("\u67D2\u3001\u5C0E\u5165\u6548\u76CA", HeadingLevel.HEADING_1),
        makeTable(
          ["\u6548\u76CA\u9805\u76EE", "\u5C0E\u5165\u524D", "\u5C0E\u5165\u5F8C", "\u6539\u5584\u5E45\u5EA6"],
          [
            ["\u6BCF\u65E5\u5DE1\u6AA2\u6642\u9593", "2-4 \u5C0F\u6642", "3 \u79D2", "99.9%"],
            ["\u7570\u5E38\u767C\u73FE\u6642\u9593", "\u5E73\u5747 2 \u5C0F\u6642", "15 \u5206\u9418", "87.5%"],
            ["\u7A3D\u6838\u6E96\u5099", "3-5 \u5929", "5 \u5206\u9418", "99.9%"],
            ["\u4EBA\u529B\u9700\u6C42", "3-5 \u4EBA", "1 \u4EBA", "60-80%"],
            ["\u4EBA\u70BA\u758F\u5931\u7387", "\u7D04 5%", "\u8D8A\u8FD1 0%", "~100%"],
            ["\u653B\u64CA\u5075\u6E2C", "\u88AB\u52D5\u767C\u73FE", "\u4E3B\u52D5\u5075\u6E2C", "\u8CEA\u8B8A"],
          ],
          [2000, 2500, 2360, 2500]
        ),

        heading("ROI \u8A66\u7B97", HeadingLevel.HEADING_2),
        para("\u5047\u8A2D 500 \u53F0\u4E3B\u6A5F\u3001\u73FE\u6709 3 \u540D\u7DAD\u904B\u5DE5\u7A0B\u5E2B\uFF0C\u6BCF\u4EBA\u6708\u85AA NT$ 60,000\uFF1A"),
        bulletItem("\u6BCF\u65E5\u5DE1\u6AA2\u7BC0\u7701 2 \u4EBA\u5DE5\u6642 \u00D7 22 \u5929 = 44 \u4EBA\u5DE5\u6642/\u6708"),
        bulletItem("\u7D04\u7B49\u65BC 0.25 \u540D\u5168\u8077\u4EBA\u529B = NT$ 15,000/\u6708"),
        bulletItem("\u4F01\u696D\u7248 NT$ 150 \u842C \u00F7 NT$ 15,000 = 10 \u500B\u6708\u56DE\u672C"),
        bulletItem("\u52A0\u4E0A\u7A3D\u6838\u6548\u7387\u63D0\u5347\u3001\u8CC7\u5B89\u98A8\u96AA\u964D\u4F4E\uFF0C\u5BE6\u969B ROI \u66F4\u9AD8"),

        new Paragraph({ spacing: { before: 400 }, children: [] }),

        // 8. 聯繫
        heading("\u634C\u3001\u806F\u7E6B\u8CC7\u8A0A", HeadingLevel.HEADING_1),
        para("\u5982\u6709\u8208\u8DA3\u4E86\u89E3\u66F4\u591A\u6216\u5B89\u6392\u5C55\u793A\uFF0C\u6B61\u8FCE\u806F\u7E6B\uFF1A"),
        new Paragraph({ spacing: { after: 400 }, children: [] }),
        para("\u672C\u4F01\u5283\u66F8\u70BA\u6A5F\u5BC6\u6587\u4EF6\uFF0C\u50C5\u4F9B\u5167\u90E8\u8A55\u4F30\u4F7F\u7528\u3002", { color: "CC0000", size: 20 }),
      ]
    }
  ]
});

Packer.toBuffer(doc).then(buffer => {
  const outPath = process.argv[2] || "proposal.docx";
  fs.writeFileSync(outPath, buffer);
  console.log("Generated: " + outPath + " (" + buffer.length + " bytes)");
});
