# File-based access control cho Trino

> Tóm tắt theo [File-based access control — Trino 482](https://trino.io/docs/current/security/file-system-access-control.html). Cập nhật tham chiếu: 2026-07-11.

File-based access control (file ACL) là cơ chế **phân quyền** của Trino. Nó đọc các rule JSON do quản trị viên quản lý để quyết định user/role/group được dùng tài nguyên hay thao tác nào. Nó không thay thế cơ chế **xác thực** như password file, OAuth hoặc Kerberos: xác thực cho biết người dùng là ai, còn file ACL quyết định người đó được làm gì.

Các block cấu hình dưới đây giữ nguyên tên property, giá trị mẫu và cú pháp JSON của tài liệu Trino. Chỉ phần giải thích được viết lại bằng tiếng Việt.

## 1. Chọn phạm vi áp dụng

Trino có hai dạng file ACL:

| Dạng | Khi dùng | Phạm vi |
| --- | --- | --- |
| **System-level** | Cần một chính sách chung cho cả cluster. | Một file JSON điều khiển catalog, schema, table, function, procedure, query, impersonation, system information, v.v. |
| **Catalog-level** | Cần policy riêng cho một catalog/connector hỗ trợ `FILE` (ví dụ Iceberg). | Một file JSON cho từng catalog; hỗ trợ schema, table, cột, function và session property trong catalog đó. |

System-level thường là điểm bắt đầu phù hợp để chặn/mở quyền trên toàn cluster. Catalog-level là lớp phân quyền theo connector, không phải mọi connector đều hỗ trợ.

## 2. Mô hình đánh giá rule — phần quan trọng nhất

- Các rule trong mỗi danh sách được đọc **từ trên xuống dưới**; **rule đầu tiên khớp** được áp dụng. Đặt ngoại lệ/chặn cụ thể trước rule cho phép rộng hơn.
- Nếu một rule section đã có nhưng không có rule nào khớp, phần lớn thao tác bị từ chối. Không nên dựa vào các default ngầm; hãy thêm rule rõ ràng, gồm cả rule chặn cuối nếu chính sách cần deny-by-default.
- Các trường nhận diện như `user`, `role`, `group`, `catalog`, `schema`, `table`, `function`, `procedure` là **regular expression**; khi bỏ qua, mặc định thường là `.*`.
- Rule `role` khớp nếu có ít nhất một role đang bật khớp regex. Rule `group` khớp nếu user thuộc ít nhất một group khớp regex; vì vậy phải cấu hình [group provider](https://trino.io/docs/current/security/group-provider.html) nếu dùng `group`.
- `information_schema` là ngoại lệ: rule catalog/schema/table trong trang này không áp dụng cho các table do hệ thống định nghĩa trong schema đó.
- Với catalog/schema/table, tài liệu nêu rằng khi hoàn toàn không cung cấp rule thì quyền được cấp. Một section rỗng có thể được dùng để gỡ quyền cấp mặc định, ví dụ:

```json
{
  "schemas": []
}
```

- `SHOW` không đồng nghĩa với toàn quyền: catalog/schema/table chỉ hiện khi user có ít nhất một quyền trên chính đối tượng hoặc đối tượng lồng bên trong nó. Catalog `system` mặc định có thể truy cập; thêm catalog rule để ghi đè hành vi này.

## 3. Bật system-level file ACL

Tạo `etc/access-control.properties` trên coordinator. Hai property sau là bắt buộc; `access-control.name` phải là `file` và `security.config-file` trỏ đến JSON rule file.

```properties
access-control.name=file
security.config-file=etc/rules.json
```

Với Docker Compose của repository này, file cấu hình của coordinator được mount vào `/etc/trino`. Vì vậy có thể đặt file host tại `trino/etc/access-control.properties` và `trino/etc/rules.json`; nếu chọn đường dẫn tuyệt đối trong container, giá trị tương ứng là `/etc/trino/rules.json`.

### Đọc rule JSON từ HTTP (tùy chọn)

Nếu endpoint trả về JSON bọc rule trong key `data`, dùng JSON Pointer RFC 6901 để chọn object chứa rule:

```properties
access-control.name=file
security.config-file=http://trino-test/config
security.json-pointer=/data
```

Khi file/endpoint trả trực tiếp một JSON object chứa các rule, không cần `security.json-pointer`.

### Nạp lại rule

Mặc định, thay đổi rule cần restart Trino. Để Trino tự đọc lại file/endpoint theo chu kỳ, thêm:

```properties
security.refresh-period=1s
```

Chọn chu kỳ hợp lý cho vận hành; refresh không thay thế việc kiểm thử policy trước khi đưa vào môi trường dùng chung.

## 4. Catalog, schema và table rules

Ba section chính trong `rules.json` là `catalogs`, `schemas`, `tables`.

### 4.1 Catalog rules

Mỗi rule có các trường tùy chọn `user`, `role`, `group`, `catalog` và trường bắt buộc `allow`.

`allow` nhận `all`, `read-only`, hoặc `none` (mặc định là `none`). `all` chỉ nói catalog rule không hạn chế thêm; schema/table rule vẫn có thể chặn thao tác. `read-only` chặn ghi. Giá trị boolean cũ vẫn tương thích: `true` tương đương `all`, `false` tương đương `none`.

Mẫu sau cho phép role `admin` vào `mysql`/`system`, các group nhất định vào `postgres`, mọi user vào `hive`, và cho `alice` chỉ đọc `postgresql`. Rule cuối chặn `system` đối với các user không đã khớp rule `admin` ở trên:

```json
{
  "catalogs": [
    {
      "role": "admin",
      "catalog": "(mysql|system)",
      "allow": "all"
    },
    {
      "group": "finance|human_resources",
      "catalog": "postgres",
      "allow": true
    },
    {
      "catalog": "hive",
      "allow": "all"
    },
    {
      "user": "alice",
      "catalog": "postgresql",
      "allow": "read-only"
    },
    {
      "catalog": "system",
      "allow": "none"
    }
  ]
}
```

Thứ tự là một phần của policy: ví dụ nếu muốn chặn `alice` trước một rule cho phép tất cả user, rule của `alice` phải đứng trước rule rộng đó.

### 4.2 Schema rules

Schema rule gồm `user`, `role`, `group`, `catalog`, `schema` (đều tùy chọn) và `owner` (bắt buộc, boolean). `owner: true` cấp quyền sở hữu schema, cần cho nhiều thao tác DDL.

```json
{
  "schemas": [
    {
      "role": "admin",
      "schema": ".*",
      "owner": true
    },
    {
      "user": "guest",
      "owner": false
    },
    {
      "catalog": "default",
      "schema": "default",
      "owner": true
    }
  ]
}
```

### 4.3 Table rules, row filter và column mask

Table rule có `user`, `role`, `group`, `catalog`, `schema`, `table` (tùy chọn), cùng `privileges` (bắt buộc). Các giá trị `privileges` là:

`SELECT`, `INSERT`, `DELETE`, `UPDATE`, `OWNERSHIP`, `GRANT_SELECT`.

Rule còn có thể chứa:

- `columns`: danh sách ràng buộc cột. Mỗi item có `name`, và tùy chọn `allow: false`, `mask`, `mask_environment`.
- `filter`: biểu thức boolean lọc hàng (row-level filter).
- `filter_environment`: context dùng khi đánh giá filter.
- `mask_environment`: context dùng khi đánh giá subquery trong mask.

`mask` có thể dùng biểu thức điều kiện như `IF` hoặc `CASE`. Mẫu sau thể hiện role admin toàn quyền, user bị chặn, row filter theo `current_user`, chặn cột `address` và mask cột `SSN`:

```json
{
  "tables": [
    {
      "role": "admin",
      "privileges": ["SELECT", "INSERT", "DELETE", "UPDATE", "OWNERSHIP"]
    },
    {
      "user": "banned_user",
      "privileges": []
    },
    {
      "catalog": "default",
      "schema": "hr",
      "table": "employee",
      "privileges": ["SELECT"],
      "filter": "user = current_user",
      "filter_environment": {
        "user": "system_user"
      }
    },
    {
      "catalog": "default",
      "schema": "default",
      "table": ".*",
      "privileges": ["SELECT"],
      "columns" : [
         {
            "name": "address",
            "allow": false
         },
         {
            "name": "SSN",
            "mask": "'XXX-XX-' + substring(credit_card, -4)",
            "mask_environment": {
              "user": "system_user"
            }
         }
      ]
    }
  ]
}
```

### 4.4 Liên hệ giữa SQL và quyền

Đây là các quan hệ cần nhớ khi thiết kế policy system-level:

| Thao tác | Catalog rule | Quyền bổ sung |
| --- | --- | --- |
| `SHOW CATALOGS` | Luôn được phép | Visibility vẫn phụ thuộc quyền lồng bên trong. |
| `SHOW SCHEMAS`, `SHOW TABLES`, `SHOW COLUMNS` | `read-only` | Cần catalog/schema/table có thể nhìn thấy. |
| `SELECT` từ table | `read-only` | `SELECT` trên table. |
| `SELECT` từ view | `read-only` | `SELECT` và `GRANT_SELECT`. |
| `INSERT`, `DELETE`, `UPDATE` | `all` | Lần lượt `INSERT`, `DELETE`, `UPDATE`. |
| `CREATE TABLE`/`VIEW`, `DROP`, `ALTER`, `COMMENT` | `all` | Schema/table owner tùy lệnh; rename yêu cầu ownership trên cả đối tượng cũ và mới. |
| `CREATE SCHEMA`, `DROP SCHEMA`, `ALTER SCHEMA` | `read-only` hoặc `all` tùy lệnh | Ownership schema. |

Không phải connector nào cũng hỗ trợ mọi thao tác hoặc catalog user-defined function.

## 5. Các rule system-level khác

| Section | Mục đích và trường/quyền cần nhớ | Default đáng chú ý |
| --- | --- | --- |
| `functions` | `user`, `role`, `group`, `catalog`, `schema`, `function`; `privileges`: `EXECUTE`, `GRANT_EXECUTE`, `OWNERSHIP`. | Nếu section không có, chỉ function trong `system.builtin` chạy được. Function trong `system.builtin` luôn truy cập được và không thể bị rule ghi đè. Cẩn trọng khi cấp quyền schema `system` của catalog vì table function như `query` có thể truy cập/sửa dữ liệu bên dưới. |
| `procedures` | Cho `CALL`; dùng các trường tương tự function và `procedure`; quyền `EXECUTE`, `GRANT_EXECUTE`. | Nếu section không có, chỉ procedure trong `system.builtin` chạy được. Table procedure (`ALTER TABLE ... EXECUTE`) không có privilege file ACL riêng, nên thực tế đều được cho phép. |
| `system_session_properties` | `user`, `role`, `group`, `property`, `allow`. | Không có section: mọi user được đặt system session property. |
| `catalog_session_properties` | Như trên, thêm `catalog`. | Không khớp rule: từ chối đặt property. |
| `queries` | `user`, `role`, `group`, `queryOwner`, `allow`: `execute`, `view`, `kill`. | User luôn xem/kill query của chính họ. Rule có `queryOwner` không được chứa `execute`. |
| `impersonation` | `original_user`, `original_role`, `new_user` (bắt buộc), `allow`. `new_user` có thể dùng capture group từ `original_user`, ví dụ `$1`. | Không có impersonation/principal rule: impersonation không được phép. |
| `principals` | Mapping principal sang user. | **Deprecated**; dùng user mapping cộng impersonation rules thay thế. |
| `system_information` | Đọc REST endpoint nhạy cảm, system information function/System connector, hoặc graceful shutdown; `allow`: `read`, `write`. | Không có rule: từ chối toàn bộ system information. Các endpoint `GET /v1/info`, `/v1/info/state`, `/v1/status` luôn public. |
| `authorization` | Đổi owner qua `ALTER SCHEMA/TABLE/VIEW ... SET AUTHORIZATION`; `original_user/group/role`, `new_user` và/hoặc `new_role`, `allow`. | Cần có ít nhất `new_user` hoặc `new_role`, và người chạy lệnh vẫn cần `OWNERSHIP`. |

### Mẫu session property và query rule

```json
{
    "system_session_properties": [
        {
            "role": "admin",
            "allow": true
        },
        {
            "user": "banned_user",
            "allow": false
        },
        {
            "property": "resource_overcommit",
            "allow": true
        }
    ],
    "catalog_session_properties": [
        {
            "role": "admin",
            "allow": true
        },
        {
            "user": "banned_user",
            "allow": false
        },
        {
            "catalog": "hive",
            "property": "bucket_execution_enabled",
            "allow": true
        }
    ]
}
```

```json
{
  "queries": [
    {
      "role": "admin",
      "allow": ["execute", "kill", "view"]
    },
    {
      "user": "alice",
      "allow": ["execute", "kill"]
    },
    {
      "group": "contractors",
      "queryOwner": "alice|dave",
      "allow": ["view"]
    },
    {
      "allow": ["execute"]
    }
  ]
}
```

### Mẫu impersonation, system information và ownership authorization

```json
{
    "impersonation": [
        {
            "original_role": "admin",
            "new_user": "bob",
            "allow": false
        },
        {
            "original_role": "admin",
            "new_user": ".*"
        },
        {
            "original_user": ".*",
            "new_user": "test"
        },
        {
            "original_user": "team_(.*)",
            "new_user": "team_$1_sandbox",
            "allow": true
        }
    ]
}
```

```json
{
  "system_information": [
    {
      "role": "admin",
      "allow": ["read", "write"]
    },
    {
      "user": "alice",
      "allow": ["read"]
    }
  ]
}
```

```json
{
  "authorization": [
    {
      "original_role": "admin",
      "new_user": "bob",
      "allow": false
    },
    {
      "original_role": "admin",
      "new_user": ".*",
      "new_role": ".*"
    }
  ],
  "schemas": [
    {
      "role": "admin",
      "owner": true
    }
  ],
  "tables": [
    {
      "role": "admin",
      "privileges": ["OWNERSHIP"]
    }
  ]
}
```

Nếu đặt `management.user`, user cố định này vẫn phải được `system_information` rule cho phép. Khi management interface chạy qua HTTPS, bật thêm `management.user.https-enabled` nếu cần áp dụng fixed user ở HTTPS.

## 6. Catalog-level file ACL

Catalog-level ACL được cấu hình trong file properties của **chính catalog/connector**. Ví dụ Iceberg dùng file `rules.json` riêng:

```properties
iceberg.security=FILE
security.config-file=etc/catalog/rules.json
```

Xem tài liệu connector để xác nhận connector hỗ trợ `FILE`. Rule file catalog-level có các section, cũng được xử lý theo thứ tự từ trên xuống:

1. `schemas`
2. `tables`
3. `session_properties`
4. `functions`

Khác biệt chính so với system-level:

- `schemas`: `user`, `group`, `schema`, `owner`; không có `catalog`/`role` vì file đã gắn với một catalog.
- `tables`: `user`, `group`, `schema`, `table`, `privileges`, `columns`, `filter`, `filter_environment`; column/mask dùng cùng ý nghĩa như system-level.
- `session_properties`: `user`, `group`, `property`, `allow`.
- `functions`: `user`, `group`, `schema`, `function`, `privileges` (`EXECUTE`, `GRANT_EXECUTE`, `OWNERSHIP`). Không có function rule thì access không được phép.
- Các rule này cũng không áp dụng cho table hệ thống trong `information_schema`.

Mẫu đầy đủ sau cho một catalog cho thấy ownership schema, table privilege/row filter/column mask và session property:

```json
{
  "schemas": [
    {
      "user": "admin",
      "schema": ".*",
      "owner": true
    },
    {
      "group": "finance|human_resources",
      "schema": "employees",
      "owner": true
    },
    {
      "user": "guest",
      "owner": false
    },
    {
      "schema": "default",
      "owner": true
    }
  ],
  "tables": [
    {
      "user": "admin",
      "privileges": ["SELECT", "INSERT", "DELETE", "UPDATE", "OWNERSHIP"]
    },
    {
      "user": "banned_user",
      "privileges": []
    },
    {
      "schema": "hr",
      "table": "employee",
      "privileges": ["SELECT"],
      "filter": "user = current_user"
    },
    {
      "schema": "default",
      "table": ".*",
      "privileges": ["SELECT"],
      "columns" : [
         {
            "name": "address",
            "allow": false
         },
         {
            "name": "ssn",
            "mask": "'XXX-XX-' + substring(credit_card, -4)",
            "mask_environment": {
              "user": "admin"
            }
         }
      ]
    }
  ],
  "session_properties": [
    {
      "property": "force_local_scheduling",
      "allow": true
    },
    {
      "user": "admin",
      "property": "max_split_size",
      "allow": true
    }
  ]
}
```

## 7. Kiểm thử trước khi viết policy thật

Để xác nhận system-level file ACL đã được nạp, tài liệu Trino đề xuất tạm thời chặn catalog `system`:

```json
{
  "catalogs": [
    {
      "catalog": "system",
      "allow": "none"
    }
  ]
}
```

Sau khi restart (hoặc chờ refresh nếu đã cấu hình), chạy bằng Trino CLI:

```text
trino> SELECT * FROM system.runtime.nodes;
Query 20200824_183358_00000_c62aw failed: Access Denied: Cannot access catalog system
```

Sau khi xác minh, bỏ rule chặn thử nghiệm và thay bằng policy thực tế. Kiểm thử tối thiểu nên có user/role cho phép, user bị chặn, truy vấn `SHOW`, `SELECT`, thao tác ghi (nếu có), và một trường hợp row filter/column mask nếu policy dùng chúng.

## 8. Checklist vận hành an toàn

- Giữ `access-control.properties` và JSON rule dưới quyền kiểm soát thay đổi; JSON sai có thể làm coordinator không khởi động hoặc chặn user ngoài dự kiến.
- Luôn review thứ tự rule: deny/exceptions cụ thể đứng trước allow rộng.
- Không cấp `OWNERSHIP`, `GRANT_SELECT`, `GRANT_EXECUTE` hay quyền schema `system` một cách rộng rãi.
- Quyết định rõ cách xử lý `information_schema` và catalog `system`; đừng giả định chúng bị bảo vệ giống table thường.
- Nếu dùng group/role, xác minh mapping và role đang bật bằng đúng user thực tế.
- Dùng refresh period khi cần cập nhật nhanh, nhưng triển khai policy quan trọng theo quy trình test/rollback.

## Tham khảo

- [Trino — File-based access control](https://trino.io/docs/current/security/file-system-access-control.html)
- [Trino — System access control](https://trino.io/docs/current/security/system-access-control.html)
- [Trino — Group provider](https://trino.io/docs/current/security/group-provider.html)
