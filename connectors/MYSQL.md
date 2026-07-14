# MySQL connector cho Trino

> Tóm tắt theo [MySQL connector — Trino current](https://trino.io/docs/current/connector/mysql.html) (đối chiếu Trino 482 ngày 2026-07-14).

MySQL connector là JDBC connector cho phép Trino đọc, tạo và thay đổi dữ liệu/metadata trong MySQL bên ngoài. Nó phù hợp khi cần join MySQL với các catalog Trino khác, nhưng hiệu quả vẫn phụ thuộc vào pushdown, lượng dữ liệu truyền qua mạng và năng lực MySQL source.

## 1. Yêu cầu và phạm vi

- MySQL 5.7, 8.0 hoặc cao hơn.
- Coordinator và toàn bộ worker truy cập mạng được MySQL; cổng mặc định là `3306`.
- User JDBC có đúng quyền MySQL tối thiểu.
- Có thể tạo nhiều catalog, mỗi file `etc/catalog/<tên>.properties` cho một server/kết nối. Catalog name là tên file không có `.properties`.

## 2. Cách tạo catalog và TLS

Tạo `etc/catalog/mysql.properties` và đặt nội dung sau vào đó; thay URL, user và password bằng thông tin thực tế. Không commit password thật: dùng Trino secrets, credential provider hoặc secret manager phù hợp.

```properties
connector.name=mysql
connection-url=jdbc:mysql://example.net:3306
connection-user=root
connection-password=secret
```

MySQL Connector/J dùng `sslMode`; mặc định là `PREFERRED`, chỉ mã hóa nếu server hỗ trợ. Để bắt buộc TLS, sửa `connection-url` trong `etc/catalog/mysql.properties` theo ví dụ sau; connection sẽ fail nếu TLS không được thiết lập.

```properties
connection-url=jdbc:mysql://example.net:3306/?sslMode=REQUIRED
```

## 3. Credential provider và property kết nối

Credential provider nhận `INLINE` (mặc định), `FILE` hoặc `KEYSTORE`. Credential cũng có thể đến từ extra credentials khi client kết nối Trino.

| Property name | Ý nghĩa |
| --- | --- |
| `connection-user` / `connection-password` | User/password khi dùng inline credential. |
| `credential-provider.type` | Chọn `INLINE`, `FILE` hoặc `KEYSTORE`. |
| `user-credential-name` / `password-credential-name` | Extra credential name chứa user/password. |
| `connection-credential-file` | Properties file credential có `connection-user` và `connection-password`. |
| `keystore-file-path` / `keystore-type` / `keystore-password` | Đường dẫn, định dạng và password của keystore. |
| `keystore-user-credential-name` / `keystore-password-credential-name` | Entity keystore chứa user/password. |
| `keystore-user-credential-password` / `keystore-password-credential-password` | Password bảo vệ entity keystore tương ứng. |

TLS giữa Trino và MySQL không thay thế TLS/authentication của client đến Trino hay access control trong Trino. Không ghi secret và keystore password vào repository.

## 4. Property catalog quan trọng

| Property name | Mặc định | Ý nghĩa |
| --- | --- | --- |
| `case-insensitive-name-matching` | `false` | Cho phép matching schema/table không phân biệt hoa-thường. |
| `case-insensitive-name-matching.cache-ttl` | `1m` | TTL cache tên khi bật matching không phân biệt case. |
| `case-insensitive-name-matching.config-file` | `null` | JSON mapping để xử lý tên chỉ khác case. |
| `case-insensitive-name-matching.config-file.refresh-period` | `0s` | Chu kỳ refresh mapping; `0s` là tắt. |
| `metadata.cache-ttl` | `0s` | TTL metadata/statistics; `0s` tắt cache. |
| `metadata.cache-missing` | `false` | Cache metadata không tồn tại. |
| `metadata.schemas.cache-ttl` / `metadata.tables.cache-ttl` / `metadata.statistics.cache-ttl` | Theo `metadata.cache-ttl` | TTL riêng cho các loại metadata. |
| `metadata.cache-maximum-size` | `10000` | Số object metadata tối đa trong cache. |
| `write.batch-size` | `1000` | Số statement tối đa trong batch. Tài liệu khuyên không đổi giá trị mặc định. |
| `dynamic-filtering.enabled` | `true` | Push dynamic filter vào JDBC query. |
| `dynamic-filtering.wait-timeout` | Theo connector default | Thời gian chờ dynamic filter trước khi tạo split/query. |
| `unsupported-type-handling` | `IGNORE` | Bỏ qua type không hỗ trợ, hoặc dùng `CONVERT_TO_VARCHAR`. |
| `jdbc-types-mapped-to-varchar` | Không đặt | Ép danh sách JDBC type sang `VARCHAR`. |
| `insert.non-transactional-insert.enabled` | `false` | Ghi trực tiếp target table thay vì temporary table, có rủi ro partial/corrupt write nếu lỗi. |
| `merge.non-transactional-merge.enabled` | `false` | Bật `MERGE` không transactional, có rủi ro partial update. |

Không bật case-insensitive matching nếu MySQL có object chỉ khác chữ hoa-thường mà chưa có mapping rõ ràng. Metadata cache làm DDL mới được thấy chậm hơn, nên chọn TTL theo tần suất thay đổi schema.

## 5. Type mapping và timezone

Các mapping thường gặp: MySQL `JSON` → Trino `JSON`, `BINARY`/`BLOB` → `VARBINARY`, `ENUM` → `VARCHAR`, `DECIMAL(p,s)` → `DECIMAL(p,s)` khi `p ≤ 38` (lớn hơn chuyển `NUMBER`), `DATETIME` → `TIMESTAMP`, và `TIMESTAMP` → `TIMESTAMP WITH TIME ZONE`.

MySQL connector đặt session time zone của MySQL connection theo JVM time zone để giữ time instant cho MySQL `TIMESTAMP`. Time zone đó phải tồn tại ở cả JVM và MySQL server; nếu không, query có thể lỗi `Unknown or incorrect time zone`. Kiểm thử timestamp/DST với dữ liệu thật trước production.

## 6. SQL support và giới hạn ghi

Connector hỗ trợ `INSERT`, `UPDATE`, `DELETE`, `MERGE`, `TRUNCATE`, `CREATE TABLE`, `CTAS`, `DROP TABLE`, `CREATE/DROP SCHEMA`, procedure và table function.

- `INSERT` mặc định dùng temporary table. Bật non-transactional insert có thể cải thiện hiệu năng nhưng exception hiếm có thể để dữ liệu không nhất quán và không rollback được.
- `UPDATE` chỉ hỗ trợ predicate/assignment hằng số; không hỗ trợ expression/function trong `SET` và không cập nhật đồng thời toàn bộ cột của row.
- `DELETE ... WHERE` chỉ hoạt động nếu predicate được pushdown hoàn toàn tới MySQL.
- `MERGE` chỉ khả dụng sau khi bật `merge.non-transactional-merge.enabled=true`; chỉ sửa direct target table và có thể partial update nếu lỗi.
- Hạn chế quyền `system.execute('query')` vì nó có thể chạy SQL native trực tiếp trên MySQL.

Sau khi deploy catalog, dùng các lệnh sau để xác minh schema, table, type mapping và đọc dữ liệu.

```sql
SHOW SCHEMAS FROM mysql;
SHOW TABLES FROM mysql.application;
DESCRIBE mysql.application.example_table;
SELECT * FROM mysql.application.example_table LIMIT 10;
```

## 7. Hiệu năng, bảo mật và kiểm thử

Trino có thể push predicate, aggregation, join và Top-N tùy query/type/capability MySQL. Dùng `EXPLAIN` để xác minh thực tế; join giữa MySQL và catalog khác thường cần Trino xử lý dữ liệu sau khi đọc từ source.

Áp dụng TLS, least-privilege MySQL user và system access control của Trino. Xem [file-based access control](../security/FILE_SYSTEM_ACCESS_CONTROL.md) nếu dùng file rule cho policy Trino.

- [ ] Tất cả worker kết nối được MySQL qua network và TLS theo yêu cầu.
- [ ] Credential không nằm trong Git, user MySQL có least privilege.
- [ ] Đã kiểm thử `DECIMAL`, JSON, BLOB, `DATETIME`, `TIMESTAMP`, timezone/DST và type ứng dụng đặc thù.
- [ ] Đã xác minh pushdown bằng `EXPLAIN` cho query quan trọng.
- [ ] DDL/DML được thử trong schema/table thử nghiệm trước production.
- [ ] Non-transactional `INSERT`/`MERGE` chỉ bật khi có chấp nhận rủi ro partial write.

## References

- [Trino — MySQL connector](https://trino.io/docs/current/connector/mysql.html)
- [MySQL Connector/J Developer Guide](https://dev.mysql.com/doc/connector-j/en/)
- [Trino — File-based access control](https://trino.io/docs/current/security/file-system-access-control.html)
