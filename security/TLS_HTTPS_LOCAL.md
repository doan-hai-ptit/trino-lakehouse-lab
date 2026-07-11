# Bật TLS/HTTPS local cho Trino

Tài liệu này cấu hình HTTPS cho lab Docker hiện tại với kiến trúc:

```text
Browser / CLI
     |
https://trino.localhost:443
     |
Nginx (TLS termination)
     |
http://trino:8080 (Docker network nội bộ)
     |
Trino coordinator <--> 2 Trino workers
```

`trino.localhost` chỉ phù hợp cho máy local. Không cần mua tên miền và không cần sửa file `hosts` vì tên miền có hậu tố `.localhost` được trỏ tới loopback.

> TLS trong hướng dẫn này bảo vệ đường đi từ client đến Trino coordinator. Kết nối coordinator-to-worker vẫn là HTTP trong Docker network nội bộ. Xem phần [Mở rộng production](#mở-rộng-production) nếu cần mã hóa traffic nội bộ.

## Điều kiện trước khi bắt đầu

- Docker Desktop đang chạy.
- Docker Compose đang có các service: `trino`, `trino-worker-1`, `trino-worker-2`.
- PowerShell đang đứng tại thư mục gốc của project.
- Port `443` trên máy local chưa bị chương trình khác chiếm.

Kiểm tra port 443 (không có output nghĩa là đang trống):

```powershell
Get-NetTCPConnection -LocalPort 443 -ErrorAction SilentlyContinue
```

## 1. Cài và khởi tạo CA local với mkcert

Mở PowerShell **Run as Administrator**, sau đó chạy:

```powershell
winget install -e --id FiloSottile.mkcert
mkcert -install
```

Lệnh `mkcert -install` cài CA local vào Windows trust store để Chrome/Edge tin certificate được tạo ở bước sau.

> Không chia sẻ private key hoặc thư mục CA do `mkcert` tạo. CA đó có thể được dùng để tạo certificate mà máy của bạn tin cậy.

## 2. Tạo certificate cho Trino local

Mở một PowerShell bình thường tại thư mục gốc project và chạy:

```powershell
New-Item -ItemType Directory -Force secrets\certs
mkcert -cert-file secrets\certs\trino.localhost.pem `
  -key-file secrets\certs\trino.localhost-key.pem `
  trino.localhost localhost 127.0.0.1 ::1
```

Kết quả cần có hai file sau:

```text
secrets/certs/trino.localhost.pem
secrets/certs/trino.localhost-key.pem
```

Không commit các file này. Thêm dòng sau vào `.gitignore`:

```gitignore
secrets/
```

## 3. Tạo cấu hình Nginx

Tạo thư mục và mở file cấu hình:

```powershell
New-Item -ItemType Directory -Force nginx\conf.d
notepad nginx\conf.d\trino.conf
```

Dán toàn bộ nội dung sau vào `nginx/conf.d/trino.conf`, lưu file và đóng Notepad:

```nginx
server {
    listen 443 ssl;
    server_name trino.localhost;

    ssl_certificate     /etc/nginx/certs/trino.localhost.pem;
    ssl_certificate_key /etc/nginx/certs/trino.localhost-key.pem;

    location / {
        proxy_pass http://trino:8080;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }
}
```

## 4. Cập nhật Docker Compose

Mở `docker-compose.yaml`.

### 4.1 Không public cổng Trino 8080

Trong service `trino`, xóa phần sau:

```yaml
    ports:
      - "8080:8080"
```

Nginx vẫn kết nối được đến `trino:8080` qua Docker network. Việc bỏ port mapping giúp người dùng không bypass HTTPS bằng `http://localhost:8080`.

### 4.2 Thêm Nginx service

Thêm service sau ở cùng cấp với `trino` và các service khác:

```yaml
  nginx:
    image: nginx:1.30.3-alpine
    container_name: lakehouse-nginx
    depends_on:
      trino:
        condition: service_started
    ports:
      - "443:443"
    volumes:
      - "./nginx/conf.d:/etc/nginx/conf.d:ro"
      - "./secrets/certs:/etc/nginx/certs:ro"
```

Pin version `1.30.3-alpine` để lần chạy sau không tự đổi version Nginx bất ngờ.

## 5. Cho Trino tin header HTTPS từ Nginx

Trong `trino/etc/config.properties`, giữ các dòng hiện có và thêm:

```properties
http-server.process-forwarded=true
```

Cấu hình coordinator hoàn chỉnh sẽ có dạng:

```properties
coordinator=true
node-scheduler.include-coordinator=true
http-server.http.port=8080
http-server.process-forwarded=true
discovery.uri=http://trino:8080
```

`discovery.uri` dùng hostname Docker `trino` để hai worker tìm được coordinator. Không đổi nó thành `https://trino.localhost`, vì đây không phải endpoint nội bộ của các containers trong cấu hình TLS termination tại Nginx.

## 6. Kiểm tra cấu hình và khởi động

Kiểm tra Compose trước:

```powershell
docker compose config --quiet
```

Khởi động hoặc cập nhật containers:

```powershell
docker compose up -d
docker compose ps
```

Kiểm tra log Nginx nếu service không lên:

```powershell
docker compose logs nginx
```

Kiểm tra các node Trino đã đăng ký:

```powershell
docker compose logs trino
docker compose logs trino-worker-1
docker compose logs trino-worker-2
```

## 7. Xác minh HTTPS

Mở Web UI:

```text
https://trino.localhost/ui
```

Certificate phải được trình duyệt tin cậy, không có cảnh báo bảo mật.

Kiểm tra từ PowerShell:

```powershell
curl.exe -I https://trino.localhost
```

CLI Trino sử dụng URL HTTPS:

```powershell
trino --server https://trino.localhost
```

Sau khi vào CLI, chạy:

```sql
SELECT node_id, coordinator, state
FROM system.runtime.nodes;
```

Kết quả cần có ba node: một coordinator và hai worker đang `active`.

## Khắc phục lỗi thường gặp

### Không truy cập được `https://trino.localhost`

1. Kiểm tra Nginx đang chạy: `docker compose ps`.
2. Kiểm tra port 443: `Get-NetTCPConnection -LocalPort 443`.
3. Xem log: `docker compose logs nginx`.
4. Đảm bảo hai file certificate ở đúng thư mục `secrets/certs/`.

### Browser báo certificate không tin cậy

Chạy lại PowerShell bằng quyền Administrator:

```powershell
mkcert -install
```

Sau đó đóng và mở lại browser. Trên máy khác trong LAN, certificate này sẽ không được tin cậy; cần cài CA local vào máy đó hoặc sử dụng CA/chứng chỉ doanh nghiệp.

### Nginx báo không tìm thấy upstream `trino`

Đảm bảo tất cả service thuộc cùng một Docker Compose project, và service coordinator vẫn tên là `trino`. Không thay `proxy_pass http://trino:8080` bằng `localhost:8080`; trong container, `localhost` là chính container Nginx.

### Worker không hiện trong `system.runtime.nodes`

Kiểm tra các file worker đều chứa:

```properties
coordinator=false
discovery.uri=http://trino:8080
```

Mỗi worker phải có `node.id` riêng, ví dụ `trino-worker-1` và `trino-worker-2`.

## Mở rộng production

Khi đưa ra Internet, thay `trino.localhost` bằng tên miền thật, ví dụ `trino.example.com`:

1. Mua/đăng ký domain và tạo DNS record `A` trỏ đến public IP của server.
2. Mở firewall port 80/443; chỉ public Nginx, không public `8080` của Trino.
3. Dùng certificate từ Let's Encrypt hoặc CA doanh nghiệp, có gia hạn tự động.
4. Bật authentication và access control trong Trino; HTTPS chỉ mã hóa đường truyền, không xác thực người dùng.
5. Nếu mạng giữa coordinator và workers không được tin cậy, cấu hình thêm TLS cho internal communication bằng `internal-communication.https.required=true` và làm theo tài liệu Trino cho mô hình multi-node.

## Tham khảo

- [Trino: TLS and HTTPS](https://trino.io/docs/current/security/tls.html)
- [Trino: Security overview](https://trino.io/docs/current/security/overview.html)
- [mkcert](https://github.com/FiloSottile/mkcert)
- [Nginx download](https://nginx.org/en/download.html)
