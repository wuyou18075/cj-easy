import os
import re
import sys
import time
import json
import sqlite3
import datetime
import requests
import subprocess
from threading import Thread
from Crypto.PublicKey import RSA
from Crypto.Signature import pkcs1_15
from Crypto.Hash import SHA256
import base64

# ==================== 容器/脚本 环境变量 ====================
ROLE = os.getenv("ROLE", "SLAVE")
BOT_TOKEN = os.getenv("BOT_TOKEN", "")
ADMIN_ID = os.getenv("GROUP_ID", "")  # 这里直接传入你个人的 TG 用户 ID（数字）
VPS_NAME = os.getenv("VPS_NAME", "")
MY_PORT = int(os.getenv("PORT", "9000"))
MY_DOMAIN = os.getenv("DOMAIN", "")
MASTER_URL = os.getenv("MASTER_URL", "")
NODE_PATH = os.getenv("NODE_PATH", "/root/node.txt")

DATA_DIR = "/app/data" if os.path.exists("/app") else "./data"
os.makedirs(DATA_DIR, exist_ok=True)
DB_PATH = os.path.join(DATA_DIR, "cluster.db")
PRI_KEY_PATH = os.path.join(DATA_DIR, "private_key.pem")
PUB_KEY_PATH = os.path.join(DATA_DIR, "public_key.pem")

# ==================== SQLite 数据库服务 ====================
def init_db():
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    # 节点表
    c.execute('''CREATE TABLE IF NOT EXISTS nodes (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    name TEXT UNIQUE, alias TEXT UNIQUE,
                    ip TEXT, domain TEXT, port INTEGER,
                    status TEXT DEFAULT 'online', last_seen TEXT
                 )''')
    # 白名单用户表
    c.execute('''CREATE TABLE IF NOT EXISTS whitelist (
                    user_id TEXT PRIMARY KEY,
                    username TEXT,
                    added_time TEXT
                 )''')
    
    # 默认将主管理员加入白名单
    if ADMIN_ID:
        now_str = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        c.execute("INSERT OR IGNORE INTO whitelist (user_id, username, added_time) VALUES (?, ?, ?)", 
                  (str(ADMIN_ID), "Main_Admin", now_str))
        
    conn.commit()
    conn.close()

def get_external_ip():
    try:
        return requests.get("https://ipv4.icanhazip.com", timeout=5).text.strip()
    except:
        return "127.0.0.1"

def generate_signature(timestamp):
    try:
        with open(PRI_KEY_PATH, "r") as f: private_key = RSA.import_key(f.read())
        h = SHA256.new(timestamp.encode('utf-8'))
        return base64.b64encode(pkcs1_15.new(private_key).sign(h)).decode('utf-8')
    except: return ""

def verify_signature(timestamp, signature_b64):
    try:
        if abs(time.time() - float(timestamp)) > 30: return False
        with open(PUB_KEY_PATH, "r") as f: pub_key = RSA.import_key(f.read())
        h = SHA256.new(timestamp.encode('utf-8'))
        pkcs1_15.new(pub_key).verify(h, base64.b64decode(signature_b64))
        return True
    except: return False

# ==================== FLASK API (接收从端报到) ====================
from flask import Flask, request, jsonify
app = Flask(__name__)

@app.route("/register_api", methods=["POST"])
def register_api():
    if ROLE != "MASTER": return jsonify({"error": "Forbidden"}), 403
    data = request.get_json()
    if not data or not verify_signature(data["timestamp"], data["signature"]): return jsonify({"error": "Unauthorized"}), 401
    
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    now_str = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    
    c.execute("SELECT id FROM nodes WHERE ip = ?", (data["ip"],))
    row = c.fetchone()
    if row:
        c.execute("UPDATE nodes SET status='online', last_seen=? WHERE id=?", (now_str, row[0]))
    else:
        c.execute("INSERT INTO nodes (name, ip, domain, port, last_seen) VALUES (?, ?, ?, ?, ?)", 
                  (data["name"], data["ip"], data["domain"], data["port"], now_str))
    conn.commit()
    conn.close()
    
    # 消息推送给主管理员
    if BOT_TOKEN and ADMIN_ID:
        tg_text = f"📢 *[节点自动上线]*\n● 节点名称: `{data['name']}`\n● 节点状态: 验证通过，已成功加入集群控制。"
        requests.post(f"https://api.telegram.org/bot{BOT_TOKEN}/sendMessage", data={"chat_id": ADMIN_ID, "text": tg_text, "parse_mode": "Markdown"})
    return jsonify({"status": "success"})

