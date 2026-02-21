# PD-Element


⚙️ Installation

```
bash <(curl -Ls https://raw.githubusercontent.com/Mehdi682007/PD-Element/main/install.sh)

```
🧩 Project Overview

Matrix Stack Manager is a professional all-in-one installer and management toolkit for deploying a private chat server based on:

Matrix Synapse (Homeserver)

Element Web (Client)

coturn (STUN/TURN server)

Nginx + Let's Encrypt SSL

It allows you to run your own secure chat infrastructure similar to Telegram or WhatsApp — fully self-hosted.

✨ Features
🛠 Automated Installation

Full Matrix + Element + TURN deployment

Automatic SSL via Let's Encrypt

Automatic Nginx & .well-known configuration

ARM & x86 compatible

👥 User Management

Create admin users

Create normal users

Create users with auto-generated passwords

Deactivate users safely

Reactivate existing users

List all users

📦 Upload Management

Set upload limits for:

Nginx (client_max_body_size)

Synapse (max_upload_size)

🧾 Registration Control

Toggle public registration ON/OFF

Prevent spam after initial setup

🔎 Advanced Utilities

Full Health Check

Fix Wizard (common issue repair)

Full Backup system

Restore from backup

Element Web update manager

Full uninstall / purge mode

📦 Requirements

Ubuntu 20.04 / 22.04 / 24.04

Root access

Domain pointing to your server IP

Open ports:

80

443

3478 (TURN)

49160-49200 (UDP relay)

🔐 Security

Public registration control

TURN shared-secret authentication

Forced HTTPS

No exposed HTTP API

📈 Roadmap

Sliding Sync support (Element X optimized)

Worker mode for scaling

Advanced monitoring

Advanced rate limiting

📺 Community

Telegram:
👉 https://t.me/MYoutub

YouTube:
👉 https://www.youtube.com/@ParsDigital
