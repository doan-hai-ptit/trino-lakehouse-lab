# Ma trận phân quyền NYC Taxi Lakehouse

Tài liệu này mô tả chính sách quyền mong muốn cho lakehouse NYC Taxi. Đây là đặc tả nghiệp vụ để dùng khi thiết kế ACL; tài liệu không thay đổi `rules.json`, `group.txt`, mật khẩu, catalog hoặc dữ liệu đang chạy.

Hai catalog có mục đích khác nhau:

| Catalog | Nội dung | Ai nên dùng |
| --- | --- | --- |
| `iceberg` | Dữ liệu chuyến đi dung lượng lớn: nguồn, Bronze, Silver, Quality, Mart và Semantic. | DE, DS, DA, admin theo từng schema. |
| `postgresql` | Dữ liệu vận hành nhỏ: target, rule chất lượng, audit pipeline và refresh dashboard. Không đặt `fact_trip` tại đây. | DE, DA, admin theo từng bảng. |

## Vai trò và nguyên tắc

| Vai trò | Tài khoản ví dụ | Mục đích | Mức quyền |
| --- | --- | --- | --- |
| `admin` | `admin` | Quản trị nền tảng, xử lý sự cố và cấp quyền. | Toàn quyền. |
| DE | `de1`, `de2` | Xây dựng và vận hành pipeline dữ liệu. | Đọc nguồn, ghi/đổi dữ liệu đích và audit pipeline. |
| DS | `ds1`, `ds2` | Khai phá và huấn luyện mô hình. | Chỉ đọc dữ liệu đã chuẩn hoá; bị áp dụng row filter và column mask. |
| DA | `da1`, `da2` | Dashboard, báo cáo và phân tích KPI. | Chỉ đọc Mart/Semantic/Quality và target nghiệp vụ. |

Nguyên tắc là DS và DA không truy cập trực tiếp dữ liệu raw/Bronze, và DA không truy cập fact-level Silver. DE không thay đổi target KPI do business quản lý; họ chỉ ghi audit vận hành.

## Quyền của admin

| Phạm vi | Được phép |
| --- | --- |
| Mọi catalog, schema, table, view | `SELECT`, `INSERT`, `UPDATE`, `DELETE`, tạo/sửa/xoá schema, table, view và quản lý ownership. |
| `iceberg.nyc_taxi.fhvhv_trips` | Đọc, kiểm tra dữ liệu nguồn và xử lý sự cố. |
| `postgresql.ops.*` | Quản trị target, rule chất lượng, audit pipeline và dashboard refresh. |
| Query/system information | Xem, huỷ query của người khác và xem thông tin vận hành. |

Admin là tài khoản break-glass, không nên dùng để chạy dashboard hay pipeline thường ngày.

## Quyền của Data Engineer

| Đối tượng | Đọc | Ghi/thay đổi | Không được làm |
| --- | --- | --- | --- |
| `iceberg.nyc_taxi.fhvhv_trips` | Có, là nguồn 2024–2025. | Không. | Không sửa hoặc xoá dữ liệu nguồn. |
| `iceberg.bronze.*` | Có. | Có: tạo bảng, CTAS/INSERT, UPDATE/DELETE khi cần reprocess. | Không cấp quyền hoặc thay ownership sang user khác nếu chưa có quy trình. |
| `iceberg.silver.*` | Có. | Có: xây `fact_trip`, dimension và sửa dữ liệu chuẩn hoá. | Không dùng schema này làm lớp dashboard cuối cùng. |
| `iceberg.quality.*` | Có. | Có: ghi kết quả kiểm tra chất lượng. | Không thay ngưỡng business trong PostgreSQL. |
| `iceberg.mart.*`, `iceberg.semantic.*` | Có. | Có: tạo bảng tổng hợp, view semantic và refresh chúng. | Không sửa trực tiếp kết quả do DA xuất ra ngoài hệ thống. |
| `postgresql.ops.pipeline_run`, `postgresql.ops.dashboard_refresh_run` | Có. | Có: ghi trạng thái chạy, thời gian, lỗi và số record. | Không dùng hai bảng này để chứa trip-level data. |
| `postgresql.ops.data_quality_rule` | Có. | Không. | Không tự đổi rule/threshold do business phê duyệt. |
| `postgresql.ops.monthly_kpi_target`, `postgresql.ops.zone_demand_target` | Không cần cho pipeline mặc định. | Không. | Không đổi target KPI. |

Nếu DE thử `INSERT`, `UPDATE`, `DELETE`, `DROP` lên bảng nguồn hoặc bảng target, query phải nhận `Access Denied`. Khi chạy `SHOW TABLES`, DE chỉ nên thấy các schema/bảng có ít nhất một quyền ở trên.

## Quyền của Data Scientist

DS chỉ dùng dữ liệu sạch. Họ không được xem raw/Bronze để tránh mô hình phụ thuộc vào dữ liệu chưa kiểm tra và giảm rủi ro lộ dữ liệu chi tiết không cần thiết.

