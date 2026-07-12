# User mapping cho Trino

> Tóm tắt theo [User mapping — Trino current](https://trino.io/docs/current/security/user-mapping.html) (trang hiển thị Trino 482 khi đối chiếu ngày 2026-07-12).

User mapping chuyển identity do cơ chế authentication trả về thành username đơn giản mà Trino dùng nội bộ. Nó đặc biệt hữu ích khi identity có dạng `alice@example.com`, Kerberos principal hoặc certificate subject như `CN=Alice Smith,...`.

User mapping là bước **sau xác thực**, không thay thế password file, OAuth, Kerberos hay access control. Username sau mapping là username được các rule access control và group provider sử dụng.

Với password-file authentication, password file kiểm tra **username đầu vào** trước, rồi user mapping mới đổi principal đã xác thực thành Trino user. Vì vậy mapping `alice@example.com → alice` cần entry `alice@example.com` trong `password.db`, còn group file và ACL rule dùng `alice`.

## 1. Khi nào cần dùng trong lab này

Coordinator hiện dùng `PASSWORD` authentication với các username đơn giản trong password file, nên user mapping **chưa cần thiết** nếu giữ các username local hiện có.

Chỉ thêm mapping khi authentication provider trả về tên phức tạp (ví dụ email) nhưng policy/nhóm muốn dùng tên chuẩn hóa (ví dụ `alice`). Cấu hình mapping thuộc **coordinator** trong `trino/etc/config.properties`; không thêm vào worker.

> Trước khi test qua password authentication, dùng endpoint HTTPS `https://trino.localhost` và bảo đảm host port `8080` không còn public theo [TLS_HTTPS_LOCAL.md](TLS_HTTPS_LOCAL.md).

## 2. Chọn một trong hai cách mapping

| Cách | Phù hợp khi | Hành vi khi không khớp |
| --- | --- | --- |
| Pattern mapping | Mọi username cùng một format regex. | Authentication bị từ chối. |
| File mapping rules | Có nhiều format, cần ngoại lệ hoặc cần chặn một số identity. | Authentication bị từ chối. |

Cả hai đều dựa trên regex. Với một authentication type, chọn phương án phù hợp và kiểm thử bằng username thật trước khi triển khai rộng.

## 3. Pattern mapping rule

Pattern phải capture username đầu ra ở group đầu tiên; Trino dùng **capture group đầu tiên** (`$1`) làm username kết quả. Với username dạng email, mẫu Trino tách thành hai group để chuyển `alice@example.com` thành `alice`:

```properties
http-server.authentication.password.user-mapping.pattern=(.*)(@.*)
```

Nếu regex không khớp, user không thể đăng nhập. `PASSWORD` là authentication type dùng chung cho password-file, LDAP và Salesforce.

> Cảnh báo cho lab hiện tại: một email-only pattern như trên sẽ không khớp các username local không có `@` và vì thế từ chối họ. Không bật nó một mình nếu vẫn cần các account đó; dùng file rule có ngoại lệ/catch-all được review kỹ, hoặc chuyển password file sang username đầu vào phù hợp trước.

### Property theo authentication type

| Authentication type | Property pattern |
| --- | --- |
| Password (file, LDAP, Salesforce) | `http-server.authentication.password.user-mapping.pattern` |
| OAuth2 | `http-server.authentication.oauth2.user-mapping.pattern` |
| Certificate | `http-server.authentication.certificate.user-mapping.pattern` |
| Header | `http-server.authentication.header.user-mapping.pattern` |
| JSON Web Token | `http-server.authentication.jwt.user-mapping.pattern` |
| Kerberos | `http-server.authentication.krb5.user-mapping.pattern` |
| Insecure | `http-server.authentication.insecure.user-mapping.pattern` |

## 4. File mapping rules

Dùng file JSON khi cần nhiều rule hoặc một deny rule cụ thể. Rule được xử lý từ trên xuống dưới; **rule đầu tiên khớp** quyết định kết quả. Không có rule khớp thì authentication bị từ chối.

Mỗi rule gồm:

| Field | Bắt buộc | Ý nghĩa |
| --- | --- | --- |
| `pattern` | Có | Regex khớp username từ authentication provider. |
| `user` | Không | Chuỗi thay thế; mặc định là `$1`. Có thể dùng capture group đặt tên. |
| `allow` | Không | Boolean cho phép/từ chối identity đã khớp. |
| `case` | Không | `keep` (mặc định), `lower` hoặc `upper` cho username sau mapping. |

Mẫu Trino: chặn `test@example.com`, chuyển `alice@example.com` thành `alice`, dùng named group cho region, và chuẩn hóa một domain thành uppercase:

```json
{
    "rules": [
        {
            "pattern": "test@example\\.com",
            "allow": false
        },
        {
            "pattern": "(.+)@example\\.com"
        },
        {
            "pattern": "(?<user>.+)@(?<region>.+)\\.example\\.com",
            "user": "${user}_${region}"
        },
        {
            "pattern": "(.*)@uppercase.com",
            "case": "upper"
        }
    ]
}
```

### Liên kết file vào coordinator

Ví dụ chính thức cho authentication type `PASSWORD`:

```properties
http-server.authentication.password.user-mapping.file=etc/user-mapping.json
```

Trino chấp nhận path tuyệt đối hoặc path tương đối với thư mục cài đặt. Trong Docker Compose của repository này, đặt JSON tại `trino/etc/user-mapping.json` (đã được mount vào `/etc/trino`) và dùng path tuyệt đối để tránh nhầm thư mục gốc của image:

```properties
http-server.authentication.password.user-mapping.file=/etc/trino/user-mapping.json
```

Sau khi thêm/chuyển property mapping, recreate coordinator. Thay đổi nội dung JSON cần được kiểm thử; không giả định nó dùng refresh period của file ACL.

### Property file theo authentication type

| Authentication type | Property file |
| --- | --- |
| Password (file, LDAP, Salesforce) | `http-server.authentication.password.user-mapping.file` |
| OAuth2 | `http-server.authentication.oauth2.user-mapping.file` |
| Certificate | `http-server.authentication.certificate.user-mapping.file` |
| Header | `http-server.authentication.header.user-mapping.pattern` |
| JSON Web Token | `http-server.authentication.jwt.user-mapping.file` |
| Kerberos | `http-server.authentication.krb5.user-mapping.file` |
| Insecure | `http-server.authentication.insecure.user-mapping.file` |

> Trang Trino hiện liệt kê property Header là `...user-mapping.pattern` cả trong bảng file mapping. Kiểm tra tài liệu đúng version/authenticator trước khi áp dụng Header authentication.

## 5. Kiểm thử và liên hệ với ACL

1. Dùng một identity mà bạn biết username đầu vào và expected username sau mapping.
2. Đăng nhập qua HTTPS bằng CLI. Lệnh dưới là **ví dụ giả định**: password file phải có entry cho username đầu vào `alice@example.com` (hoặc dùng LDAP/certificate provider); password file hiện tại của lab không có identity email mẫu này.

   ```powershell
   trino --server https://trino.localhost --user alice@example.com --password
   ```

3. Kiểm tra username Trino thực nhận:

   ```sql
   SELECT current_user;
   ```

4. Kiểm thử một rule access control dựa trên username/group, ví dụ từ [FILE_SYSTEM_ACCESS_CONTROL.md](FILE_SYSTEM_ACCESS_CONTROL.md).

Đặt deny/ngoại lệ cụ thể trước allow rule rộng. Cẩn thận với `(.*)`: nó cho phép mọi username phù hợp và có thể làm identity ngoài dự kiến vào cluster.

## 6. Checklist

- [ ] Chỉ bật mapping khi authentication trả username cần chuẩn hóa.
- [ ] Mapping property nằm trên coordinator và đúng authentication type.
- [ ] Regex có capture group/JSON rule có kết quả username dự kiến.
- [ ] Rule deny cụ thể đứng trước rule allow rộng.
- [ ] Username đầu vào khớp entry của authenticator/password file; username **sau mapping** khớp group file/LDAP và access-control rule.
- [ ] Đã test `SELECT current_user` qua HTTPS với cả user cho phép và user bị từ chối.

## Tham khảo

- [Trino — User mapping](https://trino.io/docs/current/security/user-mapping.html)
- [Trino — Password file authentication](https://trino.io/docs/current/security/password-file.html)
- [Trino — File-based access control](https://trino.io/docs/current/security/file-system-access-control.html)
