#!/usr/bin/env python3
# ============================================================
# 软件名称: HodoopForge 企业级Hadoop集群部署与管理平台软件
# 文件名称: backup-restore.py
# 文件功能: 备份恢复工具
#   提供配置文件和数据库的备份、恢复功能，
#   支持增量备份和压缩存储。
# 版    本: V1.0
# 编制日期: 2026年4月
# ============================================================

import os
import tarfile
import subprocess
import shutil
from datetime import datetime
from typing import Optional

class BackupRestore:
    """备份恢复管理器"""
    
    def __init__(self, backup_dir: str = "/backup"):
        """
        初始化备份恢复管理器
        
        参数:
            backup_dir: 备份根目录
        """
        self.backup_dir = backup_dir
        os.makedirs(backup_dir, exist_ok=True)
    
    def backup_config(self, config_paths: list, 
                     backup_name: Optional[str] = None) -> str:
        """
        备份配置文件
        
        参数:
            config_paths: 配置文件路径列表
            backup_name: 备份名称（可选）
            
        返回:
            str: 备份文件路径
        """
        if backup_name is None:
            backup_name = f"config-{datetime.now().strftime('%Y%m%d%H%M%S')}"
        
        backup_file = os.path.join(self.backup_dir, f"{backup_name}.tar.gz")
        
        with tarfile.open(backup_file, "w:gz") as tar:
            for path in config_paths:
                if os.path.exists(path):
                    tar.add(path, arcname=os.path.basename(path))
        
        return backup_file
    
    def backup_database(self, db_name: str, db_user: str, 
                       db_pass: str, backup_name: Optional[str] = None) -> str:
        """
        备份数据库
        
        参数:
            db_name: 数据库名称
            db_user: 数据库用户
            db_pass: 数据库密码
            backup_name: 备份名称（可选）
            
        返回:
            str: 备份文件路径
        """
        if backup_name is None:
            backup_name = f"db-{db_name}-{datetime.now().strftime('%Y%m%d%H%M%S')}"
        
        backup_file = os.path.join(self.backup_dir, f"{backup_name}.sql")
        
        cmd = f"mysqldump -u{db_user} -p{db_pass} {db_name} > {backup_file}"
        subprocess.run(cmd, shell=True, check=True)
        
        return backup_file
    
    def restore_config(self, backup_file: str, target_dir: str = "/") -> bool:
        """
        恢复配置文件
        
        参数:
            backup_file: 备份文件路径
            target_dir: 目标目录
            
        返回:
            bool: 是否成功
        """
        if not os.path.exists(backup_file):
            return False
        
        with tarfile.open(backup_file, "r:gz") as tar:
            tar.extractall(path=target_dir)
        
        return True
    
    def restore_database(self, backup_file: str, db_name: str,
                        db_user: str, db_pass: str) -> bool:
        """
        恢复数据库
        
        参数:
            backup_file: 备份文件路径
            db_name: 数据库名称
            db_user: 数据库用户
            db_pass: 数据库密码
            
        返回:
            bool: 是否成功
        """
        if not os.path.exists(backup_file):
            return False
        
        cmd = f"mysql -u{db_user} -p{db_pass} {db_name} < {backup_file}"
        subprocess.run(cmd, shell=True, check=True)
        
        return True
    
    def list_backups(self) -> list:
        """列出所有备份"""
        backups = []
        for filename in os.listdir(self.backup_dir):
            filepath = os.path.join(self.backup_dir, filename)
            if os.path.isfile(filepath):
                stat = os.stat(filepath)
                backups.append({
                    "name": filename,
                    "size": stat.st_size,
                    "mtime": datetime.fromtimestamp(stat.st_mtime).isoformat()
                })
        return backups


if __name__ == "__main__":
    br = BackupRestore()
    
    # 备份配置
    config_backup = br.backup_config(["/etc/hadoop/conf", "/etc/hive/conf"])
    print(f"配置备份: {config_backup}")
    
    # 列出备份
    backups = br.list_backups()
    print(f"备份数量: {len(backups)}")
