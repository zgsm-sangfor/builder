{
  "server": {
    "host": "0.0.0.0",
    "port": "8080",
    "mode": "debug"
  },
  "database": {
    "type": "sqlite"
  },
  "nacos": {
    "enabled": false,
    "port": 8848,
    "namespace": "public",
    "group": "DEFAULT_GROUP",
    "username": "",
    "password": "",
    "data_id": "costrict-admin-config"
  },
  "casdoor": {
    "enabled": true,
    "client_id": "{{CASDOOR_BUILTIN_CLIENTID}}",
    "client_secret": "{{CASDOOR_BUILTIN_CLIENTSECRET}}",
    "application_id": "app-built-in",
    "organization": "built-in",
    "login_app": "loginApp"
  },
  "higress": {
    "enabled": false,
    "environment": "production"
  },
  "monitor": {
    "enabled": true,
    "check_interval": 60
  },
  "oneapi": {
    "enabled": true,
    "username": "root",
    "password": "r!65Gq7@4acYsB"
  },
  "es": {
    "enabled": true,
    "addresses": "",
    "username": "elastic",
    "password": "{{PASSWORD_ELASTIC}}",
    "index_name": "costrict_metrics",
    "ca_path": "",
    "max_retries": 3
  },
  "upgrade": {
    "verify_tls": false
  }
}
