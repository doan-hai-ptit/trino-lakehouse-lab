# Báo cáo kiểm thử hiệu năng NYC FHVHV Lakehouse

Tài liệu này là mẫu ghi nhận kết quả cho các truy vấn P00–P12 trong [NYC_FHVHV_PERFORMANCE_TEST.sql](NYC_FHVHV_PERFORMANCE_TEST.sql). Điền các ô `_____` sau khi chạy kiểm thử; không cần chép lại câu SQL vào báo cáo.

`EXPLAIN ANALYZE` thực thi truy vấn thật và trả về execution plan cùng số liệu thực thi. Với mỗi truy vấn, chạy một cold run và ít nhất hai warm run. Luôn dùng cùng nguồn số liệu cho một metric; không trộn số liệu toàn query với số liệu của riêng một fragment hoặc operator.

## 1. Thông tin báo cáo

| Trường | Giá trị |
| --- | --- |
| Tên đợt kiểm thử | _____ |
| Người thực hiện | _____ |
| Ngày, giờ bắt đầu | _____ |
| Ngày, giờ kết thúc | _____ |
| Múi giờ | _____ |
| Mục tiêu kiểm thử | _____ |
| Phiên bản tài liệu | _____ |
| Commit/tag ứng dụng | _____ |
| Kết luận chung | ☐ Đạt ☐ Không đạt ☐ Cần kiểm tra thêm |

## 2. Môi trường kiểm thử

### 2.1. Trino

| Trường | Giá trị |
| --- | --- |
| Phiên bản Trino | _____ |
| Số coordinator | _____ |
| Số worker | _____ |
| CPU mỗi coordinator | _____ |
| RAM mỗi coordinator | _____ |
| CPU mỗi worker | _____ |
| RAM mỗi worker | _____ |
| Heap tối đa mỗi node | _____ |
| Query max memory | _____ |
| Query max total memory | _____ |
| Spill enabled | _____ |
| Retry policy | _____ |
| Resource group | _____ |
| Session properties khác mặc định | _____ |

### 2.2. Nguồn dữ liệu và hạ tầng

| Trường | Iceberg/Object storage | PostgreSQL Mart |
| --- | --- | --- |
| Catalog | `iceberg` | `postgresql` |
| Khu vực/vị trí triển khai | _____ | _____ |
| CPU | Không áp dụng/_____ | _____ |
| RAM | Không áp dụng/_____ | _____ |
| Storage | _____ | _____ |
| Network tới Trino | _____ | _____ |
| Cache trước cold run | _____ | _____ |
| Tải nền trong lúc đo | _____ | _____ |
| Phiên bản connector/DB | _____ | _____ |

### 2.3. Dữ liệu kiểm thử

| Trường | Giá trị |
| --- | --- |
| Snapshot/version dữ liệu | _____ |
| Khoảng ngày trong `fact_trip` | _____ đến _____ |
| Tổng số dòng `fact_trip` | _____ |
| Dung lượng vật lý `fact_trip` | _____ |
| Số data file `fact_trip` | _____ |
| Kích thước file trung bình | _____ |
| Partition transform | `month(pickup_date)` |
| Tổng số dòng `daily_market_kpi` | _____ |
| Dung lượng `daily_market_kpi` | _____ |
| Dữ liệu thay đổi trong lúc đo | ☐ Không ☐ Có: _____ |

## 3. Quy ước đo

| Nội dung | Giá trị áp dụng |
| --- | --- |
| Số lần chạy mỗi truy vấn | 3/_____ |
| Run 1 | Cold run |
| Run 2–3 | Warm run |
| Số dùng để so sánh | Median của warm run/_____ |
| Đơn vị thời gian | ms/s: _____ |
| Đơn vị dữ liệu | MB/GiB: _____ |
| Cách tạo cold run | _____ |
| Thời gian nghỉ giữa các run | _____ |
| Client/công cụ chạy query | _____ |
| Có workload khác chạy đồng thời | ☐ Không ☐ Có: _____ |

Ghi số liệu theo các nguyên tắc sau:

