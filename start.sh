#!/bin/bash
set -e

D="${PWD}/.n"
mkdir -p "$D"
rm -rf "$D"/* 2>/dev/null

E(){ echo "$1" | base64 -d; }

v_vl=$(E "dmxlc3M=")
v_vm=$(E "dm1lc3M=")
v_tr=$(E "dHJvamFu")
v_ws=$(E "d3M=")

U1=$(E "aHR0cDovL2NoZWNraXAuYW1hem9uYXdzLmNvbQ==")
U2=$(E "aHR0cHM6Ly9hcGkuaXBpZnkub3Jn")
IP=$(node -e 'fetch(process.argv[1]).then(r=>r.text()).then(t=>console.log(t.trim())).catch(()=>{})' "$U1")
[ -z "$IP" ] && IP=$(node -e 'fetch(process.argv[1]).then(r=>r.text()).then(t=>console.log(t.trim())).catch(()=>{})' "$U2")
[ -z "$IP" ] && IP="127.0.0.1"

ID=$(cat /proc/sys/kernel/random/uuid)
ap=8081

bs="${D}/s"
bc="${D}/c"

node -e 'const fs=require("fs");fetch(process.argv[1]).then(r=>r.arrayBuffer()).then(b=>fs.writeFileSync(process.argv[2],Buffer.from(b)))' "$(E "aHR0cHM6Ly9hbWQ2NC5zc3NzLm55Yy5tbi9zYg==")" "$bs"
node -e 'const fs=require("fs");fetch(process.argv[1]).then(r=>r.arrayBuffer()).then(b=>fs.writeFileSync(process.argv[2],Buffer.from(b)))' "$(E "aHR0cHM6Ly9naXRodWIuY29tL2Nsb3VkZmxhcmUvY2xvdWRmbGFyZWQvcmVsZWFzZXMvbGF0ZXN0L2Rvd25sb2FkL2Nsb3VkZmxhcmVkLWxpbnV4LWFtZDY0")" "$bc"

chmod +x "$bs" "$bc"

cf_j="${D}/c.j"
cat > "$cf_j" <<EOF
{"log":{"level":"warn"},"inbounds":[
{"type":"${v_vl}","listen":"127.0.0.1","listen_port":${ap},"users":[{"uuid":"${ID}"}],"transport":{"type":"${v_ws}","path":"/vl"}},
{"type":"${v_vm}","listen":"127.0.0.1","listen_port":${ap},"users":[{"uuid":"${ID}","alterId":0}],"transport":{"type":"${v_ws}","path":"/vm"}},
{"type":"${v_tr}","listen":"127.0.0.1","listen_port":${ap},"users":[{"password":"${ID}"}],"transport":{"type":"${v_ws}","path":"/tr"}}
],"outbounds":[{"type":"direct"}]}
EOF

"$bs" run -c "$cf_j" &
P1=$!
sleep 2

"$bc" tunnel --protocol http2 --no-autoupdate --url http://127.0.0.1:${ap} > "${D}/a.log" 2>&1 &
P2=$!

for i in {1..20}; do
 sleep 1
 ad=$(grep -oE "https://[a-zA-Z0-9.-]+\.trycloudflare.com" "${D}/a.log" | head -1 | sed 's|https://||')
 [ -n "$ad" ] && break
done

sf="${D}/sub"
> "$sf"
echo "${v_vl}://${ID}@${ad}:443?encryption=none&security=tls&type=${v_ws}&host=${ad}&path=%2Fvl#VL" >> "$sf"
vmj="{\"v\":\"2\",\"ps\":\"VM\",\"add\":\"${ad}\",\"port\":\"443\",\"id\":\"${ID}\",\"aid\":\"0\",\"net\":\"${v_ws}\",\"type\":\"none\",\"host\":\"${ad}\",\"path\":\"/vm\",\"tls\":\"tls\"}"
echo "${v_vm}://$(echo -n "$vmj" | base64 -w 0)" >> "$sf"
echo "${v_tr}://${ID}@${ad}:443?security=tls&type=${v_ws}&host=${ad}&path=%2Ftr#TR" >> "$sf"

echo "OK"
echo "ID: ${ID}"
cat "$sf"

trap "kill $P1 $P2 2>/dev/null" SIGINT SIGTERM
wait $P1
