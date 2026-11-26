#!/usr/bin/env python3
# ============================================================
# 软件名称: HodoopForge 企业级Hadoop集群部署与管理平台软件
# 文件名称: service-checker.py
# 文件功能: 服务检查工具
#   检查集群各服务的健康状态，
#   包括进程状态、端口监听、功能测试等。
# 版    本: V1.0
# 编制日期: 2026年4月
# ============================================================

import subprocess
import socket
from typing import Dict, List

class ServiceChecker:
    """服务检查器"""
    
    def __init__(self):
        """初始化服务检查器"""
        self.checks = {}
    
    def check_port(self, host: str, port: int) -> bool:
        """
        检查端口是否监听
        
        参数:
            host: 主机地址
            port: 端口号
            
        返回:
            bool: 端口是否监听
        """
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(5)
            result = sock.connect_ex((host, port))
            sock.close()
            return result == 0
        except:
            return False
    
    def check_process(self, process_name: str) -> bool:
        """
        检查进程是否运行
        
        参数:
            process_name: 进程名称
            
        返回:
            bool: 进程是否运行
        """
        try:
            cmd = f"pgrep -f {process_name}"
            result = subprocess.run(cmd, shell=True, capture_output=True)
            return result.returncode == 0
        except:
            return False
    
    def check_hdfs_namenode(self) -> Dict:
        """检查 HDFS NameNode"""
        return {
            "service": "hdfs_namenode",
            "process": self.check_process("namenode"),
            "port": self.check_port("localhost", 8020),
            "web": self.check_port("localhost", 9870)
        }
    
    def check_yarn_resourcemanager(self) -> Dict:
        """检查 YARN ResourceManager"""
        return {
            "service": "yarn_resourcemanager",
            "process": self.check_process("resourcemanager"),
            "port": self.check_port("localhost", 8032),
            "web": self.check_port("localhost", 8088)
        }
    
    def check_hive_server2(self) -> Dict:
        """检查 Hive Server2"""
        return {
            "service": "hive_server2",
            "process": self.check_process("hiveserver2"),
            "port": self.check_port("localhost", 10000)
        }
    
    def check_hdfs_datanode(self) -> Dict:
        """检查 HDFS DataNode"""
        return {
            "service": "hdfs_datanode",
            "process": self.check_process("datanode"),
            "port": self.check_port("localhost", 9866)
        }
    
    def check_all_services(self) -> Dict:
        """
        检查所有服务
        
        返回:
            Dict: 所有服务检查结果
        """
        self.checks["hdfs_namenode"] = self.check_hdfs_namenode()
        self.checks["yarn_resourcemanager"] = self.check_yarn_resourcemanager()
        self.checks["hive_server2"] = self.check_hive_server2()
        self.checks["hdfs_datanode"] = self.check_hdfs_datanode()
        
        return self.checks
    
    def print_report(self):
        """打印检查报告"""
        print("服务健康检查报告")
        print("=" * 50)
        
        for service, check in self.checks.items():
            status = "OK" if all(check.values()) else "FAIL"
            print(f"{service}: {status}")
            for key, value in check.items():
                print(f"  {key}: {value}")


if __name__ == "__main__":
    checker = ServiceChecker()
    checker.check_all_services()
    checker.print_report()
