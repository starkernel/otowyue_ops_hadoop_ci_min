#!/bin/bash
#
# HodoopForge - 专为现代Hadoop集群量身打造的一站式部署与管理平台
# Forge Stability. Connect the Future.
#
# This script is part of the HodoopForge project.
# Project: HodoopForge - Ambari 3.x + Bigtop 3.5.0 Integration Platform
#
cat > /var/repo/ambari/bigtop-3.5.0-vdf.xml << 'EOF'
<?xml version="1.0"?>
<repository-version xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:noNamespaceSchemaLocation="version_definition.xsd">
  <release>
    <type>STANDARD</type>
    <stack-id>BIGTOP-3.5.0</stack-id>
    <version>3.5.0.0</version>
    <build>1</build>
    <compatible-with>3.5.*</compatible-with>
    <release-notes>http://bigtop.apache.org</release-notes>
    <display>Bigtop-3.5.0.0-1</display>
  </release>
  <manifest>
    <service id="HDFS-350"       name="HDFS"       version="3.3.6"  versionId="HDFS-3.3.6"/>
    <service id="YARN-350"       name="YARN"       version="3.3.6"  versionId="YARN-3.3.6"/>
    <service id="MAPREDUCE2-350" name="MAPREDUCE2" version="3.3.6"  versionId="MAPREDUCE2-3.3.6"/>
    <service id="HIVE-350"       name="HIVE"       version="4.0.1"  versionId="HIVE-4.0.1"/>
    <service id="HBASE-350"      name="HBASE"      version="2.6.2"  versionId="HBASE-2.6.2"/>
    <service id="ZOOKEEPER-350"  name="ZOOKEEPER"  version="3.8.4"  versionId="ZOOKEEPER-3.8.4"/>
    <service id="KAFKA-350"      name="KAFKA"      version="3.4.1"  versionId="KAFKA-3.4.1"/>
    <service id="SPARK-350"      name="SPARK"      version="3.5.6"  versionId="SPARK-3.5.6"/>
    <service id="RANGER-350"     name="RANGER"     version="2.7.0"  versionId="RANGER-2.7.0"/>
    <service id="RANGER_KMS-350" name="RANGER_KMS" version="2.7.0"  versionId="RANGER_KMS-2.7.0"/>
    <service id="TEZ-350"        name="TEZ"        version="0.10.4" versionId="TEZ-0.10.4"/>
    <service id="FLINK-350"      name="FLINK"      version="1.20.1" versionId="FLINK-1.20.1"/>
    <service id="SOLR-350"       name="SOLR"       version="8.11.4" versionId="SOLR-8.11.4"/>
    <service id="ZEPPELIN-350"   name="ZEPPELIN"   version="0.11.2" versionId="ZEPPELIN-0.11.2"/>
    <service id="LIVY-350"       name="LIVY"       version="0.8.0"  versionId="LIVY-0.8.0"/>
  </manifest>
  <available-services>
    <service idref="HDFS-350"/>
    <service idref="YARN-350"/>
    <service idref="MAPREDUCE2-350"/>
    <service idref="HIVE-350"/>
    <service idref="HBASE-350"/>
    <service idref="ZOOKEEPER-350"/>
    <service idref="KAFKA-350"/>
    <service idref="SPARK-350"/>
    <service idref="RANGER-350"/>
    <service idref="RANGER_KMS-350"/>
    <service idref="TEZ-350"/>
    <service idref="FLINK-350"/>
    <service idref="SOLR-350"/>
    <service idref="ZEPPELIN-350"/>
    <service idref="LIVY-350"/>
  </available-services>
  <repository-info>
    <os family="redhat8">
      <repo>
        <baseurl>http://bigtop_hostname0</baseurl>
        <repoid>BIGTOP-3.5.0</repoid>
        <reponame>Bigtop 3.5.0</reponame>
        <unique>true</unique>
      </repo>
    </os>
  </repository-info>
</repository-version>
EOF
echo "==> VDF file created at /var/repo/ambari/bigtop-3.5.0-vdf.xml"
ls -la /var/repo/ambari/bigtop-3.5.0-vdf.xml
