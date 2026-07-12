# Group mapping cho Trino

> Tóm tắt theo [Group mapping — Trino current](https://trino.io/docs/current/security/group-mapping.html) (trang hiển thị Trino 482 khi đối chiếu ngày 2026-07-12).

Group provider ánh xạ username vào các group để access control và resource group management có thể cấp quyền theo nhóm thay vì từng user. Nó không tạo authentication, role hay quyền; sau khi provider trả group, system access control mới quyết định user được làm gì.

## 1. Trạng thái và phạm vi trong lab này

Group provider được cấu hình bằng `etc/group-provider.properties` trên **coordinator**. Giá trị `group-provider.name` chỉ có thể là `file` hoặc `ldap`; toàn bộ config của provider đã chọn nằm trong cùng file này.

> File ACL hiện có selector group như `finance|human_resources`, nhưng repository chưa có `group-provider.properties` hay group file. Vì vậy các rule dựa vào group chưa có nguồn membership để khớp như mong đợi. Tạo provider là bước cần thiết trước khi dựa vào những rule đó.

User mapping và group mapping phải dùng cùng username chuẩn hóa. Nếu [USER_MAPPING.md](USER_MAPPING.md) chuyển `alice@example.com` thành `alice`, group file/LDAP phải có member `alice`, không phải email gốc.

## 2. Property chung

```properties
group-provider.name=file
```

| Property | Giá trị/ý nghĩa |
| --- | --- |
| `group-provider.name` | `file` hoặc `ldap`. |
| `group-provider.group-case` | Chuẩn hóa tên group: `keep` (mặc định), `upper`, hoặc `lower`. |

Chọn một quy ước case và dùng nhất quán trong group source lẫn access-control regex. Ví dụ group file trả `finance` nhưng ACL tìm `FINANCE` sẽ không khớp nếu không chuẩn hóa phù hợp.

## 3. File group provider

Phù hợp với lab nhỏ hoặc group membership được quản lý cùng cấu hình. Cấu hình Trino tối thiểu:

```properties
group-provider.name=file
file.group-file=/path/to/group.txt
```

`file.refresh-period` là chu kỳ đọc lại group file, mặc định `5s`.

Trong Docker Compose của repository này, đặt file dưới `trino/etc` (được mount read-only vào `/etc/trino`) và dùng path tuyệt đối trong container:

```properties
group-provider.name=file
group-provider.group-case=lower
file.group-file=/etc/trino/group.txt
file.refresh-period=5s
```

### Định dạng group file

Mỗi dòng là một group, dấu `:` ngăn cách group và members; members cách nhau bằng dấu phẩy:

```text
group_name:user_1,user_2,user_3
```

Ví dụ dùng cùng convention lower-case với ACL:

```text
finance:alice,bob
human_resources:carol
```

Sau khi file được nạp, cập nhật membership thường có hiệu lực trong vòng `file.refresh-period`; thay đổi `group-provider.properties` vẫn nên recreate coordinator.

## 4. LDAP group provider

Dùng LDAP khi group membership đã được quản lý tập trung. Bắt đầu bằng:

```properties
group-provider.name=ldap
```

### Property LDAP quan trọng

| Nhóm | Property |
| --- | --- |
| Kết nối | `ldap.url` (`ldap://host:389` hoặc `ldaps://host:636`), `ldap.allow-insecure` (mặc định `false`), `ldap.timeout.connect`/`ldap.timeout.read` (mặc định `1m`). |
| TLS tới LDAP | `ldap.ssl.keystore.path`, `ldap.ssl.keystore.password`, `ldap.ssl.truststore.path`, `ldap.ssl.truststore.password`. |
| Bind/tìm user | `ldap.admin-user`, `ldap.admin-password`, `ldap.user-base-dn`, `ldap.user-search-filter`. `{0}` trong filter được thay bằng username Trino. |
| Tên group | `ldap.group-name-attribute`, ví dụ `cn`. |
| Referral | `ldap.ignore-referrals` (mặc định `false`). |

Không ghi password LDAP thật trong file tracked. Nếu `group-provider.properties` cần bind credential, mount một file config/secret ngoài Git hoặc dùng cơ chế secrets phù hợp. Ưu tiên `ldaps://` hoặc truststore phù hợp; không bật `ldap.allow-insecure=true` để “sửa” lỗi certificate.

### Chọn cách resolve group

`ldap.use-group-filter` mặc định `true`:

| Cách | Property bắt buộc |
| --- | --- |
| Search-based (mặc định) | `ldap.group-base-dn`, `ldap.group-search-filter`, `ldap.group-search-member-attribute`. Trino tìm group entries có user DN là member. |
| Attribute-based | Đặt `ldap.use-group-filter=false` và cấu hình `ldap.user-member-of-attribute`, thường là `memberOf`. Trino đọc danh sách group từ user attribute. |

### Mẫu OpenLDAP: search-based

```properties
group-provider.name=ldap
group-provider.group-case=lower

ldap.url=ldap://ldap.example.com:389
ldap.admin-user=cn=admin,dc=example,dc=com
ldap.admin-password=your_password
ldap.group-name-attribute=cn
ldap.user-base-dn=ou=users,dc=example,dc=com
ldap.user-search-filter=(uid={0})
ldap.use-group-filter=true
ldap.group-base-dn=ou=groups,dc=example,dc=com
ldap.group-search-filter=(cn=trino_*)
ldap.group-search-member-attribute=member
```

### Mẫu Active Directory: attribute-based, single query

```properties
group-provider.name=ldap
group-provider.group-case=lower

ldap.url=ldaps://ad.example.com:636
ldap.admin-user=cn=admin,dc=example,dc=com
ldap.admin-password=your_password
ldap.group-name-attribute=cn
ldap.user-base-dn=ou=users,dc=example,dc=com
ldap.user-search-filter=(sAMAccountName={0})
ldap.use-group-filter=false

ldap.user-member-of-attribute=memberOf
```

Các giá trị DN, attribute và filter phụ thuộc LDAP schema thực tế; không copy nguyên mẫu vào production.

## 5. Dùng group trong access control

Trino chuyển group đã resolve đến system access control. File ACL có thể dùng `group` regex, ví dụ:

```json
{
  "catalogs": [
    {
      "group": "finance|human_resources",
      "catalog": "hive",
      "allow": "read-only"
    }
  ]
}
```

Đây chỉ là ví dụ. Quy tắc hiện tại trong repository có catalog mẫu không hoàn toàn trùng catalog thực tế; hãy điều chỉnh catalog, schema/table và group theo environment trước khi kiểm thử. Xem [FILE_SYSTEM_ACCESS_CONTROL.md](FILE_SYSTEM_ACCESS_CONTROL.md) để biết thứ tự rule “first match wins”.

## 6. Kiểm thử

1. Tạo `group-provider.properties` và, nếu dùng file provider, `group.txt` dưới `trino/etc`.
2. Recreate coordinator sau khi đổi provider config:

   ```powershell
   docker compose config --quiet
   docker compose up -d --force-recreate trino nginx
   docker compose logs trino
   ```

3. Đăng nhập bằng user thuộc một group đã biết qua HTTPS, rồi chạy:

   ```sql
   SELECT current_user;
   ```

4. Thử một query mà file ACL cho phép group đó trên **catalog thực tế**, và thử một user không thuộc group để xác nhận bị từ chối.

## 7. Checklist

- [ ] Chọn duy nhất một provider: `file` hoặc `ldap`.
- [ ] Provider config chỉ nằm trên coordinator.
- [ ] Username trong group source khớp username sau authentication/user mapping.
- [ ] Case của group nhất quán với ACL regex.
- [ ] LDAP URL/TLS/truststore và bind credential được bảo vệ; không commit secret.
- [ ] ACL rule dùng đúng catalog/schema/table trong lab, không chỉ mẫu từ tài liệu.
- [ ] Đã test allow và deny bằng user thật qua HTTPS.

## Tham khảo

- [Trino — Group mapping](https://trino.io/docs/current/security/group-mapping.html)
- [Trino — User mapping](https://trino.io/docs/current/security/user-mapping.html)
- [Trino — File-based access control](https://trino.io/docs/current/security/file-system-access-control.html)
