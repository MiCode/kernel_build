#!/usr/bin/env python
# -*- coding: utf-8 -*-
import os
import sys
import binascii
import xml.etree.cElementTree as ET
from xml.etree import ElementTree
from xml.dom import minidom
import hashlib
import types
from os.path import join, getsize
import socket
import platform
import uuid
import datetime

def md5Files(filename, blocksize=65536):
    h = hashlib.md5()
    with open(filename, "rb") as f:
        for block in iter(lambda: f.read(blocksize), b""):
            h.update(block)
    return h.hexdigest()

def md5Str(string):
    s = hashlib.md5()
    s.update(string)
    return s.hexdigest()

def md5XmlElement(element):
    element_str = prettyXml(element)
    element_str_split = element_str.split('\n', 1 )
    return md5Str(element_str_split[1])

def prettyXml(xml_string):
    tree_to_string = ElementTree.tostring(xml_string, 'utf-8')
    parsed_string = minidom.parseString(tree_to_string)
    return parsed_string.toprettyxml(indent="", encoding="GB2312")

def xmlForwin(xml_string):
    return xml_string.replace("\n","\r\n")

def getLocalIP():
    """
    Returns the actual ip of the local machine.
    This code figures out what source address would be used if some traffic
    were to be sent out to some well known address on the Internet. In this
    case, a Google DNS server is used, but the specific address does not
    matter much. No traffic is actually sent.
    """
    try:
        csock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        csock.connect(('8.8.8.8', 80))
        (addr, port) = csock.getsockname()
        csock.close()
        return addr
    except socket.error:
        return "127.0.0.1"

def getLocalMAC(): 
    mac=uuid.UUID(int = uuid.getnode()).hex[-12:] 
    return "-".join([mac[e:e+2] for e in range(0,11,2)])

def getMd5Xml(files_path):
    files = []
    for f in os.listdir(files_path):
        if os.path.isfile(os.path.join(files_path, f)):
            file = os.path.join(files_path, f)
            files.append(file)

    xml = os.path.join(files_path, "MD5_DATA.xml")
    check_root = ET.Element("CHECK_ROOT")
    data = ET.SubElement(check_root, "DATA")
    data_md5 = ET.SubElement(check_root, "DATA_MD5")
    md5_data_info = ET.SubElement(data, "MD5_DATA_INFO")
    executor_info = ET.SubElement(data, "EXECUTOR_INFO")
    info_item_user = ET.SubElement(executor_info, "INFO_ITEM", NAME="User")
    info_item_ip = ET.SubElement(executor_info, "INFO_ITEM", NAME="IP")
    info_item_pc = ET.SubElement(executor_info, "INFO_ITEM", NAME="PC")
    info_item_mac = ET.SubElement(executor_info, "INFO_ITEM", NAME="MAC")
    info_item_date_time = ET.SubElement(executor_info, "INFO_ITEM", NAME="DATE_TIME")
    info_item_user.text = user
    info_item_ip.text = local_ip
    info_item_pc.text = pc
    info_item_mac.text = local_mac
    info_item_date_time.text = date

    for file in files:
        file_item = ET.SubElement(md5_data_info, "FILE_ITEM", NAME=".\\"+os.path.basename(file))
        md5 = ET.SubElement(file_item, "MD5")
        size = ET.SubElement(file_item, "SIZE")
        md5.text = md5Files(file)
        size.text = str(os.path.getsize(file))

    data_md5.text = md5XmlElement(data)
    xml_str = prettyXml(check_root)
    with open(xml,"w") as f:
        f.write(xml_str)


#-----------------------------------------------------------------
if __name__ == "__main__":
    date = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    local_ip = getLocalIP()
    local_mac = getLocalMAC()
    user = platform.uname()[1]
    pc = platform.uname()[0]
    files_path = sys.argv[1]

    getMd5Xml(files_path)