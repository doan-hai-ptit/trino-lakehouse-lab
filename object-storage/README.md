# Object storage cho Trino

> Tóm tắt theo [Object storage — Trino current](https://trino.io/docs/current/object-storage.html) (đối chiếu Trino 482 ngày 2026-07-14).

Object storage là lớp lưu các object/tệp của data lake hoặc lakehouse. Các connector Delta Lake, Hive, Hudi và Iceberg dùng Trino để truy cập trực tiếp data files và metadata files trên storage; metadata catalog của connector (như HMS, Glue, REST catalog) vẫn là một thành phần riêng.

## 1. Phạm vi và nguyên tắc cấu hình

Trino có native file-system implementation cho Azure Storage, Google Cloud Storage (GCS) và S3. Native implementation được dùng trong catalog của Delta Lake, Hive, Hudi hoặc Iceberg và phải được bật riêng trong **catalog properties file**.

Mỗi catalog chỉ dùng **một** file-system support. Vì vậy phải chọn một trong ba property sau cho catalog đó, không bật đồng thời chúng:

| Storage | Property bật native support | Mặc định |
| --- | --- | --- |
| Azure Storage | `fs.azure.enabled` | `false` |
| Google Cloud Storage | `fs.gcs.enabled` | `false` |
| S3 hoặc S3-compatible | `fs.s3.enabled` | `false` |

Ví dụ, thêm property sau vào catalog properties file đang dùng, chẳng hạn `etc/catalog/iceberg.properties`, khi catalog đó truy cập S3.

```properties
fs.s3.enabled=true
```

Không dùng `fs.hadoop.enabled` hoặc các property cũ `hive.s3.*`, `hive.gcs.*`, `hive.azure.*` cho object storage. Legacy object-storage support đã bị gỡ bỏ; `fs.hadoop.enabled` chỉ dành cho HDFS.

## 2. Các lớp quyền cần đồng thời đúng

Một truy vấn chỉ thành công khi tất cả các lớp sau cho phép:

1. Trino authentication và access control cho user/query.
2. Quyền metadata catalog của connector, nếu connector dùng metadata catalog.
3. Credential và IAM/RBAC policy của object storage cho Trino/node/user đang chạy query.
4. Network, DNS, TLS và endpoint giữa coordinator/worker với storage.

Quyền storage không thay thế policy Trino và ngược lại. Dùng least privilege, không lưu access key/secret/OAuth secret/JSON service-account key trong Git.

## 3. Chọn tài liệu theo backend

- [S3 và S3-compatible](S3.md): AWS S3, MinIO và endpoint tương thích S3; gồm IAM role, SSE và security mapping.
- [Azure Storage](AZURE_STORAGE.md): Azure Data Lake Storage Gen2, managed identity, access key và OAuth 2.0.
- [Google Cloud Storage](GCS.md): service account, Application Default Credentials và retry tuning.

## 4. Kiểm thử chung

Sau khi deploy hoặc reload catalog theo quy trình vận hành của bạn, chạy `SHOW SCHEMAS`, `SHOW TABLES` và `SELECT` trên một bảng đại diện. Với catalog có quyền ghi, tạo/ghi/xóa một bảng thử nghiệm để kiểm tra cả metadata catalog lẫn storage permissions.

- [ ] Mỗi catalog chỉ bật đúng một native file-system support.
- [ ] Mọi worker, không chỉ coordinator, có network access và credential cần thiết.
- [ ] Storage URI, metadata catalog và connector dùng cùng convention/region/endpoint phù hợp.
- [ ] Credential/role có least privilege và không tồn tại trong file tracked.
- [ ] Đã kiểm thử read, write, retry/error handling và access denied với identity thực tế.

## References

- [Trino — Object storage](https://trino.io/docs/current/object-storage.html)
- [Trino — Metastores](https://trino.io/docs/current/object-storage/metastores.html)
- [Trino — File system cache](https://trino.io/docs/current/object-storage/file-system-cache.html)
