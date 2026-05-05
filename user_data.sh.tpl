#!/bin/bash
set -euo pipefail
exec > >(tee /var/log/user-data.log) 2>&1

echo "=== [1/4] Cài đặt Docker ==="
dnf install -y docker
systemctl enable --now docker

echo "=== [2/4] Tạo systemd service cho registry:2 ==="
cat > /etc/systemd/system/registry.service <<'EOF'
[Unit]
Description=Docker Registry v2 (Local Mirror)
After=docker.service
Requires=docker.service

[Service]
Restart=always
RestartSec=5
ExecStartPre=-/usr/bin/docker rm -f local-registry
ExecStart=/usr/bin/docker run \
  --name local-registry \
  -p ${registry_port}:5000 \
  -v /var/lib/registry:/var/lib/registry \
  registry:2
ExecStop=/usr/bin/docker stop local-registry

[Install]
WantedBy=multi-user.target
EOF

# Pull registry:2 trước khi enable service
docker pull registry:2

systemctl daemon-reload
systemctl enable --now registry.service

echo "=== [3/4] Đợi registry sẵn sàng ==="
until curl -sf http://localhost:${registry_port}/v2/ > /dev/null 2>&1; do
  echo "Waiting for registry to be ready..."
  sleep 3
done
echo "Registry is up at localhost:${registry_port}"

echo "=== [4/4] Seed images vào local registry ==="
# Hàm pull → tag → push vào local registry
seed_image() {
  local src="$1"
  # Xác định registry nguồn và tạo local tag
  local local_tag="localhost:${registry_port}/$${src#*/}"

  echo "Seeding: $src → $local_tag"
  docker pull "$src" || { echo "WARN: Failed to pull $src, skipping"; return 0; }
  docker tag "$src" "$local_tag"
  docker push "$local_tag"
  # Dọn dẹp image gốc để tiết kiệm disk
  docker rmi "$src" || true
}

%{ for image in registry_images ~}
seed_image "${image}"
%{ endfor ~}

echo "=== Registry seed hoàn tất ==="
echo "Registry đang chạy tại: $(hostname -I | awk '{print $1}'):${registry_port}"
curl -sf "http://localhost:${registry_port}/v2/_catalog" | python3 -m json.tool
