# Hive connector cho Trino

> Tóm tắt theo [Hive connector — Trino current](https://trino.io/docs/current/connector/hive.html) (đối chiếu Trino 482 ngày 2026-07-14).

Hive connector cho phép Trino truy vấn dữ liệu của Apache Hive data warehouse. Trino dùng data files và metadata qua Hive Metastore (HMS) hoặc implementation tương thích; Trino **không** chạy HiveQL, MapReduce, Tez hay phần execution engine của Hive.

## 1. Yêu cầu và mô hình dữ liệu

Hive warehouse có data files (thường trên HDFS/object storage) và metadata ánh xạ schema, table, partition đến vị trí dữ liệu. HMS thường lưu metadata trong relational database nhưng Trino giao tiếp với HMS, không kết nối trực tiếp database đó.

Trước khi tạo catalog, cần:

- HMS hoặc implementation tương thích như AWS Glue.
- Một file system được Trino hỗ trợ; coordinator và toàn bộ worker phải truy cập được cả metastore và storage. HMS Thrift mặc định dùng cổng `9083`.
- Data format được hỗ trợ: ORC, Parquet, Avro; ngoài ra chỉ một số SerDe/format serializable cụ thể như RCFile, SequenceFile, CSV, JSON, OpenX JSON, TextFile và ESRI.
- Quyền storage/metastore khớp với thao tác đọc/ghi và policy access control của Trino.

## 2. Cách tạo catalog

File `etc/catalog/<tên>.properties` tạo catalog cùng tên. Có thể tạo nhiều file để kết nối nhiều Hive warehouse, ví dụ `etc/catalog/sales.properties` tạo catalog `sales`.

Chọn một metastore và một file system cho mỗi catalog. HMS và Glue không phải cấu hình cộng dồn.

### 2.1 Hive Metastore

Tạo `etc/catalog/hive.properties` và đặt nội dung sau vào đó khi dùng Hive Metastore; thay `fs.x.enabled` bằng property bật đúng file system của bạn.

```properties
connector.name=hive
hive.metastore.uri=thrift://example.net:9083
fs.x.enabled=true
```

`fs.x.enabled=true` là placeholder của Trino. Thay bằng configuration S3, Azure Storage, GCS hoặc HDFS; chỉ dùng `fs.hadoop.enabled` cho HDFS.

### 2.2 AWS Glue

Tạo `etc/catalog/hive.properties` và đặt nội dung sau vào đó khi dùng AWS Glue; bổ sung property Glue, credential và file-system access theo tài liệu Trino.

```properties
connector.name=hive
hive.metastore=glue
```

## 3. Property catalog quan trọng

| Property name | Mặc định | Ý nghĩa |
| --- | --- | --- |
| `hive.recursive-directories` | `false` | Đọc subdirectory của location table/partition. Khi tắt, subdirectory bị bỏ qua. |
| `hive.ignore-absent-partitions` | `false` | Bỏ qua partition có location không tồn tại thay vì fail query; có thể làm thiếu dữ liệu. |
| `hive.storage-format` | `ORC` | Định dạng mặc định cho bảng mới. |
| `hive.orc.use-column-names` | `false` | Đọc ORC theo tên cột thay vì ordinal position. |
| `hive.parquet.use-column-names` | `true` | Đọc Parquet theo tên cột; tắt để dùng ordinal position. |
| `hive.parquet.time-zone` | JVM default | Time zone khi đọc/ghi timestamp trong Parquet. |
| `hive.timestamp-precision` | Theo cấu hình Trino | Quyết định precision `TIMESTAMP` và `TIMESTAMP WITH LOCAL TIME ZONE` khi mapping Hive. |

Không bật `hive.ignore-absent-partitions` để che lỗi location/partition. Nếu bật recursive directory hoặc chuyển từ positional sang name-based mapping, hãy kiểm thử table cũ vì thay đổi này có thể làm kết quả khác với schema/file hiện tại.

## 4. Type mapping, schema và dữ liệu

Các mapping phổ biến: `INT` → `INTEGER`, `STRING` → `VARCHAR`, `BINARY` → `VARBINARY`, `STRUCT` → `ROW`, `ARRAY` → `ARRAY`, `MAP` → `MAP`. `UNIONTYPE` chỉ đọc được dưới dạng `ROW`; ghi `UNIONTYPE` không được hỗ trợ. Type không nằm trong mapping chính thức có thể không đọc/ghi được.

Hive schema evolution phụ thuộc mạnh vào format và cách cột được map. Với Avro, schema nằm ở file/literal schema và có các giới hạn evolution riêng. Conversion lỗi khi Hive coercion có thể tạo `NULL`, vì vậy cần kiểm tra dữ liệu sau khi đổi schema hoặc type.

## 5. SQL, partition và metadata

Connector hỗ trợ thao tác đọc/ghi, schema/table management, view/materialized view tùy khả năng source, procedure, `INSERT`, `UPDATE`, `DELETE`, `MERGE`, `TRUNCATE` và `ALTER TABLE EXECUTE optimize` theo tài liệu connector.

Truy vấn sau xác minh metadata và đọc table. Thay `analytics` và `events` bằng schema/table thật.

```sql
SHOW SCHEMAS FROM hive;
SHOW TABLES FROM hive.analytics;
SELECT * FROM hive.analytics.events LIMIT 10;
SELECT * FROM hive.analytics."events$partitions";
```

Hive metadata tables như `$properties` và `$partitions` hữu ích để kiểm tra table configuration, partition và kích thước. Với bảng partitioned, hãy luôn dùng predicate partition khi phù hợp để giảm file listing và read volume.

## 6. Hiệu năng và giới hạn vận hành

- Hive metadata chỉ lưu partition location, không lưu từng data file. Query có thể phải liệt kê file trong partition, do đó bảng nhiều partition/tệp nhỏ làm planning chậm.
- Dùng ORC/Parquet, partition hợp lý, file size phù hợp và statistics để giảm chi phí query.
- `ANALYZE` trên join key/predicate/grouping key có thể cải thiện optimizer. Với bảng partitioned, có thể chỉ analyze các partition và cột chọn lọc để tránh chi phí không cần thiết.
- Dynamic filtering và file-system cache có thể cải thiện workload phù hợp, nhưng cần đo trên query representative.
- Đọc/ghi table được chia sẻ với Hive/engine khác đòi hỏi thống nhất schema, SerDe, format, location và quy trình cập nhật metastore.
- Xem mục Hive 3-related limitations trong tài liệu Trino trước khi dùng Hive 3 metadata/feature đặc thù.

## 7. Authorization và kiểm thử

Quyền storage/HMS không thay thế authorization của Trino. Áp dụng system access control hoặc catalog policy theo mô hình bảo mật của cluster; xem [file-based access control](../security/FILE_SYSTEM_ACCESS_CONTROL.md) khi dùng rule file.

Sau khi deploy catalog, kiểm thử một bảng đại diện cho mỗi format đang dùng và, nếu có, một partition mới tạo. Với bảng ghi, dùng schema thử nghiệm để kiểm tra DDL/DML trước.

- [ ] Mọi node Trino truy cập được HMS/Glue và storage.
- [ ] `SHOW SCHEMAS`, `SHOW TABLES` và `SELECT` trả metadata/data mong đợi.
- [ ] Đã kiểm thử ORC/Parquet/Avro, timestamp timezone và mapping theo tên/vị trí cột.
- [ ] Partition location thiếu gây fail rõ ràng, trừ khi có chủ đích bật `hive.ignore-absent-partitions`.
- [ ] Quyền Trino, HMS và storage khớp với role thực tế.
- [ ] Đã đo planning/query sau khi thay đổi partitioning, file format hoặc statistics.

## References

- [Trino — Hive connector](https://trino.io/docs/current/connector/hive.html)
- [Trino — Object storage](https://trino.io/docs/current/object-storage.html)
- [Trino — File-based access control](https://trino.io/docs/current/security/file-system-access-control.html)
