# DisplayDisconnect

Menu bar app: ngắt / kết nối lại màn hình (giống "Connect this display" của BetterDisplay).

## Build & chạy
    xcode-select --install     # nếu chưa có
    ./build.sh
    open DisplayDisconnect.app

Biểu tượng màn hình xuất hiện trên menu bar. Mỗi màn hình có dấu tick = đang kết nối; bấm để ngắt/nối lại.

## CLI
    DisplayDisconnect.app/Contents/MacOS/DisplayDisconnect list
    DisplayDisconnect.app/Contents/MacOS/DisplayDisconnect disconnect <id>
    DisplayDisconnect.app/Contents/MacOS/DisplayDisconnect connect <id>

## An toàn
- Không cho ngắt màn hình cuối cùng còn hoạt động.
- Thay đổi chỉ áp dụng cho phiên đăng nhập (reboot/đăng xuất sẽ khôi phục).
- Thoát app sẽ tự nối lại các màn hình do app đã ngắt; "Reconnect All" nối lại tất cả.
- Rút màn hình ngoài khi màn built-in đang bị ngắt: app tự bật lại màn built-in sau ~1 giây (thử lại tối đa 5 lần).
- Máy thức dậy sau sleep/hibernate (vd. hết pin) mà không còn màn hình nào hoạt động: app cũng tự bật lại.
- Hết pin / mất điện làm máy tắt hẳn: khởi động lại sẽ khôi phục mọi màn hình (thay đổi chỉ theo phiên).
- Phím tắt toàn cục **⌃⌥⌘K** (Control + Option + Command + K) = "Reconnect All", dùng được cả khi màn hình đen,
  ví dụ màn hình ngoài mất nguồn nhưng macOS vẫn coi là đang cắm nên app không tự phát hiện được.
- Nếu vẫn tối: chạy `... connect <id>` qua SSH, hoặc khởi động lại.
- Các cơ chế tự khôi phục chỉ hoạt động khi app đang chạy trên menu bar (nên bật "Launch at Login").

## Lưu ý
Dùng hàm riêng (private) `CGSConfigureDisplayEnabled` của CoreGraphics — cùng kỹ thuật các công cụ tương tự dùng — nên Apple có thể thay đổi ở bản macOS sau. Đã chạy thử trên macOS 26 (Darwin 25).
