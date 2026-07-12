# Xác thực bằng password file cho Trino

> Tóm tắt theo [Password file authentication — Trino current](https://trino.io/docs/current/security/password-file.html) (trang hiển thị Trino 482 khi đối chiếu ngày 2026-07-11).

Password file authentication xác thực username/password của client bằng hash trong một file. Nó là **authentication**, không phải authorization: sau khi user đăng nhập, cần thêm access control (ví dụ [FILE_SYSTEM_ACCESS_CONTROL.md](FILE_SYSTEM_ACCESS_CONTROL.md)) để giới hạn catalog, schema và table.

## 1. Điều kiện bảo mật bắt buộc

Theo Trino, password authentication cần:

- TLS/HTTPS cho client → coordinator;
- shared secret cấu hình đồng nhất trên mọi node.

Lab này dùng HTTPS qua Nginx theo [TLS_HTTPS_LOCAL.md](TLS_HTTPS_LOCAL.md). Trước khi bật/đánh giá password login, bảo đảm `8080:8080` đã bị bỏ khỏi service `trino`: nếu coordinator còn public HTTP trực tiếp thì người dùng có thể bỏ qua lớp proxy/HTTPS.

Shared secret đang nằm literal trong các file tracked của lab hiện tại phải được coi là đã lộ. Rotate và chuyển nó sang cơ chế secret/config ngoài Git trước khi dùng ngoài môi trường lab.

> Không bật `http-server.authentication.allow-insecure-over-http=true` chỉ để giải quyết lỗi kết nối. Hãy sửa topology để client chỉ đến HTTPS proxy.

## 2. Tạo password file ngoài Git

Repository mount `./secrets/trino-secrets` vào `/etc/trino-secrets` của coordinator. Dùng **đúng một** thư mục này cho mọi lệnh:

```powershell
New-Item -ItemType Directory -Force secrets\trino-secrets
docker run --rm -it -v "${PWD}\secrets\trino-secrets:/work" httpd:2.4-alpine `
  htpasswd -B -C 10 -c /work/password.db admin
```

`-B` tạo bcrypt và `-C 10` đặt cost 10; Trino yêu cầu bcrypt có cost tối thiểu là 8. `-c` chỉ dùng khi tạo file lần đầu vì nó có thể ghi đè file hiện có.

Thêm hoặc đổi password user (bỏ `-c`):

```powershell
docker run --rm -it -v "${PWD}\secrets\trino-secrets:/work" httpd:2.4-alpine `
  htpasswd -B -C 10 /work/password.db analyst
```

Xóa user:

```powershell
docker run --rm -it -v "${PWD}\secrets\trino-secrets:/work" httpd:2.4-alpine `
  htpasswd -D /work/password.db analyst
```

Password file có một dòng `username:password-hash` cho mỗi user. Trino chỉ chấp nhận bcrypt hoặc PBKDF2; không lưu mật khẩu rõ. Giữ `secrets/` trong `.gitignore`, giới hạn quyền đọc file và không đưa password/hash vào log.

## 3. Cấu hình password authenticator trên coordinator

Tạo `trino/etc/password-authenticator.properties`:

```properties
password-authenticator.name=file
file.password-file=/etc/trino-secrets/password.db
# Tùy chọn: mặc định là 5s; có thể bỏ dòng này để dùng mặc định.
file.refresh-period=5s
```

Các property cần nhớ:

| Property | Ý nghĩa |
| --- | --- |
| `file.password-file` | Đường dẫn password file trong container. |
| `file.refresh-period` | Chu kỳ nạp lại file; mặc định `5s`. |
| `file.auth-token-cache.max-size` | Số password đã xác thực được cache; mặc định `1000`. |

Chỉ cấu hình authenticator trên coordinator. Không thêm `password-authenticator.properties` vào worker.

## 4. Bật kiểu xác thực PASSWORD

Trong `trino/etc/config.properties` của coordinator:

```properties
http-server.authentication.type=PASSWORD
```

Giữ shared secret ở tất cả node theo tài liệu internal communication; không sao chép giá trị secret vào Markdown hay Git.

## 5. Mount password file chỉ-đọc

Trong service `trino` của `docker-compose.yaml`:

```yaml
  trino:
    # ...
    volumes:
      - "./trino/etc:/etc/trino:ro"
      - "./secrets/trino-secrets:/etc/trino-secrets:ro"
```

Không mount `password.db` dưới `/etc/trino`: thư mục này đã được mount chỉ-đọc. Mount riêng ở `/etc/trino-secrets` cho phép Trino đọc hash mà không sửa file host.

## 6. Khởi động và xác minh

Sau khi đổi `config.properties` hoặc thêm authenticator, recreate services:

```powershell
docker compose config --quiet
docker compose up -d --force-recreate trino trino-worker-1 trino-worker-2 nginx
docker compose ps
docker compose logs trino
```

Mở `https://trino.localhost/ui`, đăng nhập bằng `admin` và password vừa tạo, rồi thử password sai để xác nhận bị từ chối.

Kiểm tra bằng CLI qua HTTPS:

```powershell
trino --server https://trino.localhost --user admin --password
```

```sql
SELECT current_user;
```

Sau khi file authenticator đã được nạp, thêm/đổi/xóa user trong `password.db` thường không cần restart coordinator vì Trino đọc lại theo `file.refresh-period`.

## 7. Checklist vận hành

- [ ] Client chỉ truy cập HTTPS proxy; không còn host port `8080` public.
- [ ] Shared secret giống nhau trên coordinator và worker.
- [ ] `password.db` dùng bcrypt/PBKDF2, không chứa password rõ.
- [ ] `password.db` nằm ở `secrets/trino-secrets`, bị Git bỏ qua và mount chỉ-đọc.
- [ ] Password authenticator và `http-server.authentication.type=PASSWORD` chỉ có trên coordinator.
- [ ] Đã cấu hình access control nếu user không được phép thấy toàn bộ dữ liệu.

## Tham khảo

- [Trino — Password file authentication](https://trino.io/docs/current/security/password-file.html)
- [Trino — TLS and HTTPS](https://trino.io/docs/current/security/tls.html)
- [Trino — Secure internal communication](https://trino.io/docs/current/security/internal-communication.html)
