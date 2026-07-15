# Google Cloud Storage cho Trino

> Tóm tắt theo [Google Cloud Storage file system support — Trino current](https://trino.io/docs/current/object-storage/file-system-gcs.html) (đối chiếu Trino 482 ngày 2026-07-14).

Trino có native implementation để truy cập Google Cloud Storage (GCS) từ catalog Delta Lake, Hive, Hudi hoặc Iceberg. GCS authentication, retry và endpoint được cấu hình trong catalog properties file của connector đang dùng; metadata catalog của connector vẫn là cấu hình riêng.

## 1. Cách bật native GCS

Coordinator và toàn bộ worker cần truy cập được GCS endpoint và có Google Cloud credential/permission phù hợp. Thêm property sau vào catalog properties file đang dùng, chẳng hạn `etc/catalog/iceberg.properties`, để bật native GCS support.

```properties
fs.gcs.enabled=true
```

`fs.gcs.enabled` mặc định `false`. Không dùng `fs.hadoop.enabled` hoặc `hive.gcs.*` để truy cập GCS vì legacy implementation đã bị gỡ bỏ.

## 2. Property chung và retry

| Property name | Mặc định | Ý nghĩa |
| --- | --- | --- |
| `fs.gcs.enabled` | `false` | Bật native GCS implementation. |
| `gcs.project-id` | Không đặt | Identifier của Google Cloud project. |
| `gcs.endpoint` | GCS endpoint mặc định | URL endpoint tùy chọn, ví dụ custom GCS-compatible endpoint. |
| `gcs.client.max-retries` | `20` | Số lần thử RPC tối đa. |
| `gcs.client.backoff-scale-factor` | `3` | Hệ số scale cho retry delay. |
| `gcs.client.max-retry-time` | `25s` | Tổng thời gian tối đa cho RPC retry. |
| `gcs.client.min-backoff-delay` | `10ms` | Backoff nhỏ nhất giữa các retry. |
| `gcs.client.max-backoff-delay` | `2s` | Backoff lớn nhất giữa các retry. |
| `gcs.read-block-size` | `2MiB` | Kích thước block tối thiểu đọc mỗi RPC. |
| `gcs.write-block-size` | `16MiB` | Kích thước block tối thiểu ghi mỗi RPC. |
| `gcs.page-size` | `100` | Số blob tối đa mỗi page. |
| `gcs.batch-size` | `100` | Số blob xóa mỗi batch; phù hợp với khuyến nghị GCS. |
| `gcs.application-id` | `Trino` | Giá trị thêm vào header `User-Agent`. |

Tuning retry/backoff chỉ sau khi xác minh IAM, endpoint, quota, network và đặc tính workload. Retry lớn có thể làm query chờ lâu hơn khi permission hoặc cấu hình endpoint vốn sai.

## 3. Authentication

`gcs.auth-type` mặc định là `SERVICE_ACCOUNT` và có ba lựa chọn:

| Giá trị | Hành vi |
| --- | --- |
| `SERVICE_ACCOUNT` | Nạp credential từ environment. Có thể ghi đè bằng `gcs.json-key` hoặc `gcs.json-key-file-path`. |
| `ACCESS_TOKEN` | Dùng OAuth 2.0 token do client cung cấp để truy cập GCS. |
| `APPLICATION_DEFAULT` | Tìm Application Default Credentials (ADC) trong environment; nếu không có ADC, filesystem dùng unauthenticated credential một cách tường minh. |

`gcs.json-key` chứa service-account key dưới dạng JSON; `gcs.json-key-file-path` là path đến JSON key file trên **mỗi node**. Hai property này loại trừ nhau. Ưu tiên workload identity/ADC khi hạ tầng hỗ trợ; nếu dùng key file, bảo vệ file ngoài Git, giới hạn quyền đọc và xoay vòng key.

Thêm property sau vào catalog properties file đang dùng chỉ khi cần định danh project rõ ràng.

```properties
gcs.project-id=<project-id>
```

Không đặt JSON service-account key trực tiếp vào catalog file tracked. Quyền IAM GCS của service account/workload identity phải tối thiểu theo bucket/prefix và thao tác read/write thực tế.

## 4. Migration, security và kiểm thử

Khi di trú từ legacy GCS support, bật `fs.gcs.enabled=true`, bỏ `fs.hadoop.enabled` nếu chỉ được dùng cho legacy GCS, đổi `hive.gcs.json-key-file-path` thành `gcs.json-key-file-path`. Với legacy `hive.gcs.use-access-token`, chọn giá trị `gcs.auth-type` phù hợp (thường là `ACCESS_TOKEN`).

GCS IAM quyết định identity storage có thể làm gì; system access control của Trino quyết định user Trino nào có thể truy cập catalog/table. Cấu hình cả hai lớp và kiểm thử access denied, không chỉ happy path.

Sau khi deploy catalog, đọc một bảng trong bucket thật và thực hiện create/write/drop trên location thử nghiệm. Xác minh credential được nhận trên toàn bộ worker, không chỉ coordinator.

- [ ] `fs.gcs.enabled=true` nằm trong đúng catalog và catalog không bật backend khác.
- [ ] Mọi worker có network access tới endpoint và Google credential có hiệu lực.
- [ ] Chọn đúng `gcs.auth-type`; không đặt cả `gcs.json-key` và `gcs.json-key-file-path`.
- [ ] Service-account key/token không nằm trong Git/log; ưu tiên ADC/workload identity khi có thể.
- [ ] GCS IAM và Trino access control đều least privilege.
- [ ] Đã kiểm thử read/write, retry/quota failure, endpoint tùy chỉnh (nếu dùng) và access denied.

## References

- [Trino — Google Cloud Storage file system support](https://trino.io/docs/current/object-storage/file-system-gcs.html)
- [Trino — Object storage](https://trino.io/docs/current/object-storage.html)
- [Trino — GCS migration](https://trino.io/docs/current/object-storage/file-system-gcs.html#migration-from-legacy-google-cloud-storage-file-system)
