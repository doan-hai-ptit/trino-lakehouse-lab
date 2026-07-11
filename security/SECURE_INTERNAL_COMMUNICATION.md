# Bật Secure Internal Communication cho Trino

Hướng dẫn này bật xác thực nội bộ bằng shared secret và mã hóa TLS cho lưu lượng giữa Trino coordinator và workers. Phạm vi là **node-to-node traffic**; TLS/HTTPS từ client đến coordinator là cấu hình riêng (lab hiện có tài liệu `TLS_HTTPS_LOCAL.md`).

Theo tài liệu Trino, shared secret là bắt buộc khi đã bật internal TLS; mọi node phải dùng cùng secret và cùng cấu hình TLS. Node cấu hình sai sẽ không thể đăng ký/trao đổi với coordinator.

> Cần có thời gian dừng dịch vụ: việc này yêu cầu khởi động lại coordinator và tất cả worker.

## 1. Chuẩn bị địa chỉ IP cố định cho coordinator

Internal TLS tự tạo certificate của Trino chỉ hỗ trợ **địa chỉ IP**, không hỗ trợ hostname/FQDN trong `discovery.uri`. Vì vậy không dùng `https://trino:8443` trong cấu hình mới.

Với Docker Compose, đặt IP tĩnh cho service `trino` trên một mạng riêng. Ví dụ, thêm/cập nhật phần sau trong `docker-compose.yaml` (giữ nguyên các service và volume hiện có):

```yaml
services:
  trino:
    networks:
      trino-internal:
        ipv4_address: 172.28.0.10

  trino-worker-1:
    networks:
      - trino-internal

  trino-worker-2:
    networks:
      - trino-internal

networks:
  trino-internal:
    ipam:
      config:
        - subnet: 172.28.0.0/24
```

Nếu file Compose đã khai báo mạng, chỉ cần thêm `ipv4_address: 172.28.0.10` cho coordinator và đảm bảo subnet không trùng với mạng Docker đang tồn tại. Thay `172.28.0.10` trong toàn bộ hướng dẫn bằng IP bạn chọn.

## 2. Tạo shared secret

Tạo secret dài, ngẫu nhiên một lần rồi lưu ở secret manager hoặc nơi chỉ quản trị viên đọc được. Không commit secret vào Git và không ghi ra log.

Trên Linux/macOS có OpenSSL:

```bash
openssl rand 512 | base64
```

Trên PowerShell, tạo chuỗi Base64 ngẫu nhiên tương đương:

```powershell
[Convert]::ToBase64String([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(512))
```

Sao chép toàn bộ giá trị kết quả; ví dụ dưới đây gọi nó là `<SHARED_SECRET>`.

## 3. Cập nhật cấu hình của mọi node

Chọn một HTTPS port nội bộ chưa sử dụng, ví dụ `8443`. Trong **cả ba** file dưới đây, thêm các dòng giống nhau và đổi `discovery.uri` sang IP tĩnh của coordinator:

- `trino/etc/config.properties`
- `trino-worker-1/etc/config.properties`
- `trino-worker-2/etc/config.properties`

```properties
# Bắt buộc: cùng một giá trị trên coordinator và mọi worker
internal-communication.shared-secret=<SHARED_SECRET>

# Bật TLS tự động cho communication nội bộ
internal-communication.https.required=true

# Chỉ dùng IP của coordinator, không dùng hostname/FQDN
discovery.uri=https://172.28.0.10:8443

# Mở HTTPS endpoint trên từng node
http-server.https.enabled=true
http-server.https.port=8443
```

Lưu ý:

- Giữ lại `coordinator=true` (và các thiết lập scheduler) của coordinator; workers giữ `coordinator=false`.
- `http-server.http.port=8080` có thể vẫn giữ nếu bạn còn dùng HTTP endpoint/proxy cho client. Internal communication sẽ dùng HTTPS sau khi `internal-communication.https.required=true` được bật.
- Các file phải có cùng `internal-communication.shared-secret`, `internal-communication.https.required`, HTTPS port và `discovery.uri` (trừ các dòng vai trò riêng của từng node).
- Không cần tự tạo hoặc phân phối certificate: Trino tự tạo certificate và trust configuration cho TLS nội bộ.

