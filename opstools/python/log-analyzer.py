#!/usr/bin/env python3
# ============================================================
# 软件名称: HodoopForge 企业级Hadoop集群部署与管理平台软件
# 文件名称: log-analyzer.py
# 文件功能: 日志分析工具
#   分析集群日志文件，提取错误、警告、
#   性能指标等关键信息。
# 版    本: V1.0
# 编制日期: 2026年4月
# ============================================================

import re
import os
from typing import Dict, List
from collections import Counter
from datetime import datetime

class LogAnalyzer:
    """日志分析器"""
    
    # 错误模式
    ERROR_PATTERNS = [
        r"ERROR",
        r"Exception",
        r"FATAL",
        r"Failed"
    ]
    
    # 警告模式
    WARNING_PATTERNS = [
        r"WARN",
        r"WARNING",
        r"Deprecated"
    ]
    
    def __init__(self, log_dir: str = "/var/log"):
        """
        初始化日志分析器
        
        参数:
            log_dir: 日志目录
        """
        self.log_dir = log_dir
        self.errors = []
        self.warnings = []
        self.stats = {}
    
    def analyze_file(self, filepath: str) -> Dict:
        """
        分析单个日志文件
        
        参数:
            filepath: 日志文件路径
            
        返回:
            Dict: 分析结果
        """
        if not os.path.exists(filepath):
            return {"error": "文件不存在"}
        
        result = {
            "file": filepath,
            "error_count": 0,
            "warning_count": 0,
            "errors": [],
            "warnings": []
        }
        
        with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
            for line_num, line in enumerate(f, 1):
                # 检查错误
                for pattern in self.ERROR_PATTERNS:
                    if re.search(pattern, line, re.IGNORECASE):
                        result["error_count"] += 1
                        result["errors"].append({
                            "line": line_num,
                            "content": line.strip()
                        })
                        break
                
                # 检查警告
                for pattern in self.WARNING_PATTERNS:
                    if re.search(pattern, line, re.IGNORECASE):
                        result["warning_count"] += 1
                        result["warnings"].append({
                            "line": line_num,
                            "content": line.strip()
                        })
                        break
        
        return result
    
    def analyze_directory(self, pattern: str = "*.log") -> Dict:
        """
        分析目录中的所有日志文件
        
        参数:
            pattern: 文件匹配模式
            
        返回:
            Dict: 分析结果汇总
        """
        results = {}
        
        for filename in os.listdir(self.log_dir):
            if filename.endswith(".log"):
                filepath = os.path.join(self.log_dir, filename)
                results[filename] = self.analyze_file(filepath)
        
        return results
    
    def get_error_summary(self) -> Dict:
        """
        获取错误摘要
        
        返回:
            Dict: 错误统计
        """
        error_counter = Counter()
        
        for error in self.errors:
            # 提取错误类型
            error_type = error.get("type", "UNKNOWN")
            error_counter[error_type] += 1
        
        return dict(error_counter)
    
    def generate_report(self, output_file: str):
        """
        生成分析报告
        
        参数:
            output_file: 输出文件路径
        """
        with open(output_file, "w") as f:
            f.write("日志分析报告\n")
            f.write("=" * 50 + "\n")
            f.write(f"生成时间: {datetime.now().isoformat()}\n\n")
            
            f.write("错误统计:\n")
            for error_type, count in self.get_error_summary().items():
                f.write(f"  {error_type}: {count}\n")
            
            f.write("\n警告统计:\n")
            f.write(f"  总数: {len(self.warnings)}\n")


if __name__ == "__main__":
    analyzer = LogAnalyzer("/var/log/ambari-server")
    results = analyzer.analyze_directory()
    analyzer.generate_report("/tmp/log-analysis-report.txt")
    print(f"分析报告已保存到: /tmp/log-analysis-report.txt")
