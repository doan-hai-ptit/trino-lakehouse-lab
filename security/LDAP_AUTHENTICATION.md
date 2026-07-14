# Xác thực LDAP cho Trino

> Tóm tắt theo [LDAP authentication — Trino current](https://trino.io/docs/current/security/ldap.html) (trang hiển thị Trino 482 khi đối chiếu ngày 2026-07-13).

LDAP authentication xác thực người dùng frontend của Trino (CLI, JDBC và ODBC) với một dịch vụ LDAP bên ngoài. Client gửi username/password cho coordinator; coordinator thực hiện LDAP bind để kiểm tra thông tin đó. Hiện Trino chỉ hỗ trợ cơ chế LDAP simple authentication.

LDAP là **authentication**, không phải authorization cho catalog, schema hay table. Sau khi đăng nhập, dùng system access control phù hợp, chẳng hạn [file-based access control](FILE_SYSTEM_ACCESS_CONTROL.md), để giới hạn dữ liệu và thao tác. Nếu username LDAP cần chuẩn hóa trước khi dùng trong rule, xem thêm [user mapping](USER_MAPPING.md).

## 1. Điều kiện và phạm vi cấu hình

- Chỉ cấu hình LDAP trên **coordinator**; worker không cần `password-authenticator.properties`.
- Client phải truy cập coordinator qua TLS/HTTPS. LDAP authentication cũng yêu cầu shared secret được cấu hình cho giao tiếp nội bộ của Trino.
- Dùng `ldaps://` và truststore có certificate CA/server phù hợp. `ldap://` không mã hóa chỉ có thể dùng khi chủ động bật `ldap.allow-insecure=true`; không phù hợp cho môi trường production.
- Địa chỉ LDAP, DN, password bind, keystore và truststore là dữ liệu hạ tầng hoặc bí mật. Giữ chúng ngoài Git khi có thể và giới hạn quyền đọc các file chứa chúng.

## 2. Bật password authentication và HTTPS

LDAP là một password authenticator. Trước tiên hãy cấu hình TLS/HTTPS cho coordinator theo tài liệu TLS của Trino, rồi bật kiểu xác thực `PASSWORD`.

Thêm property sau vào `etc/config.properties` trên coordinator.

```properties
http-server.authentication.type=PASSWORD
```

`PASSWORD` cũng được dùng bởi password-file và Salesforce authentication. Password authenticator được cấu hình riêng trên coordinator.

### User mapping tùy chọn

Sau khi LDAP xác thực thành công, Trino có thể map username thành tên chuẩn dùng trong Trino. Chọn **một** trong hai cách: `http-server.authentication.password.user-mapping.pattern` hoặc `http-server.authentication.password.user-mapping.file`; không đặt đồng thời cả hai. Nếu pattern/rule không khớp, đăng nhập bị từ chối. Mặc định khi không cấu hình mapping là `(.*)`.

Thêm property sau vào `etc/config.properties` trên coordinator khi mọi username có cùng định dạng và cần lấy capture group đầu tiên làm Trino username.

```properties
http-server.authentication.password.user-mapping.pattern=(.*)(@.*)
```

Nếu cần nhiều rule hoặc ngoại lệ, tạo `etc/user-mapping.json` theo [USER_MAPPING.md](USER_MAPPING.md), rồi thêm `http-server.authentication.password.user-mapping.file=etc/user-mapping.json` vào `etc/config.properties` trên coordinator thay cho pattern.

## 3. Cấu hình LDAP password authenticator

Tạo `etc/password-authenticator.properties` trên coordinator và đặt cấu hình LDAP trong file đó. Ví dụ dưới đây dùng LDAPS, truststore PEM và cách bind kiểu Active Directory; thay hostname, đường dẫn truststore và domain bằng giá trị của hệ thống LDAP.

```properties
password-authenticator.name=ldap
ldap.url=ldaps://ldap-server:636
ldap.ssl.truststore.path=/path/to/ldap_server.pem
ldap.user-bind-pattern=${USER}@corp.example.com
```

Các property cần biết:

| Property | Ý nghĩa và mặc định |
| --- | --- |
| `ldap.url` | URL LDAP, có scheme `ldap://` hoặc `ldaps://`. Dùng `ldap://` cần `ldap.allow-insecure=true`. |
| `ldap.allow-insecure` | Cho phép kết nối LDAP không có TLS; mặc định không bật. |
| `ldap.ssl.keystore.path`, `ldap.ssl.keystore.password` | Keystore PEM hoặc JKS và password tương ứng, nếu LDAP server yêu cầu client certificate. |
| `ldap.ssl.truststore.path`, `ldap.ssl.truststore.password` | Truststore PEM hoặc JKS và password tương ứng để tin cậy certificate LDAP server. |
| `ldap.user-bind-pattern` | Pattern DN/login cho bind user; bắt buộc chứa `${USER}`. |
| `ldap.ignore-referrals` | Bỏ qua referral sang LDAP server khác khi search; mặc định `false`. |
| `ldap.cache-ttl` | Thời gian cache LDAP; mặc định `1h`. |
| `ldap.timeout.connect` | Timeout thiết lập kết nối; mặc định `1m`. |
| `ldap.timeout.read` | Timeout đọc từ kết nối LDAP; mặc định `1m`. |

`ldap.user-bind-pattern` có thể gồm nhiều pattern, ngăn cách bằng dấu `:`. Trino thử theo thứ tự khai báo và dừng khi một lần login thành công hoặc mọi pattern đều thất bại. Mỗi pattern phải chứa `${USER}`.

Tạo hoặc sửa `etc/password-authenticator.properties` trên coordinator với một trong các dạng bind sau, tùy LDAP server đang dùng.

```properties
ldap.user-bind-pattern=${USER}@<domain_name_of_the_server>
```

Với OpenLDAP, tạo hoặc sửa `etc/password-authenticator.properties` trên coordinator bằng DN của user.

```properties
ldap.user-bind-pattern=uid=${USER},<distinguished_name_of_the_user>
```

Ví dụ AD thường là `${USER}@corp.example.com`; ví dụ OpenLDAP là `uid=${USER},OU=America,DC=corp,DC=example,DC=com`.

## 4. Chỉ cho phép thành viên nhóm LDAP

Xác thực password thành công không tự động nghĩa là user được phép vào Trino. Để giới hạn login theo membership, thêm `ldap.user-base-dn` và `ldap.group-auth-pattern` vào cấu hình LDAP cơ bản. Query phải chứa `${USER}`; Trino thay thế biến này bằng username đang đăng nhập. Query thành công thì user được ủy quyền vào coordinator.

Thêm các property sau vào `etc/password-authenticator.properties` trên coordinator khi dùng authorization theo nhóm với bind của chính user.

```properties
ldap.user-base-dn=OU=America,DC=corp,DC=example,DC=com
ldap.group-auth-pattern=(&(objectClass=person)(sAMAccountName=${USER})(memberof=CN=AuthorizedGroup,OU=Asia,DC=corp,DC=example,DC=com))
```

Với Active Directory, pattern thường dùng `sAMAccountName`; với OpenLDAP, pattern thường dùng `uid`. Tạo hoặc sửa `etc/password-authenticator.properties` trên coordinator bằng ví dụ OpenLDAP sau khi group membership được biểu diễn qua `memberOf`.

```properties
ldap.group-auth-pattern=(&(objectClass=inetOrgPerson)(uid=${USER})(memberof=CN=AuthorizedGroup,OU=Asia,DC=corp,DC=example,DC=com))
```

Đối với OpenLDAP, cần bật `memberOf` overlay để query theo `memberOf` hoạt động. Pattern có thể biểu diễn điều kiện phức tạp, ví dụ user thuộc một trong nhiều group. Đặt các truy vấn LDAP cẩn thận: một match quá rộng sẽ cấp quyền login cho nhiều người hơn dự kiến.

## 5. Dùng LDAP service user để tra cứu group

Nếu user thông thường không có quyền search LDAP, Trino có thể dùng một service user. Khi đó Trino:

1. Bind bằng `ldap.bind-dn` và `ldap.bind-password` để chạy `ldap.group-auth-pattern`.
2. Lấy DN của user từ kết quả query nhóm.
3. Bind lại bằng DN đó và password do user cung cấp để xác thực password.

Đây là phương án thay cho việc dùng bind của user để tra cứu group. Trong `etc/password-authenticator.properties` trên coordinator, phải cấu hình đồng thời `ldap.bind-dn`, `ldap.bind-password` và `ldap.group-auth-pattern`; không ghi password thực vào tài liệu hoặc hệ thống quản lý mã nguồn. `ldap.group-auth-pattern` vẫn phải chứa `${USER}` và phải trả về đúng một user DN có thể dùng để bind.

## 6. Kiểm thử bằng Trino CLI

Client CLI cũng phải tin cậy certificate HTTPS của coordinator. Dùng keystore hoặc truststore phù hợp, truyền username LDAP và yêu cầu prompt password.

Chạy lệnh sau từ máy client, thay các placeholder bằng endpoint, certificate store, catalog, schema và user thực tế.

```text
./trino \
  --server https://trino-coordinator.example.com:8443 \
  --keystore-path /tmp/trino.jks \
  --keystore-password password \
  --truststore-path /tmp/trino_truststore.jks \
  --truststore-password password \
  --catalog <catalog> \
  --schema <schema> \
  --user <LDAP user> \
  --password
```

Sau khi đăng nhập, chạy `SELECT current_user;` để xác minh username Trino nhận được, đặc biệt nếu đã bật user mapping. Kiểm thử tối thiểu nên gồm:

- một user có password hợp lệ và thuộc nhóm được phép;
- user có password sai;
- user hợp lệ nhưng không thuộc nhóm được phép;
- username cần map, nếu có user mapping;
- một query bị access control từ chối, để xác minh authentication và authorization là hai lớp độc lập.

## 7. Khắc phục sự cố

- Kiểm tra nội dung và password của JKS/PEM bằng công cụ inspect/validate keystore của Trino; xác nhận truststore chứa CA/certificate đúng cho LDAP server và CLI tin cậy certificate của coordinator.
- Để xem lỗi giữa Trino và LDAP, thêm mức log sau vào cấu hình logging của Trino trong thời gian điều tra, rồi hạ lại sau khi xong.

  Thêm dòng sau vào `etc/log.properties` của Trino.

  ```text
  io.trino.plugin.password=DEBUG
  ```

- Nếu CLI gặp lỗi TLS, chạy executable JAR với `-Djavax.net.debug=ssl` để xem chi tiết SSL handshake.
- Lỗi `No subject alternative names present` thường nghĩa là certificate coordinator không có SAN khớp hostname/IP trong `--server`; cấp lại certificate với SAN phù hợp.
- Từ JDK 8u181, LDAPS kiểm tra endpoint identification chặt hơn. Lỗi `No subject alternative DNS name matching ... found` nên được sửa bằng certificate LDAP có SAN/subject khớp hostname. Có thể tạm thời tắt kiểm tra bằng `-Dcom.sun.jndi.ldap.object.disableEndpointIdentification=true` trong `jvm.config`, nhưng không nên dùng cách này ở production.

## 8. Checklist triển khai

- [ ] HTTPS/TLS đã được bật cho client → coordinator và shared secret đã được cấu hình cho toàn cluster.
- [ ] `http-server.authentication.type=PASSWORD` chỉ được đặt trên coordinator.
- [ ] `etc/password-authenticator.properties` có `password-authenticator.name=ldap`, `ldap.url` và bind pattern phù hợp AD/OpenLDAP.
- [ ] LDAPS, truststore và hostname/SAN certificate LDAP đã được kiểm tra.
- [ ] Chỉ bật `ldap.allow-insecure` nếu có lý do đặc biệt và đã chấp nhận rủi ro.
- [ ] Nếu giới hạn theo nhóm, `ldap.group-auth-pattern` có `${USER}` và được thử với user được phép lẫn user bị từ chối.
- [ ] DN/password của service user được quản lý như secret, nếu dùng service user.
- [ ] Đã kiểm thử CLI qua HTTPS, `SELECT current_user`, user mapping và policy authorization.

## References

- [Trino — LDAP authentication](https://trino.io/docs/current/security/ldap.html)
- [Trino — TLS and HTTPS](https://trino.io/docs/current/security/tls.html)
- [Trino — User mapping](https://trino.io/docs/current/security/user-mapping.html)
- [Trino — Secure internal communication](https://trino.io/docs/current/security/internal-communication.html)