Ví dụ cấu hình tối thiểu của coordinator sau khi cập nhật:

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

Ví dụ worker (thay `node.id` trong `node.properties` là riêng biệt như hiện tại):

```properties
coordinator=false
http-server.http.port=8080
http-server.https.enabled=true
http-server.https.port=8443
discovery.uri=https://172.28.0.10:8443
internal-communication.shared-secret=<SHARED_SECRET>
internal-communication.https.required=true
```

## 4. Kiểm tra và khởi động lại cluster

Kiểm tra cú pháp Compose rồi khởi động lại toàn bộ node để các giá trị mới được áp dụng nhất quán:

```powershell
docker compose config --quiet
docker compose up -d --force-recreate
docker compose ps
```

Nếu worker không lên, xem log từng node:

```powershell
docker compose logs trino
docker compose logs trino-worker-1
docker compose logs trino-worker-2
```

## 5. Xác minh shared secret và TLS nội bộ

1. Mở Trino Web UI rồi xác nhận số `ACTIVE WORKERS` bằng số worker được cấu hình (với lab này là 2).
2. Hoặc chạy query từ CLI/Web UI:

   ```sql
   SELECT node_id, coordinator, state
   FROM system.runtime.nodes;
   ```

   Kết quả phải có coordinator và 2 worker ở trạng thái `active`.
3. Để kiểm tra xác thực thực sự hoạt động (chỉ làm trong môi trường lab), đổi shared secret của một worker, khởi động lại worker đó, rồi kiểm tra số `ACTIVE WORKERS` giảm đi 1. Worker có secret sai không được coordinator xác thực và không đăng ký được.
4. Khôi phục secret đúng, khởi động lại worker (hoặc toàn cluster) và xác nhận đầy đủ workers quay lại `active`.

## Hiệu năng và tinh chỉnh tùy chọn

TLS làm tăng chi phí CPU và có thể làm chậm đáng kể các query trao đổi nhiều dữ liệu giữa node, như distributed join, aggregation hoặc window function. Truy vấn ít truyền dữ liệu, ví dụ `SELECT count(*) FROM table`, thường chịu ảnh hưởng nhỏ hơn.

Trino mặc định dùng HTTP/2 cho internal TLS. Nếu cần chẩn đoán tương thích/hiệu năng, có thể tắt trên **mọi node**:

```properties
internal-communication.http2.enabled=false
```

Với mạng băng thông rất cao, `/dev/urandom` có thể thành nút thắt. Tài liệu Trino gợi ý thử cấu hình sau trên coordinator và tất cả workers:

```properties
http-server.https.secure-random-algorithm=SHA1PRNG
```

Nếu máy không có đủ entropy để seed `SHA1PRNG`, thêm dòng sau vào `etc/jvm.config` của mọi node:

```text
-Djava.security.egd=file:/dev/urandom
```

Chỉ áp dụng phần tinh chỉnh này sau khi đo đạc; không cần cho đa số môi trường Docker local.

## Checklist trước khi hoàn tất

- [ ] Coordinator có IP nội bộ cố định.
- [ ] `discovery.uri` dùng `https://<IP-coordinator>:8443`, không dùng hostname/FQDN.
- [ ] Shared secret mạnh, giống hệt nhau trên mọi node, không bị commit.
- [ ] HTTPS endpoint được bật trên coordinator và mọi worker.
- [ ] Tất cả node được khởi động lại.
- [ ] Web UI hoặc `system.runtime.nodes` hiển thị đủ 2 workers `active`.

## Nguồn tham khảo

- [Trino 482 — Secure internal communication](https://trino.io/docs/current/security/internal-communication.html)
- [Trino — TLS and HTTPS](https://trino.io/docs/current/security/tls.html)
