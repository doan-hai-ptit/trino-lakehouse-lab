# Azure Storage cho Trino

> Tóm tắt theo [Azure Storage file system support — Trino current](https://trino.io/docs/current/object-storage/file-system-azure.html) (đối chiếu Trino 482 ngày 2026-07-14).

Trino có native implementation để truy cập Azure Data Lake Storage Gen2 (ADLS Gen2) từ catalog Delta Lake, Hive, Hudi hoặc Iceberg. Storage account phải bật **hierarchical namespace**; Azure Blob Storage không có hierarchical namespace không đáp ứng yêu cầu của implementation này.

## 1. Yêu cầu và cách bật Azure Storage

Coordinator và mọi worker phải truy cập được Azure endpoint và có identity được cấp quyền Azure RBAC phù hợp. Metadata catalog của connector được cấu hình riêng với Azure storage.

Thêm các property sau vào catalog properties file đang dùng, chẳng hạn `etc/catalog/iceberg.properties`, khi dùng default authentication hoặc user-assigned managed identity.

```properties
fs.azure.enabled=true
azure.auth-type=DEFAULT
```

`fs.azure.enabled` mặc định `false` và phải là `true` trước khi các property `azure.*` có hiệu lực. Không dùng `fs.hadoop.enabled` hoặc `hive.azure.*` cho Azure object storage; legacy implementation đã bị gỡ bỏ.

## 2. Property chung và tuning

| Property name | Mặc định | Ý nghĩa |
| --- | --- | --- |
| `fs.azure.enabled` | `false` | Bật native Azure Storage implementation. |
| `azure.auth-type` | `DEFAULT` | Chọn `DEFAULT`, `ACCESS_KEY` hoặc `OAUTH`. |
| `azure.endpoint` | `core.windows.net` | Hostname suffix Azure endpoint. Dùng suffix cloud tương ứng cho US Government, Germany hoặc China cloud. |
| `azure.read-block-size` | `4MB` | Kích thước block đọc. |
| `azure.write-block-size` | `4MB` | Kích thước block ghi. |
| `azure.max-write-concurrency` | `8` | Số thao tác ghi đồng thời tối đa. |
| `azure.max-single-upload-size` | `4MB` | Kích thước upload đơn tối đa. |
| `azure.max-http-requests` | 2 × số CPU mỗi node | Số HTTP request Azure đồng thời mỗi node; giảm khi gặp rate limit. |
| `azure.connection-pool-max-idle-time` | `5m` | Thời gian connection idle trước khi pool đóng. |
| `azure.http-request-timeout` | `10m` | Timeout HTTP, gồm thời gian Azure SDK retry. |
| `azure.application-id` | `Trino` | Giá trị thêm vào header `User-Agent`. |
| `azure.multipart-write-enabled` | `false` | Bật multipart write cho file lớn. |

Không tăng concurrency/block size chỉ để xử lý lỗi. Trước tiên kiểm tra Azure throttling, băng thông, file size, số worker và permission; sau đó thay đổi từng property và đo workload đại diện.

## 3. Chọn một cơ chế authentication

`azure.auth-type` quyết định authentication. `DEFAULT`, `ACCESS_KEY` và `OAUTH` là lựa chọn thay thế nhau; không trộn property secret từ phương án này vào phương án khác.

### 3.1 DEFAULT và user-assigned managed identity

`DEFAULT` nạp credential từ environment nếu có hoặc dùng user-assigned managed identity. Khi chọn user-assigned identity, thêm property phù hợp vào catalog properties file đang dùng; chỉ được đặt **một** trong hai property identity sau.

```properties
azure.user-assigned-managed-identity.client-id=<client-id>
```

Hoặc thêm property sau vào cùng catalog properties file để định danh identity bằng resource ID.

```properties
azure.user-assigned-managed-identity.resource-id=<resource-id>
```

Đừng đặt cả `client-id` lẫn `resource-id`. Managed identity thường là lựa chọn nên ưu tiên vì không phải lưu long-lived secret trong catalog.

### 3.2 Access key

Với access key, đặt `azure.auth-type=ACCESS_KEY` và cung cấp `azure.access-key` từ secret management an toàn. `azure.access-key` là decrypted access key của storage account; không đưa nó vào file tracked hoặc Markdown chia sẻ công khai. Access key cấp quyền rộng ở mức account nên cần xoay vòng và hạn chế tối đa.

### 3.3 OAuth 2.0 service principal

Với service principal, đặt `azure.auth-type=OAUTH`. Các property cần có là:

| Property name | Ý nghĩa |
| --- | --- |
| `azure.oauth.tenant-id` | Tenant ID Azure dùng để xác thực. |
| `azure.oauth.endpoint` | URL endpoint OAuth 2.0. |
| `azure.oauth.client-id` | Client/application ID của service principal. |
| `azure.oauth.secret` | Client secret; phải quản lý ngoài Git. |

OAuth service principal phù hợp khi một catalog cần truy cập nhiều storage account. Cấp Azure RBAC role theo từng storage account/container, ví dụ quyền Blob Data phù hợp, thay vì cấp rộng theo subscription.

## 4. Authorization, vận hành và migration

Azure RBAC/storage ACL quyết định Trino identity có thể đọc/ghi object nào; system access control của Trino quyết định user Trino nào có thể dùng catalog/table. Cấu hình cả hai, áp dụng least privilege và kiểm thử bằng user/role thực tế.

Khi di trú từ legacy Azure support: bật `fs.azure.enabled=true`, bỏ `fs.hadoop.enabled` nếu chỉ dùng cho Azure, chọn `azure.auth-type`, rồi đổi `hive.azure.abfs-access-key` thành `azure.access-key`; đổi nhóm `hive.azure.abfs.oauth.*` sang `azure.oauth.*`. Các property legacy `hive.azure.abfs-storage-account`, `hive.azure.wasb-access-key` và `hive.azure.wasb-storage-account` phải bị loại bỏ.

Sau khi deploy catalog, thử đọc bảng hiện có, rồi trong location thử nghiệm tạo/ghi/xóa bảng để xác minh quyền đọc, ghi, rename/delete metadata và retry behavior.

- [ ] Storage account là ADLS Gen2 và đã bật hierarchical namespace.
- [ ] `fs.azure.enabled=true` nằm trong đúng catalog, không bật backend khác trong catalog đó.
- [ ] Mọi worker có network access và cùng cơ chế identity/credential cần thiết.
- [ ] Chọn đúng một auth type; không đặt đồng thời client ID và resource ID cho managed identity.
- [ ] Access key/OAuth secret không nằm trong Git hoặc log.
- [ ] Azure RBAC/ACL và policy Trino đều cấp least privilege.
- [ ] Đã kiểm thử read/write và xử lý rate limit/timeout trong môi trường thử nghiệm.

## References

- [Trino — Azure Storage file system support](https://trino.io/docs/current/object-storage/file-system-azure.html)
- [Trino — Object storage](https://trino.io/docs/current/object-storage.html)
- [Trino — Azure migration](https://trino.io/docs/current/object-storage/file-system-azure.html#migration-from-legacy-azure-storage-file-system)
