# PD-Element


## 🧩 Overview

**Matrix Stack Manager** is a professional all-in-one installer and management toolkit for:

- Matrix Synapse
- Element Web
- TURN Server (coturn)
- Nginx + Let's Encrypt SSL

Deploy your own Telegram/WhatsApp-like chat server in minutes — fully self-hosted.

---

## ✨ Key Features

### 🔧 Full Automated Installation
- Synapse setup
- PostgreSQL or SQLite support
- Nginx configuration
- Automatic SSL issuance
- Element Web installation
- .well-known configuration
- TURN server for voice/video calls

---

### 👥 User Management
- Create admin users
- Create normal users
- Create users with random passwords
- Reactivate users
- List users
- Deactivate users safely

---

### 📦 Upload Control
- Modify:
  - Nginx `client_max_body_size`
  - Synapse `max_upload_size`

---

### 🧾 Registration Control
- Enable / Disable public registration
- Prevent spam after onboarding users

---

### 🔎 Health Check
- Service status
- Matrix API validation
- .well-known validation
- Port checks
- SSL certificate info

---

### 🧰 Fix Wizard
Automatically fixes common issues:
- Missing Nginx symlinks
- Disabled coturn
- Broken Nginx config
- Service restarts

---

### 💾 Backup & Restore
Full backup including:
- Database
- Synapse configs
- Nginx configs
- TURN configs
- SSL certificates (optional)

---

### ⬆️ Element Updater
- Update to specific version
- Fetch latest from GitHub API
- Preserve config.json

---

### 🧨 Full Purge
Completely remove the entire stack safely.

---

## 🗄️ Database Support

- SQLite (simple mode)
- PostgreSQL (recommended for production)

---

## 📱 Compatible With

- Element Web
- Element Mobile
- Element X
- Any Matrix-compatible client

---

## ⚙️ Requirements

- Ubuntu 20.04 / 22.04
- Root access
- Domain pointing to server IP
- Open ports 80 & 443

---

## 🚀 Quick Install

```
bash <(curl -Ls https://raw.githubusercontent.com/Mehdi682007/PD-Element/main/install.sh)
```

---

## 📌 Current Version

**v1.4**

---

## 📄 License

MIT License

---

⭐ If this project helps you, consider starring the repository!