# ==================== MASTER TG BOT 核心控制 ====================
def run_telegram_bot():
    from telegram import Update
    from telegram.ext import Application, CommandHandler, MessageHandler, filters, ContextTypes

    # 鉴权：只有白名单内的人允许执行命令
    def is_authorized(user_id):
        conn = sqlite3.connect(DB_PATH)
        c = conn.cursor()
        c.execute("SELECT 1 FROM whitelist WHERE user_id = ?", (str(user_id),))
        res = c.fetchone()
        conn.close()
        return res is not None

    # 鉴权：是否为主管理员
    def is_main_admin(user_id):
        return str(user_id) == str(ADMIN_ID)

    async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
        u_id = update.effective_user.id
        if not is_authorized(u_id): 
            await update.message.reply_text("❌ 您不在系统白名单中，无权操作。")
            return
        
        welcome = (
            "🛡️ *专属 VPS 安全云控面板* 🛡️\n\n"
            "👤 *白名单管理命令 (仅主管理员可用)*:\n"
            "├ `/add [用户ID]` \\- 授权一个新用户进入白名单\n"
            "└ `/kick [用户ID]` \\- 将该用户踢出白名单并取消授权\n\n"
            "📊 *状态查询命令*:\n"
            "├ `/status` \\- 查看锁定的服务器硬件快照\n"
            "└ `/net` \\- 链路网络测速"
        )
        await update.message.reply_text(welcome, parse_mode="MarkdownV2")

    # 【新增命令：授权加入白名单】
    async def add_user(update: Update, context: ContextTypes.DEFAULT_TYPE):
        u_id = update.effective_user.id
        if not is_main_admin(u_id):
            await update.message.reply_text("❌ 只有主管理员有权限授权新用户。")
            return
        if not context.args:
            await update.message.reply_text("💡 使用方法：`/add 123456789` (填入目标用户的 TG 数字 ID)")
            return
        
        target_id = context.args[0]
        if not target_id.isdigit():
            await update.message.reply_text("❌ 格式错误，TG 用户 ID 必须是纯数字。")
            return

        conn = sqlite3.connect(DB_PATH)
        c = conn.cursor()
        now_str = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        try:
            c.execute("INSERT OR IGNORE INTO whitelist (user_id, username, added_time) VALUES (?, ?, ?)", (target_id, f"User_{target_id}", now_str))
            conn.commit()
            await update.message.reply_text(f"✅ 授权成功！用户 `{target_id}` 已成功加入白名单。")
        except Exception as e:
            await update.message.reply_text(f"❌ 数据库写入失败: {e}")
        finally:
            conn.close()

    # 【新增命令：踢出白名单】
    async def kick_user(update: Update, context: ContextTypes.DEFAULT_TYPE):
        u_id = update.effective_user.id
        if not is_main_admin(u_id):
            await update.message.reply_text("❌ 只有主管理员有权限移除用户。")
            return
        if not context.args:
            await update.message.reply_text("💡 使用方法：`/kick 123456789` (填入要踢出的用户 TG 数字 ID)")
            return
        
        target_id = context.args[0]
        if str(target_id) == str(ADMIN_ID):
            await update.message.reply_text("❌ 无法移除你自己（主管理员）。")
            return

        conn = sqlite3.connect(DB_PATH)
        c = conn.cursor()
        c.execute("DELETE FROM whitelist WHERE user_id = ?", (target_id,))
        conn.commit()
        conn.close()
        await update.message.reply_text(f"🚫 踢出成功！已取消用户 `{target_id}` 的所有操作授权。")

    # 其余查询命令精简保留...
    async def status_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
        if not is_authorized(update.effective_user.id): return
        await update.message.reply_text("🖥️ *硬件快照服务正常启动，正在调取数据...*")

    app = Application.builder().token(BOT_TOKEN).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("add", add_user))
    app.add_handler(CommandHandler("kick", kick_user))
    app.add_handler(CommandHandler("status", status_command))
    
    print("🤖 Master Bot 线程成功拉起...")
    app.run_polling()

if __name__ == "__main__":
    init_db()
    flask_thread = Thread(target=lambda: app.run(host="0.0.0.0", port=MY_PORT, use_reloader=False))
    flask_thread.daemon = True
    flask_thread.start()

    if ROLE == "MASTER": run_telegram_bot()
    else:
        while True: time.sleep(3600)
