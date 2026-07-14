# Delta Lake connector cho Trino

> Tóm tắt theo [Delta Lake connector — Trino current](https://trino.io/docs/current/connector/delta-lake.html) (đối chiếu Trino 482 ngày 2026-07-14).

Delta Lake connector cho phép Trino đọc và ghi bảng Delta Lake, gồm cả bảng do Databricks Delta Lake tạo. Connector đọc trực tiếp Delta transaction log, vì vậy nhận biết được thay đổi do engine khác ghi vào bảng. Data files là Parquet; transaction log cung cấp phiên bản bảng, schema, partition và thông tin commit.

## 1. Yêu cầu và phạm vi

Trước khi tạo catalog, cần bảo đảm:

- Coordinator và mọi worker truy cập mạng được đến storage chứa Delta transaction log và data files.
- Có Hive Metastore (HMS) hoặc AWS Glue làm metadata catalog. Với HMS qua Thrift, cổng mặc định là `9083`.
- Storage là AWS/S3-compatible, Azure Storage, Google Cloud Storage hoặc HDFS được Trino hỗ trợ; data files là Parquet.
- Identity chạy Trino có quyền đọc transaction log/data. Workload ghi cần thêm quyền storage và semantics concurrent-write phù hợp.
- Bảng được tạo bởi phiên bản Databricks/Delta Lake tương thích. Khi chia sẻ bảng giữa nhiều engine, phải kiểm tra Delta table features của tất cả engine trước khi ghi.

Connector chỉ nhận diện bảng Delta Lake trong metastore. Nếu cùng metastore còn có bảng Hive không phải Delta, chúng không hiển thị trong Delta Lake catalog.

## 2. Cách tạo catalog

Tên file `etc/catalog/<tên>.properties` xác định tên catalog Trino. Ví dụ `etc/catalog/delta.properties` tạo catalog `delta`, dùng trong `delta.schema_name.table_name`.

Một catalog cần đúng một metadata catalog và một cấu hình file system. HMS và Glue là hai lựa chọn thay thế; không ghép hai cấu hình trong cùng file.

### 2.1 Hive Metastore

Tạo `etc/catalog/delta.properties` và đặt nội dung sau vào đó khi dùng Hive Metastore; thay `fs.x.enabled` bằng property bật đúng file system của bạn.

```properties
connector.name=delta_lake
hive.metastore.uri=thrift://example.net:9083
fs.x.enabled=true
```

`fs.x.enabled=true` là chỗ giữ chỗ trong ví dụ chính thức. Thay nó bằng cấu hình S3, Azure Storage, GCS hoặc HDFS phù hợp; chỉ dùng `fs.hadoop.enabled` cho HDFS.

### 2.2 AWS Glue

Tạo `etc/catalog/delta.properties` và đặt nội dung sau vào đó khi dùng AWS Glue; bổ sung cấu hình Glue, credential và file system theo tài liệu Trino.

```properties
connector.name=delta_lake
hive.metastore=glue
```

## 3. Property catalog quan trọng

Các giá trị mặc định được Trino thiết kế cho sử dụng thông thường. Không ghi đè hàng loạt; thay đổi từng property, đo query đại diện và theo dõi memory/metadata load.

| Property name | Mặc định | Ý nghĩa |
| --- | --- | --- |
| `delta.metadata.cache-ttl` | `30m` | Thời gian cache metadata bảng. TTL dài giảm I/O nhưng làm metadata mới được thấy chậm hơn. |
| `delta.metadata.cache-max-retained-size` | 5% JVM max memory | Giới hạn metadata cache; có thể đặt theo data size, ví dụ `64MB`. |
| `delta.transaction-log.max-cached-file-size` | `16MB` | Kích thước log file tối đa được cache trong memory. |
| `delta.compression-codec` | `ZSTD` | Codec ghi file mới: `NONE`, `SNAPPY`, `ZSTD`, `GZIP`; session property là `compression_codec`. |
| `delta.max-partitions-per-writer` | `100` | Số partition tối đa mỗi writer xử lý. |
| `delta.idle-writer-min-file-size` | `16MB` | Ngưỡng data trước khi writer idle được đóng; session property là `idle_writer_min_file_size`. |
| `delta.target-max-file-size` | `1GB` | Kích thước data file ghi mục tiêu, không phải giới hạn cứng. |
| `delta.unique-table-location` | `true` | Tạo vị trí bảng ngẫu nhiên, duy nhất. |
| `delta.default-checkpoint-writing-interval` | `10` | Số statement ghi giữa các checkpoint transaction log; table property có thể ghi đè. |
| `delta.dynamic-filtering.wait-timeout` | Không đặt | Thời gian chờ dynamic filter khi sinh split. |
| `delta.table-statistics-enabled` | `true` | Cho phép dùng table statistics cho tối ưu hóa. |
| `delta.extended-statistics.enabled` | `true` | Cho phép `ANALYZE` và sử dụng extended statistics. |
| `delta.extended-statistics.collect-on-write` | `true` | Thu thập extended statistics trong thao tác ghi. |
| `delta.register-table-procedure.enabled` | `false` | Cho phép `system.register_table`; chỉ bật cho người vận hành tin cậy. |
| `delta.vacuum.min-retention` | `7 DAYS` | Retention tối thiểu của `VACUUM`. |
| `delta.deletion-vectors-enabled` | `false` | Bật deletion vectors mặc định cho bảng mới. |
| `delta.enable-non-concurrent-writes` | `false` | Cho phép write support trên mọi file system; cần hiểu rõ cảnh báo về concurrency/checkpoint trước khi bật. |

`delta.hide-non-delta-lake-tables` chỉ áp dụng với Glue và mặc định `false`; nó không làm bảng không-Delta trong HMS trở nên có thể truy vấn được từ catalog Delta.

## 4. Authorization và bảo mật

`delta.security` chọn cách connector kiểm tra quyền:

| Giá trị | Hành vi |
| --- | --- |
| `ALLOW_ALL` (mặc định) | Connector không thực thi authorization. |
| `SYSTEM` | Dùng system-level access control của Trino. |
| `READ_ONLY` | Cho phép đọc data/metadata và chặn ghi. |
| `FILE` | Dùng catalog-level file access control qua `security.config-file`. |

Khi dùng system access control, thêm property sau vào `etc/catalog/delta.properties`.

```properties
delta.security=SYSTEM
```

Khi dùng catalog-level file access control, thêm các property sau vào `etc/catalog/delta.properties` và tạo JSON rule file được nêu trong property. `SYSTEM` và `FILE` là các mô hình thay thế nhau.

```properties
delta.security=FILE
security.config-file=etc/catalog/delta-rules.json
```

Authorization của Trino không thay thế quyền storage/metastore. Cần kiểm tra cả policy Trino lẫn quyền đối với transaction log/data files. Xem [file-based access control](../security/FILE_SYSTEM_ACCESS_CONTROL.md) để thiết kế rule.

## 5. Khả năng tương thích và SQL

Connector hỗ trợ đọc/ghi data và metadata, `INSERT`, `UPDATE`, `DELETE`, `MERGE`, schema/table management, view và time travel. Các Delta features không có mức hỗ trợ như nhau:

- Reader và writer: column mapping, deletion vectors, timestamp without time zone, vacuum protocol check.
- Writer-only: append-only table, column invariant, `CHECK` constraint, change data feed, invariant.
- Reader-only: Iceberg compatibility v1/v2, type widening, V2 checkpoint.

Không suy luận rằng một feature mới trong Delta/Databricks sẽ ghi được từ Trino. Xác minh feature level trước khi dùng nhiều writer khác nhau.

### 5.1 Time travel và metadata tables

`$history`, `$partitions` và `$properties` giúp kiểm tra phiên bản, partition và metadata. Chạy các truy vấn sau để xem lịch sử rồi đọc một phiên bản cũ; thay tên bảng/snapshot bằng dữ liệu thật.

```sql
SELECT version, timestamp, operation
FROM delta.analytics."events$history"
ORDER BY version DESC;

SELECT *
FROM delta.analytics.events
FOR VERSION AS OF 3;
```

Time travel cũng hỗ trợ `FOR TIMESTAMP AS OF`. Snapshot/log cũ phải còn tồn tại; `VACUUM` và retention có thể làm lịch sử không còn truy vấn được.

### 5.2 Register, unregister và VACUUM

`system.register_table` dùng transaction log/data files sẵn có để đăng ký bảng vào metastore, nhưng chỉ gọi được khi `delta.register-table-procedure.enabled=true`. `system.unregister_table` bỏ đăng ký metadata, không xóa data files.

`VACUUM` xóa file cũ không còn ở transaction log hoặc không cần cho snapshot mới hơn retention. Chỉ chạy sau khi xác nhận không còn reader, job, time travel hoặc engine khác cần chúng. Lệnh sau chạy trên catalog `delta`; thay tên schema/table bằng đối tượng thật.

```sql
CALL delta.system.vacuum('analytics', 'events', '7d');
```

Giá trị retention phải không nhỏ hơn `delta.vacuum.min-retention`; mặc định là `7 DAYS`.

## 6. Type mapping và hiệu năng

Các mapping chính là `STRING` → `VARCHAR`, `BINARY` → `VARBINARY`, `STRUCT` → `ROW`, `ARRAY` → `ARRAY`, `MAP` → `MAP`, `TIMESTAMPNTZ` → `TIMESTAMP(6)` và `TIMESTAMP` → `TIMESTAMP(3) WITH TIME ZONE`. Kiểu không được liệt kê trong tài liệu không được hỗ trợ; kiểm thử type mapping trước khi ghi data từ Trino.

Để giữ hiệu năng ổn định:

- Partition theo predicate phổ biến nhưng tránh partition quá mịn gây small files.
- Theo dõi transaction-log/metadata cache và memory coordinator trên bảng nhiều snapshot.
- Dùng statistics/`ANALYZE` cho join key, filter và grouping key khi có workload phức tạp.
- Kiểm tra `$partitions` để phát hiện file nhỏ hoặc partition skew trước khi tuning writer/file size.
- Fault-tolerant execution hỗ trợ cả read/write với mọi retry policy, nhưng không thay thế concurrent-write semantics của storage và transaction log.

## 7. Kiểm thử và checklist

Sau khi deploy catalog, chạy các truy vấn sau để xác minh catalog, đọc dữ liệu và metadata.

```sql
SHOW SCHEMAS FROM delta;
SHOW TABLES FROM delta.analytics;
SELECT * FROM delta.analytics.events LIMIT 10;
SELECT version, operation
FROM delta.analytics."events$history"
ORDER BY version DESC;
```

- [ ] Tất cả node Trino truy cập được metastore và storage.
- [ ] Catalog chỉ nhìn thấy bảng Delta Lake mong đợi.
- [ ] Đã kiểm thử đọc, ghi, time travel và type mapping trong khu vực thử nghiệm.
- [ ] `delta.security` và quyền storage đều giới hạn đúng user/role.
- [ ] Chưa bật `register_table` hoặc non-concurrent writes nếu chưa có quy trình vận hành rõ ràng.
- [ ] Retention `VACUUM` phản ánh nhu cầu rollback, time travel và consumer khác.

## References

- [Trino — Delta Lake connector](https://trino.io/docs/current/connector/delta-lake.html)
- [Trino — Object storage](https://trino.io/docs/current/object-storage.html)
- [Trino — File-based access control](https://trino.io/docs/current/security/file-system-access-control.html)
