# Secret cục bộ

Thư mục này chỉ giữ tài liệu và template trơ trong Git. Các file secret thật bị `.gitignore` loại trừ.

Trước khi khởi động stack, cần tạo:

```text
secrets/
|-- certs/
|   |-- trino.localhost-key.pem
|   `-- trino.localhost.pem
`-- trino-secrets/
    `-- password.db
```

- Tạo certificate bằng `mkcert` theo README ở thư mục gốc. Không chia sẻ private key hoặc CA key.
- Tạo `password.db` bằng `htpasswd` với bcrypt cost tối thiểu `8`; dự án dùng cost `10` trong lệnh mẫu.
- Mỗi dòng password store có dạng `username:bcrypt-hash`. Không lưu plain-text password.
- `password.db.example` chỉ mô tả định dạng và không chứa credential có thể đăng nhập.

Nginx mount `secrets/certs` ở chế độ read-only. Trino coordinator mount `secrets/trino-secrets` ở chế độ read-only; worker không cần password store vì authentication của client diễn ra tại coordinator.

## References

- [Trino password file authentication](https://trino.io/docs/current/security/password-file.html)
- [mkcert](https://github.com/FiloSottile/mkcert)
