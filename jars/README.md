# Thư viện cục bộ cho Hive Metastore

`docker-compose.yaml` mount ba dependency sau vào container Hive Metastore:

- `postgresql-42.7.7.jar`: PostgreSQL JDBC driver.
- `hadoop-aws-3.4.1.jar`: S3A file system cho Hadoop.
- `bundle-2.24.6.jar`: AWS SDK bundle được S3A sử dụng.

Các file JAR không được commit vào Git. Tải đúng tên và phiên bản bằng các lệnh trong README ở thư mục gốc, sau đó kiểm tra:

```powershell
Get-ChildItem jars -File
docker compose config --quiet
```

Khi nâng phiên bản dependency, phải cập nhật đồng thời tên file trong thư mục này và các volume mount tương ứng trong `docker-compose.yaml`.
