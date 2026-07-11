# Bật xác thực bằng file mật khẩu cho Trino

Hướng dẫn này thêm đăng nhập bằng **tên người dùng + mật khẩu** cho Trino coordinator trong Docker Compose của project này. Mật khẩu chỉ được truyền qua HTTPS tại `https://trino.localhost`, nơi Nginx đang kết thúc TLS.

> Không dùng cơ chế này qua `http://localhost:8080`. Không mở lại cổng `8080` ra máy host, vì như vậy người dùng có thể bỏ qua lớp HTTPS/proxy.

## Điều kiện trước khi thực hiện

- Đã hoàn tất HTTPS theo [TLS_HTTPS_LOCAL.md](TLS_HTTPS_LOCAL.md). Cấu hình hiện tại đã có `http-server.process-forwarded=true`, và Nginx gửi `X-Forwarded-Proto: https`; đây là mô hình reverse proxy được Trino hỗ trợ.
- Shared secret phải giống nhau trên coordinator và mọi worker. Project hiện đã có `internal-communication.shared-secret` trong cả ba file cấu hình. Trino yêu cầu shared secret khi bật bất kỳ kiểu xác thực client nào.
- Docker Desktop đang chạy. Mọi lệnh PowerShell bên dưới chạy tại thư mục gốc project.

## 1. Tạo password file được bỏ qua bởi Git

Thư mục `secrets/` đã có trong `.gitignore`, nên password hash không bị commit. Tạo thư mục và tạo user đầu tiên (`admin`):

```powershell
New-Item -ItemType Directory -Force secrets\trino
docker run --rm -it -v "${PWD}\secrets\trino-secrets:/work" httpd:2.4-alpine `
  htpasswd -B -C 10 -c /work/password.db admin
```

Lệnh sẽ hỏi mật khẩu hai lần và tạo `secrets/trino/password.db`. Tùy chọn `-B` tạo bcrypt; `-C 10` đặt cost là 10 (Trino yêu cầu bcrypt có cost tối thiểu là 8). Không ghi mật khẩu dạng rõ vào file hay commit file này.

Để thêm user mới, **bỏ `-c`** (vì `-c` sẽ tạo lại và có thể ghi đè file):

```powershell
docker run --rm -it -v "${PWD}\secrets\trino-secrets:/work" httpd:2.4-alpine `
  htpasswd -B -C 10 /work/password.db analyst
```

Để đổi mật khẩu của user đã có, chạy lại lệnh thêm user với cùng tên. Xóa một user bằng:

```powershell
docker run --rm -it -v "${PWD}\secrets\trino-secrets:/work" httpd:2.4-alpine `
  htpasswd -D /work/password.db analyst
```

## 2. Tạo cấu hình password authenticator

Tạo file `trino/etc/password-authenticator.properties` với nội dung sau:

```properties
password-authenticator.name=file
file.password-file=/etc/trino-secrets/password.db
# Tùy chọn: mặc định là 5s; có thể bỏ dòng này để dùng mặc định.
file.refresh-period=5s
```

`password.db` có một dòng cho mỗi user theo dạng `username:password-hash`. Trino chỉ chấp nhận hash bcrypt hoặc PBKDF2; không tự lưu hay so sánh mật khẩu rõ.

## 3. Bật PASSWORD trên coordinator

Mở `trino/etc/config.properties` và thêm dòng sau (giữ nguyên các dòng có sẵn):

```properties
http-server.authentication.type=PASSWORD
```

Chỉ coordinator cần `password-authenticator.properties` và `http-server.authentication.type`. Không thêm cấu hình authenticator vào các worker.

## 4. Mount password file vào container coordinator

Trong service `trino` của `docker-compose.yaml`, mount thư mục chứa password file tại một đường dẫn **ngoài** `/etc/trino`:

```yaml
  trino:
    # ...
    volumes:
      - "./trino/etc:/etc/trino:ro"
      - "./secrets/trino-secrets:/etc/trino-secrets:ro"
```

Không mount bên dưới `/etc/trino`: thư mục này đã được mount chỉ-đọc, nên Docker không thể tạo mount point lồng nhau như `/etc/trino/password.db`. Mount thư mục ở trên chỉ-đọc, để Trino đọc hash nhưng không sửa file nguồn.

## 5. Kiểm tra và khởi động lại

```powershell
docker compose config --quiet
docker compose up -d --force-recreate trino trino-worker-1 trino-worker-2 nginx
docker compose ps
docker compose logs trino
```

Nếu Trino không khởi động, kiểm tra trước rằng file `secrets/trino/password.db` tồn tại và `trino/etc/password-authenticator.properties` có đúng tên authenticator là `file`.

## 6. Xác minh đăng nhập

1. Mở `https://trino.localhost/ui`. Nhập user `admin` và mật khẩu vừa tạo. Đăng nhập thành công sẽ hiển thị user ở góc trên phải.
2. Thử một mật khẩu sai; đăng nhập phải bị từ chối.
3. Dùng Trino CLI qua HTTPS:

   ```powershell
   trino --server https://trino.localhost --user admin --password
   ```

   Sau khi CLI hỏi mật khẩu, chạy:

   ```sql
   SELECT current_user;
   ```

## Vận hành và lưu ý bảo mật

- Trino tự nạp lại password file theo `file.refresh-period` (mặc định `5s`), nên thường không cần restart coordinator sau khi thêm/đổi/xóa user.
- `file.auth-token-cache.max-size` có mặc định là `1000`; chỉ cần cấu hình nếu cần giới hạn cache token đã xác thực.
- Password file authentication chỉ xác thực danh tính; nó chưa giới hạn catalog, schema, hay bảng. Khi cần phân quyền, cấu hình thêm system access control (ví dụ file-based access control).
- Secret hiện có trong các `config.properties` nên được thay bằng secret mới và đưa ra khỏi Git trước khi dùng ngoài môi trường lab.

## Tham khảo

- [Trino — Password file authentication](https://trino.io/docs/current/security/password-file.html)
- [Trino — TLS and HTTPS](https://trino.io/docs/current/security/tls.html)
- [Trino — Secure internal communication](https://trino.io/docs/current/security/internal-communication.html)
