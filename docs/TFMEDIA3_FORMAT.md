# TFMEDIA3 裸卡格式

本文档以既有写卡工具和 `tf_media.img` 为兼容基线。所有多字节整数均为
little-endian，逻辑扇区大小固定为 512 字节。

## LBA 0：超级块

| 偏移 | 大小 | 字段 | 固定值/说明 |
|---:|---:|---|---|
| 0 | 8 | magic | ASCII `TFMEDIA3` |
| 8 | 2 | version | 3 |
| 10 | 2 | header_bytes | 512 |
| 12 | 2 | entry_size | 16 |
| 14 | 2 | entry_count | 0..20 |
| 16 | 4 | index_lba | 当前工具为 1 |
| 20 | 4 | index_sectors | 当前工具为 1 |
| 24 | 2 | width | 640 |
| 26 | 2 | height | 480 |
| 28 | 4 | fps_num | 25 |
| 32 | 4 | fps_den | 1 |
| 36 | 2 | audio_channels | 1 |
| 38 | 2 | audio_bits | 16 |
| 40 | 4 | audio_rate | 48000 |
| 44 | 4 | flags/reserved | 当前为 0 |
| 48 | 4 | total_sectors | 镜像总扇区数 |
| 52..507 | 456 | reserved | 0 |
| 508 | 4 | crc32 | 对字节 0..507 计算的标准 CRC32 |

## 媒体索引

从 `index_lba` 开始，每项 16 字节，结构为 `<BBHIII`：

| 偏移 | 大小 | 字段 |
|---:|---:|---|
| 0 | 1 | media_type：1=图片，2=视频 |
| 1 | 1 | flags |
| 2 | 2 | media_id |
| 4 | 4 | metadata_lba |
| 8 | 4 | data_lba |
| 12 | 4 | data_bytes |

索引顺序就是轮播顺序。工具分别限制最多 10 个视频、10 张图片，硬件总表容量为 20 项。

## TFMETA3 元数据扇区

每个媒体的 `metadata_lba` 指向一个 512 字节扇区：

| 偏移 | 大小 | 字段 |
|---:|---:|---|
| 0 | 8 | ASCII `TFMETA3\0` |
| 8 | 4 | frame_index_lba |
| 12 | 4 | frame_count |
| 16 | 4 | audio_lba；图片为 0 |
| 20 | 4 | audio_bytes；图片为 0 |
| 24 | 4 | duration_num |
| 28 | 4 | duration_den |
| 32 | 4 | fps_num |
| 36 | 4 | fps_den |
| 64 | 64 | UTF-8 名称，NUL 填充 |
| 508 | 4 | 对字节 0..507 计算的标准 CRC32 |

图片包含一个 JPEG 帧。为保持旧工具界面行为，FPGA 对图片固定停留 3 秒，
不依赖样例镜像中的 `duration_num/duration_den`。

## 帧索引和媒体数据

`frame_index_lba` 指向 `frame_count` 个 `<II` 记录：

- `offset`：相对于 `data_lba * 512` 的字节偏移；
- `size`：该帧 JPEG 字节数，必须不大于 65536。

JPEG 数据连续存放在 `data_lba` 开始的区域。视频音频是从 `audio_lba`
开始的连续 little-endian signed PCM16 流，不与 JPEG 帧交错。

每个 25 fps 视频帧对应 1920 个单声道采样，即 3840 字节 PCM。

## 黄金镜像

`use/写卡工具/tf_media.img` 是兼容性黄金向量，当前包含：

- 图片 0：JPEG 14357 字节；
- 视频 1：1393 帧，JPEG 合计 36349568 字节，PCM 5349120 字节；
- 图片 2：JPEG 36450 字节。