- `Queued`, `Analysis`, `Planning` và `Execution`: lấy từ phần tổng quan của query.
- `CPU`: lấy total CPU của query từ cùng một nguồn quan sát cho mọi run. Nếu chỉ có CPU theo fragment, ghi rõ cách tổng hợp trong phần ghi chú.
- `Input rows` và `Physical input`: lấy tại scan/source operator liên quan; với truy vấn nhiều nguồn, ghi riêng từng nguồn trong phần phân tích plan.
- `Peak memory` và `Spilled`: lấy từ query statistics hoặc giao diện theo dõi query. Ghi `0 B` nếu xác nhận không spill; ghi `N/A` nếu metric không có.
- `Input std.dev.`: ghi giá trị lớn nhất đáng chú ý tại operator chính để đánh giá skew.
- Không dùng số liệu của query lỗi để tính median.

## 4. P00 — Statistics và phạm vi dữ liệu

### 4.1. `iceberg.silver.fact_trip`

| Column/summary | Row count | Data size | Distinct values | Null fraction | Low value | High value |
| --- | ---: | ---: | ---: | ---: | --- | --- |
| Table summary | _____ | _____ | N/A | N/A | N/A | N/A |
| `pickup_date` | N/A | _____ | _____ | _____ | _____ | _____ |
| `source_year` | N/A | _____ | _____ | _____ | _____ | _____ |
| `pu_location_id` | N/A | _____ | _____ | _____ | _____ | _____ |
| `dispatching_base_num` | N/A | _____ | _____ | _____ | _____ | _____ |
| `trip_miles` | N/A | _____ | _____ | _____ | _____ | _____ |
| `driver_pay` | N/A | _____ | _____ | _____ | _____ | _____ |

### 4.2. `fact_trip` trong tháng 01/2025

| Trường | Giá trị |
| --- | --- |
| Estimated row count | _____ |
| Estimated data size | _____ |
| `pickup_date` low/high | _____ / _____ |
| Statistics đầy đủ | ☐ Có ☐ Thiếu ☐ Toàn bộ `NULL` |
| Nhận xét | _____ |

### 4.3. `postgresql.mart.daily_market_kpi`

| Column/summary | Row count | Data size | Distinct values | Null fraction | Low value | High value |
| --- | ---: | ---: | ---: | ---: | --- | --- |
| Table summary | _____ | _____ | N/A | N/A | N/A | N/A |
| `metric_date` | N/A | _____ | _____ | _____ | _____ | _____ |
| `source_year` | N/A | _____ | _____ | _____ | _____ | _____ |
| `trip_count` | N/A | _____ | _____ | _____ | _____ | _____ |

### 4.4. Đánh giá statistics

| Kiểm tra | Kết quả | Ghi chú |
| --- | --- | --- |
| Optimizer có row count cho `fact_trip` | ☐ Có ☐ Không | _____ |
| Có min/max cho `pickup_date` | ☐ Có ☐ Không | _____ |
| Filter tháng làm giảm estimated rows | ☐ Có ☐ Không | _____ |
| PostgreSQL trả statistics cần thiết | ☐ Có ☐ Không | _____ |
| Cần thu thập/cập nhật statistics | ☐ Có ☐ Không | _____ |

## 5. Nhật ký chạy chi tiết

Điền một dòng cho mỗi lần chạy. `R1` là cold run; `R2` và `R3` là warm run.

| ID | Run | Query ID | Trạng thái | Queued | Analysis | Planning | Execution | CPU | Input rows | Physical input | Peak memory | Spilled | Input std.dev. lớn nhất |
| --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| P01 | R1 | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ |
| P01 | R2 | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ |
| P01 | R3 | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ |
| P02 | R1 | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ |
| P02 | R2 | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ |
| P02 | R3 | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ |
| P03 | R1 | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ |
| P03 | R2 | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ |
| P03 | R3 | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ |
| P04 | R1 | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ |
| P04 | R2 | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ |
| P04 | R3 | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ |
| P05 | R1 | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ |
| P05 | R2 | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ |
| P05 | R3 | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ |
| P06 | R1 | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ |
| P06 | R2 | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ |
| P06 | R3 | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ |
| P07 | R1 | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ |
| P07 | R2 | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ |
| P07 | R3 | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ |
| P08 | R1 | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ |
| P08 | R2 | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ |
| P08 | R3 | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ |
| P09 | R1 | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ |
| P09 | R2 | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ |
| P09 | R3 | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ |
| P10 | R1 | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ |
| P10 | R2 | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ |
| P10 | R3 | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ |
| P11-A | R1 | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ |
| P11-A | R2 | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ |
| P11-A | R3 | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ |
| P11-B | R1 | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ |
| P11-B | R2 | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ |
| P11-B | R3 | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ |

