import os

INSPECTION_HOME = "/opt/inspection"

MONGO_CONFIG = {
    "host": "localhost",
    "port": 27017,
    "db": "inspection",
}

LDAP_CONFIG = {
    "server": "ldap://your-ad-server.company.com",
    "base_dn": "dc=company,dc=com",
    "bind_user": "CN=svc_ldap,OU=Service,DC=company,DC=com",
    "bind_password": "",
    "cache_ttl": 3600,
}

SETTINGS_FILE = os.path.join(INSPECTION_HOME, "data/settings.json")
REPORTS_DIR = os.path.join(INSPECTION_HOME, "data/reports")
HOSTS_CONFIG = os.path.join(INSPECTION_HOME, "data/hosts_config.json")
SNAPSHOTS_DIR = os.path.join(INSPECTION_HOME, "data/snapshots")

FLASK_HOST = "0.0.0.0"
FLASK_PORT = 5000
FLASK_DEBUG = False

SECRET_KEY = "REPLACE_ME_WITH_secrets_token_hex_32"
BACKUP_DIR = "/var/backups/inspection"
LOG_DIR = os.path.join(INSPECTION_HOME, "logs")
