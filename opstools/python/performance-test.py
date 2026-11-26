#!/usr/bin/env python3
# ============================================================
# 软件名称: HodoopForge 企业级Hadoop集群部署与管理平台软件
# 文件名称: performance-test.py
# 文件功能: 性能测试工具
#   执行集群性能基准测试，
#   包括 HDFS 读写、YARN 作业、SQL 查询等。
# 版    本: V1.0
# 编制日期: 2026年4月
# ============================================================

import subprocess
import time
import json
from typing import Dict, List
from datetime import datetime

class PerformanceTester:
    """性能测试器"""
    
    def __init__(self):
        """初始化性能测试器"""
        self.results = {}
    
    def test_hdfs_write(self, file_size_mb: int = 1024) -> Dict:
        """
        测试 HDFS 写性能
        
        参数:
            file_size_mb: 测试文件大小（MB）
            
        返回:
            Dict: 测试结果
        """
        start_time = time.time()
        
        # 使用 hadoop jar 运行 TestDFSIO 写测试
        cmd = f"hadoop jar hadoop-mapreduce-client-jobclient.jar TestDFSIO -write -nrFiles 10 -fileSize {file_size_mb}"
        subprocess.run(cmd, shell=True, check=True)
        
        end_time = time.time()
        duration = end_time - start_time
        
        result = {
            "test": "hdfs_write",
            "file_size_mb": file_size_mb,
            "duration_seconds": duration,
            "throughput_mb_s": file_size_mb / duration
        }
        
        self.results["hdfs_write"] = result
        return result
    
    def test_hdfs_read(self, file_size_mb: int = 1024) -> Dict:
        """
        测试 HDFS 读性能
        
        参数:
            file_size_mb: 测试文件大小（MB）
            
        返回:
            Dict: 测试结果
        """
        start_time = time.time()
        
        # 使用 hadoop jar 运行 TestDFSIO 读测试
        cmd = f"hadoop jar hadoop-mapreduce-client-jobclient.jar TestDFSIO -read -nrFiles 10 -fileSize {file_size_mb}"
        subprocess.run(cmd, shell=True, check=True)
        
        end_time = time.time()
        duration = end_time - start_time
        
        result = {
            "test": "hdfs_read",
            "file_size_mb": file_size_mb,
            "duration_seconds": duration,
            "throughput_mb_s": file_size_mb / duration
        }
        
        self.results["hdfs_read"] = result
        return result
    
    def test_hive_query(self, query: str) -> Dict:
        """
        测试 Hive 查询性能
        
        参数:
            query: SQL 查询语句
            
        返回:
            Dict: 测试结果
        """
        start_time = time.time()
        
        # 使用 beeline 执行查询
        cmd = f"beeline -u jdbc:hive2://localhost:10000 -e \"{query}\""
        subprocess.run(cmd, shell=True, check=True)
        
        end_time = time.time()
        duration = end_time - start_time
        
        result = {
            "test": "hive_query",
            "query": query,
            "duration_seconds": duration
        }
        
        self.results["hive_query"] = result
        return result
    
    def run_all_tests(self) -> Dict:
        """
        运行所有性能测试
        
        返回:
            Dict: 所有测试结果
        """
        print("开始性能测试...")
        
        # HDFS 写测试
        print("执行 HDFS 写测试...")
        self.test_hdfs_write(1024)
        
        # HDFS 读测试
        print("执行 HDFS 读测试...")
        self.test_hdfs_read(1024)
        
        # Hive 查询测试
        print("执行 Hive 查询测试...")
        self.test_hive_query("SELECT COUNT(*) FROM test_table")
        
        self.results["timestamp"] = datetime.now().isoformat()
        return self.results
    
    def save_results(self, output_file: str):
        """
        保存测试结果
        
        参数:
            output_file: 输出文件路径
        """
        with open(output_file, "w") as f:
            json.dump(self.results, f, indent=2)


if __name__ == "__main__":
    tester = PerformanceTester()
    results = tester.run_all_tests()
    tester.save_results("/tmp/performance-test-results.json")
    print(f"测试结果已保存到: /tmp/performance-test-results.json")
