# 全能格式转换

免费离线格式转换工具 - 支持200+文件格式互转

## 支持的转换

| 类别 | 格式 | 转换方向 |
|------|------|---------|
| 🖼️ 图片 | PNG/JPEG/WebP/GIF/BMP/TIFF/HEIC/AVIF/ICO | 互相转换 |
| 📄 文档 | PDF/DOCX/XLSX/PPTX/ODT/ODS/ODP/RTF/TXT/CSV | 互转PDF/TXT/CSV/DOCX |
| 📦 压缩包 | ZIP/TAR/GZ/BZ2 → ZIP | 解压重打包 |

## 架构

- **文件检测**: 魔数头识别 (200+格式)
- **图片转换**: image库编解码
- **文档转换**: Apache POI + iText
- **压缩包**: archive库
- **编译**: GitHub Actions自动编译APK
