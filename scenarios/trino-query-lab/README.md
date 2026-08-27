# Kịch bản truy vấn và kiểm thử Trino

Kịch bản này dùng ba catalog có sẵn trong lab:

- `tpch`: nguồn dữ liệu chuẩn để tạo dữ liệu thử.
- `iceberg`: dữ liệu phân tích trong schema `query_scenario`.
- `postgres_ops`: dữ liệu mục tiêu vận hành trong PostgreSQL.

Kịch bản bao phủ truy vấn một catalog, truy vấn liên catalog, quyền ở mức bảng, cột và hàng, cùng một quy trình đo hiệu năng có thể lặp lại. Dữ liệu nghiệp vụ được tạo giả lập từ TPC-H `sf10`; không dùng các bảng hiện có ngoài schema riêng `iceberg.query_scenario`.

## 1. Vai trò và kết quả mong đợi

| User | Group hiện có | Phạm vi trong kịch bản |
| --- | --- | --- |
| `admin` | Không bắt buộc | Tạo dữ liệu, xem toàn bộ dữ liệu và chạy benchmark. |
| `de1` | `data_engineering` | Đọc/ghi toàn bộ bảng trong `iceberg.query_scenario`. |
| `da1` | `data_analytics` | Chỉ đọc dữ liệu `region_code = 1`; không đọc `address`; `phone` bị mask. |
| `da2` | `data_analytics` | Chỉ đọc dữ liệu `region_code = 2`; không đọc `address`; `phone` bị mask. |

`da1` và `da2` không được đọc bảng `supplier_confidential`. Cả hai được phép đọc các bảng cần thiết trong `postgres_ops.ops` để chạy truy vấn liên catalog.

## 2. Chuẩn bị

Khởi động cluster theo cấu hình của repository và bảo đảm các service Trino, Hive Metastore, MinIO và PostgreSQL Ops đều sẵn sàng. Khởi tạo dữ liệu PostgreSQL Ops bằng file `postgres-ops/sql/001_operational_tables.sql` nếu các bảng trong schema `ops` chưa tồn tại.

Mở Trino CLI bằng user `admin`, rồi chạy file [00_setup.sql](sql/00_setup.sql). File này xóa và tạo lại **chỉ ba bảng thuộc schema lab** `iceberg.query_scenario`, sau đó nạp khoảng 15 triệu dòng chuyến đi từ `tpch.sf10.orders`.

Ví dụ chạy từ một Trino CLI đã kết nối:

```text
trino> SOURCE scenarios/trino-query-lab/sql/00_setup.sql;
```

Nếu CLI chạy ngoài container, dùng đường dẫn tuyệt đối mà CLI đó có thể đọc. `SOURCE` là lệnh của CLI, không phải câu SQL gửi qua JDBC.

Kiểm tra dữ liệu sau khi nạp:

```sql
SELECT count(*) AS trip_rows
FROM iceberg.query_scenario.trip_fact;

SELECT count(*) AS customer_rows
FROM iceberg.query_scenario.customer_secure;
```

Giá trị mong đợi lần lượt là `15000000` và `1500000` khi dùng `tpch.sf10`. Bảng `supplier_confidential` có `100000` dòng.

### Chọn kích thước dữ liệu

TPC-H connector sinh dữ liệu xác định ngay khi đọc, nên không cần tải dataset nguồn. Dữ liệu chỉ chiếm object storage sau khi các lệnh CTAS ghi chúng sang Iceberg.

| Schema TPC-H | `trip_fact` | `customer_secure` | `supplier_confidential` | Mục đích |
| --- | ---: | ---: | ---: | --- |
| `tiny` | 15.000 | 1.500 | 100 | Smoke test cú pháp. |
| `sf1` | 1.500.000 | 150.000 | 10.000 | Kiểm thử chức năng nhanh. |
| `sf10` | 15.000.000 | 1.500.000 | 100.000 | Profile mặc định để test hiệu năng lab. |
| `sf100` | 150.000.000 | 15.000.000 | 1.000.000 | Stress test; cần kiểm tra trước dung lượng và thời gian chạy. |

