#!/usr/bin/env python3
# ============================================================
# 软件名称: HodoopForge 企业级Hadoop集群部署与管理平台软件
# 文件名称: alert-manager.py
# 文件功能: 告警管理工具
#   监控 Ambari 告警信息，支持告警查询、
#   确认、通知等功能。
# 版    本: V1.0
# 编制日期: 2026年4月
# ============================================================

import requests
import json
from typing import List, Dict
from enum import Enum

class AlertState(Enum):
    """告警状态枚举"""
    OK = "OK"
    WARNING = "WARNING"
    CRITICAL = "CRITICAL"
    UNKNOWN = "UNKNOWN"

class AlertManager:
    """告警管理器"""
    
    def __init__(self, ambari_host: str = "localhost",
                 ambari_port: int = 20609,
                 username: str = "admin", password: str = "admin"):
        """
        初始化告警管理器
        
        参数:
            ambari_host: Ambari Server 主机
            ambari_port: Ambari Server 端口
            username: 认证用户名
            password: 认证密码
        """
        self.base_url = f"http://{ambari_host}:{ambari_port}/api/v1"
        self.auth = (username, password)
    
    def get_alerts(self, cluster_name: str, 
                   state: AlertState = None) -> List[Dict]:
        """
        获取告警列表
        
        参数:
            cluster_name: 集群名称
            state: 告警状态过滤（可选）
            
        返回:
            List[Dict]: 告警列表
        """
        url = f"{self.base_url}/clusters/{cluster_name}/alerts"
        response = requests.get(url, auth=self.auth)
        
        if response.status_code != 200:
            return []
        
        data = response.json()
        alerts = data.get("items", [])
        
        # 按状态过滤
        if state:
            alerts = [a for a in alerts if a.get("state") == state.value]
        
        return alerts
    
    def get_critical_alerts(self, cluster_name: str) -> List[Dict]:
        """获取严重告警"""
        return self.get_alerts(cluster_name, AlertState.CRITICAL)
    
    def get_warning_alerts(self, cluster_name: str) -> List[Dict]:
        """获取警告告警"""
        return self.get_alerts(cluster_name, AlertState.WARNING)
    
    def acknowledge_alert(self, cluster_name: str, alert_id: str) -> bool:
        """
        确认告警
        
        参数:
            cluster_name: 集群名称
            alert_id: 告警 ID
            
        返回:
            bool: 是否成功
        """
        url = f"{self.base_url}/clusters/{cluster_name}/alerts/{alert_id}"
        data = {"Alert": {"state": "OK"}}
        response = requests.put(url, json=data, auth=self.auth)
        return response.status_code == 200


if __name__ == "__main__":
    manager = AlertManager()
    
    # 获取严重告警
    critical_alerts = manager.get_critical_alerts("c1")
    print(f"严重告警数量: {len(critical_alerts)}")
    
    for alert in critical_alerts:
        print(f"  - {alert.get('label')}: {alert.get('definition')}")
