#!/bin/bash
set -euo pipefail
exec > >(tee /var/log/bastion-userdata.log) 2>&1

echo "=== Cài đặt Docker ==="
dnf install -y docker
systemctl enable --now docker

echo "=== Cấu hình Docker registry:2 như systemd service ==="
cat > /etc/systemd/system/docker-registry.service <<'EOF'
[Unit]
Description=Docker Registry
After=docker.service
Requires=docker.service

[Service]
Type=simple
ExecStartPre=-/usr/bin/docker stop registry
ExecStartPre=-/usr/bin/docker rm registry
ExecStart=/usr/bin/docker run --rm --name registry \
  -p ${registry_port}:5000 \
  -v /var/lib/registry:/var/lib/registry \
  registry:2
ExecStop=/usr/bin/docker stop registry
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now docker-registry.service

echo "=== Chờ registry start ==="
for i in {1..30}; do
  if curl -sf http://localhost:${registry_port}/v2/ > /dev/null 2>&1; then
    echo "Registry is ready!"
    break
  fi
  echo "Waiting for registry... ($i/30)"
  sleep 2
done

echo "=== Seeding images vào local registry ==="
%{ for image in registry_images ~}
echo "Pulling and pushing: ${image}"
SOURCE_IMAGE="${image}"
TARGET_IMAGE="localhost:${registry_port}/$${SOURCE_IMAGE#*/}"

docker pull "$SOURCE_IMAGE" || echo "Failed to pull $SOURCE_IMAGE, continuing..."
docker tag "$SOURCE_IMAGE" "$TARGET_IMAGE"
docker push "$TARGET_IMAGE" || echo "Failed to push $TARGET_IMAGE, continuing..."
docker rmi "$SOURCE_IMAGE" "$TARGET_IMAGE" || true
%{ endfor ~}

echo "=== Bastion registry setup hoàn tất ==="
