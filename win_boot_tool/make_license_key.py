#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成 Ed25519 授权签名密钥对（只需运行一次）。
私钥 -> license_signing_key.pem（务必保管+备份，绝不入库）
公钥 -> 打印出来贴进 boot_tool.py 的 _LICENSE_PUBKEY
"""
import os

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

here = os.path.dirname(os.path.abspath(__file__))
priv_path = os.path.join(here, "license_signing_key.pem")
if os.path.exists(priv_path):
    raise SystemExit(f"私钥已存在：{priv_path}（如需换钥先备份删除）")

priv = Ed25519PrivateKey.generate()
pem = priv.private_bytes(
    encoding=serialization.Encoding.PEM,
    format=serialization.PrivateFormat.PKCS8,
    encryption_algorithm=serialization.NoEncryption(),
)
with open(priv_path, "wb") as f:
    f.write(pem)

pub_hex = priv.public_key().public_bytes(
    serialization.Encoding.Raw, serialization.PublicFormat.Raw).hex()
print(f"私钥已写入：{priv_path}")
print(f"公钥（贴进 boot_tool.py 的 _LICENSE_PUBKEY）：")
print(pub_hex)