| Đối tượng | Quyền | Lọc hàng/cột |
| --- | --- | --- |
| `iceberg.silver.fact_trip` | Chỉ `SELECT`. | Chỉ hàng có `source_year = 2025`; `driver_pay` được mask thành `NULL` (vẫn giữ kiểu `DECIMAL(12, 2)`). |
| `iceberg.silver.dim_date`, `dim_location`, `dim_base` | Chỉ `SELECT`. | Không lọc. |
| `iceberg.quality.*` | Chỉ `SELECT`. | Dùng để đánh giá tính tin cậy của feature/model. |
| `iceberg.mart.*`, `iceberg.semantic.*` | Chỉ `SELECT`. | Dùng để so sánh model với KPI và chia sẻ kết quả. |
| `iceberg.nyc_taxi.*`, `iceberg.bronze.*` | Không có quyền. | Không thấy bảng khả dụng; truy vấn trực tiếp phải bị từ chối. |
| `postgresql.*` | Không có quyền. | Không thấy target/audit vận hành. |

Ví dụ sau là kết quả mong muốn khi DS đọc fact: `MIN(source_year)` và `MAX(source_year)` đều bằng `2025`; `COUNT(driver_pay)` bằng `0` vì tất cả giá trị đã bị mask. DS vẫn có thể dùng các cột như thời điểm, quãng đường, zone, loại chuyến đi và giá vé để xây feature.

DS không có quyền `INSERT`, `UPDATE`, `DELETE`, `CREATE`, `DROP` trên bất kỳ schema Iceberg nào. Nếu cố ghi vào Silver hoặc tạo bảng training trong `iceberg.silver`, query phải bị từ chối. Nếu cần workspace để lưu feature/model output, nên cấp riêng một schema như `iceberg.ds_sandbox` có quota và thời hạn dọn dẹp, thay vì mở quyền ghi Silver.

## Quyền của Data Analyst

| Đối tượng | Quyền | Mục đích |
| --- | --- | --- |
| `iceberg.mart.*` | Chỉ `SELECT`. | Bảng KPI theo ngày, zone, base và luồng di chuyển. |
| `iceberg.semantic.*` | Chỉ `SELECT`. | Nguồn ưu tiên cho BI/dashboard vì tên cột và logic đã được chuẩn hoá. |
| `iceberg.quality.*` | Chỉ `SELECT`. | Hiển thị cảnh báo độ trễ, thiếu dữ liệu và chất lượng báo cáo. |
| `postgresql.ops.monthly_kpi_target` | Chỉ `SELECT`. | So sánh KPI thực tế với target theo tháng. |
| `postgresql.ops.zone_demand_target` | Chỉ `SELECT`. | So sánh nhu cầu zone thực tế với target. |
| `postgresql.ops.data_quality_rule` | Chỉ `SELECT`. | Giải thích ngưỡng/cờ chất lượng trên dashboard. |
| `iceberg.nyc_taxi.*`, `iceberg.bronze.*`, `iceberg.silver.*` | Không có quyền. | DA không truy cập dữ liệu ở mức chuyến đi. |
| `postgresql.ops.pipeline_run`, `dashboard_refresh_run` | Không có quyền mặc định. | Chỉ cấp đọc thêm cho vai trò vận hành dashboard nếu thực sự cần. |

DA không có quyền ghi. Khi DA chạy `SHOW TABLES FROM iceberg.silver`, không nên thấy `fact_trip`; truy vấn trực tiếp vào bảng đó phải trả `Access Denied`. DA vẫn có thể join `iceberg.mart.*` với các target được phép trong `postgresql.ops` để xây báo cáo chéo catalog.

## Hành vi khi không có quyền

| Thao tác | Hành vi mong muốn |
| --- | --- |
| `SHOW CATALOGS` | Không dùng lệnh này như một ranh giới bảo mật; Trino cho phép chạy lệnh, trong khi quyền thực sự được kiểm tra khi truy cập catalog/schema/table. |
| `SHOW SCHEMAS FROM <catalog>` | Chỉ schema mà user có ownership hoặc có quyền trên object bên trong mới nên hiển thị. |
| `SHOW TABLES FROM <catalog>.<schema>` | Chỉ table/view mà user có ít nhất một quyền mới nên hiển thị. |
| `SELECT` bảng không được cấp | `Access Denied`. |
| `INSERT`, `UPDATE`, `DELETE`, `CREATE`, `DROP` không được cấp | `Access Denied`. |
| Đọc cột đã mask | Query thành công nhưng nhận giá trị đã che, ví dụ `driver_pay = NULL` cho DS. |
| Đọc bảng có row filter | Query thành công nhưng Trino tự thêm điều kiện lọc; DS không thể lấy bản ghi năm 2024 bằng cách bỏ `WHERE`. |

`information_schema` có những ngoại lệ riêng trong file-based access control, vì vậy không nên coi metadata hiển thị là cơ chế che giấu tuyệt đối. Bảo vệ chính phải là quyền thực thi trên table/view và thử nghiệm bằng từng user.

## Checklist trước khi triển khai ACL

- Xác nhận tên user trong password authenticator trùng với user được gán group.
- Dùng rule cụ thể cho `silver.fact_trip` của DS trước rule Silver tổng quát, nếu không row filter và mask sẽ bị bỏ qua do Trino dùng rule đầu tiên khớp.
- Cấp quyền theo tên bảng cho `postgresql.ops`, không dùng wildcard ghi cho toàn bộ schema.
- Kiểm thử dương tính và âm tính bằng mỗi user sau mỗi thay đổi quyền.
- Rà soát lại policy khi thêm schema/bảng mới; mặc định từ chối quyền mới là an toàn hơn cấp wildcard.

## References

- [Trino: File-based access control](https://trino.io/docs/current/security/file-system-access-control.html)
- [Trino: Group mapping](https://trino.io/docs/current/security/group-provider.html)
