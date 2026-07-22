# Connectors Trino

Tài liệu này gộp hướng dẫn cho các connector Delta Lake, Hive, Iceberg, MySQL và PostgreSQL. Mỗi connector là một catalog độc lập; chọn connector theo loại data source và metadata mà nó hỗ trợ, rồi áp dụng cấu hình trong phần tương ứng.

Các connector lakehouse cần một metastore hoặc catalog metadata và cấu hình object storage phù hợp. Các connector cơ sở dữ liệu quan hệ cần endpoint, credential và TLS đến database. Dù chọn loại nào, quyền tại data source không thay thế authorization của Trino.

---

## Delta Lake connector cho Trino

> Tóm tắt theo [Delta Lake connector — Trino current](https://trino.io/docs/current/connector/delta-lake.html) (đối chiếu Trino 482 ngày 2026-07-14).

Delta Lake connector cho phép Trino đọc và ghi bảng Delta Lake, gồm cả bảng do Databricks Delta Lake tạo. Connector đọc trực tiếp Delta transaction log, vì vậy nhận biết được thay đổi do engine khác ghi vào bảng. Data files là Parquet; transaction log cung cấp phiên bản bảng, schema, partition và thông tin commit.

### 1. Yêu cầu và phạm vi

Trước khi tạo catalog, cần bảo đảm:

- Coordinator và mọi worker truy cập mạng được đến storage chứa Delta transaction log và data files.
- Có Hive Metastore (HMS) hoặc AWS Glue làm metadata catalog. Với HMS qua Thrift, cổng mặc định là `9083`.
- Storage là AWS/S3-compatible, Azure Storage, Google Cloud Storage hoặc HDFS được Trino hỗ trợ; data files là Parquet.
- Identity chạy Trino có quyền đọc transaction log/data. Workload ghi cần thêm quyền storage và semantics concurrent-write phù hợp.
- Bảng được tạo bởi phiên bản Databricks/Delta Lake tương thích. Khi chia sẻ bảng giữa nhiều engine, phải kiểm tra Delta table features của tất cả engine trước khi ghi.

Connector chỉ nhận diện bảng Delta Lake trong metastore. Nếu cùng metastore còn có bảng Hive không phải Delta, chúng không hiển thị trong Delta Lake catalog.

### 2. Cách tạo catalog

Tên file `etc/catalog/<tên>.properties` xác định tên catalog Trino. Ví dụ `etc/catalog/delta.properties` tạo catalog `delta`, dùng trong `delta.schema_name.table_name`.

Một catalog cần đúng một metadata catalog và một cấu hình file system. HMS và Glue là hai lựa chọn thay thế; không ghép hai cấu hình trong cùng file.

#### 2.1 Hive Metastore

Tạo `etc/catalog/delta.properties` và đặt nội dung sau vào đó khi dùng Hive Metastore; thay `fs.x.enabled` bằng property bật đúng file system của bạn.

```properties
connector.name=delta_lake
hive.metastore.uri=thrift://example.net:9083
fs.x.enabled=true
```

`fs.x.enabled=true` là chỗ giữ chỗ trong ví dụ chính thức. Thay nó bằng cấu hình S3, Azure Storage, GCS hoặc HDFS phù hợp; chỉ dùng `fs.hadoop.enabled` cho HDFS.

#### 2.2 AWS Glue

Tạo `etc/catalog/delta.properties` và đặt nội dung sau vào đó khi dùng AWS Glue; bổ sung cấu hình Glue, credential và file system theo tài liệu Trino.

```properties
connector.name=delta_lake
hive.metastore=glue
```

### 3. Property catalog quan trọng

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

### 4. Authorization và bảo mật

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

Authorization của Trino không thay thế quyền storage/metastore. Cần kiểm tra cả policy Trino lẫn quyền đối với transaction log/data files. Xem [file-based access control](../security/README.md#file-based-access-control-cho-trino) để thiết kế rule.

### 5. Khả năng tương thích và SQL

Connector hỗ trợ đọc/ghi data và metadata, `INSERT`, `UPDATE`, `DELETE`, `MERGE`, schema/table management, view và time travel. Các Delta features không có mức hỗ trợ như nhau:

- Reader và writer: column mapping, deletion vectors, timestamp without time zone, vacuum protocol check.
- Writer-only: append-only table, column invariant, `CHECK` constraint, change data feed, invariant.
- Reader-only: Iceberg compatibility v1/v2, type widening, V2 checkpoint.

Không suy luận rằng một feature mới trong Delta/Databricks sẽ ghi được từ Trino. Xác minh feature level trước khi dùng nhiều writer khác nhau.

#### 5.1 Time travel và metadata tables

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

#### 5.2 Register, unregister và VACUUM

`system.register_table` dùng transaction log/data files sẵn có để đăng ký bảng vào metastore, nhưng chỉ gọi được khi `delta.register-table-procedure.enabled=true`. `system.unregister_table` bỏ đăng ký metadata, không xóa data files.

`VACUUM` xóa file cũ không còn ở transaction log hoặc không cần cho snapshot mới hơn retention. Chỉ chạy sau khi xác nhận không còn reader, job, time travel hoặc engine khác cần chúng. Lệnh sau chạy trên catalog `delta`; thay tên schema/table bằng đối tượng thật.

```sql
CALL delta.system.vacuum('analytics', 'events', '7d');
```

Giá trị retention phải không nhỏ hơn `delta.vacuum.min-retention`; mặc định là `7 DAYS`.

### 6. Type mapping và hiệu năng

Các mapping chính là `STRING` → `VARCHAR`, `BINARY` → `VARBINARY`, `STRUCT` → `ROW`, `ARRAY` → `ARRAY`, `MAP` → `MAP`, `TIMESTAMPNTZ` → `TIMESTAMP(6)` và `TIMESTAMP` → `TIMESTAMP(3) WITH TIME ZONE`. Kiểu không được liệt kê trong tài liệu không được hỗ trợ; kiểm thử type mapping trước khi ghi data từ Trino.

Để giữ hiệu năng ổn định:

- Partition theo predicate phổ biến nhưng tránh partition quá mịn gây small files.
- Theo dõi transaction-log/metadata cache và memory coordinator trên bảng nhiều snapshot.
- Dùng statistics/`ANALYZE` cho join key, filter và grouping key khi có workload phức tạp.
- Kiểm tra `$partitions` để phát hiện file nhỏ hoặc partition skew trước khi tuning writer/file size.
- Fault-tolerant execution hỗ trợ cả read/write với mọi retry policy, nhưng không thay thế concurrent-write semantics của storage và transaction log.

### 7. Kiểm thử và checklist

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

---

## Hive connector cho Trino

> Tóm tắt theo [Hive connector — Trino current](https://trino.io/docs/current/connector/hive.html) (đối chiếu Trino 482 ngày 2026-07-14).

Hive connector cho phép Trino truy vấn dữ liệu của Apache Hive data warehouse. Trino dùng data files và metadata qua Hive Metastore (HMS) hoặc implementation tương thích; Trino **không** chạy HiveQL, MapReduce, Tez hay phần execution engine của Hive.

### 1. Yêu cầu và mô hình dữ liệu

Hive warehouse có data files (thường trên HDFS/object storage) và metadata ánh xạ schema, table, partition đến vị trí dữ liệu. HMS thường lưu metadata trong relational database nhưng Trino giao tiếp với HMS, không kết nối trực tiếp database đó.

Trước khi tạo catalog, cần:

- HMS hoặc implementation tương thích như AWS Glue.
- Một file system được Trino hỗ trợ; coordinator và toàn bộ worker phải truy cập được cả metastore và storage. HMS Thrift mặc định dùng cổng `9083`.
- Data format được hỗ trợ: ORC, Parquet, Avro; ngoài ra chỉ một số SerDe/format serializable cụ thể như RCFile, SequenceFile, CSV, JSON, OpenX JSON, TextFile và ESRI.
- Quyền storage/metastore khớp với thao tác đọc/ghi và policy access control của Trino.

### 2. Cách tạo catalog

File `etc/catalog/<tên>.properties` tạo catalog cùng tên. Có thể tạo nhiều file để kết nối nhiều Hive warehouse, ví dụ `etc/catalog/sales.properties` tạo catalog `sales`.

Chọn một metastore và một file system cho mỗi catalog. HMS và Glue không phải cấu hình cộng dồn.

#### 2.1 Hive Metastore

Tạo `etc/catalog/hive.properties` và đặt nội dung sau vào đó khi dùng Hive Metastore; thay `fs.x.enabled` bằng property bật đúng file system của bạn.

```properties
connector.name=hive
hive.metastore.uri=thrift://example.net:9083
fs.x.enabled=true
```

`fs.x.enabled=true` là placeholder của Trino. Thay bằng configuration S3, Azure Storage, GCS hoặc HDFS; chỉ dùng `fs.hadoop.enabled` cho HDFS.

#### 2.2 AWS Glue

Tạo `etc/catalog/hive.properties` và đặt nội dung sau vào đó khi dùng AWS Glue; bổ sung property Glue, credential và file-system access theo tài liệu Trino.

```properties
connector.name=hive
hive.metastore=glue
```

### 3. Property catalog quan trọng

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

### 4. Type mapping, schema và dữ liệu

Các mapping phổ biến: `INT` → `INTEGER`, `STRING` → `VARCHAR`, `BINARY` → `VARBINARY`, `STRUCT` → `ROW`, `ARRAY` → `ARRAY`, `MAP` → `MAP`. `UNIONTYPE` chỉ đọc được dưới dạng `ROW`; ghi `UNIONTYPE` không được hỗ trợ. Type không nằm trong mapping chính thức có thể không đọc/ghi được.

Hive schema evolution phụ thuộc mạnh vào format và cách cột được map. Với Avro, schema nằm ở file/literal schema và có các giới hạn evolution riêng. Conversion lỗi khi Hive coercion có thể tạo `NULL`, vì vậy cần kiểm tra dữ liệu sau khi đổi schema hoặc type.

### 5. SQL, partition và metadata

Connector hỗ trợ thao tác đọc/ghi, schema/table management, view/materialized view tùy khả năng source, procedure, `INSERT`, `UPDATE`, `DELETE`, `MERGE`, `TRUNCATE` và `ALTER TABLE EXECUTE optimize` theo tài liệu connector.

Truy vấn sau xác minh metadata và đọc table. Thay `analytics` và `events` bằng schema/table thật.

```sql
SHOW SCHEMAS FROM hive;
SHOW TABLES FROM hive.analytics;
SELECT * FROM hive.analytics.events LIMIT 10;
SELECT * FROM hive.analytics."events$partitions";
```

Hive metadata tables như `$properties` và `$partitions` hữu ích để kiểm tra table configuration, partition và kích thước. Với bảng partitioned, hãy luôn dùng predicate partition khi phù hợp để giảm file listing và read volume.

### 6. Hiệu năng và giới hạn vận hành

- Hive metadata chỉ lưu partition location, không lưu từng data file. Query có thể phải liệt kê file trong partition, do đó bảng nhiều partition/tệp nhỏ làm planning chậm.
- Dùng ORC/Parquet, partition hợp lý, file size phù hợp và statistics để giảm chi phí query.
- `ANALYZE` trên join key/predicate/grouping key có thể cải thiện optimizer. Với bảng partitioned, có thể chỉ analyze các partition và cột chọn lọc để tránh chi phí không cần thiết.
- Dynamic filtering và file-system cache có thể cải thiện workload phù hợp, nhưng cần đo trên query representative.
- Đọc/ghi table được chia sẻ với Hive/engine khác đòi hỏi thống nhất schema, SerDe, format, location và quy trình cập nhật metastore.
- Xem mục Hive 3-related limitations trong tài liệu Trino trước khi dùng Hive 3 metadata/feature đặc thù.

### 7. Authorization và kiểm thử

Quyền storage/HMS không thay thế authorization của Trino. Áp dụng system access control hoặc catalog policy theo mô hình bảo mật của cluster; xem [file-based access control](../security/README.md#file-based-access-control-cho-trino) khi dùng rule file.

Sau khi deploy catalog, kiểm thử một bảng đại diện cho mỗi format đang dùng và, nếu có, một partition mới tạo. Với bảng ghi, dùng schema thử nghiệm để kiểm tra DDL/DML trước.

- [ ] Mọi node Trino truy cập được HMS/Glue và storage.
- [ ] `SHOW SCHEMAS`, `SHOW TABLES` và `SELECT` trả metadata/data mong đợi.
- [ ] Đã kiểm thử ORC/Parquet/Avro, timestamp timezone và mapping theo tên/vị trí cột.
- [ ] Partition location thiếu gây fail rõ ràng, trừ khi có chủ đích bật `hive.ignore-absent-partitions`.
- [ ] Quyền Trino, HMS và storage khớp với role thực tế.
- [ ] Đã đo planning/query sau khi thay đổi partitioning, file format hoặc statistics.

---

## Iceberg connector cho Trino

> Tóm tắt theo [Iceberg connector — Trino current](https://trino.io/docs/current/connector/iceberg.html) (đối chiếu Trino 482 ngày 2026-07-14).

Iceberg connector cho phép Trino đọc và ghi các bảng theo Apache Iceberg table format. Iceberg lưu trạng thái bảng trong metadata files: mỗi lần thay đổi sẽ tạo metadata file mới và thay thế tham chiếu metadata cũ theo cách atomic. Metadata lưu schema, partitioning, table properties và snapshot; data files có thể dùng Parquet, ORC hoặc Avro.

Iceberg khác Hive truyền thống ở chỗ metadata lưu đường dẫn cụ thể đến data files. Vì vậy, Trino không cần liệt kê toàn bộ file trong từng partition trước khi đọc. Đây là lợi thế quan trọng khi bảng có rất nhiều partition hoặc file.

### 1. Phạm vi, phiên bản và yêu cầu

Connector hỗ trợ Iceberg table spec v1 và v2. Hỗ trợ format version 3 là **experimental**. `VARIANT`, `TIMESTAMP_NS` và `TIMESTAMPTZ_NS` cần format version 3; đồng thời v3 hiện không hỗ trợ row-level `UPDATE`, `DELETE`, `OPTIMIZE`, cũng như một số tính năng v3 như column default value và encryption.

Trước khi tạo catalog, cần bảo đảm:

- Coordinator và mọi worker truy cập mạng được đến object storage hoặc HDFS chứa data/metadata files.
- Có đúng một metadata catalog cho catalog Trino này: Hive Metastore (HMS), AWS Glue, JDBC, REST, Nessie hoặc Snowflake catalog.
- Data files là Parquet (mặc định), ORC hoặc Avro trên file system được Trino hỗ trợ.
- Identity chạy Trino có quyền đọc metadata/data và, nếu ghi, có quyền tạo/đổi tên/xóa tệp theo thao tác thực hiện.
- Khi dùng HMS qua Thrift hoặc HDFS có Kerberos, cấu hình Kerberos theo phần Hive/HDFS của tài liệu Trino.

### 2. Mô hình catalog và cách chọn cấu hình

Mỗi file `etc/catalog/<tên>.properties` tạo một catalog Trino có tên `<tên>`. Ví dụ, `etc/catalog/iceberg.properties` tạo catalog `iceberg`, được dùng trong tên đầy đủ `iceberg.schema_name.table_name`.

Một catalog Iceberg gồm ba lớp độc lập:

| Lớp | Vai trò | Lựa chọn chính |
| --- | --- | --- |
| Connector | Cung cấp SQL, metadata và logic Iceberg cho Trino. | `connector.name=iceberg` |
| Metadata catalog | Lưu/định vị metadata của schema và bảng. | HMS, Glue, JDBC, REST, Nessie hoặc Snowflake |
| File system | Lưu metadata files, manifests và data files. | S3, Azure Storage, Google Cloud Storage hoặc HDFS |

Chọn **một** metadata catalog và **một** cơ chế file-system access cho mỗi file catalog. Không ghép cấu hình của HMS với REST/Nessie/Glue trong cùng `iceberg.properties`.

#### 2.1 Cấu hình tối thiểu với Hive Metastore

HMS là `iceberg.catalog.type` mặc định. Tạo `etc/catalog/iceberg.properties` và đặt nội dung sau vào đó khi dùng Hive Metastore; thay `fs.x.enabled` bằng property bật đúng file system của bạn.

```properties
connector.name=iceberg
hive.metastore.uri=thrift://example.net:9083
fs.x.enabled=true
```

`fs.x.enabled=true` trong ví dụ chính thức là chỗ giữ chỗ, không phải property có thể dùng nguyên trạng. Hãy chọn đúng một hướng dẫn file system của Trino và thay nó bằng property phù hợp, ví dụ cấu hình S3, Azure Storage, GCS hoặc `fs.hadoop.enabled` cho HDFS. Chỉ dùng `fs.hadoop.enabled` cho HDFS.

#### 2.2 Metadata catalog khác HMS

Nếu không dùng HMS, vẫn tạo `etc/catalog/iceberg.properties`, luôn đặt `connector.name=iceberg`, rồi chọn `iceberg.catalog.type` và thêm toàn bộ property bắt buộc của implementation đó.

| `iceberg.catalog.type` | Khi phù hợp | Ghi chú |
| --- | --- | --- |
| `hive_metastore` | Đã có Hive Metastore. | Mặc định; dùng `hive.metastore.uri` hoặc cấu hình HMS tương ứng. |
| `glue` | Metadata nằm trong AWS Glue Data Catalog. | Cần cấu hình Glue và quyền AWS. |
| `jdbc` | Muốn dùng JDBC catalog của Iceberg. | Cần JDBC URI/driver và kho metadata tương thích. |
| `rest` | Dùng Iceberg REST catalog. | Cần REST endpoint và cơ chế xác thực của catalog. |
| `nessie` | Quản lý branch/tag qua Nessie. | Cần Nessie server và cấu hình endpoint/auth. |
| `snowflake` | Dùng Snowflake catalog. | Cần cấu hình Snowflake catalog theo tài liệu Trino. |

Các property chi tiết của các lựa chọn này khác nhau; không thay chúng bằng `hive.metastore.uri`. Xem tài liệu [metastore configuration](https://trino.io/docs/current/object-storage/metastores.html) tương ứng trước khi triển khai.

### 3. Property catalog quan trọng

Không cần đặt mọi property dưới đây: các giá trị mặc định của Trino là điểm khởi đầu hợp lý. Chỉ ghi đè sau khi đo được nhu cầu về hiệu năng, layout, retention hoặc policy.

#### 3.1 Metadata, định dạng và ghi dữ liệu

| Property name | Mặc định | Ý nghĩa vận hành |
| --- | --- | --- |
| `iceberg.catalog.type` | `hive_metastore` | Chọn metadata catalog: `hive_metastore`, `glue`, `jdbc`, `rest`, `nessie`, `snowflake`. |
| `iceberg.file-format` | `PARQUET` | Định dạng mặc định cho bảng mới: `PARQUET`, `ORC`, `AVRO`. Có thể ghi đè bằng table property `format`. |
| `iceberg.compression-codec` | `ZSTD` | Codec ghi file mới: `NONE`, `SNAPPY`, `LZ4`, `ZSTD`, `GZIP`. Có thể ghi đè bằng `compression_codec`. |
| `iceberg.max-partitions-per-writer` | `100` | Số partition tối đa mỗi writer xử lý; session property tương ứng là `max_partitions_per_writer`. |
| `iceberg.target-max-file-size` | `1GB` | Kích thước file ghi mục tiêu, không phải giới hạn cứng. |
| `iceberg.idle-writer-min-file-size` | `16MB` | Ngưỡng dữ liệu để writer partition được coi là idle và đóng lại. |
| `iceberg.unique-table-location` | `true` | Dùng vị trí bảng ngẫu nhiên, duy nhất khi tạo bảng. |
| `iceberg.object-store-layout.enabled` | `false` | Bật Iceberg object-store file layout; đường dẫn ghi có thêm hash xác định. |
| `iceberg.allowed-extra-properties` | `[]` | Danh sách extra table properties được phép đặt; `*` cho phép tất cả, nên cần giới hạn cẩn thận. |

`iceberg.use-file-size-from-metadata` mặc định `true` chỉ là workaround cho một vấn đề đã được sửa từ Iceberg 0.11.0. Không nên thay đổi property này nếu không có lý do tương thích đã xác minh.

#### 3.2 Planning, đọc dữ liệu và thống kê

| Property name | Mặc định | Ý nghĩa vận hành |
| --- | --- | --- |
| `iceberg.dynamic-filtering.wait-timeout` | `1s` | Thời gian chờ dynamic filter khi tạo split. |
| `iceberg.max-split-size` | Theo table property nếu không đặt | Kích thước split mục tiêu; một số split có thể lớn hơn. |
| `iceberg.minimum-assigned-split-weight` | `0.05` | Trọng số split tối thiểu `(0, 1]`; thấp có thể giúp nhiều file nhỏ, cao có thể giúp query bị skew. |
| `iceberg.projection-pushdown-enabled` | `true` | Chỉ đọc trường cần thiết trong cấu trúc phức hợp khi có thể. |
| `iceberg.table-statistics-enabled` | `true` | Cho phép optimizer dùng table statistics; không nên tắt chỉ để né vấn đề hiệu năng. |
| `iceberg.extended-statistics.collect-on-write` | `true` | Thu thập extended statistics khi ghi. |
| `iceberg.query-partition-filter-required` | `false` | Bắt buộc filter trên partition key với các schema đã chỉ định. |
| `iceberg.query-partition-filter-required-schemas` | `[]` | Danh sách schema bị áp dụng yêu cầu partition filter. |
| `iceberg.bucket-execution` | `true` | Cho phép engine tận dụng physical bucketing để giảm data exchange. |

#### 3.3 Cache, concurrency và dọn dữ liệu

| Property name | Mặc định | Ý nghĩa vận hành |
| --- | --- | --- |
| `iceberg.metadata-cache.enabled` | `true` | Cache metadata files trong memory trên coordinator. Cache này không dùng khi `fs.cache.enabled=true`. |
| `iceberg.parquet-footer-cache.type` | `none` | Dùng `memory` để bật bounded in-memory cache cho Parquet footer. |
| `iceberg.parquet-footer-cache.memory.max-size` | `10MB` | Kích thước tối đa của memory footer cache. |
| `iceberg.split-manager-threads` | Gấp 2 số CPU coordinator | Thread tạo split. |
| `iceberg.planning-threads` | Gấp 2 số CPU coordinator | Thread đọc manifest trong query planning. |
| `iceberg.metadata.parallelism` | `8` | Thread tải metadata bảng. |
| `iceberg.file-delete-threads` | Gấp 2 số CPU coordinator | Thread xóa file cho `expire_snapshots`, `remove_orphan_files` và `DROP TABLE`. |
| `iceberg.expire-snapshots.min-retention` | `7d` | Retention tối thiểu của `expire_snapshots`. |
| `iceberg.remove-orphan-files.min-retention` | `7d` | Retention tối thiểu của `remove_orphan_files`. |
| `iceberg.delete-schema-locations-fallback` | `false` | Có xóa schema location khi Trino không xác định được nó có external files hay không. |

Hai property retention là hàng rào an toàn, không phải đề xuất giữ dữ liệu chỉ bảy ngày. Đừng hạ retention trước khi xác nhận time travel, job đang chạy, engine khác và quy trình khôi phục không cần snapshot/file cũ.

#### 3.4 Procedure, materialized view và sorted writing

| Property name | Mặc định | Ý nghĩa vận hành |
| --- | --- | --- |
| `iceberg.register-table-procedure.enabled` | `false` | Cho phép `system.register_table`; tắt mặc định để giảm nguy cơ đăng ký nhầm dữ liệu. |
| `iceberg.add-files-procedure.enabled` | `false` | Cho phép `system.add_files`; chỉ bật cho người vận hành hiểu rõ nguồn file. |
| `iceberg.sorted-writing-enabled` | `true` | Ghi có sắp xếp khi bảng có `sorted_by`. |
| `iceberg.sorted-writing.local-staging-path` | Không đặt | Đường dẫn local staging của sorted write; có thể dùng `${USER}`. Nếu không có, object storage có thể bị dùng làm staging và kém hiệu quả. |
| `iceberg.incremental-refresh-enabled` | `true` | Cho phép refresh incremental cho materialized view khi khả thi; giảm scan nhưng có thể tạo nhiều file hơn. |
| `iceberg.materialized-views.refresh-max-snapshots-to-expire` | `200` | Số snapshot materialized-view tối đa bị expire trong một lần refresh. |
| `iceberg.materialized-views.refresh-snapshot-retention-period` | `4h` | Khoảng giữ snapshot materialized view khi refresh. |

Iceberg hỗ trợ fault-tolerant execution cho cả đọc và ghi với mọi retry policy của Trino. Việc retry không thay thế yêu cầu storage và metadata catalog phải có semantics phù hợp cho concurrent commit.

### 4. Cấu hình authorization

`iceberg.security` chọn cách connector kiểm tra quyền trong phạm vi catalog:

| Giá trị | Hành vi |
| --- | --- |
| `ALLOW_ALL` | Không thực thi authorization ở cấp connector. |
| `SYSTEM` | Dùng system-level access control của Trino. |
| `READ_ONLY` | Chỉ cho phép đọc data/metadata; chặn thao tác ghi như `CREATE TABLE`, `INSERT`, `DELETE`. |
| `FILE` | Dùng catalog-level file access control qua `security.config-file`. |

`ALLOW_ALL` không nên là lựa chọn mặc định cho môi trường nhiều người dùng. Khi policy dùng system access control, thêm property sau vào `etc/catalog/iceberg.properties`.

```properties
iceberg.security=SYSTEM
```

Khi policy dành riêng cho catalog Iceberg, thêm các property sau vào `etc/catalog/iceberg.properties` và tạo file rule được chỉ định. `FILE` và `SYSTEM` là hai mô hình khác nhau; chọn một theo kiến trúc phân quyền.

```properties
iceberg.security=FILE
security.config-file=etc/catalog/iceberg-rules.json
```

Quyền Trino không thay thế quyền ở storage/metastore: cả hai lớp phải cho phép thao tác hợp lệ. Xem [file-based access control](../security/README.md#file-based-access-control-cho-trino) để biết thứ tự đánh giá rule và thiết kế policy.

### 5. Type mapping và khả năng tương thích

Các mapping quan trọng khi đọc/ghi gồm:

| Iceberg | Trino |
| --- | --- |
| `INT`, `LONG`, `FLOAT`, `DOUBLE` | `INTEGER`, `BIGINT`, `REAL`, `DOUBLE` |
| `DECIMAL(p,s)` | `DECIMAL(p,s)` |
| `STRING`, `UUID`, `BINARY`, `FIXED(L)` | `VARCHAR`, `UUID`, `VARBINARY`, `VARBINARY` |
| `STRUCT`, `LIST`, `MAP` | `ROW`, `ARRAY`, `MAP` |
| `TIMESTAMP`, `TIMESTAMPTZ` | `TIMESTAMP(6)`, `TIMESTAMP(6) WITH TIME ZONE` |
| `TIMESTAMP_NS`, `TIMESTAMPTZ_NS` | `TIMESTAMP(9)`, `TIMESTAMP(9) WITH TIME ZONE` (chỉ v3) |

Iceberg `VARIANT` chỉ hỗ trợ cho bảng format version 3 hoặc cao hơn; tạo bảng có cột này bằng `format_version = 3`. Không phải mọi type Trino/Iceberg đều được hỗ trợ, và mapping không phải lúc nào cũng đối xứng. Hãy kiểm thử type mapping với dữ liệu thật trước khi di trú hoặc bật ghi từ nhiều engine.

### 6. SQL: schema, table, snapshot và thay đổi dữ liệu

Connector hỗ trợ `CREATE/DROP/ALTER SCHEMA`, `CREATE/DROP/ALTER TABLE`, `CTAS`, view, materialized view, `INSERT`, `UPDATE`, `DELETE`, `TRUNCATE` và `MERGE`.

Tạo schema cần xác định location nếu metadata catalog/file-system của bạn yêu cầu. Bảng không có table property `location` sẽ được đặt dưới schema location. Chạy SQL sau trong catalog Iceberg để tạo một schema và bảng thử nghiệm; thay URI bằng location thuộc storage bạn quản lý.

```sql
CREATE SCHEMA iceberg.analytics
WITH (location = 's3://my-bucket/a/path/');

CREATE TABLE iceberg.analytics.events (
    event_id BIGINT,
    event_date DATE,
    customer_id BIGINT
)
WITH (
    format = 'PARQUET',
    partitioning = ARRAY['month(event_date)'],
    sorted_by = ARRAY['event_date']
);
```

Row-level delete cần Iceberg format v2 vì connector ghi position delete files. Schema evolution hỗ trợ thêm, xóa, đổi tên cột (kể cả nested structure) và chỉ hỗ trợ widening type: `INTEGER` → `BIGINT`, `REAL` → `DOUBLE`, hoặc tăng precision của `DECIMAL` nhưng không đổi scale. Partitioning có thể thay đổi mà vẫn truy vấn được dữ liệu cũ.

#### 6.1 Table properties quan trọng

| Table property trong `WITH` | Ý nghĩa và mặc định |
| --- | --- |
| `format` | `PARQUET`, `ORC` hoặc `AVRO`; mặc định lấy từ `iceberg.file-format`. |
| `compression_codec` | `NONE`, `ZSTD`, `SNAPPY`, `LZ4`, `GZIP`; mặc định lấy từ `iceberg.compression-codec`. |
| `partitioning` | Mảng transform/cột partition, ví dụ `ARRAY['month(event_date)']`. |
| `sorted_by` | Mảng cột/thứ tự sắp xếp trong **từng file**, không phải thứ tự toàn dataset. |
| `location` | URI location của table. |
| `format_version` | `1`, `2`, `3`; mặc định `2`. v2 cần cho row-level delete; v3 experimental. |
| `max_commit_retry` | Số retry commit; mặc định theo `iceberg.max-commit-retry`, là `4`. |
| `delete_after_commit_enabled` | Xóa metadata version cũ sau commit; mặc định `false`. |
| `max_previous_versions` | Số metadata version trước đó cần track; mặc định `100`. |
| `orc_bloom_filter_columns` / `parquet_bloom_filter_columns` | Cột dùng bloom filter cho predicate equality/`IN`; cần đúng định dạng file. |
| `object_store_layout_enabled` | Bật object-store layout cho bảng; mặc định `false`. |

Sau khi tạo, có thể cập nhật `format`, `format_version`, `partitioning`, `sorted_by`, `max_commit_retry`, `delete_after_commit_enabled`, `max_previous_versions`, `object_store_layout_enabled` và `data_location` qua `ALTER TABLE SET PROPERTIES`. Dùng `SHOW CREATE TABLE` để xem property hiện tại trước khi thay đổi.

#### 6.2 Snapshot, time travel và metadata tables

Mỗi thay đổi tạo snapshot. Metadata tables hữu ích nhất là `$properties`, `$history`, `$snapshots`, `$manifests`, `$partitions`, `$files`, `$entries` và `$refs`. Chạy truy vấn sau để xác định snapshot và đọc phiên bản cũ; thay `events` bằng tên bảng thật.

```sql
SELECT snapshot_id, committed_at, operation
FROM iceberg.analytics."events$snapshots"
ORDER BY committed_at DESC;

SELECT *
FROM iceberg.analytics.events
FOR VERSION AS OF 8954597067493422955;
```

Time travel cũng hỗ trợ `FOR TIMESTAMP AS OF`, branch và tag. Không expire snapshot hay xóa file cũ trước khi xác định mọi consumer còn cần phạm vi time travel nào.

#### 6.3 Procedures và bảo trì

Các procedure ở schema `system` của catalog. `register_table` và `add_files` phải được bật rõ ràng bằng property tương ứng trước khi gọi. Chỉ cấp quyền dùng chúng cho người vận hành vì chúng có thể khiến metadata trỏ đến dữ liệu hiện hữu không như kỳ vọng.

`optimize` gom nhiều file nhỏ thành file lớn hơn theo partition, giúp đọc hiệu quả hơn. Lệnh sau là thao tác thay đổi dữ liệu; chỉ chạy trên bảng được chọn và theo dõi metric trả về.

```sql
ALTER TABLE iceberg.analytics.events EXECUTE optimize(file_size_threshold => '128MB');
```

`expire_snapshots` dọn snapshot cũ; `remove_orphan_files` xóa file không còn được metadata liên kết. Ngưỡng retention của procedure không được thấp hơn `iceberg.expire-snapshots.min-retention` hoặc `iceberg.remove-orphan-files.min-retention`. Chạy các lệnh sau chỉ sau khi đã xác minh chính sách giữ dữ liệu, reader và writer khác.

```sql
ALTER TABLE iceberg.analytics.events EXECUTE expire_snapshots(retention_threshold => '7d');
ALTER TABLE iceberg.analytics.events EXECUTE remove_orphan_files(retention_threshold => '7d');
```

`table_changes` trả về thay đổi cấp dòng giữa hai snapshot, nhưng không hỗ trợ snapshot có delete files và không tính “net effect” của nhiều snapshot. Nếu một hàng bị xóa rồi thêm lại trong phạm vi, kết quả vẫn có cả delete và insert.

### 7. Hiệu năng và các điểm cần theo dõi

- Partition theo filter phổ biến, nhưng tránh partition quá mịn gây nhiều file nhỏ. Dùng transform như `month(event_date)` khi phù hợp.
- `sorted_by` hữu ích nhất cho cột cardinality cao thường dùng với selective filter; sorting là theo từng output file.
- Chạy `ANALYZE` cho join key, predicate hoặc grouping key trên bảng lớn để giúp cost-based optimizer. Thu thập toàn bộ cột của bảng rộng có thể tốn kém.
- Dùng `optimize` theo partition khi xuất hiện file nhỏ hoặc delete files; đo hiệu quả trước và sau khi chạy.
- Kiểm tra `$files` và `$snapshots` để phát hiện số file, delete files, snapshot tăng bất thường.
- Metadata cache, Parquet footer cache và số planning thread là tuning nâng cao. Thay đổi từng biến, đo query representative và theo dõi memory coordinator.
- Materialized view có thể refresh incremental; cách này thường quét ít dữ liệu hơn nhưng có thể sinh nhiều file hơn so với full refresh.

### 8. Kiểm thử triển khai

Sau khi deploy catalog, xem log coordinator để bảo đảm catalog nạp thành công, sau đó chạy các truy vấn sau. Chúng xác nhận catalog, schema, quyền đọc/ghi, metadata và snapshot cơ bản.

```sql
SHOW SCHEMAS FROM iceberg;
SHOW TABLES FROM iceberg.analytics;
SELECT * FROM iceberg.analytics.events LIMIT 10;
SELECT * FROM iceberg.analytics."events$properties";
SELECT snapshot_id, committed_at
FROM iceberg.analytics."events$snapshots"
ORDER BY committed_at DESC;
```

Tiếp theo, trong schema/bucket thử nghiệm, tạo bảng, chèn dữ liệu, xác minh snapshot mới, chạy `EXPLAIN` cho truy vấn có partition filter, rồi thử một thao tác `UPDATE` hoặc `DELETE` nếu bảng dùng format v2. Kiểm thử allow và deny bằng các user/role thực tế nếu bật access control.

### 9. Checklist vận hành

- [ ] File `etc/catalog/iceberg.properties` dùng `connector.name=iceberg`, đúng một metadata catalog và đúng một file-system configuration.
- [ ] Coordinator **và tất cả worker** có network access, credential và quyền storage/metastore cần thiết.
- [ ] Đã chọn rõ format version; không dùng v3 experimental cho row-level update/delete/optimize.
- [ ] Đã kiểm thử type mapping, timezone, dữ liệu nested và dữ liệu từ engine khác.
- [ ] `iceberg.security` không để `ALLOW_ALL` ngoài môi trường được kiểm soát; quyền Trino và quyền storage nhất quán.
- [ ] `register_table`, `add_files`, `expire_snapshots`, `remove_orphan_files` chỉ cấp cho người vận hành có quy trình phê duyệt.
- [ ] Retention phản ánh nhu cầu time travel, rollback, backup và consumer khác; không hạ xuống tùy tiện.
- [ ] Theo dõi file nhỏ, snapshot/metadata growth, planner memory và thống kê sau khi workload thay đổi.
- [ ] Đã kiểm thử đọc, ghi, time travel, rollback và access-control trong môi trường thử nghiệm trước production.

---

## MySQL connector cho Trino

> Tóm tắt theo [MySQL connector — Trino current](https://trino.io/docs/current/connector/mysql.html) (đối chiếu Trino 482 ngày 2026-07-14).

MySQL connector là JDBC connector cho phép Trino đọc, tạo và thay đổi dữ liệu/metadata trong MySQL bên ngoài. Nó phù hợp khi cần join MySQL với các catalog Trino khác, nhưng hiệu quả vẫn phụ thuộc vào pushdown, lượng dữ liệu truyền qua mạng và năng lực MySQL source.

### 1. Yêu cầu và phạm vi

- MySQL 5.7, 8.0 hoặc cao hơn.
- Coordinator và toàn bộ worker truy cập mạng được MySQL; cổng mặc định là `3306`.
- User JDBC có đúng quyền MySQL tối thiểu.
- Có thể tạo nhiều catalog, mỗi file `etc/catalog/<tên>.properties` cho một server/kết nối. Catalog name là tên file không có `.properties`.

### 2. Cách tạo catalog và TLS

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

### 3. Credential provider và property kết nối

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

TLS giữa Trino và MySQL không thay thế TLS/authentication của client đến Trino hay access control trong Trino. Không ghi secret và keystore password vào Git.

### 4. Property catalog quan trọng

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

### 5. Type mapping và timezone

Các mapping thường gặp: MySQL `JSON` → Trino `JSON`, `BINARY`/`BLOB` → `VARBINARY`, `ENUM` → `VARCHAR`, `DECIMAL(p,s)` → `DECIMAL(p,s)` khi `p ≤ 38` (lớn hơn chuyển `NUMBER`), `DATETIME` → `TIMESTAMP`, và `TIMESTAMP` → `TIMESTAMP WITH TIME ZONE`.

MySQL connector đặt session time zone của MySQL connection theo JVM time zone để giữ time instant cho MySQL `TIMESTAMP`. Time zone đó phải tồn tại ở cả JVM và MySQL server; nếu không, query có thể lỗi `Unknown or incorrect time zone`. Kiểm thử timestamp/DST với dữ liệu thật trước production.

### 6. SQL support và giới hạn ghi

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

### 7. Hiệu năng, bảo mật và kiểm thử

Trino có thể push predicate, aggregation, join và Top-N tùy query/type/capability MySQL. Dùng `EXPLAIN` để xác minh thực tế; join giữa MySQL và catalog khác thường cần Trino xử lý dữ liệu sau khi đọc từ source.

Áp dụng TLS, least-privilege MySQL user và system access control của Trino. Xem [file-based access control](../security/README.md#file-based-access-control-cho-trino) nếu dùng file rule cho policy Trino.

- [ ] Tất cả worker kết nối được MySQL qua network và TLS theo yêu cầu.
- [ ] Credential không nằm trong Git, user MySQL có least privilege.
- [ ] Đã kiểm thử `DECIMAL`, JSON, BLOB, `DATETIME`, `TIMESTAMP`, timezone/DST và type ứng dụng đặc thù.
- [ ] Đã xác minh pushdown bằng `EXPLAIN` cho query quan trọng.
- [ ] DDL/DML được thử trong schema/table thử nghiệm trước production.
- [ ] Non-transactional `INSERT`/`MERGE` chỉ bật khi có chấp nhận rủi ro partial write.

---

## PostgreSQL connector cho Trino

> Tóm tắt theo [PostgreSQL connector — Trino current](https://trino.io/docs/current/connector/postgresql.html) (đối chiếu Trino 482 ngày 2026-07-14).

PostgreSQL connector là JDBC connector cho phép Trino đọc, tạo và thay đổi dữ liệu/metadata trong một PostgreSQL database bên ngoài. Nó phù hợp cho truy vấn liên catalog, ví dụ join dữ liệu PostgreSQL với dữ liệu lakehouse, nhưng không biến PostgreSQL thành kho phân tích phân tán.

### 1. Yêu cầu và phạm vi

- PostgreSQL 12.x hoặc cao hơn.
- Coordinator và mọi worker truy cập mạng được đến PostgreSQL; cổng mặc định là `5432`.
- User dùng cho JDBC connection có đúng quyền tối thiểu cần thiết trên database đích.
- Một catalog PostgreSQL chỉ truy cập **một database** trên một PostgreSQL server. Cần nhiều file catalog nếu muốn truy cập nhiều database hoặc server.

File `etc/catalog/<tên>.properties` tạo catalog `<tên>`. Ví dụ `etc/catalog/postgresql.properties` tạo catalog `postgresql`, được dùng trong `postgresql.schema_name.table_name`.

### 2. Cách tạo catalog và kết nối TLS

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

### 3. Credential provider và property kết nối

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

Không lưu secret/keystore password trong Git. TLS của JDBC connection và authentication/authorization của client đến Trino là hai lớp khác nhau; cấu hình cả hai khi cần.

### 4. Property catalog quan trọng

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

### 5. Type mapping và các điểm cần chú ý

Các mapping chính: `NUMERIC(p,s)` → `DECIMAL(p,s)` hoặc `NUMBER`, `BYTEA` → `VARBINARY`, `JSON`/`JSONB` → `JSON`, `UUID` → `UUID`, `TIMESTAMPTZ` → `TIMESTAMP WITH TIME ZONE`, `ARRAY` → `ARRAY` hoặc `JSON` tùy `postgresql.array-mapping`, và PostGIS `GEOMETRY`/`POINT` → `GEOMETRY`.

PostgreSQL array không có fixed dimension trong khi Trino array yêu cầu fixed dimension. Vì vậy `DISABLED` là mặc định; chọn `AS_ARRAY` chỉ khi array có dimension cố định, hoặc `AS_JSON` khi cần giữ array dimension linh hoạt. Type không được hỗ trợ bị bỏ qua theo mặc định, nên hãy kiểm tra `DESCRIBE`/`SHOW COLUMNS` sau khi nạp catalog.

### 6. SQL support và giới hạn ghi

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

### 7. Hiệu năng, bảo mật và kiểm thử

Predicate, aggregation, join và Top-N có thể được pushdown tùy query/type/capability của PostgreSQL. Dùng `EXPLAIN` để xác nhận pushdown thực tế; không giả định join liên catalog được đẩy xuống PostgreSQL. `ANALYZE`/statistics bên PostgreSQL và statistics Trino giúp planning tốt hơn.

Áp dụng system access control của Trino để giới hạn catalog/schema/table, đồng thời giữ quyền PostgreSQL và TLS tối thiểu. Xem [file-based access control](../security/README.md#file-based-access-control-cho-trino) nếu policy dùng file rule.

- [ ] Từng worker kết nối được PostgreSQL qua network/TLS theo yêu cầu.
- [ ] Catalog trỏ đúng một database; database/server khác dùng catalog riêng.
- [ ] Credential không nằm trong Git và user database có least privilege.
- [ ] Đã kiểm thử numeric, JSONB, UUID, timestamp, array và geometry (nếu có).
- [ ] Đã xác minh pushdown bằng `EXPLAIN` với query quan trọng.
- [ ] DML/DDL được thử trong database hoặc schema thử nghiệm trước production.
- [ ] Non-transactional `INSERT`/`MERGE` chỉ bật khi chấp nhận rõ ràng rủi ro partial write.

## References

- [Trino — Delta Lake connector](https://trino.io/docs/current/connector/delta-lake.html)
- [Trino — Object storage](https://trino.io/docs/current/object-storage.html)
- [Trino — File-based access control](https://trino.io/docs/current/security/file-system-access-control.html)
- [Trino — Hive connector](https://trino.io/docs/current/connector/hive.html)
- [Trino — Iceberg connector](https://trino.io/docs/current/connector/iceberg.html)
- [Trino — Metastores](https://trino.io/docs/current/object-storage/metastores.html)
- [Apache Iceberg — Table specification](https://iceberg.apache.org/spec/)
- [Trino — MySQL connector](https://trino.io/docs/current/connector/mysql.html)
- [MySQL Connector/J Developer Guide](https://dev.mysql.com/doc/connector-j/en/)
- [Trino — PostgreSQL connector](https://trino.io/docs/current/connector/postgresql.html)
- [PostgreSQL JDBC driver documentation](https://jdbc.postgresql.org/documentation/)
