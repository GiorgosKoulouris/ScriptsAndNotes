#!/bin/bash
cfToken=''

grep -iq ubuntu /etc/*release && {
	curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
	dpkg -i cloudflared.deb && 
	cloudflared service install "$cfToken"
	rm -rf cloudflared.deb
} || {
	curl -L --output cloudflared.rpm https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-x86_64.rpm
	yum localinstall -y cloudflared.rpm
	cloudflared service install "$cfToken"
	rm -rf cloudflared.rpm
}
