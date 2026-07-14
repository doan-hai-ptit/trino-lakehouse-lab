# Iceberg connector cho Trino

> Tóm tắt theo [Iceberg connector — Trino current](https://trino.io/docs/current/connector/iceberg.html) (đối chiếu Trino 482 ngày 2026-07-14).

Iceberg connector cho phép Trino đọc và ghi các bảng theo Apache Iceberg table format. Iceberg lưu trạng thái bảng trong metadata files: mỗi lần thay đổi sẽ tạo metadata file mới và thay thế tham chiếu metadata cũ theo cách atomic. Metadata lưu schema, partitioning, table properties và snapshot; data files có thể dùng Parquet, ORC hoặc Avro.

Iceberg khác Hive truyền thống ở chỗ metadata lưu đường dẫn cụ thể đến data files. Vì vậy, Trino không cần liệt kê toàn bộ file trong từng partition trước khi đọc. Đây là lợi thế quan trọng khi bảng có rất nhiều partition hoặc file.

## 1. Phạm vi, phiên bản và yêu cầu

Connector hỗ trợ Iceberg table spec v1 và v2. Hỗ trợ format version 3 là **experimental**. `VARIANT`, `TIMESTAMP_NS` và `TIMESTAMPTZ_NS` cần format version 3; đồng thời v3 hiện không hỗ trợ row-level `UPDATE`, `DELETE`, `OPTIMIZE`, cũng như một số tính năng v3 như column default value và encryption.

Trước khi tạo catalog, cần bảo đảm:

- Coordinator và mọi worker truy cập mạng được đến object storage hoặc HDFS chứa data/metadata files.
- Có đúng một metadata catalog cho catalog Trino này: Hive Metastore (HMS), AWS Glue, JDBC, REST, Nessie hoặc Snowflake catalog.
- Data files là Parquet (mặc định), ORC hoặc Avro trên file system được Trino hỗ trợ.
- Identity chạy Trino có quyền đọc metadata/data và, nếu ghi, có quyền tạo/đổi tên/xóa tệp theo thao tác thực hiện.
- Khi dùng HMS qua Thrift hoặc HDFS có Kerberos, cấu hình Kerberos theo phần Hive/HDFS của tài liệu Trino.

## 2. Mô hình catalog và cách chọn cấu hình

Mỗi file `etc/catalog/<tên>.properties` tạo một catalog Trino có tên `<tên>`. Ví dụ, `etc/catalog/iceberg.properties` tạo catalog `iceberg`, được dùng trong tên đầy đủ `iceberg.schema_name.table_name`.

Một catalog Iceberg gồm ba lớp độc lập:

| Lớp | Vai trò | Lựa chọn chính |
| --- | --- | --- |
| Connector | Cung cấp SQL, metadata và logic Iceberg cho Trino. | `connector.name=iceberg` |
| Metadata catalog | Lưu/định vị metadata của schema và bảng. | HMS, Glue, JDBC, REST, Nessie hoặc Snowflake |
| File system | Lưu metadata files, manifests và data files. | S3, Azure Storage, Google Cloud Storage hoặc HDFS |

Chọn **một** metadata catalog và **một** cơ chế file-system access cho mỗi file catalog. Không ghép cấu hình của HMS với REST/Nessie/Glue trong cùng `iceberg.properties`.

### 2.1 Cấu hình tối thiểu với Hive Metastore

HMS là `iceberg.catalog.type` mặc định. Tạo `etc/catalog/iceberg.properties` và đặt nội dung sau vào đó khi dùng Hive Metastore; thay `fs.x.enabled` bằng property bật đúng file system của bạn.

```properties
connector.name=iceberg
hive.metastore.uri=thrift://example.net:9083
fs.x.enabled=true
```

`fs.x.enabled=true` trong ví dụ chính thức là chỗ giữ chỗ, không phải property có thể dùng nguyên trạng. Hãy chọn đúng một hướng dẫn file system của Trino và thay nó bằng property phù hợp, ví dụ cấu hình S3, Azure Storage, GCS hoặc `fs.hadoop.enabled` cho HDFS. Chỉ dùng `fs.hadoop.enabled` cho HDFS.

### 2.2 Metadata catalog khác HMS

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

## 3. Property catalog quan trọng

Không cần đặt mọi property dưới đây: các giá trị mặc định của Trino là điểm khởi đầu hợp lý. Chỉ ghi đè sau khi đo được nhu cầu về hiệu năng, layout, retention hoặc policy.

### 3.1 Metadata, định dạng và ghi dữ liệu

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

### 3.2 Planning, đọc dữ liệu và thống kê

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

### 3.3 Cache, concurrency và dọn dữ liệu

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

### 3.4 Procedure, materialized view và sorted writing

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

## 4. Cấu hình authorization

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

Quyền Trino không thay thế quyền ở storage/metastore: cả hai lớp phải cho phép thao tác hợp lệ. Xem [file-based access control](../security/FILE_SYSTEM_ACCESS_CONTROL.md) để biết thứ tự đánh giá rule và thiết kế policy.

## 5. Type mapping và khả năng tương thích

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

## 6. SQL: schema, table, snapshot và thay đổi dữ liệu

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

### 6.1 Table properties quan trọng

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

### 6.2 Snapshot, time travel và metadata tables

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

### 6.3 Procedures và bảo trì

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

## 7. Hiệu năng và các điểm cần theo dõi

- Partition theo filter phổ biến, nhưng tránh partition quá mịn gây nhiều file nhỏ. Dùng transform như `month(event_date)` khi phù hợp.
- `sorted_by` hữu ích nhất cho cột cardinality cao thường dùng với selective filter; sorting là theo từng output file.
- Chạy `ANALYZE` cho join key, predicate hoặc grouping key trên bảng lớn để giúp cost-based optimizer. Thu thập toàn bộ cột của bảng rộng có thể tốn kém.
- Dùng `optimize` theo partition khi xuất hiện file nhỏ hoặc delete files; đo hiệu quả trước và sau khi chạy.
- Kiểm tra `$files` và `$snapshots` để phát hiện số file, delete files, snapshot tăng bất thường.
- Metadata cache, Parquet footer cache và số planning thread là tuning nâng cao. Thay đổi từng biến, đo query representative và theo dõi memory coordinator.
- Materialized view có thể refresh incremental; cách này thường quét ít dữ liệu hơn nhưng có thể sinh nhiều file hơn so với full refresh.

## 8. Kiểm thử triển khai

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

## 9. Checklist vận hành

- [ ] File `etc/catalog/iceberg.properties` dùng `connector.name=iceberg`, đúng một metadata catalog và đúng một file-system configuration.
- [ ] Coordinator **và tất cả worker** có network access, credential và quyền storage/metastore cần thiết.
- [ ] Đã chọn rõ format version; không dùng v3 experimental cho row-level update/delete/optimize.
- [ ] Đã kiểm thử type mapping, timezone, dữ liệu nested và dữ liệu từ engine khác.
- [ ] `iceberg.security` không để `ALLOW_ALL` ngoài môi trường được kiểm soát; quyền Trino và quyền storage nhất quán.
- [ ] `register_table`, `add_files`, `expire_snapshots`, `remove_orphan_files` chỉ cấp cho người vận hành có quy trình phê duyệt.
- [ ] Retention phản ánh nhu cầu time travel, rollback, backup và consumer khác; không hạ xuống tùy tiện.
- [ ] Theo dõi file nhỏ, snapshot/metadata growth, planner memory và thống kê sau khi workload thay đổi.
- [ ] Đã kiểm thử đọc, ghi, time travel, rollback và access-control trong môi trường thử nghiệm trước production.

## References

- [Trino — Iceberg connector](https://trino.io/docs/current/connector/iceberg.html)
- [Trino — Object storage](https://trino.io/docs/current/object-storage.html)
- [Trino — Metastores](https://trino.io/docs/current/object-storage/metastores.html)
- [Trino — File-based access control](https://trino.io/docs/current/security/file-system-access-control.html)
- [Apache Iceberg — Table specification](https://iceberg.apache.org/spec/)
