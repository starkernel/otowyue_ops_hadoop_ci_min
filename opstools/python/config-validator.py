#!/usr/bin/env python3
# ============================================================
# 软件名称: HodoopForge 企业级Hadoop集群部署与管理平台软件
# 文件名称: config-validator.py
# 文件功能: 配置文件验证工具
#   验证 Hadoop 配置文件的正确性，
#   检查必需参数、格式、依赖关系等。
# 版    本: V1.0
# 编制日期: 2026年4月
# ============================================================

import xml.etree.ElementTree as ET
import os
from typing import List, Tuple

class ConfigValidator:
    """配置文件验证器"""
    
    # 必需配置项定义
    REQUIRED_CONFIGS = {
        "core-site.xml": ["fs.defaultFS", "hadoop.tmp.dir"],
        "hdfs-site.xml": ["dfs.replication", "dfs.namenode.name.dir"],
        "yarn-site.xml": ["yarn.resourcemanager.hostname"],
        "hive-site.xml": ["javax.jdo.option.ConnectionURL"]
    }
    
    def __init__(self, config_dir: str = "/etc/hadoop/conf"):
        """
        初始化验证器
        
        参数:
            config_dir: 配置文件目录
        """
        self.config_dir = config_dir
        self.errors = []
        self.warnings = []
    
    def validate_file(self, filename: str) -> bool:
        """
        验证单个配置文件
        
        参数:
            filename: 配置文件名
            
        返回:
            bool: 验证是否通过
        """
        filepath = os.path.join(self.config_dir, filename)
        
        if not os.path.exists(filepath):
            self.errors.append(f"配置文件不存在: {filepath}")
            return False
        
        try:
            tree = ET.parse(filepath)
            root = tree.getroot()
            
            # 检查必需配置项
            if filename in self.REQUIRED_CONFIGS:
                for required in self.REQUIRED_CONFIGS[filename]:
                    found = False
                    for prop in root.findall("property"):
                        name = prop.find("name")
                        if name is not None and name.text == required:
                            found = True
                            break
                    if not found:
                        self.errors.append(f"缺少必需配置: {required}")
            
            return len(self.errors) == 0
            
        except ET.ParseError as e:
            self.errors.append(f"XML 解析错误: {e}")
            return False
    
    def validate_all(self) -> Tuple[List[str], List[str]]:
        """
        验证所有配置文件
        
        返回:
            (errors, warnings): 错误和警告列表
        """
        for filename in self.REQUIRED_CONFIGS.keys():
            self.validate_file(filename)
        
        return self.errors, self.warnings


if __name__ == "__main__":
    validator = ConfigValidator()
    errors, warnings = validator.validate_all()
    
    if errors:
        print("验证失败:")
        for error in errors:
            print(f"  [ERROR] {error}")
    else:
        print("验证通过")
    
    if warnings:
        print("警告:")
        for warning in warnings:
            print(f"  [WARN] {warning}")
