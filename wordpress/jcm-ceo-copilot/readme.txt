JCM CEO Copilot — WordPress Plugin
==================================

Install (admin only):
1. Zip the `jcm-ceo-copilot` folder.
2. WordPress Admin → Plugins → Add New → Upload Plugin → Activate.
3. Open **CEO Copilot** in the left admin menu.

Access:
- Only users with Administrator role (`manage_options`) see the menu.
- The dashboard loads from your VPS Mission Control URL.
- When prompted in the iframe, sign in with your Mission Control credentials (not your WordPress password).

Security:
- Rotate WordPress password if it was shared in chat.
- Set MISSION_CONTROL_USER and MISSION_CONTROL_PASSWORD on the VPS `.env` file.
