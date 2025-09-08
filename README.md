This is a simple wireguard VPN user management script using on VPN server.
Client config file and qrcode are generated.

### dependency

* wireguard
* qrencode

### config
The wireguard default config directory is /etc/wireguard.

1. Copy script `wg-config.def.sample` config file  `/etc/wireguard/wg-config.def`. This is the main wg-configs config.

2. Copy `client.conf.tpl.sample` to `/etc/wireguard/client.conf.tpl`

3. Copy `server.conf.tpl.sample` to `/etc/wireguard/server.conf.tpl`

4. put `wg-configs.sh` to your path or any location you wish.

You can generate the public key and private key with command `cd /etc/wireguard && wg genkey | tee prikey | wg pubkey > pubkey`.

### usage

Running as root.

#### init wireguard server

```bash
./wg-config.sh -i
```

#### add a user

```bash
./wg-config.sh -a alice
```

This will generate a client conf and qrcode in users directory which name is alice and add alice to the wg server config.

This will disable default route change. Route traffic Manually.

```bash
./wg-config.sh -a alice -r
```

client will route all traffic to server.

#### delete a user

```bash
./wg-config.sh -d alice
```
This will delete the alice directory and delete alice from the wg server config.

#### clear all

```bash
./wg-config.sh -c
```

Delete all users before clear.
