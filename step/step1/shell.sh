# docker-compose 생성 한방 쿼리
cd ~
mkdir -p ~/aws-vpc-local-lab/step/step1
cd ~/aws-vpc-local-lab/step/step1

cat > docker-compose.yml << 'EOF'
version: "3.8"

services:
  app-server:
    image: nginx:stable
    container_name: app-server
    network_mode: "none"

  database:
    image: mysql:8.0
    container_name: database
    network_mode: "none"
    environment:
      MYSQL_ROOT_PASSWORD: localpass
      MYSQL_DATABASE: appdb
EOF

# compose demon 실행
docker-compose up -d

# docker 프로세스 확인
docker ps

# log 확인
docker logs database --tail 30

# appserver - nginx 확인
docker exec app-server nginx -v
docker exec app-server nginx -t
docker logs app-server --tail 20

# DB 상태도 확인
docker exec database mysqladmin ping -uroot -plocalpass

# Host에서 VM 접근 확인 - 실패
curl http://192.168.56.2

# VPC VM 내부에서 확인 - 실패
curl http://localhost
curl http://127.0.0.1

# App Server -> DB 접근 - 실패
docker exec app-server sh -c 'getent hosts database || echo "database name lookup failed"'

# DB -> App Server 접근 - 실패
docker exec database sh -c 'getent hosts app-server || echo "app-server name lookup failed"'

# 컨테이너 Network 확인
docker inspect app-server --format '{{.HostConfig.NetworkMode}}'
docker inspect database --format '{{.HostConfig.NetworkMode}}'

docker inspect app-server --format 'mode={{.HostConfig.NetworkMode}} ip={{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}} gateway={{range .NetworkSettings.Networks}}{{.Gateway}}{{end}}'
docker inspect database --format 'mode={{.HostConfig.NetworkMode}} ip={{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}} gateway={{range .NetworkSettings.Networks}}{{.Gateway}}{{end}}'

docker inspect app-server --format '{{json .NetworkSettings.Networks}}'
docker inspect database --format '{{json .NetworkSettings.Networks}}'

# 실습 후 마무리 - 필요시
cd ~/aws-vpc-local-lab/step/step1
docker-compose down