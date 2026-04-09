{
  "organizations": [
    {
      "owner": "admin",
      "name": "built-in",
      "displayName": "manager",
      "logo": "https://costrict.ai/favicon.png",
      "passwordType": "plain",
      "passwordOptions": ["AtLeast6"],
      "countryCodes": ["US", "ES", "FR", "DE", "GB", "CN", "JP", "KR", "VN", "ID", "SG", "IN"],
      "languages": ["en", "zh", "es", "fr", "de", "id", "ja", "ko", "ru", "vi", "pt"],
      "initScore": 2000
    },
    {
      "owner": "admin",
      "name": "user-group",
      "displayName": "costrict",
      "logo": "https://costrict.ai/favicon.png",
      "passwordType": "plain",
      "passwordOptions": ["AtLeast6"],
      "countryCodes": ["CN"],
      "languages": ["en", "es", "fr", "de", "zh", "id", "ja", "ko", "ru", "vi", "pt", "it", "ms", "tr", "ar", "he", "nl", "pl", "fi", "sv", "uk", "kk", "fa", "cs", "sk"],
      "initScore": 0
    }
  ],
  "applications": [
    {
      "owner": "admin",
      "name": "app-built-in",
      "displayName": "managerApp",
      "logo": "https://costrict.ai/favicon.png",
      "organization": "built-in",
      "cert": "cert-built-in",
      "clientId": "{{CASDOOR_BUILTIN_CLIENTID}}",
      "clientSecret": "{{CASDOOR_BUILTIN_CLIENTSECRET}}",
      "enablePassword": false,
      "enableSignUp": false,
      "enableSigninSession": false,
      "enableAutoSignin": false,
      "enableCodeSignin": false,
      "enableSamlCompress": false,
      "enableSamlC14n10": false,
      "enableSamlPostBinding": false,
      "useEmailAsSamlNameId": false,
      "enableWebAuthn": false,
      "enableLinkWithEmail": false,
      "providers": [],
      "signinMethods": [
        {
          "name": "Password",
          "displayName": "Password",
          "rule": "All"
        }
      ],
      "signupItems": [
        {
          "name": "ID",
          "visible": false,
          "required": true,
          "prompted": false,
          "rule": "Random"
        },
        {
          "name": "Username",
          "visible": true,
          "required": true,
          "prompted": false,
          "rule": "None"
        },
        {
          "name": "Display name",
          "visible": true,
          "required": true,
          "prompted": false,
          "rule": "None"
        },
        {
          "name": "Password",
          "visible": true,
          "required": true,
          "prompted": false,
          "rule": "None"
        },
        {
          "name": "Confirm password",
          "visible": true,
          "required": true,
          "prompted": false,
          "rule": "None"
        },
        {
          "name": "Email",
          "visible": true,
          "required": true,
          "prompted": false,
          "rule": "Normal"
        },
        {
          "name": "Phone",
          "visible": true,
          "required": true,
          "prompted": false,
          "rule": "None"
        },
        {
          "name": "Agreement",
          "visible": true,
          "required": true,
          "prompted": false,
          "rule": "None"
        }
      ],
      "tokenFormat": "JWT"
    },
    {
      "owner": "admin",
      "name": "loginApp",
      "displayName": "loginApp",
      "logo": "https://costrict.ai/favicon.png",
      "organization": "user-group",
      "cert": "cert-built-in",
      "clientId": "{{OIDC_CLIENT_ID}}",
      "clientSecret": "{{OIDC_CLIENT_SECRET}}",
      "enablePassword": false,
      "enableSignUp": false,
      "enableSigninSession": false,
      "enableAutoSignin": false,
      "enableCodeSignin": false,
      "enableSamlCompress": false,
      "enableSamlC14n10": false,
      "enableSamlPostBinding": false,
      "useEmailAsSamlNameId": false,
      "enableWebAuthn": false,
      "enableLinkWithEmail": false,
      "providers": [
        {
          "name": "Oauth",
          "canSignUp": true,
          "canSignIn": true,
          "canUnlink": true,
          "prompted": false,
          "rule": "None"
        },
        {
          "name": "SMS",
          "canSignUp": true,
          "canSignIn": true,
          "canUnlink": true,
          "prompted": false,
          "rule": "All"
        }
      ],
      "signinMethods": [
        {
          "name": "Verification code",
          "displayName": "Verification code",
          "rule": "Phone only"
        },
        {
          "name": "Password",
          "displayName": "Password",
          "rule": "All"
        }
      ],
      "signupItems": [
        {
          "name": "ID",
          "visible": false,
          "required": true,
          "prompted": false,
          "rule": "Random"
        },
        {
          "name": "Username",
          "visible": true,
          "required": true,
          "prompted": false,
          "rule": "None"
        },
        {
          "name": "Display name",
          "visible": true,
          "required": true,
          "prompted": false,
          "rule": "None"
        },
        {
          "name": "Password",
          "visible": true,
          "required": true,
          "prompted": false,
          "rule": "None"
        },
        {
          "name": "Confirm password",
          "visible": true,
          "required": true,
          "prompted": false,
          "rule": "None"
        },
        {
          "name": "Phone",
          "visible": true,
          "required": false,
          "prompted": false,
          "rule": "No verification"
        },
        {
          "name": "Agreement",
          "visible": true,
          "required": true,
          "prompted": false,
          "rule": "None"
        },
        {
          "name": "Signup button",
          "visible": true,
          "required": true,
          "prompted": false,
          "rule": "None"
        },
        {
          "name": "Providers",
          "visible": true,
          "required": true,
          "prompted": false,
          "rule": "small"
        }
      ],
      "grantTypes": ["authorization_code", "password", "client_credentials", "token", "id_token", "refresh_token"],
      "redirectUris": ["{{COSTRICT_BASEURL}}/oidc-auth/api/v1/plugin/login/callback"],
      "tokenFormat": "JWT",
      "expireInHours": 1200,
      "refreshExpireInHours": 1200
    }
  ],
  "users": [
    {
      "owner": "built-in",
      "name": "admin",
      "type": "normal-user",
      "password": "123",
      "passwordType": "plain",
      "displayName": "Admin",
      "avatar": "https://cdn.casbin.org/img/casbin.svg",
      "email": "admin@example.com",
      "phone": "12345678910",
      "countryCode": "US",
      "affiliation": "Example Inc.",
      "title": "staff",
      "score": 2000,
      "ranking": 1,
      "isAdmin": false,
      "isGlobalAdmin": false,
      "isForbidden": false,
      "isDeleted": false,
      "signupApplication": "app-built-in"
    },
    {
      "owner": "user-group",
      "name": "demo",
      "type": "normal-user",
      "password": "test123",
      "passwordType": "plain",
      "displayName": "demo",
      "avatar": "https://cdn.casbin.org/img/casbin.svg",
      "phone": "13410000000",
      "countryCode": "CN",
      "score": 0,
      "ranking": 1,
      "isAdmin": false,
      "isGlobalAdmin": false,
      "isForbidden": false,
      "isDeleted": false,
      "signupApplication": "loginApp"
    }
  ],
  "certs": [
    {
      "owner": "admin",
      "name": "cert-built-in",
      "displayName": "Built-in Cert",
      "type": "JWT",
      "cryptoAlgorithm": "x509",
      "bitSize": 4096,
      "expireInYears": 20,
      "certificate": "-----BEGIN CERTIFICATE-----\nMIIE3TCCAsWgAwIBAgIDAeJAMA0GCSqGSIb3DQEBCwUAMCgxDjAMBgNVBAoTBWFk\nbWluMRYwFAYDVQQDEw1jZXJ0LWJ1aWx0LWluMB4XDTI1MDczMTE4MTgzNFoXDTQ1\nMDczMTE4MTgzNFowKDEOMAwGA1UEChMFYWRtaW4xFjAUBgNVBAMTDWNlcnQtYnVp\nbHQtaW4wggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQC2uJL1rSjrkOTv\nB86kXOX8heyRC2oHAjih8V+7/OQIsI69/4azcDm1yGRSqxUAgb8VSYqw/hs3sPLv\n8XdgAUFSuThh3hqLiWgIjKpju/+1h2W7j2+wog5g9SzRqhjVL5Nxk/QMeFzhhlzy\nkzNhBEolXs5fd33KcLiaVhE10AqgJ+9zkonwLz/ZyyxtDMiug4Wi9Nd403Oc7S3T\nurF4CaQUi+488SRhR/ltJ8v7OC0+tB7EWYU7ipBk+RgQssNRowb8HDPxDQBh+d/e\nz1NNjsRAf5iDWKZSTFy1dPnCA5KrL7T+FWhM+zpS9oA5IiPdIiP2QE1jhN/Fk9TL\nYqpQ09lcKXJSUGy9nrWu0Fk3qCRtF5yFskPSEaOHlqKJxh0YoNrV/KpQsOHcHlzE\nVGu16TADnbxcNaO+BOt3/ZcZiRbW1g3/bYWsUJOK8sUGhVx2rmxhTQDXlEBcRG1V\n+zPDw7H9VFMR2ZDEDTKjQvK/krSKd2RIUX/JSASO+oZSw0o2pyI5O79vtw5cB3TR\n3YEsXM8+gIbAUAFplvcBDXuALT9tsnjpf2B2I7eq7YMQAvo2TTlncYdnqTPdmgT2\n5hAnny2o1C9WLUGr7O20o+0gIeNj/tjdD3on08lIIKlNxkD2rBnkcP64VuKxAX/4\ngYq3YYFokYdsMuFM03pZFUrnAEY7WQIDAQABoxAwDjAMBgNVHRMBAf8EAjAAMA0G\nCSqGSIb3DQEBCwUAA4ICAQCSDOAHlyhrwZrcrP85T79AmhPq8Hhj0HmmR8cdiMb3\nRuzRCCkWHolK1NVnnRLhgVBG2OJH/PyZ05jRmlsAvaG8RCgcJyRJ9gFdOo3UlerT\nfb+VfZrGAwxVFuywGygctNVgN1arZ0nil2TAVQ93Z+ENZpRgKoca5xYXEhzWfJ0T\nxrnZM6ZYC+fjRfXoqvQRDHpoUvlkeWvqIswyr3fBK19JJoPGqgOa7iziqJbBdAs1\nvZ6gJoeEiocgb2qaETQi8GYymR3tHhnnCW7NC2ZRxGlQsFGGmhZwe5vSbA8jtrtV\n6owiQRT6arcp+nTQKPJwqPrGYqA0XF3uAbipjctapHirs+Pp3dVeSAeK7DNOVtSy\n771Pv2QhXjeo5kPwaMaT899jzcjzj6SpcZOio4cLZs7yYwuWJ27zgvN/Msr64QdK\ngh2R3uJLoORVJQRW/hCIYDo41e1kvUzWsIqnaCIonwtdaDzHdp6Q+7Fn90xX4Qq6\neJ05byQxIduUNhII+8d8d7Cs0VxP8GMFEiGtwP4JPMU3d/Hp0AAgLWHe/92nkQZ1\naFBBx31qIrrnpc0NWcrS/K5LibsnpRReHU5wPTrOf9HweOQ0HviVFmFcl17UfKVH\nknO89BoIM+PAxgRaCB0MPgPDPajdUFWup1craNB691D74ZoLgttIiKY1Kkf3M/hZ\nWQ==\n-----END CERTIFICATE-----",
      "privateKey": "-----BEGIN RSA PRIVATE KEY-----\n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\n-----END RSA PRIVATE KEY-----"
    }
  ],
  "providers": [
    {
      "owner": "user-group",
      "name": "Oauth",
      "displayName": "Oauth",
      "category": "OAuth",
      "type": "Custom",
      "method": "Normal",
      "clientId": "1239280978",
      "clientSecret": "49a2e85e8fbe81ce5bf768889c8e2a9b",
      "scopes": "openid profile email",
      "userMapping": {
        "avatarUrl": "",
        "displayName": "username",
        "email": "phone_number",
        "id": "employee_number",
        "username": "username"
      }
    },
    {
      "owner": "user-group",
      "name": "SMS",
      "displayName": "SMS",
      "category": "SMS",
      "type": "Custom HTTP SMS",
      "method": "POST"
    }
  ]
}