## 6. Kết quả tổng hợp P01–P11

Điền median của các warm run hợp lệ. Nếu chỉ có một warm run hợp lệ, đánh dấu trong cột ghi chú.

| ID | Mục tiêu | Median execution | Median CPU | Median physical input | Median peak memory | Median spilled | Đạt tiêu chí | Ghi chú |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- | --- |
| P01 | Full scan baseline | _____ | _____ | _____ | _____ | _____ | ☐ Có ☐ Không ☐ Chưa đặt | _____ |
| P02 | Partition pruning một tháng | _____ | _____ | _____ | _____ | _____ | ☐ Có ☐ Không ☐ Chưa đặt | _____ |
| P03 | Selective filter/column pruning | _____ | _____ | _____ | _____ | _____ | ☐ Có ☐ Không ☐ Chưa đặt | _____ |
| P04 | Aggregation cardinality cao | _____ | _____ | _____ | _____ | _____ | ☐ Có ☐ Không ☐ Chưa đặt | _____ |
| P05 | Join fact–dimension | _____ | _____ | _____ | _____ | _____ | ☐ Có ☐ Không ☐ Chưa đặt | _____ |
| P06 | Aggregate và Top-N | _____ | _____ | _____ | _____ | _____ | ☐ Có ☐ Không ☐ Chưa đặt | _____ |
| P07 | Window trên aggregate ngày | _____ | _____ | _____ | _____ | _____ | ☐ Có ☐ Không ☐ Chưa đặt | _____ |
| P08 | PostgreSQL filter/aggregation | _____ | _____ | _____ | _____ | _____ | ☐ Có ☐ Không ☐ Chưa đặt | _____ |
| P09 | PostgreSQL Mart–target join | _____ | _____ | _____ | _____ | _____ | ☐ Có ☐ Không ☐ Chưa đặt | _____ |
| P10 | Join xuyên catalog | _____ | _____ | _____ | _____ | _____ | ☐ Có ☐ Không ☐ Chưa đặt | _____ |
| P11-A | KPI tính từ Silver | _____ | _____ | _____ | _____ | _____ | ☐ Có ☐ Không ☐ Chưa đặt | _____ |
| P11-B | KPI đọc từ Mart | _____ | _____ | _____ | _____ | _____ | ☐ Có ☐ Không ☐ Chưa đặt | _____ |

## 7. Phân tích execution plan

| ID | Điểm cần kiểm tra | Kết quả quan sát | Đánh giá |
| --- | --- | --- | --- |
| P01 | Full scan; physical input; skew giữa task | _____ | ☐ Tốt ☐ Cần tối ưu |
| P02 | Constraint trên `pickup_date`; partition pruning | _____ | ☐ Có pruning ☐ Không rõ ☐ Không pruning |
| P03 | Chỉ đọc cột cần thiết; filter location/date | _____ | ☐ Có pruning ☐ Không rõ ☐ Không pruning |
| P04 | Partial/final aggregation; hash exchange; skew | _____ | ☐ Tốt ☐ Cần tối ưu |
| P05 | Join distribution; kích thước `dim_date`; exchange | _____ | ☐ Broadcast ☐ Partitioned ☐ Khác: _____ |
| P06 | Partial aggregation trước Top-N | _____ | ☐ Có ☐ Không |
| P07 | Sort/window input; memory; spill | _____ | ☐ Tốt ☐ Cần tối ưu |
| P08 | Filter/aggregation pushdown tới PostgreSQL | _____ | ☐ Toàn phần ☐ Một phần ☐ Không |
| P09 | Join/aggregation pushdown trong PostgreSQL catalog | _____ | ☐ Toàn phần ☐ Một phần ☐ Không |
| P10 | Scan mỗi connector; vị trí join; network exchange | _____ | ☐ Tốt ☐ Cần tối ưu |
| P11-A | Iceberg scan và partial aggregation | _____ | ☐ Tốt ☐ Cần tối ưu |
| P11-B | PostgreSQL scan/pushdown | _____ | ☐ Tốt ☐ Cần tối ưu |

### Operator hoặc stage tốn chi phí nhất

| ID | Fragment/stage/operator | CPU | Input | Output | Blocked | Nhận xét |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| _____ | _____ | _____ | _____ | _____ | _____ | _____ |
| _____ | _____ | _____ | _____ | _____ | _____ | _____ |
| _____ | _____ | _____ | _____ | _____ | _____ | _____ |

