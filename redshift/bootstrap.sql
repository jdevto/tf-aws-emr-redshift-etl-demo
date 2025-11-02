-- Create dim_category table for lookup
CREATE TABLE IF NOT EXISTS public.dim_category (
    id INT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    description VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Delete existing data if any (for idempotency)
DELETE FROM public.dim_category WHERE id IN (1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20);

-- Insert sample categories (20 rows)
INSERT INTO public.dim_category (id, name, description) VALUES
(1, 'Electronics', 'Electronic devices and accessories'),
(2, 'Clothing', 'Apparel and fashion items'),
(3, 'Food & Beverages', 'Food products and drinks'),
(4, 'Home & Garden', 'Home improvement and garden supplies'),
(5, 'Sports & Outdoors', 'Sports equipment and outdoor gear'),
(6, 'Books', 'Books and publications'),
(7, 'Toys & Games', 'Toys and gaming products'),
(8, 'Health & Beauty', 'Health and beauty products'),
(9, 'Automotive', 'Automotive parts and accessories'),
(10, 'Pet Supplies', 'Products for pets'),
(11, 'Office Supplies', 'Office equipment and supplies'),
(12, 'Musical Instruments', 'Musical instruments and equipment'),
(13, 'Jewelry', 'Jewelry and watches'),
(14, 'Baby Products', 'Products for babies'),
(15, 'Tools & Hardware', 'Tools and hardware supplies'),
(16, 'Movies & TV', 'Movies and TV shows'),
(17, 'Software', 'Software and digital products'),
(18, 'Furniture', 'Furniture and home decor'),
(19, 'Travel', 'Travel products and services'),
(20, 'Gift Cards', 'Gift cards and certificates');

-- Grant permissions to admin user (already has access as admin)
GRANT SELECT ON public.dim_category TO PUBLIC;
