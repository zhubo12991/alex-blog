#!/bin/bash
set -e

TK=""

D="${PWD}/.n"
W="${PWD}/public"
mkdir -p "$D"
rm -rf "$D"/* 2>/dev/null

E() { echo "$1" | base64 -d; }

GT() {
    node -e 'fetch(process.argv[1],{signal:AbortSignal.timeout(5000)}).then(r=>r.text()).then(t=>console.log(t.trim())).catch(e=>console.log(""))' "$1"
}

DL() {
    url="$1"
    out="$2"
    echo "."
    node -e 'const fs=require("fs");fetch(process.argv[1]).then(r=>{if(!r.ok)throw new Error(r.statusText);return r.arrayBuffer()}).then(b=>fs.writeFileSync(process.argv[2],Buffer.from(b))).catch(e=>{console.error(e);process.exit(1)})' "$url" "$out"
}

v_vl=$(E "dmxlc3M=")
v_vm=$(E "dm1lc3M=")
v_tr=$(E "dHJvamFu")
v_ws=$(E "d3M=")

L=(
    "Y2YuMDkwMjI3Lnh5eg=="
    "Y2YuODc3Nzc0Lnh5eg=="
    "Y2YuMTMwNTE5Lnh5eg=="
    "Y2YuMDA4NTAwLnh5eg=="
    "c3RvcmUudWJpLmNvbQ=="
    "c2Fhcy5zaW4uZmFu"
)

U1=$(E "aHR0cDovL2NoZWNraXAuYW1hem9uYXdzLmNvbQ==")
U2=$(E "aHR0cHM6Ly9hcGkuaXBpZnkub3Jn")

IP=$(GT "$U1")
[ -z "$IP" ] && IP=$(GT "$U2")
[ -z "$IP" ] && IP="${SERVER_IP:-127.0.0.1}"

B=""
for i in "${L[@]}"; do
    dm=$(E "$i")
    code=$(node -e 'fetch("https://"+process.argv[1],{method:"HEAD",signal:AbortSignal.timeout(2000)}).then(r=>console.log(r.ok)).catch(e=>console.log("false"))' "$dm")
    if [ "$code" == "true" ]; then
        B="$dm"; break
    fi
done
[ -z "$B" ] && B=$(E "${L[0]}")

w="${SERVER_PORT:-${PORT}}"
[ -z "$w" ] && w=3000
ap=8081
p1=10001
p2=10002
p3=10003

f_u="${D}/u"
[ -f "$f_u" ] && ID=$(cat "$f_u") || { ID=$(cat /proc/sys/kernel/random/uuid); echo "$ID" > "$f_u"; }

ar=$(uname -m)
if [[ "$ar" == "aarch64" ]]; then
    bu=$(E "aHR0cHM6Ly9hcm02NC5zc3NzLm55Yy5tbg==")
    aa="arm64"
else
    bu=$(E "aHR0cHM6Ly9hbWQ2NC5zc3NzLm55Yy5tbg==")
    aa="amd64"
fi

bs="${D}/s"
bc="${D}/c"
cu=$(E "aHR0cHM6Ly9naXRodWIuY29tL2Nsb3VkZmxhcmUvY2xvdWRmbGFyZWQvcmVsZWFzZXMvbGF0ZXN0L2Rvd25sb2FkL2Nsb3VkZmxhcmVkLWxpbnV4LQ==")

DL "${bu}/sb" "$bs" && chmod +x "$bs"
DL "${cu}${aa}" "$bc" && chmod +x "$bc"

sp_u=$(E "aHR0cHM6Ly9zcGVlZC5jbG91ZGZsYXJlLmNvbS9tZXRh")
JD=$(GT "$sp_u")
ORG=$(echo "$JD" | sed -n 's/.*"asOrganization":"\([^"]*\)".*/\1/p')
[ -z "$ORG" ] && ORG="N"

g_s() {
    ad="$1"
    sf="${D}/s.t"
    > "$sf"
    
    [ -n "$ad" ] && echo "${v_vl}://${ID}@${B}:443?encryption=none&security=tls&sni=${ad}&type=${v_ws}&host=${ad}&path=%2Fvl#VL-${ORG}" >> "$sf"
    
    if [ -n "$ad" ]; then
        vm_j="{\"v\":\"2\",\"ps\":\"VM-${ORG}\",\"add\":\"${B}\",\"port\":\"443\",\"id\":\"${ID}\",\"aid\":\"0\",\"scy\":\"auto\",\"net\":\"${v_ws}\",\"type\":\"none\",\"host\":\"${ad}\",\"path\":\"/vm\",\"tls\":\"tls\",\"sni\":\"${ad}\"}"
        vm_b64=$(echo -n "$vm_j" | base64 -w 0)
        echo "${v_vm}://${vm_b64}" >> "$sf"
    fi

    [ -n "$ad" ] && echo "${v_tr}://${ID}@${B}:443?security=tls&sni=${ad}&type=${v_ws}&host=${ad}&path=%2Ftr#TR-${ORG}" >> "$sf"
    
    cp "$sf" "${D}/sub"
}

