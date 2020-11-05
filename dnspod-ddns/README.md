# utils > ddns

DDNS scripts written in Lua, available for DNSPod CN & INTL.

## Dependencies

Dependencies under OpenWRT:

```
opkg install luasocket luasec
```

## Usage

### With `uhttpd`
A sample `uhttpd` configuration: 

```
config uhttpd sample
	list listen_http '0.0.0.0:2333'
	option home '/www/luaroot'
	list interpreter '.lua=/usr/bin/lua'
```
### With Other HTTP Servers
...