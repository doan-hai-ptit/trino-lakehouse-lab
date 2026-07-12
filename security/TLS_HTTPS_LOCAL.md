# HTTPS local cho Trino qua Nginx

> Tóm tắt theo [TLS and HTTPS — Trino current](https://trino.io/docs/current/security/tls.html) (trang hiển thị Trino 482 khi đối chiếu ngày 2026-07-11).

Tài liệu này dùng mô hình **TLS termination tại Nginx** cho lab Docker. Đây là hướng Trino khuyến nghị khi đã có load balancer hoặc reverse proxy: client kết nối HTTPS đến proxy, proxy chuyển tiếp HTTP trên Docker network đến Trino coordinator.

Nó chỉ mã hóa hop **client → Nginx**. Hop `Nginx → coordinator` vẫn là HTTP và phải ở Docker network riêng/tin cậy; nó không được public ra host. Hướng dẫn này không bật TLS native của Trino và cũng không mã hóa traffic coordinator ↔ worker; xem [SECURE_INTERNAL_COMMUNICATION.md](SECURE_INTERNAL_COMMUNICATION.md) nếu cần lớp bảo vệ nội bộ.

## 1. Kiến trúc và ranh giới bảo mật

```text
Browser / CLI
     |
https://trino.localhost:443
     |
Nginx (TLS termination)
     |
http://trino:8080 (Docker network nội bộ)
     |
Trino coordinator <--> workers
```

Trino hỗ trợ TLS 1.2 và 1.3 cho client. Trong mô hình này:

- Nginx giữ certificate/private key và thực hiện TLS handshake.
- Nginx gửi `X-Forwarded-Proto: https`; Trino phải có `http-server.process-forwarded=true` để hiểu request đã được bảo vệ tại proxy.
- Không cần bật `http-server.https.enabled=true` trên coordinator chỉ để dùng mô hình Nginx này.
- HTTPS không tự xác thực hay phân quyền user. Khi dùng password/OAuth/... phải bật authentication và access control riêng.

> **Trạng thái repository hiện tại:** service `trino` vẫn publish `8080:8080`. Password authentication thông thường từ chối HTTP trực tiếp, nhưng đó không đủ để coi cổng này an toàn: khi `http-server.process-forwarded=true`, client HTTP không tin cậy có thể tự gửi `X-Forwarded-Proto: https` và làm Trino coi request cleartext là đã được bảo vệ. Trước khi coi lab là HTTPS-only hoặc bật password authentication, phải bỏ host-port mapping này; chỉ Nginx nên public `443`.

> HTTPS trong tài liệu này chỉ bảo vệ frontend Trino. Compose hiện cũng publish PostgreSQL (`5433`), MinIO (`9000`/`9001`) và Hive Metastore (`9083`); lab chưa phải một deployment production-hardened. Với môi trường ngoài local, bỏ/bind/protect các host port đó riêng.

Vì `http-server.process-forwarded=true` khiến Trino xử lý forwarded header từ proxy, coordinator không nên là endpoint HTTP công khai cho client không tin cậy.

## 2. Chuẩn bị certificate local

`trino.localhost` phù hợp cho máy local. Dùng `mkcert` để tạo CA local mà Chrome/Edge trên máy phát triển tin cậy.

Mở PowerShell **Run as Administrator**:

```powershell
winget install -e --id FiloSottile.mkcert
mkcert -install
```

Tại thư mục gốc project, tạo certificate:

```powershell
New-Item -ItemType Directory -Force secrets\certs
mkcert -cert-file secrets\certs\trino.localhost.pem `
  -key-file secrets\certs\trino.localhost-key.pem `
  trino.localhost localhost 127.0.0.1 ::1
```

Kết quả:

```text
secrets/certs/trino.localhost.pem
secrets/certs/trino.localhost-key.pem
```

Không commit certificate hay private key. Repository đã bỏ qua `secrets/`; cũng không chia sẻ CA local do `mkcert` tạo.

## 3. Cấu hình Nginx — giữ nguyên các header proxy

Tạo `nginx/conf.d/trino.conf`:

```powershell
New-Item -ItemType Directory -Force nginx\conf.d
notepad nginx\conf.d\trino.conf
```

Nội dung:

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

`proxy_pass http://trino:8080` là địa chỉ service Docker, không phải `localhost:8080`. Trong container Nginx, `localhost` trỏ về chính Nginx.

## 4. Docker Compose: chỉ public Nginx

Trong service `trino`, **xóa** host port mapping sau nếu còn tồn tại:

```yaml
ports:
  - "8080:8080"
```

Giữ service Nginx ở cùng Docker Compose project:

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

Nginx vẫn truy cập được `trino:8080` qua network Docker, nên không cần public cổng này ra máy host.

## 5. Cấu hình coordinator

Trong `trino/etc/config.properties`, giữ HTTP endpoint nội bộ và thêm/giữ dòng sau để nhận forwarded header:

```properties
http-server.http.port=8080
http-server.process-forwarded=true
discovery.uri=http://trino:8080
```

`discovery.uri` là kết nối nội bộ để worker tìm coordinator, nên không đổi thành `https://trino.localhost` trong mô hình TLS termination tại Nginx. Các cấu hình authentication, shared secret và catalog hiện có phải được giữ riêng; block trên chỉ là phần liên quan proxy/TLS frontend.

### Phương án khác: TLS trực tiếp trên Trino

Nếu không dùng reverse proxy, Trino có thể tự phục vụ HTTPS trên coordinator bằng certificate mà process coordinator đọc được:

```properties
http-server.https.enabled=true
http-server.https.port=8443
http-server.https.keystore.path=etc/clustercoord.pem
```

Không trộn cấu hình native này vào mô hình Nginx chỉ vì muốn có HTTPS: tài liệu Trino nêu rõ coordinator phía sau load balancer/proxy không cần `http-server.https.enabled=true`. Direct TLS phù hợp khi coordinator là endpoint HTTPS trực tiếp; xem trang nguồn để biết PEM/JKS/PKCS#12 và password của JKS.

`http-server.https.keystore.path=etc/clustercoord.pem` là ví dụ path tương đối cho bản cài tar.gz trong tài liệu Trino, không phải path Docker của repository này. Nếu chủ động chuyển sang direct TLS trong container, mount certificate ở một vị trí riêng và dùng đường dẫn tuyệt đối của mount đó; không giả định `etc/clustercoord.pem` sẽ trỏ vào `/etc/trino`.

## 6. Khởi động và xác minh

Kiểm tra Compose trước:

```powershell
docker compose config --quiet
docker compose up -d
docker compose ps
docker compose logs nginx
```

Xác nhận cổng HTTP không còn publish ra host:

```powershell
docker compose port trino 8080
```

Lệnh trên không được trả về host port. Nếu nó trả về một địa chỉ, xóa `8080:8080` rồi tạo lại service `trino`.

Mở Web UI:

```text
https://trino.localhost/ui
```

Certificate phải được browser tin cậy. Khi password authentication đang bật, lệnh sau có thể trả `401 Unauthorized` nếu không gửi credential; đó vẫn là dấu hiệu TLS/proxy đã nhận request:

```powershell
curl.exe -I https://trino.localhost
```

Kiểm thử end-to-end bằng CLI qua HTTPS:

```powershell
trino --server https://trino.localhost --user admin --password
```

```sql
SELECT node_id, coordinator, state
FROM system.runtime.nodes;
```

Kết quả của lab phải có một coordinator và hai worker `active`.

## 7. Lỗi thường gặp

| Triệu chứng | Kiểm tra |
| --- | --- |
| Không vào được `https://trino.localhost` | `docker compose ps`, port `443`, `docker compose logs nginx` và hai file trong `secrets/certs/`. |
| Browser không tin certificate | Chạy lại `mkcert -install` với quyền Administrator, rồi khởi động lại browser. Máy khác cần tin CA local riêng hoặc dùng CA doanh nghiệp. |
| Nginx không thấy upstream | Giữ `proxy_pass http://trino:8080` và đảm bảo service coordinator vẫn tên `trino`. |
| Vẫn vào được `http://localhost:8080` | `8080:8080` vẫn đang được publish; bỏ mapping và recreate coordinator. |
| Worker không xuất hiện | Kiểm tra `coordinator=false` và `discovery.uri=http://trino:8080` ở worker; TLS frontend không thay đổi discovery nội bộ. |

## 8. Khi đưa ra môi trường ngoài local

- Thay certificate `mkcert` bằng certificate CA công khai hoặc CA doanh nghiệp; self-signed certificate không phù hợp production.
- Chỉ public proxy/load balancer, không public HTTP coordinator.
- Nếu proxy và coordinator không cùng private/trusted network, bảo vệ cả upstream proxy → coordinator thay vì giữ `proxy_pass` qua HTTP.
- Bật authentication và access control; HTTPS chỉ bảo vệ kênh truyền.
- Nếu network giữa các node không tin cậy, bật [Secure internal communication](SECURE_INTERNAL_COMMUNICATION.md).

## Tham khảo

- [Trino — TLS and HTTPS](https://trino.io/docs/current/security/tls.html)
- [Trino — Secure internal communication](https://trino.io/docs/current/security/internal-communication.html)
- [mkcert](https://github.com/FiloSottile/mkcert)
