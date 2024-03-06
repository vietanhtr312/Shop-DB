	-- 												Xóa Mọi bảng trước
	-- -------------------------------------------------------------------------------------------------
	-- DROP TABLE IF EXISTS  status CASCADE;
	-- DROP TABLE IF EXISTS  staff CASCADE;
	-- DROP TABLE IF EXISTS  order_items CASCADE;
	-- DROP TABLE IF EXISTS  orders CASCADE;
	-- DROP TABLE IF EXISTS  payments CASCADE;
	-- DROP TABLE IF EXISTS  product CASCADE;
	-- DROP TABLE IF EXISTS  discount CASCADE;
	-- DROP TABLE IF EXISTS  category CASCADE;
	-- DROP TABLE IF EXISTS  users CASCADE;
	
	-- DROP TABLE IF EXISTS current_sessions CASCADE;
	-- DROP TABLE IF EXISTS current_order_items CASCADE;


	-- 												Tạo Bảng
	-- -------------------------------------------------------------------------------------------------
	CREATE TABLE users (
		user_id 		SERIAL PRIMARY KEY,
		user_name 		VARCHAR(120) UNIQUE,
		password 		VARCHAR(100),
		first_name 		VARCHAR(60),
		last_name  		VARCHAR(60),
		phone_number 	VARCHAR(15) UNIQUE,
		email			VARCHAR(100),
		address 		VARCHAR(100),
		last_login		DATE,
		registerd_at	DATE,
		profile 		TEXT
	);

	CREATE TABLE payments (
		payment_id		SERIAL PRIMARY KEY,
		user_id			bigint NOT NULL,
		provider		VARCHAR(50) NOT NULL,
		account_num		VARCHAR(50) NOT NULL,
		expiry_date 	DATE NOT NULL,
		
		FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
	);

	CREATE TABLE category (
		category_id 	SERIAL PRIMARY KEY,
		parent_id		bigint DEFAULT NULL,
		title			VARCHAR(150) NOT NULL,
		content			TEXT,
		
		FOREIGN key (parent_id) REFERENCES category(category_id) ON DELETE CASCADE
	);

	CREATE TABLE discount (
		discount_id 	SERIAL PRIMARY KEY,
		name			VARCHAR(100),
		descr			TEXT,
		dis_condition	BIGINT,
		dis_percent		DOUBLE PRECISION,
		active			BOOLEAN,
		create_at 	 	DATE,
		modify_at		Date
	);

	CREATE TABLE product (
		prod_id 		SERIAL PRIMARY KEY,
		category_id		bigint,
		discount_id		bigint,
		title			TEXT,
		descr 			TEXT ,
		quantity		bigint DEFAULT 0,
		price			Money,
		
		FOREIGN KEY (discount_id) REFERENCES discount(discount_id),
		FOREIGN KEY (category_id) REFERENCES category(category_id) ON DELETE CASCADE
	);

	CREATE TABLE status (
		status_id 		bigint PRIMARY KEY,
		status_name		VARCHAR(256) NOT NULL
	);
	
	CREATE TABLE staff (
		staff_id 		bigint,
		user_name 		VARCHAR(200) UNIQUE,
		password 		VARCHAR(200) NOT NULL,
		first_name		VARCHAR(60) NOT NULL,
		last_name		VARCHAR(60) NOT NULL,
		phone_number	VARCHAR(15) UNIQUE,
		
		PRIMARY KEY (staff_id)
	);

	CREATE TABLE orders (
		order_id 		SERIAL PRIMARY KEY,
		user_id			bigint NOT NULL,
		status_id		bigint DEFAULT 1,
		staff_id 		bigint DEFAULT NULL,
		create_at 		Date,
		last_updated_at	Date,
		order_total		Money DEFAULT 0,
		FOREIGN KEY (user_id) REFERENCES users(user_id)	,
		FOREIGN KEY (staff_id) REFERENCES staff(staff_id)
	);

	CREATE TABLE order_items (
		prod_id 		bigint DEFAULT NULL,
		order_id		bigint NOT NULL,
		number			bigint DEFAULT 0,
		total_price		Money DEFAULT 0,
		
		FOREIGN KEY (prod_id) REFERENCES product(prod_id),
		FOREIGN KEY (order_id) REFERENCES orders(order_id)
	);

	ALTER TABLE order_items ADD CONSTRAINT order_items_prod_id_order_id_key UNIQUE (prod_id, order_id);


	-- 															    Kỹ thuật đánh chỉ mực
	-- ---------------------------------------------------------------------------------------------------------------------------------------

	-- chỉ mục cho 2 trường này ở orders dùng để truy vấn mỗi khi muốn lấy đơn hàng của customer ra
	CREATE INDEX idx_orders ON orders USING btree (order_id,user_id);

	CREATE INDEX idx_category_title_parent ON category USING btree (parent_id,title);

	-- Tạo Function để sử dụng cho gin 
	CREATE EXTENSION IF NOT EXISTS pg_trgm;
	CREATE EXTENSION IF NOT EXISTS btree_gin;

	-- Sử dụng để lấy các item trong order nhanh hơn (truy vấn thường xuyên)
	CREATE INDEX idx_order_item ON order_items USING gin (order_id);

	-- Đoạn sau là đánh chỉ mục cho primary key của mỗi bảng bằng hash index để tối ưu
	CREATE INDEX idx_users ON users USING hash (user_id);

	CREATE INDEX idx_payments ON payments USING hash (payment_id);

	CREATE INDEX idx_category ON category USING hash (category_id);

	CREATE INDEX idx_discount ON discount USING hash (discount_id);

	CREATE INDEX idX_product ON	product USING hash (prod_id);

	CREATE INDEX idx_staff ON staff USING hash (staff_id);

	-- 																Thêm dữ liệu cố định
	-- ---------------------------------------------------------------------------------------------------------------------------------------
			
	INSERT INTO status(status_id,status_name) 
	VALUES (1,'unpaid'),
		   (2,'paid'),
		   (3,'confimred'),
		   (4,'received'),
		   (5,'cancel');
		   
	-- 																CÁC FUNCTION

	-- ---------------------------------------------------------------------------------------------------------------------------------------



	-- ----------------------------------------------------------------------------------------------------------------
		--											Chức năng Customer
	-- ----------------------------------------------------------------------------------------------------------------

	--1
	-- -------------------------------
	-- Hàm Register User vào hệ thống
	-- -------------------------------
	DROP FUNCTION IF EXISTS register_user;
	CREATE OR REPLACE FUNCTION register_user(user_name VARCHAR(200), password VARCHAR(100), phone_number VARCHAR(15)) RETURNS void AS $$
	DECLARE
		new_user_id BIGINT;
	BEGIN
		IF EXISTS (SELECT 1 FROM users WHERE users.user_name = $1) THEN
			RAISE EXCEPTION 'User_name đã tồn tại';
		END IF; 
		IF EXISTS (SELECT 1 FROM users WHERE users.phone_number = $3) THEN
			RAISE EXCEPTION 'Phone number đã tồn tại';
		ELSE
			INSERT INTO users (user_name, password, phone_number) VALUES ($1, $2, $3);
			RAISE NOTICE 'Đã tạo thành công user';
		END IF;
	END;
	$$ LANGUAGE plpgsql;

	--2
	-- -------------------
	-- Hàm Login Customer
	-- -------------------
	DROP FUNCTION IF EXISTS login;
	CREATE OR REPLACE FUNCTION login(user_name VARCHAR(200), password VARCHAR(100)) RETURNS void AS $$
	DECLARE 
		id BIGINT;
		last_order_id BIGINT;
	BEGIN
		IF EXISTS (SELECT 1 FROM users WHERE users.user_name = $1 AND users.password = $2) THEN
			
			SELECT users.user_id INTO id FROM users WHERE users.user_name = $1 AND users.password = $2;
			
			-- DROP TABLE IF EXISTS current_sessions;
			PERFORM logout();
			
			-- Tạo bảng tạo thời lưu dữ liệu của phiên người dùng này
			CREATE TEMPORARY TABLE current_sessions (
				id 					bigint,
				role 				VARCHAR(20),
				current_order_id	bigint
			);
			
			-- Lấy order_id cuối cùng 
			SELECT MAX(orders.order_id) INTO last_order_id FROM orders WHERE user_id = id;
			
			-- Nếu chưa có order_id nào thuộc về user_id hiện tại trong order nào thì thêm mới
			IF last_order_id IS NULL THEN
				-- Tạo order mới
				INSERT INTO orders (user_id,status_id,create_at,last_updated_at,order_total) VALUES 
								   (id,1,CURRENT_DATE,CURRENT_DATE,'0');
								   
				SELECT MAX(orders.order_id) INTO last_order_id FROM orders WHERE user_id = id;
				
			END IF;
			
			-- Thêm các dữ liệu cần thiết vào bảng tạm thời
			INSERT INTO  current_sessions(id,role,current_order_id) VALUES (id,'customer',last_order_id);	
			
			RAISE NOTICE 'Đăng nhập thành công';
			
			-- PERFORM create_cart();
			
			-- Nhắc nhở bổ sung thông tin
			IF (SELECT users.last_name FROM users WHERE user_id = id) IS NULL THEN
				RAISE NOTICE 'Yêu cầu quý khách điền đầy đủ thông tin trong profile';
			END IF;
			
			PERFORM create_cart();
		ELSE
			RAISE EXCEPTION 'Đăng nhập thất bại. User không tồn tại';
		END IF;
	END;
	$$ LANGUAGE plpgsql;

	--3
	-- ------------
	-- Xem Profile
	-- ------------
	DROP FUNCTION IF EXISTS profile;
	CREATE OR REPLACE FUNCTION profile()
	RETURNS TABLE (first_name VARCHAR(60), last_name VARCHAR(60), phone_number VARCHAR(15), email VARCHAR(100), address VARCHAR(100), profile TEXT) AS $$
	DECLARE
		id BIGINT;
	BEGIN
		
		-- Kiểm tra xem đã đăng nhập chưa 
		IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'current_sessions') THEN
			RAISE EXCEPTION 'Chưa đăng nhập';
			RETURN;
		END IF;
		
		-- Kiểm tra xem có quyền hạn thêm hay không
		IF (SELECT current_sessions.role FROM current_sessions) NOT LIKE 'customer' THEN
			RAISE EXCEPTION 'Không có quyền sửa thông tin tài khoản';
			RETURN;
		END IF;
		
		SELECT current_sessions.id INTO id FROM current_sessions;

		RETURN QUERY SELECT users.first_name, users.last_name, users.phone_number, users.email, users.address, users.profile FROM users
		WHERE user_id = id;
	END;
	$$ LANGUAGE plpgsql;

	--4
	-- -----------------------------------------------
	-- Thay đổi Profile nếu giá trị đầu vào khác null
	-- -----------------------------------------------
	DROP FUNCTION IF EXISTS profile_change;
	CREATE OR REPLACE FUNCTION profile_change(first_name VARCHAR(60), last_name VARCHAR(60), phone_number VARCHAR(15), email VARCHAR(100), address VARCHAR(100), profile VARCHAR(200))
	RETURNS void AS $$
	DECLARE
		id BIGINT;
	BEGIN
		
		-- Kiểm tra xem đã đăng nhập chưa 
		IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'current_sessions') THEN
			RAISE EXCEPTION 'Chưa đăng nhập';
			RETURN;
		END IF;
		
		-- Kiểm tra xem có quyền hạn thêm hay không
		IF (SELECT current_sessions.role FROM current_sessions) NOT LIKE 'customer' THEN
			RAISE EXCEPTION 'Không có quyền sửa thông tin tài khoản';
			RETURN;
		END IF;

		SELECT current_sessions.id INTO id FROM current_sessions;

		UPDATE users SET first_name = COALESCE($1, users.first_name),
						last_name = COALESCE($2, users.last_name),
						phone_number = COALESCE($3, users.phone_number),
						email = COALESCE($4, users.email),
						address = COALESCE($5, users.address),	
						profile = COALESCE($6, users.profile)
		WHERE user_id = id;
	END;
	$$ LANGUAGE plpgsql;


	--5
	-- ------------------------------
	-- Thêm tài khoản thanh toán 
	-- ------------------------------
	DROP FUNCTION IF EXISTS add_payment;
	CREATE OR REPLACE FUNCTION add_payment(payment_id BIGINT, provider VARCHAR(50), account_num VARCHAR(50), expiry_date Date)
	RETURNS void AS $$
	DECLARE
		id BIGINT;
		_user_id BIGINT;
	BEGIN
		-- Kiểm tra xem đã đăng nhập chưa 
		IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'current_sessions') THEN
			RAISE EXCEPTION 'Chưa đăng nhập';
			RETURN;
		END IF;
		
		-- Kiểm tra xem có quyền hạn thêm hay không
		IF (SELECT current_sessions.role FROM current_sessions) NOT LIKE 'customer' THEN
			RAISE EXCEPTION 'Không có quyền thêm tài khoản thanh toán';
			RETURN;
		END IF;
		
		-- Lấy payment_id lớn nhất + 1 
		SELECT COALESCE(MAX(payments.payment_id), 0) + 1 INTO id FROM payments;
		
		-- Lấy id của user hiện tại
		SELECT current_sessions.id into _user_id FROM current_sessions;
		
		-- Kiểm tra xem có từng tồn tại payments.payment_id nào thỏa mãn payment_id hiện tại		
		IF payment_id IS NULL OR payment_id >= id THEN
			-- Nếu chưa tồn tại payment
			INSERT INTO payments (user_id, provider, account_num, expiry_date) VALUES (_user_id, $2, $3, $4);	
			RAISE NOTICE 'Thêm tài khoản thanh toán thành công';
		ELSE
			-- Nếu đã tồn tại		
			
			-- Nếu không tồn tại payment nào thỏa mãn yêu cầu nào thỏa mãn yêu cầu 
			IF NOT EXISTS (SELECT 1 FROM payments WHERE payments.payment_id = $1 AND payments.user_id = _user_id) THEN
				RAISE EXCEPTION 'ID tài khoản thanh toán sai hoặc không tồn tại';
				RETURN;
			END IF;
		
			UPDATE payments SET provider = COALESCE($2, payments.provider),
								account_num = COALESCE($3, payments.account_num),
								expiry_date = COALESCE($4, payments.expiry_date)
			WHERE payments.payment_id = $1 AND payments.user_id = _user_id;
			RAISE NOTICE 'Sửa thông tin tài khoản thanh toán thành công';
		END IF;
	END;
	$$ LANGUAGE plpgsql;



	--6
	-- ------------------------------
	-- Xem các tài khoản thanh toán  
	-- ------------------------------
	DROP FUNCTION IF EXISTS payment_info;
	CREATE OR REPLACE FUNCTION payment_info()
	RETURNS TABLE (payment_id BIGINT, provider VARCHAR(50), account_num VARCHAR(50), expiry_date Date) AS $$
	DECLARE
		id BIGINT;
		_user_id BIGINT;
	BEGIN
		-- Kiểm tra xem đã đăng nhập chưa 
		IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'current_sessions') THEN
			RAISE EXCEPTION 'Chưa đăng nhập';
			RETURN;
		END IF;
		
		-- Kiểm tra xem có quyền hạn thêm hay không
		IF (SELECT current_sessions.role FROM current_sessions) NOT LIKE 'customer' THEN
			RAISE EXCEPTION 'Không có quyền xem thông tin tài khoản thanh toán';
			RETURN;
		END IF;
		
		-- Lấy id của user hiện tại
		SELECT current_sessions.id into _user_id FROM current_sessions;
		
		RETURN QUERY SELECT payments.payment_id::BIGINT, payments.provider, payments.account_num, payments.expiry_date FROM payments 
		WHERE payments.user_id = _user_id;

	END;
	$$ LANGUAGE plpgsql;
	
	--7
	-- ---------------
	--   Xóa Payment
	-- ---------------
	
	DROP FUNCTION IF EXISTS delete_payment(BIGINT);
	CREATE OR REPLACE FUNCTION delete_payment(pay_id BIGINT) 
	RETURNS void AS $$
	DECLARE
		usr_id BIGINT;
	BEGIN
		-- Kiểm tra xem đã đăng nhập chưa 
		IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'current_sessions') THEN
			RAISE EXCEPTION 'Chưa đăng nhập';
			RETURN;
		END IF;
		
		-- Kiểm tra xem có quyền hạn mua hay không
		IF (SELECT current_sessions.role FROM current_sessions) NOT LIKE 'customer' THEN
			RAISE EXCEPTION 'Không hủy được vì không phải customer';
			RETURN;
		END IF;
		
		SELECT current_sessions.id INTO usr_id FROM current_sessions;
		
		-- Kiểm tra xem payment có tồn tại không
		IF NOT EXISTS (SELECT 1 FROM payments WHERE payments.payment_id = pay_id) THEN
			RAISE EXCEPTION 'Thông tin thanh toán không tồn tại, kiểm tra lại paymnet id';
			RETURN;
		END IF;
		
		DELETE FROM payments WHERE payments.payment_id = pay_id;
		
		RAISE NOTICE 'Đã xóa thành công payment';
	END;
	$$ LANGUAGE plpgsql;


	--8
	-- ----------
	-- 	logout
	-- ----------

	DROP FUNCTION IF EXISTS logout;
	CREATE OR REPLACE FUNCTION logout() RETURNS void AS $$
	DECLARE 
		id BIGINT;
	BEGIN
		-- Kiểm tra xem có tài khoản nào đã đăng nhập không
		IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'current_sessions') THEN
			-- Nếu tài khoản đang đăng nhập là customer
			IF (SELECT role FROM current_sessions) LIKE 'customer' THEN
				-- Lưu thông tin giỏ hàng..
				PERFORM save_cart();
				-- Lưu xong thì xóa
				DROP TABLE IF EXISTS current_order_items;
			END IF;
			
			-- Cuối cùng thì xóa sessions hiện tại
			DROP TABLE IF EXISTS current_sessions;
			RAISE NOTICE 'Đã đăng xuất khỏi tài khoản';
			RETURN;
		END IF;
		
		-- RAISE NOTICE 'Không cần đăng xuất';
	END;
	$$ LANGUAGE plpgsql;
	
	--9
	-- ---------------------------------
	-- Áp dụng mã giảm giá vào sản phẩm
	-- ---------------------------------
	
	DROP FUNCTION IF EXISTS apply_discount;
	CREATE OR REPLACE FUNCTION apply_discount(num BIGINT, pri MONEY, dis_id BIGINT) RETURNS Money AS $$
	DECLARE 
		dis_per BIGINT 	:= NULL;
		dis_cond BIGINT := NULL;
		active  BOOL   	:= FALSE;
	BEGIN
	
		IF dis_id IS NULL THEN
			RETURN pri*num;
		END IF;
		
		SELECT discount.dis_percent, discount.dis_condition, discount.active INTO dis_per, dis_cond, active FROM discount WHERE discount.discount_id = dis_id;
		
		IF active IS FALSE OR dis_per IS NULL OR dis_cond IS NULL THEN
			RAISE NOTICE 'không có mã hoặc mã không còn dùng được';
			RETURN pri*num;
		END IF;
			
		RETURN (num - num % dis_cond)*pri*(100-dis_per)/100 + (num % dis_cond)*pri;
	END;	
	$$ LANGUAGE plpgsql;
	
	-- 25 (N)  =  (N/condition)*price*(100-5)%  + (N%condition)*price
	
	
	--10
	-- ---------------------------------------------------
	-- Tạo giỏ hàng của customer ở phiên làm việc hiện tại
	-- ---------------------------------------------------
	DROP FUNCTION IF EXISTS create_cart;
	CREATE OR REPLACE FUNCTION create_cart() RETURNS void AS $$
	DECLARE 
		id BIGINT;
	BEGIN
		-- Kiểm tra xem đã đăng nhập chưa 
		IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'current_sessions') THEN
			RAISE EXCEPTION 'Chưa đăng nhập';
			RETURN;
		END IF;
		
		-- Kiểm tra xem có quyền hạn hay không
		IF (SELECT current_sessions.role FROM current_sessions) NOT LIKE 'customer' THEN
			RAISE EXCEPTION 'Không tạo được giỏ hàng vì không phải customer';
			RETURN;
		END IF;
		
		DROP TABLE IF EXISTS current_order_items;
		
		CREATE TEMPORARY TABLE current_order_items (
			prod_id 	BIGINT UNIQUE, 
			number 		BIGINT,
			total_price	Money
		);
		
		SELECT current_sessions.current_order_id INTO id FROM current_sessions; 
		
		INSERT INTO current_order_items(prod_id,number,total_price)  	
			SELECT prod_id,number,total_price FROM order_items 
			WHERE order_items.order_id = id AND order_items.number > 0;
		
		RAISE NOTICE 'Đã tạo cart với order_id = %',id;	
	END;
	$$ LANGUAGE plpgsql;
	
	
	--11
	-- ---------------------------
	-- 	Xem giỏ hàng hiện tại có 
	-- ---------------------------
	DROP FUNCTION IF EXISTS view_cart;
	CREATE OR REPLACE FUNCTION view_cart() RETURNS TABLE (prod_id BIGINT,title TEXT, number BIGINT, total_price MONEY) AS $$
	DECLARE 
		id BIGINT;
	BEGIN
		-- Kiểm tra xem đã đăng nhập chưa 
		IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'current_sessions') THEN
			RAISE EXCEPTION 'Chưa đăng nhập';
			RETURN;
		END IF;
		
		-- Kiểm tra xem có quyền hạn hay không
		IF (SELECT current_sessions.role FROM current_sessions) NOT LIKE 'customer' THEN
			RAISE EXCEPTION 'Không xem được giỏ hàng vì không phải customer';
			RETURN;
		END IF;
		
		RETURN QUERY SELECT current_order_items.prod_id, product.title, current_order_items.number, current_order_items.total_price FROM current_order_items 
		JOIN product ON product.prod_id = current_order_items.prod_id;
	END;
	$$ LANGUAGE plpgsql;

	
	--12
	-- ---------------------
	-- Thêm đồ vào giỏ hàng
	-- ---------------------
	DROP FUNCTION IF EXISTS add_cart;
	CREATE OR REPLACE FUNCTION add_cart(id BIGINT, number BIGINT) RETURNS void AS $$
	DECLARE 
		quan 		BIGINT := 0;
		pri			Money  := 0;
		numInCart 	BIGINT := 0;
		dis_id 		BIGINT := null;
	BEGIN
		-- Kiểm tra xem đã đăng nhập chưa 
		IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'current_sessions') THEN
			RAISE EXCEPTION 'Chưa đăng nhập';
			RETURN;
		END IF;
		
		-- Kiểm tra xem có quyền hạn hay không
		IF (SELECT current_sessions.role FROM current_sessions) NOT LIKE 'customer' THEN
			RAISE EXCEPTION 'Không có quyền thêm đồ vào giỏ hàng vì không phải customer';
			RETURN;
		END IF;
		
		-- Nếu number = 0 thì câu lệnh vô nghĩa
		IF number = 0 THEN 
			RAISE EXCEPTION 'Câu lệnh không có ý nghĩa khi thêm 0 vật phẩm vào';
		END IF;
		
		-- Lưu giá trị quan,pri,numInCart trước 
		SELECT product.quantity,product.price INTO quan,pri FROM product WHERE product.prod_id = id;
		SELECT current_order_items.number INTO numInCart FROM current_order_items WHERE current_order_items.prod_id = id;
		
		-- Nếu không tồn tại sản phẩm thì mặc định là 0
		IF numInCart IS NULL OR numInCart < 0 THEN 
			numInCart := 0;
		END IF;
		
		-- Nếu số lượng trừ đi lớn hơn số lượng có trong giỏ thì đặt lại số lượng trừ đi thành số lượng có trong giỏ
		IF number + numInCart < 0 THEN 
			number := -numInCart;
		END IF;

		-- Xem xét số lượng hàng chỉ được thực hiện khi number>0 tức là đang thêm sản phẩm
		IF number > 0 THEN
			IF quan < number + numInCart THEN
				IF quan-numInCart <= 0 THEN
					RAISE EXCEPTION 'Không còn hàng';
				ELSE
					RAISE EXCEPTION 'Số lượng không đủ, vui lòng nhập số lượng nhỏ hơn %', quan-numInCart;
				END IF;
				RETURN;
			END IF;
		END IF;

		IF number + numInCart > 0 THEN
			-- Nếu đang đang còn sản phẩm trong giỏ
			
			-- Lấy mã giảm của sản phẩm
			SELECT discount_id INTO dis_id FROM product WHERE product.prod_id = id;
			
			-- Thêm hoặc update sản phẩm vào giỏ hàng
			INSERT INTO current_order_items(prod_id,number,total_price) 
				SELECT id, number, apply_discount(number,pri,dis_id)
			ON CONFLICT (prod_id)
				DO UPDATE SET number = current_order_items.number + EXCLUDED.number,
							  --total_price = (current_order_items.number + EXCLUDED.number)*pri;
							  total_price = apply_discount(current_order_items.number + EXCLUDED.number, pri, dis_id);
							  
		ELSE
			-- Nếu không còn sản phẩm nào
			DELETE FROM current_order_items WHERE current_order_items.prod_id = id;
		END IF;
							
		IF number > 0 THEN 
			RAISE NOTICE 'Đã thêm thành công % sản phẩm vào giỏ hàng',number;
		ELSE
			IF number + numInCart <= 0 THEN
				RAISE NOTICE 'Đã xóa sản phẩm khỏi giỏ hàng';
			ELSE
				RAISE NOTICE 'Đã xóa % sản phẩm ra khỏi giỏ hàng',number;
			END IF;
		END IF;
		
	END;
	$$ LANGUAGE plpgsql;


	--13
	-- --------------
	-- Lưu giỏ hàng 
	-- --------------
	DROP FUNCTION IF EXISTS save_cart;
	CREATE OR REPLACE FUNCTION save_cart() RETURNS void AS $$
	DECLARE 
		id BIGINT;
	BEGIN
		-- Kiểm tra xem đã đăng nhập chưa 
		IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'current_sessions') THEN
			RAISE EXCEPTION 'Chưa đăng nhập';
			RETURN;
		END IF;
		
		-- Kiểm tra xem có quyền hạn thêm hay không
		IF (SELECT current_sessions.role FROM current_sessions) NOT LIKE 'customer' THEN
			RAISE EXCEPTION 'Không lưu được giỏ hàng vì không phải customer';
			RETURN;
		END IF;
		
		SELECT current_sessions.current_order_id INTO id FROM current_sessions;
		
		IF id IS NULL THEN 
			RAISE EXCEPTION 'Lỗi: id = NULL, xin hãy kiểm tra lại đăng nhập hoặc giá trị nào đó đã tác động sai bảng lưu thông tin tạm thời vì lỗi này rất khó tự xảy ra';
		END IF;
				
		-- Thêm hoặc update các mặt hàng vào order_items để lưu trữ lâu dài
		INSERT INTO order_items(prod_id, order_id, number, total_price) 
			SELECT current_order_items.prod_id, id, current_order_items.number, current_order_items.total_price FROM current_order_items 
				WHERE EXISTS (SELECT 1 FROM product WHERE product.prod_id = current_order_items.prod_id)
		ON CONFLICT (order_id, prod_id)
			DO UPDATE SET number = EXCLUDED.number,
						  total_price = EXCLUDED.total_price;
		
		-- Xóa các mặt hàng không còn trong order_items hiện tại
		DELETE FROM order_items WHERE order_items.order_id = id AND order_items.prod_id NOT IN (SELECT current_order_items.prod_id FROM current_order_items); 
		
		--Xóa các mặt hàng không tồn tại trong hệ thống nữa
		DELETE FROM order_items WHERE 
			NOT EXISTS (SELECT * FROM product WHERE product.prod_id = order_items.prod_id);
						  
		-- Cập nhật tổng đơn hàng vào bảng orders
		UPDATE orders SET order_total =  COALESCE((SELECT SUM(current_order_items.total_price) FROM current_order_items), 0::MONEY)
		WHERE orders.order_id = id;

	END;
	$$ LANGUAGE plpgsql;

	-- 'Dao' 	-> 'Dao Nhật' 		-> 'Dao cao cấp'
	--								-> 'Dao bình dân'
	
	--			-> 'Dao nội địa' 	-> 'Dao cao cấp'
	
	
	
	--14
	-- --------------------------------
	-- Xem các mặt hàng theo danh mục 
	-- --------------------------------
	DROP FUNCTION IF EXISTS view_product;
	CREATE OR REPLACE FUNCTION view_product(BIGINT) 
	RETURNS TABLE (prod_id BIGINT,category_id BIGINT, discount_id BIGINT, title TEXT, descr TEXT, quantity BIGINT,price MONEY) AS $$
	DECLARE
		id  	BIGINT;
		child	BIGINT[] := '{}';
		child1	BIGINT[] := '{}';
	BEGIN
		child := array_append(child,$1);
	
		IF $1 IS NULL THEN
			RETURN QUERY SELECT product.prod_id::BIGINT, 
								product.category_id, 
								product.discount_id, 
								product.title, product.descr, 
								product.quantity, 
								product.price 
			FROM product;
			RETURN;
		END IF;
		
		WHILE array_length(child, 1) > 0 LOOP
		
			RETURN QUERY SELECT product.prod_id::BIGINT, 
								product.category_id, 
								product.discount_id, 
								product.title, product.descr, 
								product.quantity, 
								product.price 
			FROM product WHERE product.category_id = ANY(child);
			
			child1 := ARRAY(SELECT DISTINCT category.category_id FROM category WHERE category.parent_id = ANY(child));
			
			child := child1;
			child1:= '{}';
		END LOOP;
	END;
	$$ LANGUAGE plpgsql;
	
	
	--15
	-- ------------------------------
	-- 	Truy xuất thông tin tín dụng
	-- ------------------------------
	
	DROP FUNCTION IF EXISTS credit_check;
	CREATE OR REPLACE FUNCTION credit_check(pay_id BIGINT) 
	RETURNS MONEY AS $$
	DECLARE
		expiry DATE := NULL;
	BEGIN
		-- Kiểm tra xem đã đăng nhập chưa 
		IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'current_sessions') THEN
			RAISE EXCEPTION 'Chưa đăng nhập';
			RETURN 0::MONEY;
		END IF;
		
		-- Kiểm tra xem có quyền hạn mua hay không
		IF (SELECT current_sessions.role FROM current_sessions) NOT LIKE 'customer' THEN
			RAISE EXCEPTION 'Không mua được giỏ hàng vì không phải customer';
			RETURN 0::MONEY;
		END IF;

		-- REQUEST tới csdl ngân hàng để lấy số tiền trong tài khoản
		RETURN 100000::MONEY;
		
	END;
	$$ LANGUAGE plpgsql;
	
	
	--16
	-- ---------------------
	-- Xem đơn hàng hiện tại
	-- ---------------------
	
	DROP FUNCTION IF EXISTS view_order();
	CREATE OR REPLACE FUNCTION view_order() 
	RETURNS TABLE (order_id BIGINT, status VARCHAR(256), create_at DATE, last_updated_at DATE, order_total MONEY) AS $$
	DECLARE
		user_idx BIGINT;
		order_idx BIGINT;
	BEGIN
		-- Kiểm tra xem đã đăng nhập chưa 
		IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'current_sessions') THEN
			RAISE EXCEPTION 'Chưa đăng nhập';
			RETURN;
		END IF;
		
		-- Kiểm tra xem có quyền hạn thêm hay không
		IF (SELECT current_sessions.role FROM current_sessions) NOT LIKE 'customer' THEN
			RAISE EXCEPTION 'Không xem được đơn hàng vì không phải customer';
			RETURN;
		END IF;
		
		SELECT current_sessions.id, current_sessions.current_order_id INTO user_idx,order_idx FROM current_sessions;
		
		RETURN QUERY SELECT orders.order_id::bigint, status.status_name AS status, orders.create_at, orders.last_updated_at, orders.order_total FROM orders
		JOIN status ON status.status_id = orders.status_id
		WHERE (orders.order_id,orders.user_id) = (order_idx,user_idx);
		
	END;
	$$ LANGUAGE plpgsql;
	
	
	--17
	-- ----------------------------
	--  Xem đơn hàng với id cụ thể
	-- ----------------------------
	
	DROP FUNCTION IF EXISTS view_order(BIGINT);
	CREATE OR REPLACE FUNCTION view_order(ord_id BIGINT) 
	RETURNS TABLE (order_id BIGINT, status VARCHAR(256), create_at DATE, last_updated_at DATE, order_total MONEY) AS $$
	DECLARE
		user_idx BIGINT;
	BEGIN
		-- Kiểm tra xem đã đăng nhập chưa 
		IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'current_sessions') THEN
			RAISE EXCEPTION 'Chưa đăng nhập';
			RETURN;
		END IF;
		
		-- Kiểm tra xem có quyền hạn thêm hay không
		IF (SELECT current_sessions.role FROM current_sessions) NOT LIKE 'customer' THEN
			RAISE EXCEPTION 'Không xem được đơn hàng vì không phải customer';
			RETURN;
		END IF;
		
		-- Kiểm tra xem có phải đơn hàng của người dùng hiện tại không
		IF (SELECT current_sessions.id FROM current_sessions) != (SELECT orders.user_id FROM orders WHERE orders.order_id = ord_id) THEN
			RAISE EXCEPTION 'Không xem được đơn hàng vì không phải đơn hàng của bạn';
			RETURN;
		END IF;
		
		SELECT current_sessions.id INTO user_idx FROM current_sessions;
		
		RETURN QUERY SELECT orders.order_id::bigint, status.status_name AS status, orders.create_at, orders.last_updated_at, orders.order_total FROM orders
		JOIN status ON status.status_id = orders.status_id
		WHERE (orders.order_id,orders.user_id) = (ord_id,user_idx);
		
	END;
	$$ LANGUAGE plpgsql;
	
	
	--18
	-- ---------------------
	-- Xem đơn hàng cụ thể 
	-- ---------------------
	DROP FUNCTION IF EXISTS view_order_details(BIGINT); 
	CREATE OR REPLACE FUNCTION view_order_details(ord_id BIGINT)
	RETURNS TABLE (title TEXT, descr TEXT, price MONEY, number BIGINT, total_price MONEY) AS $$
	BEGIN
		-- Kiểm tra xem đã đăng nhập chưa 
		IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'current_sessions') THEN
			RAISE EXCEPTION 'Chưa đăng nhập';
			RETURN;
		END IF;
		
		-- Kiểm tra xem có quyền hạn xem hay không
		IF (SELECT current_sessions.role FROM current_sessions) NOT LIKE 'customer' THEN
			RAISE EXCEPTION 'Không xem được đơn hàng vì không phải customer';
			RETURN;
		END IF;
		
		-- Kiểm tra xem có phải đơn hàng của người dùng hiện tại không
		IF (SELECT current_sessions.id FROM current_sessions) != (SELECT orders.user_id FROM orders WHERE orders.order_id = ord_id) THEN
			RAISE EXCEPTION 'Không xem được đơn hàng vì không phải đơn hàng của bạn';
			RETURN;
		END IF;
		
		RETURN QUERY SELECT product.title, product.descr, product.price, order_items.number, order_items.total_price FROM order_items
		JOIN orders ON orders.order_id = order_items.order_id
		JOIN product ON product.prod_id = order_items.prod_id
		WHERE orders.order_id = ord_id;	
	END 
	$$ LANGUAGE plpgsql;
	
	
	--19
	-- --------------------
	-- Thanh Toán Giỏ Hàng
	-- --------------------
	DROP FUNCTION IF EXISTS buy_cart;
	CREATE OR REPLACE FUNCTION buy_cart(pay_id BIGINT) 
	RETURNS void AS $$
	DECLARE
		total 	MONEY := NULL;
		ord_id	BIGINT:= NULL;
		usr_id 	BIGINT:= NULL; 
		buy 	BOOLEAN := TRUE;
		temp 	RECORD;
	BEGIN
		-- Kiểm tra xem đã đăng nhập chưa 
		IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'current_sessions') THEN
			RAISE EXCEPTION 'Chưa đăng nhập';
			RETURN;
		END IF;
		
		-- Kiểm tra xem có quyền hạn mua hay không
		IF (SELECT current_sessions.role FROM current_sessions) NOT LIKE 'customer' THEN
			RAISE EXCEPTION 'Không mua được vì không phải customer';
			RETURN;
		END IF;
		
		SELECT current_sessions.id, current_sessions.current_order_id INTO usr_id, ord_id FROM current_sessions;
		
		PERFORM save_cart();
		
		-- Kiểm tra xem có vật phẩm nào bị hết hàng không
		FOR temp IN
			UPDATE order_items
			SET number = LEAST(number, GREATEST(product.quantity, 0))
			FROM product
			WHERE product.prod_id = order_items.prod_id AND product.quantity < order_items.number
			RETURNING product.title
		LOOP
			RAISE NOTICE 'đã sửa đổi số lượng sản phẩm % vì hết hàng, vui lòng xem lại giỏ hàng',temp.title;
			buy := FALSE;
		END LOOP;
		
		IF buy IS FALSE THEN
			RAISE NOTICE 'đã cập nhật số lượng hàng';
			
			PERFORM create_cart();
			
			RETURN;
		END IF;
		
		
		-- Kiểm tra xem có vật phẩm chưa
		IF (SELECT COUNT(*) FROM order_items WHERE order_items.order_id = ord_id) <= 0 THEN
			RAISE EXCEPTION 'Chưa có vật phẩm trong giỏ hàng';
		END IF;
		
		-- Lấy tổng giá trị đơn hàng hiện tại
		SELECT orders.order_total INTO total FROM orders WHERE  orders.order_id = ord_id;
		
		-- Kiểm tra xem có thanh toán được hay không
		IF pay_id IS NULL THEN
		
			-- Tìm lần lượt từng tài khoản thành toán xem có tài khoản thanh toán đủ số dư và khả dụng hay không
			SELECT payment_id INTO pay_id FROM payments 
			JOIN current_sessions ON current_sessions.id = payments.user_id
			WHERE payments.expiry_date >= CURRENT_DATE AND credit_check(payments.payment_id)>=total
			LIMIT 1;
			
			IF pay_id IS NULL THEN
				RAISE EXCEPTION 'Vui lòng kiểm tra lại số dư tài khoản hoặc thêm tài khoản thanh toán mới';
			END IF;
		END IF;
		
		-- ... Truy xuất thẻ tín dụng và thanh toán
		RAISE NOTICE 'Thanh toán thành công!';
		
		-- Đưa đơn hàng vào trạng thái chờ xác nhận và vào bảng Manage
		UPDATE orders SET status_id = 2 WHERE orders.order_id = ord_id;
				
		-- Giảm số lượng các mặt hàng có trong đơn đã mua
		UPDATE product SET quantity = quantity - current_order_items.number
		FROM current_order_items 
		WHERE product.prod_id = current_order_items.prod_id;
		
		-- Tạo Order mới
		INSERT INTO orders (user_id,status_id,create_at,last_updated_at,order_total) VALUES 
						   (usr_id ,1        ,CURRENT_DATE,CURRENT_DATE,'0');
		
		SELECT MAX(orders.order_id) INTO ord_id FROM orders WHERE orders.user_id = usr_id ;
		
		-- Cập nhật id mới cho current_order_id trong bảng current_sessions
		UPDATE current_sessions SET current_order_id = ord_id;
		
		-- Tạo giỏ hàng mới
		PERFORM create_cart();
		
		RAISE NOTICE 'Đã tạo order mới: %',ord_id;
		
	END;
	$$ LANGUAGE plpgsql;
	
	
	
	--20
	-- -------------------------------------
	-- Xem các đơn hàng theo từng trạng thái
	-- -------------------------------------
	
	DROP FUNCTION IF EXISTS view_order_of;
	CREATE OR REPLACE FUNCTION view_order_of(stt VARCHAR(256)) 
	RETURNS TABLE (order_id BIGINT, create_at DATE, last_updated_at DATE, order_total MONEY) AS $$
	DECLARE
		usr_id BIGINT;
	BEGIN
		-- Kiểm tra xem đã đăng nhập chưa 
		IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'current_sessions') THEN
			RAISE EXCEPTION 'Chưa đăng nhập';
			RETURN;
		END IF;
		
		-- Kiểm tra xem có quyền hạn mua hay không
		IF (SELECT current_sessions.role FROM current_sessions) NOT LIKE 'customer' THEN
			RAISE EXCEPTION 'Không mua được vì không phải customer';
			RETURN;
		END IF;
		
		SELECT current_sessions.id INTO usr_id FROM current_sessions;
		
		RETURN QUERY 
			SELECT orders.order_id::BIGINT,orders.create_at,orders.last_updated_at,orders.order_total FROM orders 
			JOIN status ON status.status_id = orders.status_id
			WHERE orders.user_id = usr_id AND status.status_name = stt;
	END;
	$$ LANGUAGE plpgsql;
	
	
	--21
	-- ---------------------------
	-- Hủy đơn hàng chưa xác nhận
	-- ---------------------------
	
	DROP FUNCTION IF EXISTS cancel_order;
	CREATE OR REPLACE FUNCTION cancel_order(ord_id BIGINT) 
	RETURNS void AS $$
	DECLARE
		usr_id BIGINT;
	BEGIN
		-- Kiểm tra xem đã đăng nhập chưa 
		IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'current_sessions') THEN
			RAISE EXCEPTION 'Chưa đăng nhập';
			RETURN;
		END IF;
		
		-- Kiểm tra xem có quyền hạn mua hay không
		IF (SELECT current_sessions.role FROM current_sessions) NOT LIKE 'customer' THEN
			RAISE EXCEPTION 'Không hủy được vì không phải customer';
			RETURN;
		END IF;
		
		SELECT current_sessions.id INTO usr_id FROM current_sessions;
		
		-- Kiểm tra xem đơn hàng có tồn tại không
		IF NOT EXISTS (SELECT 1 FROM orders WHERE (orders.order_id,orders.user_id) = (ord_id,usr_id)) THEN
			RAISE EXCEPTION 'Đơn hàng không tồn tại, kiểm tra lại order id';
			RETURN;
		END IF;
		
		-- Kiểm tra xem đơn hàng có đang ở trạng thái paid không
		IF (SELECT orders.status_id FROM orders WHERE (orders.order_id,orders.user_id) = (ord_id,usr_id)) != 2 THEN
			RAISE EXCEPTION 'Không thể hủy đơn hàng';
			RETURN;
		END IF;
		
		-- Trả lại số lượng các mặt hàng đã mua trong đơn
		UPDATE product SET quantity = quantity + order_items.number
		FROM order_items
		WHERE product.prod_id = order_items.prod_id AND order_items.order_id = ord_id;
		
		-- Nếu có tồn tại thì đặt tại status id = cancel
		UPDATE orders SET status_id = 5 WHERE orders.order_id = ord_id;  
		
		RAISE NOTICE 'Hủy đơn hàng thành công';
		
	END;
	$$ LANGUAGE plpgsql;
	
	
	
	
	--22
	-- ----------------------------------------------------------------
	-- 					 	Xác nhận đã nhận được hàng
	-- ----------------------------------------------------------------
	
	DROP FUNCTION IF EXISTS received_order;
	CREATE OR REPLACE FUNCTION received_order(ord_id BIGINT) 
	RETURNS void AS $$
	DECLARE
		usr_id BIGINT;
	BEGIN
		-- Kiểm tra xem đã đăng nhập chưa 
		IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'current_sessions') THEN
			RAISE EXCEPTION 'Chưa đăng nhập';
			RETURN;
		END IF;
		
		-- Kiểm tra xem có quyền hạn mua hay không
		IF (SELECT current_sessions.role FROM current_sessions) NOT LIKE 'customer' THEN
			RAISE EXCEPTION 'Không hủy được vì không phải customer';
			RETURN;
		END IF;
		
		SELECT current_sessions.id INTO usr_id FROM current_sessions;
		
		-- Kiểm tra xem đơn hàng có tồn tại không
		IF NOT EXISTS (SELECT 1 FROM orders WHERE (orders.order_id,orders.user_id) = (ord_id,usr_id)) THEN
			RAISE EXCEPTION 'Đơn hàng không tồn tại, kiểm tra lại order id';	
			RETURN;
		END IF;
		
		-- Kiểm tra xem đơn hàng có đang ở trạng thái confimred không
		IF (SELECT orders.status_id FROM orders WHERE (orders.order_id,orders.user_id) = (ord_id,usr_id)) != 3 THEN
			RAISE EXCEPTION 'Đơn hàng chưa ở trạng thái xác nhận';
			RETURN;
		END IF;
				
		-- Nếu có tồn tại thì đặt tại status id = 4 (received)
		UPDATE orders SET status_id = 4 WHERE orders.order_id = ord_id;  
		
		RAISE NOTICE 'Nhận đơn hàng thành công';
		
	END;
	$$ LANGUAGE plpgsql;

	-- -------------------------------------------------------------------------------------------------------------------------
	--														Chức năng Staff
	-- -------------------------------------------------------------------------------------------------------------------------
	
	-- (23-34) trừ 25 Cường
	
	--23
	-- ----------------
	-- Hàm login staff
	-- ----------------
	DROP FUNCTION IF EXISTS login_staff;
	CREATE OR REPLACE FUNCTION login_staff(user_name VARCHAR(200), password VARCHAR(100)) RETURNS void AS $$
	DECLARE 
		id BIGINT;
	BEGIN
		IF EXISTS (SELECT 1 FROM staff WHERE staff.user_name = $1 AND staff.password = $2) THEN
			
			SELECT staff.Staff_id into id FROM staff WHERE staff.user_name = $1 AND staff.password = $2;
			
			-- DROP TABLE IF EXISTS current_sessions;
			PERFORM logout();
			
			CREATE TEMPORARY TABLE current_sessions (
				id 		bigint,
				role 	VARCHAR(20)			
			);
			INSERT INTO  current_sessions(id,role) VALUES (id,'staff');	
		
			RAISE NOTICE 'Staff đã vào hệ thống';
		ELSE
			RAISE EXCEPTION 'Tài khoản không tồn tại';
		END IF;
	END;
	$$ LANGUAGE plpgsql;

	--24
	-- --------------------------------------
	-- Hàm thêm một danh mục mặt hàng nào đó
	-- ---------------------------------------
	DROP FUNCTION IF EXISTS add_category;
	CREATE OR REPLACE FUNCTION add_category(category_id Bigint, parent_id BIGINT, title TEXT, content TEXT) 
	RETURNS void AS $$
	DECLARE 
		id BIGINT;
	BEGIN
		-- Kiểm tra xem đã đăng nhập chưa 
		IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'current_sessions') THEN
			RAISE EXCEPTION 'Chưa đăng nhập';
			RETURN;
		END IF;
		
		-- Kiểm tra xem có quyền hạn thêm hay không
		IF (SELECT current_sessions.role FROM current_sessions) NOT LIKE 'staff' THEN
			RAISE EXCEPTION 'Không có quyền thêm danh mục';
			RETURN;
		END IF;
		
		-- Thêm/Sửa danh mục	
		SELECT COALESCE(MAX(category.category_id), 0) + 1 INTO id FROM category;	
		
		IF category_id IS NULL OR category_id >= id THEN
			-- Nếu chưa tồn tại sản phẩm
			INSERT INTO category (parent_id, title, content) VALUES ($2, $3, $4);
			RAISE NOTICE 'Thêm danh mục thành công';
		ELSE
			-- Nếu đã tồn tại
			UPDATE category SET parent_id = COALESCE($2, category.parent_id),
								title = COALESCE($3, category.title),
								content = COALESCE($4, category.content)
			WHERE category.category_id = $1;
			RAISE NOTICE 'Sửa danh mục thành công';
		END IF;
		
	END;
	$$ LANGUAGE plpgsql;


	--25
	-- ---------------------------------
	-- Hàm lấy ID từ 1 list các category
	-- ---------------------------------

	DROP FUNCTION IF EXISTS catid;
	CREATE OR REPLACE FUNCTION catid(VARIADIC arr VARCHAR(150)[]) 
	RETURNS BIGINT AS $$
	DECLARE
		id BIGINT;
		s VARCHAR(150);
	BEGIN
		FOREACH s IN ARRAY $1 LOOP
			IF id is NULL THEN 
				SELECT category.category_id INTO id FROM category 
				WHERE category.title LIKE s;
			ELSE
				SELECT category.category_id INTO id FROM category 
				WHERE category.parent_id = id AND category.title LIKE s;	
			END IF;
		END LOOP;

		IF id IS NOT NULL THEN  
			RETURN id; 
		ELSE 
			RAISE EXCEPTION 'Viết sai tên đề mục hoặc không tồn tại';
		END IF;	
			
	END;
	$$ LANGUAGE plpgsql;
	
	
	--26
	-- -----------------
	-- Xóa đề mục sản phẩm
	-- -----------------
	DROP FUNCTION IF EXISTS delete_category(BIGINT); 
	CREATE OR REPLACE FUNCTION delete_category(cat_id BIGINT)
	RETURNS void AS $$
	DECLARE 
		id BIGINT;
		cat_parent_id BIGINT;
	BEGIN
		-- Kiểm tra xem đã đăng nhập chưa 
		IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'current_sessions') THEN
			RAISE EXCEPTION 'Chưa đăng nhập';
			RETURN;
		END IF;
		
		-- Kiểm tra xem có quyền hạn thêm hay không
		IF (SELECT current_sessions.role FROM current_sessions) NOT LIKE 'staff' THEN
			RAISE EXCEPTION 'Không có quyền xóa đề mục';
			RETURN;
		END IF;
		
		IF NOT EXISTS (SELECT 1 FROM category WHERE category.category_id = cat_id) THEN
			RAISE EXCEPTION 'Không tồn tại đề mục';
		END IF;
		
		--Lấy parent của đề mục hiện tại
		SELECT category.parent_id INTO cat_parent_id FROM category WHERE category.category_id = cat_id;
		
		-- Cập nhật đề mục của product hiện tại thành đề mục parent
		UPDATE product SET category_id = cat_parent_id WHERE product.category_id IN (SELECT category_id FROM view_product(cat_id));
		
		--Xóa đề mục
		DELETE FROM category WHERE category.category_id = cat_id;
		
		RAISE NOTICE 'Xóa đề mục thành công';
	END 
	$$ LANGUAGE plpgsql;
	
	
	--27
	-- -------------------------
	-- Hàm thêm sản phẩm nào đó
	-- -------------------------
	DROP FUNCTION IF EXISTS add_product;
	CREATE OR REPLACE FUNCTION add_product(prod_id BIGINT, category_id BIGINT, discount_id BIGINT, title TEXT, descr TEXT, quantity BIGINT, price Money) 
	RETURNS void AS $$
	DECLARE 
		id BIGINT;
	BEGIN
		-- Kiểm tra xem đã đăng nhập chưa 
		IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'current_sessions') THEN
			RAISE EXCEPTION 'Chưa đăng nhập';
			RETURN;
		END IF;
		
		-- Kiểm tra xem có quyền hạn thêm hay không
		IF (SELECT current_sessions.role FROM current_sessions) NOT LIKE 'staff' THEN
			RAISE EXCEPTION 'Không có quyền thêm sản phẩm';
			RETURN;
		END IF;
		
		-- Thêm/Sửa danh mục	
		SELECT COALESCE(MAX(product.prod_id), 0) + 1 INTO id FROM product;
			
		IF prod_id IS NULL OR prod_id >= id THEN
			-- Nếu chưa tồn tại sản phẩm
			INSERT INTO product(category_id, discount_id, title , descr , quantity , price )
				   VALUES ($2, $3, $4, $5, $6, $7);			   
			RAISE NOTICE 'Thêm sản phẩm thành công';
		ELSE
			-- Nếu đã tồn tại
			UPDATE product SET category_id = COALESCE($2, product.category_id),
								discount_id = COALESCE($3, product.discount_id),
								title = COALESCE($4, product.title),
								descr = COALESCE($5, product.descr),
								-- Cộng thêm số lượng chứ không phải gán số lượng
								--quantity = COALESCE($6, product.quantity),
								quantity = MAX(0::BIGINT,(SELECT product.quantity + COALESCE($6, 0) )),
								price = COALESCE($7, product.price)
			WHERE product.prod_id = $1;
			RAISE NOTICE 'Sửa thông tin sản phẩm thành công';
		END IF;
		
	END;
	$$ LANGUAGE plpgsql;
	
	
	--28
	-- -----------------
	-- Xóa sản phẩm
	-- -----------------
	DROP FUNCTION IF EXISTS delete_product; 
	CREATE OR REPLACE FUNCTION delete_product(pr_id BIGINT)
	RETURNS void AS $$
	DECLARE 
		id BIGINT;
	BEGIN
		-- Kiểm tra xem đã đăng nhập chưa 
		IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'current_sessions') THEN
			RAISE EXCEPTION 'Chưa đăng nhập';
			RETURN;
		END IF;
		
		-- Kiểm tra xem có quyền hạn thêm hay không
		IF (SELECT current_sessions.role FROM current_sessions) NOT LIKE 'staff' THEN
			RAISE EXCEPTION 'Không có quyền xóa sản phẩm';
			RETURN;
		END IF;
		
		IF NOT EXISTS (SELECT 1 FROM product WHERE product.prod_id = pr_id) THEN
			RAISE EXCEPTION 'Không tồn tại sản phẩm';
		END IF;
		
		--Xóa các sản phẩm có prod_id = pr_id trong giỏ hàng hiện tại của tất cả khách hàng
		DELETE FROM order_items 
		WHERE order_id IN (SELECT order_id FROM orders WHERE status = 1);

		
		--Cập nhật thành NULL các sản phẩm có prod_id = pr_id tồn tại trong đơn hàng đã từng mua
		UPDATE order_items SET prod_id = NULL 
							WHERE order_items.prod_id = pr_id;
				
		--Xóa sản phẩm
		DELETE FROM product WHERE product.prod_id = pr_id;
		
		RAISE NOTICE 'Xóa sản phẩm thành công';
	END 
	$$ LANGUAGE plpgsql;


	--29
	-- -----------------
	-- Thêm mã giảm giá
	-- -----------------
	DROP FUNCTION IF EXISTS add_discount; 
	CREATE OR REPLACE FUNCTION add_discount(discount_id BIGINT,name VARCHAR(100), descr TEXT, dis_condition bigint, dis_percent float, active BOOLEAN)
	RETURNS void AS $$
	DECLARE 
		id BIGINT;
	BEGIN
		-- Kiểm tra xem đã đăng nhập chưa 
		IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'current_sessions') THEN
			RAISE EXCEPTION 'Chưa đăng nhập';
			RETURN;
		END IF;
		
		-- Kiểm tra xem có quyền hạn thêm hay không
		IF (SELECT current_sessions.role FROM current_sessions) NOT LIKE 'staff' THEN
			RAISE EXCEPTION 'Không có quyền thêm mã giảm';
			RETURN;
		END IF;
		
		-- Thêm/Sửa danh mục	
		SELECT COALESCE(MAX(discount.discount_id), 0) + 1 INTO id FROM discount;
			
		IF discount_id IS NULL OR discount_id >= id THEN
			-- Nếu chưa tồn tại sản phẩm
			INSERT INTO discount(name, descr, dis_condition, dis_percent , active , create_at , modify_at )
				   VALUES ($2, $3, $4, $5, $6, CURRENT_DATE, CURRENT_DATE);			   
			RAISE NOTICE 'Thêm mã giảm thành công';
		ELSE
			-- Nếu đã tồn tại
			UPDATE discount SET name = COALESCE($2, discount.name),
								descr = COALESCE($3, discount.descr),
								dis_percent = COALESCE($4, discount.dis_condition),
								dis_percent = COALESCE($5, discount.dis_percent),
								active = COALESCE($6, discount.active),
								modify_at = CURRENT_DATE
			WHERE discount.discount_id = $1;
			RAISE NOTICE 'Sửa thông tin mã giảm thành công';
		END IF;
	END 
	$$ LANGUAGE plpgsql;
	
	
	--30
	-- -----------------
	-- Xóa mã giảm giá
	-- -----------------
	DROP FUNCTION IF EXISTS delete_discount; 
	CREATE OR REPLACE FUNCTION delete_discount(dis_id BIGINT)
	RETURNS void AS $$
	DECLARE 
		id BIGINT;
	BEGIN
		-- Kiểm tra xem đã đăng nhập chưa 
		IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'current_sessions') THEN
			RAISE EXCEPTION 'Chưa đăng nhập';
			RETURN;
		END IF;
		
		-- Kiểm tra xem có quyền hạn thêm hay không
		IF (SELECT current_sessions.role FROM current_sessions) NOT LIKE 'staff' THEN
			RAISE EXCEPTION 'Không có quyền xóa mã giảm';
			RETURN;
		END IF;
		
		IF NOT EXISTS (SELECT 1 FROM discount WHERE discount.discount_id = dis_id) THEN
			RAISE EXCEPTION 'Không tồn tại mã giảm giá';
		END IF;
		
		--Xóa các sản phẩm có tồn tại mã giảm này
		UPDATE product SET product.discount_id = NULL WHERE product.discount_id = dis_id;
		
		--Xóa discount
		DELETE FROM discount WHERE discount_id = dis_id;
		
		RAISE NOTICE 'Xóa discount thành công';
	END 
	$$ LANGUAGE plpgsql;
	
	
	--31
	-- --------------------------
	-- 	Xem các đơn cần xác nhận
	-- --------------------------
	DROP FUNCTION IF EXISTS check_order; 
	CREATE OR REPLACE FUNCTION check_order()
	RETURNS TABLE (order_id BIGINT, user_id BIGINT, order_total MONEY, first_name VARCHAR(60),last_name VARCHAR(60),phone_number VARCHAR(15)) AS $$
	BEGIN
		-- Kiểm tra xem đã đăng nhập chưa 
		IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'current_sessions') THEN
			RAISE EXCEPTION 'Chưa đăng nhập';
			RETURN;
		END IF;
		
		-- Kiểm tra xem có quyền hạn thêm hay không
		IF (SELECT current_sessions.role FROM current_sessions) NOT LIKE 'staff' THEN
			RAISE EXCEPTION 'Không có quyền xem các đơn cần xác nhận thêm mã giảm';
			RETURN;
		END IF;
		
		RETURN QUERY SELECT orders.order_id::BIGINT,orders.user_id, orders.order_total, users.first_name, users.last_name, users.phone_number 
		FROM orders
		JOIN users  ON orders.user_id  = users.user_id
		WHERE orders.status_id = 2;
		
	END 
	$$ LANGUAGE plpgsql;
	
	
	--32
	-- -------------------
	-- Xem các đơn cụ thể 
	-- -------------------
	DROP FUNCTION IF EXISTS check_order_details(BIGINT); 
	CREATE OR REPLACE FUNCTION check_order_details(ord_id BIGINT)
	RETURNS TABLE (title TEXT, descr TEXT, price MONEY, number BIGINT, total_price MONEY) AS $$
	BEGIN
		-- Kiểm tra xem đã đăng nhập chưa 
		IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'current_sessions') THEN
			RAISE EXCEPTION 'Chưa đăng nhập';
			RETURN;
		END IF;
		
		-- Kiểm tra xem có quyền hạn thêm hay không
		IF (SELECT current_sessions.role FROM current_sessions) NOT LIKE 'staff' THEN
			RAISE EXCEPTION 'Không có quyền xem các đơn';
			RETURN;
		END IF;
		
		RETURN QUERY SELECT product.title, product.descr, product.price, order_items.number, order_items.total_price FROM order_items
		JOIN orders ON orders.order_id = order_items.order_id
		JOIN product ON product.prod_id = order_items.prod_id
		WHERE orders.order_id = ord_id;	
	END 
	$$ LANGUAGE plpgsql;
	
	--33
	-- -----------------------
	-- 	Xác nhận các đơn hàng
	-- -----------------------
	DROP FUNCTION IF EXISTS confimred_order; 
	CREATE OR REPLACE FUNCTION confimred_order(ord_id BIGINT)
	RETURNS TABLE (order_id BIGINT, user_id BIGINT, order_total MONEY, first_name VARCHAR(60),last_name VARCHAR(60),phone_number VARCHAR(15)) AS $$
	BEGIN
		-- Kiểm tra xem đã đăng nhập chưa 
		IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'current_sessions') THEN
			RAISE EXCEPTION 'Chưa đăng nhập';
			RETURN;
		END IF;
		
		-- Kiểm tra xem có quyền hạn thêm hay không
		IF (SELECT current_sessions.role FROM current_sessions) NOT LIKE 'staff' THEN
			RAISE EXCEPTION 'Không có quyền xem các đơn cần xác nhận thêm mã giảm';
			RETURN;
		END IF;
		
		IF (SELECT orders.status_id FROM orders WHERE orders.order_id = ord_id) >= 3 THEN
			RAISE EXCEPTION 'Đơn hàng đã được xác nhận';
			RETURN;
		END IF ;
		
		-- Đặt trạng thái đơn hàng thành 3 (confimred)
		UPDATE orders SET status_id = 3,
						  staff_id = (SELECT current_sessions.id FROM current_sessions)
					  WHERE orders.order_id = ord_id;
					  
		RAISE NOTICE 'Xác nhận đơn hàng thành công';
		
	END 
	$$ LANGUAGE plpgsql;
	
	
	--34
	-- ----------------------
	-- 	Từ chối các đơn hàng
	-- ----------------------
	
	
	DROP FUNCTION IF EXISTS reject_order; 
	CREATE OR REPLACE FUNCTION reject_order(ord_id BIGINT)
	RETURNS TABLE (order_id BIGINT, user_id BIGINT, order_total MONEY, first_name VARCHAR(60),last_name VARCHAR(60),phone_number VARCHAR(15)) AS $$
	BEGIN
		-- Kiểm tra xem đã đăng nhập chưa 
		IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'current_sessions') THEN
			RAISE EXCEPTION 'Chưa đăng nhập';
			RETURN;
		END IF;
		
		-- Kiểm tra xem có quyền hạn thêm hay không
		IF (SELECT current_sessions.role FROM current_sessions) NOT LIKE 'staff' THEN
			RAISE EXCEPTION 'Không có quyền xem các đơn cần xác nhận thêm mã giảm';
			RETURN;
		END IF;
		
		IF (SELECT orders.status_id FROM orders WHERE orders.order_id = ord_id) != 2 THEN
			RAISE EXCEPTION 'Đơn hàng không ở trạng thái chờ xác nhận';
			RETURN;
		END IF ;
		
		-- Trả lại tiền vào tài khoản...
		
		-- Đặt trạng thái đơn hàng thành 5 (cancel)
		UPDATE orders SET status_id = 5,
						  staff_id = (SELECT current_sessions.id FROM current_sessions)
					WHERE orders.order_id = ord_id;
					  
		-- Trả lại số lượng hàng
		UPDATE product SET quantity = quantity + order_items.number
		FROM order_items
		WHERE product.prod_id = order_items.prod_id AND order_items.order_id = ord_id;
					  
		RAISE NOTICE 'Hủy đơn hàng của khách thành công';
	END 
	$$ LANGUAGE plpgsql;

	-- 											DATA ADDED & TEST FUNCTION 
	-- ------------------------------------------------------------------------------------------------------------------
	
	-- Test 

	-- INSERT INTO staff(staff_id,user_name,password,first_name,last_name,phone_number)
	-- VALUES 	(1,'admin1','123','Ha','Bach','0990'),
	-- 		(2,'admin2','123','Jams','Gothic','0237');

	-- SELECT login_staff('admin1','123');

	-- SELECT add_category(null,null,'Dao','Các loại dao hiện có');
	-- SELECT add_category(null,catid('Dao'),'Dao Nhật Bản','Các loại dao xuất xứ nhật bản');
	-- SELECT add_category(null,catid('Dao'),'Dao Nội Địa','Các loại dao trong nước');
	-- SELECT add_category(null,catid('Dao','Dao Nhật Bản'),'Dao gọt hoa quả','Dao gọt các loại hoa quả');
	-- SELECT add_category(null,catid('Dao','Dao Nội Địa'),'Dao gọt hoa quả','Dao gọt các loại hoa quả');

	-- SELECT add_category(null,null,'Nồi','Các loại nồi');
	-- SELECT add_category(null,catid('Nồi'),'Nồi Đất','Các loại nồi làm bằng đất');
	-- SELECT add_category(null,catid('Nồi','Nồi Đất'),'Nồi Nấu Cá Chuyên Dụng','Loại nồi nấu cá kho tộ chuyên dụng');
	-- SELECT add_category(null,catid('Nồi','Nồi Đất'),'Nồi Nấu Cơm Niêu','Loại nồi đất dùng 1 lần nấu cơm niêu siêu ngon');

	-- SELECT add_category(null,catid('Nồi'),'Nồi Inox','Các loại nồi làm bằng inox');
	-- SELECT add_category(null,catid('Nồi','Nồi Inox'),'Nồi Inox Cao Cấp','Các loại nồi inox bền và đắt tiền');
	-- SELECT add_category(null,catid('Nồi','Nồi Inox'),'Nồi Inox Bình Dân','Loại nồi được ưa chuộng trong mọi hộ dân');

	-- SELECT add_category(null,catid('Nồi'),'Nồi Gang','Các loại nồi làm bằng gang');
	-- SELECT add_category(null,catid('Nồi','Nồi Gang'),'Nồi Gang Cao Cấp','Loại nồi tốt nhất');
	-- SELECT add_category(null,catid('Nồi','Nồi Gang'),'Nồi Gang Bình Dân','Loại nồi giá cả phải chăng');	


	-- SELECT add_product(null,catid('Dao','Dao Nhật Bản'),null,'Dao Japa','Dao của hãng Japa, chất lượng tốt',10,'900');
	-- SELECT add_product(null,catid('Dao','Dao Nhật Bản'),null,'Dao TAJIRO','Dao của hãng TAJIRO, chất lượng rất tốt',15,'100');
	-- SELECT add_product(null,catid('Dao','Dao Nhật Bản'),null,'Dao SHUN','Dao của hãng SHUN, loại dao thái thịt rất bén',20,'500');
	-- SELECT add_product(null,catid('Dao','Dao Nhật Bản','Dao gọt hoa quả'),null,'Dao Kyo','Loại dao cắt hoa quả và lột vỏ các loại quả rất hiệu quả',20,'200');

	-- SELECT add_product(null,catid('Dao','Dao Nội Địa'),null,'Dao Hòa Phát','Chất lượng uy tín của người Việt',10,'120');
	-- SELECT add_product(null,catid('Dao','Dao Nội Địa'),null,'Dao Hoa Sen','Xuất hiện trong mọi căn bếp gia đình',25,'200');
	
	-- SELECT add_product(null,catid('Nồi','Nồi Inox','Nồi Inox Cao Cấp'),null,'Nồi Sakura','Inox 304 đảm bảo cho sức khỏe',10,'1000');
	-- SELECT add_product(null,catid('Nồi','Nồi Inox','Nồi Inox Cao Cấp'),null,'Nồi Hunku','Bền bỉ theo thời gian',15,'900');
	-- SELECT add_product(null,catid('Nồi','Nồi Inox','Nồi Inox Cao Cấp'),null,'Nồi Sunhouse','Đem niềm vui tới mọi nhà',30,'100');
	-- SELECT add_product(null,catid('Nồi','Nồi Inox','Nồi Inox Cao Cấp'),null,'Nồi Kangaroo','Nồi Inox hàng đầu Việt Nam',10,'1000');
	
	-- SELECT add_product(null,catid('Nồi','Nồi Inox','Nồi Inox Bình Dân'),null,'Nồi Sakura Loại 2','Loại nỗi được ưa chuộng',15,'200');
	-- SELECT add_product(null,catid('Nồi','Nồi Inox','Nồi Inox Bình Dân'),null,'Nồi Sakura Loại 3','Loại nồi thông dụng',15,'100');
	-- SELECT add_product(null,catid('Nồi','Nồi Inox','Nồi Inox Bình Dân'),null,'Nồi Sunhouse Loại 2','Loại nồi xuất hiện nhiều trong các gia đình',20,'300');
	-- SELECT add_product(null,catid('Nồi','Nồi Inox','Nồi Inox Bình Dân'),null,'Nồi Sunhouse Loại 3','Loại nồi xuất hiện nhiều trong các gia đình',20,'250');
	
	-- SELECT add_product(null,catid('Nồi','Nồi Đất','Nồi Nấu Cá Chuyên Dụng'),null,'Nồi Bát Tràng','Nấu cá kho tuyệt vời',20,'250');
	-- SELECT add_product(null,catid('Nồi','Nồi Đất','Nồi Nấu Cá Chuyên Dụng'),null,'Nồi làng Vũ Đại','Nấu cá kho rất ngon',20,'200');
	-- SELECT add_product(null,catid('Nồi','Nồi Đất','Nồi Nấu Cơm Niêu'),null,'Nồi Bát Tràng (dùng 1 lần)','Nấu cơm niêu rất ngon',30,'70');
	-- SELECT add_product(null,catid('Nồi','Nồi Đất','Nồi Nấu Cơm Niêu'),null,'Nồi làng gốm xưa','Nấu cơm niêu giòn và ngon',30,'50');
	
	-- SELECT add_discount(null,'test','test mã giảm',10,5,TRUE);

	-- SELECT register_user('Bakku','123','0990');
	-- SELECT register_user('QN','123','0123');

	-- SELECT login('Bakku','123');
	
	-- SELECT add_payment(null,'VNN','1231','2027-4-6');
	
	-- select add_cart(1,3);
	-- select add_cart(2,2);
	-- select buy_cart(null);
	
	-- SELECT login('QN','123');

	-- SELECT add_payment(null,'BN','13331','2024-4-6');
	
	-- SELECT add_cart(1,2);
	-- SELECT add_Cart(2,3);
	-- SELECT buy_cart(null);
	
	-- SELECT login_staff('admin1','123');
	-- select * from check_order();