## 8. Các phép so sánh chính

### 8.1. Hiệu quả partition pruning: P01 so với P02

| Chỉ số | P01 | P02 | Chênh lệch/tỷ lệ |
| --- | ---: | ---: | ---: |
| Median execution | _____ | _____ | _____ |
| Median CPU | _____ | _____ | _____ |
| Median physical input | _____ | _____ | _____ |
| Median input rows | _____ | _____ | _____ |

Điền kết quả tính toán:

- Giảm physical input: `(P01 input - P02 input) / P01 input × 100` = _____%.
- Tăng tốc execution: `P01 execution / P02 execution` = _____×.
- Partition pruning đạt kỳ vọng: ☐ Có ☐ Không ☐ Chưa đủ dữ liệu.
- Nhận xét: _____

### 8.2. Column/selective pruning: P02 so với P03

| Chỉ số | P02 | P03 | Chênh lệch/tỷ lệ |
| --- | ---: | ---: | ---: |
| Median execution | _____ | _____ | _____ |
| Median CPU | _____ | _____ | _____ |
| Median physical input | _____ | _____ | _____ |
| Median input rows | _____ | _____ | _____ |

- Giảm physical input: _____%.
- Tăng tốc execution: _____×.
- Nhận xét: _____

### 8.3. Silver so với PostgreSQL Mart: P11-A và P11-B

| Chỉ số | P11-A Silver | P11-B Mart | Mart/Silver hoặc mức cải thiện |
| --- | ---: | ---: | ---: |
| Median execution | _____ | _____ | _____ |
| Median CPU | _____ | _____ | _____ |
| Median physical input | _____ | _____ | _____ |
| Median peak memory | _____ | _____ | _____ |
| Kết quả KPI khớp nhau | _____ | _____ | ☐ Có ☐ Không |

Điền kết quả tính toán:

- Speedup của Mart: `P11-A execution / P11-B execution` = _____×.
- Giảm physical input: `(P11-A input - P11-B input) / P11-A input × 100` = _____%.
- Giảm CPU: `(P11-A CPU - P11-B CPU) / P11-A CPU × 100` = _____%.
- Mart nhanh hơn Silver: ☐ Có ☐ Không.
- Kết luận về việc đặt Mart ở PostgreSQL: _____

### 8.4. Ảnh hưởng của cache

| ID | Cold execution | Median warm execution | Cải thiện warm so với cold |
| --- | ---: | ---: | ---: |
| P01 | _____ | _____ | _____% |
| P02 | _____ | _____ | _____% |
| P08 | _____ | _____ | _____% |
| P11-A | _____ | _____ | _____% |
| P11-B | _____ | _____ | _____% |

Công thức: `(cold - warm) / cold × 100`.

Nhận xét về ảnh hưởng cache: _____

## 9. P12 — Kiểm thử concurrency

Chạy cùng truy vấn P12 trong 1 session để lấy baseline, sau đó chạy đồng thời trong 3–5 session. Mọi session phải dùng cùng user, cùng session properties và cùng khoảng thời gian dữ liệu.

### 9.1. Điều kiện chạy

| Trường | Giá trị |
| --- | --- |
| User | _____ |
| Số session baseline | 1 |
| Số session concurrent | _____ |
| Cách đồng bộ thời điểm bắt đầu | _____ |
| Resource group | _____ |
| Workload khác | _____ |
| Thời điểm chạy | _____ |

### 9.2. Baseline một session

| Run | Query ID | Queued | Execution | CPU | Physical input | Peak memory | Spilled |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| R1 cold | _____ | _____ | _____ | _____ | _____ | _____ | _____ |
| R2 warm | _____ | _____ | _____ | _____ | _____ | _____ | _____ |
| R3 warm | _____ | _____ | _____ | _____ | _____ | _____ | _____ |
| Median warm | N/A | _____ | _____ | _____ | _____ | _____ | _____ |

### 9.3. Concurrent run

| Session | Query ID | Trạng thái | Queued | Execution | CPU | Blocked | Peak memory | Spilled |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| S1 | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ |
| S2 | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ |
| S3 | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ |
| S4 | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ |
| S5 | _____ | _____ | _____ | _____ | _____ | _____ | _____ | _____ |
| Median | N/A | _____ | _____ | _____ | _____ | _____ | _____ | _____ |
| P95 hoặc max | N/A | _____ | _____ | _____ | _____ | _____ | _____ | _____ |

