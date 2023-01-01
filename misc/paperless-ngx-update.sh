#!/usr/bin/env bash
clear
RELEASE=$(curl -s https://api.github.com/repos/paperless-ngx/paperless-ngx/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
SER=/etc/systemd/system/paperless-task-queue.service
YW=$(echo "\033[33m")
RD=$(echo "\033[01;31m")
BL=$(echo "\033[36m")
GN=$(echo "\033[1;92m")
CL=$(echo "\033[m")
RETRY_NUM=10
RETRY_EVERY=3
NUM=$RETRY_NUM
CM="${GN}✓${CL}"
CROSS="${RD}✗${CL}"
BFR="\\r\\033[K"
HOLD="-"
set -e

function msg_info() {
    local msg="$1"
    echo -ne " ${HOLD} ${YW}${msg}..."
}

function msg_ok() {
    local msg="$1"
    echo -e "${BFR} ${CM} ${GN}${msg}${CL}"
}

function msg_error() {
    local msg="$1"
    echo -e "${BFR} ${CROSS} ${RD}${msg}${CL}"
}

cat <<"EOF"
    ____                        __                                     
   / __ \____ _____  ___  _____/ /__  __________    ____  ____ __  __
  / /_/ / __ `/ __ \/ _ \/ ___/ / _ \/ ___/ ___/___/ __ \/ __ `/ |/_/
 / ____/ /_/ / /_/ /  __/ /  / /  __(__  |__  )___/ / / / /_/ />  <  
/_/    \__,_/ .___/\___/_/  /_/\___/____/____/   /_/ /_/\__, /_/|_|  
           /_/           UPDATE                        /____/        
EOF

while true; do
    read -p "This will Update Paperless-ngx to $RELEASE. Proceed(y/n)?" yn
    case $yn in
    [Yy]*) break ;;
    [Nn]*) exit ;;
    *) echo "Please answer yes or no." ;;
    esac
done
sleep 2
msg_info "Stopping Paperless-ngx"
systemctl stop paperless-consumer paperless-webserver paperless-scheduler
if [ -f "$SER" ]; then
   systemctl stop paperless-task-queue.service
fi
sleep 1
msg_ok "Stopped Paperless-ngx"

msg_info "Updating to ${RELEASE}"
if [ "$(dpkg -l | awk '/libmariadb-dev-compat/ {print }'|wc -l)" != 1 ]; then apt-get install -y libmariadb-dev-compat; fi &>/dev/null
wget https://github.com/paperless-ngx/paperless-ngx/releases/download/$RELEASE/paperless-ngx-$RELEASE.tar.xz &>/dev/null
tar -xf paperless-ngx-$RELEASE.tar.xz &>/dev/null
cp -r /opt/paperless/paperless.conf paperless-ngx/
cp -r paperless-ngx/* /opt/paperless/
cd /opt/paperless
sed -i -e 's|-e git+https://github.com/paperless-ngx/django-q.git|git+https://github.com/paperless-ngx/django-q.git|' /opt/paperless/requirements.txt
pip install -r requirements.txt &>/dev/null
cd /opt/paperless/src
/usr/bin/python3 manage.py migrate &>/dev/null
if [ -f "$SER" ]; then
    msg_ok "paperless-task-queue.service Exists."
else
cat <<EOF >/etc/systemd/system/paperless-task-queue.service
[Unit]
Description=Paperless Celery Workers
Requires=redis.service
[Service]
WorkingDirectory=/opt/paperless/src
ExecStart=celery --app paperless worker --loglevel INFO
[Install]
WantedBy=multi-user.target
EOF
systemctl enable paperless-task-queue &>/dev/null
msg_ok "paperless-task-queue.service Created."
fi
cat <<EOF >/etc/systemd/system/paperless-scheduler.service
[Unit]
Description=Paperless Celery beat
Requires=redis.service
[Service]
WorkingDirectory=/opt/paperless/src
ExecStart=celery --app paperless beat --loglevel INFO
[Install]
WantedBy=multi-user.target
EOF
msg_ok "Updated to ${RELEASE}"

msg_info "Cleaning up"
cd ~
rm paperless-ngx-$RELEASE.tar.xz
rm -rf paperless-ngx
msg_ok "Cleaned"

msg_info "Starting Paperless-ngx"
systemctl daemon-reload
systemctl start paperless-consumer paperless-webserver paperless-scheduler paperless-task-queue.service
sleep 1
msg_ok "Finished Update"
echo -e "\n${BL}It may take a minute or so for Paperless-ngx to become available.${CL}\n"