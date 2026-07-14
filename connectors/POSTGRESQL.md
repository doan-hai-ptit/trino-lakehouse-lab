# PostgreSQL connector cho Trino

> Tóm tắt theo [PostgreSQL connector — Trino current](https://trino.io/docs/current/connector/postgresql.html) (đối chiếu Trino 482 ngày 2026-07-14).

PostgreSQL connector là JDBC connector cho phép Trino đọc, tạo và thay đổi dữ liệu/metadata trong một PostgreSQL database bên ngoài. Nó phù hợp cho truy vấn liên catalog, ví dụ join dữ liệu PostgreSQL với dữ liệu lakehouse, nhưng không biến PostgreSQL thành kho phân tích phân tán.

## 1. Yêu cầu và phạm vi

- PostgreSQL 12.x hoặc cao hơn.
- Coordinator và mọi worker truy cập mạng được đến PostgreSQL; cổng mặc định là `5432`.
- User dùng cho JDBC connection có đúng quyền tối thiểu cần thiết trên database đích.
- Một catalog PostgreSQL chỉ truy cập **một database** trên một PostgreSQL server. Cần nhiều file catalog nếu muốn truy cập nhiều database hoặc server.

File `etc/catalog/<tên>.properties` tạo catalog `<tên>`. Ví dụ `etc/catalog/postgresql.properties` tạo catalog `postgresql`, được dùng trong `postgresql.schema_name.table_name`.

## 2. Cách tạo catalog và kết nối TLS

Tạo `etc/catalog/postgresql.properties` và đặt nội dung sau vào đó; thay URL, user và password bằng thông tin database thực tế. Không commit mật khẩu thật: dùng Trino secrets, credential provider hoặc hệ thống quản lý secret phù hợp.

```properties
connector.name=postgresql
connection-url=jdbc:postgresql://example.net:5432/database
connection-user=root
connection-password=secret
```

`connection-url` được truyền cho PostgreSQL JDBC driver. Chỉ thêm JDBC parameters đã kiểm tra tương thích với connector. Khi data source đã có TLS với certificate tin cậy, sửa `connection-url` trong `etc/catalog/postgresql.properties` để bật TLS theo ví dụ chính thức.

```properties
connection-url=jdbc:postgresql://example.net:5432/database?ssl=true
```

## 3. Credential provider và property kết nối

Credential có thể đến từ inline catalog property, properties file riêng, Java keystore hoặc extra credentials của client. `credential-provider.type` nhận `INLINE` (mặc định), `FILE` hoặc `KEYSTORE`.

| Property name | Ý nghĩa |
| --- | --- |
| `connection-user` / `connection-password` | User/password khi dùng inline credential. |
| `credential-provider.type` | Chọn `INLINE`, `FILE` hoặc `KEYSTORE`. |
| `user-credential-name` / `password-credential-name` | Tên extra credential của Trino chứa user/password. |
| `connection-credential-file` | Properties file credential; phải có `connection-user` và `connection-password`. |
| `keystore-file-path` / `keystore-type` / `keystore-password` | Vị trí, định dạng và password của keystore. |
| `keystore-user-credential-name` / `keystore-password-credential-name` | Entity trong keystore chứa user/password. |
| `keystore-user-credential-password` / `keystore-password-credential-password` | Password bảo vệ các entity keystore tương ứng. |

Không lưu secret/keystore password trong repository. TLS của JDBC connection và authentication/authorization của client đến Trino là hai lớp khác nhau; cấu hình cả hai khi cần.

## 4. Property catalog quan trọng

| Property name | Mặc định | Ý nghĩa |
| --- | --- | --- |
| `postgresql.include-system-tables` | `false` | Hiển thị các PostgreSQL catalog table trong schema `pg_catalog`. |
| `case-insensitive-name-matching` | `false` | Cho phép schema/table name không phân biệt hoa-thường. |
| `case-insensitive-name-matching.cache-ttl` | `1m` | TTL cache tên khi bật case-insensitive matching. |
| `case-insensitive-name-matching.config-file` | `null` | JSON mapping để phân biệt tên chỉ khác case. |
| `case-insensitive-name-matching.config-file.refresh-period` | `0s` | Chu kỳ kiểm tra JSON mapping; `0s` là tắt refresh. |
| `metadata.cache-ttl` | `0s` | TTL metadata, table/column statistics; `0s` tắt cache. |
| `metadata.cache-missing` | `false` | Cache kết quả metadata không tồn tại. |
| `metadata.schemas.cache-ttl` / `metadata.tables.cache-ttl` / `metadata.statistics.cache-ttl` | Theo `metadata.cache-ttl` | TTL riêng cho schema, table và statistics metadata. |
| `metadata.cache-maximum-size` | `10000` | Số object metadata tối đa trong cache. |
| `unsupported-type-handling` | `IGNORE` | Bỏ qua cột type không hỗ trợ, hoặc đặt `CONVERT_TO_VARCHAR`. |
| `jdbc-types-mapped-to-varchar` | Không đặt | Ép danh sách JDBC type thành `VARCHAR`. |
| `postgresql.array-mapping` | `DISABLED` | Xử lý PostgreSQL array: `DISABLED`, `AS_ARRAY`, `AS_JSON`. |
| `insert.non-transactional-insert.enabled` | `false` | Ghi trực tiếp target table thay vì temporary table; có nguy cơ không rollback được. |
| `merge.non-transactional-merge.enabled` | `false` | Bật `MERGE` không transactional; lỗi hiếm có thể tạo partial update. |

Case-insensitive matching có thể gây ambiguity nếu PostgreSQL có nhiều schema/table chỉ khác hoa-thường. Không bật trước khi có mapping rõ ràng. Metadata cache giảm round trip nhưng trì hoãn việc Trino thấy DDL mới.

## 5. Type mapping và các điểm cần chú ý

Các mapping chính: `NUMERIC(p,s)` → `DECIMAL(p,s)` hoặc `NUMBER`, `BYTEA` → `VARBINARY`, `JSON`/`JSONB` → `JSON`, `UUID` → `UUID`, `TIMESTAMPTZ` → `TIMESTAMP WITH TIME ZONE`, `ARRAY` → `ARRAY` hoặc `JSON` tùy `postgresql.array-mapping`, và PostGIS `GEOMETRY`/`POINT` → `GEOMETRY`.

PostgreSQL array không có fixed dimension trong khi Trino array yêu cầu fixed dimension. Vì vậy `DISABLED` là mặc định; chọn `AS_ARRAY` chỉ khi array có dimension cố định, hoặc `AS_JSON` khi cần giữ array dimension linh hoạt. Type không được hỗ trợ bị bỏ qua theo mặc định, nên hãy kiểm tra `DESCRIBE`/`SHOW COLUMNS` sau khi nạp catalog.

## 6. SQL support và giới hạn ghi

Connector hỗ trợ read/write, `INSERT`, `UPDATE`, `DELETE`, `MERGE`, `TRUNCATE`, schema/table management, procedure và table function. Tuy nhiên đây không phải transaction end-to-end xuyên Trino:

- `INSERT` mặc định ghi qua temporary table. Bật non-transactional insert có thể nhanh hơn, nhưng khi exception xảy ra dữ liệu có thể bị hỏng và không rollback được.
- `UPDATE` chỉ hỗ trợ predicate và assignment là hằng số. Không hỗ trợ expression/function trong `SET`, và không thể cập nhật đồng thời tất cả cột của một row.
- `DELETE ... WHERE` chỉ hoạt động khi predicate được pushdown hoàn toàn đến PostgreSQL.
- `MERGE` cần bật `merge.non-transactional-merge.enabled=true`, chỉ hỗ trợ sửa target table trực tiếp và có nguy cơ partial update nếu lỗi.
- `system.flush_metadata_cache()` dùng để xóa metadata cache. Hạn chế quyền `system.execute('query')` vì nó có thể thực thi SQL native trên data source.

Sau khi nạp catalog, xác minh metadata và query cơ bản bằng các câu lệnh sau.

```sql
SHOW SCHEMAS FROM postgresql;
SHOW TABLES FROM postgresql.public;
DESCRIBE postgresql.public.example_table;
SELECT * FROM postgresql.public.example_table LIMIT 10;
```

## 7. Hiệu năng, bảo mật và kiểm thử

Predicate, aggregation, join và Top-N có thể được pushdown tùy query/type/capability của PostgreSQL. Dùng `EXPLAIN` để xác nhận pushdown thực tế; không giả định join liên catalog được đẩy xuống PostgreSQL. `ANALYZE`/statistics bên PostgreSQL và statistics Trino giúp planning tốt hơn.

Áp dụng system access control của Trino để giới hạn catalog/schema/table, đồng thời giữ quyền PostgreSQL và TLS tối thiểu. Xem [file-based access control](../security/FILE_SYSTEM_ACCESS_CONTROL.md) nếu policy dùng file rule.

- [ ] Từng worker kết nối được PostgreSQL qua network/TLS theo yêu cầu.
- [ ] Catalog trỏ đúng một database; database/server khác dùng catalog riêng.
- [ ] Credential không nằm trong Git và user database có least privilege.
- [ ] Đã kiểm thử numeric, JSONB, UUID, timestamp, array và geometry (nếu có).
- [ ] Đã xác minh pushdown bằng `EXPLAIN` với query quan trọng.
- [ ] DML/DDL được thử trong database hoặc schema thử nghiệm trước production.
- [ ] Non-transactional `INSERT`/`MERGE` chỉ bật khi chấp nhận rõ ràng rủi ro partial write.

## References

- [Trino — PostgreSQL connector](https://trino.io/docs/current/connector/postgresql.html)
- [PostgreSQL JDBC driver documentation](https://jdbc.postgresql.org/documentation/)
- [Trino — File-based access control](https://trino.io/docs/current/security/file-system-access-control.html)