### 9.4. Đánh giá concurrency

- Hệ số chậm hơn: `median concurrent execution / median baseline execution` = _____×.
- Mức tăng queued time: _____%/_____×.
- Có query lỗi: ☐ Không ☐ Có, số lượng: _____.
- Có spill: ☐ Không ☐ Có, lớn nhất: _____.
- Có dấu hiệu thiếu memory: ☐ Không ☐ Có: _____.
- Có dấu hiệu bão hòa CPU: ☐ Không ☐ Có: _____.
- Có dấu hiệu nghẽn I/O/network: ☐ Không ☐ Có: _____.
- Mức concurrency chấp nhận được: _____ session.
- Nhận xét: _____

## 10. Tiêu chí chấp nhận

Điền ngưỡng trước khi kết luận để tránh chọn ngưỡng theo kết quả đã đo.

| Tiêu chí | Ngưỡng | Kết quả đo | Đạt |
| --- | ---: | ---: | --- |
| P02 giảm physical input so với P01 | ≥ _____% | _____% | ☐ Có ☐ Không |
| P02 execution time | ≤ _____ | _____ | ☐ Có ☐ Không |
| P04 không spill | `0 B`/≤ _____ | _____ | ☐ Có ☐ Không |
| P05 input skew | ≤ _____% | _____% | ☐ Có ☐ Không |
| P07 peak memory | ≤ _____ | _____ | ☐ Có ☐ Không |
| P08 có pushdown | _____ | _____ | ☐ Có ☐ Không |
| P09 có pushdown | _____ | _____ | ☐ Có ☐ Không |
| P10 execution time | ≤ _____ | _____ | ☐ Có ☐ Không |
| P11-B nhanh hơn P11-A | ≥ _____× | _____× | ☐ Có ☐ Không |
| P12 degradation tại _____ session | ≤ _____× | _____× | ☐ Có ☐ Không |
| Tỷ lệ query thành công | ≥ _____% | _____% | ☐ Có ☐ Không |

## 11. Vấn đề và đề xuất

| Mức độ | ID liên quan | Hiện tượng | Bằng chứng | Nguyên nhân giả định | Hành động đề xuất | Người phụ trách |
| --- | --- | --- | --- | --- | --- | --- |
| _____ | _____ | _____ | _____ | _____ | _____ | _____ |
| _____ | _____ | _____ | _____ | _____ | _____ | _____ |
| _____ | _____ | _____ | _____ | _____ | _____ | _____ |

## 12. Kết luận

| Nội dung | Kết luận |
| --- | --- |
| Iceberg full scan | _____ |
| Partition/column pruning | _____ |
| Aggregation và Top-N | _____ |
| Join fact–dimension | _____ |
| Window function | _____ |
| PostgreSQL pushdown | _____ |
| Join xuyên catalog | _____ |
| Silver so với Mart | _____ |
| Khả năng chịu concurrency | _____ |
| Nút thắt chính | _____ |
| Khuyến nghị ưu tiên | _____ |
| Quyết định cuối | ☐ Đạt ☐ Không đạt ☐ Cần benchmark lại |

## 13. Checklist hoàn tất

- [ ] P00 đã được ghi trước khi chạy benchmark.
- [ ] Môi trường và snapshot dữ liệu không đổi giữa các run.
- [ ] Mỗi P01–P11 có một cold run và ít nhất hai warm run hợp lệ.
- [ ] Không dùng run lỗi để tính median.
- [ ] P01 và P02 được so sánh để xác nhận partition pruning.
- [ ] P08 và P09 đã kiểm tra pushdown trong plan, không chỉ so sánh thời gian.
- [ ] P10 đã ghi input riêng của Iceberg và PostgreSQL.
- [ ] P11-A và P11-B trả kết quả KPI tương đương.
- [ ] P12 dùng cùng truy vấn và cấu hình cho baseline lẫn concurrent run.
- [ ] Mọi đơn vị thời gian và dung lượng được ghi nhất quán.
- [ ] Query ID hoặc execution plan được lưu để truy vết.
- [ ] Tiêu chí chấp nhận được điền trước khi kết luận.

## References

- [Trino: EXPLAIN ANALYZE](https://trino.io/docs/current/sql/explain-analyze.html)
- [Trino: SHOW STATS](https://trino.io/docs/current/sql/show-stats.html)