js="${D}/j.js"
cat > "$js" <<'EOF'
const h=require('http'),n=require('net'),f=require('fs'),p=require('path');
const pt=process.argv[2],ap=process.argv[3],pd=process.argv[4],sf=process.argv[5],id=process.argv[6];

function S(q,r){
 const u=q.url.split('?')[0];
 if(u.includes('/sub')||(id&&u.includes('/'+id))){
  r.writeHead(200,{'Content-Type':'text/plain;charset=utf-8'});
  try{r.end(f.readFileSync(sf,'utf8'))}catch(e){r.end('')}return;
 }
 let fp=u==='/'?p.join(pd,'index.html'):p.join(pd,u);
 f.readFile(fp,(e,c)=>{
  if(e){
   f.readFile(p.join(pd,'index.html'),(xE,xB)=>{
    if(xE){r.writeHead(404);r.end()}else{r.writeHead(200,{'Content-Type':'text/html'});r.end(xB)}
   });
  }else{r.writeHead(200);r.end(c)}
 });
}

function W(q,k,hd){
 let tp=0;
 if(q.url.startsWith('/vl')) tp=10001;
 else if(q.url.startsWith('/vm')) tp=10002;
 else if(q.url.startsWith('/tr')) tp=10003;
 if(tp){
  const c=n.createConnection(tp);
  c.on('connect', ()=>{c.write(hd);k.pipe(c).pipe(k)});
  c.on('error', ()=>k.destroy());
 } else { k.destroy(); }
}

h.createServer(S).on('upgrade',W).listen(pt,'0.0.0.0');
h.createServer(S).on('upgrade',W).listen(ap,'127.0.0.1');
EOF

node "$js" "$w" "$ap" "$W" "${D}/sub" "$ID" &
P1=$!

IN="{
    \"type\": \"${v_vl}\",
    \"tag\": \"vl-in\",
    \"listen\": \"127.0.0.1\",
    \"listen_port\": ${p1},
    \"users\": [{\"uuid\": \"${ID}\"}],
    \"transport\": {\"type\": \"${v_ws}\", \"path\": \"/vl\"}
},{
    \"type\": \"${v_vm}\",
    \"tag\": \"vm-in\",
    \"listen\": \"127.0.0.1\",
    \"listen_port\": ${p2},
    \"users\": [{\"uuid\": \"${ID}\", \"alterId\": 0}],
    \"transport\": {\"type\": \"${v_ws}\", \"path\": \"/vm\"}
},{
    \"type\": \"${v_tr}\",
    \"tag\": \"tr-in\",
    \"listen\": \"127.0.0.1\",
    \"listen_port\": ${p3},
    \"users\": [{\"password\": \"${ID}\"}],
    \"transport\": {\"type\": \"${v_ws}\", \"path\": \"/tr\"}
}"

cf_j="${D}/c.j"
cat > "$cf_j" <<EOF
{"log":{"level":"warn"},"inbounds":[${IN}],"outbounds":[{"type":"direct","tag":"d"}]}
EOF

"$bs" run -c "$cf_j" &
P2=$!
sleep 2

l_a="${D}/a.l"
ad=""
"$bc" tunnel --edge-ip-version auto --protocol http2 --no-autoupdate --url http://127.0.0.1:${ap} > "$l_a" 2>&1 &
P3=$!

for i in {1..20}; do
    sleep 1
    kw=$(E "dHJ5Y2xvdWRmbGFyZS5jb20=")
    ad=$(grep -oE "https://[a-zA-Z0-9-]+\.${kw}" "$l_a" 2>/dev/null | head -1 | sed 's|https://||')
    [ -n "$ad" ] && break
done

g_s "$ad"

S_URL="http://${IP}:${w}/sub"
echo "OK"
echo "L: $S_URL"
echo "ID: $ID"

trap "kill $P1 $P2 $P3 2>/dev/null; exit" SIGTERM SIGINT
wait $P2
