Mục Tiêu:
•	Mục tiêu chính tạo ra hệ thống để cung cấp cho cửa hàng muốn tiếp cận người dùng online và cũng là để người dùng mạng có trang mua hàng thuận tiện mà không cần đến tận nơi mua.

Đối tượng sử dụng và yêu cầu:

•	Đối tượng thứ 1: Chủ cửa hàng, có quyền quản lí, cập nhật hàng hóa, sửa đổi giá, số lượng, sản phẩm, thông tin nhưng không có quyền mua hàng.

•	Đối tượng thứ 2: Khách hàng, khi sử dụng hệ thống chỉ có quyền xem hàng, mua hàng, thanh toán và kiểm tra đơn hàng của bản thân.

Yêu cầu phi chức năng:

•	Khả năng quản lí tốt các loại hàng, tự động cập nhật hàng hiệu quả.
•	Độ tin cậy về dữ liệu cao
•	Cơ sở dữ liệu mang tính toàn vẹn
•	Khả năng phản hồi và xử lí đa người dùng hiệu quả

Thuộc tính của các sản phẩm: Tên gọi, Nguồn gốc xuất xứ, Thương hiệu, Chất liệu, Kích thước, Kiểu Dáng, Màu Sắc, Mô tả

Các chức năng chung của người bán hàng:

1.	Thêm danh mục, sản phẩm mới
•	Thêm danh mục, sản phẩm mới bằng cách nhập các thông tin, thuộc tính, số lượng và giá cả của sản phẩm vào 
•	Mỗi sản phẩm sau khi thêm vào sẽ có 1 ID riêng biệt.

3.	Quản lí danh mục, sản phẩm
•	Sửa đổi thông tin mô tả, số lượng và giá cả của sản phẩm, danh mục.
•	Xóa danh mục, sản phẩm.

5.	Quản lí mã giảm giá
•	Một bảng gồm các mã giảm, có thể thêm, sửa đổi hoặc xóa.
•	Hình thức giảm giá: cửa hàng sẽ giảm giá sản phẩm nếu tổng giá trị đơn hàng đạt giá trị nhất định.
•	Tổng giá trị đơn hàng và phần trăm giảm sẽ do người bán nhập vào.

6.	Quản lí đơn hàng
•	Kiểm tra các đơn hàng đang cần xử lý
•	Xác nhận đơn hàng “confirmed” để giao đến người mua hoặc hủy đơn hàng “cancel”

Các chức năng chung của người mua hàng:

1.	Thêm sản phẩm vào giỏ hàng

•	Mỗi khi người dùng thêm/bớt sản phẩm (trong giới hạn số lượng còn lại của kho), giỏ hàng sẽ cập nhật lại số lượng sản phẩm.

•	Kiểm tra xem khi mua với tổng giá trị đơn hàng nhất định thì có được giảm giá hay không. Mã giảm giá sẽ được tự áp dụng khi đạt đủ điều kiện.

•	Giá của đơn hàng (sau tự áp dụng giảm giá) sẽ được cập nhật sau khi hoàn thành thêm/bớt sản phẩm trong giỏ hàng.

2.	Xem sản phẩm trong cửa hàng và tình trạng đơn hàng

•	Hiển thị toàn bộ sản phẩm hoặc tìm kiếm theo từng danh mục.

•	Kiểm tra đơn hàng hiện tại đang trong trạng thái gì, xem lại các đơn hàng trong quá khứ.

3.	Thanh toán giỏ hàng
   
•	Kiểm tra xem sản phẩm trong giỏ hàng có món nào không đủ số lượng hay không, nếu có thì thông báo tới người dùng và cập nhật lại số lượng còn lại. (tránh việc nhiều người mua đồng thời và có người thanh toán trước nên giỏ hàng cập nhật không kịp số lượng)
•	Nếu thỏa mãn, kiểm tra tài khoản người dùng có đủ số dư hay không và thực hiện thanh toán.

•	Tự động xóa các sản phẩm trong giỏ hàng hiện tại sau khi hoàn thành phiên giao dịch.

•	Sau khi thanh toán xong sẽ chuyển sang trạng thái “paid” và được lưu để có thể xem lại

4.	Quy trình giao hàng
   
•	Trong 1 phiên giao dịch, 1 khách hàng sẽ có 1 mã đơn bao gồm những sản phẩm được thanh toán trong giỏ hàng ở phiên giao dịch đó.

•	Sau khi người mua xác nhận đã nhận, đơn sẽ chuyển thành “received”

•	Nếu khách hàng xác nhận hủy trước khi bên cửa hàng “confirmed” thì đơn sẽ chuyển thành “cancel” và tài khoản sẽ được trả lại tiền bằng với số tiền của đơn hàng đó.

