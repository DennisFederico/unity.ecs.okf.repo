#!/bin/bash
#kiso-mcp-server.exe -s ecs-okf -H 0.0.0.0 -p 61080
my_host="$(hostname).local"
default_if="$(route get default 2>/dev/null | awk '/interface:/{print $2}')"

# macOS does not support `hostname -I`; prefer ipconfig/ifconfig based discovery.
if [ -n "$default_if" ]; then
  my_ip="$(ipconfig getifaddr "$default_if" 2>/dev/null)"
fi

if [ -z "$my_ip" ]; then
  candidate_ips="$(ifconfig 2>/dev/null | awk '/inet / {print $2}' | sed '/^127\./d' | sed '/^169\.254\./d')"
  my_ip="$(printf '%s\n' "$candidate_ips" | grep -E '^192\.' | head -n 1)"
  if [ -z "$my_ip" ]; then
    my_ip="$(printf '%s\n' "$candidate_ips" | grep -Ev '^172\.(1[6-9]|2[0-9]|3[0-1])\.' | head -n 1)"
  fi
fi

allowed_hosts="$my_host"
if [ -n "$my_ip" ]; then
  allowed_hosts="$allowed_hosts,$my_ip"
fi
echo "Starting kiso-mcp-server with --allowedHosts: $allowed_hosts"
java --add-modules jdk.incubator.vector -jar ./kiso-mcp-server.jar -s ecs-okf -H 0.0.0.0 -p 61080 --allowedHosts "$allowed_hosts"