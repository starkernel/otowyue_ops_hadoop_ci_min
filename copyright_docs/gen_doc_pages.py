#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
HodoopForge 文档鉴别材料生成工具
按照中国软件著作权登记要求生成文档前后各30页
"""

import os

# 源文档路径
SOURCE_DOC = 'copyright_docs/用户手册.md'
TARGET = 'copyright_docs/文档鉴别材料-用户手册.md'

# 每页行数（软著要求每页约50行）
LINES_PER_PAGE = 50
# 前30页行数
FRONT_PAGES = 30
# 后30页行数  
BACK_PAGES = 30

def count_lines(filepath):
    """统计文件行数"""
    with open(filepath, 'r', encoding='utf-8') as f:
        return sum(1 for _ in f)

def read_all_lines(filepath):
    """读取所有行"""
    with open(filepath, 'r', encoding='utf-8') as f:
        return f.readlines()

def generate_doc_pages():
    """生成文档前后30页"""
    
    lines = read_all_lines(SOURCE_DOC)
    total_lines = len(lines)
    
    print(f"源文档: {SOURCE_DOC}")
    print(f"总行数: {total_lines}")
    
    # 前30页约1500行，后30页约1500行
    front_page_lines = 1500
    back_page_start = max(0, total_lines - 1500)
    
    print(f"前30页: 1-{front_page_lines}行")
    print(f"后30页: {back_page_start+1}-{total_lines}行")
    
    output = []
    
    # 文档头部
    output.append("""# HodoopForge 文档鉴别材料

**软件名称**：HodoopForge 企业级Hadoop集群部署与管理平台软件 V1.0  
**文档名称**：用户手册  
**编制日期**：2026年5月  

**说明**：按中国软件著作权登记要求，提供文档前30页与后30页，每页约50行。

**文档统计**：
- 文档总行数：{total}行
- 前30页：第1-1,500行
- 后30页：第{back_start}-{total}行

---

# 文档 前30页

---

""".format(total=total_lines, back_start=back_page_start+1))
    
    # 生成前30页
    page_num = 1
    lines_in_page = 0
    
    front_lines = lines[:front_page_lines]
    i = 0
    
    while i < len(front_lines) and page_num <= 30:
        if lines_in_page == 0:
            output.append(f"## 第{page_num}页\n\n")
        
        # 添加行
        remaining = 50 - lines_in_page
        chunk = front_lines[i:i+remaining]
        output.extend(chunk)
        
        added = len(chunk)
        lines_in_page += added
        i += added
        
        if lines_in_page >= 50:
            output.append("\n---\n\n")
            page_num += 1
            lines_in_page = 0
    
    if lines_in_page > 0:
        output.append("\n---\n\n")
    
    # 后30页起始位置
    output.append("""# 文档 后30页

---

""")
    
    # 生成后30页
    page_num = 1
    lines_in_page = 0
    
    back_lines = lines[back_page_start:]
    i = 0
    
    while i < len(back_lines) and page_num <= 30:
        if lines_in_page == 0:
            output.append(f"## 后第{page_num}页\n\n")
        
        # 添加行
        remaining = 50 - lines_in_page
        chunk = back_lines[i:i+remaining]
        output.extend(chunk)
        
        added = len(chunk)
        lines_in_page += added
        i += added
        
        if lines_in_page >= 50:
            output.append("\n---\n\n")
            page_num += 1
            lines_in_page = 0
    
    if lines_in_page > 0:
        output.append("\n---\n\n")
    
    # 文档尾部
    output.append(f"""---

**文档说明**：
- 本文档按中国软件著作权登记要求编制
- 文档前30页：展示用户手册的起始部分
- 文档后30页：展示用户手册的结尾部分
- 每页约50行，总计约3,000行文档展示

**编制单位**：HodoopForge 开发团队  
**编制日期**：2026年5月
""")
    
    # 写入文件
    with open(TARGET, 'w', encoding='utf-8') as f:
        f.write(''.join(output))
    
    print(f"\n文档已生成: {TARGET}")
    print(f"文档大小: {os.path.getsize(TARGET)} 字节")

if __name__ == '__main__':
    generate_doc_pages()
