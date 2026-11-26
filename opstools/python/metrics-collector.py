#!/usr/bin/env python3
# ============================================================
# 软件名称: HodoopForge 企业级Hadoop集群部署与管理平台软件
# 文件名称: metrics-collector.py
# 文件功能: 集群指标收集工具
#   从 Ambari 收集集群性能指标，
#   包括 CPU、内存、磁盘、网络等。
# 版    本: V1.0
# 编制日期: 2026年4月
# ============================================================

import requests
import json
import time
from typing import Dict, List
from datetime import datetime

class MetricsCollector:
    """集群指标收集器"""
    
    def __init__(self, ambari_host: str = "localhost", 
                 ambari_port: int = 20609,
                 username: str = "admin", password: str = "admin"):
        """
        初始化指标收集器
        
        参数:
            ambari_host: Ambari Server 主机
            ambari_port: Ambari Server 端口
            username: 认证用户名
            password: 认证密码
        """
        self.base_url = f"http://{ambari_host}:{ambari_port}/api/v1"
        self.auth = (username, password)
    
    def collect_host_metrics(self, cluster_name: str, host_name: str) -> Dict:
        """
        收集指定节点的指标
        
        参数:
            cluster_name: 集群名称
            host_name: 节点名称
            
        返回:
            Dict: 节点指标数据
        """
        url = f"{self.base_url}/clusters/{cluster_name}/hosts/{host_name}/host_components"
        response = requests.get(url, auth=self.auth)
        
        if response.status_code != 200:
            return {}
        
        data = response.json()
        metrics = {
            "host": host_name,
            "timestamp": datetime.now().isoformat(),
            "components": []
        }
        
        for item in data.get("items", []):
            comp_name = item["HostRoles"]["component_name"]
            comp_state = item["HostRoles"]["state"]
            metrics["components"].append({
                "name": comp_name,
                "state": comp_state
            })
        
        return metrics
    
    def collect_cluster_metrics(self, cluster_name: str) -> Dict:
        """
        收集集群整体指标
        
        参数:
            cluster_name: 集群名称
            
        返回:
            Dict: 集群指标数据
        """
        # 获取所有节点
        hosts_url = f"{self.base_url}/clusters/{cluster_name}/hosts"
        hosts_response = requests.get(hosts_url, auth=self.auth)
        hosts_data = hosts_response.json()
        
        metrics = {
            "cluster": cluster_name,
            "timestamp": datetime.now().isoformat(),
            "hosts": []
        }
        
        for host_item in hosts_data.get("items", []):
            host_name = host_item["Hosts"]["host_name"]
            host_metrics = self.collect_host_metrics(cluster_name, host_name)
            metrics["hosts"].append(host_metrics)
        
        return metrics
    
    def save_metrics(self, metrics: Dict, output_file: str):
        """
        保存指标到文件
        
        参数:
            metrics: 指标数据
            output_file: 输出文件路径
        """
        with open(output_file, "w") as f:
            json.dump(metrics, f, indent=2)


if __name__ == "__main__":
    collector = MetricsCollector()
    metrics = collector.collect_cluster_metrics("c1")
    collector.save_metrics(metrics, "/tmp/cluster-metrics.json")
    print(f"指标已保存到: /tmp/cluster-metrics.json")