Để đổi scale, sửa đồng nhất ba nguồn `tpch.sf10.orders`, `tpch.sf10.customer` và `tpch.sf10.supplier` trong `sql/00_setup.sql`. Không trộn nhiều scale trong cùng một lần setup vì khóa khách hàng của `orders` phải khớp với bảng `customer`.

## 3. Truy vấn một catalog

Chạy [01_single_catalog.sql](sql/01_single_catalog.sql) để kiểm tra:

1. Scan và aggregate chỉ trong Iceberg.
2. Join hai bảng trong cùng catalog `iceberg`.
3. Predicate trên `metric_month` để quan sát partition pruning.

Với `da1` hoặc `da2`, row filter được ghép vào truy vấn trước khi tính aggregate. Vì vậy tổng số dòng và doanh thu quan sát được của hai user khác nhau, còn `admin` thấy toàn bộ dữ liệu.

## 4. Truy vấn đa catalog

Chạy [02_multi_catalog.sql](sql/02_multi_catalog.sql). Query aggregate dữ liệu thực tế ở Iceberg trước, sau đó join với KPI mục tiêu trong PostgreSQL:

```text
iceberg.query_scenario.trip_fact
              │ aggregate theo tháng/base
              ▼
      kết quả trung gian nhỏ
              │
              ├── JOIN ── postgres_ops.ops.base_monthly_kpi_target
              ▼
       mức hoàn thành KPI
```

Trino không thể push toàn bộ join này xuống một nguồn vì hai bảng thuộc hai catalog khác nhau. Filter và projection trên từng scan vẫn có thể được connector tương ứng push down. Dùng `EXPLAIN (TYPE DISTRIBUTED)` trong file để xác nhận plan còn một join do Trino thực hiện.

## 5. Áp dụng policy kiểm thử

File [rules.json](security/rules.json) là policy mẫu hoàn chỉnh dành cho kịch bản. Nó không được tự động gắn vào runtime để tránh vô tình thay policy hiện tại.

Để dùng policy này, sao lưu policy đang vận hành theo quy trình của bạn, sau đó cấu hình `etc/access-control.properties` trên coordinator trỏ đến file JSON đã được đặt trong filesystem mà process Trino đọc được.

Tạo `etc/access-control.properties` và đặt nội dung sau vào file:

```properties
access-control.name=file
security.config-file=etc/query-scenario-rules.json
security.refresh-period=1s
```

Đặt bản sao của `security/rules.json` tại `etc/query-scenario-rules.json`. Với cấu hình có `security.refresh-period`, Trino tự nạp lại policy; nếu không dùng refresh, cần restart coordinator. Rule được xét từ trên xuống và rule đầu tiên khớp sẽ thắng, nên các ngoại lệ cụ thể cho `customer_secure` và `supplier_confidential` phải đứng trước rule cho phép rộng hơn.

Giữ hoặc cập nhật `etc/group.txt` với mapping group dùng trong kịch bản sau:

```text
data_engineering:de1,de2
data_science:ds1,ds2
data_analytics:da1,da2
```

Không dùng file policy mẫu này cho production nếu chưa review các rule fallback, quyền ghi và quyền ở nguồn dữ liệu bên dưới.

## 6. Ma trận kiểm thử phân quyền

Chạy các câu trong [03_security_tests.sql](sql/03_security_tests.sql) riêng bằng từng user. Không chạy cả file như một batch vì file cố ý chứa các truy vấn phải thất bại.

| Case | User | Kết quả mong đợi |
| --- | --- | --- |
| S01 | `admin` | Thấy cả `region_code` 1 và 2. |
| S02 | `da1` | Chỉ thấy `region_code = 1`. |
| S03 | `da2` | Chỉ thấy `region_code = 2`. |
| S04 | `da1`/`da2` | `phone` có dạng mask; không thấy số gốc. |
| S05 | `da1`/`da2` | Chọn cột `address` bị `Access Denied`. |
| S06 | `da1`/`da2` | `SELECT *` thất bại vì chứa cột không được phép. |
| S07 | `da1`/`da2` | Đọc `supplier_confidential` bị từ chối. |
| S08 | `de1` | Đọc được `supplier_confidential`. |
| S09 | `da1`/`da2` | Query liên catalog chạy được nhưng chỉ dùng các hàng thuộc region của user. |

