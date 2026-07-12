# Secure internal communication cho Trino

> Tóm tắt theo [Secure internal communication — Trino current](https://trino.io/docs/current/security/internal-communication.html) (trang hiển thị Trino 482 khi đối chiếu ngày 2026-07-11).

Tài liệu này bảo vệ traffic **node-to-node** trong Trino: xác thực node bằng shared secret và, nếu bật, mã hóa traffic coordinator ↔ worker bằng TLS tự động. Nó khác với HTTPS cho client; hướng dẫn frontend proxy nằm ở [TLS_HTTPS_LOCAL.md](TLS_HTTPS_LOCAL.md).

> **Trạng thái repository hiện tại:** internal TLS chưa được bật. Các node vẫn discovery qua `http://trino:8080` và chưa có `internal-communication.https.required=true`. Hướng dẫn này là cấu hình mục tiêu, không tự sửa Compose hay các file config.

> **Shared secret hiện tại cần được coi là đã lộ:** repository đang lưu một giá trị literal trong các `config.properties` được Git theo dõi. Trước khi dùng ngoài lab, hãy rotate secret, gỡ secret khỏi file tracked và nạp nó qua cơ chế secret/config được bỏ qua bởi Git.

## 1. Khi nào shared secret là bắt buộc

Trino yêu cầu cùng một shared secret trên **mọi node** khi:

- dùng bất kỳ client authentication nào trên coordinator (password file, OAuth, LDAP, ...); hoặc
- bật TLS cho internal communication.

Node có secret khác sẽ không được coordinator xác thực/đăng ký. Shared secret xác thực node; nó không tự mã hóa traffic. Để mã hóa traffic nội bộ cần bật `internal-communication.https.required=true`.

## 2. Điều kiện và mạng Docker

Internal TLS tự tạo certificate và trust configuration. Vì cơ chế này chỉ hỗ trợ **IP address**, `discovery.uri` phải dùng IP của coordinator — không dùng hostname/FQDN như `https://trino:8443`.

Chọn một subnet Docker chưa dùng và gắn IP cố định cho coordinator. Trong project này, coordinator và worker còn cần nói chuyện với Nginx, Hive Metastore và MinIO trên network `default`. Vì vậy không thay thế `default` bằng một network mới; dùng **cả hai** network:

```yaml
services:
  trino:
    networks:
      default:
      trino-internal:
        ipv4_address: 172.28.0.10

  trino-worker-1:
    networks:
      - default
      - trino-internal

  trino-worker-2:
    networks:
      - default
      - trino-internal

networks:
  trino-internal:
    ipam:
      config:
        - subnet: 172.28.0.0/24
```

Thay `172.28.0.10` và `172.28.0.0/24` bằng dải không trùng với network Docker đang có. Giữ `default` để các hostname service hiện hữu như `trino`, `hive-metastore` và `minio` tiếp tục hoạt động.

## 3. Tạo shared secret

Tạo một secret dài, ngẫu nhiên và lưu trong secret manager hoặc vị trí chỉ quản trị viên đọc. Không commit, không in ra log và không dùng giá trị thật trong tài liệu.

Lệnh Trino nêu cho Linux/macOS:

```bash
openssl rand 512 | base64
```

Tương đương trên PowerShell:

```powershell
[Convert]::ToBase64String([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(512))
```

Gọi giá trị kết quả là `<SHARED_SECRET>` trong các block dưới.

## 4. Cấu hình đồng nhất cho mọi node

Chọn một HTTPS port nội bộ, ví dụ `8443`. Cập nhật **cả ba** file:

- `trino/etc/config.properties`
- `trino-worker-1/etc/config.properties`
- `trino-worker-2/etc/config.properties`

Các dòng internal TLS bắt buộc:

```properties
internal-communication.shared-secret=<SHARED_SECRET>
internal-communication.https.required=true
discovery.uri=https://172.28.0.10:8443
http-server.https.enabled=true
http-server.https.port=8443
```

Các giá trị secret, URI và HTTPS port phải giống hệt nhau trên coordinator/worker. Trino tự tạo certificate nên không cần tự phân phối certificate hay truststore.

Ví dụ coordinator sau khi thêm internal TLS (giữ các property khác của coordinator, gồm authentication, catalog và proxy nếu có):

```properties
coordinator=true
node-scheduler.include-coordinator=true
http-server.http.port=8080
http-server.https.enabled=true
http-server.https.port=8443
http-server.process-forwarded=true
discovery.uri=https://172.28.0.10:8443
internal-communication.shared-secret=<SHARED_SECRET>
internal-communication.https.required=true
```

Ví dụ worker:

```properties
coordinator=false
http-server.http.port=8080
http-server.https.enabled=true
http-server.https.port=8443
discovery.uri=https://172.28.0.10:8443
internal-communication.shared-secret=<SHARED_SECRET>
internal-communication.https.required=true
```

Có thể giữ `http-server.http.port=8080` vì Nginx vẫn forward frontend traffic đến coordinator qua HTTP. Tuy nhiên, khi mô hình frontend là HTTPS-only, không publish `8080` ra host; xem [TLS_HTTPS_LOCAL.md](TLS_HTTPS_LOCAL.md).

## 5. Triển khai và xác minh

Việc đổi discovery URI/TLS cần restart mọi node. Trước khi áp dụng, kiểm tra Compose:

```powershell
docker compose config --quiet
docker compose up -d --force-recreate trino trino-worker-1 trino-worker-2 nginx
docker compose ps
```

Nếu worker không lên, xem log:

```powershell
docker compose logs trino
docker compose logs trino-worker-1
docker compose logs trino-worker-2
```

Xác minh bằng Web UI hoặc CLI:

```sql
SELECT node_id, coordinator, state
FROM system.runtime.nodes;
```

Lab phải hiển thị một coordinator và hai worker `active`. Trino cũng đề xuất test shared secret theo cách có kiểm soát: đổi secret của một worker, restart worker đó và xác nhận số `ACTIVE WORKERS` giảm một; sau đó khôi phục secret và xác nhận worker đăng ký lại.

## 6. Hiệu năng và tinh chỉnh tùy chọn

TLS nội bộ có overhead CPU. Các query truyền ít dữ liệu giữa node (ví dụ `SELECT count(*) FROM table`) thường ít ảnh hưởng hơn; distributed join, aggregation và window function có thể chậm đáng kể. Đo đạc trước khi tinh chỉnh.

Khi internal TLS bật, Trino mặc định dùng HTTP/2. Nếu cần chẩn đoán tương thích/hiệu năng, tắt trên **mọi node**:

```properties
internal-communication.http2.enabled=false
```

Trong môi trường băng thông rất cao, nguồn entropy có thể thành nút thắt. Trino gợi ý thử trên coordinator và mọi worker:

```properties
http-server.https.secure-random-algorithm=SHA1PRNG
```

Nếu host Linux thiếu entropy để seed `SHA1PRNG`, thêm vào `etc/jvm.config` của mọi node:

```text
-Djava.security.egd=file:/dev/urandom
```

Các tinh chỉnh này không cần cho hầu hết lab Docker local và chỉ nên dùng sau khi có số liệu đo.

## 7. Checklist vận hành

- [ ] Coordinator có IP cố định trên network `trino-internal`.
- [ ] `default` vẫn được giữ cho Nginx, Hive Metastore, MinIO và các service khác.
- [ ] `discovery.uri` dùng `https://<IP-coordinator>:<https-port>`, không dùng hostname/FQDN.
- [ ] Mọi node dùng cùng shared secret và secret không bị commit.
- [ ] HTTPS endpoint/TLS internal được bật trên coordinator lẫn worker.
- [ ] Tất cả node đã restart và hiển thị đủ worker `active`.

## Tham khảo

- [Trino — Secure internal communication](https://trino.io/docs/current/security/internal-communication.html)
- [Trino — TLS and HTTPS](https://trino.io/docs/current/security/tls.html)
