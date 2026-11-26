#!/usr/bin/env python3
# ============================================================
# 软件名称: HodoopForge 企业级Hadoop集群部署与管理平台软件
# 文件名称: api-client.py
# 文件功能: Ambari REST API 客户端
#   封装 Ambari REST API 调用，提供简洁的
#   Python 接口用于集群管理操作。
# 版    本: V1.0
# 编制日期: 2026年4月
# ============================================================

import requests
import json
from typing import Dict, List, Optional

class AmbariAPIClient:
    """Ambari REST API 客户端类"""
    
    def __init__(self, host: str = "localhost", port: int = 20609,
                 username: str = "admin", password: str = "admin"):
        """
        初始化 API 客户端
        
        参数:
            host: Ambari Server 主机名
            port: Ambari Server 端口
            username: 认证用户名
            password: 认证密码
        """
        self.base_url = f"http://{host}:{port}/api/v1"
        self.auth = (username, password)
        self.session = requests.Session()
        self.session.auth = self.auth
    
    def get(self, endpoint: str) -> Dict:
        """执行 GET 请求"""
        url = f"{self.base_url}/{endpoint}"
        response = self.session.get(url)
        response.raise_for_status()
        return response.json()
    
    def post(self, endpoint: str, data: Dict) -> Dict:
        """执行 POST 请求"""
        url = f"{self.base_url}/{endpoint}"
        headers = {"X-Requested-By": "ambari"}
        response = self.session.post(url, json=data, headers=headers)
        response.raise_for_status()
        return response.json()
    
    def put(self, endpoint: str, data: Dict) -> Dict:
        """执行 PUT 请求"""
        url = f"{self.base_url}/{endpoint}"
        headers = {"X-Requested-By": "ambari"}
        response = self.session.put(url, json=data, headers=headers)
        response.raise_for_status()
        return response.json()
    
    def get_clusters(self) -> List[Dict]:
        """获取所有集群列表"""
        return self.get("clusters").get("items", [])
    
    def get_cluster_info(self, cluster_name: str) -> Dict:
        """获取指定集群信息"""
        return self.get(f"clusters/{cluster_name}")
    
    def get_hosts(self, cluster_name: str) -> List[Dict]:
        """获取集群所有节点"""
        return self.get(f"clusters/{cluster_name}/hosts").get("items", [])
    
    def get_services(self, cluster_name: str) -> List[Dict]:
        """获取集群所有服务"""
        return self.get(f"clusters/{cluster_name}/services").get("items", [])
    
    def get_components(self, cluster_name: str) -> List[Dict]:
        """获取集群所有组件"""
        return self.get(f"clusters/{cluster_name}/components").get("items", [])
    
    def start_service(self, cluster_name: str, service_name: str) -> Dict:
        """启动指定服务"""
        data = {
            "RequestInfo": {"context": "启动服务"},
            "Body": {"ServiceInfo": {"state": "STARTED"}}
        }
        return self.put(f"clusters/{cluster_name}/services/{service_name}", data)
    
    def stop_service(self, cluster_name: str, service_name: str) -> Dict:
        """停止指定服务"""
        data = {
            "RequestInfo": {"context": "停止服务"},
            "Body": {"ServiceInfo": {"state": "INSTALLED"}}
        }
        return self.put(f"clusters/{cluster_name}/services/{service_name}", data)


if __name__ == "__main__":
    # 示例用法
    client = AmbariAPIClient()
    clusters = client.get_clusters()
    print(f"集群数量: {len(clusters)}")
    for cluster in clusters:
        print(f"  - {cluster['Clusters']['cluster_name']}")