Mặc định, `SELECT *` thất bại nếu có một cột không được phép. Có thể bật `hide-inaccessible-columns=true` ở system access control nếu muốn tự ẩn cột, nhưng việc đó thay đổi hành vi toàn cluster và không cần thiết cho bài test này.

## 7. Kiểm thử hiệu năng

Chạy [04_performance.sql](sql/04_performance.sql) bằng `admin`. File gồm:

- P01: aggregate toàn bảng, dùng làm baseline throughput.
- P02: cùng dạng aggregate nhưng lọc một tháng, dùng để kiểm tra partition pruning.
- P03: join trong một catalog Iceberg.
- P04: join liên catalog Iceberg–PostgreSQL sau khi aggregate.

Quy trình đo:

1. Chạy từng query một lần để warm up metadata, connection pool và cache.
2. Chạy lại mỗi query ít nhất 5 lần, tuần tự và không thay đổi session properties giữa các lần.
3. Ghi median và p95 của elapsed time; không chỉ lấy lần nhanh nhất.
4. Trong Web UI, lưu query ID, CPU time, scheduled time, processed rows/bytes, peak memory, số split và lượng dữ liệu qua exchange.
5. Dùng `EXPLAIN ANALYZE` chỉ khi chấp nhận query thực sự chạy.
6. So sánh P01 với P02 để đánh giá pruning; so sánh P03 với P04 để nhận diện chi phí connector và exchange, không coi đây là hai query có workload hoàn toàn tương đương.

Mẫu ghi kết quả:

| Query | Lần 1 | Lần 2 | Lần 3 | Lần 4 | Lần 5 | Median | p95 | Processed bytes | Peak memory |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| P01 |  |  |  |  |  |  |  |  |  |
| P02 |  |  |  |  |  |  |  |  |  |
| P03 |  |  |  |  |  |  |  |  |  |
| P04 |  |  |  |  |  |  |  |  |  |

Không chạy nhiều query đồng thời trong baseline. Nếu mục tiêu là concurrency test, cố định số client, ramp-up, thời lượng, think time và workload mix rồi báo cáo throughput cùng latency p50/p95/p99 thành một bài test riêng.

## 8. Tiêu chí hoàn thành

- [ ] Hai bảng nguồn thử nghiệm có đúng số dòng mong đợi.
- [ ] Query một catalog và đa catalog cho kết quả hợp lệ.
- [ ] Các allow case và deny case trong ma trận đều đúng.
- [ ] `da1` và `da2` không nhìn thấy hàng của nhau.
- [ ] Column mask không làm lộ giá trị gốc; cột bị cấm thực sự trả lỗi.
- [ ] Plan P02 cho thấy lượng dữ liệu đọc giảm so với P01.
- [ ] Plan đa catalog còn join/exchange do Trino thực hiện.
- [ ] Mỗi benchmark có ít nhất 5 lần đo và lưu query ID để truy vết.

## References

- [Trino — File-based access control](https://trino.io/docs/current/security/file-system-access-control.html)
- [Trino — TPC-H connector](https://trino.io/docs/current/connector/tpch.html)
- [Trino — Iceberg connector](https://trino.io/docs/current/connector/iceberg.html)
- [Trino — EXPLAIN](https://trino.io/docs/current/sql/explain.html)
- [Trino — EXPLAIN ANALYZE](https://trino.io/docs/current/sql/explain-analyze.html)
- [Trino — Web UI](https://trino.io/docs/current/admin/web-interface.html)
- [Trino — Cost-based optimizations](https://trino.io/docs/current/optimizer/cost-based-optimizations.html)
